import 'dart:typed_data';

import 'docx_files.dart';
import 'image_edit_files.dart';
import 'pdf_edit_picker.dart';
import 'pdf_edit_model.dart';
import 'text_document_picker.dart';

/// Serve the saved copy once. Subsequent Open actions use the normal picker.
class SavedTextPicker extends DeviceTextDocumentPicker {
  final String name;
  Uint8List? _bytes;
  SavedTextPicker(this.name, Uint8List bytes) : _bytes = bytes;
  @override
  Future<TextDocument?> pick() async {
    final bytes = _bytes;
    _bytes = null;
    return bytes == null ? super.pick() : TextDocument.decode(name, bytes);
  }
}

class SavedPdfPicker extends DevicePdfEditPicker {
  final String name;
  Uint8List? _bytes;
  SavedPdfPicker(this.name, Uint8List bytes) : _bytes = bytes;
  @override
  Future<PickedEditPdf?> pick() async {
    final bytes = _bytes;
    _bytes = null;
    return bytes == null ? super.pick() : PickedEditPdf(name, bytes);
  }
}

class SavedDocxFiles extends DeviceDocxFiles {
  final String name;
  Uint8List? _bytes;
  SavedDocxFiles(this.name, Uint8List bytes) : _bytes = bytes;
  @override
  Future<DocxPicked?> pick() async {
    final bytes = _bytes;
    _bytes = null;
    return bytes == null ? super.pick() : DocxPicked(name, bytes);
  }
}

class SavedImageFiles extends DeviceImageEditFiles {
  final String name;
  Uint8List? _bytes;
  SavedImageFiles(this.name, Uint8List bytes) : _bytes = bytes;
  @override
  Future<PickedEditorImage?> pick() async {
    final bytes = _bytes;
    _bytes = null;
    return bytes == null ? super.pick() : PickedEditorImage(name, bytes);
  }
}
