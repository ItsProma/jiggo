import 'package:flutter/services.dart';

import 'text_document.dart';

Future<TextDocument?> pickTextDocument() async {
  const channel = MethodChannel('jiggo/pdf_files');
  final result = await channel.invokeMapMethod<String, dynamic>('openText');
  if (result == null) return null;
  return TextDocument.decode(
    result['name'] as String,
    result['bytes'] as Uint8List,
  );
}
