import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/image_edit_files.dart';
import '../services/image_edit_model.dart';
import '../services/image_edit_processor.dart';
import '../services/pdf_markup_model.dart';
import '../services/pdf_markup_renderer.dart';

enum _Tool { move, pen, highlight, signature, text, image }

class PdfMarkupScreen extends StatefulWidget {
  final EditedImage background;
  final ImageEditFiles? imageFiles;
  final ImageEditProcessor processor;
  final Future<EditedImage> Function(EditedImage, List<PdfMark>)? render;
  const PdfMarkupScreen({
    super.key,
    required this.background,
    this.imageFiles,
    this.processor = const ImageEditProcessor(),
    this.render,
  });
  @override
  State<PdfMarkupScreen> createState() => _PdfMarkupScreenState();
}

class _PdfMarkupScreenState extends State<PdfMarkupScreen> {
  final _history = PdfMarkHistory();
  final _images = <Object, ui.Image>{};
  _Tool _tool = _Tool.move;
  PdfMark? _pending, _moving;
  int _selected = -1, _pointer = -1;
  List<Offset> _stroke = [];
  Offset? _start;
  bool _busy = false, _leaving = false, _scrollMode = true, _confirming = false;
  int _color = 0xff111111;
  double _size = .008;
  String? _notice;
  bool get _dirty => _history.marks.isNotEmpty || _pending != null;
  @override
  void initState() {
    super.initState();
    _history.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      setState(() {
        _selected = _selected.clamp(-1, _history.marks.length - 1);
      });
    }
  }

  @override
  void dispose() {
    _history.removeListener(_changed);
    _history.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  void _safe(VoidCallback action) {
    try {
      action();
      setState(() => _notice = null);
    } catch (_) {
      setState(
        () => _notice =
            'Unable to add this item. Use shorter text or fewer items.',
      );
    }
  }

  void _choose(_Tool tool) {
    if (_busy) return;
    setState(() {
      _tool = tool;
      _scrollMode = false;
      _pending = null;
      _stroke = [];
      _moving = null;
      _notice = null;
      _size = switch (tool) {
        _Tool.text => .04,
        _Tool.image => .28,
        _Tool.signature => .006,
        _ => .008,
      };
      if (tool == _Tool.highlight) _color = 0xffffd600;
      if (tool == _Tool.signature) _color = 0xff111111;
    });
  }

  Future<void> _addText() async {
    _choose(_Tool.text);
    final controller = TextEditingController();
    final route = DialogRoute<String>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(c.tr('Add PDF text')),
        content: TextField(
          key: const ValueKey('pdf-markup-text'),
          controller: controller,
          maxLength: 300,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: c.tr('Write Bangla or English text'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(c.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: Text(c.tr('Next')),
          ),
        ],
      ),
    );
    final text = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;
    final mark = PdfMark(
      kind: PdfMarkKind.text,
      points: const [Offset(.1, .1)],
      text: text,
      color: _color,
      size: _size,
    );
    if (!pdfMarkTextFits(
      mark,
      Size(
        widget.background.width.toDouble(),
        widget.background.height.toDouble(),
      ),
    )) {
      setState(
        () =>
            _notice = 'This text does not fit. Use fewer words or fewer lines.',
      );
      return;
    }
    setState(() => _pending = mark);
  }

  Future<void> _addImage() async {
    if (_busy) return;
    _choose(_Tool.image);
    if (_images.length >= 4) {
      setState(() => _notice = 'Use up to four images in one markup session.');
      return;
    }
    setState(() => _busy = true);
    ui.Image? decoded;
    try {
      final picked = await (widget.imageFiles ?? DeviceImageEditFiles()).pick();
      if (!mounted || picked == null) return;
      final processor = widget.processor;
      var frame = (await processor.prepare(picked.bytes, picked.name)).image;
      final scale = math.min(
        1.0,
        math.min(
          1200 / math.max(frame.width, frame.height),
          math.sqrt(1000000 / (frame.width * frame.height)),
        ),
      );
      if (scale < 1) {
        frame = await processor.resize(
          frame,
          math.max(1, (frame.width * scale).floor()),
          math.max(1, (frame.height * scale).floor()),
        );
      }
      if (frame.bytes.length > 4 * 1024 * 1024) throw const FormatException();
      final codec = await ui.instantiateImageCodec(frame.bytes);
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      _images[frame.bytes] = decoded;
      decoded = null;
      setState(
        () => _pending = PdfMark(
          kind: PdfMarkKind.image,
          points: const [Offset(.1, .1)],
          size: _size,
          image: frame.bytes,
          imageAspect: frame.width / frame.height,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _notice = 'Could not add image. Choose a JPG or PNG under 15 MB.',
        );
      }
    } finally {
      decoded?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resizeSelected(double factor) {
    if (_selected < 0 || _busy) return;
    final old = _history.marks[_selected];
    var points = old.points;
    if (old.kind != PdfMarkKind.text && old.kind != PdfMarkKind.image) {
      final center = Offset(
        (points.map((p) => p.dx).reduce(math.min) +
                points.map((p) => p.dx).reduce(math.max)) /
            2,
        (points.map((p) => p.dy).reduce(math.min) +
                points.map((p) => p.dy).reduce(math.max)) /
            2,
      );
      points = points.map((p) => center + (p - center) * factor).toList();
    }
    final mark = PdfMark(
      kind: old.kind,
      points: points,
      color: old.color,
      size: (old.size * factor).clamp(.002, .45),
      text: old.text,
      image: old.image,
      imageAspect: old.imageAspect,
    );
    if (!mark.valid ||
        (mark.kind == PdfMarkKind.text &&
            !pdfMarkTextFits(
              mark,
              Size(
                widget.background.width.toDouble(),
                widget.background.height.toDouble(),
              ),
            ))) {
      return;
    }
    _safe(() => _history.replace(_selected, mark));
  }

  void _resizePending(double value) {
    if (_pending?.kind == PdfMarkKind.text) {
      final mark = PdfMark(
        kind: PdfMarkKind.text,
        points: _pending!.points,
        text: _pending!.text,
        color: _color,
        size: value,
      );
      if (!pdfMarkTextFits(
        mark,
        Size(
          widget.background.width.toDouble(),
          widget.background.height.toDouble(),
        ),
      )) {
        setState(
          () => _notice =
              'This text does not fit. Use fewer words or fewer lines.',
        );
        return;
      }
    }
    setState(() => _size = value);
  }

  Offset _point(Offset p, Size size) => Offset(
    (p.dx / size.width).clamp(0.0, 1.0),
    (p.dy / size.height).clamp(0.0, 1.0),
  );
  PdfMark? _draft() {
    if (_moving != null) return _moving;
    if (_stroke.isEmpty) return null;
    final kind = switch (_tool) {
      _Tool.highlight => PdfMarkKind.highlight,
      _Tool.signature => PdfMarkKind.signature,
      _ => PdfMarkKind.pen,
    };
    return PdfMark(
      kind: kind,
      points: List.of(_stroke),
      color: _color,
      size: _size,
    );
  }

  void _down(PointerDownEvent e, Size size) {
    if (_busy || _scrollMode || _pointer != -1) return;
    _pointer = e.pointer;
    _start = _point(e.localPosition, size);
    setState(() {
      if (_pending != null) {
        _moving = PdfMark(
          kind: _pending!.kind,
          points: [_start!],
          text: _pending!.text,
          color: _color,
          size: _size,
          image: _pending!.image,
          imageAspect: _pending!.imageAspect,
        );
      } else if (_tool == _Tool.move) {
        _selected = -1;
        for (var i = _history.marks.length - 1; i >= 0; i--) {
          if (pdfMarkBounds(
            _history.marks[i],
            size,
          ).inflate(10).contains(e.localPosition)) {
            _selected = i;
            _moving = _history.marks[i];
            break;
          }
        }
      } else if ([
        _Tool.pen,
        _Tool.signature,
        _Tool.highlight,
      ].contains(_tool)) {
        _stroke = [_start!];
      }
    });
  }

  void _move(PointerMoveEvent e, Size size) {
    if (e.pointer != _pointer) return;
    final p = _point(e.localPosition, size);
    setState(() {
      if (_pending != null && _moving != null) {
        _moving = _moving!.moved(p - _moving!.points.first);
      } else if (_tool == _Tool.move && _selected >= 0) {
        _moving = _history.marks[_selected].moved(p - _start!);
      } else if (_tool == _Tool.highlight) {
        _stroke = [_start!, p];
      } else if (_stroke.isNotEmpty && _stroke.length < 1000) {
        _stroke.add(p);
      }
    });
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final mark = _draft();
    if (mark != null) {
      _safe(() {
        if (_tool == _Tool.move && _pending == null && _selected >= 0) {
          if (!identical(mark, _history.marks[_selected])) {
            _history.replace(_selected, mark);
          }
        } else {
          _history.add(mark);
          _selected = _history.marks.length - 1;
        }
        if (_pending != null) _tool = _Tool.move;
        _pending = null;
      });
    }
    setState(() {
      _pointer = -1;
      _start = null;
      _stroke = [];
      _moving = null;
    });
  }

  void _cancel(PointerEvent e) {
    if (e.pointer == _pointer) {
      setState(() {
        _pointer = -1;
        _stroke = [];
        _moving = null;
        _start = null;
      });
    }
  }

  Future<bool> _confirm() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(c.tr('Discard page markup?')),
            content: Text(
              c.tr('Apply to page to keep these changes, or discard them.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(c.tr('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(c.tr('Discard')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _apply() async {
    if (_busy || _pending != null || _history.marks.isEmpty) return;
    setState(() {
      _busy = true;
      _confirming = true;
    });
    try {
      final keep = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: Text(c.tr('Ready to keep these changes?')),
          content: Text(
            c.tr(
              'This edited page will be saved as an image. Text on it will not be selectable or searchable. Your original PDF is kept.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(c.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(c.tr('Keep changes')),
            ),
          ],
        ),
      );
      if (!mounted || keep != true) return;
      setState(() => _confirming = false);
      final image = await (widget.render ?? renderPdfMarks)(
        widget.background,
        _history.marks,
      );
      if (mounted) {
        setState(() => _leaving = true);
        Navigator.pop(context, image);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Could not apply markup. Your page changes are kept here.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final marks = List<PdfMark>.of(_history.marks);
    final draft = _draft();
    if (draft != null) {
      if (_tool == _Tool.move && _pending == null && _selected >= 0) {
        marks[_selected] = draft;
      } else {
        marks.add(draft);
      }
    }
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
          title: Text(context.tr('Edit page')),
          actions: [
            IconButton(
              tooltip: context.tr('Undo'),
              onPressed: _busy || !_history.canUndo
                  ? null
                  : () {
                      _pending = null;
                      _history.undo();
                    },
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: context.tr('Redo'),
              onPressed: _busy || !_history.canRedo ? null : _history.redo,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: context.tr('Help'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(c.tr('Edit page')),
                  content: Text(
                    c.tr(
                      'Applied markup turns this page into an image. Text on this page will not be selectable or searchable. Keep your original PDF.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(c.tr('OK')),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _scrollMode = !_scrollMode),
                  child: Text(
                    context.tr(_scrollMode ? 'Resume editing' : 'Scroll page'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        _busy ||
                            _pointer != -1 ||
                            _pending != null ||
                            _history.marks.isEmpty
                        ? null
                        : _apply,
                    child: Text(
                      context.tr('Keep changes'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            if (_busy && !_confirming) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: !_scrollMode && _tool == _Tool.move
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        onPressed: _busy ? null : () => _choose(_Tool.move),
                        icon: const Icon(Icons.open_with),
                        label: Text(context.tr('Move item')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: !_scrollMode && _tool == _Tool.text
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        onPressed: _busy ? null : _addText,
                        icon: const Icon(Icons.text_fields),
                        label: Text(context.tr('Add text')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: !_scrollMode && _tool == _Tool.image
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        onPressed: _busy ? null : _addImage,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(context.tr('Add image')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              !_scrollMode && _tool == _Tool.highlight
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _choose(_Tool.highlight),
                        icon: const Icon(Icons.highlight),
                        label: Text(context.tr('Highlight area')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: !_scrollMode && _tool == _Tool.pen
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        onPressed: _busy ? null : () => _choose(_Tool.pen),
                        icon: const Icon(Icons.draw),
                        label: Text(context.tr('Draw')),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              !_scrollMode && _tool == _Tool.signature
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _choose(_Tool.signature),
                        icon: const Icon(Icons.gesture),
                        label: Text(context.tr('Draw signature')),
                      ),
                    ],
                  ),
                  if (_tool == _Tool.move && _selected >= 0 && _pending == null)
                    Wrap(
                      spacing: 6,
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : () => _resizeSelected(.9),
                          icon: const Icon(Icons.remove),
                          label: Text(context.tr('Smaller')),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _resizeSelected(1.1),
                          icon: const Icon(Icons.add),
                          label: Text(context.tr('Larger')),
                        ),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _safe(() => _history.remove(_selected)),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(context.tr('Delete item')),
                        ),
                      ],
                    ),
                  if (_pending != null) ...[
                    Text(
                      context.tr(
                        _scrollMode
                            ? 'Tap Resume editing to place your item.'
                            : 'Tap or drag on the page to place your item.',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _pending = null),
                      child: Text(context.tr('Cancel placement')),
                    ),
                  ] else
                    Text(
                      context.tr(
                        _scrollMode
                            ? 'Scroll mode is on. Choose a tool to edit the page.'
                            : _tool == _Tool.move
                            ? 'Select an item below, then drag on the page to move it.'
                            : _tool == _Tool.highlight
                            ? 'Drag a rectangle over the area to highlight.'
                            : _tool == _Tool.signature
                            ? 'Draw your signature on the page. This is not a digital certificate.'
                            : 'Draw on the page with your finger or mouse.',
                      ),
                    ),
                  if (_tool != _Tool.move && _tool != _Tool.image)
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(context.tr('Color')),
                        DropdownButton<int>(
                          value: _color,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _color = v!),
                          items: [
                            DropdownMenuItem(
                              value: 0xff111111,
                              child: Text(context.tr('Black')),
                            ),
                            DropdownMenuItem(
                              value: 0xff4355c8,
                              child: Text(context.tr('Blue')),
                            ),
                            DropdownMenuItem(
                              value: 0xffd32f2f,
                              child: Text(context.tr('Red')),
                            ),
                            DropdownMenuItem(
                              value: 0xff15804a,
                              child: Text(context.tr('Green')),
                            ),
                            DropdownMenuItem(
                              value: 0xffffd600,
                              child: Text(context.tr('Yellow')),
                            ),
                          ],
                        ),
                        if (_tool != _Tool.move && _tool != _Tool.highlight)
                          SizedBox(
                            width: 200,
                            child: Column(
                              children: [
                                Text(context.tr('Size')),
                                Slider(
                                  value: _size,
                                  min: _tool == _Tool.text
                                      ? .018
                                      : _tool == _Tool.image
                                      ? .05
                                      : .002,
                                  max: _tool == _Tool.text
                                      ? .12
                                      : _tool == _Tool.image
                                      ? .45
                                      : .025,
                                  onChanged: _busy ? null : _resizePending,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  if (_tool == _Tool.image && _pending != null)
                    Row(
                      children: [
                        Text(context.tr('Size')),
                        Expanded(
                          child: Slider(
                            value: _size,
                            min: .05,
                            max: .45,
                            onChanged: _busy ? null : _resizePending,
                          ),
                        ),
                      ],
                    ),
                  LayoutBuilder(
                    builder: (c, constraints) {
                      final aspect =
                          widget.background.width / widget.background.height;
                      return SizedBox(
                        height: (constraints.maxWidth / aspect).clamp(
                          150.0,
                          520.0,
                        ),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: aspect,
                            child: LayoutBuilder(
                              builder: (c, box) {
                                final size = Size(box.maxWidth, box.maxHeight);
                                return GestureDetector(
                                  onTapUp: !_scrollMode || _busy
                                      ? null
                                      : (details) {
                                          for (
                                            var i = _history.marks.length - 1;
                                            i >= 0;
                                            i--
                                          ) {
                                            if (pdfMarkBounds(
                                                  _history.marks[i],
                                                  size,
                                                )
                                                .inflate(10)
                                                .contains(
                                                  details.localPosition,
                                                )) {
                                              setState(() {
                                                _selected = i;
                                                _tool = _Tool.move;
                                                _scrollMode = false;
                                                _pending = null;
                                              });
                                              break;
                                            }
                                          }
                                        },
                                  child: RawGestureDetector(
                                    gestures: _scrollMode
                                        ? {}
                                        : {
                                            EagerGestureRecognizer:
                                                GestureRecognizerFactoryWithHandlers<
                                                  EagerGestureRecognizer
                                                >(
                                                  () =>
                                                      EagerGestureRecognizer(),
                                                  (_) {},
                                                ),
                                          },
                                    child: Listener(
                                      key: const ValueKey('pdf-markup-board'),
                                      onPointerDown: (e) => _down(e, size),
                                      onPointerMove: (e) => _move(e, size),
                                      onPointerUp: _up,
                                      onPointerCancel: _cancel,
                                      child: CustomPaint(
                                        foregroundPainter: _MarksPainter(
                                          marks,
                                          _images,
                                          selected:
                                              _pending == null &&
                                                  _tool == _Tool.move
                                              ? _selected
                                              : -1,
                                        ),
                                        child: Image.memory(
                                          widget.background.bytes,
                                          fit: BoxFit.fill,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_history.marks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(context.tr('Select item')),
                    Wrap(
                      spacing: 6,
                      children: List.generate(
                        _history.marks.length,
                        (i) => ChoiceChip(
                          label: Text('${i + 1}'),
                          selected: _selected == i,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                  _selected = i;
                                  _scrollMode = false;
                                  _tool = _Tool.move;
                                  _pending = null;
                                }),
                        ),
                      ),
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
          ],
        ),
      ),
    );
  }
}

class _MarksPainter extends CustomPainter {
  final List<PdfMark> marks;
  final Map<Object, ui.Image> images;
  final int selected;
  _MarksPainter(this.marks, this.images, {this.selected = -1});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintPdfMarks(canvas, size, marks, images: images);
    if (selected >= 0 && selected < marks.length) {
      canvas.drawRect(
        pdfMarkBounds(marks[selected], size).inflate(3),
        Paint()
          ..color = const Color(0xff4355c8)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarksPainter old) => true;
}
