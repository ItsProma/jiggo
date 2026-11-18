import 'dart:typed_data';

import 'pdf_delivery.dart';
import 'pdf_file_actions_native.dart'
    if (dart.library.js_interop) 'pdf_file_actions_web.dart'
    as platform;
export 'pdf_delivery.dart';

abstract class PdfFileActions {
  Future<PdfDelivery> save(Uint8List bytes, String filename);
  Future<PdfDelivery> share(Uint8List bytes, String filename);
}

class DevicePdfFileActions implements PdfFileActions {
  final _files = platform.PlatformPdfFiles();
  @override
  Future<PdfDelivery> save(Uint8List bytes, String filename) =>
      _files.save(bytes, filename);
  @override
  Future<PdfDelivery> share(Uint8List bytes, String filename) =>
      _files.share(bytes, filename);
}
