import 'package:flutter/services.dart';

import 'docx_codec.dart';
import 'docx_picked.dart';
import 'pdf_delivery.dart';

class PlatformDocxFiles {
  static const _channel = MethodChannel('jiggo/pdf_files');
  Future<DocxPicked?> pick() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('openDocx');
    if (result == null) return null;
    final bytes = result['bytes'] as Uint8List;
    final name = result['name'] as String;
    if (bytes.length > DocxCodec.maxBytes ||
        !name.toLowerCase().endsWith('.docx')) {
      throw const FormatException();
    }
    return DocxPicked(name, bytes);
  }

  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    final ok = await _channel.invokeMethod<bool>('saveDocx', {
      'bytes': bytes,
      'filename': filename,
    });
    return ok == true ? PdfDelivery.saved : PdfDelivery.cancelled;
  }

  Future<PdfDelivery> share(Uint8List bytes, String filename) async {
    final ok = await _channel.invokeMethod<bool>('shareDocx', {
      'bytes': bytes,
      'filename': filename,
    });
    return ok == true ? PdfDelivery.shareOpened : PdfDelivery.cancelled;
  }
}
