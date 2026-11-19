import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_edit_model.dart';

abstract class PdfEditSource {
  int get pageCount;
  Widget preview(int index, int turns);
  Future<void> close();
}

abstract class PdfEditEngine {
  Future<PdfEditSource> open(PickedEditPdf file);
  Future<PdfEditSource> blank();
  Future<Uint8List> export(
    List<PdfEditSource> sources,
    List<EditPdfPage> pages,
  );
}

class PdfrxEditSource implements PdfEditSource {
  final PdfDocument document;
  PdfrxEditSource(this.document);
  @override
  int get pageCount => document.pages.length;
  @override
  Widget preview(int index, int turns) => RotatedBox(
    quarterTurns: turns,
    child: PdfPageView(
      document: document,
      pageNumber: index + 1,
      maximumDpi: 110,
      backgroundColor: Colors.white,
    ),
  );
  @override
  Future<void> close() => document.dispose();
}

class DevicePdfEditEngine implements PdfEditEngine {
  @override
  Future<PdfEditSource> open(PickedEditPdf file) async {
    file.validate();
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openData(
      file.bytes,
      sourceName: file.name,
      passwordProvider: () async => null,
    );
    if (doc.isEncrypted ||
        doc.pages.isEmpty ||
        doc.pages.length > PdfPagePlan.maxPages) {
      await doc.dispose();
      throw const FormatException(
        'Encrypted PDFs or PDFs over 100 pages are not supported.',
      );
    }
    return PdfrxEditSource(doc);
  }

  @override
  Future<PdfEditSource> blank() async {
    final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.SizedBox()));
    return open(PickedEditPdf('blank.pdf', await doc.save()));
  }

  @override
  Future<Uint8List> export(
    List<PdfEditSource> sources,
    List<EditPdfPage> pages,
  ) async {
    if (pages.isEmpty || pages.length > PdfPagePlan.maxPages) {
      throw const FormatException();
    }
    final out = await PdfDocument.createNew(sourceName: 'Jiggo edited copy');
    try {
      out.pages = pages.map((p) {
        var page =
            (sources[p.source] as PdfrxEditSource).document.pages[p.index];
        for (var i = 0; i < p.turns; i++) {
          page = page.rotatedCW90();
        }
        return page;
      }).toList();
      final bytes = await out.encodePdf();
      if (bytes.length > 32 * 1024 * 1024) {
        throw const FormatException('Output exceeds 32 MB');
      }
      return bytes;
    } finally {
      await out.dispose();
    }
  }
}
