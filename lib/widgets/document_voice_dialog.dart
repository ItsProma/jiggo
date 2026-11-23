import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/document_speech.dart';

class DocumentVoiceDialog extends StatefulWidget {
  final DocumentSpeech speech;
  final String initialLanguage;
  final int maxCharacters;
  const DocumentVoiceDialog({
    super.key,
    required this.speech,
    required this.initialLanguage,
    required this.maxCharacters,
  });

  @override
  State<DocumentVoiceDialog> createState() => _DocumentVoiceDialogState();
}

class _DocumentVoiceDialogState extends State<DocumentVoiceDialog>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  late String _language = widget.initialLanguage;
  bool _starting = false;
  bool _listening = false;
  bool _stopping = false;
  bool _acceptSpeech = false;
  String? _error;
  int _run = 0;
  String _failure(String fallback) => widget.speech is SpeechFailureInfo
      ? ((widget.speech as SpeechFailureInfo).lastFailure ?? fallback)
      : fallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _cancelSpeech() async {
    try {
      await widget.speech.cancel();
    } catch (_) {
      // Leaving the dialog must work even when the platform service fails.
    }
  }

  @override
  void dispose() {
    ++_run;
    _acceptSpeech = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cancelSpeech());
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ++_run;
      _acceptSpeech = false;
      unawaited(_cancelSpeech());
      if (mounted) {
        setState(() {
          _starting = false;
          _listening = false;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _start() async {
    if (_starting || _listening || _stopping) return;
    final run = ++_run;
    final prefix = _text.text.trim();
    setState(() {
      _starting = true;
      _error = null;
      _acceptSpeech = true;
    });
    try {
      if (!await widget.speech.initialize()) {
        if (!mounted || run != _run) return;
        setState(
          () => _error = _failure(
            'Voice is unavailable or microphone permission was denied. You can still type your details.',
          ),
        );
        return;
      }
      if (!mounted || run != _run) return;
      final locales = await widget.speech.locales();
      if (!mounted || run != _run) return;
      final preferred = _language == 'bn' ? 'bn-BD' : 'en-US';
      String? locale;
      for (final candidate in locales) {
        if (candidate.replaceAll('_', '-').toLowerCase() ==
            preferred.toLowerCase()) {
          locale = candidate;
          break;
        }
      }
      locale ??= locales
          .where(
            (l) =>
                l.toLowerCase().startsWith('$_language-') ||
                l.toLowerCase().startsWith('${_language}_'),
          )
          .firstOrNull;
      if (locale == null) {
        setState(
          () => _error = 'This speech language is unavailable on this device. Try another language or type instead.',
        );
        return;
      }
      await widget.speech.listen(
        locale: locale,
        onText: (text) {
          if (!mounted || run != _run || !_acceptSpeech) return;
          final value = [
            if (prefix.isNotEmpty) prefix,
            if (text.trim().isNotEmpty) text.trim(),
          ].join('\n');
          setState(() {
            _text.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            );
          });
        },
        onListening: (listening) {
          if (mounted && run == _run) setState(() => _listening = listening);
        },
        onError: () {
          if (!mounted || run != _run) return;
          setState(() {
            _listening = false;
            _error = _failure(
              'Speech could not be recognised. Check microphone permission and your connection, then try again or type.',
            );
          });
        },
      );
    } catch (_) {
      if (mounted && run == _run) {
        _acceptSpeech = false;
        await _cancelSpeech();
        if (!mounted || run != _run) return;
        setState(() {
          _listening = false;
          _error = _failure(
            'Voice is unavailable or microphone permission was denied. You can still type your details.',
          );
        });
      }
    } finally {
      if (mounted && run == _run) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    try {
      await widget.speech.stop();
    } catch (_) {
      _acceptSpeech = false;
      await _cancelSpeech();
      if (mounted) {
        setState(
          () => _error = 'Speech could not be recognised. Check microphone permission and your connection, then try again or type.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _listening = false;
          _stopping = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _starting || _listening || _stopping;
    final fits = _text.text.trim().length <= widget.maxCharacters;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: Text(context.tr('Say your details')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'Voice uses your device or browser speech service, which may process audio online. Jiggo does not save audio files. Review the text before adding it.',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _language,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Speaking language'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'bn',
                    child: Text(context.tr('Bangla')),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(context.tr('English')),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) setState(() => _language = v);
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('voice-start-stop'),
                onPressed: _starting || _stopping
                    ? null
                    : _listening
                    ? _stop
                    : _start,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Text(
                  context.tr(
                    _starting
                        ? 'Opening microphone...'
                        : _stopping
                        ? 'Stopping...'
                        : _listening
                        ? 'Stop listening'
                        : _error != null
                        ? 'Retry'
                        : 'Start listening',
                  ),
                ),
              ),
              if (_listening)
                Text(context.tr('Listening... Speak a short sentence.')),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    context.tr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('voice-transcript'),
                controller: _text,
                readOnly: busy,
                minLines: 3,
                maxLines: 7,
                decoration: InputDecoration(
                  labelText: context.tr('Review and edit text'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  // A delayed final result must never replace manual corrections.
                  _acceptSpeech = false;
                  setState(() {});
                },
              ),
              Text(
                context.tr('Space available: {count} characters', {
                  'count': widget.maxCharacters,
                }),
              ),
              if (!fits)
                Text(
                  context.tr('Shorten the recognised text before adding it.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('voice-use-text'),
          onPressed: busy || !fits || _text.text.trim().isEmpty
              ? null
              : () {
                  _acceptSpeech = false;
                  ++_run;
                  Navigator.pop(context, _text.text.trim());
                },
          child: Text(context.tr('Use text')),
        ),
      ],
    );
  }
}
