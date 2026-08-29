import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:welwi/models/cloud_event.dart';
import 'package:welwi/services/cloud_config.dart';

/// REST client for the deployed ADK text/vision agent on Cloud Run
/// (welwi_agent: orchestrator + note_agent + calendar_agent + iris_agent).
///
/// One instance = one ADK session. Create a fresh instance per chat sheet
/// so the multi-turn propose->confirm flow (e.g. propose_note then "yes")
/// stays in the same session server-side.
class WelwiCloudClient {
  final String userId;
  final String sessionId;
  bool _sessionReady = false;

  WelwiCloudClient({String? userId, String? sessionId})
      : userId = userId ?? 'flutter_user',
        sessionId = sessionId ?? const Uuid().v4();

  Uri _uri(String path) => Uri.parse('${CloudConfig.textAgentBaseUrl}$path');

  Future<void> ensureSession() async {
    if (_sessionReady) return;
    final uri = _uri(
        '/apps/${CloudConfig.textAppName}/users/$userId/sessions/$sessionId');
    final res = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: '{}')
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception(
          'Failed to create cloud session (${res.statusCode}): ${res.body}');
    }
    _sessionReady = true;
    log('WelwiCloudClient: session ready ($sessionId)');
  }

  /// Sends one user turn (text, optionally with an attached image) and
  /// returns every ADK event produced in response — may span multiple
  /// sub-agents (e.g. orchestrator's transfer_to_agent, then note_agent's
  /// own propose_note call).
  Future<List<CloudEvent>> sendText(
    String text, {
    List<int>? imageBytes,
    String imageMime = 'image/png',
  }) async {
    await ensureSession();

    final parts = <Map<String, dynamic>>[];
    if (imageBytes != null && imageBytes.isNotEmpty) {
      parts.add({
        'inlineData': {'mimeType': imageMime, 'data': base64Encode(imageBytes)}
      });
    }
    parts.add({'text': text});

    final uri = _uri('/run');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'app_name': CloudConfig.textAppName,
            'user_id': userId,
            'session_id': sessionId,
            'new_message': {'role': 'user', 'parts': parts},
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (res.statusCode != 200) {
      throw Exception(
          'Cloud agent request failed (${res.statusCode}): ${res.body}');
    }

    final List<dynamic> events = jsonDecode(res.body);
    return events.map(_parseEvent).toList();
  }

  CloudEvent _parseEvent(dynamic raw) {
    final map = raw as Map<String, dynamic>;
    final author = map['author'] as String? ?? 'agent';
    final content = map['content'] as Map<String, dynamic>? ?? {};
    final parts = (content['parts'] as List<dynamic>?) ?? const [];

    final textBuf = StringBuffer();
    final calls = <CloudFunctionCall>[];
    final responses = <CloudFunctionResponse>[];

    for (final p in parts) {
      final part = p as Map<String, dynamic>;
      final t = part['text'];
      if (t is String && t.isNotEmpty) textBuf.write(t);

      final fc = part['functionCall'] as Map<String, dynamic>?;
      if (fc != null) {
        calls.add(CloudFunctionCall(
          name: fc['name'] as String? ?? '',
          args: Map<String, dynamic>.from(fc['args'] as Map? ?? {}),
        ));
      }

      final fr = part['functionResponse'] as Map<String, dynamic>?;
      if (fr != null) {
        responses.add(CloudFunctionResponse(
          name: fr['name'] as String? ?? '',
          response: Map<String, dynamic>.from(fr['response'] as Map? ?? {}),
        ));
      }
    }

    return CloudEvent(
      author: author,
      text: textBuf.toString(),
      functionCalls: calls,
      functionResponses: responses,
    );
  }
}
