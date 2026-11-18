import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// All transforms refer to the normalized original. Repeated edits do not
/// repeatedly crop/re-encode the previous preview or alter the user's source.
class ScanCrop {
  final double left, top, width, height;
  const ScanCrop(this.left, this.top, this.width, this.height);
  static const full = ScanCrop(0, 0, 1, 1);
  bool get valid =>
      [left, top, width, height].every((v) => v.isFinite) &&
      left >= 0 &&
      top >= 0 &&
      width > 0 &&
      height > 0 &&
      left + width <= 1.000001 &&
      top + height <= 1.000001;
  ScanCrop within(ScanCrop selection) => ScanCrop(
    left + selection.left * width,
    top + selection.top * height,
    width * selection.width,
    height * selection.height,
  );
  ScanCrop clockwise() =>
      ScanCrop(1 - top - height, left, height, width).clamped();
  ScanCrop clamped() {
    final x = left.clamp(0.0, .999999), y = top.clamp(0.0, .999999);
    return ScanCrop(
      x,
      y,
      width.clamp(.000001, 1 - x),
      height.clamp(.000001, 1 - y),
    );
  }

  List<double> get values => [left, top, width, height];
}

class PdfScanPage {
  final int id;
  final String name;
  final Uint8List original, preview;
  final int width, height, quarterTurns;
  final ScanCrop crop;
  const PdfScanPage({
    required this.id,
    required this.name,
    required this.original,
    required this.preview,
    required this.width,
    required this.height,
    this.quarterTurns = 0,
    this.crop = ScanCrop.full,
  });
  int get retainedBytes =>
      original.length + (identical(original, preview) ? 0 : preview.length);
  bool get edited =>
      quarterTurns != 0 ||
      crop.values.toString() != ScanCrop.full.values.toString();
}

class PdfScanImages {
  static const maxInputBytes = 15 * 1024 * 1024;
  static const maxPixels = 32 * 1000 * 1000;
  static const maxEdge = 2400;
  static const maxPages = 20;
  static const maxRetainedBytes = 48 * 1024 * 1024;

  Future<PdfScanPage> prepare(
    Uint8List bytes, {
    required int id,
    required String name,
  }) async {
    if (bytes.isEmpty || bytes.length > maxInputBytes) {
      throw const FormatException('photo-size');
    }
    final result = await compute(_preparePhoto, bytes);
    final jpeg = result['bytes'] as Uint8List;
    return PdfScanPage(
      id: id,
      name: name,
      original: jpeg,
      preview: jpeg,
      width: result['width'] as int,
      height: result['height'] as int,
    );
  }

  Future<PdfScanPage> transform(
    PdfScanPage page, {
    int? quarterTurns,
    ScanCrop? crop,
  }) async {
    final turns = (quarterTurns ?? page.quarterTurns) % 4;
    final selection = crop ?? page.crop;
    if (!selection.valid) throw const FormatException('photo-crop');
    final result = await compute(_transformPhoto, {
      'bytes': page.original,
      'turns': turns,
      'crop': selection.values,
    });
    final unedited =
        turns == 0 &&
        selection.values.toString() == ScanCrop.full.values.toString();
    return PdfScanPage(
      id: page.id,
      name: page.name,
      original: page.original,
      preview: unedited ? page.original : result['bytes'] as Uint8List,
      width: result['width'] as int,
      height: result['height'] as int,
      quarterTurns: turns,
      crop: selection,
    );
  }
}

Map<String, Object> _preparePhoto(Uint8List bytes) {
  img.Decoder decoder;
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    decoder = img.JpegDecoder();
  } else if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    decoder = img.PngDecoder();
  } else if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    decoder = img.WebPDecoder();
  } else {
    throw const FormatException('photo-format');
  }
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > PdfScanImages.maxPixels) {
    throw const FormatException('photo-dimensions');
  }
  var image = decoder.decodeFrame(0);
  if (image == null) throw const FormatException('photo-format');
  image = img.bakeOrientation(image);
  if (math.max(image.width, image.height) > PdfScanImages.maxEdge) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? PdfScanImages.maxEdge : null,
      height: image.height > image.width ? PdfScanImages.maxEdge : null,
      interpolation: img.Interpolation.average,
    );
  }
  // Flatten transparent inputs onto white and strip camera location/EXIF data.
  if (image.hasAlpha) {
    final white = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 3,
    );
    img.fill(white, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(white, image);
    image = white;
  }
  image.exif = img.ExifData();
  image.textData = null;
  return {
    'bytes': img.encodeJpg(image, quality: 94),
    'width': image.width,
    'height': image.height,
  };
}

Map<String, Object> _transformPhoto(Map<String, Object> data) {
  var image = img.decodeJpg(data['bytes'] as Uint8List);
  if (image == null) throw const FormatException('photo-format');
  final turns = data['turns'] as int;
  if (turns != 0) image = img.copyRotate(image, angle: 90 * turns);
  final rect = (data['crop'] as List<double>);
  final x = (rect[0] * image.width).round().clamp(0, image.width - 1);
  final y = (rect[1] * image.height).round().clamp(0, image.height - 1);
  final right = ((rect[0] + rect[2]) * image.width).round().clamp(
    x + 1,
    image.width,
  );
  final bottom = ((rect[1] + rect[3]) * image.height).round().clamp(
    y + 1,
    image.height,
  );
  image = img.copyCrop(image, x: x, y: y, width: right - x, height: bottom - y);
  image.exif = img.ExifData();
  return {
    'bytes': img.encodeJpg(image, quality: 94),
    'width': image.width,
    'height': image.height,
  };
}
