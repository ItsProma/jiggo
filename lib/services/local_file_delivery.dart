import 'dart:convert';
import 'dart:typed_data';

import 'local_file_model.dart';
import 'docx_files.dart';
import 'image_edit_files.dart';
import 'pdf_file_actions.dart';
import 'text_file_actions.dart';
export 'pdf_delivery.dart';

class LocalFileDelivery {
  Future<PdfDelivery> deliver(
    LocalFileInfo info,
    Uint8List bytes, {
    required bool share,
  }) {
    switch (info.kind) {
      case LocalFileKind.pdf:
        final files = DevicePdfFileActions();
        return share
            ? files.share(bytes, info.name)
            : files.save(bytes, info.name);
      case LocalFileKind.docx:
        final files = DeviceDocxFiles();
        return share
            ? files.share(bytes, info.name)
            : files.save(bytes, info.name);
      case LocalFileKind.txt:
        final files = DeviceTextFileActions();
        final text = utf8.decode(bytes);
        return share
            ? files.share(text, info.name)
            : files.save(text, info.name);
      case LocalFileKind.png:
      case LocalFileKind.jpg:
        final files = DeviceImageEditFiles();
        return share
            ? files.share(bytes, info.name)
            : files.save(bytes, info.name);
    }
  }
}
