import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/scan_image.dart';

void main() {
  final jpeg = Uint8List.fromList([
    0xff,
    0xd8,
    0xff,
    0xe0,
  ]);

  test('Detects JPEG bytes without trusting a file extension', () {
    expect(ScanImage.validate(jpeg), 'image/jpeg');
  });

  test('Detects PNG and WebP signatures', () {
    final png = Uint8List.fromList([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);

    final webp = Uint8List.fromList(
      'RIFF0000WEBP'.codeUnits,
    );

    expect(ScanImage.validate(png), 'image/png');
    expect(ScanImage.validate(webp), 'image/webp');
  });

  test('Rejects empty, truncated and non-image bytes', () {
    final invalidImages = [
      Uint8List(0),
      Uint8List.fromList([0xff, 0xd8]),
      Uint8List.fromList('not an image'.codeUnits),
    ];

    for (final bytes in invalidImages) {
      expect(
        () => ScanImage.validate(bytes),
        throwsFormatException,
      );
    }
  });

  test('Final payload accepts 2 MB and rejects larger input', () {
    final maximum = Uint8List(ScanImage.maxBytes)
      ..setAll(0, jpeg);

    final oversized = Uint8List(ScanImage.maxBytes + 1)
      ..setAll(0, jpeg);

    expect(ScanImage.validate(maximum), 'image/jpeg');

    expect(
      () => ScanImage.validate(oversized),
      throwsFormatException,
    );
  });
}