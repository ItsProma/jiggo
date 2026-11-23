import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/services/guided_document_model.dart';
import 'package:jiggo/services/cv_education.dart';
import 'package:jiggo/services/cv_photo.dart';
import 'package:jiggo/services/bd_cv_pdf.dart';

GuidedDocument sampleCv({bool bn = false}) {
  final d = GuidedDocument('CV / Resume')
    ..language = bn ? 'Bangla' : 'English'
    ..values.addAll({
      'name': bn ? 'নমুনা নাম' : 'Sample Applicant',
      'email': 'sample@example.com',
      'phone': '01234567890',
      'cvAddress': bn ? 'সিলেট, বাংলাদেশ' : 'Sylhet, Bangladesh',
      'cvObjective': bn
          ? 'নিজের দক্ষতা কাজে লাগিয়ে প্রতিষ্ঠানে অবদান রাখতে চাই।'
          : 'Seeking an opportunity to contribute my design skills and continue learning.',
      'skills': bn
          ? 'গ্রাফিক ডিজাইন, Microsoft Word'
          : 'Graphic design, Microsoft Word',
      'languages': bn ? 'বাংলা ও English' : 'Bangla and English',
      'noExperience': 'yes',
      '_cvDeclaration': 'yes',
    });
  d.education.add(
    cvEducationPrefix +
        jsonEncode({
          'degree': 'HSC',
          'institution': bn ? 'নমুনা কলেজ' : 'Sample College',
          'subject': bn ? 'ব্যবসায় শিক্ষা' : 'Business Studies',
          'board': bn ? 'সিলেট' : 'Sylhet',
          'year': '2022',
          'result': '4.50 / 5.00',
        }),
  );
  return d;
}

void main() {
  test('BD layout preserves structured education, omits unstated facts and only includes a chosen declaration', () {
    final d = sampleCv();
    expect(d.design, 'BD Traditional');
    expect(d.localContent, contains('| Exam / Degree |'));
    expect(d.localContent, contains('4.50 / 5.00'));
    expect(d.localContent, isNot(contains(cvEducationPrefix)));
    expect(d.localContent, contains('Declaration'));
    d.values.remove('_cvDeclaration');
    expect(d.localContent, isNot(contains('Declaration')));
    expect(d.localContent, isNot(contains('Nationality')));
    expect(d.localContent, isNot(contains('Father')));
    final restored = GuidedDocument.decode(d.type, jsonEncode(d.toJson()));
    expect(restored.education, d.education);
    expect(restored.design, 'BD Traditional');
  });
  testWidgets(
    'Photo preparation strips bulky originals, survives local draft round trip and never enters AI instructions',
    (t) async {
      await t.runAsync(() async {
        final original = Uint8List.fromList(
          img.encodePng(
            img.Image(width: 800, height: 1000)
              ..clear(img.ColorRgb8(70, 90, 150)),
          ),
        );
        final bytes = await prepareCvPhoto(original);
        expect(bytes.length, lessThanOrEqualTo(67500));
        final d = sampleCv()..cvPhoto = base64Encode(bytes);
        final restored = GuidedDocument.decode(d.type, jsonEncode(d.toJson()));
        expect(restored.cvPhoto, d.cvPhoto);
        expect(d.instructions, isNot(contains(d.cvPhoto)));
      });
    },
  );
  for (final bn in [false, true]) {
    testWidgets('Traditional CV exports real complete PDF $bn', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.runAsync(() async {
        for (final f in [
          ('JiggoSans', 'assets/fonts/NotoSans-Regular.ttf'),
          ('JiggoBengali', 'assets/fonts/NotoSansBengali-Regular.ttf'),
        ]) {
          final loader = FontLoader(f.$1)..addFont(rootBundle.load(f.$2));
          await loader.load();
        }
        final d = sampleCv(bn: bn);
        final photo = Uint8List.fromList(
          img.encodeJpg(
            img.Image(width: 180, height: 230)
              ..clear(img.ColorRgb8(200, 215, 235)),
          ),
        );
        final bytes = await BdCvPdf.build(
          title: d.title,
          content: d.localContent,
          photo: photo,
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        if (Platform.environment['JIGGO_CV_QA'] == '1') {
          await File('/tmp/jiggo-bd-${bn ? 'bn' : 'en'}.pdf')
              .writeAsBytes(bytes);
        }
      });
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('A full paper preview fits a narrow viewport', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final d = sampleCv();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BdCvPaper(title: d.title, content: d.localContent),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
