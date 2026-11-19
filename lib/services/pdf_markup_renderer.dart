import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'image_edit_model.dart';
import 'pdf_markup_model.dart';

Rect pdfMarkRect(PdfMark mark, Size size) {
  final a = Offset(
    mark.points.first.dx * size.width,
    mark.points.first.dy * size.height,
  );
  if (mark.kind == PdfMarkKind.image) {
    var width = (size.width * mark.size).clamp(1.0, size.width);
    var height = width / mark.imageAspect;
    if (height > size.height) {
      width *= size.height / height;
      height = size.height;
    }
    return Rect.fromLTWH(
      a.dx.clamp(0.0, size.width - width),
      a.dy.clamp(0.0, size.height - height),
      width,
      height,
    );
  }
  if (mark.kind == PdfMarkKind.highlight && mark.points.length >= 2) {
    final b = Offset(
      mark.points.last.dx * size.width,
      mark.points.last.dy * size.height,
    );
    return Rect.fromPoints(a, b);
  }
  return Rect.fromLTWH(a.dx, a.dy, 1, 1);
}

TextPainter _textPainter(PdfMark mark, Size size) {
  final painter = TextPainter(
    text: TextSpan(
      text: mark.text,
      style: TextStyle(
        color: Color(mark.color),
        fontSize: math.min(size.width, size.height) * mark.size,
        fontFamily: 'JiggoSans',
        fontFamilyFallback: const ['JiggoBengali'],
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 8,
  );
  painter.layout(maxWidth: size.width * .94);
  return painter;
}

/// Matches painted bounds for touch selection and the editor-only selection outline.
Rect pdfMarkBounds(PdfMark mark, Size size) {
  if (mark.kind == PdfMarkKind.text) {
    final p = _textPainter(mark, size);
    try {
      return Rect.fromLTWH(
        (mark.points.first.dx * size.width).clamp(
          0.0,
          math.max(0.0, size.width - p.width),
        ),
        (mark.points.first.dy * size.height).clamp(
          0.0,
          math.max(0.0, size.height - p.height),
        ),
        p.width,
        p.height,
      );
    } finally {
      p.dispose();
    }
  }
  if (mark.kind == PdfMarkKind.image || mark.kind == PdfMarkKind.highlight) {
    return pdfMarkRect(mark, size);
  }
  final xs = mark.points.map((p) => p.dx * size.width),
      ys = mark.points.map((p) => p.dy * size.height);
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  ).inflate(math.min(size.width, size.height) * mark.size / 2);
}

bool pdfMarkTextFits(PdfMark mark, Size size) {
  if (!mark.valid) return false;
  final p = _textPainter(mark, size);
  try {
    return !p.didExceedMaxLines &&
        p.height <= size.height &&
        p.width <= size.width;
  } finally {
    p.dispose();
  }
}

void paintPdfMarks(
  Canvas canvas,
  Size size,
  List<PdfMark> marks, {
  Map<Object, ui.Image> images = const {},
}) {
  for (final m in marks) {
    if (!m.valid) throw const FormatException('invalid-mark');
    switch (m.kind) {
      case PdfMarkKind.pen:
      case PdfMarkKind.signature:
        final paint = Paint()
          ..color = Color(m.color)
          ..strokeWidth = math.min(size.width, size.height) * m.size
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        final path = Path()
          ..moveTo(
            m.points.first.dx * size.width,
            m.points.first.dy * size.height,
          );
        for (final p in m.points.skip(1)) {
          path.lineTo(p.dx * size.width, p.dy * size.height);
        }
        if (m.points.length == 1) {
          canvas.drawCircle(
            Offset(
              m.points.first.dx * size.width,
              m.points.first.dy * size.height,
            ),
            paint.strokeWidth / 2,
            Paint()..color = Color(m.color),
          );
        } else {
          canvas.drawPath(path, paint);
        }
      case PdfMarkKind.highlight:
        canvas.drawRect(
          pdfMarkRect(m, size),
          Paint()..color = Color(m.color).withValues(alpha: .32),
        );
      case PdfMarkKind.text:
        final p = _textPainter(m, size);
        try {
          if (p.didExceedMaxLines || p.height > size.height) {
            throw const FormatException('text-does-not-fit');
          }
          final point = Offset(
            (m.points.first.dx * size.width).clamp(
              0.0,
              math.max(0, size.width - p.width),
            ),
            (m.points.first.dy * size.height).clamp(
              0.0,
              math.max(0, size.height - p.height),
            ),
          );
          p.paint(canvas, point);
        } finally {
          p.dispose();
        }
      case PdfMarkKind.image:
        final image = images[m.image];
        if (image == null) throw const FormatException('image-not-ready');
        paintImage(
          canvas: canvas,
          rect: pdfMarkRect(m, size),
          image: image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
        );
    }
  }
}

Future<EditedImage> renderPdfMarks(
  EditedImage background,
  List<PdfMark> marks,
) async {
  if (!background.valid ||
      marks.isEmpty ||
      marks.length > PdfMarkHistory.maxMarks) {
    throw const FormatException();
  }
  final images = <Object, ui.Image>{};
  ui.Image? base;
  ui.Picture? picture;
  ui.Image? output;
  Future<ui.Image> decode(Iterable<int> data) async {
    final bytes = data is Uint8List ? data : Uint8List.fromList(data.toList());
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  try {
    base = await decode(background.bytes);
    for (final m in marks.where((m) => m.kind == PdfMarkKind.image)) {
      if (!images.containsKey(m.image!)) {
        images[m.image!] = await decode(m.image!);
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImage(base, Offset.zero, Paint());
    paintPdfMarks(
      canvas,
      Size(background.width.toDouble(), background.height.toDouble()),
      marks,
      images: images,
    );
    picture = recorder.endRecording();
    output = await picture.toImage(background.width, background.height);
    final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw const FormatException();
    return EditedImage(
      bytes.buffer.asUint8List(),
      background.width,
      background.height,
    );
  } finally {
    base?.dispose();
    output?.dispose();
    picture?.dispose();
    for (final image in images.values) {
      image.dispose();
    }
  }
}
