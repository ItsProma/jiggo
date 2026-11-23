import '../widgets/guarded_page_exit.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_strings.dart';
import '../services/handwriting_gateway.dart';
import '../services/text_file_actions.dart';
import '../widgets/ai_report_button.dart';

class HandwritingTextScreen extends StatefulWidget {
  final String title, text;
  final String? documentId, expectedUid;
  final HandwritingGateway? gateway;
  final TextFileActions? files;
  const HandwritingTextScreen({
    super.key,
    required this.title,
    required this.text,
    this.documentId,
    this.expectedUid,
    this.gateway,
    this.files,
  });
  @override
  State<HandwritingTextScreen> createState() => _HandwritingTextScreenState();
}

class _HandwritingTextScreenState extends State<HandwritingTextScreen>
    with GuardedPageExit<HandwritingTextScreen> {
  late final _title = TextEditingController(text: widget.title);
  late final _text = TextEditingController(text: widget.text);
  late final HandwritingGateway _gateway;
  late final _files = widget.files ?? DeviceTextFileActions();
  late String _savedTitle, _savedText;
  bool _busy = false;
  String? _notice;
  bool get _dirty => _title.text != _savedTitle || _text.text != _savedText;
  @override
  void initState() {
    super.initState();
    _gateway =
        widget.gateway ??
        FirebaseHandwritingGateway(expectedUid: widget.expectedUid);
    _savedTitle = widget.title;
    _savedText = widget.text;
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  bool _valid() {
    if (_title.text.trim().length < 3 ||
        _title.text.length > 150 ||
        _text.text.trim().isEmpty ||
        _text.text.length > 20000) {
      setState(
        () => _notice =
            'Use a title of 3–150 characters and text of 1–20000 characters.',
      );
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_busy || widget.documentId == null || !_valid()) return;
    final title = _title.text.trim(), text = _text.text;
    setState(() => _busy = true);
    try {
      await _gateway.save(widget.documentId!, title, text);
      if (!mounted) return;
      setState(() {
        _savedTitle = title;
        _savedText = text;
        _title.text = title;
        _notice = 'Changes saved to Library.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Unable to save changes. Your edited text is kept; copy or download it.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(bool share) async {
    if (_busy || !_valid()) return;
    setState(() => _busy = true);
    try {
      final result = share
          ? await _files.share(_text.text, _title.text.trim())
          : await _files.save(_text.text, handwritingFilename(_title.text));
      if (mounted) {
        setState(
          () => _notice = switch (result) {
            PdfDelivery.saved => 'Text file saved.',
            PdfDelivery.downloadRequested =>
              'Text download requested. Check Downloads.',
            PdfDelivery.shareOpened => 'Text sharing opened.',
            PdfDelivery.cancelled =>
              'Sharing or saving did not finish. Your text is kept.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Unable to export text. Copy it or try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) setState(() => _notice = 'Copied');
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_dirty || widget.documentId == null) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(context.tr('Leave edited text?')),
          content: Text(
            context.tr(
              'Save changes, copy or download your text before leaving.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Leave')),
            ),
          ],
        ),
      );
      if (!mounted || leave != true) return;
    }
    if (mounted) await finishPageExit();
  }

  @override
  Widget build(BuildContext context) => guardPageExit(
    Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => guardedBack(_close)),
        title: Text(context.tr('Handwriting text')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.tr(
                'Review every line. AI can misread handwriting. [unclear] marks text it could not read.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                widget.documentId == null
                    ? 'Library saving was not confirmed. Copy or download this text before leaving.'
                    : 'This note is saved in Library. Save changes after editing.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('handwriting-title'),
              controller: _title,
              enabled: !_busy,
              maxLength: 150,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              decoration: InputDecoration(labelText: context.tr('Note title')),
              onChanged: (_) => setState(() => _notice = null),
            ),
            TextField(
              key: const ValueKey('handwriting-text'),
              controller: _text,
              enabled: !_busy,
              minLines: 10,
              maxLines: 24,
              maxLength: 20000,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => Text('${_text.text.length}/20000'),
              decoration: InputDecoration(
                labelText: context.tr('Recognized text'),
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _notice = null),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(context.tr(_notice!)),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('handwriting-save'),
                  onPressed: _busy || !_dirty || widget.documentId == null
                      ? null
                      : _save,
                  child: Text(context.tr('Save changes')),
                ),
                OutlinedButton(
                  key: const ValueKey('handwriting-copy'),
                  onPressed: _busy ? null : _copy,
                  child: Text(context.tr('Copy')),
                ),
                OutlinedButton(
                  key: const ValueKey('handwriting-download'),
                  onPressed: _busy ? null : () => _export(false),
                  child: Text(context.tr('Save TXT')),
                ),
                OutlinedButton(
                  key: const ValueKey('handwriting-share'),
                  onPressed: _busy ? null : () => _export(true),
                  child: Text(context.tr('Share text')),
                ),
              ],
            ),
            AiReportButton(source: 'scan', content: _text.text),
          ],
        ),
      ),
    ),
    _close,
  );
}
