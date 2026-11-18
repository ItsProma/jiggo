
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'bangla_pdf_paginator.dart';

class PdfExportService {

  static bool _containsBangla(String text) {
    return RegExp(r'[\u0980-\u09FF]').hasMatch(text);
  }


  static List<pw.TextSpan> _buildInlineSpans(
    List<md.Node>? nodes,
  ) {
    final spans = <pw.TextSpan>[];

    for (final node in nodes ?? <md.Node>[]) {
      if (node is md.Text) {
        spans.add(pw.TextSpan(text: node.text));
      } else if (node is md.Element) {
        final isBold = node.tag == 'strong' || node.tag == 'b';
        final isItalic = node.tag == 'em' || node.tag == 'i';

        spans.add(
          pw.TextSpan(
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : null,
              fontStyle: isItalic ? pw.FontStyle.italic : null,
            ),
            children: _buildInlineSpans(node.children),
          ),
        );
      }
    }

    return spans;
  }

  static Future<void> exportDocument({
    required String title,
    required String content,
  }) async {
    final isBanglaDocument =
    _containsBangla('$title\n$content');
    
    if (isBanglaDocument) {
      final pages = await BanglaPdfPaginator.renderPages(
        content: '# $title\n\n$content',
      );

      final banglaPdf = pw.Document();

      for (final pageBytes in pages) {
        final pageImage = pw.MemoryImage(pageBytes);

        banglaPdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(
                pageImage,
                fit: pw.BoxFit.fill,
              ),
            ),
          ),
        );
      }

      await Printing.sharePdf(
        bytes: await banglaPdf.save(),
        filename: 'jiggo_document.pdf',
      );

      return;
    }

    final englishFontData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final banglaFontData = await rootBundle.load(
      'assets/fonts/NotoSansBengali-Regular.ttf',
    );

    final englishFont = pw.Font.ttf(englishFontData);
    final banglaFont = pw.Font.ttf(banglaFontData);

    final theme = pw.ThemeData.withFont(
      base: englishFont,
      bold: englishFont,
      fontFallback: [banglaFont],
    );

    final markdownNodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    ).parseLines(content.split('\n'));

    final widgets = <pw.Widget>[];

    for (final node in markdownNodes) {
      if (node is! md.Element) continue;

      final tag = node.tag;
      final text = node.textContent.trim();

      if (text.isEmpty) continue;

      if (RegExp(r'^h[1-6]$').hasMatch(tag) &&
    text.toLowerCase() == title.trim().toLowerCase()) {
  continue;
}

      if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
        final level = int.parse(tag.substring(1));

        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(
              top: 12,
              bottom: 8,
            ),
            child: pw.Text(
              text,
              style: pw.TextStyle(
                fontSize: level <= 2 ? 17 : 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );
      
} else if (tag == 'p') {
  widgets.add(
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(
            fontSize: 11,
            lineSpacing: 4,
          ),
          children: _buildInlineSpans(node.children),
        ),
      ),
    ),
  );
}
 else if (tag == 'ul' || tag == 'ol') {
        var number = 1;

        for (final child in node.children ?? <md.Node>[]) {
          if (child is! md.Element || child.tag != 'li') {
            continue;
          }

          final prefix = tag == 'ol' ? '${number++}.' : '-';

          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(
                left: 12,
                bottom: 6,
              ),
              child: pw.Text(
                '$prefix ${child.textContent.trim()}',
                style: const pw.TextStyle(
                  fontSize: 11,
                  lineSpacing: 3,
                ),
              ),
            ),
          );
        }
      } else {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              text,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        );
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: theme,
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 20),
          ...widgets,
        ],
      ),
    );

    final pdfBytes = await pdf.save();

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'jiggo_document.pdf',
    );
  }
}
