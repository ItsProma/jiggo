import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_scan_image.dart';

class ScanPdfBuilder {
  static const maxOutputBytes = 32 * 1024 * 1024;
  Future<Uint8List> build(List<PdfScanPage> pages, String title) async {
    if (pages.isEmpty || pages.length > PdfScanImages.maxPages) {
      throw const FormatException('pdf-pages');
    }
    return compute(_buildPdf, {
      'title': title,
      'pages': [
        for (final page in pages)
          {'bytes': page.preview, 'width': page.width, 'height': page.height},
      ],
    });
  }
}

Future<Uint8List> _buildPdf(Map<String, Object> data) async {
  final pdf = pw.Document(title: data['title'] as String, creator: 'Jiggo');
  for (final value in data['pages'] as List) {
    final page = value as Map;
    final format = (page['width'] as int) > (page['height'] as int)
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(12),
        build: (_) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(page['bytes'] as Uint8List),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );
  }
  final bytes = await pdf.save();
  if (bytes.length > ScanPdfBuilder.maxOutputBytes) {
    throw const FormatException('pdf-size');
  }
  return bytes;
}

String scanPdfFilename(String title) {
  var name = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').trim();
  name = name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
  name = String.fromCharCodes(name.runes.take(80))
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  return '${name.isEmpty ? 'jiggo_scan' : name}.pdf';
}
