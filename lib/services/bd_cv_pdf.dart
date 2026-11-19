import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'bangla_pdf_paginator.dart';

class CvPaperParts {
  final String name, contacts, body;
  const CvPaperParts(this.name, this.contacts, this.body);
  factory CvPaperParts.parse(String content) {
    final lines = content.trim().split('\n');
    if (lines.isEmpty || !lines.first.startsWith('# ')) {
      return CvPaperParts('', '', content);
    }
    final name = lines.removeAt(0).substring(2).trim();
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    final contacts = <String>[];
    if (lines.isNotEmpty &&
        !lines.first.startsWith('#') &&
        !lines.first.startsWith('|')) {
      while (lines.isNotEmpty && lines.first.trim().isNotEmpty) {
        contacts.add(lines.removeAt(0));
      }
    }
    return CvPaperParts(name, contacts.join('\n'), lines.join('\n').trim());
  }
}

String cvPrintTitle(String title) =>
    title == 'Resume' ? 'CURRICULUM VITAE' : title;
String _plain(String markdown) => md.Document()
    .parseLines(markdown.split('\n'))
    .map((n) => n.textContent)
    .join('\n');

class BdCvHeader extends StatelessWidget {
  final String title;
  final CvPaperParts parts;
  final Uint8List? photo;
  const BdCvHeader({
    super.key,
    required this.title,
    required this.parts,
    this.photo,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        cvPrintTitle(title),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'JiggoSans',
          fontFamilyFallback: ['JiggoBengali'],
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parts.name.isNotEmpty)
                  Text(
                    _plain(parts.name),
                    style: const TextStyle(
                      fontFamily: 'JiggoSans',
                      fontFamilyFallback: ['JiggoBengali'],
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  _plain(parts.contacts),
                  style: const TextStyle(
                    fontFamily: 'JiggoSans',
                    fontFamilyFallback: ['JiggoBengali'],
                    fontSize: 11,
                    height: 1.5,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          if (photo != null) ...[
            const SizedBox(width: 20),
            Container(
              width: 85,
              height: 110,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black54),
              ),
              child: Image.memory(
                photo!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

class BdCvPaper extends StatelessWidget {
  final String title, content;
  final Uint8List? photo;
  const BdCvPaper({
    super.key,
    required this.title,
    required this.content,
    this.photo,
  });
  @override
  Widget build(BuildContext context) {
    final parts = CvPaperParts.parse(content);
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 595,
          child: Theme(
            data: ThemeData(
              textTheme: Typography.material2021().englishLike.merge(
                Typography.material2021().black,
              ),
              fontFamily: 'JiggoSans',
              fontFamilyFallback: ['JiggoBengali'],
            ),
            child: Material(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BdCvHeader(title: title, parts: parts, photo: photo),
                    const SizedBox(height: 20),
                    MarkdownBody(
                      data: parts.body,
                      builders: {'h2': CvSectionHeading()},
                      selectable: false,
                      imageBuilder: (_, _, alt) => Text(alt ?? ''),
                      styleSheet: BanglaPdfPaginator.documentStyle.copyWith(
                        h2: BanglaPdfPaginator.documentStyle.h2?.copyWith(
                          fontSize: 14,
                        ),
                        tableHead: const TextStyle(
                          fontFamily: 'JiggoSans',
                          fontFamilyFallback: ['JiggoBengali'],
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        tableBody: const TextStyle(
                          fontFamily: 'JiggoSans',
                          fontFamilyFallback: ['JiggoBengali'],
                          fontSize: 10,
                        ),
                        tableBorder: TableBorder.all(color: Colors.black54),
                        tableCellsPadding: const EdgeInsets.all(5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BdCvPdf {
  static Future<Uint8List> build({
    required String title,
    required String content,
    Uint8List? photo,
  }) async {
    final parts = CvPaperParts.parse(content);
    if (RegExp(r'[\u0980-\u09FF]').hasMatch('$title\n$content')) {
      final pages = await BanglaPdfPaginator.renderPages(
        content: parts.body,
        traditional: true,
        firstPageHeader: BdCvHeader(title: title, parts: parts, photo: photo),
      );
      final pdf = pw.Document();
      for (final page in pages) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pw.MemoryImage(page), fit: pw.BoxFit.fill),
            ),
          ),
        );
      }
      return pdf.save();
    }
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final widgets = <pw.Widget>[];
    for (final node in md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    ).parseLines(parts.body.split('\n'))) {
      if (node is! md.Element) continue;
      if (node.tag == 'table') {
        final rows = <List<String>>[];
        void visit(md.Node n) {
          if (n is md.Element) {
            if (n.tag == 'tr') {
              rows.add([
                for (final c in n.children ?? <md.Node>[])
                  if (c is md.Element && (c.tag == 'th' || c.tag == 'td'))
                    c.textContent,
              ]);
            } else {
              for (final c in n.children ?? <md.Node>[]) {
                visit(c);
              }
            }
          }
        }

        visit(node);
        if (rows.isNotEmpty) {
          widgets.add(
            pw.TableHelper.fromTextArray(
              headers: rows.first,
              data: rows.skip(1).toList(),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              border: pw.TableBorder.all(width: .5),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          );
        }
      } else if (RegExp(r'^h[1-6]$').hasMatch(node.tag)) {
        widgets.add(
          pw.Container(
            width: double.infinity,
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            margin: const pw.EdgeInsets.only(top: 14, bottom: 8),
            child: pw.Text(
              node.textContent,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
        );
      } else if (node.tag == 'ul' || node.tag == 'ol') {
        for (final item in node.children ?? <md.Node>[]) {
          if (item is md.Element && item.tag == 'li') {
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5, left: 8),
                child: pw.Text(
                  '- ${item.textContent}',
                  style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
                ),
              ),
            );
          }
        }
      } else {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              node.textContent,
              style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
            ),
          ),
        );
      }
    }
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 30,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        footer: (c) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${c.pageNumber} / ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Center(
            child: pw.Text(
              cvPrintTitle(title),
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _plain(parts.name),
                      style: pw.TextStyle(
                        fontSize: 21,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      _plain(parts.contacts),
                      style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 4),
                    ),
                  ],
                ),
              ),
              if (photo != null) ...[
                pw.SizedBox(width: 20),
                pw.Container(
                  width: 85,
                  height: 110,
                  padding: const pw.EdgeInsets.all(2),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: .5),
                  ),
                  child: pw.Image(
                    pw.MemoryImage(photo),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 14),
          ...widgets,
        ],
      ),
    );
    return pdf.save();
  }
}
