import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:welwi/models/calendar_event.dart';
import 'package:welwi/providers/calendar_provider.dart';
import 'package:welwi/providers/notes_provider.dart';
import 'package:welwi/screens/sighted_data_screen.dart';
import 'package:welwi/services/pcm_audio_player.dart';
import 'package:welwi/services/welwi_cloud_voice_client.dart';
import 'package:welwi/theme/app_theme.dart';

/// The app's single always-on companion: opens straight into a live session
/// with Gemini (gemini-3.1-flash-live-preview) — mic audio (PCM16 16kHz)
/// streams continuously and Gemini's own synthesized voice (real PCM audio,
/// not device TTS) streams back. The camera stays off by default (privacy,
/// battery, and most requests — notes, calendar — need no camera at all);
/// the agent itself turns it on via the `enable_camera` tool the moment the
/// user asks for visual help, and off again via `disable_camera` once done.
/// No taps, no menus: opening the app is the entire interaction.
class CloudVoiceScreen extends StatefulWidget {
  const CloudVoiceScreen({super.key});

  @override
  State<CloudVoiceScreen> createState() => _CloudVoiceScreenState();
}

class _CloudVoiceScreenState extends State<CloudVoiceScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final AudioRecorder _recorder = AudioRecorder();
  WelwiCloudVoiceClient? _voiceClient;
  final PcmAudioPlayer _audioPlayer = PcmAudioPlayer();

  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<LiveEvent>? _eventSub;
  Timer? _frameTimer;
  bool _sendingFrame = false;

  bool _isLive = false;
  bool _isConnecting = false;
  String _status = 'Starting...';

  Map<String, dynamic>? _pendingNote;
  Map<String, dynamic>? _pendingEvent;

  Timer? _reminderTimer;
  final Set<String> _announcedEventIds = {};

  bool _isSpeaking = false;
  Timer? _speakingResetTimer;
  final List<_ActionToast> _toasts = [];

  bool _cameraEnabled = false;
  bool _cameraBusy = false;

  int _tapCount = 0;
  Timer? _tapResetTimer;

  // Guards against two overlapping live sessions ever coexisting — observed
  // as the agent answering one utterance two or three times. The app's
  // lifecycle callback can fire _startLive/_stopLive in quick, overlapping
  // succession (rapid background/foreground flicker, or a natural session
  // end racing a lifecycle pause), and each is async with several awaited
  // steps; without this, a stale in-flight _startLive from an earlier call
  // could finish setting up a second WelwiCloudVoiceClient + recorder after
  // a newer one already has, both listening to the same mic. Every
  // _startLive captures the generation it started with and bails out after
  // each await if a newer call has since begun.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Zero-interaction entry point: the live session begins the moment the
    // app is open, with no button to find or tap first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLive());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLive && !_isConnecting) {
      _startLive();
    } else if (state == AppLifecycleState.paused) {
      _stopLive();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speakingResetTimer?.cancel();
    _tapResetTimer?.cancel();
    _stopLive();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermissions() async {
    var cam = await Permission.camera.status;
    if (!cam.isGranted) cam = await Permission.camera.request();
    var mic = await Permission.microphone.status;
    if (!mic.isGranted) mic = await Permission.microphone.request();
    return cam.isGranted && mic.isGranted;
  }

  Future<void> _startLive() async {
    if (_isLive || _isConnecting) return;
    final myGen = ++_generation;
    setState(() {
      _isConnecting = true;
      _status = 'Requesting camera & microphone...';
    });

    if (!await _ensurePermissions()) {
      if (myGen != _generation) return;
      setState(() {
        _isConnecting = false;
        _status = 'Camera and microphone access is needed. Please allow it in Settings.';
      });
      return;
    }
    if (myGen != _generation) return;

    try {
      setState(() => _status = 'Connecting...');
      final client = WelwiCloudVoiceClient();
      await client.connect();
      if (myGen != _generation) {
        // Superseded mid-connect (e.g. the app backgrounded again while
        // this was still negotiating) — close what was just opened instead
        // of leaving it running alongside whatever started after it.
        await client.close();
        return;
      }
      _voiceClient = client;

      _eventSub = _voiceClient!.events.listen(
        _onLiveEvent,
        onError: (e) => log('CloudVoiceScreen: live event stream error: $e'),
        onDone: _onLiveSessionEnded,
      );

      // echoCancel/noiseSuppress + the VOICE_COMMUNICATION audio source are
      // what actually stop the phone from hearing its own speaker output
      // through the mic. Without them, the agent's own voice leaking back
      // into the recording gets sent to Gemini, whose server-side voice
      // detection reads that as the user interrupting — and now that the
      // client correctly reacts to real interruptions (see _onLiveEvent),
      // that false positive cut the agent off mid-sentence on its own audio.
      final micStream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication),
      ));
      if (myGen != _generation) {
        await _recorder.stop();
        return;
      }
      _audioSub = micStream.listen((chunk) => _voiceClient?.sendAudioChunk(chunk));

      _reminderTimer = Timer.periodic(const Duration(seconds: 20), (_) => _checkDueReminders());

      // The real cause of "it keeps disconnecting" during hands-free use:
      // nothing touches the screen during a voice conversation, so Android
      // times it out and locks it, which backgrounds the app and tears the
      // whole session down. Keeping the screen awake while live is the fix.
      unawaited(WakelockPlus.enable());

      if (!mounted || myGen != _generation) return;
      setState(() {
        _isLive = true;
        _isConnecting = false;
        _status = 'Listening';
      });
    } catch (e) {
      log('CloudVoiceScreen: start error: $e');
      if (myGen != _generation) return;
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _status = 'Connection lost — reconnecting...';
      });
      await _stopLive(keepStatus: true);
      // No interaction available to retry manually, so retry on its own.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_isLive && !_isConnecting) _startLive();
      });
    }
  }

  /// Instead of a static system notification doing the talking, when a
  /// scheduled event's time arrives while the live session is open, this
  /// nudges the agent to announce it right now, in its own real voice —
  /// the same "wake_reason: reminder" persona the backend already speaks
  /// with when a session is opened specifically for a reminder.
  void _checkDueReminders() {
    if (!mounted || _voiceClient == null) return;
    final calendarProvider = Provider.of<CalendarProvider>(context, listen: false);
    final now = DateTime.now();
    for (final CalendarEvent event in calendarProvider.events) {
      if (event.time == null || _announcedEventIds.contains(event.id)) continue;
      final start = DateTime(
        event.date.year, event.date.month, event.date.day,
        event.time!.hour, event.time!.minute,
      );
      final secondsSinceStart = now.difference(start).inSeconds;
      if (secondsSinceStart >= 0 && secondsSinceStart <= 90) {
        _announcedEventIds.add(event.id);
        _voiceClient?.sendText(
          '[SYSTEM: It is now time for the reminder "${event.title}"'
          '${event.description.isNotEmpty ? " — ${event.description}" : ""}. '
          'Proactively let the user know right now, warmly and briefly, in your own words.]',
        );
      }
    }
  }

  /// Cloud Run and the underlying Gemini Live session both have a finite
  /// connection lifetime — this fires whenever the live connection ends,
  /// whether from an error, an idle timeout, or the session's own natural
  /// duration limit. There's no button for the user to reconnect with (zero
  /// taps, by design), so the app quietly opens a fresh session on its own
  /// — this is what actually fixes "it only answers once and then stops."
  Future<void> _onLiveSessionEnded() async {
    log('CloudVoiceScreen: live session ended, reconnecting...');
    if (!mounted || !_isLive) return;
    await _stopLive(keepStatus: true);
    if (!mounted) return;
    setState(() => _status = 'Reconnecting...');
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted && !_isLive && !_isConnecting) _startLive();
  }

  /// Called when the agent calls its `enable_camera` tool — lazily opens
  /// the camera hardware (not touched at all until now) and starts the
  /// ~1fps frame-send loop proven against the deployed agent.
  Future<void> _enableCamera() async {
    if (_cameraEnabled || _cameraBusy) return;
    _cameraBusy = true;
    try {
      var cam = await Permission.camera.status;
      if (!cam.isGranted) cam = await Permission.camera.request();
      if (!cam.isGranted) return;

      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();
      await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      _frameTimer = Timer.periodic(const Duration(seconds: 1), (_) => _captureAndSendFrame());
      if (mounted) {
        setState(() {
          _cameraEnabled = true;
          _status = 'Listening and watching';
        });
      }
    } catch (e) {
      log('CloudVoiceScreen: enable camera error: $e');
    } finally {
      _cameraBusy = false;
    }
  }

  Future<void> _disableCamera() async {
    if (!_cameraEnabled) return;
    _frameTimer?.cancel();
    _frameTimer = null;
    await _cameraController?.dispose();
    _cameraController = null;
    if (mounted) {
      setState(() {
        _cameraEnabled = false;
        if (_isLive) _status = 'Listening';
      });
    }
  }

  Future<void> _captureAndSendFrame() async {
    if (_sendingFrame) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    _sendingFrame = true;
    try {
      final XFile picture = await controller.takePicture();
      final bytes = await picture.readAsBytes();
      _voiceClient?.sendVideoFrame(bytes);
      try {
        final f = File(picture.path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    } catch (e) {
      log('CloudVoiceScreen: frame capture error: $e');
    } finally {
      _sendingFrame = false;
    }
  }

  void _onLiveEvent(LiveEvent event) {
    if (event.interrupted) {
      // The user talked over the agent — the server keeps the interrupted
      // turn's audio flowing right up until this event, so without this the
      // old answer's tail plays under the new one and sounds like the agent
      // repeating itself. Cut it immediately, don't wait for it to finish.
      _audioPlayer.stop();
    }

    if (event.audioChunk != null) {
      _audioPlayer.enqueue(event.audioChunk!, event.audioSampleRate);
      if (!_isSpeaking && mounted) setState(() => _isSpeaking = true);
      _speakingResetTimer?.cancel();
      _speakingResetTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _isSpeaking = false);
      });
    }

    for (final fc in event.functionCalls) {
      final name = fc['name'] as String?;
      final args = fc['args'] as Map<String, dynamic>? ?? {};
      if (name == 'propose_note') _pendingNote = args;
      if (name == 'propose_calendar_event') _pendingEvent = args;
      if (name == 'enable_camera') _enableCamera();
      if (name == 'disable_camera') _disableCamera();
    }

    for (final fr in event.functionResponses) {
      final name = fr['name'] as String?;
      final response = fr['response'] as Map<String, dynamic>? ?? {};
      final status = response['status'] as String?;
      if (name == 'save_note' && status == 'saved' && _pendingNote != null) {
        _applyNoteLocally(_pendingNote!, response['note_id'] as String?);
        _pendingNote = null;
      } else if (name == 'discard_note') {
        _pendingNote = null;
      } else if (name == 'create_calendar_event' && status == 'created' && _pendingEvent != null) {
        _applyEventLocally(_pendingEvent!, response['event_id'] as String?);
        _pendingEvent = null;
      } else if (name == 'discard_calendar_event') {
        _pendingEvent = null;
      } else if (name == 'update_note' && status == 'updated') {
        _applyNoteUpdateLocally(response);
      } else if (name == 'delete_note' && status == 'deleted') {
        _applyNoteDeleteLocally(response);
      } else if (name == 'update_calendar_event' && status == 'updated') {
        _applyEventUpdateLocally(response);
      } else if (name == 'delete_calendar_event' && status == 'deleted') {
        _applyEventDeleteLocally(response);
      }
    }
  }

  void _applyNoteLocally(Map<String, dynamic> args, String? noteId) {
    if (!mounted) return;
    final title = args['title'] as String? ?? 'Note';
    // Using the backend's real Firestore id (not a fresh local uuid) as the
    // local id is what lets a later update_note/delete_note call — which
    // only knows that same Firestore id — find and change this same entry.
    Provider.of<NotesProvider>(context, listen: false).createNote(
      id: noteId,
      title: title,
      content: args['content'] as String? ?? '',
    );
    HapticFeedback.mediumImpact();
    _showToast(_ActionToast(icon: Icons.note_add_rounded, label: 'Note saved', title: title));
  }

  void _applyEventLocally(Map<String, dynamic> args, String? eventId) {
    if (!mounted) return;
    final title = args['title'] as String? ?? 'Event';
    try {
      final start = DateTime.parse(args['start_iso'] as String);
      Provider.of<CalendarProvider>(context, listen: false).createEventFromWelwi(
        id: eventId,
        title: title,
        date: DateTime(start.year, start.month, start.day),
        time: TimeOfDay(hour: start.hour, minute: start.minute),
        description: args['description'] as String? ?? '',
      );
      HapticFeedback.mediumImpact();
      _showToast(_ActionToast(icon: Icons.event_available_rounded, label: 'Event added', title: title));
    } catch (e) {
      log('CloudVoiceScreen: could not parse event start_iso: $e');
    }
  }

  void _applyNoteUpdateLocally(Map<String, dynamic> response) {
    if (!mounted) return;
    final id = response['note_id'] as String?;
    final updates = response['updates'] as Map<String, dynamic>? ?? {};
    if (id == null) return;
    Provider.of<NotesProvider>(context, listen: false).updateNote(
      id,
      title: updates['title'] as String?,
      content: updates['content'] as String?,
    );
    HapticFeedback.mediumImpact();
    _showToast(_ActionToast(icon: Icons.edit_note_rounded, label: 'Note updated', title: updates['title'] as String? ?? ''));
  }

  void _applyNoteDeleteLocally(Map<String, dynamic> response) {
    if (!mounted) return;
    final id = response['note_id'] as String?;
    if (id == null) return;
    Provider.of<NotesProvider>(context, listen: false).deleteNote(id);
    HapticFeedback.mediumImpact();
    _showToast(_ActionToast(icon: Icons.delete_rounded, label: 'Note deleted', title: ''));
  }

  void _applyEventUpdateLocally(Map<String, dynamic> response) {
    if (!mounted) return;
    final id = response['event_id'] as String?;
    final updates = response['updates'] as Map<String, dynamic>? ?? {};
    if (id == null) return;
    DateTime? date;
    TimeOfDay? time;
    final startIso = updates['start_iso'] as String?;
    if (startIso != null) {
      try {
        final start = DateTime.parse(startIso);
        date = DateTime(start.year, start.month, start.day);
        time = TimeOfDay(hour: start.hour, minute: start.minute);
      } catch (_) {}
    }
    Provider.of<CalendarProvider>(context, listen: false).updateEvent(
      id,
      title: updates['title'] as String?,
      date: date,
      time: time,
      description: updates['description'] as String?,
    );
    HapticFeedback.mediumImpact();
    _showToast(_ActionToast(icon: Icons.edit_calendar_rounded, label: 'Event updated', title: updates['title'] as String? ?? ''));
  }

  void _applyEventDeleteLocally(Map<String, dynamic> response) {
    if (!mounted) return;
    final id = response['event_id'] as String?;
    if (id == null) return;
    Provider.of<CalendarProvider>(context, listen: false).deleteEvent(id);
    HapticFeedback.mediumImpact();
    _showToast(_ActionToast(icon: Icons.event_busy_rounded, label: 'Event deleted', title: ''));
  }

  /// Visible proof-of-action right on the one screen the app has — there's
  /// no notes/calendar list to navigate to and confirm against, by design
  /// (zero taps), so the confirmation has to surface here instead.
  void _showToast(_ActionToast toast) {
    if (!mounted) return;
    setState(() => _toasts.add(toast));
    Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _toasts.remove(toast));
    });
  }

  Future<void> _stopLive({bool keepStatus = false}) async {
    _generation++;
    _frameTimer?.cancel();
    _frameTimer = null;
    _reminderTimer?.cancel();
    _reminderTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _eventSub?.cancel();
    _eventSub = null;
    await _voiceClient?.close();
    _voiceClient = null;
    await _cameraController?.dispose();
    _cameraController = null;
    await _audioPlayer.stop();
    unawaited(WakelockPlus.disable());
    if (mounted) {
      setState(() {
        _isLive = false;
        _isConnecting = false;
        _isSpeaking = false;
        _cameraEnabled = false;
        if (!keepStatus) _status = 'Starting...';
      });
    }
  }

  /// Five quick taps anywhere opens the sighted view (Notes/Calendar lists)
  /// — for a companion glancing over, or a judge who wants to see the data
  /// behind the voice, without that ever being required to use the app.
  void _handleTap() {
    _tapResetTimer?.cancel();
    _tapCount++;
    if (_tapCount >= 5) {
      _tapCount = 0;
      HapticFeedback.heavyImpact();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SightedDataScreen()));
      return;
    }
    _tapResetTimer = Timer(const Duration(milliseconds: 600), () => _tapCount = 0);
  }

  _OrbState get _orbState {
    if (_isSpeaking) return _OrbState.speaking;
    if (_isLive) return _OrbState.listening;
    return _OrbState.connecting;
  }

  @override
  Widget build(BuildContext context) {
    final cameraReady = _cameraEnabled && _cameraController != null && _cameraController!.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleTap,
        child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: cameraReady
                ? CameraPreview(_cameraController!, key: const ValueKey('camera'))
                : Container(
                    key: const ValueKey('voice-only'),
                    decoration: const BoxDecoration(gradient: AppColors.surfaceGradient),
                  ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.2)),
          // Bottom scrim so the glass panel stays legible over any scene.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 340,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.85)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                if (_toasts.isNotEmpty) _buildToasts(),
                const Spacer(),
                _PresenceOrb(state: _orbState),
                const SizedBox(height: 18),
                Text(
                  _status,
                  style: TextStyle(
                    color: _isLive ? AppColors.dopamineMid : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Semantics(
      liveRegion: true,
      label: 'Welwi companion. $_status',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => AppColors.dopamineGradientHorizontal.createShader(bounds),
              child: const Text(
                'Welwi',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToasts() {
    return Column(
      children: _toasts
          .map((t) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppColors.dopamineGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: AppColors.dopamineStart.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(t.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                          Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

}

class _ActionToast {
  final IconData icon;
  final String label;
  final String title;
  _ActionToast({required this.icon, required this.label, required this.title});
}

enum _OrbState { connecting, listening, speaking }

/// The app's single visual focal point — no button, nothing to tap, just a
/// living indicator of Welwi's state: dim pulse while connecting, a slow
/// brand-gradient breathing glow while listening, and a faster, brighter
/// glow the instant real Gemini audio is actually playing.
class _PresenceOrb extends StatefulWidget {
  final _OrbState state;
  const _PresenceOrb({required this.state});

  @override
  State<_PresenceOrb> createState() => _PresenceOrbState();
}

class _PresenceOrbState extends State<_PresenceOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSpeaking = widget.state == _OrbState.speaking;
    final isListening = widget.state == _OrbState.listening;
    final duration = isSpeaking ? const Duration(milliseconds: 420) : const Duration(milliseconds: 1400);
    if (_controller.duration != duration) {
      _controller.duration = duration;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final baseSize = isSpeaking ? 118.0 : (isListening ? 108.0 : 96.0);
        final size = baseSize + (isSpeaking ? 14 : 8) * t;
        final glowAlpha = isListening || isSpeaking ? 0.35 + 0.35 * t : 0.15;

        return Semantics(
          label: isSpeaking ? 'Welwi is speaking' : (isListening ? 'Welwi is listening' : 'Connecting'),
          child: SizedBox(
            width: 150,
            height: 150,
            child: Center(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: widget.state == _OrbState.connecting
                      ? null
                      : AppColors.dopamineGradient,
                  color: widget.state == _OrbState.connecting ? Colors.white24 : null,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.dopamineStart.withValues(alpha: glowAlpha),
                      blurRadius: isSpeaking ? 40 : 26,
                      spreadRadius: isSpeaking ? 10 : 4,
                    ),
                  ],
                ),
                child: Center(
                  child: widget.state == _OrbState.connecting
                      ? const SizedBox(
                          width: 26, height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
                        )
                      : Icon(
                          isSpeaking ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
