import 'package:flutter/services.dart';

import 'pdf_edit_model.dart';

Future<PickedEditPdf?> pickEditPdf() async {
  const channel = MethodChannel('jiggo/pdf_files');
  final result = await channel.invokeMapMethod<String, dynamic>('openPdf');
  if (result == null) return null;
  final picked = PickedEditPdf(
    result['name'] as String,
    result['bytes'] as Uint8List,
  );
  picked.validate();
  return picked;
}
