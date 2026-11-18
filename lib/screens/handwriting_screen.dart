import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../services/app_strings.dart';
import '../services/ai_eligibility_service.dart';
import '../services/ai_limit_messages.dart';
import '../services/handwriting_gateway.dart';
import '../services/pdf_scan_image.dart';
import '../services/scan_image.dart';
import '../services/scan_photo_source.dart';
import '../widgets/scan_crop_editor.dart';
import 'handwriting_text_screen.dart';

class HandwritingScreen extends StatefulWidget {
  final ScanPhotoSource? photos;
  final HandwritingGateway? gateway;
  final PdfScanImages? images;
  const HandwritingScreen({super.key, this.photos, this.gateway, this.images});
  @override
  State<HandwritingScreen> createState() => _HandwritingScreenState();
}

class _HandwritingScreenState extends State<HandwritingScreen> {
  late final HandwritingGateway _gateway;
  late final _photos = widget.photos ?? DeviceScanPhotos();
  late final _images = widget.images ?? PdfScanImages();
  PdfScanPage? _photo;
  String _language = 'auto';
  bool _busy = false;
  String? _error;
  int? _remaining;
  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseHandwritingGateway();
  }

  Future<void> _pick(bool camera) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files = await _photos.pick(camera: camera, limit: 1);
      if (files.isEmpty || !mounted) return;
      if (await files.first.length() > PdfScanImages.maxInputBytes) {
        throw const FormatException();
      }
      final photo = await _images.prepare(
        await files.first.readAsBytes(),
        id: 1,
        name: files.first.name,
      );
      if (mounted) {
        setState(() {
          _photo = photo;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Choose a clear JPG, PNG or WebP photo under 15 MB. Check camera or photo permission.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(bool rotate) async {
    if (_busy || _photo == null) return;
    final photo = _photo!;
    setState(() => _busy = true);
    try {
      var crop = photo.crop;
      var turns = photo.quarterTurns;
      if (rotate) {
        turns = (turns + 1) % 4;
        crop = crop.clockwise();
      } else {
        final selection = await Navigator.push<ScanCrop>(
          context,
          MaterialPageRoute<ScanCrop>(
            builder: (_) => ScanCropEditor(page: photo),
          ),
        );
        if (!mounted || selection == null) return;
        crop = crop.within(selection).clamped();
      }
      final edited = await _images.transform(
        photo,
        quarterTurns: turns,
        crop: crop,
      );
      if (mounted) {
        setState(() {
          _photo = edited;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to edit this page. The previous version is kept.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) {
    if (e is FirebaseFunctionsException) {
      final reason = e.details is Map ? (e.details as Map)['reason'] : null;
      if (reason == 'handwriting-unreadable') {
        return 'No readable handwriting found. Take a sharper, closer photo and try again.';
      }
      final safety = aiSafetyMessage(e.details);
      if (safety != null) return safety;
      if (e.code == 'resource-exhausted') return aiLimitMessage(e.details);
      if (e.code == 'unauthenticated') return 'Please log in first.';
      if (e.code == 'not-found') {
        return 'Handwriting service is not available yet. Complete the server setup first.';
      }
      if (e.code == 'deadline-exceeded') {
        return 'The request timed out. Check Library before trying again.';
      }
    }
    return 'Unable to recognize handwriting. Check Library before trying again; a note may already have been saved.';
  }

  Future<void> _recognize() async {
    if (_busy || _photo == null) return;
    final photo = _photo!, language = _language;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.gateway == null &&
          !await AiEligibilityService.ensure(context)) {
        return;
      }
      if (!mounted) return;
      final bytes = await ScanImage.prepare(photo.preview);
      final result = await _gateway.recognize(bytes, language);
      if (!mounted) return;
      final text = result['text'], title = result['title'];
      if (text is! String ||
          text.trim().isEmpty ||
          text.length > 20000 ||
          title is! String) {
        throw const FormatException();
      }
      final id = result['savedToLibrary'] == true
          ? result['documentId'] as String?
          : null;
      setState(() => _remaining = (result['remainingToday'] as num?)?.toInt());
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => HandwritingTextScreen(
            title: title,
            text: text,
            documentId: id,
            gateway: _gateway,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Handwriting Recognition'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr(
              'Turn handwritten Bangla or English notes into editable text. Upload only the page you need; avoid personal details.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('handwriting-camera'),
                onPressed: _busy ? null : () => _pick(true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(context.tr('Take photo')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('handwriting-gallery'),
                onPressed: _busy ? null : () => _pick(false),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(context.tr('Choose photo')),
              ),
            ],
          ),
          if (_photo != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.memory(
                  _photo!.preview,
                  fit: BoxFit.contain,
                  cacheWidth: 1000,
                ),
              ),
            ),
            Wrap(
              children: [
                TextButton.icon(
                  key: const ValueKey('handwriting-crop'),
                  onPressed: _busy ? null : () => _edit(false),
                  icon: const Icon(Icons.crop),
                  label: Text(context.tr('Crop page')),
                ),
                TextButton.icon(
                  key: const ValueKey('handwriting-rotate'),
                  onPressed: _busy ? null : () => _edit(true),
                  icon: const Icon(Icons.rotate_90_degrees_cw),
                  label: Text(context.tr('Rotate page')),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const ValueKey('handwriting-language'),
            initialValue: _language,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr('Handwriting language hint'),
            ),
            items: [
              for (final entry in const {
                'auto': 'Bangla & English',
                'bn': 'Bangla',
                'en': 'English',
              }.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(context.tr(entry.value)),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v != null) setState(() => _language = v);
                  },
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'The selected photo is sent to Jiggo’s AI service only when you press Recognize handwriting.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Text stays in its original language. AI may misread words. Scan & Solve and handwriting share the daily 10-scan allowance.',
            ),
          ),
          if (_remaining != null)
            Text(
              context.tr('Remaining scans today: {count}', {
                'count': _remaining,
              }),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('handwriting-recognize'),
            onPressed: _busy || _photo == null ? null : _recognize,
            child: Text(context.tr('Recognize handwriting')),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Text(
              context.tr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
