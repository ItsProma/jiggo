import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class DocumentSpeech {
  Future<bool> initialize();
  Future<List<String>> locales();
  Future<void> listen({
    required String locale,
    required void Function(String text) onText,
    required void Function(bool listening) onListening,
    required void Function() onError,
  });
  Future<void> stop();
  Future<void> cancel();
}

/// One recognizer for the application. The plugin keeps initialization callbacks
/// for its lifetime; callbacks here always point to the current dialog session.
class DeviceDocumentSpeech implements DocumentSpeech {
  static final instance = DeviceDocumentSpeech._();
  DeviceDocumentSpeech._();
  final _speech = SpeechToText();
  Future<bool>? _initializing;
  void Function(bool)? _onListening;
  void Function()? _onError;
  int _session = 0;

  @override
  Future<bool> initialize() => _initializing ??= _initialize();

  Future<bool> _initialize() async {
    try {
      final ready = await _speech.initialize(
        options: [SpeechToText.androidNoBluetooth],
        onStatus: (status) => _onListening?.call(status == 'listening'),
        onError: (_) => _onError?.call(),
      );
      if (!ready) _initializing = null;
      return ready;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  @override
  Future<List<String>> locales() async {
    // Browser recognition does not enumerate installed speech languages.
    if (kIsWeb) return const ['bn-BD', 'en-US'];
    return (await _speech.locales()).map((e) => e.localeId).toList();
  }

  @override
  Future<void> listen({
    required String locale,
    required void Function(String text) onText,
    required void Function(bool listening) onListening,
    required void Function() onError,
  }) async {
    final session = ++_session;
    _onListening = onListening;
    _onError = onError;
    await _speech.listen(
      onResult: (result) {
        if (session == _session) onText(result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: locale,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 8),
      ),
    );
    if (session == _session) onListening(_speech.isListening);
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() async {
    ++_session;
    _onListening = null;
    _onError = null;
    await _speech.cancel();
  }
}
