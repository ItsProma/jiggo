import 'dart:typed_data';

import 'package:flutter/material.dart';

enum PdfMarkKind { pen, highlight, signature, text, image }

class PdfMark {
  final PdfMarkKind kind;
  final List<Offset> points;
  final int color;
  final double size;
  final String? text;
  final Uint8List? image;
  final double imageAspect;
  PdfMark({
    required this.kind,
    required List<Offset> points,
    this.color = 0xff111111,
    this.size = .008,
    this.text,
    this.image,
    this.imageAspect = 1,
  }) : points = List.unmodifiable(points);
  PdfMark moved(Offset delta) {
    final minX = points.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
    final maxX = points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
    final minY = points.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
    final dx = delta.dx.clamp(-minX, 1 - maxX),
        dy = delta.dy.clamp(-minY, 1 - maxY);
    return PdfMark(
      kind: kind,
      points: points.map((p) => Offset(p.dx + dx, p.dy + dy)).toList(),
      color: color,
      size: size,
      text: text,
      image: image,
      imageAspect: imageAspect,
    );
  }

  bool get valid =>
      points.isNotEmpty &&
      points.length <= 1000 &&
      points.every(
        (p) =>
            p.dx.isFinite &&
            p.dy.isFinite &&
            p.dx >= 0 &&
            p.dx <= 1 &&
            p.dy >= 0 &&
            p.dy <= 1,
      ) &&
      size.isFinite &&
      size >= .002 &&
      size <= .45 &&
      (kind != PdfMarkKind.text ||
          (text != null &&
              text!.trim().isNotEmpty &&
              text!.length <= 300 &&
              text!.split('\n').length <= 8)) &&
      (kind != PdfMarkKind.image ||
          (image != null &&
              image!.isNotEmpty &&
              image!.length <= 4 * 1024 * 1024 &&
              imageAspect.isFinite &&
              imageAspect > 0));
}

class PdfMarkHistory extends ChangeNotifier {
  static const maxMarks = 60;
  List<PdfMark> _marks = const [];
  final List<List<PdfMark>> _undo = [], _redo = [];
  List<PdfMark> get marks => List.unmodifiable(_marks);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void _commit(List<PdfMark> next) {
    if (next.length > maxMarks ||
        next.any((m) => !m.valid) ||
        next.where((m) => m.kind == PdfMarkKind.image).length > 4) {
      throw const FormatException('markup-limit');
    }
    _undo.add(_marks);
    if (_undo.length > 20) _undo.removeAt(0);
    _marks = next;
    _redo.clear();
    notifyListeners();
  }

  void add(PdfMark mark) => _commit([..._marks, mark]);
  void replace(int i, PdfMark mark) {
    final next = List.of(_marks);
    next[i] = mark;
    _commit(next);
  }

  void remove(int i) {
    final next = List.of(_marks)..removeAt(i);
    _commit(next);
  }

  void clear() {
    if (_marks.isNotEmpty) _commit([]);
  }

  void undo() {
    if (canUndo) {
      _redo.add(_marks);
      _marks = _undo.removeLast();
      notifyListeners();
    }
  }

  void redo() {
    if (canRedo) {
      _undo.add(_marks);
      _marks = _redo.removeLast();
      notifyListeners();
    }
  }
}
