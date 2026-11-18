import 'package:flutter/foundation.dart';

import 'docx_codec.dart';

List<Map<String, dynamic>> decodeDocx(Uint8List bytes) =>
    DocxCodec().decode(bytes);
Uint8List encodeDocx(List<Map<String, dynamic>> delta) =>
    DocxCodec().encode(delta);

class DocxProcessor {
  const DocxProcessor();
  Future<List<Map<String, dynamic>>> decode(Uint8List bytes) =>
      compute(decodeDocx, bytes);
  Future<Uint8List> encode(List<Map<String, dynamic>> delta) =>
      compute(encodeDocx, delta);
}
