import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/pdf_markup_model.dart';
import 'package:jiggo/services/pdf_edit_model.dart';

PdfMark pen([List<Offset> points = const [Offset(.1, .2), Offset(.3, .4)]]) =>
    PdfMark(kind: PdfMarkKind.pen, points: points);
void main() {
  test('markup undo redo delete move clear and redo branch', () {
    final h = PdfMarkHistory();
    addTearDown(h.dispose);
    h.add(pen());
    h.add(
      PdfMark(
        kind: PdfMarkKind.text,
        points: const [Offset(.5, .5)],
        text: 'বাংলা',
        size: .04,
      ),
    );
    h.replace(0, h.marks[0].moved(const Offset(.1, .1)));
    expect(h.marks[0].points.first.dx, closeTo(.2, .001));
    h.undo();
    expect(h.marks[0].points.first.dx, .1);
    h.redo();
    h.remove(1);
    expect(h.marks.length, 1);
    h.undo();
    expect(h.marks.length, 2);
    h.clear();
    expect(h.marks, isEmpty);
    h.undo();
    expect(h.marks.length, 2);
    h.add(pen());
    expect(h.canRedo, false);
  });
  test('stroke movement preserves shape at edges; points cannot mutate', () {
    final points = [const Offset(.1, .2), const Offset(.3, .4)];
    final m = pen(points);
    points[0] = Offset.zero;
    expect(m.points[0], const Offset(.1, .2));
    final shifted = m.moved(const Offset(1, -1));
    expect(shifted.points[1].dx, closeTo(1, .001));
    expect(shifted.points[1].dy - shifted.points[0].dy, closeTo(.2, .001));
    expect(() => m.points.add(Offset.zero), throwsUnsupportedError);
  });
  test('invalid marks and oversized history do not change prior work', () {
    final h = PdfMarkHistory();
    addTearDown(h.dispose);
    h.add(pen());
    expect(() => h.add(pen([const Offset(-1, 0)])), throwsFormatException);
    expect(h.marks.length, 1);
    expect(
      () => h.add(
        PdfMark(
          kind: PdfMarkKind.text,
          points: const [Offset.zero],
          text: '',
          size: .04,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => h.add(
        PdfMark(
          kind: PdfMarkKind.image,
          points: const [Offset.zero],
          size: .2,
          image: Uint8List(4 * 1024 * 1024 + 1),
        ),
      ),
      throwsFormatException,
    );
    for (var i = 1; i < PdfMarkHistory.maxMarks; i++) {
      h.add(pen());
    }
    expect(() => h.add(pen()), throwsFormatException);
    expect(h.marks.length, 60);
    var steps = 0;
    while (h.canUndo) {
      h.undo();
      steps++;
    }
    expect(steps, 20);
  });
  test(
    'replacing a page keeps markup attached through reorder and rotation',
    () {
      final p = PdfPagePlan()
        ..load([const EditPdfPage(0, 0), const EditPdfPage(0, 1)]);
      p.replace(1, const EditPdfPage(1, 0));
      p.move(1, 0);
      p.rotate(0);
      expect(p.signature, '1:0:1,0:0:0');
      p.undo();
      p.undo();
      p.undo();
      expect(p.signature, '0:0:0,0:1:0');
      p.redo();
      expect(p.signature, '0:0:0,1:0:0');
    },
  );
}
