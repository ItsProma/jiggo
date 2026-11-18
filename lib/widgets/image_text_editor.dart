import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../services/app_strings.dart';
import '../services/image_edit_model.dart';
import '../services/image_edit_processor.dart';

class ImageTextEditor extends StatefulWidget {
  final EditedImage image;
  const ImageTextEditor({super.key, required this.image});
  @override
  State<ImageTextEditor> createState() => _ImageTextEditorState();
}

class _ImageTextEditorState extends State<ImageTextEditor> {
  final _text = TextEditingController();
  double _x = .5, _y = .5, _size = .06;
  int _color = 0xffffffff;
  bool _background = true;
  ImageLabel get _label => ImageLabel(
    _text.text,
    x: _x,
    y: _y,
    size: _size,
    color: _color,
    background: _background,
  );
  bool get _fits {
    try {
      final layout = imageLabelLayout(widget.image, _label);
      layout.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Add text to image'))),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'Write your text, then tap or drag on the photo to position it.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('image-label-text'),
              controller: _text,
              maxLength: 300,
              minLines: 2,
              maxLines: 5,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => Text('${_text.text.length}/300'),
              decoration: InputDecoration(
                labelText: context.tr('Text on image'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text(context.tr('Text size')),
            Slider(
              value: _size,
              min: .01,
              max: .2,
              onChanged: (v) => setState(() => _size = v),
            ),
            DropdownButtonFormField<int>(
              initialValue: _color,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Text color')),
              items: [
                for (final (color, label) in [
                  (0xffffffff, 'White'),
                  (0xff000000, 'Black'),
                  (0xff5744cc, 'Purple'),
                ])
                  DropdownMenuItem(
                    value: color,
                    child: Text(context.tr(label)),
                  ),
              ],
              onChanged: (v) => setState(() => _color = v ?? _color),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Text background')),
              value: _background,
              onChanged: (v) => setState(() => _background = v),
            ),
            SizedBox(
              height: 320,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = math.min(
                    constraints.maxWidth / widget.image.width,
                    constraints.maxHeight / widget.image.height,
                  );
                  final size = Size(
                    widget.image.width * scale,
                    widget.image.height * scale,
                  );
                  void position(Offset point) => setState(() {
                    _x = (point.dx / size.width).clamp(0.0, 1.0);
                    _y = (point.dy / size.height).clamp(0.0, 1.0);
                  });
                  return Center(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const CustomPaint(painter: ImageCheckerboard()),
                          Image.memory(
                            widget.image.bytes,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                          if (_fits)
                            CustomPaint(
                              painter: ImageLabelPainter(widget.image, _label),
                            ),
                          RawGestureDetector(
                            key: const ValueKey('image-label-placement'),
                            gestures: <Type, GestureRecognizerFactory>{
                              EagerGestureRecognizer:
                                  GestureRecognizerFactoryWithHandlers<
                                    EagerGestureRecognizer
                                  >(() => EagerGestureRecognizer(), (_) {}),
                            },
                            child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (e) => position(e.localPosition),
                              onPointerMove: (e) => position(e.localPosition),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_text.text.isNotEmpty && !_fits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.tr(
                    'The text does not fit. Shorten it or reduce its size.',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _fits ? () => Navigator.pop(context, _label) : null,
              child: Text(context.tr('Apply text')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}

class ImageLabelPainter extends CustomPainter {
  final EditedImage image;
  final ImageLabel label;
  ImageLabelPainter(this.image, this.label);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / image.width, size.height / image.height);
    paintImageLabel(canvas, image, label);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ImageLabelPainter old) =>
      old.image != image || old.label != label;
}

class ImageCheckerboard extends CustomPainter {
  const ImageCheckerboard();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xffececf0),
    );
    final paint = Paint()..color = const Color(0xffd3d3dc);
    for (var y = 0.0; y < size.height; y += 12) {
      for (var x = 0.0; x < size.width; x += 12) {
        if (((x / 12).floor() + (y / 12).floor()) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(
              x,
              y,
              math.min(12, size.width - x),
              math.min(12, size.height - y),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(ImageCheckerboard old) => false;
}
