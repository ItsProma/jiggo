import 'dart:convert';

import '../services/local_file_saver.dart';
import '../services/local_file_model.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_strings.dart';
import '../services/text_document_picker.dart';
import '../services/text_file_actions.dart';

class FileEditorScreen extends StatefulWidget {
  final LocalFileSaver? library;
  final bool autoOpen;
  final TextDocumentPicker? picker;
  final TextFileActions? files;
  const FileEditorScreen({
    super.key,
    this.picker,
    this.files,
    this.library,
    this.autoOpen = false,
  });
  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  final _text = TextEditingController();
  final _title = TextEditingController(text: 'My text');
  final _undo = UndoHistoryController();
  final _focus = FocusNode();
  late final _picker = widget.picker ?? DeviceTextDocumentPicker();
  late final _files = widget.files ?? DeviceTextFileActions();
  bool _busy = false;
  int _generation = 0;
  String _baseline = '', _baseTitle = 'My text';
  String? _notice;
  bool get _changed => _text.text != _baseline || _title.text != _baseTitle;
  @override
  void initState() {
    super.initState();
    if (widget.autoOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    _undo.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<bool> _confirm() async {
    if (!_changed) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('Leave this text?')),
            content: Text(
              context.tr(
                'Save a TXT copy or copy your text before continuing. Use Save to Library to keep a copy on this device.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr('Continue')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _open() async {
    if (_busy || !await _confirm() || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = await _picker.pick();
      if (!mounted || file == null) return;
      if (file.text.length > TextDocument.maxCharacters) {
        throw const FormatException();
      }
      final name = file.name.replaceAll(
        RegExp(r'\.txt$', caseSensitive: false),
        '',
      );
      setState(() {
        _text.text = file.text;
        _title.text = name.length > 140 ? name.substring(0, 140) : name;
        _baseline = file.text;
        _baseTitle = _title.text;
        _generation++;
        _notice = 'Opened a local copy. Your original file is unchanged.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Could not open this file. Choose a UTF-8 TXT file under 128 KB and 20000 characters. Your current text is kept.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    if (_busy) return;
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || clip?.text == null) return;
      final selection = _text.selection;
      final start = selection.isValid ? selection.start : _text.text.length;
      final end = selection.isValid ? selection.end : start;
      final next = _text.text.replaceRange(start, end, clip!.text!);
      if (next.length > TextDocument.maxCharacters) {
        setState(
          () => _notice = 'Text is too long. Keep it within 20000 characters.',
        );
        return;
      }
      _text.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + clip.text!.length),
      );
      setState(() => _notice = null);
      _focus.requestFocus();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Clipboard access failed. Paste directly into the text field.',
        );
      }
    }
  }

  Future<void> _export(bool share, {bool library = false}) async {
    if (_busy) return;
    if (_text.text.trim().isEmpty ||
        _text.text.length > TextDocument.maxCharacters ||
        _title.text.trim().isEmpty ||
        _title.text.length > 140) {
      setState(
        () => _notice =
            'Enter a title of 1–140 characters and text of 1–20000 characters.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final saver = library
          ? (widget.library ?? AccountLocalFileSaver.capture())
          : null;
      final title = _title.text.trim();
      final result = library
          ? await saveLocalCopy(
              saver!,
              handwritingFilename('${title}_edited'),
              LocalFileKind.txt,
              Uint8List.fromList(utf8.encode(_text.text)),
              'Text Editor',
            )
          : share
          ? await _files.share(_text.text, title)
          : await _files.save(
              _text.text,
              handwritingFilename('${title}_edited'),
            );
      if (!mounted) return;
      setState(
        () => _notice = library
            ? 'Saved to Library on this device.'
            : switch (result) {
                PdfDelivery.saved =>
                  'TXT copy saved. Your original file is unchanged.',
                PdfDelivery.downloadRequested =>
                  'TXT download requested. Check Downloads before leaving.',
                PdfDelivery.shareOpened => 'Text sharing opened.',
                PdfDelivery.cancelled =>
                  'Sharing or saving did not finish. Your text is kept.',
              },
      );
      // Sharing or requesting a download does not prove a file was saved.
      if (result == PdfDelivery.saved) {
        _baseline = _text.text;
        _baseTitle = _title.text;
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = library
              ? localSaveFailure(error)
              : 'Unable to export text. Copy it or try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _text.text));
      if (mounted) setState(() => _notice = 'Text copied.');
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Unable to copy text. Try saving a TXT copy.');
      }
    }
  }

  Future<void> _close() async {
    if (_busy || !await _confirm() || !mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: _close),
      title: Text(context.tr('Text Editor')),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Write, paste or open a TXT file.')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('open-txt'),
                  onPressed: _busy ? null : _open,
                  icon: const Icon(Icons.folder_open),
                  label: Text(context.tr('Open TXT')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.content_paste),
                  label: Text(context.tr('Paste text')),
                ),
                ValueListenableBuilder<UndoHistoryValue>(
                  valueListenable: _undo,
                  builder: (context, value, _) => Wrap(
                    children: [
                      IconButton(
                        tooltip: context.tr('Undo'),
                        onPressed: !_busy && value.canUndo ? _undo.undo : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: context.tr('Redo'),
                        onPressed: !_busy && value.canRedo ? _undo.redo : null,
                        icon: const Icon(Icons.redo),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('text-file-title'),
              controller: _title,
              enabled: !_busy,
              maxLength: 140,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => Text('${_title.text.length}/140'),
              decoration: InputDecoration(labelText: context.tr('File title')),
              onChanged: (_) => setState(() => _notice = null),
            ),
            TextField(
              key: ValueKey('text-file-body-$_generation'),
              controller: _text,
              undoController: _undo,
              focusNode: _focus,
              enabled: !_busy,
              minLines: 12,
              maxLines: 24,
              maxLength: TextDocument.maxCharacters,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => Text('${_text.text.length}/20000'),
              decoration: InputDecoration(
                labelText: context.tr('Your text'),
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('local-library-save'),
                  onPressed: _busy ? null : () => _export(false, library: true),
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(context.tr('Save to Library')),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _export(false),
                  child: Text(context.tr('Save TXT copy')),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _copy,
                  child: Text(context.tr('Copy text')),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _export(true),
                  child: Text(context.tr('Share text')),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
