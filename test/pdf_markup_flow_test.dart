import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/pdf_editor_screen.dart';
import 'package:jiggo/screens/pdf_markup_screen.dart';
import 'package:jiggo/services/pdf_markup_engine.dart';
import 'package:jiggo/services/pdf_edit_engine.dart';
import 'package:jiggo/services/pdf_edit_model.dart';
import 'package:jiggo/services/image_edit_model.dart';
import 'package:jiggo/services/app_settings.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';
import 'pdf_editor_test.dart' show Picker, Files, Source;
import 'pdf_markup_screen_test.dart' show background, reveal, tap;

import 'dart:typed_data';

class OnePage extends Source {
  @override
  int get pageCount => 1;
}

class Engine implements PdfEditEngine {
  final sources = <Source>[];
  List<EditPdfPage>? output;
  @override
  Future<PdfEditSource> open(PickedEditPdf f) async {
    final s = f.name == 'marked-page.pdf' ? OnePage() : Source();
    sources.add(s);
    return s;
  }

  @override
  Future<PdfEditSource> blank() async => OnePage();
  @override
  Future<Uint8List> export(List<PdfEditSource> s, List<EditPdfPage> p) async {
    output = List.of(p);
    return Uint8List.fromList('%PDF-test'.codeUnits);
  }
}

class Markup implements PdfMarkupEngine {
  bool fail = false;
  @override
  Future<PdfMarkupRaster> raster(PdfEditSource s, EditPdfPage p) async =>
      PdfMarkupRaster(background(), 320, 440);
  @override
  Future<Uint8List> encode(EditedImage i, double w, double h) async {
    if (fail) throw const FormatException();
    return Uint8List.fromList('%PDF-mark'.codeUnits);
  }
}

void main() {
  testWidgets(
    'applying markup replaces just selected page and parent undo restores source',
    (t) async {
      final settings = AppSettings(store: MemorySettingsStore());
      await settings.setLanguage('en');
      final engine = Engine(), markup = Markup();
      await t.pumpWidget(
        settingsApp(
          settings,
          PdfEditorScreen(
            picker: Picker(),
            engine: engine,
            files: Files(),
            markup: markup,
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Open PDF');
      await tap(t, 'Add page markup');
      final context = t.element(find.byType(PdfMarkupScreen));
      Navigator.pop(context, background());
      await t.pumpAndSettle();
      await tap(t, 'Save PDF copy');
      expect(engine.output!.map((p) => p.source), [1, 0]);
      await reveal(t, find.byTooltip('Undo'));
      await t.tap(find.byTooltip('Undo'));
      await t.pumpAndSettle();
      await tap(t, 'Save PDF copy');
      expect(engine.output!.map((p) => p.source), [0, 0]);
    },
  );
  testWidgets('markup encode failure retains existing PDF', (t) async {
    final settings = AppSettings(store: MemorySettingsStore());
    await settings.setLanguage('en');
    final engine = Engine(), markup = Markup()..fail = true;
    await t.pumpWidget(
      settingsApp(
        settings,
        PdfEditorScreen(
          picker: Picker(),
          engine: engine,
          files: Files(),
          markup: markup,
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Open PDF');
    await tap(t, 'Add page markup');
    Navigator.pop(t.element(find.byType(PdfMarkupScreen)), background());
    await t.pumpAndSettle();
    await tap(t, 'Save PDF copy');
    expect(engine.output!.map((p) => p.source), [0, 0]);
    expect(engine.sources.length, 1);
  });
}
