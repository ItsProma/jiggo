import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'pdf_edit_model.dart';

Future<PickedEditPdf?> pickEditPdf() async {
  final done = Completer<PickedEditPdf?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.pdf,application/pdf';
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
          if (file.size > PickedEditPdf.maxBytes) throw const FormatException();
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          final picked = PickedEditPdf(file.name, bytes);
          picked.validate();
          done.complete(picked);
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
