import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'speech_recognizer_service.dart';

class SystemSpeechRecognizerService implements SpeechRecognizerService {
  SystemSpeechRecognizerService();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;
  SpeechDoneCallback? _onDone;
  SpeechErrorCallback? _onError;

  @override
  bool get isAvailable => _available;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    if (_initialized) return _available;
    _available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _onDone?.call();
        }
      },
      onError: (SpeechRecognitionError error) {
        _onError?.call(StateError(error.errorMsg));
      },
    );
    _initialized = true;
    return _available;
  }

  @override
  Future<bool> listen({
    required SpeechTextCallback onResult,
    SpeechDoneCallback? onDone,
    SpeechErrorCallback? onError,
    String? localeId,
  }) async {
    final ok = await initialize();
    if (!ok) return false;

    _onDone = onDone;
    _onError = onError;
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
    );
    return true;
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
  }

  @override
  Future<void> cancel() async {
    await _speech.cancel();
  }
}
