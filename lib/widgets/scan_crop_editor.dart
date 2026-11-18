import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../services/app_strings.dart';
import '../services/pdf_scan_image.dart';

enum ScanCropHandle { topLeft, topRight, bottomLeft, bottomRight, move }

ScanCrop moveScanCrop(
  ScanCrop crop,
  ScanCropHandle handle,
  double dx,
  double dy,
) {
  var l = crop.left,
      t = crop.top,
      r = crop.left + crop.width,
      b = crop.top + crop.height;
  const min = .05;
  if (handle == ScanCropHandle.move) {
    l = (l + dx).clamp(0.0, 1 - crop.width);
    t = (t + dy).clamp(0.0, 1 - crop.height);
    return ScanCrop(l, t, crop.width, crop.height);
  }
  if (handle == ScanCropHandle.topLeft || handle == ScanCropHandle.bottomLeft) {
    l = (l + dx).clamp(0.0, r - min);
  }
  if (handle == ScanCropHandle.topRight ||
      handle == ScanCropHandle.bottomRight) {
    r = (r + dx).clamp(l + min, 1.0);
  }
  if (handle == ScanCropHandle.topLeft || handle == ScanCropHandle.topRight) {
    t = (t + dy).clamp(0.0, b - min);
  }
  if (handle == ScanCropHandle.bottomLeft ||
      handle == ScanCropHandle.bottomRight) {
    b = (b + dy).clamp(t + min, 1.0);
  }
  return ScanCrop(l, t, r - l, b - t);
}

class ScanCropEditor extends StatefulWidget {
  final PdfScanPage page;
  final String title;
  const ScanCropEditor({
    super.key,
    required this.page,
    this.title = 'Crop page',
  });
  @override
  State<ScanCropEditor> createState() => _ScanCropEditorState();
}

class _ScanCropEditorState extends State<ScanCropEditor> {
  ScanCrop _crop = ScanCrop.full;
  int? _pointer;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr(widget.title))),
    body: SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.tr(
                'Drag the corners to crop, or drag inside the box to move it.',
              ),
            ),
          ),
          SizedBox(
            height: (MediaQuery.sizeOf(context).height * .5).clamp(
              260.0,
              520.0,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = math.max(1.0, constraints.maxWidth - 48),
                    maxH = math.max(1.0, constraints.maxHeight - 48);
                final scale = math.min(
                  maxW / widget.page.width,
                  maxH / widget.page.height,
                );
                final w = widget.page.width * scale,
                    h = widget.page.height * scale;
                final rect = Rect.fromLTWH(
                  24 + _crop.left * w,
                  24 + _crop.top * h,
                  _crop.width * w,
                  _crop.height * h,
                );
                void move(ScanCropHandle handle, Offset delta) {
                  setState(
                    () => _crop = moveScanCrop(
                      _crop,
                      handle,
                      delta.dx / w,
                      delta.dy / h,
                    ),
                  );
                }

                Widget dragArea(
                  ScanCropHandle handle, {
                  required Key key,
                  Widget? child,
                }) => RawGestureDetector(
                  gestures: {
                    EagerGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer
                        >(() => EagerGestureRecognizer(), (_) {}),
                  },
                  child: Listener(
                    key: key,
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      _pointer ??= event.pointer;
                    },
                    onPointerMove: (event) {
                      if (_pointer == event.pointer) move(handle, event.delta);
                    },
                    onPointerUp: (event) {
                      if (_pointer == event.pointer) _pointer = null;
                    },
                    onPointerCancel: (event) {
                      if (_pointer == event.pointer) _pointer = null;
                    },
                    child: child,
                  ),
                );

                return Center(
                  child: SizedBox(
                    width: w + 48,
                    height: h + 48,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 24,
                          top: 24,
                          width: w,
                          height: h,
                          child: Image.memory(
                            widget.page.preview,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            cacheWidth: 1000,
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _CropPainter(
                                rect,
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fromRect(
                          rect: rect,
                          child: dragArea(
                            ScanCropHandle.move,
                            key: const ValueKey('crop-move'),
                          ),
                        ),
                        for (final handle in [
                          ScanCropHandle.topLeft,
                          ScanCropHandle.topRight,
                          ScanCropHandle.bottomLeft,
                          ScanCropHandle.bottomRight,
                        ])
                          Positioned(
                            left:
                                ((handle == ScanCropHandle.topLeft ||
                                        handle == ScanCropHandle.bottomLeft)
                                    ? rect.left
                                    : rect.right) -
                                18,
                            top:
                                ((handle == ScanCropHandle.topLeft ||
                                        handle == ScanCropHandle.topRight)
                                    ? rect.top
                                    : rect.bottom) -
                                18,
                            width: 36,
                            height: 36,
                            child: dragArea(
                              handle,
                              key: ValueKey(handle),
                              child: Center(
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() => _crop = ScanCrop.full),
                  child: Text(context.tr('Reset crop')),
                ),
                OutlinedButton(
                  onPressed: _crop.width <= .2 || _crop.height <= .2
                      ? null
                      : () => setState(
                          () => _crop = _crop.within(
                            const ScanCrop(.05, .05, .9, .9),
                          ),
                        ),
                  child: Text(context.tr('Trim edges')),
                ),
                FilledButton(
                  key: const ValueKey('apply-scan-crop'),
                  onPressed: () => Navigator.pop(context, _crop),
                  child: Text(context.tr('Apply crop')),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  final Rect rect;
  final Color color;
  _CropPainter(this.rect, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(mask, Paint()..color = Colors.black54);
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.rect != rect || old.color != color;
}
