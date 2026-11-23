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

String speechFailureMessage(String code) {
  final value = code.toLowerCase().replaceAll('_', '-');
  if (value.contains('not-allowed') ||
      value.contains('permission') ||
      value.contains('denied')) {
    return 'Microphone permission is blocked. Allow microphone access in app or site settings, then retry.';
  }
  if (value.contains('network') || value.contains('server')) {
    return 'The speech service could not connect. Check your connection and retry.';
  }
  if (value.contains('no-match') ||
      value.contains('no-speech') ||
      value.contains('speech-timeout')) {
    return 'No speech was recognised. Tap Retry and speak clearly near the microphone.';
  }
  if (value.contains('audio-capture') || value.contains('audio-error')) {
    return 'No microphone is available. Check your microphone and close other recording apps.';
  }
  if (value.contains('language')) {
    return 'This speech language is unavailable on this device. Try another language or type instead.';
  }
  if (value.contains('busy') || value.contains('in-progress')) {
    return 'The microphone is busy. Stop other recording apps and retry.';
  }
  if (value.contains('not-supported') || value.contains('unavailable')) {
    return 'Speech recognition is unavailable here. Try Chrome or enable the speech service in device settings. You can still type.';
  }
  return 'Speech could not be recognised. Check microphone permission and your connection, then try again or type.';
}

abstract interface class SpeechFailureInfo {
  String? get lastFailure;
}

/// One recognizer for the application. The plugin keeps initialization callbacks
/// for its lifetime; callbacks here always point to the current dialog session.
class DeviceDocumentSpeech implements DocumentSpeech, SpeechFailureInfo {
  @override
  String? lastFailure;
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
      lastFailure = null;
      final ready = await _speech.initialize(
        options: [SpeechToText.androidNoBluetooth],
        onStatus: (status) => _onListening?.call(status == 'listening'),
        onError: (error) {
          lastFailure = speechFailureMessage(error.errorMsg);
          _onError?.call();
        },
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
    // Clear a completed/failed previous recognizer before opening a new session.
    _onListening = null;
    _onError = null;
    await _speech.cancel();
    final session = ++_session;
    lastFailure = null;
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
    // On the web, onstart arrives asynchronously; isListening may still be false.
    // The recognizer status callback owns the listening state.
    if (session == _session && _speech.isListening) onListening(true);
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
