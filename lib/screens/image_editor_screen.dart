import '../services/local_file_saver.dart';
import '../services/local_file_model.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_strings.dart';
import '../services/image_edit_files.dart';
import '../services/image_edit_model.dart';
import '../services/image_edit_processor.dart';
import '../services/pdf_scan_image.dart' show PdfScanPage, ScanCrop;
import '../widgets/scan_crop_editor.dart';
import '../widgets/image_text_editor.dart';

class ImageEditorScreen extends StatefulWidget {
  final LocalFileSaver? library;
  final bool autoOpen;
  final ImageEditFiles? files;
  final ImageEditProcessor processor;
  const ImageEditorScreen({
    super.key,
    this.library,
    this.autoOpen = false,

    this.files,
    this.processor = const ImageEditProcessor(),
  });
  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  late final _files = widget.files ?? DeviceImageEditFiles();
  final _title = TextEditingController(text: 'My image');
  ImageEditHistory? _history;
  EditedImage? _savedImage;
  String _format = 'png', _savedFormat = 'png', _savedTitle = 'My image';
  String? _notice;
  bool _busy = false, _modalOpen = false;
  bool get _dirty =>
      _history != null &&
      (!identical(_history!.current, _savedImage) ||
          _title.text != _savedTitle ||
          _format != _savedFormat);
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
    super.dispose();
  }

  Future<bool> _confirm() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('Leave this image?')),
            content: Text(
              context.tr(
                'Save a new image copy before continuing. Use Save to Library to keep a copy on this device.',
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

  Future<void> _open() async {
    if (_busy || !await _confirm() || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = await _files.pick();
      if (file == null || !mounted) return;
      if (file.bytes.length > EditedImage.maxInputBytes) {
        throw const FormatException('image-input');
      }
      final photo = await widget.processor.prepare(file.bytes, file.name);
      if (!mounted) return;
      if (!photo.image.valid || !['png', 'jpg'].contains(photo.format)) {
        throw const FormatException('image-format');
      }
      setState(() {
        _history = ImageEditHistory(photo.image);
        _savedImage = photo.image;
        _format = photo.format;
        _savedFormat = _format;
        _title.text = String.fromCharCodes(
          file.name
              .replaceFirst(RegExp(r'\.(png|jpe?g)$', caseSensitive: false), '')
              .runes
              .take(70),
        );
        _savedTitle = _title.text;
        _notice = photo.reduced
            ? 'Opened a smaller working copy: at most 4096 pixels per side and 6 megapixels. Your original file is unchanged.'
            : 'Opened a local copy. Your original file is unchanged.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Could not open this image. Choose a non-animated JPG or PNG under 15 MB and 32 megapixels. Your current image is kept.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(
    Future<EditedImage?> Function(EditedImage) operation,
  ) async {
    if (_busy || _history == null) return;
    final frame = _history!.current;
    setState(() => _busy = true);
    try {
      final next = await operation(frame);
      if (!mounted || next == null) return;
      setState(() {
        _history!.commit(next);
        _notice = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'Unable to apply this edit. Your image is kept. Try a smaller size or shorter text.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<EditedImage?> _crop(EditedImage frame) async {
    final crop = await Navigator.push<ScanCrop>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanCropEditor(
          title: 'Crop image',
          page: PdfScanPage(
            id: 0,
            name: _title.text,
            original: frame.bytes,
            preview: frame.bytes,
            width: frame.width,
            height: frame.height,
          ),
        ),
      ),
    );
    if (!mounted || crop == null) return null;
    return widget.processor.crop(frame, crop);
  }

  Future<EditedImage?> _text(EditedImage frame) async {
    final label = await Navigator.push<ImageLabel>(
      context,
      MaterialPageRoute(builder: (_) => ImageTextEditor(image: frame)),
    );
    if (!mounted || label == null) return null;
    return widget.processor.addText(frame, label);
  }

  Future<EditedImage?> _resize(EditedImage frame) async {
    final width = TextEditingController(text: '${frame.width}'),
        height = TextEditingController(text: '${frame.height}');
    var locked = true;
    String? error;
    final ratio = frame.width / frame.height;
    setState(() => _modalOpen = true);
    final route = DialogRoute<(int, int)>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(context.tr('Resize image')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('Use 1–4096 pixels per side, up to 6 megapixels.'),
                ),
                TextField(
                  key: const ValueKey('image-resize-width'),
                  controller: width,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr('Width in pixels'),
                  ),
                  onChanged: (s) {
                    if (locked) {
                      final n = int.tryParse(s);
                      if (n != null) height.text = '${(n / ratio).round()}';
                    }
                  },
                ),
                TextField(
                  key: const ValueKey('image-resize-height'),
                  controller: height,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr('Height in pixels'),
                  ),
                  onChanged: (s) {
                    if (locked) {
                      final n = int.tryParse(s);
                      if (n != null) width.text = '${(n * ratio).round()}';
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Keep proportions')),
                  value: locked,
                  onChanged: (v) => setDialog(() {
                    locked = v;
                    final w = int.tryParse(width.text);
                    if (v && w != null) height.text = '${(w / ratio).round()}';
                  }),
                ),
                if (!locked)
                  Text(
                    context.tr('Different proportions can stretch the image.'),
                  ),
                if (error != null) Text(context.tr(error!)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final w = int.tryParse(width.text),
                    h = int.tryParse(height.text);
                if (w == null || h == null || !EditedImage.validSize(w, h)) {
                  setDialog(
                    () => error = 'Choose valid dimensions within 4096 pixels and 6 megapixels.',
                  );
                  return;
                }
                Navigator.pop(dialog, (w, h));
              },
              child: Text(context.tr('Apply resize')),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    width.dispose();
    height.dispose();
    if (mounted) setState(() => _modalOpen = false);
    if (!mounted || result == null) return null;
    return widget.processor.resize(frame, result.$1, result.$2);
  }

  void _undo(bool redo) {
    if (_busy || _history == null) return;
    setState(() {
      if (redo) {
        _history!.redo();
      } else {
        _history!.undo();
      }
      _notice = null;
    });
  }

  Future<void> _export(bool share, {bool library = false}) async {
    if (_busy || _history == null) return;
    if (_title.text.trim().isEmpty || _title.text.length > 140) {
      setState(() => _notice = 'Enter an image title of 1–140 characters.');
      return;
    }
    final frame = _history!.current, title = _title.text, format = _format;
    setState(() => _busy = true);
    try {
      final saver = library
          ? (widget.library ?? AccountLocalFileSaver.capture())
          : null;
      final bytes = await widget.processor.export(frame, format);
      if (!mounted) return;
      if (bytes.isEmpty || bytes.length > EditedImage.maxEncodedBytes) {
        throw const FormatException('image-output');
      }
      final filename = editedImageFilename(title, format);
      final result = library
          ? await saveLocalCopy(
              saver!,
              filename,
              LocalFileKind.values.byName(format),
              bytes,
              'Image Editor',
            )
          : share
          ? await _files.share(bytes, filename)
          : await _files.save(bytes, filename);
      if (!mounted) return;
      setState(() {
        _notice = library
            ? 'Saved to Library on this device.'
            : switch (result) {
                PdfDelivery.saved => 'Image copy saved.',
                PdfDelivery.downloadRequested =>
                  'Image download requested. Check Downloads before leaving.',
                PdfDelivery.shareOpened => 'Image sharing opened.',
                PdfDelivery.cancelled =>
                  'Sharing or saving did not finish. Your image is kept.',
              };
        if (result == PdfDelivery.saved) {
          _savedImage = frame;
          _savedTitle = title;
          _savedFormat = format;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = library ? localSaveFailure(error) : 'Unable to save or share this image. Your edits are kept; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy || !await _confirm() || !mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final frame = _history?.current;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _close),
        title: Text(context.tr('Image Editor')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'Edit JPG and PNG locally. Save a new copy before closing or refreshing.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _open,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(context.tr('Open image')),
              ),
              if (_busy && !_modalOpen) const LinearProgressIndicator(),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(context.tr(_notice!)),
                ),
              if (frame != null) ...[
                const SizedBox(height: 12),
                Text('${frame.width} × ${frame.height} px'),
                const SizedBox(height: 8),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 360,
                      maxWidth: 700,
                    ),
                    child: AspectRatio(
                      aspectRatio: frame.width / frame.height,
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const CustomPaint(painter: ImageCheckerboard()),
                            Image.memory(
                              frame.bytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _edit(_crop),
                      icon: const Icon(Icons.crop),
                      label: Text(context.tr('Crop image')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _edit(widget.processor.rotate),
                      icon: const Icon(Icons.rotate_90_degrees_cw),
                      label: Text(context.tr('Rotate image')),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _edit(_resize),
                      child: Text(context.tr('Resize image')),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _edit(_text),
                      child: Text(context.tr('Add text')),
                    ),
                    IconButton(
                      tooltip: context.tr('Undo'),
                      onPressed: !_busy && _history!.canUndo
                          ? () => _undo(false)
                          : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: context.tr('Redo'),
                      onPressed: !_busy && _history!.canRedo
                          ? () => _undo(true)
                          : null,
                      icon: const Icon(Icons.redo),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _edit((_) async => _history!.original),
                      child: Text(context.tr('Reset image')),
                    ),
                  ],
                ),
                Text(
                  context.tr(
                    'Text becomes part of the picture after applying. Use Undo to change it. Undo history is limited for large images.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('image-file-title'),
                  controller: _title,
                  enabled: !_busy,
                  maxLength: 140,
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  buildCounter: (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => Text('${_title.text.length}/140'),
                  decoration: InputDecoration(
                    labelText: context.tr('File title'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('image-format-$_format'),
                  initialValue: _format,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('Image format'),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'png', child: Text('PNG')),
                    DropdownMenuItem(value: 'jpg', child: Text('JPG')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _format = v ?? _format),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    _format == 'png' ? 'PNG keeps transparent areas.' : 'JPG uses quality 95. Transparent areas become white.',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('local-library-save'),
                      onPressed: _busy || _history == null
                          ? null
                          : () => _export(false, library: true),
                      icon: const Icon(Icons.library_add_outlined),
                      label: Text(context.tr('Save to Library')),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : () => _export(false),
                      child: Text(context.tr('Save image copy')),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _export(true),
                      child: Text(context.tr('Share image')),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
