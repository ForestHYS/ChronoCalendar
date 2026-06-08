import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'speech_recognizer_service.dart';

class SystemSpeechRecognizerService implements SpeechRecognizerService {
  SystemSpeechRecognizerService();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;
  bool _disposed = false;
  int _generation = 0;
  SpeechDoneCallback? _onDone;
  SpeechErrorCallback? _onError;

  @override
  bool get isAvailable => _available;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    if (_disposed) return false;
    if (_initialized) return _available;
    _available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          final onDone = _onDone;
          _clearCallbacks();
          onDone?.call();
        }
      },
      onError: (SpeechRecognitionError error) {
        final onError = _onError;
        _clearCallbacks();
        onError?.call(StateError(error.errorMsg));
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

    final gen = ++_generation;
    _onDone = () {
      if (gen == _generation) onDone?.call();
    };
    _onError = (error) {
      if (gen == _generation) onError?.call(error);
    };
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          if (gen != _generation) return;
          onResult(result.recognizedWords, result.finalResult);
        },
      );
    } catch (_) {
      if (gen == _generation) _clearCallbacks();
      rethrow;
    }
    return true;
  }

  @override
  Future<void> stop() async {
    _generation++;
    if (!_disposed) {
      await _speech.stop();
    }
    _clearCallbacks();
  }

  @override
  Future<void> cancel() async {
    _generation++;
    if (!_disposed) {
      await _speech.cancel();
    }
    _clearCallbacks();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
  }

  void _clearCallbacks() {
    _onDone = null;
    _onError = null;
  }
}
