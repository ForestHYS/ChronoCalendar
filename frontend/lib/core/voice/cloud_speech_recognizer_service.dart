import 'speech_recognizer_service.dart';

class CloudSpeechRecognizerService implements SpeechRecognizerService {
  CloudSpeechRecognizerService();

  @override
  bool get isAvailable => false;

  @override
  bool get isListening => false;

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> listen({
    required SpeechTextCallback onResult,
    SpeechDoneCallback? onDone,
    SpeechErrorCallback? onError,
    String? localeId,
  }) {
    throw UnimplementedError('Cloud ASR has not been configured yet.');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}
