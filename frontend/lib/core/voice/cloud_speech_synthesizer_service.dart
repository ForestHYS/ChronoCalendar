import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';

import '../api/api_client.dart';
import 'speech_synthesizer_service.dart';

class CloudSpeechSynthesizerService implements SpeechSynthesizerService {
  CloudSpeechSynthesizerService(this._api) {
    _completeSub = _player.onPlayerComplete.listen((_) {
      _finishCurrent();
    });
  }

  final ApiClient _api;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;

  bool _speaking = false;
  int _generation = 0;
  Completer<void>? _completion;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<void> speak(String text, {String? localeId}) async {
    final value = text.trim();
    if (value.isEmpty) return;

    await stop();
    final gen = ++_generation;
    final completion = Completer<void>();
    _completion = completion;
    try {
      final data = await _api.request(
        'POST',
        'agent/tts/',
        body: {'text': value, 'format': 'mp3'},
        auth: true,
      );
      if (_generation != gen) {
        if (!completion.isCompleted) completion.complete();
        return;
      }
      final audioBase64 = data is Map<String, dynamic>
          ? data['audio_base64'] as String?
          : null;
      if (audioBase64 == null || audioBase64.isEmpty) {
        _finishCurrent();
        throw StateError('语音服务没有返回音频');
      }
      final bytes = base64Decode(audioBase64);
      _speaking = true;
      await _player.play(BytesSource(bytes));
      await completion.future;
    } catch (_) {
      if (_generation == gen) _finishCurrent();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
    _finishCurrent();
  }

  void _finishCurrent() {
    _speaking = false;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }

  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _player.dispose();
  }
}
