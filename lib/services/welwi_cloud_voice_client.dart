import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:welwi/services/cloud_config.dart';

/// One parsed message from the Live WebSocket — mirrors ADK's Event JSON
/// (camelCase via by_alias=True). A single logical spoken turn from the
/// model usually arrives as several of these (transcript deltas), ending
/// with one where [turnComplete] is true.
class LiveEvent {
  final String author;
  final String text;
  final String outputTranscription;
  /// True when [outputTranscription] is the authoritative complete sentence
  /// for this turn (confirmed against the real deployed agent: partial
  /// deltas arrive with finished=false and must be concatenated for a live
  /// caption, then one final event repeats the FULL sentence with
  /// finished=true — using both would double the text sent to TTS).
  final bool transcriptionFinished;
  final bool turnComplete;
  /// True on the event that ends a turn the user talked over (barge-in).
  /// Confirmed against the real deployed agent: the server keeps sending
  /// audio for the turn that was already in flight even after the user
  /// starts talking again, then marks it with `interrupted` once it stops.
  /// The client must react to this by silencing whatever's currently
  /// playing — otherwise the tail of the interrupted answer keeps sounding
  /// while the new answer starts, which is exactly what sounded like the
  /// agent "answering multiple times".
  final bool interrupted;
  final List<Map<String, dynamic>> functionCalls;
  final List<Map<String, dynamic>> functionResponses;
  /// Raw PCM16 audio spoken by the model, when this event carries one
  /// (mimeType `audio/pcm;rate=NNNNN` — confirmed 24000 Hz mono against the
  /// real deployed agent). This is Gemini's own synthesized voice, not a
  /// device TTS re-reading of the transcript.
  final Uint8List? audioChunk;
  final int audioSampleRate;

  LiveEvent({
    this.author = '',
    this.text = '',
    this.outputTranscription = '',
    this.transcriptionFinished = false,
    this.turnComplete = false,
    this.interrupted = false,
    this.functionCalls = const [],
    this.functionResponses = const [],
    this.audioChunk,
    this.audioSampleRate = 24000,
  });
}

/// WebSocket client for the deployed ADK voice/Live agent on Cloud Run
/// (welwi_voice_agent) — streams mic audio + camera frames to Gemini Live
/// and receives back Gemini's own synthesized voice (raw PCM16 audio),
/// a text transcription of it, and tool calls.
class WelwiCloudVoiceClient {
  final String userId;
  final String sessionId;
  WebSocketChannel? _channel;
  final _controller = StreamController<LiveEvent>.broadcast();

  Stream<LiveEvent> get events => _controller.stream;

  WelwiCloudVoiceClient({String? userId, String? sessionId})
      : userId = userId ?? 'flutter_voice_user',
        sessionId = sessionId ?? const Uuid().v4();

  Future<void> connect() async {
    final httpBase = CloudConfig.voiceAgentWsUrl.replaceFirst('wss://', 'https://');
    final sessionUri = Uri.parse(
      '$httpBase/apps/${CloudConfig.voiceAppName}/users/$userId/sessions/$sessionId',
    );
    final res = await http
        .post(sessionUri, headers: {'Content-Type': 'application/json'}, body: '{}')
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Failed to create voice session (${res.statusCode}): ${res.body}');
    }

    final wsUri = Uri.parse(
      '${CloudConfig.voiceAgentWsUrl}/run_live'
      '?user_id=$userId&session_id=$sessionId&app_name=${CloudConfig.voiceAppName}&modalities=AUDIO',
    );
    _channel = WebSocketChannel.connect(wsUri);
    await _channel!.ready;
    // Cloud Run and the underlying Gemini Live session both have finite
    // connection lifetimes — this WILL close on its own eventually even on
    // a healthy connection, not just on error. Closing `_controller` here
    // (rather than just logging) is what lets the UI layer's `onDone`
    // notice and reconnect automatically instead of silently going quiet
    // after the session's first exchange.
    _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        log('WelwiCloudVoiceClient: WS error: $e');
        if (!_controller.isClosed) _controller.close();
      },
      onDone: () {
        log('WelwiCloudVoiceClient: WS closed');
        if (!_controller.isClosed) _controller.close();
      },
    );
  }

  void _onMessage(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final content = map['content'] as Map<String, dynamic>? ?? {};
      final parts = (content['parts'] as List<dynamic>?) ?? const [];

      final textBuf = StringBuffer();
      final calls = <Map<String, dynamic>>[];
      final responses = <Map<String, dynamic>>[];
      Uint8List? audioChunk;
      int audioSampleRate = 24000;

      for (final p in parts) {
        final part = p as Map<String, dynamic>;
        final t = part['text'];
        if (t is String) textBuf.write(t);

        final fc = part['functionCall'] as Map<String, dynamic>?;
        if (fc != null) {
          calls.add({
            'name': fc['name'],
            'args': Map<String, dynamic>.from(fc['args'] as Map? ?? {}),
          });
        }

        final fr = part['functionResponse'] as Map<String, dynamic>?;
        if (fr != null) {
          responses.add({
            'name': fr['name'],
            'response': Map<String, dynamic>.from(fr['response'] as Map? ?? {}),
          });
        }

        final inline = part['inlineData'] as Map<String, dynamic>?;
        final mimeType = inline?['mimeType'] as String?;
        if (inline != null && mimeType != null && mimeType.startsWith('audio/pcm')) {
          final data = inline['data'] as String?;
          if (data != null && data.isNotEmpty) {
            audioChunk = base64Decode(data);
            final rateMatch = RegExp(r'rate=(\d+)').firstMatch(mimeType);
            if (rateMatch != null) audioSampleRate = int.parse(rateMatch.group(1)!);
          }
        }
      }

      final ot = (map['outputTranscription'] ?? map['output_transcription']) as Map<String, dynamic>?;
      final turnComplete = (map['turnComplete'] ?? map['turn_complete']) == true;
      final interrupted = (map['interrupted'] ?? map['interruption']) == true;

      _controller.add(LiveEvent(
        author: map['author'] as String? ?? '',
        text: textBuf.toString(),
        outputTranscription: ot?['text'] as String? ?? '',
        transcriptionFinished: ot?['finished'] == true,
        turnComplete: turnComplete,
        interrupted: interrupted,
        functionCalls: calls,
        functionResponses: responses,
        audioChunk: audioChunk,
        audioSampleRate: audioSampleRate,
      ));
    } catch (e) {
      log('WelwiCloudVoiceClient: parse error: $e');
    }
  }

  /// Injects a system-authored text turn into the live session — used to
  /// make the agent proactively speak (e.g. a calendar reminder firing)
  /// instead of a static system notification doing the talking.
  void sendText(String text) {
    _channel?.sink.add(jsonEncode({
      'content': {
        'role': 'user',
        'parts': [
          {'text': text}
        ]
      }
    }));
  }

  void sendVideoFrame(List<int> jpegBytes) {
    _channel?.sink.add(jsonEncode({
      'blob': {'mime_type': 'image/jpeg', 'data': base64Encode(jpegBytes)}
    }));
  }

  void sendAudioChunk(List<int> pcm16Bytes) {
    _channel?.sink.add(jsonEncode({
      'blob': {'mime_type': 'audio/pcm;rate=16000', 'data': base64Encode(pcm16Bytes)}
    }));
  }

  Future<void> close() async {
    await _channel?.sink.close();
    if (!_controller.isClosed) await _controller.close();
  }
}
