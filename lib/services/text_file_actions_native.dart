import 'dart:convert';

import 'package:flutter/services.dart';

import 'pdf_delivery.dart';

class PlatformTextFiles {
  static const _channel = MethodChannel('jiggo/pdf_files');
  Future<PdfDelivery> save(String text, String filename) async {
    final result = await _channel.invokeMethod<bool>('saveText', {
      'bytes': Uint8List.fromList(utf8.encode(text)),
      'filename': filename,
    });
    return result == true ? PdfDelivery.saved : PdfDelivery.cancelled;
  }

  Future<PdfDelivery> share(String text, String title) async {
    final result = await _channel.invokeMethod<bool>('shareText', {
      'text': text,
      'title': title,
    });
    return result == true ? PdfDelivery.shareOpened : PdfDelivery.cancelled;
  }
}
