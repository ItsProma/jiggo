import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_strings.dart';
import '../services/ai_eligibility_service.dart';
import '../services/ai_limit_messages.dart';
import '../services/guided_document_model.dart';
import '../services/document_details.dart';
import '../services/document_selections.dart';
import '../services/cv_education.dart';
import '../services/cv_photo.dart';
import '../services/bd_cv_pdf.dart';
import '../services/cv_reference_templates.dart';
import '../services/guided_document_store.dart';
import '../services/guided_document_gateway.dart';
import '../services/document_speech.dart';
import '../services/handwriting_gateway.dart';
import '../services/pdf_scan_image.dart';
import '../services/scan_image.dart';
import '../services/pdf_export_service.dart';
import '../services/pdf_file_actions.dart';
import '../services/local_file_saver.dart';
import '../services/local_file_model.dart';
import '../widgets/document_voice_dialog.dart';
import '../widgets/ai_report_button.dart';
import '../widgets/education_details_dialog.dart';

class GuidedDocumentScreen extends StatefulWidget {
  final String documentType;
  final String? ownerId;
  final String? Function()? currentOwner;
  final GuidedDraftStore? store;
  final GuidedDocumentGateway? gateway;
  final DocumentDetailsGateway? detailsGateway;
  final LocalFileSaver? saver;
  final PdfFileActions? files;
  final DocumentSpeech? speech;
  final Future<Uint8List> Function({
    required String title,
    required String content,
    bool modern,
  })?
  pdfBuilder;
  final Future<XFile?> Function()? photoPicker;
  final Future<String> Function(Uint8List)? questionReader;
  const GuidedDocumentScreen({
    super.key,
    required this.documentType,
    this.ownerId,
    this.currentOwner,
    this.store,
    this.gateway,
    this.detailsGateway,
    this.saver,
    this.files,
    this.speech,
    this.pdfBuilder,
    this.photoPicker,
    this.questionReader,
  });
  @override
  State<GuidedDocumentScreen> createState() => _GuidedDocumentScreenState();
}

class _GuidedDocumentScreenState extends State<GuidedDocumentScreen>
    with WidgetsBindingObserver {
  late GuidedDocument _doc;
  String? _owner;
  String _uiLanguage = 'English';
  bool _loading = true,
      _busy = false,
      _loadError = false,
      _waitingForUser = false;
  String? _notice;
  int? _remaining;
  String? _detailsInput;
  Map<String, dynamic>? _detailsResponse;
  bool get _quick =>
      _doc.type != 'Invoice' && _doc.step == 0 && _doc.v('_entry') != 'form';
  var _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  void _top() {
    final stage = _doc.step;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && _doc.step == stage) {
          _scroll.jumpTo(0);
        }
      });
    });
  }

  final _fields = <String, TextEditingController>{};
  final _education = <TextEditingController>[],
      _experience = <TextEditingController>[];
  final _items = <Map<String, TextEditingController>>[];
  final _preview = TextEditingController();
  Timer? _debounce;
  Future<void> _saveWork = Future.value();
  String? _lastSnapshot;
  Uint8List? _pdf;
  GuidedDraftStore get _store => widget.store ?? guidedDrafts;
  String? _uid() => widget.currentOwner != null
      ? widget.currentOwner!()
      : widget.ownerId ?? FirebaseAuth.instance.currentUser?.uid;
  bool get _active => mounted && _owner != null && _uid() == _owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _doc = GuidedDocument(widget.documentType);
    _owner = widget.ownerId ?? _uid();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _uiLanguage = Localizations.localeOf(context).languageCode == 'bn'
            ? 'Bangla'
            : 'English';
        _load();
      }
    });
  }

  void _disposeInputs() {
    for (final c in [
      ..._fields.values,
      ..._education,
      ..._experience,
      ..._items.expand((m) => m.values),
    ]) {
      c.dispose();
    }
    _fields.clear();
    _education.clear();
    _experience.clear();
    _items.clear();
  }

  void _fillInputs() {
    for (final e in _doc.values.entries) {
      _fields[e.key] = TextEditingController(text: e.value);
    }
    _education.addAll(
      _doc.education.map((s) => TextEditingController(text: s)),
    );
    _experience.addAll(
      _doc.experience.map((s) => TextEditingController(text: s)),
    );
    _items.addAll(
      _doc.items.map(
        (m) => m.map((k, v) => MapEntry(k, TextEditingController(text: v))),
      ),
    );
    _preview.text = _doc.preview;
  }

  Future<void> _load() async {
    if (!mounted || !_active) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
          _notice = 'Please sign in to use saved drafts.';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _loadError = false;
      _notice = null;
    });
    try {
      final raw = await _store
          .read(_owner!, widget.documentType)
          .timeout(const Duration(seconds: 5));
      if (!mounted || !_active) return;
      _doc = GuidedDocument.decode(widget.documentType, raw);
      if (raw == null) _doc.language = _uiLanguage;
      prepareDocumentSelections(_doc, fresh: raw == null);
      if (_doc.type == 'CV / Resume' && _doc.v('_bdLayout') != 'yes') {
        _doc.design = 'BD Traditional';
        _doc.values['_bdLayout'] = 'yes';
      }
      if (_doc.values['_entry'] == null &&
          _doc.fields.any((f) => _doc.v(f.id).isNotEmpty)) {
        _doc.values['_entry'] = 'form';
      }
      _fillInputs();
      _lastSnapshot = jsonEncode(_doc.toJson());
    } catch (_) {
      if (_active) {
        setState(() {
          _loadError = true;
          _notice =
              'Saved draft could not be loaded. Retry or start a new draft.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fresh() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.tr('Replace the saved draft?')),
        content: Text(
          c.tr(
            'This starts a new form on this device. Downloaded and Library files are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.tr('Start new')),
          ),
        ],
      ),
    );
    if (yes != true || !_active) return;
    final old = [
      ..._fields.values,
      ..._education,
      ..._experience,
      ..._items.expand((m) => m.values),
    ];
    _fields.clear();
    _education.clear();
    _experience.clear();
    _items.clear();
    final catalogue = {
      for (final key in ['_customers', '_products'])
        if (_doc.values.containsKey(key)) key: _doc.values[key]!,
    };
    _doc = GuidedDocument(widget.documentType)..language = _uiLanguage;
    prepareDocumentSelections(_doc, fresh: true);
    _doc.values.addAll(catalogue);
    _form = GlobalKey<FormState>();
    _remaining = null;
    _detailsInput = null;
    _detailsResponse = null;
    _pdf = null;
    _preview.clear();
    _notice = null;
    _fillInputs();
    setState(() => _loadError = false);
    _top();
    _persist();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  TextEditingController _c(String id) => _fields.putIfAbsent(
    id,
    () => TextEditingController(text: id == 'title' ? _doc.title : _doc.v(id)),
  );
  void _changed() {
    _doc.preview = '';
    _preview.clear();
    _pdf = null;
    _doc.aiGenerated = false;
    _schedule();
    setState(() => _notice = null);
  }

  void _set(String id, String value) {
    _doc.values[id] = value;
    if (id == 'mode') {
      _doc.values['noExperience'] = value == 'Experienced' ? 'no' : 'yes';
    }
    if (id == 'title' || id == '_input') {
      _pdf = null;
      _schedule();
      setState(() {});
    } else {
      _changed();
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  void _persist() {
    if (!mounted || !_active || _loadError || _loading) return;
    _doc.preview = _preview.text;
    final raw = jsonEncode(_doc.toJson());
    if (raw == _lastSnapshot) return;
    _lastSnapshot = raw;
    final owner = _owner!;
    _saveWork = _saveWork
        .then((_) => _store.write(owner, widget.documentType, raw))
        .catchError((Object _) {
          _lastSnapshot = null;
          if (_active) {
            setState(
              () => _notice = 'Your form could not be saved on this device. Download your document before leaving.',
            );
          }
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _debounce?.cancel();
      _persist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _persist();
    _disposeInputs();
    _preview.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_busy) return;
    final error =
        selectionValidation(_doc, step: _doc.step) ??
        _doc.validation(onlyStep: _doc.step);
    if (_form.currentState?.validate() == false || error != null) {
      setState(() => _notice = error ?? 'Complete the required fields.');
      _top();
      return;
    }
    if (_doc.step < 2) {
      setState(() {
        _doc.step++;
        _notice = null;
        if (_doc.type == 'Assignment' &&
            _doc.step == 2 &&
            _doc.v('outline').isEmpty) {
          final outline = _doc.label(
            'Introduction\nMain discussion\nExamples\nConclusion\nVerified sources (if available)',
            'ভূমিকা\nমূল আলোচনা\nউদাহরণ\nউপসংহার\nযাচাই করা সূত্র (থাকলে)',
          );
          _doc.values['outline'] = outline;
          _c('outline').text = outline;
        }
      });
      _top();
      _persist();
      return;
    }
    if (selectionValidation(_doc) != null || _doc.validation() != null) {
      setState(() => _notice = selectionValidation(_doc) ?? _doc.validation());
      return;
    }
    if (_doc.preview.isNotEmpty) {
      setState(() => _doc.step = 3);
      _top();
      return;
    }
    if (['CV / Resume', 'Invoice'].contains(_doc.type)) {
      _preview.text = _doc.localContent;
      setState(() => _doc.step = 3);
      _top();
      _persist();
      return;
    }
    await _generate();
  }

  Future<void> _generate() async {
    if (_busy || !_active) return;
    if (_doc.instructions.length > 8000) {
      setState(() => _notice = 'Shorten your details to fit the AI limit.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (widget.gateway == null &&
          !await AiEligibilityService.ensure(context)) {
        return;
      }
      if (!mounted || !_active) return;
      final data =
          await (widget.gateway ?? FirebaseGuidedDocumentGateway(_owner!))
              .generate(_doc);
      if (!mounted || !_active) return;
      final text = data['document'];
      if (text is! String || text.trim().isEmpty || text.length > 20000) {
        throw const FormatException('document-result');
      }
      _preview.text = text;
      _pdf = null;
      _doc.aiGenerated = true;
      setState(() {
        _doc.step = 3;
        _remaining = (data['remainingToday'] as num?)?.toInt();
      });
      _top();
      _persist();
    } on FirebaseFunctionsException catch (e) {
      if (_active) {
        setState(
          () => _notice =
              aiSafetyMessage(e.details) ??
              (e.code == 'resource-exhausted'
                  ? aiLimitMessage(e.details)
                  : e.code == 'invalid-argument'
                  ? 'The document service needs updating or some details are too long. Your form is kept.'
                  : 'Unable to create the draft. Check your connection and try again.'),
        );
      }
    } catch (_) {
      if (_active) {
        setState(
          () => _notice = 'Unable to create the draft. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForUser = false;
        });
      }
    }
  }

  Future<void> _voice(
    String id,
    int max, {
    TextEditingController? target,
    ValueChanged<String>? onAccepted,
  }) async {
    if (_busy || !_active) return;
    final c = target ?? _c(id);
    final space = max - c.text.length - (c.text.isEmpty ? 0 : 1);
    if (space < 1) return;
    setState(() => _busy = true);
    try {
      setState(() => _waitingForUser = true);
      final text = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DocumentVoiceDialog(
          speech: widget.speech ?? DeviceDocumentSpeech.instance,
          initialLanguage: Localizations.localeOf(context).languageCode == 'bn'
              ? 'bn'
              : 'en',
          maxCharacters: space,
        ),
      );
      if (!mounted || !_active || text == null || text.trim().isEmpty) return;
      final combined = [
        c.text,
        text.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
      if (combined.length > max) return;
      c.text = combined;
      if (onAccepted != null) {
        onAccepted(combined);
      } else {
        _set(id, combined);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForUser = false;
        });
      }
    }
  }

  Future<void> _date(String id) async {
    if (_busy) return;
    DateTime initial = DateTime.now();
    try {
      initial = id == 'cvDob'
          ? (DateTime.tryParse(_c(id).text) ?? DateTime.now())
          : parseDocumentDate(_c(id).text);
    } catch (_) {}
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(id == 'cvDob' ? 1900 : 2000),
      lastDate: id == 'cvDob' ? DateTime.now() : DateTime(2100, 12, 31),
    );
    if (d == null || !_active) return;
    final value =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    _c(id).text = value;
    _set(id, value);
  }

  Future<void> _useCv() async {
    if (_busy || !_active) return;
    setState(() => _busy = true);
    try {
      final raw = await _store.read(_owner!, 'CV / Resume');
      if (!mounted || !_active) return;
      if (raw == null) {
        setState(
          () => _notice = 'Create and save CV details on this device first.',
        );
        return;
      }
      final cv = GuidedDocument.decode('CV / Resume', raw);
      setState(() => _waitingForUser = true);
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: Text(c.tr('Use these CV details?')),
          content: Text(
            [
              cv.v('name'),
              cv.v('email'),
              cv.v('phone'),
              ...cv.education.map(cvEducationSummary),
              cv.v('skills'),
              ...cv.experience,
            ].where((s) => s.isNotEmpty).join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(c.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(c.tr('Use details')),
            ),
          ],
        ),
      );
      if (!mounted || !_active || yes != true) return;
      for (final entry in {
        'name': cv.v('name'),
        'email': cv.v('email'),
        'phone': cv.v('phone'),
        'qualification': [
          ...cv.education.map(cvEducationSummary),
          cv.v('skills'),
        ].where((s) => s.isNotEmpty).join('\n'),
        'experience': cv.v('noExperience') == 'yes'
            ? ''
            : cv.experience.join('\n'),
      }.entries) {
        final limit = _doc.fields.where((f) => f.id == entry.key).first.max;
        if (entry.value.length > limit) continue;
        _c(entry.key).text = entry.value;
        _doc.values[entry.key] = entry.value;
        _doc.values.remove('_pick_${entry.key}');
        _doc.values.remove('_other_${entry.key}');
        _fields['_custom_${entry.key}']?.text = entry.value;
      }
      _doc.values['_entry'] = 'form';
      _changed();
    } catch (_) {
      if (_active) {
        setState(
          () => _notice = 'Saved CV details could not be loaded. You can type them instead.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForUser = false;
        });
      }
    }
  }

  Future<void> _photo() async {
    if (_busy || !_active) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final photo =
          await (widget.photoPicker?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 2000,
                maxHeight: 2000,
                requestFullMetadata: false,
              ));
      if (photo == null || !_active) return;
      if (await photo.length() > 15 * 1024 * 1024) {
        throw const FormatException('photo');
      }
      if (!mounted || !_active) return;
      if (widget.questionReader == null &&
          !await AiEligibilityService.ensure(context)) {
        return;
      }
      if (!mounted || !_active) return;
      final prepared = await PdfScanImages().prepare(
        await photo.readAsBytes(),
        id: 0,
        name: photo.name,
      );
      final bytes = await ScanImage.prepare(prepared.preview);
      if (!mounted || !_active) return;
      final text = widget.questionReader != null
          ? await widget.questionReader!(bytes)
          : (await FirebaseHandwritingGateway(expectedUid: _owner)
                .recognize(bytes, 'auto'))['text'];
      if (!mounted || !_active) return;
      if (text is! String || text.trim().isEmpty) {
        throw const FormatException('photo-text');
      }
      // Review before replacing an existing typed question; no silent truncation.
      setState(() => _waitingForUser = true);
      final reviewed = await showDialog<String>(
        context: context,
        builder: (_) => _QuestionReview(text: text),
      );
      if (!mounted || !_active || reviewed == null) return;
      _c('question').text = reviewed;
      _doc.values['question'] = reviewed;
      _changed();
    } catch (_) {
      if (_active) {
        setState(
          () => _notice = 'Could not read this question photo. Type or paste the question instead.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForUser = false;
        });
      }
    }
  }

  Future<void> _deliver(String action) async {
    if (_busy || !_active || _preview.text.trim().isEmpty) return;
    if (_preview.text.length > 20000) {
      setState(() => _notice = 'Use 20000 characters or fewer.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final LocalFileSaver? saver = action == 'library'
          ? (widget.saver ?? AccountLocalFileSaver.capture())
          : null;
      _persist();
      await _saveWork;
      if (!mounted || !_active) return;
      final bytes = _pdf ??=
          await (widget.pdfBuilder == null &&
                  _doc.type == 'CV / Resume' &&
                  referenceCvDesigns.contains(_doc.design)
              ? CvReferencePdf.build(
                  content: _preview.text,
                  design: _doc.design,
                  color: _doc.v('_cvColor').isEmpty
                      ? 'Teal'
                      : _doc.v('_cvColor'),
                  photo: _doc.cvPhoto.isEmpty
                      ? null
                      : base64Decode(_doc.cvPhoto),
                )
              : (widget.pdfBuilder == null &&
                        _doc.type == 'CV / Resume' &&
                        _doc.design == 'BD Traditional'
                    ? BdCvPdf.build(
                        title: _doc.title,
                        content: _preview.text,
                        photo: _doc.cvPhoto.isEmpty
                            ? null
                            : base64Decode(_doc.cvPhoto),
                      )
                    : (widget.pdfBuilder ?? PdfExportService.buildDocument)(
                        title: _doc.title,
                        content: _preview.text,
                        modern:
                            _doc.type == 'CV / Resume' &&
                            _doc.design == 'Modern',
                      )));
      if (!mounted || !_active) return;
      final name = localFileName(_doc.title, LocalFileKind.pdf);
      final result = action == 'library'
          ? await saveLocalCopy(
              saver!,
              name,
              LocalFileKind.pdf,
              bytes,
              'Document Maker',
            )
          : action == 'share'
          ? await (widget.files ?? DevicePdfFileActions()).share(bytes, name)
          : await (widget.files ?? DevicePdfFileActions()).save(bytes, name);
      if (!mounted || !_active) return;
      setState(
        () => _notice = switch (result) {
          PdfDelivery.saved =>
            action == 'library'
                ? 'Saved to Library on this device.'
                : 'PDF copy saved.',
          PdfDelivery.downloadRequested =>
            'PDF download requested. Check Downloads before leaving.',
          PdfDelivery.shareOpened =>
            'PDF share sheet opened. Finish sharing before leaving.',
          PdfDelivery.cancelled => 'Cancelled. Your draft is kept.',
        },
      );
    } catch (e) {
      if (_active) {
        setState(
          () => _notice = action == 'library' ? localSaveFailure(e) : 'Unable to export PDF. Your draft is kept. Try shorter paragraphs.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForUser = false;
        });
      }
    }
  }

  Widget _field(GuidedField field) {
    final date = ['start', 'end', 'date', 'cvDob'].contains(field.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('guided-${field.id}'),
        controller: _c(field.id),
        enabled: !_busy,
        readOnly: date,
        onTap: date ? () => _date(field.id) : null,
        minLines: field.multiline ? 3 : 1,
        maxLines: field.multiline ? 5 : 1,
        maxLength: field.max,
        decoration: InputDecoration(
          labelText: '${context.tr(field.label)}${field.required ? ' *' : ''}',
          hintText: context.tr(field.hint),
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          suffixIcon: date
              ? const Icon(Icons.calendar_month)
              : IconButton(
                  tooltip: context.tr('Say your details'),
                  onPressed: _busy ? null : () => _voice(field.id, field.max),
                  icon: const Icon(Icons.mic_none),
                ),
        ),
        onChanged: (v) => _set(field.id, v),
        validator: (value) => field.required && (value ?? '').trim().isEmpty
            ? context.tr('This field is required.')
            : ((value ?? '').length > field.max
                  ? context.tr('Shorten this field.')
                  : null),
      ),
    );
  }

  Widget _repeat(bool education) {
    final inputs = education ? _education : _experience,
        data = education ? _doc.education : _doc.experience;
    final label = education ? 'Education' : 'Experience';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr(label), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < inputs.length; i++)
          if (education && readCvEducation(data[i]) != null)
            Card(
              child: ListTile(
                title: Text(cvEducationSummary(data[i])),
                subtitle: Text(context.tr('Tap to edit education details')),
                onTap: _busy ? null : () => _editEducation(i),
                trailing: IconButton(
                  tooltip: context.tr('Remove'),
                  onPressed: _busy
                      ? null
                      : () {
                          final old = inputs.removeAt(i);
                          data.removeAt(i);
                          _changed();
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => old.dispose(),
                          );
                        },
                  icon: const Icon(Icons.close),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                key: ValueKey(inputs[i]),
                controller: inputs[i],
                enabled: !_busy,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: '${context.tr(label)} ${i + 1}',
                  hintText: context.tr(
                    education
                        ? 'Qualification, institution and year'
                        : 'Job title, company, dates and what you did',
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: IconButton(
                    tooltip: context.tr('Say your details'),
                    icon: const Icon(Icons.mic_none),
                    onPressed: _busy
                        ? null
                        : () => _voice(
                            '',
                            500,
                            target: inputs[i],
                            onAccepted: (value) {
                              data[i] = value;
                              _changed();
                            },
                          ),
                  ),
                  suffixIcon: IconButton(
                    tooltip: context.tr('Remove'),
                    onPressed: _busy
                        ? null
                        : () {
                            final old = inputs.removeAt(i);
                            data.removeAt(i);
                            _changed();
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => old.dispose(),
                            );
                          },
                    icon: const Icon(Icons.close),
                  ),
                ),
                onChanged: (v) {
                  data[i] = v;
                  _changed();
                },
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
        if (inputs.length < 8)
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () {
                    if (education) {
                      _addEducation();
                    } else {
                      inputs.add(TextEditingController());
                      data.add('');
                      _changed();
                    }
                  },
            icon: const Icon(Icons.add),
            label: Text(
              context.tr(education ? 'Add education' : 'Add experience'),
            ),
          ),
      ],
    );
  }

  Widget _invoiceItems() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Items and prices'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      for (var i = 0; i < _items.length; i++)
        Card(
          key: ObjectKey(_items[i]),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${context.tr('Item')} ${i + 1}')),
                    if (_items.length > 1)
                      IconButton(
                        tooltip: context.tr('Remove'),
                        onPressed: _busy
                            ? null
                            : () {
                                final old = _items.removeAt(i);
                                _doc.items.removeAt(i);
                                _changed();
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  for (final c in old.values) {
                                    c.dispose();
                                  }
                                });
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
                if (savedInvoiceProducts(_doc)
                    .any((m) => m['currency'] == _doc.v('currency')))
                  TextButton.icon(
                    onPressed: _busy ? null : () => _chooseProduct(i),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(context.tr('Choose saved item')),
                  ),
                for (final key in ['name', 'quantity', 'rate'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      key: ValueKey(_items[i][key]),
                      controller: _items[i][key],
                      enabled: !_busy,
                      maxLength: key == 'name' ? 120 : 12,
                      keyboardType: key == 'name'
                          ? TextInputType.text
                          : const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                      decoration: InputDecoration(
                        labelText: context.tr(switch (key) {
                          'name' => 'Product or service',
                          'quantity' => 'Quantity',
                          _ => 'Unit price',
                        }),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        _doc.items[i][key] = v;
                        _changed();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (_items.length < 20)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () {
                  final item = {'name': '', 'quantity': '1', 'rate': ''};
                  _doc.items.add(item);
                  _items.add(
                    item.map(
                      (k, v) => MapEntry(k, TextEditingController(text: v)),
                    ),
                  );
                  _changed();
                },
          icon: const Icon(Icons.add),
          label: Text(context.tr('Add another item')),
        ),
      _totals(),
    ],
  );
  Widget _totals() {
    try {
      final t = _doc.invoice,
          currency = _doc.v('currency').isEmpty ? 'BDT' : _doc.v('currency');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in [
              ('Subtotal', t.subtotal),
              ('Discount', t.discount),
              ('Tax', t.tax),
              ('Total', t.total),
            ])
              Text(
                '${context.tr(row.$1)}: $currency ${money(row.$2)}',
                style: TextStyle(
                  fontWeight: row.$1 == 'Total' ? FontWeight.bold : null,
                ),
              ),
          ],
        ),
      );
    } catch (_) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(context.tr('Enter valid items to see the total.')),
      );
    }
  }

  Widget _selectField(GuidedField field) {
    final matches = documentSelections(_doc).where((s) => s.id == field.id);
    if (matches.isNotEmpty) {
      return _selectionControl(matches.first, field: field);
    }
    if (_doc.type == 'Invoice' && field.id == 'buyer') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (savedInvoiceCustomers(_doc).isNotEmpty)
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseCustomer,
              icon: const Icon(Icons.person_search_outlined),
              label: Text(context.tr('Choose saved customer')),
            ),
          _field(field),
        ],
      );
    }
    if (!field.required &&
        !(_doc.type == 'CV / Resume' &&
            ['email', 'phone'].contains(field.id))) {
      return ExpansionTile(
        key: ValueKey('optional-${field.id}'),
        initiallyExpanded: _doc.v(field.id).isNotEmpty,
        title: Text('${context.tr(field.label)} · ${context.tr('Optional')}'),
        children: [_field(field)],
      );
    }
    return _field(field);
  }

  Widget _selectionControl(DocumentSelection spec, {GuidedField? field}) {
    final chosen = selectedOptions(_doc, spec);
    final custom = _fields.putIfAbsent(
      '_custom_${spec.id}',
      () => TextEditingController(text: otherSelectionText(_doc, spec)),
    );
    void update(List<String> options, String other) {
      applyDocumentSelection(_doc, spec, options, other);
      if (spec.id == 'context') {
        final recipient = documentSelections(_doc)
            .firstWhere((s) => s.id == 'recipient');
        final pick = _doc.v('_pick_recipient');
        if (pick.isNotEmpty &&
            !selectedOptions(_doc, recipient).contains('Other') &&
            !recipient.options.contains(_doc.v('recipient')) &&
            !recipient.options.any(
              (p) =>
                  AppStrings.text(p, _doc.bn ? 'bn' : 'en') ==
                  _doc.v('recipient'),
            )) {
          _doc.values['recipient'] = '';
          _doc.values.remove('_pick_recipient');
          _doc.values.remove('_other_recipient');
        }
      }
      _changed();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.tr(spec.label)}${spec.required ? ' *' : ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final option in spec.options)
                FilterChip(
                  key: ValueKey('select-${spec.id}-$option'),
                  label: Text(
                    context.tr(
                      spec.id == 'noExperience'
                          ? (option == 'yes'
                                ? 'No work experience'
                                : 'Have work experience')
                          : option,
                    ),
                  ),
                  selected: chosen.contains(option),
                  onSelected: _busy
                      ? null
                      : (selected) {
                          final next = spec.multiple
                              ? List<String>.of(chosen)
                              : <String>[];
                          if (selected) {
                            next.add(option);
                          } else {
                            next.remove(option);
                          }
                          update(next, custom.text);
                        },
                ),
            ],
          ),
          if (chosen.contains('Other'))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextFormField(
                key: ValueKey('guided-${spec.id}'),
                controller: custom,
                enabled: !_busy,
                minLines: field?.multiline == true ? 2 : 1,
                maxLines: field?.multiline == true ? 4 : 1,
                maxLength: field?.max ?? 120,
                decoration: InputDecoration(
                  labelText: context.tr('Write your own detail'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: context.tr('Say your details'),
                    onPressed: _busy
                        ? null
                        : () => _voice(
                            '',
                            field?.max ?? 120,
                            target: custom,
                            onAccepted: (value) => update(chosen, value),
                          ),
                    icon: const Icon(Icons.mic_none),
                  ),
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? context.tr('This field is required.')
                    : null,
                onChanged: (value) => update(chosen, value),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editEducation(int index) async {
    final row = _education[index];
    final text = await showDialog<String>(
      context: context,
      builder: (_) => EducationDetailsDialog(
        language: _doc.language,
        initial: readCvEducation(_doc.education[index]),
      ),
    );
    if (!_active || text == null || !_education.contains(row)) return;
    final current = _education.indexOf(row);
    row.text = text;
    _doc.education[current] = text;
    _changed();
  }

  Future<void> _addCvPhoto() async {
    if (_busy || !_active) return;
    setState(() => _busy = true);
    try {
      final file =
          await (widget.photoPicker?.call() ??
              ImagePicker().pickImage(source: ImageSource.gallery));
      if (file == null || !_active) return;
      if (await file.length() > PdfScanImages.maxInputBytes) {
        throw const FormatException('cv-photo-size');
      }
      final bytes = await prepareCvPhoto(await file.readAsBytes());
      if (!_active) return;
      _doc.cvPhoto = base64Encode(bytes);
      _pdf = null;
      _schedule();
      setState(() {});
    } catch (_) {
      if (_active) {
        setState(
          () => _notice =
              'Could not open this photo. Try a JPG or PNG under 15 MB.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addEducation() async {
    if (_busy || !_active || _education.length >= 8) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => EducationDetailsDialog(language: _doc.language),
    );
    if (!_active || text == null) return;
    _education.add(TextEditingController(text: text));
    _doc.education.add(text);
    _changed();
  }

  void _rememberInvoice() {
    try {
      if (_doc.validation() != null || selectionValidation(_doc) != null) {
        throw const FormatException();
      }
      rememberInvoiceChoices(_doc);
      _schedule();
      setState(() => _notice = 'Customer and items remembered on this device.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Customer and items remembered on this device.'),
          ),
        ),
      );
    } catch (_) {
      setState(
        () => _notice = 'Complete the invoice details before remembering them.',
      );
    }
  }

  Future<void> _chooseCustomer() async {
    final customer = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(c.tr('Choose saved customer')),
        children: [
          for (final name in savedInvoiceCustomers(_doc))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (!_active || customer == null) return;
    _c('buyer').text = customer;
    _set('buyer', customer);
  }

  Future<void> _chooseProduct(int i) async {
    final row = _items[i];
    final currency = _doc.v('currency');
    final product = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(c.tr('Choose saved item')),
        children: [
          for (final item in savedInvoiceProducts(
            _doc,
          ).where((m) => m['currency'] == currency))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, item),
              child: Text('${item['name']} · $currency ${item['rate']}'),
            ),
        ],
      ),
    );
    if (!_active ||
        product == null ||
        !_items.contains(row) ||
        _doc.v('currency') != currency) {
      return;
    }
    final index = _items.indexOf(row);
    for (final key in ['name', 'rate']) {
      row[key]!.text = product[key]!;
      _doc.items[index][key] = product[key]!;
    }
    _changed();
  }

  Widget _cvReviewSection(IconData icon, Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

  List<Widget> _cvReview() => [
    Text(context.tr('Choose what you know, then preview your CV.')),
    const SizedBox(height: 16),
    _cvReviewSection(
      Icons.auto_awesome_outlined,
      _selectField(_doc.fields.firstWhere((f) => f.id == 'skills')),
    ),
    _cvReviewSection(
      Icons.translate,
      _selectField(_doc.fields.firstWhere((f) => f.id == 'languages')),
    ),
    Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      child: ExpansionTile(
        key: const ValueKey('cv-extra-details'),
        leading: const Icon(Icons.add_circle_outline),
        title: Text(context.tr('Add more to your CV')),
        subtitle: Text(context.tr('Optional — you can skip this')),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final id in [
            'cvObjective',
            'projects',
            'cvHobbies',
            'cvReferences',
          ]) ...[
            _selectField(_doc.fields.firstWhere((f) => f.id == id)),
            if (id == 'cvObjective')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          final text = _doc.label(
                            'I am seeking an opportunity to contribute my skills, learn through practical work and support the goals of the organisation.',
                            'নিজের দক্ষতা কাজে লাগিয়ে বাস্তব অভিজ্ঞতা অর্জন এবং প্রতিষ্ঠানের লক্ষ্য পূরণে অবদান রাখার সুযোগ চাই।',
                          );
                          _c('cvObjective').text = text;
                          _set('cvObjective', text);
                        },
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('Use a simple career objective')),
                ),
              ),
          ],
          const Divider(),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _doc.v('_cvDeclaration') == 'yes',
            title: Text(context.tr('Include a declaration and signature line')),
            onChanged: _busy
                ? null
                : (value) =>
                      _set('_cvDeclaration', value == true ? 'yes' : 'no'),
          ),
        ],
      ),
    ),
    _cvReviewSection(Icons.description_outlined, _language()),
  ];

  List<Widget> _stepContent() {
    final type = _doc.type, step = _doc.step;
    if (type == 'CV / Resume' && step == 2) return _cvReview();
    return [
      for (final spec in documentSelections(_doc).where(
        (spec) => spec.step == step && !_doc.fields.any((f) => f.id == spec.id),
      ))
        _selectionControl(spec),
      if (step == 0 && type == 'Job Application')
        OutlinedButton.icon(
          onPressed: _busy ? null : _useCv,
          icon: const Icon(Icons.badge_outlined),
          label: Text(context.tr('Use saved CV details')),
        ),
      if (_doc.v('_assisted') != 'yes')
        for (final f in _doc.fields.where((f) => f.step == step))
          _selectField(f)
      else ...[
        for (final f in _doc.fields.where(
          (f) => f.step == step && _needsAnswer(f),
        ))
          _selectField(f),
        if (_doc.fields.any((f) => f.step == step && !_needsAnswer(f)))
          ExpansionTile(
            title: Text(context.tr('View or change other details')),
            children: [
              for (final f in _doc.fields.where(
                (f) => f.step == step && !_needsAnswer(f),
              ))
                _selectField(f),
            ],
          ),
      ],
      if (step == 0 && type != 'Invoice')
        TextButton.icon(
          onPressed: _busy
              ? null
              : () {
                  _doc.values['_entry'] = 'quick';
                  setState(() {});
                  _top();
                  _persist();
                },
          icon: const Icon(Icons.mic_none),
          label: Text(context.tr('Write or say it instead')),
        ),
      if (step == 0 && type == 'Assignment') ...[
        OutlinedButton.icon(
          onPressed: _busy ? null : _photo,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(context.tr('Read question from a photo')),
        ),
        Text(
          context.tr(
            'Photo reading uses the scan allowance and may save a transcription in your cloud Library. Review the text before using it.',
          ),
        ),
      ],
      if (step == 0 && type == 'CV / Resume') ...[
        if (_doc.cvPhoto.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Image.memory(
              base64Decode(_doc.cvPhoto),
              width: 85,
              height: 110,
              fit: BoxFit.contain,
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _addCvPhoto,
              icon: const Icon(Icons.portrait_outlined),
              label: Text(context.tr('Add or change CV photo (optional)')),
            ),
            if (_doc.cvPhoto.isNotEmpty)
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        _doc.cvPhoto = '';
                        _pdf = null;
                        setState(() {});
                        _schedule();
                      },
                child: Text(context.tr('Remove photo')),
              ),
          ],
        ),
        Text(
          context.tr(
            'Your CV photo stays in this device draft and PDF. It is not sent to the writing AI.',
          ),
        ),
      ],
      if (step == 2 && type == 'CV / Resume') ...[
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  final text = _doc.label(
                    'I am seeking an opportunity to contribute my skills, learn through practical work and support the goals of the organisation.',
                    'নিজের দক্ষতা কাজে লাগিয়ে বাস্তব অভিজ্ঞতা অর্জন এবং প্রতিষ্ঠানের লক্ষ্য পূরণে অবদান রাখার সুযোগ চাই।',
                  );
                  _c('cvObjective').text = text;
                  _set('cvObjective', text);
                },
          child: Text(context.tr('Use a simple career objective')),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _doc.v('_cvDeclaration') == 'yes',
          title: Text(context.tr('Include a declaration and signature line')),
          onChanged: _busy
              ? null
              : (value) => _set('_cvDeclaration', value == true ? 'yes' : 'no'),
        ),
      ],
      if (step == 1 && type == 'CV / Resume') ...[
        _repeat(true),
        const SizedBox(height: 20),
        if (_doc.v('noExperience') == 'no') _repeat(false),
      ],
      if (step == 1 && type == 'Invoice') _invoiceItems(),
      if (step == 1 &&
          type == 'Leave Application' &&
          _doc.v('start').isNotEmpty &&
          _doc.v('end').isNotEmpty)
        Builder(
          builder: (c) {
            try {
              return Text(
                c.tr('Leave duration: {count} calendar day(s)', {
                  'count': leaveDays(_doc.v('start'), _doc.v('end')),
                }),
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          },
        ),
      if (step == 2) ...[
        if (type == 'Invoice') ...[
          ExpansionTile(
            title: Text(context.tr('Discount and tax (optional)')),
            children: [
              _field(
                const GuidedField(
                  'discount',
                  'Discount amount',
                  'Optional: 0',
                  max: 12,
                ),
              ),
              _field(
                const GuidedField(
                  'tax',
                  'Tax rate (%)',
                  'Optional: 0 to 100',
                  max: 6,
                ),
              ),
            ],
          ),
          _totals(),
          OutlinedButton.icon(
            onPressed: _busy ? null : _rememberInvoice,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(context.tr('Remember customer and items')),
          ),
        ],
        if (type == 'CV / Resume')
          Text(
            context.tr(
              'Only information you provide will appear. No experience or qualifications will be invented.',
            ),
          ),
        if (type == 'Assignment')
          Text(
            context.tr(
              'This is a suggested outline you can change. Review facts and verify sources before submitting your work.',
            ),
          ),
        _language(),
        ExpansionTile(
          title: Text(context.tr('Check the details you entered')),
          childrenPadding: const EdgeInsets.all(12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final field in _doc.fields.where(
              (field) => _doc.v(field.id).isNotEmpty,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(
                  '${context.tr(field.label)}: ${_doc.v(field.id)}',
                ),
              ),
            if (_doc.education.any((s) => s.trim().isNotEmpty))
              SelectableText(
                '${context.tr('Education')}: ${_doc.education.where((s) => s.trim().isNotEmpty).join('\n')}',
              ),
            if (_doc.v('noExperience') != 'yes' &&
                _doc.experience.any((s) => s.trim().isNotEmpty))
              SelectableText(
                '${context.tr('Experience')}: ${_doc.experience.where((s) => s.trim().isNotEmpty).join('\n')}',
              ),
            if (_doc.type == 'Invoice')
              for (final item in _doc.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(
                    '${item['name']} · ${item['quantity']} × ${_doc.v('currency')} ${item['rate']}',
                  ),
                ),
          ],
        ),
      ],
    ];
  }

  Widget _language() => DropdownButtonFormField<String>(
    key: const ValueKey('guided-language'),
    initialValue: _doc.language,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: context.tr('Document Language'),
      border: const OutlineInputBorder(),
    ),
    items: ['Bangla', 'English']
        .map((s) => DropdownMenuItem(value: s, child: Text(context.tr(s))))
        .toList(),
    onChanged: _busy
        ? null
        : (v) {
            if (v != null) {
              _doc.language = v;
              syncSelectionLanguage(_doc);
              if (_doc.v('title').isEmpty) _fields['title']?.text = _doc.title;
              _changed();
            }
          },
  );
  bool _needsAnswer(GuidedField field) =>
      _doc.v('_missing').split(',').contains(field.id);

  Widget _quickEntry() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Write or say your details'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'Tell Jiggo what you need in your own words. You will check the details before they enter your form.',
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const ValueKey('guided-quick-input'),
        controller: _c('_input'),
        enabled: !_busy,
        minLines: 5,
        maxLines: 8,
        maxLength: 2000,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.tr('Your details'),
          hintText: context.tr(_quickExample),
        ),
        onChanged: (value) {
          _doc.values['_input'] = value;
          _schedule();
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : () => _voice('_input', 2000),
          icon: const Icon(Icons.mic_none),
          label: Text(context.tr('Say your details')),
        ),
      ),
      FilledButton.icon(
        key: const ValueKey('guided-arrange'),
        onPressed: _busy ? null : _arrange,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: Text(context.tr('Arrange my details')),
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'Arranging details uses one AI request. Creating an AI draft uses another. Both count towards your daily document limit.',
        ),
      ),
      if (_doc.type == 'Job Application')
        OutlinedButton.icon(
          onPressed: _busy ? null : _useCv,
          icon: const Icon(Icons.badge_outlined),
          label: Text(context.tr('Use saved CV details')),
        ),
      TextButton(
        key: const ValueKey('guided-manual'),
        onPressed: _busy
            ? null
            : () {
                _doc.values['_entry'] = 'form';
                setState(() {});
                _top();
                _persist();
              },
        child: Text(context.tr('Fill in the form myself')),
      ),
    ],
  );
  String get _quickExample => switch (_doc.type) {
    'CV / Resume' => 'For example: My name is Rina. I finished HSC in 2022. I can use Photoshop. This is my first job. My email is rina@example.com.',
    'Job Application' => 'For example: I am applying for a sales assistant job at Sample Shop. I finished HSC and have one year of shop experience. My name is Rina.',
    'Leave Application' => 'For example: I am Rina, a student at Sample College. I need leave from 20 to 22 November 2026 because I am ill. Write to the principal.',
    'Formal Letter' => 'For example: My name is Rina. Write to my landlord to request a repair to the kitchen tap.',
    _ => 'For example: I need a college Biology assignment explaining photosynthesis, about 500 words. My teacher asked for an introduction and examples.',
  };
  Future<void> _arrange() async {
    if (_busy || !_active) return;
    final input = _c('_input').text.trim();
    if (input.length < 10 || input.length > 2000) {
      setState(
        () => _notice = 'Write a few details first (10 to 2000 characters).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (widget.detailsGateway == null &&
          !await AiEligibilityService.ensure(context)) {
        return;
      }
      if (!_active) return;
      final response = input == _detailsInput && _detailsResponse != null
          ? _detailsResponse!
          : await (widget.detailsGateway ??
                    FirebaseDocumentDetailsGateway(_owner!))
                .extract(_doc, input);
      if (!mounted || !_active) return;
      final proposal = DocumentDetails.parse(_doc, response['details']);
      _detailsInput = input;
      _detailsResponse = response;
      final candidate = proposal.proposed(_doc);
      _remaining = (response['remainingToday'] as num?)?.toInt();
      final fieldLabels = {
        for (final f in _doc.fields) f.id: f.label,
        'mode': 'Which describes you?',
        'noExperience': 'I have no work experience',
        'context': 'Where do you need leave?',
        'purpose': 'Letter type',
        'length': 'Approximate word count',
      };
      setState(() => _waitingForUser = true);
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: Text(c.tr('Check the suggested details')),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.tr(
                  'AI can misunderstand. Accept only if these details are yours. Existing matching fields will be replaced.',
                ),
              ),
              const SizedBox(height: 12),
              for (final e in proposal.values.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SelectableText(
                    '${c.tr(fieldLabels[e.key] ?? e.key)}: ${['mode', 'context', 'purpose', 'length', 'noExperience'].contains(e.key) ? c.tr(e.key == 'noExperience' ? (e.value == 'yes' ? 'Yes' : 'No') : e.value) : e.value}',
                  ),
                ),
              if (proposal.education.isNotEmpty)
                SelectableText(
                  '${c.tr('Education')}: ${proposal.education.join('\n')}',
                ),
              if (proposal.experience.isNotEmpty)
                SelectableText(
                  '${c.tr('Experience')}: ${proposal.experience.join('\n')}',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(c.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(c.tr('Use these details')),
            ),
          ],
        ),
      );
      if (!_active || accepted != true) return;
      final old = [
        ..._fields.values,
        ..._education,
        ..._experience,
        ..._items.expand((m) => m.values),
      ];
      _fields.clear();
      _education.clear();
      _experience.clear();
      _items.clear();
      _doc = candidate;
      _doc.values['_assisted'] = 'yes';
      _doc.step = 2;
      for (var i = 0; i < 3; i++) {
        if (selectionValidation(_doc, step: i) != null ||
            _doc.validation(onlyStep: i) != null) {
          _doc.step = i;
          break;
        }
      }
      if (_doc.type == 'Assignment' && _doc.v('outline').isEmpty) {
        _doc.values['outline'] = _doc.label(
          'Introduction\nMain discussion\nExamples\nConclusion\nVerified sources (if available)',
          'ভূমিকা\nমূল আলোচনা\nউদাহরণ\nউপসংহার\nযাচাই করা সূত্র (থাকলে)',
        );
      }
      final missing = _doc.fields
          .where((f) => f.required && _doc.v(f.id).isEmpty)
          .map((f) => f.id)
          .toSet();
      if (_doc.type == 'CV / Resume' &&
          _doc.v('email').isEmpty &&
          _doc.v('phone').isEmpty) {
        missing.addAll(['email', 'phone']);
      }
      if (_doc.type == 'Leave Application' &&
          _doc.validation(onlyStep: 1) != null) {
        missing.addAll(['start', 'end']);
      }
      _doc.values['_missing'] = missing.join(',');
      _form = GlobalKey<FormState>();
      _fillInputs();
      _pdf = null;
      setState(
        () => _notice = _doc.validation() != null
            ? 'Fill in the missing details below.'
            : 'Details added. Review them before creating your document.',
      );
      _top();
      _persist();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in old) {
          controller.dispose();
        }
      });
    } on FirebaseFunctionsException catch (e) {
      if (_active) {
        setState(
          () => _notice =
              aiSafetyMessage(e.details) ??
              (e.code == 'resource-exhausted'
                  ? aiLimitMessage(e.details)
                  : 'Could not arrange your details. Your text and form are kept. Try again or fill in the form yourself.'),
        );
      }
    } catch (_) {
      if (_active) {
        setState(
          () => _notice = 'Could not arrange your details. Your text and form are kept. Try again or fill in the form yourself.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForUser = false;
        });
      }
    }
  }

  Widget _previewContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(
        const GuidedField(
          'title',
          'Document Title',
          'You can change the automatic title',
          max: 150,
        ),
      ),
      if (_doc.type == 'CV / Resume')
        DropdownButtonFormField<String>(
          key: const ValueKey('cv-design'),
          initialValue: _doc.design,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.tr('CV design'),
            border: const OutlineInputBorder(),
          ),
          items:
              [
                    'Modern Sidebar',
                    'BD Classic',
                    'BD Traditional',
                    'Simple',
                    'Modern',
                  ]
                  .map(
                    (s) =>
                        DropdownMenuItem(value: s, child: Text(context.tr(s))),
                  )
                  .toList(),
          onChanged: _busy
              ? null
              : (v) {
                  if (v != null) {
                    setState(() => _doc.design = v);
                    _pdf = null;
                    _schedule();
                  }
                },
        ),
      if (_doc.type == 'CV / Resume' &&
          _doc.cvPhoto.isNotEmpty &&
          !['BD Traditional', ...referenceCvDesigns].contains(_doc.design))
        Text(
          context.tr(
            'Photos are included in Modern Sidebar, BD Classic and BD Traditional.',
          ),
        ),
      const SizedBox(height: 16),
      if (_doc.type != 'Invoice')
        ExpansionTile(
          title: Text(context.tr('Edit draft text')),
          children: [
            TextField(
              key: const ValueKey('guided-preview-text'),
              controller: _preview,
              enabled: !_busy,
              minLines: 8,
              maxLines: 18,
              maxLength: 20000,
              onChanged: (value) {
                _doc.preview = value;
                _pdf = null;
                _schedule();
                setState(() {});
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                helperText: context.tr(
                  'Changes here are included in your PDF.',
                ),
              ),
            ),
          ],
        ),
      if (_doc.type == 'CV / Resume' && _doc.design == 'Modern Sidebar')
        Wrap(
          spacing: 8,
          children: [
            for (final name in cvPalette.keys)
              ChoiceChip(
                key: ValueKey('cv-color-$name'),
                label: Text(context.tr(name)),
                avatar: CircleAvatar(
                  radius: 7,
                  backgroundColor: Color(cvPalette[name]!),
                ),
                selected:
                    (_doc.v('_cvColor').isEmpty
                        ? 'Teal'
                        : _doc.v('_cvColor')) ==
                    name,
                onSelected: _busy
                    ? null
                    : (_) {
                        _doc.values['_cvColor'] = name;
                        _pdf = null;
                        setState(() {});
                        _schedule();
                      },
              ),
          ],
        ),
      if (_doc.type == 'CV / Resume' &&
          referenceCvDesigns.contains(_doc.design))
        CvReferencePaper(
          content: _preview.text,
          design: _doc.design,
          color: _doc.v('_cvColor').isEmpty ? 'Teal' : _doc.v('_cvColor'),
          photo: _doc.cvPhoto.isEmpty ? null : base64Decode(_doc.cvPhoto),
        )
      else if (_doc.type == 'CV / Resume' && _doc.design == 'BD Traditional')
        BdCvPaper(
          title: _doc.title,
          content: _preview.text,
          photo: _doc.cvPhoto.isEmpty ? null : base64Decode(_doc.cvPhoto),
        )
      else
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: _doc.design == 'Modern' && _doc.type == 'CV / Resume'
                  ? const Color(0xff4355c8)
                  : Colors.grey.shade300,
              width: _doc.design == 'Modern' ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: MarkdownBody(
            data: _preview.text,
            imageBuilder: (uri, title, alt) => Text(alt ?? ''),
            selectable: true,
            styleSheet:
                MarkdownStyleSheet.fromTheme(
                  ThemeData(
                    textTheme: Typography.material2021().englishLike.merge(
                      Typography.material2021().black,
                    ),
                  ),
                ).copyWith(
                  p: const TextStyle(
                    color: Colors.black,
                    fontFamily: 'JiggoSans',
                    fontFamilyFallback: ['JiggoBengali'],
                    fontSize: 14,
                  ),
                  h1: TextStyle(
                    color: _doc.design == 'Modern'
                        ? const Color(0xff4355c8)
                        : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                  h2: TextStyle(
                    color: _doc.design == 'Modern'
                        ? const Color(0xff4355c8)
                        : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  listBullet: const TextStyle(color: Colors.black),
                ),
          ),
        ),
      if (_remaining != null)
        Text(
          context.tr('AI requests remaining today: {count}', {
            'count': _remaining,
          }),
        ),
      if (_doc.type == 'CV / Resume')
        TextButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(context.tr('Improve wording with AI')),
        ),
      if (_doc.aiGenerated)
        AiReportButton(source: 'document', content: _preview.text),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('guided-save-library'),
            onPressed: _busy ? null : () => _deliver('library'),
            icon: const Icon(Icons.library_add_outlined),
            label: Text(context.tr('Save to Library')),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _deliver('download'),
            icon: const Icon(Icons.download),
            label: Text(context.tr('Download PDF')),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _deliver('share'),
            icon: const Icon(Icons.share),
            label: Text(context.tr('Share PDF')),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'Forms and new Library PDFs stay on this device. Download a backup to use them elsewhere.',
        ),
      ),
    ],
  );
  bool _leavingForm = false, _backPending = false;
  Future<void> _back() async {
    if (_busy || _backPending) return;
    _backPending = true;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      if (!_loading && !_loadError && _doc.step > 0) {
        setState(() {
          _doc.step--;
          _form = GlobalKey<FormState>();
        });
        _top();
        _persist();
        return;
      }
      _debounce?.cancel();
      _persist();
      await _saveWork;
      if (!mounted) return;
      if (!_loadError && !_loading && _lastSnapshot == null) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(c.tr('Leave without saving?')),
            content: Text(
              c.tr('Your latest changes could not be saved on this device.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(c.tr('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(c.tr('Leave')),
              ),
            ],
          ),
        );
        if (!mounted || leave != true) return;
      }
      setState(() => _leavingForm = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } finally {
      _backPending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _doc.step;
    final cvReview =
        !_loading &&
        !_loadError &&
        !_quick &&
        _doc.type == 'CV / Resume' &&
        step == 2 &&
        _active;
    if (!_loading && !_loadError && !_active) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr(widget.documentType))),
        body: Center(
          child: Text(
            context.tr('Account changed. Reopen this form to continue.'),
          ),
        ),
      );
    }
    return PopScope(
      canPop: _leavingForm,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _busy ? null : _back),
          title: Text(context.tr(widget.documentType)),
          actions: [
            if (!_loading && !_loadError)
              PopupMenuButton<String>(
                tooltip: context.tr('Document options'),
                enabled: !_busy,
                onSelected: (_) => _fresh(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'new',
                    child: Text(context.tr('Start new')),
                  ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: cvReview
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _back,
                        child: Text(context.tr('Back')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('guided-next'),
                          onPressed: _busy ? null : _next,
                          icon: const Icon(Icons.visibility_outlined),
                          label: Text(context.tr('Preview document')),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(context.tr(_notice ?? 'Unable to load draft.')),
                    TextButton(
                      onPressed: _load,
                      child: Text(context.tr('Retry')),
                    ),
                    if (_owner != null)
                      TextButton(
                        onPressed: _fresh,
                        child: Text(context.tr('Start new')),
                      ),
                  ],
                )
              : Form(
                  key: _form,
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (!_quick) ...[
                        Text(
                          context.tr('Step {number} of 4', {
                            'number': step + 1,
                          }),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: (step + 1) / 4),
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            [
                              'Basic details',
                              'More details',
                              cvReview ? 'Finish your CV' : 'Review details',
                              'Preview',
                            ][step],
                          ),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        if (!cvReview)
                          Text(
                            context.tr(
                              'Your form is kept on this device for this account. You can return later.',
                            ),
                          ),
                        const SizedBox(height: 20),
                      ],
                      if (_busy && !_waitingForUser)
                        const LinearProgressIndicator(),
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(context.tr(_notice!)),
                        ),
                      if (_quick)
                        _quickEntry()
                      else if (step == 3)
                        _previewContent()
                      else
                        ..._stepContent(),
                      const SizedBox(height: 20),
                      if (!cvReview)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (step > 0)
                              OutlinedButton(
                                onPressed: _busy ? null : _back,
                                child: Text(context.tr('Back')),
                              ),
                            if (step < 3 && !_quick)
                              FilledButton(
                                key: const ValueKey('guided-next'),
                                onPressed: _busy ? null : _next,
                                child: Text(
                                  context.tr(
                                    step < 2
                                        ? 'Next'
                                        : [
                                            'CV / Resume',
                                            'Invoice',
                                          ].contains(_doc.type)
                                        ? 'Preview document'
                                        : 'Create draft',
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _QuestionReview extends StatefulWidget {
  final String text;
  const _QuestionReview({required this.text});
  @override
  State<_QuestionReview> createState() => _QuestionReviewState();
}

class _QuestionReviewState extends State<_QuestionReview> {
  late final _text = TextEditingController(text: widget.text);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    scrollable: true,
    title: Text(c.tr('Review the question text')),
    content: TextField(
      controller: _text,
      maxLength: 2000,
      maxLines: 8,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        helperText: c.tr('Correct any reading mistakes before using it.'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: Text(c.tr('Cancel')),
      ),
      FilledButton(
        onPressed: _text.text.trim().isEmpty || _text.text.length > 2000
            ? null
            : () => Navigator.pop(c, _text.text.trim()),
        child: Text(c.tr('Use this text')),
      ),
    ],
  );
}
