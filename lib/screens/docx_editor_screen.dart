import '../services/local_file_saver.dart';
import '../services/local_file_model.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../services/app_strings.dart';
import '../services/docx_codec.dart';
import '../services/docx_files.dart';
import '../services/docx_processor.dart';

class DocxEditorScreen extends StatefulWidget {
  final LocalFileSaver? library;
  final bool autoOpen;
  final DocxFiles? files;
  final DocxProcessor processor;
  const DocxEditorScreen({
    super.key,
    this.library,
    this.autoOpen = false,

    this.files,
    this.processor = const DocxProcessor(),
  });
  @override
  State<DocxEditorScreen> createState() => _DocxEditorScreenState();
}

class _DocxEditorScreenState extends State<DocxEditorScreen> {
  late QuillController _controller;
  final _title = TextEditingController(text: 'My document');
  late final _files = widget.files ?? DeviceDocxFiles();
  bool _busy = false;
  int _generation = 0;
  String? _notice;
  late String _saved;
  String _savedTitle = 'My document';
  bool get _dirty =>
      _saved != jsonEncode(_controller.document.toDelta().toJson()) ||
      _title.text != _savedTitle;
  QuillController _make(List<dynamic> json) {
    final controller = QuillController(
      document: Document.fromJson(json),
      selection: const TextSelection.collapsed(offset: 0),
      config: const QuillControllerConfig(
        // Quill is pinned to the tested version; this disables HTML/Markdown paste.
        // ignore: experimental_member_use
        clipboardConfig: QuillClipboardConfig(enableExternalRichPaste: false),
      ),
    );
    controller.onReplaceText = (index, len, data) {
      if (_busy ||
          data is! String ||
          controller.document.length - len + data.length > DocxCodec.maxText) {
        if (mounted) {
          setState(
            () => _notice = 'Use plain text within 20000 characters. Your current document is kept.',
          );
        }
        return false;
      }
      return true;
    };
    controller.addListener(_change);
    return controller;
  }

  @override
  void initState() {
    super.initState();
    _controller = _make([
      {'insert': '\n'},
    ]);
    _saved = jsonEncode(_controller.document.toDelta().toJson());
    if (widget.autoOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  void _change() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_change);
    _controller.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<bool> _confirm() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('Leave this document?')),
            content: Text(
              context.tr(
                'Save a DOCX copy before continuing. Use Save to Library to keep a copy on this device.',
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

  Future<void> _open({bool blank = false}) async {
    if (_busy || !await _confirm() || !mounted) return;
    setState(() {
      _busy = true;
      _controller.readOnly = true;
    });
    try {
      final picked = blank ? null : await _files.pick();
      if (!blank && picked == null) return;
      if (picked != null &&
          (!picked.name.toLowerCase().endsWith('.docx') ||
              picked.bytes.length > DocxCodec.maxBytes)) {
        throw const FormatException();
      }
      final delta = blank
          ? <Map<String, dynamic>>[
              {'insert': '\n'},
            ]
          : await widget.processor.decode(picked!.bytes);
      if (!mounted) return;
      final next = _make(delta);
      final old = _controller;
      old.removeListener(_change);
      final title = blank
          ? 'My document'
          : picked!.name.replaceFirst(
              RegExp(r'\.docx$', caseSensitive: false),
              '',
            );
      setState(() {
        _controller = next;
        _generation++;
        _title.text = title.length > 140 ? title.substring(0, 140) : title;
        _savedTitle = _title.text;
        _saved = jsonEncode(next.document.toDelta().toJson());
        _notice = blank
            ? null
            : 'Opened a basic editable copy. Review formatting before saving.';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'This file could not be opened. Use a basic DOCX under 2 MB without tables, images, links, tracked changes or nested lists. Your current document is kept.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _controller.readOnly = false;
        });
      }
    }
  }

  Future<void> _export(bool share, {bool library = false}) async {
    if (_busy) return;
    if (_title.text.trim().isEmpty ||
        _title.text.length > 140 ||
        _controller.document.length > DocxCodec.maxText) {
      setState(
        () => _notice =
            'Use a title of 1–140 characters and text within 20000 characters.',
      );
      return;
    }
    final delta = List<Map<String, dynamic>>.from(
      _controller.document.toDelta().toJson(),
    );
    final title = _title.text;
    setState(() {
      _busy = true;
      _controller.readOnly = true;
    });
    try {
      final saver = library
          ? (widget.library ?? AccountLocalFileSaver.capture())
          : null;
      final bytes = await widget.processor.encode(delta);
      if (!mounted) return;
      final result = library
          ? await saveLocalCopy(
              saver!,
              docxFilename(title),
              LocalFileKind.docx,
              bytes,
              'Word DOCX',
            )
          : share
          ? await _files.share(bytes, docxFilename(title))
          : await _files.save(bytes, docxFilename(title));
      if (!mounted) return;
      setState(() {
        _notice = library
            ? 'Saved to Library on this device.'
            : switch (result) {
                PdfDelivery.saved => 'DOCX copy saved.',
                PdfDelivery.downloadRequested =>
                  'DOCX download requested. Check Downloads before leaving.',
                PdfDelivery.shareOpened => 'DOCX sharing opened.',
                PdfDelivery.cancelled =>
                  'Sharing or saving did not finish. Your document is kept.',
              };
        if (result == PdfDelivery.saved) {
          _saved = jsonEncode(delta);
          _savedTitle = title;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = library ? localSaveFailure(error) : 'Unable to export DOCX. Use only Bold, Italic, Heading and single-level lists. Your document is kept; copy the text if needed.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _controller.readOnly = false;
        });
      }
    }
  }

  void _inline(Attribute attribute) {
    final current = _controller
        .getSelectionStyle()
        .attributes[attribute.key]
        ?.value;
    _controller.formatSelection(
      Attribute.clone(attribute, current == true ? null : true),
    );
  }

  void _block(String key, dynamic value) {
    if (key == 'header') {
      _controller.formatSelection(Attribute.clone(Attribute.ul, null));
    }
    if (key == 'list') {
      _controller.formatSelection(Attribute.clone(Attribute.h1, null));
    }
    final attr = key == 'header' ? Attribute.h1 : Attribute.ul;
    _controller.formatSelection(Attribute.clone(attr, value));
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: _controller.document.toPlainText()),
      );
      if (mounted) setState(() => _notice = 'Text copied.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Unable to copy text. Try saving a DOCX copy.',
        );
      }
    }
  }

  Future<void> _close() async {
    if (_busy || !await _confirm() || !mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final attrs = _controller.getSelectionStyle().attributes;
    final heading = attrs['header']?.value as int? ?? 0;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _close),
        title: Text(context.tr('Word DOCX')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('Basic DOCX copy editor')),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Keeps text, Bold, Italic, Heading 1–3 and single-level lists. Fonts, colors and page layout are normalized. Lists restart from 1. Save a new copy before closing or refreshing.',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _open(),
                    icon: const Icon(Icons.folder_open),
                    label: Text(context.tr('Open DOCX')),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _open(blank: true),
                    child: Text(context.tr('New document')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('docx-title'),
                controller: _title,
                enabled: !_busy,
                maxLength: 140,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                decoration: InputDecoration(
                  labelText: context.tr('File title'),
                ),
                onChanged: (_) => setState(() {}),
              ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  IconButton(
                    tooltip: context.tr('Bold'),
                    isSelected: attrs['bold']?.value == true,
                    onPressed: _busy ? null : () => _inline(Attribute.bold),
                    icon: const Icon(Icons.format_bold),
                  ),
                  IconButton(
                    tooltip: context.tr('Italic'),
                    isSelected: attrs['italic']?.value == true,
                    onPressed: _busy ? null : () => _inline(Attribute.italic),
                    icon: const Icon(Icons.format_italic),
                  ),
                  IconButton(
                    tooltip: context.tr('Bullet list'),
                    isSelected: attrs['list']?.value == 'bullet',
                    onPressed: _busy
                        ? null
                        : () => _block(
                            'list',
                            attrs['list']?.value == 'bullet' ? null : 'bullet',
                          ),
                    icon: const Icon(Icons.format_list_bulleted),
                  ),
                  IconButton(
                    tooltip: context.tr('Numbered list'),
                    isSelected: attrs['list']?.value == 'ordered',
                    onPressed: _busy
                        ? null
                        : () => _block(
                            'list',
                            attrs['list']?.value == 'ordered'
                                ? null
                                : 'ordered',
                          ),
                    icon: const Icon(Icons.format_list_numbered),
                  ),
                  IconButton(
                    tooltip: context.tr('Undo'),
                    onPressed: !_busy && _controller.hasUndo
                        ? _controller.undo
                        : null,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: context.tr('Redo'),
                    onPressed: !_busy && _controller.hasRedo
                        ? _controller.redo
                        : null,
                    icon: const Icon(Icons.redo),
                  ),
                ],
              ),
              DropdownButtonFormField<int>(
                key: ValueKey('docx-heading-$_generation-$heading'),
                initialValue: heading,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Paragraph style'),
                ),
                items: [
                  for (var i = 0; i <= 3; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        context.tr(i == 0 ? 'Normal text' : 'Heading $i'),
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => _block('header', v == 0 ? null : v),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(minHeight: 300),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QuillEditor.basic(
                  key: ValueKey('docx-editor-$_generation'),
                  controller: _controller,
                  config: QuillEditorConfig(
                    scrollable: false,
                    placeholder: context.tr(
                      'Write or paste your document text here.',
                    ),
                  ),
                ),
              ),
              Text('${_controller.document.length}/${DocxCodec.maxText}'),
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
                  OutlinedButton.icon(
                    key: const ValueKey('local-library-save'),
                    onPressed: _busy
                        ? null
                        : () => _export(false, library: true),
                    icon: const Icon(Icons.library_add_outlined),
                    label: Text(context.tr('Save to Library')),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _export(false),
                    child: Text(context.tr('Save DOCX copy')),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _export(true),
                    child: Text(context.tr('Share DOCX')),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _copy,
                    child: Text(context.tr('Copy text')),
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
}
