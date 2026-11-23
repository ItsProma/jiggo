
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/pdf_export_service.dart';
import 'package:jiggo/services/bangla_pdf_paginator.dart';

import 'dart:ui' as ui;

void main() {
  testWidgets('English Simple and Modern export real PDF bytes', (t) async {
    await t.runAsync(() async {
      final a = await PdfExportService.buildDocument(
        title: 'Resume',
        content: '# A Person\n\n## Education\n\nA real course.',
      );
      final b = await PdfExportService.buildDocument(
        title: 'Resume',
        content: '# A Person\n\n## Education\n\nA real course.',
        modern: true,
      );
      expect(String.fromCharCodes(a.take(5)), '%PDF-');
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
      expect(a, isNot(b));
    });
  });
  testWidgets(
    'Bangla pagination is A4-sized regardless of phone viewport and splits long sections',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.runAsync(() async {
        for (final item in [
          ('JiggoSans', 'assets/fonts/NotoSans-Regular.ttf'),
          ('JiggoBengali', 'assets/fonts/NotoSansBengali-Regular.ttf'),
        ]) {
          final loader = FontLoader(item.$1)..addFont(rootBundle.load(item.$2));
          await loader.load();
        }
        final content =
            '# জীবনবৃত্তান্ত\n\n## শিক্ষা\n\n${List.generate(9, (i) => '- ${'বাংলা English পড়াশোনা ও কাজের তথ্য। ' * 12}').join('\n')}';
        final pages = await BanglaPdfPaginator.renderPages(
          content: content,
          modern: true,
        );
        expect(pages.length, greaterThan(1));
        for (final bytes in pages) {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 1190);
          expect(frame.image.height, 1684);
          frame.image.dispose();
          codec.dispose();
        }
        final pdf = await PdfExportService.buildDocument(
          title: 'জীবনবৃত্তান্ত',
          content: '## নাম\n\nবাংলা নাম\n\n## দক্ষতা\n\nডিজাইন ও গ্রাহকসেবা',
          modern: true,
        );
        expect(pdf, isA<Uint8List>());
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      });
      expect(t.takeException(), isNull);
    },
  );
}
