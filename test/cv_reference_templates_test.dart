import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/services/cv_reference_templates.dart';
import 'package:jiggo/services/guided_document_model.dart';

import 'bd_cv_test.dart' show sampleCv;
import 'guided_document_screen_test.dart' show boot, tap;
import 'support/memory_guided_drafts.dart';

Future<void> fonts() async {
  for (final item in [
    ('JiggoSans', 'assets/fonts/NotoSans-Regular.ttf'),
    ('JiggoBengali', 'assets/fonts/NotoSansBengali-Regular.ttf'),
  ]) {
    final loader = FontLoader(item.$1)..addFont(rootBundle.load(item.$2));
    await loader.load();
  }
}

void main() {
  test('Both layouts keep the same facts, including education table cells and custom sections', () {
    final doc = sampleCv()
      ..values.addAll({
        'cvDob': '2000-01-01',
        'cvNationality': 'Bangladeshi',
        'cvHobbies': 'Reading',
        'cvPersonal': 'Personal detail supplied by the applicant',
      });
    final side = CvTemplateData.parse(doc.localContent, sidebar: true);
    expect(side.side.map((b) => b.text).join('\n'), contains('Reading'));
    expect(side.side.map((b) => b.text).join('\n'), contains('Bangladeshi'));
    final all = side.body.map((b) => b.text).join('\n');
    expect(all, contains('4.50 / 5.00'));
    expect(all, contains('Sample College'));
    expect(all, isNot(contains('Reading')));
    final classic = CvTemplateData.parse(doc.localContent, sidebar: false);
    expect(classic.body.map((b) => b.text).join('\n'), contains('Reading'));
    expect(classic.side, isEmpty);
    final custom = CvTemplateData.parse(
      '${doc.localContent}\n\n## A custom section\n\nKeep this user edit.',
      sidebar: true,
    );
    expect(
      custom.body.map((b) => b.text).join('\n'),
      contains('Keep this user edit.'),
    );
  });
  for (final design in referenceCvDesigns) {
    for (final bn in [false, true]) {
      testWidgets(
        'Exports the selected layout with photo and real PDF bytes: $design $bn',
        (t) async {
          await t.runAsync(() async {
            await fonts();
            final doc = sampleCv(bn: bn)
              ..values['cvHobbies'] = bn ? 'বই পড়া' : 'Reading';
            final photo = Uint8List.fromList(
              img.encodeJpg(
                img.Image(width: 180, height: 230)
                  ..clear(img.ColorRgb8(185, 205, 225)),
              ),
            );
            final bytes = await CvReferencePdf.build(
              content: doc.localContent,
              design: design,
              photo: photo,
              color: 'Teal',
            );
            expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
            if (Platform.environment['JIGGO_CV_QA'] == '1') {
              await File(
                '/tmp/jiggo-${design == 'BD Classic' ? 'classic' : 'sidebar'}-${bn ? 'bn' : 'en'}.pdf',
              ).writeAsBytes(bytes);
            }
          });
          expect(t.takeException(), isNull);
        },
      );
      testWidgets(
        'Preview fits a narrow screen with large system text: $design $bn',
        (t) async {
          await t.binding.setSurfaceSize(const Size(320, 700));
          addTearDown(() => t.binding.setSurfaceSize(null));
          final doc = sampleCv(bn: bn);
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: CvReferencePaper(
                      content: doc.localContent,
                      design: design,
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'Pagination retains the last body and sidebar details across pages',
    (t) async {
      await t.runAsync(() async {
        await fonts();
        final doc = sampleCv()
          ..values['cvPersonal'] = '${'A real personal detail. ' * 20}SIDE_END';
        final content =
            '${doc.localContent}\n\n## More experience\n\n${List.generate(24, (i) => '${'Detailed work supplied by the applicant. ' * 8} Item $i.').join('\n\n')}\n\nBODY_END';
        final pages = await CvReferencePdf.paginate(
          content,
          design: 'Modern Sidebar',
        );
        expect(pages.length, greaterThan(1));
        expect(
          pages.expand((p) => p.body).map((b) => b.text).join(''),
          contains('BODY_END'),
        );
        expect(
          pages.expand((p) => p.side).map((b) => b.text).join(''),
          contains('SIDE_END'),
        );
        if (Platform.environment['JIGGO_CV_QA'] == '1') {
          await File('/tmp/jiggo-sidebar-long.pdf').writeAsBytes(
            await CvReferencePdf.build(
              content: content,
              design: 'Modern Sidebar',
            ),
          );
        }
      });
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Switching templates and sidebar colour preserves edited text and the saved draft',
    (t) async {
      final store = MemoryGuidedDrafts(), doc = sampleCv()..step = 3;
      doc.preview = '${doc.localContent}\n\nKeep my custom edit.';
      await store.write('A', doc.type, jsonEncode(doc.toJson()));
      await boot(t, doc.type, store);
      await tap(t, find.byKey(const ValueKey('cv-design')));
      await t.tap(find.text('Modern Sidebar').last);
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('cv-color-Navy')));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final restored = GuidedDocument.decode(
        doc.type,
        await store.read('A', doc.type),
      );
      expect(restored.design, 'Modern Sidebar');
      expect(restored.v('_cvColor'), 'Navy');
      expect(restored.preview, contains('Keep my custom edit.'));
    },
  );
}
