import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/app_strings.dart';
import '../services/local_file_store.dart';
import '../services/local_file_saver.dart';
import '../services/local_file_openers.dart';
import '../services/local_file_delivery.dart';
import '../services/pdf_edit_model.dart';
import 'file_editor_screen.dart';
import 'docx_editor_screen.dart';
import 'image_editor_screen.dart';
import 'pdf_editor_screen.dart';

class LocalFileDetailsScreen extends StatefulWidget {
  final LocalFileInfo info;
  final String userId;
  final LocalFileStore store;
  final String? Function()? currentOwner;
  final LocalFileDelivery? delivery;
  const LocalFileDetailsScreen({
    super.key,
    required this.info,
    required this.userId,
    required this.store,
    this.currentOwner,
    this.delivery,
  });
  @override
  State<LocalFileDetailsScreen> createState() => _LocalFileDetailsScreenState();
}

class _LocalFileDetailsScreenState extends State<LocalFileDetailsScreen> {
  Uint8List? _bytes;
  bool _loading = true, _busy = false;
  String? _error, _notice;
  bool get _active =>
      mounted &&
      (widget.currentOwner == null || widget.currentOwner!() == widget.userId);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.store.read(widget.userId, widget.info.id);
      if (_active) setState(() => _bytes = bytes);
    } catch (_) {
      if (_active) {
        setState(
          () => _error = 'Could not open this local file. Try again or restore a downloaded backup.',
        );
      }
    } finally {
      if (_active) setState(() => _loading = false);
    }
  }

  Future<void> _deliver(bool share) async {
    if (!_active || _busy || _bytes == null) return;
    setState(() => _busy = true);
    try {
      final result = await (widget.delivery ?? LocalFileDelivery()).deliver(
        widget.info,
        _bytes!,
        share: share,
      );
      if (_active) {
        setState(
          () => _notice = switch (result) {
            PdfDelivery.saved => 'File copy saved.',
            PdfDelivery.downloadRequested =>
              'Download requested. Check your Downloads folder.',
            PdfDelivery.shareOpened =>
              'Share sheet opened. Finish sharing in the selected app.',
            PdfDelivery.cancelled => 'Cancelled. Your Library copy is kept.',
          },
        );
      }
    } catch (_) {
      if (_active) {
        setState(
          () => _notice = 'Unable to download or share. Your Library copy is kept; try again.',
        );
      }
    } finally {
      if (_active) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    if (!_active || _busy || _bytes == null) return;
    final info = widget.info, bytes = _bytes!;
    final saver = AccountLocalFileSaver(
      store: widget.store,
      expectedOwner: widget.userId,
      currentOwner: widget.currentOwner ?? () => widget.userId,
    );
    final Widget screen = switch (info.kind) {
      LocalFileKind.txt => FileEditorScreen(
        picker: SavedTextPicker(info.name, bytes),
        autoOpen: true,
        library: saver,
      ),
      LocalFileKind.docx => DocxEditorScreen(
        files: SavedDocxFiles(info.name, bytes),
        autoOpen: true,
        library: saver,
      ),
      LocalFileKind.pdf => PdfEditorScreen(
        picker: SavedPdfPicker(info.name, bytes),
        autoOpen: true,
        library: saver,
      ),
      LocalFileKind.png || LocalFileKind.jpg => ImageEditorScreen(
        files: SavedImageFiles(info.name, bytes),
        autoOpen: true,
        library: saver,
      ),
    };
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _preview() {
    final bytes = _bytes!;
    return switch (widget.info.kind) {
      LocalFileKind.pdf => PdfViewer.data(bytes, sourceName: widget.info.name),
      LocalFileKind.png || LocalFileKind.jpg => InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Text(
              context.tr(
                'Image preview unavailable. Download a copy to open it.',
              ),
            ),
          ),
        ),
      ),
      LocalFileKind.txt => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topLeft,
          child: SelectableText(utf8.decode(bytes)),
        ),
      ),
      LocalFileKind.docx => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr(
              'Open in editor to view or edit this DOCX. Save to Library creates a new copy.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    final tooLarge =
        widget.info.kind == LocalFileKind.pdf &&
        widget.info.size > PickedEditPdf.maxBytes;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.info.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      context.tr(
                        'Stored on this device only. Download a backup before clearing app or browser data.',
                      ),
                    ),
                    if (tooLarge)
                      Text(
                        context.tr(
                          'PDFs over 10 MB can be viewed and downloaded, but cannot be reopened in this editor.',
                        ),
                      ),
                    if (_bytes != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy || tooLarge ? null : _edit,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(context.tr('Open in editor')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _deliver(false),
                            icon: const Icon(Icons.download),
                            label: Text(context.tr('Download copy')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _deliver(true),
                            icon: const Icon(Icons.share),
                            label: Text(context.tr('Share file')),
                          ),
                        ],
                      ),
                    if (_notice != null) Text(context.tr(_notice!)),
                    if (_busy) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(context.tr(_error!)),
                            TextButton(
                              onPressed: _load,
                              child: Text(context.tr('Retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _bytes == null
                  ? const SizedBox.shrink()
                  : _preview(),
            ),
          ],
        ),
      ),
    );
  }
}
