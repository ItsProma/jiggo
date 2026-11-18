import '../services/app_theme.dart';
import '../services/app_strings.dart';
import '../services/document_brief.dart';
import '../services/document_speech.dart';
import '../widgets/document_details_dialog.dart';
import '../widgets/document_voice_dialog.dart';

import 'dart:async' as async_utils;

import '../services/ai_eligibility_service.dart';
import '../services/ads_service.dart';
import '../widgets/ai_report_button.dart';
import '../services/pdf_export_service.dart';
import '../services/ai_limit_messages.dart';
import 'document_editor_screen.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/material.dart';

class AiDocumentScreen extends StatefulWidget {
  final String documentType;
  final DocumentSpeech? speech;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? generator;
  final Future<void> Function({required String title, required String content})?
  pdfExporter;

  const AiDocumentScreen({
    super.key,
    this.documentType = 'Custom AI Document',
    this.generator,
    this.speech,
    this.pdfExporter,
  });

  @override
  State<AiDocumentScreen> createState() => _AiDocumentScreenState();
}

class _AiDocumentScreenState extends State<AiDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();

  String _language = 'Bangla';
  bool _initialized = false;
  bool _manualTitle = false;
  bool _isPreparing = false;
  bool _questionsReviewed = false;
  Map<String, String> _answers = {};
  DocumentBrief get _brief => DocumentBrief(widget.documentType);
  bool get _busy =>
      _isPreparing || _isGenerating || _isExporting || _isOpeningEditor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _language = Localizations.localeOf(context).languageCode == 'bn'
        ? 'Bangla'
        : 'English';
    _titleController.text = _brief.title(_language);
  }

  Future<bool> _reviewDetails() async {
    final questions = _brief.questionsFor(_instructionsController.text);
    if (questions.isEmpty) return true;
    final answers = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => DocumentDetailsDialog(
        brief: _brief,
        details: _instructionsController.text,
        answers: _answers,
        questions: questions,
      ),
    );
    if (!mounted || answers == null) return false;
    setState(() {
      _answers = answers;
      _questionsReviewed = true;
    });
    return true;
  }

  Future<void> _editDetails() async {
    if (_busy) return;
    setState(() => _isPreparing = true);
    try {
      await _reviewDetails();
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  void _detailsChanged() {
    _answers = {};
    _questionsReviewed = false;
  }

  Future<void> _voiceDetails() async {
    if (_busy) return;
    final original = _instructionsController.text;
    final separator = original.trim().isEmpty ? '' : '\n';
    final available = 2000 - original.length - separator.length;
    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Shorten your details before adding voice text.'),
          ),
        ),
      );
      return;
    }
    final uid = widget.generator == null
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    setState(() => _isPreparing = true);
    try {
      final text = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DocumentVoiceDialog(
          speech: widget.speech ?? DeviceDocumentSpeech.instance,
          initialLanguage: Localizations.localeOf(context).languageCode == 'bn'
              ? 'bn'
              : 'en',
          maxCharacters: available,
        ),
      );
      if (!mounted || text == null || text.isEmpty || text.length > available) {
        return;
      }
      if (widget.generator == null &&
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      setState(() {
        _instructionsController.text = '$original$separator$text';
        _detailsChanged();
      });
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  bool _isGenerating = false;
  String? _generatedDocument;
  String? _generatedTitle;
  String? _generatedLanguage;
  String? _documentId;
  String? _documentOwnerUid;
  bool _saveConfirmed = false;
  bool _isExporting = false;
  bool _isOpeningEditor = false;
  int? _remainingDocuments;
  @override
  void dispose() {
    _titleController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _generateDocument() async {
    if (_busy || _formKey.currentState?.validate() != true) return;
    final preparedUid = widget.generator == null
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    setState(() => _isPreparing = true);
    try {
      if (!_questionsReviewed && !await _reviewDetails()) return;
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
    if (!mounted) return;
    if (widget.generator == null &&
        FirebaseAuth.instance.currentUser?.uid != preparedUid) {
      return;
    }
    final title = _titleController.text.trim().isEmpty
        ? _brief.title(_language)
        : _titleController.text.trim();
    final language = _language;
    final instructions = _brief.compose(_instructionsController.text, _answers);
    if (instructions.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Shorten your details or answers to continue.'),
          ),
        ),
      );
      return;
    }
    final payload = <String, dynamic>{
      'title': title,
      'instructions': instructions,
      'documentType': widget.documentType,
      'language': language,
    };
    setState(() => _isGenerating = true);
    try {
      // A test callback avoids using a real Firebase project in widget tests.
      final ownerUid = widget.generator == null
          ? FirebaseAuth.instance.currentUser?.uid
          : null;
      late final Map<String, dynamic> data;
      final generator = widget.generator;
      if (generator != null) {
        data = await generator(payload);
      } else {
        if (!await AiEligibilityService.ensure(context)) {
          return;
        }
        if (!mounted || AiEligibilityService.currentUid != ownerUid) {
          return;
        }
        payload['expectedUid'] = ownerUid;
        async_utils.unawaited(AdsService.instance.start());
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable(
              'generateDocument',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 70),
              ),
            );
        final result = await callable.call(payload);
        data = Map<String, dynamic>.from(result.data as Map);
      }
      if (widget.generator == null &&
          AiEligibilityService.currentUid != ownerUid) {
        return;
      }
      final document = data['document'];
      if (document is! String || document.trim().isEmpty) {
        throw const FormatException('Empty document received');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _generatedDocument = document;
        _generatedTitle = data['title'] as String? ?? title;
        _generatedLanguage = data['language'] as String? ?? language;
        _saveConfirmed = data['savedToLibrary'] == true;
        _documentId = _saveConfirmed ? data['documentId'] as String? : null;
        _documentOwnerUid = ownerUid;
        _remainingDocuments = (data['remainingToday'] as num?)?.toInt();
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      final message =
          aiSafetyMessage(error.details) ??
          switch (error.code) {
            'resource-exhausted' => aiLimitMessage(error.details),
            'unauthenticated' => 'Please log in first.',
            'invalid-argument' => 'Check the title and document instructions.',
            'deadline-exceeded' =>
              'Request timed out. Check Library before generating again.',
            'unavailable' => 'Check your internet connection and try again.',
            'failed-precondition' => 'This account is unavailable for AI requests. Please check your account status.',
            _ => 'Unable to generate document. Please try again later.',
          };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr(message))));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Unable to generate document. Please try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _downloadPdf() async {
    if (_isExporting || _generatedDocument == null) {
      return;
    }
    final title = _generatedTitle!;
    final content = _generatedDocument!;
    setState(() => _isExporting = true);
    try {
      final exporter = widget.pdfExporter ?? PdfExportService.exportDocument;
      await exporter(title: title, content: content);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('Unable to export PDF. Please try again.')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _editDocument() async {
    if (_isOpeningEditor || _isExporting || _documentId == null) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != _documentOwnerUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Log in with the account that created this document.'),
          ),
        ),
      );
      return;
    }
    final id = _documentId!;
    setState(() => _isOpeningEditor = true);
    try {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => DocumentEditorScreen(
            documentId: id,
            title: _generatedTitle!,
            content: _generatedDocument!,
          ),
        ),
      );
      if (!mounted ||
          saved != true ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('documents')
          .doc(id)
          .get();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      final data = snapshot.data();
      if (data == null) {
        throw StateError('Document not found');
      }
      setState(() {
        _generatedTitle = data['title'] as String? ?? _generatedTitle;
        _generatedDocument = data['content'] as String? ?? _generatedDocument;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Unable to open or refresh this document. Check Library.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningEditor = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageColor,
      appBar: AppBar(
        backgroundColor: context.pageColor,
        title: Text(context.tr('Create Document')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              context.tr(widget.documentType),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Write a few details. Jiggo will help you make a draft.',
              ),
              style: TextStyle(color: context.mutedColor),
            ),
            const SizedBox(height: 24),

            TextFormField(
              key: const ValueKey('document-title'),
              controller: _titleController,
              enabled: !_busy,
              onChanged: (value) => _manualTitle = value.trim().isNotEmpty,
              maxLength: 150,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => Text('${_titleController.text.length}/150'),
              decoration: InputDecoration(
                labelText: context.tr('Document Title'),
                helperText: context.tr(
                  'A title is filled in for you. You can change it.',
                ),
                helperMaxLines: 3,
                prefixIcon: const Icon(Icons.title),
                filled: true,
                fillColor: context.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              validator: (value) {
                if (value != null &&
                    value.trim().isNotEmpty &&
                    value.trim().length < 3) {
                  return context.tr('Enter a title with at least 3 characters');
                }
                if ((value?.length ?? 0) > 150) {
                  return context.tr('Use 150 characters or fewer');
                }
                return null;
              },
            ),

            const SizedBox(height: 18),

            TextFormField(
              key: const ValueKey('document-details'),
              controller: _instructionsController,
              enabled: !_busy,
              onChanged: (_) => setState(_detailsChanged),
              minLines: 5,
              maxLines: 8,
              maxLength: 2000,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => Text('${_instructionsController.text.length}/2000'),
              decoration: InputDecoration(
                labelText: context.tr('Write or say your details'),
                hintText: context.tr(
                  'Tell us what you need. Do not include sensitive details that are not needed.',
                ),
                alignLabelWithHint: true,
                filled: true,
                fillColor: context.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              validator: (value) {
                if ((value?.length ?? 0) > 2000) {
                  return context.tr('Use 2000 characters or fewer');
                }
                return null;
              },
            ),

            const SizedBox(height: 12),

            ExpansionTile(
              key: const ValueKey('document-example'),
              tilePadding: EdgeInsets.zero,
              title: Text(context.tr('See a simple example')),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(context.tr(_brief.example)),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('document-voice'),
                onPressed: _busy ? null : _voiceDetails,
                icon: const Icon(Icons.mic_none),
                label: Text(context.tr('Say your details')),
              ),
            ),
            if (_questionsReviewed)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : _editDetails,
                  child: Text(context.tr('Review added details')),
                ),
              ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _language,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('Document Language'),
                prefixIcon: const Icon(Icons.language),
                filled: true,
                fillColor: context.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'Bangla',
                  child: Text(context.tr('Bangla')),
                ),
                DropdownMenuItem(
                  value: 'English',
                  child: Text(context.tr('English')),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _language = value;
                          if (!_manualTitle) {
                            _titleController.text = _brief.title(value);
                          }
                        });
                      }
                    },
            ),

            const SizedBox(height: 28),

            SizedBox(
              child: FilledButton.icon(
                onPressed: _busy ? null : _generateDocument,
                icon: const Icon(Icons.auto_awesome),
                label: Text(context.tr('Generate with AI')),
                style: FilledButton.styleFrom(
                  backgroundColor: context.accentColor,
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (_isGenerating)
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(context.tr('Generating your document...')),
                  ],
                ),
              )
            else if (_generatedDocument != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _generatedTitle!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(context.tr(_generatedLanguage!)),
                    const SizedBox(height: 12),
                    Text(
                      context.tr(
                        _saveConfirmed ? 'Saved to Library' : 'Library saving could not be confirmed. Copy or export this document before leaving.',
                      ),
                    ),
                    if (_remainingDocuments != null)
                      Text(
                        context.tr('Remaining documents today: {count}', {
                          'count': _remainingDocuments,
                        }),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await Clipboard.setData(
                              ClipboardData(text: _generatedDocument!),
                            );
                            if (!mounted ||
                                !context.mounted ||
                                !messenger.mounted) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.tr('Document copied successfully'),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: Text(context.tr('Copy')),
                        ),
                        TextButton.icon(
                          onPressed: _isExporting || _isOpeningEditor
                              ? null
                              : _downloadPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(
                            context.tr(
                              _isExporting
                                  ? 'Preparing PDF...'
                                  : 'Download PDF',
                            ),
                          ),
                        ),
                        if (_documentId != null)
                          TextButton.icon(
                            onPressed: _isOpeningEditor || _isExporting
                                ? null
                                : _editDocument,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                              context.tr(
                                _isOpeningEditor
                                    ? 'Opening...'
                                    : 'Edit Document',
                              ),
                            ),
                          ),
                      ],
                    ),

                    AiReportButton(
                      source: 'document',
                      content: _generatedDocument!,
                    ),
                    const Divider(),

                    const SizedBox(height: 12),
                    MarkdownBody(data: _generatedDocument!, selectable: true),
                  ],
                ),
              )
            else
              Text(
                context.tr(
                  'Your AI-generated document will appear here after generation.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.mutedColor),
              ),
          ],
        ),
      ),
    );
  }
}
