import '../services/local_file_saver.dart';
import '../services/local_file_model.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../services/app_strings.dart';
import '../services/app_theme.dart';
import '../services/pdf_file_actions.dart';
import '../services/pdf_scan_image.dart';
import '../services/scan_pdf_builder.dart';
import '../services/scan_photo_source.dart';
import '../widgets/scan_crop_editor.dart';

class ScanPdfScreen extends StatefulWidget {
  final LocalFileSaver? library;
  final ScanPhotoSource? photos;
  final PdfScanImages? images;
  final ScanPdfBuilder? builder;
  final PdfFileActions? files;
  const ScanPdfScreen({
    super.key,
    this.library,

    this.photos,
    this.images,
    this.builder,
    this.files,
  });
  @override
  State<ScanPdfScreen> createState() => _ScanPdfScreenState();
}

class _ScanPdfScreenState extends State<ScanPdfScreen> {
  late final _photos = widget.photos ?? DeviceScanPhotos();
  late final _images = widget.images ?? PdfScanImages();
  late final _builder = widget.builder ?? ScanPdfBuilder();
  late final _files = widget.files ?? DevicePdfFileActions();
  final _title = TextEditingController();
  final _pages = <PdfScanPage>[];
  bool _initialized = false, _busy = false, _exported = false;
  int _nextId = 1;
  Uint8List? _pdf;
  String? _filename, _notice;
  Map<String, Object?> _noticeValues = const {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _title.text = context.tr('Scanned document');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  int get _retained => _pages.fold(0, (n, p) => n + p.retainedBytes);
  void _invalidate() {
    _pdf = null;
    _filename = null;
    _exported = false;
    _notice = null;
    _noticeValues = const {};
  }

  void _feedback(String message, [Map<String, Object?> values = const {}]) {
    _notice = message;
    _noticeValues = values;
  }

  Future<void> _pick(bool camera) async {
    if (_busy || _pages.length >= PdfScanImages.maxPages) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _notice = null;
    });
    var added = 0, skipped = 0;
    try {
      final room = PdfScanImages.maxPages - _pages.length;
      final selected = await _photos.pick(camera: camera, limit: room);
      if (!mounted) return;
      skipped = selected.length > room ? selected.length - room : 0;
      for (final file in selected.take(room)) {
        try {
          if (await file.length() > PdfScanImages.maxInputBytes) {
            skipped++;
            continue;
          }
          final page = await _images.prepare(
            await file.readAsBytes(),
            id: _nextId++,
            name: file.name,
          );
          if (!mounted) return;
          if (_retained + page.retainedBytes > PdfScanImages.maxRetainedBytes) {
            skipped++;
            continue;
          }
          setState(() {
            _pages.add(page);
            _invalidate();
          });
          added++;
        } catch (_) {
          skipped++;
        }
      }
      if (mounted && selected.isNotEmpty) {
        setState(
          () => _feedback('Added {added} page(s). Skipped {skipped} file(s).', {
            'added': added,
            'skipped': skipped,
          }),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback(
            'Unable to open photos or camera. Check permission and try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(PdfScanPage page, String action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      var turns = page.quarterTurns;
      var crop = page.crop;
      if (action == 'crop') {
        final selection = await Navigator.push<ScanCrop>(
          context,
          MaterialPageRoute<ScanCrop>(
            builder: (_) => ScanCropEditor(page: page),
          ),
        );
        if (!mounted || selection == null) return;
        if (selection.values.toString() == ScanCrop.full.values.toString()) {
          return;
        }
        crop = crop.within(selection).clamped();
      } else if (action == 'rotate') {
        turns = (turns + 1) % 4;
        crop = crop.clockwise();
      } else {
        turns = 0;
        crop = ScanCrop.full;
      }
      final edited = await _images.transform(
        page,
        quarterTurns: turns,
        crop: crop,
      );
      if (!mounted) return;
      if (_retained - page.retainedBytes + edited.retainedBytes >
          PdfScanImages.maxRetainedBytes) {
        setState(
          () => _feedback(
            'These photos need too much memory. Remove a page or choose smaller photos.',
          ),
        );
        return;
      }
      setState(() {
        _pages[_pages.indexWhere((p) => p.id == page.id)] = edited;
        _invalidate();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback(
            'Unable to edit this page. The previous version is kept.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _move(int from, int to) {
    if (_busy || to < 0 || to >= _pages.length) return;
    setState(() {
      final page = _pages.removeAt(from);
      _pages.insert(to, page);
      _invalidate();
    });
  }

  Future<void> _create() async {
    if (_busy || _pages.isEmpty) return;
    if (_title.text.length > 80) {
      setState(
        () => _feedback('Use 80 characters or fewer for the file name.'),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final title = _title.text.trim().isEmpty
        ? context.tr('Scanned document')
        : _title.text.trim();
    final pages = List<PdfScanPage>.unmodifiable(_pages);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final bytes = await _builder.build(pages, title);
      if (!mounted) return;
      setState(() {
        _pdf = bytes;
        _filename = scanPdfFilename(title);
        _feedback('PDF ready: {count} page(s). Save a copy before leaving.', {
          'count': pages.length,
        });
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _feedback(
            'Unable to create the PDF. Try fewer or smaller photos. Your pages are kept.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver(bool share, {bool library = false}) async {
    if (_busy || _pdf == null || _filename == null) return;
    setState(() => _busy = true);
    try {
      final saver = library
          ? (widget.library ?? AccountLocalFileSaver.capture())
          : null;
      final result = library
          ? await saveLocalCopy(
              saver!,
              _filename!,
              LocalFileKind.pdf,
              _pdf!,
              'Scan to PDF',
            )
          : share
          ? await _files.share(_pdf!, _filename!)
          : await _files.save(_pdf!, _filename!);
      if (!mounted) return;
      setState(() {
        if (result == PdfDelivery.saved ||
            result == PdfDelivery.downloadRequested) {
          _exported = true;
        }
        _feedback(
          library
              ? 'Saved to Library on this device.'
              : switch (result) {
                  PdfDelivery.saved => 'PDF saved successfully.',
                  PdfDelivery.downloadRequested =>
                    'PDF download requested. Check your Downloads folder.',
                  PdfDelivery.shareOpened => 'Share sheet opened. Save a copy if you want to keep this PDF.',
                  PdfDelivery.cancelled =>
                    'Save or sharing was cancelled. Your PDF is still ready.',
                },
        );
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _feedback(
            library ? localSaveFailure(error) : 'Unable to save or share. Your PDF is still ready; try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_pages.isNotEmpty && !_exported) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(context.tr('Leave these pages?')),
          content: Text(
            context.tr(
              'Save a PDF first if you want to keep these pages. Unsaved pages are cleared when you leave.',
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
    if (mounted) Navigator.pop(context);
  }

  void _preview(PdfScanPage page, int number) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(context.tr('Page {number}', {'number': number})),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Image.memory(page.preview, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.pageColor,
    appBar: AppBar(
      leading: BackButton(onPressed: _close),
      title: Text(context.tr('Scan to PDF')),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              buildDefaultDragHandles: false,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      'Create a PDF from photos on this device. No AI request is made.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('scan-pdf-title'),
                    controller: _title,
                    enabled: !_busy,
                    maxLength: 80,
                    maxLengthEnforcement: MaxLengthEnforcement.none,
                    buildCounter: (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => Text('${_title.text.length}/80'),
                    decoration: InputDecoration(
                      labelText: context.tr('PDF file name'),
                    ),
                    onChanged: (_) => setState(_invalidate),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('scan-pdf-camera'),
                        onPressed: _busy || _pages.length >= 20
                            ? null
                            : () => _pick(true),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(context.tr('Take photo')),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('scan-pdf-gallery'),
                        onPressed: _busy || _pages.length >= 20
                            ? null
                            : () => _pick(false),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(context.tr('Add photos')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr(
                      'JPG, PNG or WebP. Up to 20 pages. Very large, damaged or unsupported files are skipped.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('Pages: {count}/20', {'count': _pages.length}),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    context.tr(
                      'Drag the handle or use the arrows to change page order. Tap a photo to zoom.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_busy) const LinearProgressIndicator(),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(context.tr(_notice!, _noticeValues)),
                    ),
                  if (_pages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(context.tr('Add your first page to begin.')),
                    ),
                ],
              ),
              itemCount: _pages.length,
              onReorderItem: (oldIndex, newIndex) => _move(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final page = _pages[index];
                return Card(
                  key: ValueKey(page.id),
                  color: context.cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            InkWell(
                              onTap: _busy
                                  ? null
                                  : () => _preview(page, index + 1),
                              child: Image.memory(
                                page.preview,
                                width: 64,
                                height: 84,
                                fit: BoxFit.contain,
                                cacheWidth: 160,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('Page {number}', {
                                      'number': index + 1,
                                    }),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    page.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              enabled: !_busy,
                              child: Tooltip(
                                message: context.tr('Drag to reorder'),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              key: ValueKey('crop-${page.id}'),
                              tooltip: context.tr('Crop page'),
                              onPressed: _busy
                                  ? null
                                  : () => _edit(page, 'crop'),
                              icon: const Icon(Icons.crop),
                            ),
                            IconButton(
                              key: ValueKey('rotate-${page.id}'),
                              tooltip: context.tr('Rotate page'),
                              onPressed: _busy
                                  ? null
                                  : () => _edit(page, 'rotate'),
                              icon: const Icon(Icons.rotate_90_degrees_cw),
                            ),
                            IconButton(
                              key: ValueKey('reset-${page.id}'),
                              tooltip: context.tr('Reset page'),
                              onPressed: _busy || !page.edited
                                  ? null
                                  : () => _edit(page, 'reset'),
                              icon: const Icon(Icons.restart_alt),
                            ),
                            IconButton(
                              key: ValueKey('up-${page.id}'),
                              tooltip: context.tr('Move page up'),
                              onPressed: _busy || index == 0
                                  ? null
                                  : () => _move(index, index - 1),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              key: ValueKey('down-${page.id}'),
                              tooltip: context.tr('Move page down'),
                              onPressed: _busy || index == _pages.length - 1
                                  ? null
                                  : () => _move(index, index + 1),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              key: ValueKey('remove-${page.id}'),
                              tooltip: context.tr('Remove page'),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _pages.removeAt(index);
                                      _invalidate();
                                    }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('local-library-save'),
                  onPressed: _busy || _pdf == null
                      ? null
                      : () => _deliver(false, library: true),
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(context.tr('Save to Library')),
                ),
                FilledButton.icon(
                  key: const ValueKey('scan-pdf-create'),
                  onPressed: _busy || _pages.isEmpty ? null : _create,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(context.tr('Create PDF')),
                ),
                if (_pdf != null) ...[
                  OutlinedButton(
                    key: const ValueKey('scan-pdf-save'),
                    onPressed: _busy ? null : () => _deliver(false),
                    child: Text(context.tr('Save PDF')),
                  ),
                  OutlinedButton(
                    key: const ValueKey('scan-pdf-share'),
                    onPressed: _busy ? null : () => _deliver(true),
                    child: Text(context.tr('Share PDF')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
