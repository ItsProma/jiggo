import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/pdf_editor_screen.dart';
import 'package:jiggo/services/pdf_edit_engine.dart';
import 'package:jiggo/services/pdf_edit_model.dart';
import 'package:jiggo/services/pdf_edit_picker.dart';
import 'package:jiggo/services/pdf_file_actions.dart';
import 'package:jiggo/services/app_settings.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

class Picker implements PdfEditPicker {
  bool fail = false;
  bool cancel = false;
  @override
  Future<PickedEditPdf?> pick() async {
    if (fail) throw const FormatException();
    if (cancel) return null;
    return PickedEditPdf(
      'sample.pdf',
      Uint8List.fromList('%PDF-1.7'.codeUnits),
    );
  }
}

class Source implements PdfEditSource {
  bool closed = false;
  @override
  int get pageCount => 2;
  @override
  Widget preview(int index, int turns) =>
      Text('Preview $index rotation $turns');
  @override
  Future<void> close() async {
    closed = true;
  }
}

class Engine implements PdfEditEngine {
  List<EditPdfPage>? saved;
  final sources = <Source>[];
  bool fail = false;
  @override
  Future<PdfEditSource> open(PickedEditPdf f) async {
    final s = Source();
    sources.add(s);
    return s;
  }

  @override
  Future<PdfEditSource> blank() => open(PickedEditPdf('', Uint8List(0)));
  @override
  Future<Uint8List> export(List<PdfEditSource> s, List<EditPdfPage> p) async {
    if (fail) throw const FormatException();
    saved = List.of(p);
    return Uint8List.fromList('%PDF-1.7'.codeUnits);
  }
}

class Files implements PdfFileActions {
  String? name;
  @override
  Future<PdfDelivery> save(Uint8List b, String n) async {
    name = n;
    return PdfDelivery.downloadRequested;
  }

  @override
  Future<PdfDelivery> share(Uint8List b, String n) async {
    name = n;
    return PdfDelivery.shareOpened;
  }
}

Future<void> tap(WidgetTester t, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  if (find.text(label).evaluate().isEmpty) {
    final scroll = find.byType(Scrollable).first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text(label), 180, scrollable: scroll);
    await t.pumpAndSettle();
  }
  await t.ensureVisible(find.text(label));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

Future<void> boot(
  WidgetTester t,
  Picker p,
  Engine e,
  Files f, {
  String language = 'en',
}) async {
  final settings = AppSettings(store: MemorySettingsStore());
  await settings.setLanguage(language);
  await t.pumpWidget(
    settingsApp(settings, PdfEditorScreen(picker: p, engine: e, files: f)),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('open rotate move delete undo merge export same page plan', (
    t,
  ) async {
    final p = Picker(), e = Engine(), f = Files();
    await boot(t, p, e, f);
    await tap(t, 'Open PDF');
    expect(find.text('Preview 0 rotation 0'), findsOneWidget);
    await tap(t, 'Rotate page');
    expect(find.text('Preview 0 rotation 1'), findsOneWidget);
    await tap(t, 'Move later');
    await t.scrollUntilVisible(
      find.text('Page 2 of 2'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tap(t, 'Delete page');
    await t.scrollUntilVisible(
      find.text('Page 1 of 1'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Page 1 of 1'), findsOneWidget);
    await t.ensureVisible(find.byTooltip('Undo'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Undo'));
    await t.pumpAndSettle();
    await tap(t, 'Add PDF / Merge');
    expect(find.text('Page 3 of 4'), findsOneWidget);
    await tap(t, 'Save PDF copy');
    expect(f.name, 'sample_edited.pdf');
    expect(e.saved!.length, 4);
    expect(e.saved![1].turns, 1);
    expect(e.saved![2].source, 1);
    expect(
      find.text('PDF download requested. Check Downloads before leaving.'),
      findsOneWidget,
    );
  });
  testWidgets('cancel failed picker and export retain existing pages', (
    t,
  ) async {
    final p = Picker(), e = Engine(), f = Files();
    await boot(t, p, e, f);
    await tap(t, 'Open PDF');
    p.cancel = true;
    await tap(t, 'Add PDF / Merge');
    expect(find.text('Page 1 of 2'), findsOneWidget);
    p.cancel = false;
    p.fail = true;
    await tap(t, 'Add PDF / Merge');
    expect(find.text('Page 1 of 2'), findsOneWidget);
    e.fail = true;
    await tap(t, 'Save PDF copy');
    expect(
      find.text('Could not export PDF. Your draft is kept. Try a smaller PDF.'),
      findsOneWidget,
    );
  });
  testWidgets('unsaved open asks and cancel keeps page rotation', (t) async {
    final p = Picker(), e = Engine(), f = Files();
    await boot(t, p, e, f);
    await tap(t, 'Open PDF');
    await tap(t, 'Rotate page');
    await tap(t, 'Open PDF');
    expect(find.text('Leave this PDF?'), findsOneWidget);
    await tap(t, 'Cancel');
    expect(find.text('Preview 0 rotation 1'), findsOneWidget);
    expect(e.sources.length, 1);
  });
  for (final language in ['en', 'bn']) {
    testWidgets('loaded PDF small screen large text dark $language', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final settings = AppSettings(store: MemorySettingsStore());
      await settings.setLanguage(language);
      await settings.setThemeMode(ThemeMode.dark);
      final p = Picker(), e = Engine(), f = Files();
      await t.pumpWidget(
        settingsApp(
          settings,
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 200),
            ),
            child: PdfEditorScreen(picker: p, engine: e, files: f),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, language == 'bn' ? 'PDF খোলো' : 'Open PDF');
      await tap(t, language == 'bn' ? 'পৃষ্ঠা ঘোরাও' : 'Rotate page');
      await tap(t, language == 'bn' ? 'PDF কপি সেভ করো' : 'Save PDF copy');
      expect(e.saved!.first.turns, 1);
      expect(t.takeException(), isNull);
    });
  }
}
