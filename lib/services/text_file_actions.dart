import 'text_file_actions_native.dart'
    if (dart.library.js_interop) 'text_file_actions_web.dart'
    as platform;
import 'pdf_delivery.dart';
export 'text_file_name.dart';
export 'pdf_delivery.dart';

abstract class TextFileActions {
  Future<PdfDelivery> save(String text, String filename);
  Future<PdfDelivery> share(String text, String title);
}

class DeviceTextFileActions implements TextFileActions {
  final _files = platform.PlatformTextFiles();
  @override
  Future<PdfDelivery> save(String text, String filename) =>
      _files.save(text, filename);
  @override
  Future<PdfDelivery> share(String text, String title) =>
      _files.share(text, title);
}
