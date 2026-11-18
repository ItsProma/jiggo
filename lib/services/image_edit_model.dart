import 'dart:typed_data';
import 'dart:collection';

class EditedImage {
  static const maxInputBytes = 15 * 1024 * 1024;
  static const maxEncodedBytes = 32 * 1024 * 1024;
  static const maxEdge = 4096;
  static const maxPixels = 6000000;
  final Uint8List bytes;
  final int width, height;
  const EditedImage(this.bytes, this.width, this.height);
  bool get valid =>
      bytes.isNotEmpty &&
      bytes.length <= maxEncodedBytes &&
      validSize(width, height);
  static bool validSize(int w, int h) =>
      w > 0 && h > 0 && w <= maxEdge && h <= maxEdge && w * h <= maxPixels;
}

class ImportedImage {
  final EditedImage image;
  final String name, format;
  final bool reduced;
  const ImportedImage(
    this.image,
    this.name,
    this.format, {
    this.reduced = false,
  });
}

class ImageEditHistory {
  static const maxUndoSteps = 12;
  static const maxRetainedBytes = 64 * 1024 * 1024;
  final EditedImage original;
  final List<EditedImage> _frames;
  int _index = 0;
  ImageEditHistory(this.original) : _frames = [original] {
    if (!original.valid) throw const FormatException('image-size');
  }
  EditedImage get current => _frames[_index];
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _frames.length - 1;
  int get retainedBytes {
    final buffers = HashSet<Uint8List>.identity()..add(original.bytes);
    buffers.addAll(_frames.map((f) => f.bytes));
    return buffers.fold(0, (sum, b) => sum + b.length);
  }

  void commit(EditedImage next) {
    if (!next.valid) throw const FormatException('image-size');
    if (_index < _frames.length - 1) {
      _frames.removeRange(_index + 1, _frames.length);
    }
    _frames.add(next);
    while (_frames.length > 1 &&
        (_frames.length > maxUndoSteps + 1 ||
            retainedBytes > maxRetainedBytes)) {
      _frames.removeAt(0);
    }
    _index = _frames.length - 1;
  }

  void undo() {
    if (canUndo) _index--;
  }

  void redo() {
    if (canRedo) _index++;
  }
}
