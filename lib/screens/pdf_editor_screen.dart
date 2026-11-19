import '../services/local_file_saver.dart';
import '../services/local_file_model.dart';
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
  final LocalFileSaver? library;
  final bool autoOpen;
  final PdfEditPicker? picker;
  final PdfEditEngine? engine;
  final PdfFileActions? files;
  final PdfMarkupEngine? markup;
  const PdfEditorScreen({
    super.key,
    this.library,
    this.autoOpen = false,

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
                  'Save a new PDF copy before leaving. Use Save to Library to keep a copy on this device.',
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

  Future<void> _export(bool share, {bool library = false}) async {
    if (_busy || !_hasPdf) return;
    setState(() => _busy = true);
    try {
      final saver = library
          ? (widget.library ?? AccountLocalFileSaver.capture())
          : null;
      final bytes = await _engine.export(_sources, _plan.pages);
      if (!mounted) return;
      if (bytes.length > 32 * 1024 * 1024) throw const FormatException();
      final filename = editedPdfName(_title.text);
      final result = library
          ? await saveLocalCopy(
              saver!,
              filename,
              LocalFileKind.pdf,
              bytes,
              'PDF Editor',
            )
          : share
          ? await _files.share(bytes, filename)
          : await _files.save(bytes, filename);
      if (!mounted) return;
      setState(() {
        if (result == PdfDelivery.saved) {
          _baseline = _plan.signature;
          _baseTitle = _title.text;
          _notice = library
              ? 'Saved to Library on this device.'
              : 'PDF copy saved.';
        } else if (result == PdfDelivery.downloadRequested) {
          _notice = 'PDF download requested. Check Downloads before leaving.';
        } else if (result == PdfDelivery.shareOpened) {
          _notice = 'PDF share sheet opened. Finish sharing before leaving.';
        } else {
          _notice = 'Cancelled. Your PDF draft is kept.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = library
              ? localSaveFailure(error)
              : 'Could not export PDF. Your draft is kept. Try a smaller PDF.',
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

  Future<void> _help() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(c.tr('PDF editing help')),
      content: SingleChildScrollView(
        child: Text(
          "${c.tr('Arrange PDF pages or add page markup. Existing PDF text and images cannot be changed directly.')}\n\n${c.tr('Page copies may lose bookmarks, links between pages, forms and digital signatures. Keep your original.')}",
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(c.tr('OK'))),
      ],
    ),
  );
  Future<void> _saveMenu() async {
    if (_busy || !_hasPdf) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.tr('Save PDF'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            ListTile(
              key: const ValueKey('local-library-save'),
              leading: const Icon(Icons.library_add_outlined),
              title: Text(c.tr('Save to Library')),
              onTap: () => Navigator.pop(c, 'library'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(c.tr('Save PDF copy')),
              onTap: () => Navigator.pop(c, 'download'),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(c.tr('Share PDF')),
              onTap: () => Navigator.pop(c, 'share'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _export(action == 'share', library: action == 'library');
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _PdfRenameDialog(name: _title.text),
    );
    if (mounted && name != null) setState(() => _title.text = name);
  }

  Future<void> _pagesMenu() async {
    if (_busy || !_hasPdf) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                ((MediaQuery.sizeOf(c).height > 0
                            ? MediaQuery.sizeOf(c).height
                            : View.of(c).physicalSize.height /
                                  View.of(c).devicePixelRatio) -
                        MediaQuery.viewInsetsOf(c).bottom)
                    .clamp(180.0, 1400.0) *
                .78,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.tr('Arrange pages'),
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(c.tr('Choose a page, then an action.')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: List.generate(
                    _plan.pages.length,
                    (i) => ChoiceChip(
                      label: Text('${i + 1}'),
                      selected: _selected == i,
                      onSelected: (_) {
                        setState(() => _selected = i);
                        update(() {});
                      },
                    ),
                  ),
                ),
                const Divider(height: 24),
                for (final entry in <(String, String, IconData, bool)>[
                  ('rotate', 'Rotate page', Icons.rotate_right, true),
                  (
                    'earlier',
                    'Move earlier',
                    Icons.arrow_upward,
                    _selected > 0,
                  ),
                  (
                    'later',
                    'Move later',
                    Icons.arrow_downward,
                    _selected < _plan.pages.length - 1,
                  ),
                  (
                    'delete',
                    'Delete page',
                    Icons.delete_outline,
                    _plan.pages.length > 1,
                  ),
                  ('blank', 'Add blank page', Icons.note_add_outlined, true),
                  ('merge', 'Add PDF / Merge', Icons.merge, true),
                ])
                  ListTile(
                    enabled: entry.$4,
                    leading: Icon(entry.$3),
                    title: Text(c.tr(entry.$2)),
                    onTap: entry.$4 ? () => Navigator.pop(c, entry.$1) : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rotate':
        _edit(() => _plan.rotate(_selected));
      case 'earlier':
        _edit(() {
          _plan.move(_selected, _selected - 1);
          _selected--;
        });
      case 'later':
        _edit(() {
          _plan.move(_selected, _selected + 1);
          _selected++;
        });
      case 'delete':
        _edit(() => _plan.remove(_selected));
      case 'blank':
        await _open(append: true, blank: true);
      case 'merge':
        await _open(append: true);
    }
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
        appBar: AppBar(
          title: Text(context.tr('PDF Editor')),
          actions: [
            if (_hasPdf)
              TextButton(
                onPressed: _busy ? null : _saveMenu,
                child: Text(context.tr('Save')),
              ),
            PopupMenuButton<String>(
              tooltip: context.tr('PDF options'),
              onSelected: (v) {
                if (v == 'open') {
                  _open();
                } else if (v == 'rename') {
                  _rename();
                } else {
                  _help();
                }
              },
              itemBuilder: (c) => [
                if (_hasPdf)
                  PopupMenuItem(
                    value: 'open',
                    enabled: !_busy,
                    child: Text(c.tr('Open PDF')),
                  ),
                if (_hasPdf)
                  PopupMenuItem(
                    value: 'rename',
                    enabled: !_busy,
                    child: Text(c.tr('Rename file')),
                  ),
                PopupMenuItem(value: 'help', child: Text(c.tr('Help'))),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_busy && !_asking) const LinearProgressIndicator(),
              Expanded(
                child: LayoutBuilder(
                  builder: (c, box) => ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      if (!_hasPdf) ...[
                        const SizedBox(height: 48),
                        Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 72,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          context.tr('Open a PDF to start editing'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            'Arrange pages. Add text, images and signatures.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else ...[
                        Text(
                          _title.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: context.tr('Previous page'),
                              onPressed: _busy || _selected == 0
                                  ? null
                                  : () => setState(() => _selected--),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Text(
                                context.tr('Page {number} of {count}', {
                                  'number': _selected + 1,
                                  'count': pages.length,
                                }),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              tooltip: context.tr('Next page'),
                              onPressed: _busy || _selected == pages.length - 1
                                  ? null
                                  : () => setState(() => _selected++),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: (box.maxHeight * .64).clamp(220.0, 650.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: InteractiveViewer(
                                minScale: 1,
                                maxScale: 5,
                                child: SizedBox.expand(
                                  child: _sources[pages[_selected].source]
                                      .preview(
                                        pages[_selected].index,
                                        pages[_selected].turns,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
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
                            IconButton(
                              tooltip: context.tr('Zoom'),
                              onPressed: _busy ? null : _zoom,
                              icon: const Icon(Icons.zoom_in),
                            ),
                          ],
                        ),
                      ],
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(context.tr(_notice!)),
                        ),
                    ],
                  ),
                ),
              ),
              if (!_hasPdf)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _open(),
                      icon: const Icon(Icons.folder_open),
                      label: Text(context.tr('Open PDF')),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _markup,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(context.tr('Edit page')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pagesMenu,
                        icon: const Icon(Icons.view_agenda_outlined),
                        label: Text(context.tr('Arrange pages')),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfRenameDialog extends StatefulWidget {
  final String name;
  const _PdfRenameDialog({required this.name});
  @override
  State<_PdfRenameDialog> createState() => _PdfRenameDialogState();
}

class _PdfRenameDialogState extends State<_PdfRenameDialog> {
  late final _text = TextEditingController(text: widget.name);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_text.text.trim().isNotEmpty && _text.text.length <= 140) {
      Navigator.pop(context, _text.text.trim());
    }
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(c.tr('Rename file')),
    content: TextField(
      controller: _text,
      maxLength: 140,
      decoration: InputDecoration(labelText: c.tr('File title')),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: Text(c.tr('Cancel')),
      ),
      FilledButton(onPressed: _save, child: Text(c.tr('Save'))),
    ],
  );
}
