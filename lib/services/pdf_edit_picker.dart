import 'pdf_edit_model.dart';
import 'pdf_edit_picker_native.dart'
    if (dart.library.js_interop) 'pdf_edit_picker_web.dart'
    as platform;

abstract class PdfEditPicker {
  Future<PickedEditPdf?> pick();
}

class DevicePdfEditPicker implements PdfEditPicker {
  @override
  Future<PickedEditPdf?> pick() => platform.pickEditPdf();
}
