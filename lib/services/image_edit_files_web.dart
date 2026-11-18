import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pdf_delivery.dart';

class PlatformImageFiles {
  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(
        type: filename.endsWith('.png') ? 'image/png' : 'image/jpeg',
      ),
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

  Future<PdfDelivery> share(Uint8List bytes, String filename) async {
    final file = web.File(
      [bytes.toJS].toJS,
      filename,
      web.FilePropertyBag(
        type: filename.endsWith('.png') ? 'image/png' : 'image/jpeg',
      ),
    );
    final data = web.ShareData(files: [file].toJS, title: filename);
    bool supported;
    try {
      supported = web.window.navigator.canShare(data);
    } catch (_) {
      supported = false;
    }
    if (!supported) return save(bytes, filename);
    try {
      await web.window.navigator.share(data).toDart;
      return PdfDelivery.shareOpened;
    } catch (_) {
      // Do not trigger an unexpected download if a user dismisses the sheet.
      return PdfDelivery.cancelled;
    }
  }
}
