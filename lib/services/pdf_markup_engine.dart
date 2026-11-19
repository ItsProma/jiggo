import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'image_edit_model.dart';
import 'image_edit_processor.dart';
import 'pdf_edit_engine.dart';
import 'pdf_edit_model.dart';

class PdfMarkupRaster {
  final EditedImage image;
  final double widthPoints, heightPoints;
  const PdfMarkupRaster(this.image, this.widthPoints, this.heightPoints);
}

abstract class PdfMarkupEngine {
  Future<PdfMarkupRaster> raster(PdfEditSource source, EditPdfPage page);
  Future<Uint8List> encode(
    EditedImage image,
    double widthPoints,
    double heightPoints,
  );
}

class DevicePdfMarkupEngine implements PdfMarkupEngine {
  @override
  Future<PdfMarkupRaster> raster(
    PdfEditSource source,
    EditPdfPage entry,
  ) async {
    final page = (source as PdfrxEditSource).document.pages[entry.index];
    final w = page.width, h = page.height;
    if (!w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0 ||
        w / h > 20 ||
        h / w > 20) {
      throw const FormatException();
    }
    final scale = math.min(
      2.5,
      math.min(3000 / math.max(w, h), math.sqrt(6000000 / (w * h))),
    );
    final width = math.max(1, (w * scale).floor()),
        height = math.max(1, (h * scale).floor());
    final raw = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xffffffff,
    );
    if (raw == null) throw const FormatException();
    ui.Image? bitmap;
    try {
      bitmap = await raw.createImage();
      final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException();
      var frame = EditedImage(data.buffer.asUint8List(), width, height);
      for (var i = 0; i < entry.turns; i++) {
        frame = await ImageEditProcessor().rotate(frame);
      }
      return PdfMarkupRaster(
        frame,
        entry.turns.isOdd ? h : w,
        entry.turns.isOdd ? w : h,
      );
    } finally {
      bitmap?.dispose();
      raw.dispose();
    }
  }

  @override
  Future<Uint8List> encode(
    EditedImage image,
    double widthPoints,
    double heightPoints,
  ) async {
    if (!image.valid ||
        !widthPoints.isFinite ||
        !heightPoints.isFinite ||
        widthPoints <= 0 ||
        heightPoints <= 0) {
      throw const FormatException();
    }
    Future<Uint8List> make(Uint8List bytes) async {
      final doc = pw.Document()
        ..addPage(
          pw.Page(
            pageFormat: PdfPageFormat(widthPoints, heightPoints),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
          ),
        );
      return doc.save();
    }

    var output = await make(image.bytes);
    if (output.length > PickedEditPdf.maxBytes) {
      output = await make(await ImageEditProcessor().export(image, 'jpg'));
    }
    if (output.length > PickedEditPdf.maxBytes) throw const FormatException();
    return output;
  }
}
