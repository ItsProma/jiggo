import 'text_document.dart';
import 'text_document_picker_native.dart'
    if (dart.library.js_interop) 'text_document_picker_web.dart'
    as platform;
export 'text_document.dart';

abstract class TextDocumentPicker {
  Future<TextDocument?> pick();
}

class DeviceTextDocumentPicker implements TextDocumentPicker {
  @override
  Future<TextDocument?> pick() => platform.pickTextDocument();
}
