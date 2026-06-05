import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';

import '../api/api_client.dart';
import 'speech_synthesizer_service.dart';

class CloudSpeechSynthesizerService implements SpeechSynthesizerService {
  CloudSpeechSynthesizerService(this._api) {
    _completeSub = _player.onPlayerComplete.listen((_) {
      _speaking = false;
    });
  }

  final ApiClient _api;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;

  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<void> speak(String text, {String? localeId}) async {
    final value = text.trim();
    if (value.isEmpty) return;

    final data = await _api.request(
      'POST',
      'agent/tts/',
      body: {'text': value, 'format': 'mp3'},
      auth: true,
    );
    final audioBase64 = data is Map<String, dynamic>
        ? data['audio_base64'] as String?
        : null;
    if (audioBase64 == null || audioBase64.isEmpty) {
      throw StateError('语音服务没有返回音频');
    }
    final bytes = base64Decode(audioBase64);
    await _player.stop();
    _speaking = true;
    await _player.play(BytesSource(bytes));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _speaking = false;
  }

  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _player.dispose();
  }
}
