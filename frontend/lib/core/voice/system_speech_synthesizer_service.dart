import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_synthesizer_service.dart';

class SystemSpeechSynthesizerService implements SpeechSynthesizerService {
  SystemSpeechSynthesizerService() {
    _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(_finishCurrent);
    _tts.setCancelHandler(_finishCurrent);
    _tts.setErrorHandler((_) => _finishCurrent());
  }

  final FlutterTts _tts = FlutterTts();

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
    await _tts.setLanguage(localeId ?? 'zh-CN');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    _speaking = true;
    try {
      await _tts.speak(value);
      if (_generation == gen && !completion.isCompleted) {
        _finishCurrent();
      }
      await completion.future;
    } catch (_) {
      if (_generation == gen) _finishCurrent();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _tts.stop();
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
}
