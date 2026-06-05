import 'speech_synthesizer_service.dart';

class CloudSpeechSynthesizerService implements SpeechSynthesizerService {
  CloudSpeechSynthesizerService();

  @override
  bool get isSpeaking => false;

  @override
  Future<void> speak(String text, {String? localeId}) {
    throw UnimplementedError('Cloud TTS has not been configured yet.');
  }

  @override
  Future<void> stop() async {}
}
