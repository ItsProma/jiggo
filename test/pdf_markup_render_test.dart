import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/services/pdf_markup_model.dart';
import 'package:jiggo/services/pdf_markup_renderer.dart';
import 'package:jiggo/services/image_edit_model.dart';

EditedImage white() {
  final i = img.Image(width: 400, height: 300, numChannels: 4);
  img.fill(i, color: img.ColorRgba8(255, 255, 255, 255));
  return EditedImage(img.encodePng(i), 400, 300);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (name, path) in [
      ('JiggoSans', 'assets/fonts/NotoSans-Regular.ttf'),
      ('JiggoBengali', 'assets/fonts/NotoSansBengali-Regular.ttf'),
    ]) {
      await (FontLoader(name)..addFont(rootBundle.load(path))).load();
    }
  });
  test('draw highlight and signature render to actual pixels without altering background', () async {
    final base = white(), before = base64Encode(white().bytes);
    final result = await renderPdfMarks(base, [
      PdfMark(
        kind: PdfMarkKind.highlight,
        points: const [Offset(.1, .1), Offset(.4, .4)],
        color: 0xffffd600,
      ),
      PdfMark(
        kind: PdfMarkKind.pen,
        points: const [Offset(.1, .6), Offset(.8, .6)],
        color: 0xffee0000,
        size: .02,
      ),
      PdfMark(
        kind: PdfMarkKind.signature,
        points: const [Offset(.1, .8), Offset(.3, .7), Offset(.4, .9)],
        color: 0xff111111,
        size: .01,
      ),
    ]);
    final out = img.decodePng(result.bytes)!;
    expect(out.getPixel(80, 60).b, lessThan(240));
    expect(out.getPixel(80, 60).r, 255);
    expect(out.getPixel(200, 180).r, greaterThan(200));
    expect(out.getPixel(200, 180).g, lessThan(50));
    expect(base64Encode(base.bytes), before);
    expect(result.width, 400);
    expect(result.height, 300);
  });
  test('Bangla English text and transparent sticker render; image aspect is preserved', () async {
    final sticker = img.Image(width: 20, height: 40, numChannels: 4);
    img.fill(sticker, color: img.ColorRgba8(0, 0, 255, 255));
    final bytes = img.encodePng(sticker);
    final mark = PdfMark(
      kind: PdfMarkKind.image,
      points: const [Offset(.6, .1)],
      size: .2,
      image: bytes,
      imageAspect: .5,
    );
    final r = pdfMarkRect(mark, const Size(400, 300));
    expect(r.width / r.height, closeTo(.5, .001));
    final output = await renderPdfMarks(white(), [
      mark,
      PdfMark(
        kind: PdfMarkKind.text,
        points: const [Offset(.05, .7)],
        text: 'বাংলা Hello',
        size: .07,
      ),
    ]);
    final pixels = img.decodePng(output.bytes)!;
    expect(pixels.getPixel(260, 60).b, 255);
    expect(pixels.getPixel(260, 60).r, 0);
    expect(
      pixels
          .where((p) => p.y > 200 && p.r < 100 && p.g < 100 && p.b < 100)
          .length,
      greaterThan(40),
    );
  });
  test('text that cannot fit and invalid coordinates are rejected', () async {
    final m = PdfMark(
      kind: PdfMarkKind.text,
      points: const [Offset.zero],
      text: List.filled(300, 'W').join(),
      size: .45,
    );
    expect(pdfMarkTextFits(m, const Size(400, 300)), false);
    await expectLater(renderPdfMarks(white(), [m]), throwsFormatException);
    expect(
      PdfMark(
        kind: PdfMarkKind.pen,
        points: const [Offset(double.nan, 0)],
      ).valid,
      false,
    );
  });
}
