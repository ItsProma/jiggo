import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'pdf_delivery.dart';
import 'text_file_name.dart';

class PlatformTextFiles {
  Future<PdfDelivery> save(String text, String filename) async {
    final blob = web.Blob(
      [text.toJS].toJS,
      web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body?.append(link);
    try {
      link.click();
    } finally {
      link.remove();
      Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
    }
    return PdfDelivery.downloadRequested;
  }

  Future<PdfDelivery> share(String text, String title) async {
    final data = web.ShareData(text: text, title: title);
    bool supported;
    try {
      supported = web.window.navigator.canShare(data);
    } catch (_) {
      supported = false;
    }
    if (!supported) return save(text, handwritingFilename(title));
    try {
      await web.window.navigator.share(data).toDart;
      return PdfDelivery.shareOpened;
    } catch (_) {
      return PdfDelivery.cancelled;
    }
  }
}
