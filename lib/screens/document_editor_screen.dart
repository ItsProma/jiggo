import '../services/app_theme.dart';
import '../services/app_strings.dart';

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';
import 'package:markdown/markdown.dart' as md;

class DocumentEditorScreen extends StatefulWidget {
  final String documentId;
  final String title;
  final String content;

  const DocumentEditorScreen({
    super.key,
    required this.documentId,
    required this.title,
    required this.content,
  });

  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends State<DocumentEditorScreen> {
  late final QuillController _controller;
  late final TextEditingController _titleController;

  late String _savedDeltaJson;
  late String _savedTitle;

  bool _isSaving = false;
  bool _hasChanges = false;
  bool _allowExit = false;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.title);

    final converter = MarkdownToDelta(
      markdownDocument: md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
      ),
    );

    final delta = converter.convert(widget.content);

    _controller = QuillController.basic();

    _controller.document.compose(delta, ChangeSource.local);

    _savedDeltaJson = jsonEncode(_controller.document.toDelta().toJson());
    _savedTitle = widget.title;

    // Start listening only after the original content is loaded.
    _controller.addListener(_markChanged);
    _titleController.addListener(_markChanged);
  }

  void _markChanged() {
    if (!mounted) {
      return;
    }
    final changed =
        _titleController.text != _savedTitle ||
        jsonEncode(_controller.document.toDelta().toJson()) != _savedDeltaJson;
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  Future<void> _confirmExit() async {
    if (_isSaving) {
      return;
    }

    if (!_hasChanges) {
      setState(() => _allowExit = true);
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Discard changes?')),
        content: Text(
          context.tr('You have unsaved changes. Do you want to discard them?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Keep Editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Discard')),
          ),
        ],
      ),
    );

    if (!mounted || discard != true) {
      return;
    }

    setState(() => _allowExit = true);
    Navigator.pop(context);
  }

  Future<void> _saveDocument() async {
    if (_isSaving) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Please log in first'))),
      );
      return;
    }

    final rawTitle = _titleController.text;
    final newTitle = rawTitle.trim();

    if (newTitle.isEmpty || newTitle.length > 150) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Enter a document title using 1 to 150 characters'),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final savedDelta = _controller.document.toDelta();
      final savedDeltaJson = jsonEncode(savedDelta.toJson());
      final markdown = DeltaToMarkdown().convert(savedDelta);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('documents')
          .doc(widget.documentId)
          .update({'title': newTitle, 'content': markdown});

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Document saved successfully'))),
      );

      // Keep edits made while the previous snapshot was being saved.
      _savedDeltaJson = savedDeltaJson;
      _savedTitle = rawTitle;
      final changedWhileSaving =
          _titleController.text != rawTitle ||
          jsonEncode(_controller.document.toDelta().toJson()) != savedDeltaJson;
      setState(() {
        _hasChanges = changedWhileSaving;
        _allowExit = !changedWhileSaving;
      });
      if (!changedWhileSaving) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Unable to save your document. Check your connection and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_markChanged);
    _titleController.removeListener(_markChanged);
    _controller.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _confirmExit();
        }
      },
      child: Scaffold(
        backgroundColor: context.pageColor,
        appBar: AppBar(
          title: Text(context.tr('Edit Document')),
          backgroundColor: context.pageColor,
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : _saveDocument,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(context.tr(_isSaving ? 'Saving...' : 'Save Changes')),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _titleController,
                maxLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('Document Title'),
                  hintText: context.tr('Enter document title'),
                  prefixIcon: const Icon(Icons.title),
                  filled: true,
                  fillColor: context.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Container(
              color: context.cardColor,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: QuillSimpleToolbar(
                    controller: _controller,
                    config: const QuillSimpleToolbarConfig(
                      showFontFamily: false,
                      showColorButton: false,
                      showBackgroundColorButton: false,
                      showLink: false,
                      showSearchButton: false,
                      showCodeBlock: false,
                      showQuote: false,
                      showIndent: false,
                      showClearFormat: true,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QuillEditor.basic(
                    controller: _controller,
                    config: QuillEditorConfig(
                      placeholder: context.tr('Start writing your document...'),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
