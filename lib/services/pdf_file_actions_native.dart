import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import 'pdf_delivery.dart';

class PlatformPdfFiles {
  static const _channel = MethodChannel('jiggo/pdf_files');
  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('pdf-save-platform');
    }
    final saved = await _channel.invokeMethod<bool>('savePdf', {
      'bytes': bytes,
      'filename': filename,
    });
    return saved == true ? PdfDelivery.saved : PdfDelivery.cancelled;
  }

  Future<PdfDelivery> share(Uint8List bytes, String filename) async =>
      await Printing.sharePdf(bytes: bytes, filename: filename)
      ? PdfDelivery.shareOpened
      : PdfDelivery.cancelled;
}
