import 'package:flutter_tts/flutter_tts.dart';

import 'speech_synthesizer_service.dart';

class SystemSpeechSynthesizerService implements SpeechSynthesizerService {
  SystemSpeechSynthesizerService() {
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);
  }

  final FlutterTts _tts = FlutterTts();

  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<void> speak(String text, {String? localeId}) async {
    final value = text.trim();
    if (value.isEmpty) return;

    await _tts.stop();
    await _tts.setLanguage(localeId ?? 'zh-CN');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    _speaking = true;
    await _tts.speak(value);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _speaking = false;
  }
}
