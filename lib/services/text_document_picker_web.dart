import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'text_document.dart';

Future<TextDocument?> pickTextDocument() async {
  final done = Completer<TextDocument?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.txt,text/plain';
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
          if (file.size > TextDocument.maxBytes) throw const FormatException();
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          done.complete(TextDocument.decode(file.name, bytes));
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
