import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'image_edit_model.dart';
import 'pdf_scan_image.dart' show ScanCrop;

class ImageLabel {
  final String text;
  final double x, y, size;
  final int color;
  final bool background;
  const ImageLabel(
    this.text, {
    this.x = .5,
    this.y = .5,
    this.size = .06,
    this.color = 0xffffffff,
    this.background = true,
  });
  bool get valid =>
      text.trim().isNotEmpty &&
      text.length <= 300 &&
      text.split('\n').length <= 8 &&
      [x, y, size].every((v) => v.isFinite) &&
      x >= 0 &&
      x <= 1 &&
      y >= 0 &&
      y <= 1 &&
      size >= .01 &&
      size <= .2;
}

class LabelLayout {
  final TextPainter painter;
  final Rect box;
  final double padding;
  LabelLayout(this.painter, this.box, this.padding);
  void dispose() => painter.dispose();
}

LabelLayout imageLabelLayout(EditedImage image, ImageLabel label) {
  if (!label.valid) throw const FormatException('image-label');
  final fontSize = math.min(image.width, image.height) * label.size;
  final padding = fontSize * .2;
  final maxWidth = image.width * .94 - padding * 2;
  if (maxWidth < 1) throw const FormatException('image-label');
  final painter = TextPainter(
    text: TextSpan(
      text: label.text,
      style: TextStyle(
        color: Color(label.color),
        fontSize: fontSize,
        fontFamily: 'JiggoSans',
        fontFamilyFallback: const ['JiggoBengali'],
        height: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 8,
  );
  painter.layout(maxWidth: maxWidth);
  final width = painter.width + padding * 2,
      height = painter.height + padding * 2;
  if (painter.didExceedMaxLines ||
      width > image.width ||
      height > image.height ||
      height <= 0) {
    painter.dispose();
    throw const FormatException('image-label');
  }
  return LabelLayout(
    painter,
    Rect.fromLTWH(
      (image.width - width) * label.x,
      (image.height - height) * label.y,
      width,
      height,
    ),
    padding,
  );
}

void paintImageLabel(Canvas canvas, EditedImage image, ImageLabel label) {
  final layout = imageLabelLayout(image, label);
  try {
    if (label.background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(layout.box, Radius.circular(layout.padding)),
        Paint()
          ..color = (label.color == 0xffffffff
              ? Colors.black87
              : Colors.white70),
      );
    }
    layout.painter.paint(
      canvas,
      layout.box.topLeft + Offset(layout.padding, layout.padding),
    );
  } finally {
    layout.dispose();
  }
}

Map<String, Object> normalizeEditorImage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > EditedImage.maxInputBytes) {
    throw const FormatException('image-input');
  }
  img.Decoder decoder;
  String format;
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    decoder = img.JpegDecoder();
    format = 'jpg';
  } else if (bytes.length >= 8 &&
      listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
    decoder = img.PngDecoder();
    format = 'png';
  } else {
    throw const FormatException('image-format');
  }
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > 32000000 ||
      info.numFrames > 1) {
    throw const FormatException('image-dimensions');
  }
  var image = decoder.decodeFrame(0);
  if (image == null) throw const FormatException('image-format');
  image = img.bakeOrientation(image);
  final scale = math.min(
    1.0,
    math.min(
      EditedImage.maxEdge / math.max(image.width, image.height),
      math.sqrt(EditedImage.maxPixels / (image.width * image.height)),
    ),
  );
  final reduced = scale < 1;
  if (reduced) {
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * scale).floor()),
      height: math.max(1, (image.height * scale).floor()),
      interpolation: img.Interpolation.average,
    );
  }
  // Build an image from pixels only: camera EXIF, GPS and text metadata are not copied.
  final pixels = image
      .convert(format: img.Format.uint8, numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  final clean = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final encoded = img.encodePng(clean);
  if (encoded.length > EditedImage.maxEncodedBytes) {
    throw const FormatException('image-output');
  }
  return {
    'bytes': encoded,
    'width': clean.width,
    'height': clean.height,
    'format': format,
    'reduced': reduced,
  };
}

Uint8List imageJpegCopy(Uint8List png) {
  final source = img.decodePng(png);
  if (source == null) throw const FormatException('image-format');
  final white = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  );
  img.fill(white, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(white, source);
  return img.encodeJpg(white, quality: 95);
}

class ImageEditProcessor {
  const ImageEditProcessor();
  Future<ImportedImage> prepare(Uint8List bytes, String name) async {
    final result = await compute(normalizeEditorImage, bytes);
    return ImportedImage(
      EditedImage(
        result['bytes'] as Uint8List,
        result['width'] as int,
        result['height'] as int,
      ),
      name,
      result['format'] as String,
      reduced: result['reduced'] as bool,
    );
  }

  Future<EditedImage> _render(
    EditedImage frame,
    int w,
    int h,
    void Function(Canvas, ui.Image) draw,
  ) async {
    if (!frame.valid || !EditedImage.validSize(w, h)) {
      throw const FormatException('image-size');
    }
    final codec = await ui.instantiateImageCodec(frame.bytes);
    ui.Image? input, output;
    ui.Picture? picture;
    try {
      input = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      draw(canvas, input);
      picture = recorder.endRecording();
      output = await picture.toImage(w, h);
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes > EditedImage.maxEncodedBytes) {
        throw const FormatException('image-output');
      }
      return EditedImage(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        w,
        h,
      );
    } finally {
      input?.dispose();
      output?.dispose();
      picture?.dispose();
      codec.dispose();
    }
  }

  Future<EditedImage> rotate(EditedImage frame) =>
      _render(frame, frame.height, frame.width, (canvas, image) {
        canvas.translate(frame.height.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        canvas.drawImage(image, Offset.zero, Paint());
      });
  Future<EditedImage> crop(EditedImage frame, ScanCrop crop) {
    if (!crop.valid) throw const FormatException('image-crop');
    final x = (crop.left * frame.width).round().clamp(0, frame.width - 1);
    final y = (crop.top * frame.height).round().clamp(0, frame.height - 1);
    final r = ((crop.left + crop.width) * frame.width).round().clamp(
      x + 1,
      frame.width,
    );
    final b = ((crop.top + crop.height) * frame.height).round().clamp(
      y + 1,
      frame.height,
    );
    return _render(
      frame,
      r - x,
      b - y,
      (canvas, image) => canvas.drawImageRect(
        image,
        Rect.fromLTRB(x.toDouble(), y.toDouble(), r.toDouble(), b.toDouble()),
        Rect.fromLTWH(0, 0, (r - x).toDouble(), (b - y).toDouble()),
        Paint(),
      ),
    );
  }

  Future<EditedImage> resize(EditedImage frame, int w, int h) => _render(
    frame,
    w,
    h,
    (canvas, image) => canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    ),
  );
  Future<EditedImage> addText(EditedImage frame, ImageLabel label) async {
    final layout = imageLabelLayout(frame, label);
    layout.dispose();
    return _render(frame, frame.width, frame.height, (canvas, image) {
      canvas.drawImage(image, Offset.zero, Paint());
      paintImageLabel(canvas, frame, label);
    });
  }

  Future<Uint8List> export(EditedImage frame, String format) async {
    if (!frame.valid || !['png', 'jpg'].contains(format)) {
      throw const FormatException('image-export');
    }
    return format == 'png' ? frame.bytes : compute(imageJpegCopy, frame.bytes);
  }
}
