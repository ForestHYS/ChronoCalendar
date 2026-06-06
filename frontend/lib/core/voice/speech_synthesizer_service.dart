abstract class SpeechSynthesizerService {
  bool get isSpeaking;

  Future<void> speak(String text, {String? localeId});

  Future<void> stop();
}
