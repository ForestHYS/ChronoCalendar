import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../api/api_client.dart';
import 'speech_recognizer_service.dart';

class CloudSpeechRecognizerService implements SpeechRecognizerService {
  CloudSpeechRecognizerService(this._api);

  final ApiClient _api;
  final AudioRecorder _recorder = AudioRecorder();

  bool _available = false;
  bool _listening = false;
  String? _recordingPath;
  StreamSubscription<Uint8List>? _streamSub;
  final List<int> _streamBytes = [];
  SpeechTextCallback? _onResult;
  SpeechDoneCallback? _onDone;
  SpeechErrorCallback? _onError;

  @override
  bool get isAvailable => _available;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize() async {
    _available = await _recorder.hasPermission();
    return _available;
  }

  @override
  Future<bool> listen({
    required SpeechTextCallback onResult,
    SpeechDoneCallback? onDone,
    SpeechErrorCallback? onError,
    String? localeId,
  }) async {
    if (_listening) return true;
    final ok = await initialize();
    if (!ok) return false;

    _onResult = onResult;
    _onDone = onDone;
    _onError = onError;

    if (kIsWeb) {
      _streamBytes.clear();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _streamSub = stream.listen(_streamBytes.addAll);
    } else {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}chrono_voice_$stamp.wav';
      _recordingPath = path;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    }
    _listening = true;
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_listening) return;
    String? path;
    try {
      _listening = false;
      List<int> bytes;
      if (kIsWeb) {
        await _recorder.stop();
        await _streamSub?.cancel();
        _streamSub = null;
        bytes = _wavFromPcm16(
          Uint8List.fromList(_streamBytes),
          sampleRate: 16000,
          channels: 1,
        );
      } else {
        path = await _recorder.stop();
        path ??= _recordingPath;
        if (path == null) return;
        final file = File(path);
        if (!await file.exists()) return;
        bytes = await file.readAsBytes();
      }
      final data = await _api.request(
        'POST',
        'agent/asr/',
        body: {'audio_base64': base64Encode(bytes), 'format': 'wav'},
        auth: true,
      );
      final text = data is Map<String, dynamic>
          ? data['text'] as String?
          : null;
      if (text != null && text.trim().isNotEmpty) {
        _onResult?.call(text.trim(), true);
      }
      _onDone?.call();
    } catch (e) {
      _onError?.call(e);
    } finally {
      _listening = false;
      await _deleteRecording(path ?? _recordingPath);
      _recordingPath = null;
    }
  }

  @override
  Future<void> cancel() async {
    if (_listening) {
      await _recorder.cancel();
    }
    await _streamSub?.cancel();
    _streamSub = null;
    _streamBytes.clear();
    _listening = false;
    await _deleteRecording(_recordingPath);
    _recordingPath = null;
  }

  Future<void> _deleteRecording(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Uint8List _wavFromPcm16(
    Uint8List pcm, {
    required int sampleRate,
    required int channels,
  }) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = pcm.length;
    final out = BytesBuilder(copy: false);

    void writeAscii(String value) => out.add(ascii.encode(value));
    void writeUint16(int value) {
      out.add([value & 0xff, (value >> 8) & 0xff]);
    }

    void writeUint32(int value) {
      out.add([
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);
    }

    writeAscii('RIFF');
    writeUint32(36 + dataLength);
    writeAscii('WAVE');
    writeAscii('fmt ');
    writeUint32(16);
    writeUint16(1);
    writeUint16(channels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeAscii('data');
    writeUint32(dataLength);
    out.add(pcm);
    return out.takeBytes();
  }
}
