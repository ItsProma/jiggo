import 'dart:convert';
import 'dart:typed_data';

class PickedEditPdf {
  final String name;
  final Uint8List bytes;
  const PickedEditPdf(this.name, this.bytes);
  static const maxBytes = 10 * 1024 * 1024;
  void validate() {
    if (!name.toLowerCase().endsWith('.pdf') ||
        bytes.length > maxBytes ||
        bytes.length < 5 ||
        ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw const FormatException('Choose a PDF under 10 MB.');
    }
  }
}

class EditPdfPage {
  final int source, index, turns;
  const EditPdfPage(this.source, this.index, [this.turns = 0]);
  EditPdfPage rotated() => EditPdfPage(source, index, (turns + 1) % 4);
  String get signature => '$source:$index:$turns';
}

class PdfPagePlan {
  static const maxPages = 100;
  List<EditPdfPage> _pages = const [];
  final List<List<EditPdfPage>> _undo = [], _redo = [];
  List<EditPdfPage> get pages => List.unmodifiable(_pages);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String get signature => _pages.map((p) => p.signature).join(',');
  void load(List<EditPdfPage> value) {
    _check(value);
    _pages = List.of(value);
    _undo.clear();
    _redo.clear();
  }

  void _check(List<EditPdfPage> value) {
    if (value.isEmpty || value.length > maxPages) {
      throw const FormatException('PDF page limit');
    }
  }

  void _commit(List<EditPdfPage> value) {
    _check(value);
    _undo.add(_pages);
    if (_undo.length > 20) _undo.removeAt(0);
    _pages = value;
    _redo.clear();
  }

  void append(List<EditPdfPage> value) => _commit([..._pages, ...value]);
  void rotate(int at) {
    final next = List.of(_pages);
    next[at] = next[at].rotated();
    _commit(next);
  }

  void remove(int at) {
    final next = List.of(_pages)..removeAt(at);
    _commit(next);
  }

  void move(int from, int to) {
    if (from == to) return;
    if (to < 0 || to >= _pages.length) throw RangeError.index(to, _pages);
    final next = List.of(_pages);
    final page = next.removeAt(from);
    next.insert(to, page);
    _commit(next);
  }

  void undo() {
    if (canUndo) {
      _redo.add(_pages);
      _pages = _undo.removeLast();
    }
  }

  void redo() {
    if (canRedo) {
      _undo.add(_pages);
      _pages = _redo.removeLast();
    }
  }
}

String editedPdfName(String title) {
  var name = title
      .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim();
  name = String.fromCharCodes(name.runes.take(60));
  while (utf8.encode(name).length > 170) {
    name = String.fromCharCodes(name.runes.take(name.runes.length - 1));
  }
  if (name.isEmpty || name == '.' || name == '..') name = 'Jiggo';
  return '${name}_edited.pdf';
}
