import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:jiggo/services/pdf_edit_picker_native.dart' as native;
import 'package:jiggo/services/pdf_edit_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native PDF picker uses dedicated method and handles cancellation',
    () async {
      const channel = MethodChannel('jiggo/pdf_files');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'openPdf');
        return {
          'name': 'read.pdf',
          'bytes': Uint8List.fromList('%PDF-1.7'.codeUnits),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect((await native.pickEditPdf())!.name, 'read.pdf');
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await native.pickEditPdf(), isNull);
    },
  );
  test(
    'native PDF picker refuses a wrong file without changing its bytes',
    () async {
      const channel = MethodChannel('jiggo/pdf_files');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'name': 'wrong.pdf',
          'bytes': Uint8List.fromList('not pdf'.codeUnits),
        },
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await expectLater(native.pickEditPdf(), throwsFormatException);
    },
  );
  test(
    'page edits keep source indices and undo redo exact order and rotation',
    () {
      final p = PdfPagePlan()
        ..load([const EditPdfPage(0, 0), const EditPdfPage(0, 1)]);
      final original = p.signature;
      p.append([const EditPdfPage(1, 0)]);
      p.rotate(1);
      p.move(2, 0);
      expect(p.signature, '1:0:0,0:0:0,0:1:1');
      p.remove(1);
      expect(p.signature, '1:0:0,0:1:1');
      p.undo();
      p.undo();
      p.undo();
      p.undo();
      expect(p.signature, original);
      p.redo();
      expect(p.pages.length, 3);
      p.rotate(0);
      expect(p.canRedo, false);
      p.load([const EditPdfPage(2, 0)]);
      expect(p.canUndo, false);
    },
  );
  test('last page cannot be deleted and failed append keeps prior plan', () {
    final p = PdfPagePlan()..load([const EditPdfPage(0, 0)]);
    expect(() => p.remove(0), throwsFormatException);
    expect(p.pages.length, 1);
    expect(p.canUndo, false);
    expect(
      () => p.append(List.generate(100, (i) => EditPdfPage(1, i))),
      throwsFormatException,
    );
    expect(p.pages.length, 1);
    expect(() => p.move(0, -1), throwsRangeError);
  });
  test('four rotations restore rotation and history is bounded', () {
    final p = PdfPagePlan()..load([const EditPdfPage(0, 0)]);
    for (var i = 0; i < 24; i++) {
      p.rotate(0);
    }
    expect(p.pages.single.turns, 0);
    var n = 0;
    while (p.canUndo) {
      p.undo();
      n++;
    }
    expect(n, 20);
  });
  test('input validation rejects wrong extension magic and oversize', () {
    PickedEditPdf(
      'ok.PDF',
      Uint8List.fromList(ascii.encode('%PDF-1.7')),
    ).validate();
    for (final f in [
      PickedEditPdf('bad.pdf', Uint8List(8)),
      PickedEditPdf('bad.txt', Uint8List.fromList(ascii.encode('%PDF-'))),
      PickedEditPdf('big.pdf', Uint8List(PickedEditPdf.maxBytes + 1)),
    ]) {
      expect(f.validate, throwsFormatException);
    }
  });
  test('safe new-copy names retain Bangla and stay under native limits', () {
    expect(editedPdfName('../a.pdf'), '.._a_edited.pdf');
    expect(editedPdfName(''), 'Jiggo_edited.pdf');
    final s = editedPdfName(List.filled(100, 'বাংলা').join());
    expect(s.endsWith('_edited.pdf'), true);
    expect(utf8.encode(s).length, lessThan(200));
  });
}
