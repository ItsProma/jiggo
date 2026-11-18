import 'package:flutter/services.dart';

import 'pdf_delivery.dart';

class PlatformImageFiles {
  static const _channel = MethodChannel('jiggo/pdf_files');
  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    final ok = await _channel.invokeMethod<bool>('saveImage', {
      'bytes': bytes,
      'filename': filename,
    });
    return ok == true ? PdfDelivery.saved : PdfDelivery.cancelled;
  }

  Future<PdfDelivery> share(Uint8List bytes, String filename) async {
    final ok = await _channel.invokeMethod<bool>('shareImage', {
      'bytes': bytes,
      'filename': filename,
    });
    return ok == true ? PdfDelivery.shareOpened : PdfDelivery.cancelled;
  }
}
