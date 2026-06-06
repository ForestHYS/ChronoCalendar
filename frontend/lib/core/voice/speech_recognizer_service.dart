typedef SpeechTextCallback = void Function(String text, bool isFinal);
typedef SpeechDoneCallback = void Function();
typedef SpeechErrorCallback = void Function(Object error);

abstract class SpeechRecognizerService {
  bool get isAvailable;
  bool get isListening;

  Future<bool> initialize();

  Future<bool> listen({
    required SpeechTextCallback onResult,
    SpeechDoneCallback? onDone,
    SpeechErrorCallback? onError,
    String? localeId,
  });

  Future<void> stop();

  Future<void> cancel();
}
