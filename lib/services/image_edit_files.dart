import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'image_edit_model.dart';
import 'image_edit_files_native.dart'
    if (dart.library.js_interop) 'image_edit_files_web.dart'
    as platform;
import 'pdf_delivery.dart';
export 'pdf_delivery.dart';

class PickedEditorImage {
  final String name;
  final Uint8List bytes;
  const PickedEditorImage(this.name, this.bytes);
}

abstract class ImageEditFiles {
  Future<PickedEditorImage?> pick();
  Future<PdfDelivery> save(Uint8List bytes, String name);
  Future<PdfDelivery> share(Uint8List bytes, String name);
}

class DeviceImageEditFiles implements ImageEditFiles {
  final _files = platform.PlatformImageFiles();
  @override
  Future<PickedEditorImage?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    if (await file.length() > EditedImage.maxInputBytes) {
      throw const FormatException('image-input');
    }
    return PickedEditorImage(file.name, await file.readAsBytes());
  }

  @override
  Future<PdfDelivery> save(Uint8List bytes, String name) =>
      _files.save(bytes, name);
  @override
  Future<PdfDelivery> share(Uint8List bytes, String name) =>
      _files.share(bytes, name);
}

String editedImageFilename(String title, String format) {
  if (!['png', 'jpg'].contains(format)) {
    throw const FormatException('image-format');
  }
  final base = title
      .replaceFirst(RegExp(r'\.(png|jpe?g)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  final safe = StringBuffer();
  var bytes = 0, count = 0;
  for (final rune in base.runes) {
    final part = String.fromCharCode(rune),
        size = utf8.encode(String.fromCharCode(rune)).length;
    if (bytes + size > 180 || count >= 70) break;
    safe.write(part);
    bytes += size;
    count++;
  }
  return '${safe.isEmpty ? 'jiggo_image' : safe.toString()}_edited.$format';
}
