import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/local_file_store.dart';
import '../screens/all_library_items.dart' show LibrarySort;
import '../screens/local_file_details_screen.dart';

class LocalFilesPanel extends StatefulWidget {
  final String userId, search;
  final LibrarySort sort;
  final LocalFileStore? store;
  final bool compact;
  final bool embedded, showEmpty;
  final VoidCallback? onViewAll;
  final String? Function()? currentOwner;
  const LocalFilesPanel({
    super.key,
    required this.userId,
    this.store,
    this.search = '',
    this.sort = LibrarySort.newest,
    this.compact = false,
    this.embedded = false,
    this.showEmpty = true,
    this.onViewAll,
    this.currentOwner,
  });
  @override
  State<LocalFilesPanel> createState() => _LocalFilesPanelState();
}

class _LocalFilesPanelState extends State<LocalFilesPanel> {
  late LocalFileStore _store;
  StreamSubscription<String>? _changes;
  List<LocalFileInfo> _files = [];
  bool _loading = true, _failed = false, _busy = false;
  int _generation = 0;
  bool get _active =>
      mounted &&
      (widget.currentOwner == null || widget.currentOwner!() == widget.userId);
  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant LocalFilesPanel old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId || old.store != widget.store) {
      _changes?.cancel();
      _files = [];
      _connect();
    }
  }

  void _connect() {
    _store = widget.store ?? deviceLocalFiles;
    _changes = _store.changes(widget.userId).listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (_active) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final files = await _store.list(widget.userId);
      if (_active && generation == _generation) setState(() => _files = files);
    } catch (_) {
      if (_active && generation == _generation) setState(() => _failed = true);
    } finally {
      if (_active && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String text) {
    if (_active) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr(text))));
    }
  }

  Future<void> _rename(LocalFileInfo info) async {
    if (_busy || !_active) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameFileDialog(name: info.name),
    );
    if (name == null || !_active) return;
    setState(() => _busy = true);
    try {
      await _store.rename(widget.userId, info.id, name);
    } catch (_) {
      _message('Could not rename this file. Try again.');
    } finally {
      if (_active) setState(() => _busy = false);
    }
  }

  Future<void> _delete(LocalFileInfo info) async {
    if (_busy || !_active) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete local file?')),
        content: Text(
          context.tr(
            'This removes the Library copy on this device. Downloaded files and your original are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Delete')),
          ),
        ],
      ),
    );
    if (remove != true || !_active) return;
    setState(() => _busy = true);
    try {
      await _store.remove(widget.userId, info.id);
    } catch (_) {
      _message('Could not delete this file. Try again.');
    } finally {
      if (_active) setState(() => _busy = false);
    }
  }

  void _open(LocalFileInfo info) {
    if (!_active || _busy) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LocalFileDetailsScreen(
          info: info,
          userId: widget.userId,
          store: _store,
          currentOwner: widget.currentOwner,
        ),
      ),
    );
  }

  Widget _tile(LocalFileInfo info) {
    final date = DateTime.fromMillisecondsSinceEpoch(info.updated).toLocal();
    final size = info.size < 1024 * 1024
        ? '${(info.size / 1024).ceil()} KB'
        : '${(info.size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return Card(
      child: ListTile(
        key: ValueKey('local-file-${info.id}'),
        leading: Icon(switch (info.kind) {
          LocalFileKind.pdf => Icons.picture_as_pdf_outlined,
          LocalFileKind.png || LocalFileKind.jpg => Icons.image_outlined,
          _ => Icons.description_outlined,
        }),
        title: Text(info.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${info.kind.name.toUpperCase()} · $size · ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        ),
        onTap: _busy ? null : () => _open(info),
        trailing: PopupMenuButton<String>(
          enabled: !_busy,
          tooltip: context.tr('File options'),
          onSelected: (action) {
            if (action == 'rename') {
              _rename(info);
            } else if (action == 'delete') {
              _delete(info);
            } else {
              _open(info);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'open',
              child: Text(context.tr('Open / download / share')),
            ),
            PopupMenuItem(value: 'rename', child: Text(context.tr('Rename'))),
            PopupMenuItem(value: 'delete', child: Text(context.tr('Delete'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    var files = _files
        .where(
          (f) =>
              f.name.toLowerCase().contains(widget.search.trim().toLowerCase()),
        )
        .toList();
    files.sort(
      (a, b) => switch (widget.sort) {
        LibrarySort.newest =>
          b.updated != a.updated
              ? b.updated.compareTo(a.updated)
              : b.id.compareTo(a.id),
        LibrarySort.oldest =>
          a.updated != b.updated
              ? a.updated.compareTo(b.updated)
              : a.id.compareTo(b.id),
        LibrarySort.titleAZ => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        LibrarySort.titleZA => b.name.toLowerCase().compareTo(
          a.name.toLowerCase(),
        ),
      },
    );
    Widget status;
    if (_failed) {
      status = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr(
              'Local storage is unavailable. Allow site storage or check free space, then retry.',
            ),
          ),
          TextButton(onPressed: _load, child: Text(context.tr('Retry'))),
        ],
      );
    } else if (_loading && _files.isEmpty) {
      status = const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      );
    } else if (files.isEmpty) {
      if (!widget.showEmpty) return const SizedBox.shrink();
      status = Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          context.tr(
            widget.search.trim().isEmpty
                ? 'No local files yet. Use Save to Library in an editor or Scan to PDF.'
                : 'No matching files.',
          ),
        ),
      );
    } else {
      status = widget.embedded
          ? Column(children: files.map(_tile).toList())
          : widget.compact
          ? Column(children: files.take(3).map(_tile).toList())
          : ListView.builder(
              itemCount: files.length,
              itemBuilder: (_, i) => _tile(files[i]),
            );
    }
    return Column(
      mainAxisSize: widget.compact || widget.embedded
          ? MainAxisSize.min
          : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact) ...[
          Row(
            children: [
              Expanded(child: Text(context.tr('Local files on this device'))),
              IconButton(
                onPressed: _busy ? null : _load,
                tooltip: context.tr('Refresh'),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            context.tr(
              'These files do not sync to other devices. Download a backup before clearing app or browser data.',
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (widget.compact || widget.embedded)
          status
        else
          Expanded(child: status),
        if (widget.compact && widget.onViewAll != null)
          TextButton.icon(
            onPressed: widget.onViewAll,
            icon: const Icon(Icons.folder_outlined),
            label: Text(context.tr('View all local files')),
          ),
      ],
    );
  }
}

class _RenameFileDialog extends StatefulWidget {
  final String name;
  const _RenameFileDialog({required this.name});
  @override
  State<_RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<_RenameFileDialog> {
  late final _controller = TextEditingController(
    text: widget.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.pop(context, _controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Rename file')),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 140,
      decoration: InputDecoration(labelText: context.tr('File name')),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel')),
      ),
      FilledButton(onPressed: _submit, child: Text(context.tr('Save'))),
    ],
  );
}
