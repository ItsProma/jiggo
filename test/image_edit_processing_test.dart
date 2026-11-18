import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/services/image_edit_model.dart';
import 'package:jiggo/services/image_edit_processor.dart';
import 'package:jiggo/services/image_edit_files.dart';
import 'package:jiggo/services/pdf_scan_image.dart' show ScanCrop;

Uint8List transparentPhoto({int width = 240, int height = 160}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (final p in image) {
    if (p.x < width / 2) {
      p.setRgba(255, 0, 0, p.y < height / 2 ? 255 : 128);
    } else {
      p.setRgba(0, 0, 255, p.y < height / 2 ? 255 : 0);
    }
  }
  return img.encodePng(image);
}

EditedImage prepared(Uint8List bytes) {
  final p = normalizeEditorImage(bytes);
  return EditedImage(
    p['bytes'] as Uint8List,
    p['width'] as int,
    p['height'] as int,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const processor = ImageEditProcessor();
  setUpAll(() async {
    for (final (name, path) in [
      ('JiggoSans', 'assets/fonts/NotoSans-Regular.ttf'),
      ('JiggoBengali', 'assets/fonts/NotoSansBengali-Regular.ttf'),
    ]) {
      await (FontLoader(name)..addFont(rootBundle.load(path))).load();
    }
  });
  test(
    'PNG preparation keeps partial and full transparency and removes metadata',
    () {
      final source = img.decodePng(transparentPhoto())!;
      source.textData = {'Author': 'Private text'};
      source.exif.imageIfd.make = 'Camera';
      final normalized = prepared(img.encodePng(source));
      final decoded = img.decodePng(normalized.bytes)!;
      expect(decoded.getPixel(30, 120).a, 128);
      expect(decoded.getPixel(200, 120).a, 0);
      expect(decoded.textData, isNull);
      expect(decoded.exif.imageIfd.make, isNull);
      expect(decoded.getPixel(30, 30).r, 255);
    },
  );
  test(
    'JPEG EXIF orientation is applied once and source metadata is stripped',
    () {
      final source = img.Image(width: 120, height: 80);
      img.fill(source, color: img.ColorRgb8(255, 0, 0));
      source.exif.imageIfd.orientation = 6;
      source.exif.imageIfd.make = 'Camera';
      final result = prepared(img.encodeJpg(source));
      expect([result.width, result.height], [80, 120]);
      final decoded = img.decodePng(result.bytes)!;
      expect(decoded.exif.imageIfd.orientation, isNull);
      expect(decoded.exif.imageIfd.make, isNull);
    },
  );
  test('Large images use a bounded proportional working copy', () {
    final source = img.Image(width: 4200, height: 100, numChannels: 4);
    final p = normalizeEditorImage(img.encodePng(source));
    expect(p['width'], 4096);
    expect(p['reduced'], isTrue);
    expect((p['height'] as int) / 4096, closeTo(100 / 4200, .001));
  });
  test('Invalid formats, oversized payloads and forged oversized PNG headers are rejected', () {
    expect(
      () => normalizeEditorImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => normalizeEditorImage(Uint8List(EditedImage.maxInputBytes + 1)),
      throwsFormatException,
    );
    final image = img.Image(width: 2, height: 2);
    expect(
      () => normalizeEditorImage(Uint8List.fromList(img.encodeGif(image))),
      throwsFormatException,
    );
    final huge = transparentPhoto();
    final data = ByteData.sublistView(huge);
    data.setUint32(16, 40000);
    data.setUint32(20, 40000);
    expect(() => normalizeEditorImage(huge), throwsA(anything));
  });
  test(
    'Clockwise rotation and crop preserve pixel placement, opacity and source',
    () async {
      final source = prepared(transparentPhoto());
      final before = Uint8List.fromList(source.bytes);
      final rotated = await processor.rotate(source);
      expect([rotated.width, rotated.height], [160, 240]);
      final r = img.decodePng(rotated.bytes)!;
      expect(r.getPixel(30, 30).a, 128);
      expect(r.getPixel(130, 30).r, 255);
      final crop = await processor.crop(source, const ScanCrop(.5, 0, .5, .5));
      expect([crop.width, crop.height], [120, 80]);
      expect(img.decodePng(crop.bytes)!.getPixel(50, 40).b, 255);
      expect(source.bytes, orderedEquals(before));
    },
  );
  test('Resize is exact, keeps alpha and blocks unsafe target dimensions before allocation', () async {
    final source = prepared(transparentPhoto());
    final resized = await processor.resize(source, 120, 80);
    expect([resized.width, resized.height], [120, 80]);
    expect(img.decodePng(resized.bytes)!.getPixel(100, 60).a, 0);
    await expectLater(processor.resize(source, 0, 20), throwsFormatException);
    await expectLater(
      processor.resize(source, 4096, 4096),
      throwsFormatException,
    );
    expect(
      () => processor.crop(source, const ScanCrop(-.5, 0, 1, 1)),
      throwsFormatException,
    );
  });
  test('Bangla and English labels are painted into pixels and move with later edits', () async {
    final source = prepared(transparentPhoto(width: 640, height: 480));
    const label = ImageLabel('বাংলা English', x: .2, y: .3, size: .08);
    final layout = imageLabelLayout(source, label);
    final box = layout.box;
    layout.dispose();
    final result = await processor.addText(source, label);
    expect(result.bytes, isNot(orderedEquals(source.bytes)));
    final pixel = img
        .decodePng(result.bytes)!
        .getPixel(box.left.round() + 1, box.top.round() + 10);
    expect(pixel.r, lessThan(255));
    final rotated = await processor.rotate(result);
    expect([rotated.width, rotated.height], [480, 640]);
    final resized = await processor.resize(result, 320, 240);
    expect([resized.width, resized.height], [320, 240]);
    expect(
      () => imageLabelLayout(source, ImageLabel('large\n' * 9)),
      throwsFormatException,
    );
    expect(
      () => imageLabelLayout(source, const ImageLabel('text', x: 2)),
      throwsFormatException,
    );
  });
  test('PNG export stays lossless and JPG explicitly flattens transparent pixels onto white', () async {
    final source = prepared(transparentPhoto());
    expect(await processor.export(source, 'png'), same(source.bytes));
    final jpg = imageJpegCopy(source.bytes);
    final decoded = img.decodeJpg(jpg)!;
    final white = decoded.getPixel(200, 120);
    expect([white.r, white.g, white.b], everyElement(greaterThan(245)));
    expect(decoded.exif.imageIfd.make, isNull);
    await expectLater(processor.export(source, 'gif'), throwsFormatException);
  });
  test('Undo/redo restores exact snapshots and new edits discard only the redo branch', () {
    final a = EditedImage(Uint8List.fromList([1]), 1, 1),
        b = EditedImage(Uint8List.fromList([2]), 1, 1),
        c = EditedImage(Uint8List.fromList([3]), 1, 1);
    final history = ImageEditHistory(a);
    history.commit(b);
    history.commit(c);
    history.undo();
    expect(history.current, same(b));
    history.redo();
    expect(history.current, same(c));
    history.undo();
    history.commit(a);
    expect(history.canRedo, isFalse);
    history.undo();
    expect(history.current, same(b));
    expect(history.original, same(a));
  });
  test('History is bounded by steps and retained bytes while reset remains available', () {
    final original = EditedImage(Uint8List(1), 1, 1);
    final history = ImageEditHistory(original);
    for (var i = 0; i < 20; i++) {
      history.commit(EditedImage(Uint8List.fromList([i]), 1, 1));
    }
    var count = 0;
    while (history.canUndo) {
      history.undo();
      count++;
    }
    expect(count, 12);
    final big = ImageEditHistory(original);
    for (var i = 0; i < 4; i++) {
      big.commit(EditedImage(Uint8List(24 * 1024 * 1024), 1, 1));
    }
    expect(
      big.retainedBytes,
      lessThanOrEqualTo(ImageEditHistory.maxRetainedBytes),
    );
    expect(big.original, same(original));
    big.commit(original);
    expect(big.current, same(original));
  });
  test('Image copy names keep their format and suffix within Unicode filesystem limits', () {
    for (final title in ['../a/b.png', 'বাংলা' * 40, '😀' * 140]) {
      final name = editedImageFilename(title, 'png');
      expect(name.endsWith('_edited.png'), isTrue);
      expect(name, isNot(contains('/')));
      expect(utf8.encode(name).length, lessThanOrEqualTo(200));
    }
    expect(editedImageFilename('Photo.JPG', 'jpg'), 'Photo_edited.jpg');
  });
}
