import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'pdf_delivery.dart';

import 'package:web/web.dart' as web;

import 'docx_codec.dart';
import 'docx_picked.dart';

Future<DocxPicked?> pickDocx() async {
  final done = Completer<DocxPicked?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept =
        '.docx,application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  input.style.display = 'none';
  web.document.body?.append(input);
  input.addEventListener(
    'cancel',
    ((web.Event event) {
      if (!done.isCompleted) done.complete(null);
    }).toJS,
  );
  input.addEventListener(
    'change',
    ((web.Event event) {
      () async {
        try {
          final file = input.files?.item(0);
          if (file == null) {
            done.complete(null);
            return;
          }
          if (file.size > DocxCodec.maxBytes) throw const FormatException();
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          if (!file.name.toLowerCase().endsWith('.docx')) {
            throw const FormatException();
          }
          done.complete(DocxPicked(file.name, bytes));
        } catch (e, s) {
          done.completeError(e, s);
        }
      }();
    }).toJS,
  );
  try {
    input.click();
    return await done.future;
  } finally {
    input.remove();
  }
}

class PlatformDocxFiles {
  Future<DocxPicked?> pick() => pickDocx();
  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(
        type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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
        type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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
