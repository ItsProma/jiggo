import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../services/translation_gateway.dart';
import '../services/ai_eligibility_service.dart';
import '../services/app_strings.dart';
import '../services/text_file_actions.dart';
import '../services/document_speech.dart';
import '../widgets/document_voice_dialog.dart';

class TranslatorScreen extends StatefulWidget {
  final TranslationGateway? gateway;
  const TranslatorScreen({super.key, this.gateway});
  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final _input = TextEditingController();
  late final _gateway = widget.gateway ?? FirebaseTranslationGateway();
  String _source = 'en', _target = 'bn', _output = '';
  String? _error;
  int? _remaining;
  bool _busy = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {
      _output = '';
      _error = null;
    });
  }

  Future<void> _translate() async {
    if (_busy) return;
    if (_input.text.trim().isEmpty ||
        _input.text.length > 3000 ||
        _source == _target) {
      setState(
        () => _error =
            'Enter up to 3000 characters and choose two different languages.',
      );
      return;
    }
    final text = _input.text.trim(), source = _source, target = _target;
    setState(() {
      _busy = true;
      _error = null;
      _output = '';
    });
    try {
      if (widget.gateway == null && !await AiEligibilityService.ensure(context)) {
        return;
      }
      final result = await _gateway.translate(text, source, target);
      if (!mounted) return;
      if (result['text'] is! String ||
          (result['text'] as String).trim().isEmpty) {
        throw const FormatException();
      }
      setState(() {
        _output = result['text'] as String;
        _remaining = result['remainingToday'] as int?;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e is FirebaseFunctionsException && e.code == 'resource-exhausted'
              ? 'The daily or short-term limit has been reached. Try again later.'
              : 'Translation failed. Your text is kept. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _language(bool source) => DropdownButtonFormField<String>(
    key: ValueKey(
      'translate-${source ? "source" : "target"}-${source ? _source : _target}',
    ),
    initialValue: source ? _source : _target,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: context.tr(source ? 'From' : 'To'),
      border: const OutlineInputBorder(),
    ),
    items: translationLanguages.entries
        .map(
          (e) =>
              DropdownMenuItem(value: e.key, child: Text(context.tr(e.value))),
        )
        .toList(),
    onChanged: _busy
        ? null
        : (v) {
            if (v == null) return;
            if (source) {
              _source = v;
            } else {
              _target = v;
            }
            _changed();
          },
  );
  Future<void> _voice() async {
    final lang = _source == 'bn' ? 'bn' : 'en';
    final text = await showDialog<String>(
      context: context,
      builder: (_) => DocumentVoiceDialog(
        speech: DeviceDocumentSpeech.instance,
        initialLanguage: lang,
        maxCharacters: 3000 - _input.text.length,
      ),
    );
    if (!mounted || text == null) return;
    _input.text = [_input.text, text].where((s) => s.isNotEmpty).join('\n');
    _changed();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Translator'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _language(true),
        Center(
          child: IconButton(
            key: const ValueKey('translate-swap'),
            tooltip: context.tr('Swap languages'),
            onPressed: _busy
                ? null
                : () {
                    final old = _source;
                    _source = _target;
                    _target = old;
                    if (_output.isNotEmpty) _input.text = _output;
                    _changed();
                  },
            icon: const Icon(Icons.swap_vert),
          ),
        ),
        _language(false),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('translate-input'),
          controller: _input,
          enabled: !_busy,
          minLines: 4,
          maxLines: 8,
          maxLength: 3000,
          decoration: InputDecoration(
            labelText: context.tr('Text to translate'),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => _changed(),
        ),
        if (_source == 'bn' || _source == 'en')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _voice,
              icon: const Icon(Icons.mic_none),
              label: Text(context.tr('Say your details')),
            ),
          ),
        FilledButton.icon(
          key: const ValueKey('translate-send'),
          onPressed: _busy ? null : _translate,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.translate),
          label: Text(context.tr(_busy ? 'Please wait...' : 'Translate')),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr(
            'Translations share your daily document allowance. Review important translations.',
          ),
        ),
        if (_error != null) ...[
          Text(context.tr(_error!)),
          TextButton(
            onPressed: _busy ? null : _translate,
            child: Text(context.tr('Retry')),
          ),
        ],
        if (_output.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_output),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _output));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('Copied'))),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text(context.tr('Copy')),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await DeviceTextFileActions().share(_output, 'Translation');
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.tr(
                              'Could not share. Copy the text instead.',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.share),
                label: Text(context.tr('Share')),
              ),
            ],
          ),
          if (_remaining != null)
            Text(
              context.tr('Daily uses remaining: {count}', {
                'count': _remaining,
              }),
            ),
        ],
      ],
    ),
  );
}
