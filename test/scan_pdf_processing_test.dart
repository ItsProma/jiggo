import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/services/pdf_file_actions.dart';
import 'package:jiggo/services/pdf_scan_image.dart';
import 'package:jiggo/services/scan_pdf_builder.dart';
import 'package:jiggo/widgets/scan_crop_editor.dart';

Uint8List quadrantPhoto({int width = 240, int height = 160}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    final left = pixel.x < width / 2, top = pixel.y < height / 2;
    pixel.setRgb(top && left ? 255 : 0, top && !left ? 255 : 0, !top ? 255 : 0);
  }
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final processor = PdfScanImages();
  test('EXIF orientation is applied and camera metadata is removed', () async {
    final image = img.Image(width: 120, height: 80);
    img.fill(image, color: img.ColorRgb8(255, 0, 0));
    image.exif.imageIfd.orientation = 6;
    image.exif.imageIfd.make = 'Camera metadata';
    final page = await processor.prepare(
      img.encodeJpg(image),
      id: 1,
      name: 'phone.jpg',
    );
    expect([page.width, page.height], [80, 120]);
    final decoded = img.decodeJpg(page.preview)!;
    expect(decoded.exif.imageIfd.make, isNull);
    expect(decoded.exif.imageIfd.orientation, isNull);
  });

  test(
    'Large photos resize proportionally and transparent PNG becomes white',
    () async {
      final source = img.Image(width: 3000, height: 300, numChannels: 4);
      final page = await processor.prepare(
        img.encodePng(source),
        id: 1,
        name: 'wide.png',
      );
      expect([page.width, page.height], [2400, 240]);
      final pixel = img.decodeJpg(page.preview)!.getPixel(100, 100);
      expect([pixel.r, pixel.g, pixel.b], everyElement(greaterThan(250)));
    },
  );

  test('Crops compose against the original; rotation preserves selected content; reset is reversible', () async {
    final page = await processor.prepare(
      quadrantPhoto(),
      id: 7,
      name: 'page.png',
    );
    final first = await processor.transform(
      page,
      crop: const ScanCrop(0, 0, .5, .5),
    );
    expect([first.width, first.height], [120, 80]);
    final second = await processor.transform(
      first,
      crop: first.crop.within(const ScanCrop(.25, .25, .5, .5)),
    );
    expect([second.width, second.height], [60, 40]);
    final rotated = await processor.transform(
      first,
      quarterTurns: 1,
      crop: first.crop.clockwise(),
    );
    expect([rotated.width, rotated.height], [80, 120]);
    final center = img.decodeJpg(rotated.preview)!.getPixel(40, 60);
    expect(center.r, greaterThan(240));
    expect(center.g, lessThan(15));
    final reset = await processor.transform(
      second,
      quarterTurns: 0,
      crop: ScanCrop.full,
    );
    expect(reset.preview, orderedEquals(page.original));
    expect([reset.width, reset.height], [240, 160]);
    expect(page.crop, ScanCrop.full);
  });

  test(
    'Invalid inputs and crop geometry fail without manufacturing a PDF page',
    () async {
      await expectLater(
        processor.prepare(
          Uint8List.fromList([1, 2, 3]),
          id: 1,
          name: 'bad.pdf',
        ),
        throwsFormatException,
      );
      await expectLater(
        processor.prepare(
          Uint8List(PdfScanImages.maxInputBytes + 1),
          id: 1,
          name: 'huge.jpg',
        ),
        throwsFormatException,
      );
      final page = await processor.prepare(
        quadrantPhoto(),
        id: 1,
        name: 'good.png',
      );
      await expectLater(
        processor.transform(page, crop: const ScanCrop(-.2, 0, 1, 1)),
        throwsFormatException,
      );
      await expectLater(
        ScanPdfBuilder().build([], 'Empty'),
        throwsFormatException,
      );
    },
  );

  test('Crop corner movement and translation remain inside the image', () {
    var crop = moveScanCrop(ScanCrop.full, ScanCropHandle.topLeft, .2, .3);
    expect(crop.values, [.2, .3, .8, .7]);
    crop = moveScanCrop(crop, ScanCropHandle.bottomRight, -.3, -.2);
    expect(crop.width, closeTo(.5, .00001));
    crop = moveScanCrop(crop, ScanCropHandle.move, 10, 10);
    expect(crop.valid, isTrue);
    expect(crop.left + crop.width, closeTo(1, .000001));
    crop = moveScanCrop(crop, ScanCropHandle.topLeft, 100, 100);
    expect(crop.width, closeTo(.05, .000001));
    expect(crop.height, closeTo(.05, .000001));
  });

  test('PDF filename is a leaf filename with a single safe suffix', () {
    expect(scanPdfFilename('My pages.PDF'), 'My pages.pdf');
    expect(scanPdfFilename(''), 'jiggo_scan.pdf');
    expect(scanPdfFilename('../../notes:*?.pdf'), isNot(contains('/')));
    expect(scanPdfFilename('বাংলা নোট'), 'বাংলা নোট.pdf');
  });

  test('Document photo text is embedded at its prepared resolution', () async {
    final image = img.Image(width: 900, height: 1200);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var line = 0; line < 18; line++) {
      img.drawString(
        image,
        'Jiggo scan quality - line ${line + 1}',
        font: img.arial24,
        x: 70,
        y: 90 + line * 48,
        color: img.ColorRgb8(20, 20, 20),
      );
    }
    final prepared = await processor.prepare(
      img.encodePng(image),
      id: 1,
      name: 'reading.png',
    );
    final bytes = await ScanPdfBuilder().build([prepared], 'Reading QA');
    expect(
      String.fromCharCodes(bytes),
      contains(String.fromCharCodes(prepared.preview)),
    );
    final destination = Platform.environment['JIGGO_SCAN_PDF_QA_DIR'];
    if (destination != null) {
      File('$destination/reading_qa.pdf').writeAsBytesSync(bytes);
    }
  });

  test(
    'Android save channel passes PDF bytes and honors cancellation',
    () async {
      const channel = MethodChannel('jiggo/pdf_files');
      MethodCall? captured;
      var saved = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return saved;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bytes = Uint8List.fromList('%PDF-1.7'.codeUnits);
      final files = DevicePdfFileActions();
      expect(await files.save(bytes, 'scan.pdf'), PdfDelivery.cancelled);
      expect(captured!.method, 'savePdf');
      expect((captured!.arguments as Map)['bytes'], bytes);
      saved = true;
      expect(await files.save(bytes, 'scan.pdf'), PdfDelivery.saved);
    },
  );

  test(
    'Exported PDF keeps page order, dimensions and a complete file structure',
    () async {
      final landscape = await processor.prepare(
        quadrantPhoto(),
        id: 1,
        name: 'colors.png',
      );
      final portrait = await processor.transform(
        landscape,
        quarterTurns: 1,
        crop: ScanCrop.full,
      );
      final bytes = await ScanPdfBuilder().build([
        portrait,
        landscape,
      ], 'Scan QA');
      final text = String.fromCharCodes(bytes);
      expect(text, startsWith('%PDF-'));
      expect(text.trimRight(), endsWith('%%EOF'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
      final destination = Platform.environment['JIGGO_SCAN_PDF_QA_DIR'];
      if (destination != null) {
        final dir = Directory(destination)..createSync(recursive: true);
        File('${dir.path}/scan_qa.pdf').writeAsBytesSync(bytes);
      }
    },
  );
}
