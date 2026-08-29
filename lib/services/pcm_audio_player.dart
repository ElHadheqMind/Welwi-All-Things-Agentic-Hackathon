import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Plays Gemini Live's raw PCM16 mono audio output as real synthesized
/// speech — not a device-TTS re-reading of the transcript.
///
/// `audioplayers` needs a container format its platform decoders recognize,
/// not headerless PCM, so each batch is wrapped with a minimal WAV header.
/// The important part is *batching*: network chunks arrive every ~100-300ms,
/// far more often than is safe to hand to `AudioPlayer.play()` — each call
/// has real setup overhead (new source, buffer, start), which showed up as
/// audible word-by-word stuttering when every chunk got its own play() call.
/// Instead, incoming chunks are appended to one pending buffer; whatever has
/// accumulated is flushed into a single play() call only when the player is
/// actually free (on `onPlayerComplete`). Since chunks arrive faster than a
/// short clip takes to play, this naturally coalesces bursts of chunks into
/// far fewer, larger, gapless playback calls without adding much latency —
/// the first chunk still plays as soon as it arrives.
class PcmAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  final BytesBuilder _pending = BytesBuilder(copy: false);
  int _sampleRate = 24000;
  bool _playing = false;
  bool _disposed = false;

  PcmAudioPlayer() {
    _player.onPlayerComplete.listen((_) {
      _playing = false;
      _flushAndPlay();
    });
    // Without this, audioplayers defaults to requesting EXCLUSIVE Android
    // audio focus (AndroidAudioFocus.gain) every time playback starts — the
    // documented, root-caused fix for "the agent answers once, then never
    // hears me again": exclusive focus signals every other audio session,
    // including the concurrently-running mic recording (`record` package),
    // to yield, so the user's next utterance after the agent's own reply
    // never reaches the app at all. mixWithOthers maps to
    // AndroidAudioFocus.none (iOS: mixWithOthers), letting playback and
    // recording run simultaneously, which is exactly this app's shape.
    _player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
  }

  void enqueue(Uint8List pcm16, int sampleRate) {
    if (_disposed) return;
    _sampleRate = sampleRate;
    _pending.add(pcm16);
    if (!_playing) _flushAndPlay();
  }

  void _flushAndPlay() {
    if (_disposed || _pending.isEmpty) return;
    final bytes = _pending.takeBytes();
    _playing = true;
    final wav = _wrapWav(bytes, _sampleRate);
    _player.play(BytesSource(wav)).catchError((e) {
      log('PcmAudioPlayer: play error: $e');
      _playing = false;
      _flushAndPlay();
    });
  }

  /// Drops anything buffered but not yet played (e.g. the user interrupted).
  void clearQueue() {
    _pending.clear();
  }

  /// Halts playback outright — not just clearing what hasn't played yet.
  /// Real gap found from a live device test: on a reconnect (the live
  /// session naturally ends and a fresh one opens — see
  /// CloudVoiceScreen._onLiveSessionEnded), `clearQueue()` alone leaves
  /// whatever chunk was ALREADY handed to the native player running to
  /// completion. If the new session starts talking before that finishes,
  /// the two overlap and the user hears what sounds like a repeated answer.
  /// This actually stops the underlying player, not just the queue feeding it.
  Future<void> stop() async {
    _pending.clear();
    _playing = false;
    try {
      await _player.stop();
    } catch (e) {
      log('PcmAudioPlayer: stop error: $e');
    }
  }

  Uint8List _wrapWav(Uint8List pcm16, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = pcm16.length;

    final header = ByteData(44);
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, 36 + dataLength, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // fmt chunk size
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataLength, Endian.little);

    final wav = Uint8List(44 + dataLength);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataLength, pcm16);
    return wav;
  }

  Future<void> dispose() async {
    _disposed = true;
    _pending.clear();
    await _player.dispose();
  }
}
