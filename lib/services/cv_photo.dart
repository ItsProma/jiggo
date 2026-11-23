
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'pdf_scan_image.dart';

Future<Uint8List> prepareCvPhoto(Uint8List input) async {
  final prepared = await PdfScanImages().prepare(
    input,
    id: 0,
    name: 'cv-photo',
  );
  return compute(_smallPortrait, prepared.preview);
}

Uint8List _smallPortrait(Uint8List bytes) {
  final source = img.decodeJpg(bytes);
  if (source == null) throw const FormatException('cv-photo');
  img.Image resize(int edge) => img.copyResize(
    source,
    width: source.width >= source.height ? edge : null,
    height: source.height > source.width ? edge : null,
  );
  var photo = Uint8List.fromList(img.encodeJpg(resize(480), quality: 75));
  if (photo.length > 67500) {
    photo = Uint8List.fromList(img.encodeJpg(resize(320), quality: 60));
  }
  if (photo.length > 67500) throw const FormatException('cv-photo-size');
  return photo;
}
