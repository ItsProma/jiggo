import 'dart:convert';

import 'docx_picked.dart';
export 'docx_picked.dart';

import 'dart:typed_data';

import 'docx_files_native.dart'
    if (dart.library.js_interop) 'docx_files_web.dart'
    as platform;
import 'scan_pdf_builder.dart' show scanPdfFilename;
export 'pdf_delivery.dart';
import 'pdf_delivery.dart';

abstract class DocxFiles {
  Future<DocxPicked?> pick();
  Future<PdfDelivery> save(Uint8List bytes, String name);
  Future<PdfDelivery> share(Uint8List bytes, String name);
}

class DeviceDocxFiles implements DocxFiles {
  final _files = platform.PlatformDocxFiles();
  @override
  Future<DocxPicked?> pick() => _files.pick();
  @override
  Future<PdfDelivery> save(Uint8List bytes, String name) =>
      _files.save(bytes, name);
  @override
  Future<PdfDelivery> share(Uint8List bytes, String name) =>
      _files.share(bytes, name);
}

String docxFilename(String title) {
  final base = scanPdfFilename(
    title.replaceFirst(RegExp(r'\.docx$', caseSensitive: false), ''),
  ).replaceFirst(RegExp(r'\.pdf$'), '');
  final safe = StringBuffer();
  var bytes = 0, count = 0;
  for (final rune in base.runes) {
    final part = String.fromCharCode(rune);
    final size = utf8.encode(part).length;
    if (bytes + size > 180 || count >= 70) break;
    safe.write(part);
    bytes += size;
    count++;
  }
  return '${safe.isEmpty ? 'jiggo_document' : safe.toString()}_edited.docx';
}
