import 'pdf_markup_screen.dart';
import '../services/pdf_markup_engine.dart';
import '../services/image_edit_model.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/pdf_edit_engine.dart';
import '../services/pdf_edit_model.dart';
import '../services/pdf_edit_picker.dart';
import '../services/pdf_file_actions.dart';

class PdfEditorScreen extends StatefulWidget {
  final PdfEditPicker? picker;
  final PdfEditEngine? engine;
  final PdfFileActions? files;
  final PdfMarkupEngine? markup;
  const PdfEditorScreen({
    super.key,
    this.picker,
    this.engine,
    this.files,
    this.markup,
  });
  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  late final _picker = widget.picker ?? DevicePdfEditPicker();
  late final _engine = widget.engine ?? DevicePdfEditEngine();
  late final _markupEngine = widget.markup ?? DevicePdfMarkupEngine();
  late final _files = widget.files ?? DevicePdfFileActions();
  final _sources = <PdfEditSource>[];
  final _plan = PdfPagePlan();
  final _title = TextEditingController();
  int _selected = 0, _bytes = 0, _externalSources = 0, _markupBytes = 0;
  bool _busy = false, _leaving = false, _asking = false;
  String? _notice;
  String _baseline = '', _baseTitle = '';
  bool get _hasPdf => _plan.pages.isNotEmpty;
  bool get _dirty =>
      _hasPdf && (_plan.signature != _baseline || _title.text != _baseTitle);
  @override
  void dispose() {
    _title.dispose();
    for (final source in _sources) {
      unawaited(source.close());
    }
    super.dispose();
  }

  Future<bool> _confirm() async {
    if (!_dirty) return true;
    setState(() => _asking = true);
    try {
      return await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(c.tr('Leave this PDF?')),
              content: Text(
                c.tr(
                  'Save a new PDF copy before leaving. This draft is not saved in Library.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text(c.tr('Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(c.tr('Continue')),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  void _edit(VoidCallback action) {
    if (_busy) return;
    setState(() {
      action();
      _selected = _selected.clamp(0, _plan.pages.length - 1);
      _notice = null;
    });
  }

  Future<void> _open({bool append = false, bool blank = false}) async {
    if (_busy) return;
    // Lock before the confirmation/picker so repeated taps cannot open two operations.
    setState(() => _busy = true);
    PdfEditSource? candidate;
    try {
      if (!append && !await _confirm()) return;
      if (!mounted) return;
      if (append && (_externalSources >= 10 || _sources.length >= 30)) {
        throw const FormatException();
      }
      final picked = blank ? null : await _picker.pick();
      if (!mounted || (!blank && picked == null)) return;
      picked?.validate();
      final inputBytes = picked?.bytes.length ?? 0;
      if ((append ? _bytes : 0) + inputBytes > 30 * 1024 * 1024) {
        throw const FormatException();
      }
      candidate = blank ? await _engine.blank() : await _engine.open(picked!);
      if (!mounted) return;
      final count = candidate.pageCount;
      if (count < 1 ||
          count + (append ? _plan.pages.length : 0) > PdfPagePlan.maxPages) {
        throw const FormatException();
      }
      final oldSources = append
          ? <PdfEditSource>[]
          : List<PdfEditSource>.of(_sources);
      setState(() {
        if (!append) {
          _sources.clear();
          _bytes = 0;
          _externalSources = 0;
          _markupBytes = 0;
        }
        final id = _sources.length;
        _sources.add(candidate!);
        final pages = List.generate(count, (i) => EditPdfPage(id, i));
        if (append) {
          _selected = _plan.pages.length;
          _plan.append(pages);
        } else {
          _plan.load(pages);
          _selected = 0;
          _title.text = String.fromCharCodes(
            picked!.name
                .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
                .runes
                .take(100),
          );
          _baseline = _plan.signature;
          _baseTitle = _title.text;
        }
        _bytes += inputBytes;
        _externalSources++;
        _notice = 'Opened a local PDF copy. The original file is unchanged.';
      });
      candidate = null;
      // Let old page-view widgets unmount before disposing their documents.
      await WidgetsBinding.instance.endOfFrame;
      for (final source in oldSources) {
        await source.close();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Could not open this PDF. Use an unencrypted PDF under 10 MB, up to 100 total pages and 10 source files. Your current PDF is kept.',
        );
      }
    } finally {
      await candidate?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(bool share) async {
    if (_busy || !_hasPdf) return;
    setState(() => _busy = true);
    try {
      final bytes = await _engine.export(_sources, _plan.pages);
      if (!mounted) return;
      if (bytes.length > 32 * 1024 * 1024) throw const FormatException();
      final filename = editedPdfName(_title.text);
      final result = share
          ? await _files.share(bytes, filename)
          : await _files.save(bytes, filename);
      if (!mounted) return;
      setState(() {
        if (result == PdfDelivery.saved) {
          _baseline = _plan.signature;
          _baseTitle = _title.text;
          _notice = 'PDF copy saved.';
        } else if (result == PdfDelivery.downloadRequested) {
          _notice = 'PDF download requested. Check Downloads before leaving.';
        } else if (result == PdfDelivery.shareOpened) {
          _notice = 'PDF share sheet opened. Finish sharing before leaving.';
        } else {
          _notice = 'Cancelled. Your PDF draft is kept.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Could not export PDF. Your draft is kept. Try a smaller PDF.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markup() async {
    if (_busy || !_hasPdf) return;
    setState(() => _busy = true);
    PdfEditSource? candidate;
    try {
      if (_sources.length >= 30 || _markupBytes >= 32 * 1024 * 1024) {
        throw const FormatException();
      }
      final entry = _plan.pages[_selected];
      final raster = await _markupEngine.raster(_sources[entry.source], entry);
      if (!mounted) return;
      setState(() => _asking = true);
      final edited = await Navigator.push<EditedImage>(
        context,
        MaterialPageRoute(
          builder: (_) => PdfMarkupScreen(background: raster.image),
        ),
      );
      if (!mounted || edited == null) return;
      setState(() => _asking = false);
      final bytes = await _markupEngine.encode(
        edited,
        raster.widthPoints,
        raster.heightPoints,
      );
      if (_markupBytes + bytes.length > 32 * 1024 * 1024) {
        throw const FormatException();
      }
      candidate = await _engine.open(PickedEditPdf('marked-page.pdf', bytes));
      if (!mounted) return;
      if (candidate.pageCount != 1) throw const FormatException();
      setState(() {
        final id = _sources.length;
        _sources.add(candidate!);
        _plan.replace(_selected, EditPdfPage(id, 0));
        _markupBytes += bytes.length;
        _notice = 'Page markup applied. Save a new PDF copy to keep it.';
      });
      candidate = null;
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Could not apply page markup. Your previous PDF is kept. Save your work and reopen a copy if the editor is full.',
        );
      }
    } finally {
      await candidate?.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _asking = false;
        });
      }
    }
  }

  Future<void> _zoom() async {
    final page = _plan.pages[_selected];
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: Text(c.tr('PDF preview'))),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: SizedBox.expand(
              child: _sources[page.source].preview(page.index, page.turns),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _plan.pages;
    return PopScope(
      canPop: _leaving || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _busy) return;
        if (await _confirm() && mounted) {
          setState(() => _leaving = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('PDF Editor'))),
        body: Column(
          children: [
            if (_busy && !_asking) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    context.tr(
                      'Arrange PDF pages or add page markup. Existing PDF text and images cannot be changed directly.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'Page copies may lose bookmarks, links between pages, forms and digital signatures. Keep your original.',
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
                        label: Text(context.tr('Open PDF')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || !_hasPdf
                            ? null
                            : () => _open(append: true),
                        icon: const Icon(Icons.merge),
                        label: Text(context.tr('Add PDF / Merge')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || !_hasPdf
                            ? null
                            : () => _open(append: true, blank: true),
                        icon: const Icon(Icons.note_add_outlined),
                        label: Text(context.tr('Add blank page')),
                      ),
                    ],
                  ),
                  if (_hasPdf) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _title,
                      enabled: !_busy,
                      maxLength: 140,
                      decoration: InputDecoration(
                        labelText: context.tr('File title'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Text(
                      context.tr('Page {number} of {count}', {
                        'number': _selected + 1,
                        'count': pages.length,
                      }),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: ColoredBox(
                        color: Colors.grey.shade200,
                        child: _sources[pages[_selected].source].preview(
                          pages[_selected].index,
                          pages[_selected].turns,
                        ),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        IconButton(
                          tooltip: context.tr('Previous page'),
                          onPressed: _busy || _selected == 0
                              ? null
                              : () => setState(() => _selected--),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: context.tr('Zoom'),
                          onPressed: _busy ? null : _zoom,
                          icon: const Icon(Icons.zoom_in),
                        ),
                        IconButton(
                          tooltip: context.tr('Next page'),
                          onPressed: _busy || _selected == pages.length - 1
                              ? null
                              : () => setState(() => _selected++),
                          icon: const Icon(Icons.chevron_right),
                        ),
                        IconButton(
                          tooltip: context.tr('Undo'),
                          onPressed: _busy || !_plan.canUndo
                              ? null
                              : () => _edit(_plan.undo),
                          icon: const Icon(Icons.undo),
                        ),
                        IconButton(
                          tooltip: context.tr('Redo'),
                          onPressed: _busy || !_plan.canRedo
                              ? null
                              : () => _edit(_plan.redo),
                          icon: const Icon(Icons.redo),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _markup,
                          icon: const Icon(Icons.edit_note),
                          label: Text(context.tr('Add page markup')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _edit(() => _plan.rotate(_selected)),
                          icon: const Icon(Icons.rotate_right),
                          label: Text(context.tr('Rotate page')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || _selected == 0
                              ? null
                              : () => _edit(() {
                                  _plan.move(_selected, _selected - 1);
                                  _selected--;
                                }),
                          icon: const Icon(Icons.arrow_upward),
                          label: Text(context.tr('Move earlier')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || _selected == pages.length - 1
                              ? null
                              : () => _edit(() {
                                  _plan.move(_selected, _selected + 1);
                                  _selected++;
                                }),
                          icon: const Icon(Icons.arrow_downward),
                          label: Text(context.tr('Move later')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || pages.length == 1
                              ? null
                              : () => _edit(() => _plan.remove(_selected)),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(context.tr('Delete page')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(context.tr('Page order')),
                    Wrap(
                      spacing: 6,
                      children: List.generate(
                        pages.length,
                        (i) => ChoiceChip(
                          label: Text('${i + 1}'),
                          selected: i == _selected,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _selected = i),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _export(false),
                          icon: const Icon(Icons.save_alt),
                          label: Text(context.tr('Save PDF copy')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _export(true),
                          icon: const Icon(Icons.share),
                          label: Text(context.tr('Share PDF')),
                        ),
                      ],
                    ),
                  ],
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(context.tr(_notice!)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
