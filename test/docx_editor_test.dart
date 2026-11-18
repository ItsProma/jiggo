import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/docx_editor_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/docx_codec.dart';
import 'package:jiggo/services/docx_files.dart';
import 'package:jiggo/services/docx_files_native.dart' as native;
import 'package:jiggo/services/docx_processor.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

class LocalProcessor extends DocxProcessor {
  @override
  Future<List<Map<String, dynamic>>> decode(Uint8List bytes) async =>
      DocxCodec().decode(bytes);
  @override
  Future<Uint8List> encode(List<Map<String, dynamic>> delta) async =>
      DocxCodec().encode(delta);
}

class FakeFiles implements DocxFiles {
  DocxPicked? picked;
  Uint8List? saved, shared;
  String? name;
  bool fails = false;
  Completer<DocxPicked?>? waiting;
  @override
  Future<DocxPicked?> pick() async =>
      waiting == null ? picked : await waiting!.future;
  @override
  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    saved = bytes;
    name = filename;
    if (fails) throw StateError('save failed');
    return PdfDelivery.downloadRequested;
  }

  @override
  Future<PdfDelivery> share(Uint8List bytes, String filename) async {
    shared = bytes;
    name = filename;
    return PdfDelivery.shareOpened;
  }
}

QuillController editor(WidgetTester t) =>
    t.widget<QuillEditor>(find.byType(QuillEditor)).controller;
String plain(Uint8List bytes) =>
    DocxCodec().decode(bytes).map((o) => o['insert']).join();
Future<void> boot(WidgetTester t, FakeFiles files) async {
  final settings = AppSettings(store: MemorySettingsStore());
  await settings.setLanguage('en');
  await t.pumpWidget(
    settingsApp(
      settings,
      DocxEditorScreen(files: files, processor: LocalProcessor()),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(text));
  await t.pumpAndSettle();
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Editing a DOCX copy and toolbar formatting survive export and reopening',
    (t) async {
      final source = DocxCodec().encode([
        {'insert': 'বাংলা English\n'},
      ]);
      final files = FakeFiles()..picked = DocxPicked('source.docx', source);
      await boot(t, files);
      await tap(t, 'Open DOCX');
      final c = editor(t);
      expect(c.document.toPlainText(), 'বাংলা English\n');
      c.replaceText(0, 0, 'New ', const TextSelection.collapsed(offset: 4));
      await t.pumpAndSettle();
      c.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 3),
        ChangeSource.local,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byTooltip('Bold'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Bold'));
      await t.pumpAndSettle();
      expect(
        c.document.toDelta().toJson().any(
          (o) => (o['attributes'] as Map?)?['bold'] == true,
        ),
        isTrue,
      );
      await tap(t, 'Save DOCX copy');
      expect(files.name, 'source_edited.docx');
      expect(plain(files.saved!), 'New বাংলা English\n');
      expect(plain(source), 'বাংলা English\n');
      expect(
        DocxCodec()
            .decode(files.saved!)
            .any(
              (o) =>
                  (o['attributes'] as Map?)?['bold'] == true &&
                  o['insert'] == 'New',
            ),
        isTrue,
      );
      await tap(t, 'Share DOCX');
      expect(plain(files.shared!), plain(files.saved!));
    },
  );
  testWidgets(
    'Heading and list toolbar controls produce supported DOCX blocks',
    (t) async {
      final files = FakeFiles();
      await boot(t, files);
      final c = editor(t);
      c.replaceText(0, 0, 'Section', const TextSelection.collapsed(offset: 0));
      await t.pumpAndSettle();
      await tap(t, 'Normal text');
      await tap(t, 'Heading 2');
      expect(
        c.document.toDelta().toJson().any(
          (o) => (o['attributes'] as Map?)?['header'] == 2,
        ),
        isTrue,
      );
      await t.ensureVisible(find.byTooltip('Numbered list'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Numbered list'));
      await t.pumpAndSettle();
      expect(
        c.document.toDelta().toJson().any(
          (o) => (o['attributes'] as Map?)?['header'] != null,
        ),
        isFalse,
      );
      expect(
        c.document.toDelta().toJson().any(
          (o) => (o['attributes'] as Map?)?['list'] == 'ordered',
        ),
        isTrue,
      );
      await t.tap(find.byTooltip('Bullet list'));
      await t.pumpAndSettle();
      await tap(t, 'Save DOCX copy');
      expect(
        DocxCodec()
            .decode(files.saved!)
            .any((o) => (o['attributes'] as Map?)?['list'] == 'bullet'),
        isTrue,
      );
    },
  );
  testWidgets(
    'Undo and redo work and opening a different file resets document history',
    (t) async {
      final files = FakeFiles();
      await boot(t, files);
      final c = editor(t);
      c.replaceText(0, 0, 'One', const TextSelection.collapsed(offset: 3));
      await t.pump(const Duration(milliseconds: 600));
      // Start a distinct edit group without depending on real wall-clock timing.
      c.document.history.lastRecorded = 0;
      c.replaceText(0, 3, 'Two', const TextSelection.collapsed(offset: 3));
      await t.pump(const Duration(milliseconds: 600));
      await t.ensureVisible(find.byTooltip('Undo'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Undo'));
      await t.pumpAndSettle();
      expect(c.document.toPlainText(), 'One\n');
      await t.tap(find.byTooltip('Redo'));
      await t.pumpAndSettle();
      expect(c.document.toPlainText(), 'Two\n');
      files.picked = DocxPicked(
        'next.docx',
        DocxCodec().encode([
          {'insert': 'Next\n'},
        ]),
      );
      await tap(t, 'Open DOCX');
      await tap(t, 'Continue');
      expect(editor(t).document.toPlainText(), 'Next\n');
      expect(editor(t).hasUndo, isFalse);
    },
  );
  testWidgets(
    'Unsupported import, cancelled picker and failed export keep edited text',
    (t) async {
      final files = FakeFiles();
      await boot(t, files);
      editor(t).replaceText(
        0,
        0,
        'Keep বাংলা',
        const TextSelection.collapsed(offset: 10),
      );
      await t.pumpAndSettle();
      await tap(t, 'Open DOCX');
      await tap(t, 'Continue');
      expect(editor(t).document.toPlainText(), 'Keep বাংলা\n');
      files.picked = DocxPicked(
        'broken.docx',
        Uint8List.fromList([1, 2, 3, 4]),
      );
      await tap(t, 'Open DOCX');
      await tap(t, 'Continue');
      expect(
        find.textContaining('This file could not be opened.'),
        findsOneWidget,
      );
      expect(editor(t).document.toPlainText(), 'Keep বাংলা\n');
      files.fails = true;
      await tap(t, 'Save DOCX copy');
      expect(find.textContaining('Unable to export DOCX.'), findsOneWidget);
      expect(editor(t).document.toPlainText(), 'Keep বাংলা\n');
    },
  );
  testWidgets(
    'Oversized replacement and embeds are blocked without changing current text',
    (t) async {
      await boot(t, FakeFiles());
      final c = editor(t);
      c.replaceText(
        0,
        0,
        'a' * 20001,
        const TextSelection.collapsed(offset: 0),
      );
      await t.pumpAndSettle();
      expect(c.document.toPlainText(), '\n');
      c.replaceText(
        0,
        0,
        BlockEmbed.image('https://example.invalid/image'),
        null,
      );
      await t.pumpAndSettle();
      expect(c.document.toPlainText(), '\n');
      expect(
        find.textContaining('Use plain text within 20000 characters.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Pending file picker disables duplicate opening and late results are ignored after exit',
    (t) async {
      final files = FakeFiles()..waiting = Completer<DocxPicked?>();
      await boot(t, files);
      await t.tap(find.text('Open DOCX'));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find
                  .ancestor(
                    of: find.text('Open DOCX'),
                    matching: find.byType(FilledButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      files.waiting!.complete(
        DocxPicked(
          'later.docx',
          DocxCodec().encode([
            {'insert': 'Late\n'},
          ]),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Android DOCX open, binary save and sharing channel use DOCX methods',
    (t) async {
      const channel = MethodChannel('jiggo/pdf_files');
      final calls = <MethodCall>[];
      final bytes = DocxCodec().encode([
        {'insert': 'বাংলা\n'},
      ]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'openDocx'
                ? {'name': 'test.docx', 'bytes': bytes}
                : true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final files = native.PlatformDocxFiles();
      expect((await files.pick())!.name, 'test.docx');
      expect(await files.save(bytes, 'test_edited.docx'), PdfDelivery.saved);
      expect(
        await files.share(bytes, 'test_edited.docx'),
        PdfDelivery.shareOpened,
      );
      expect(calls.map((c) => c.method), ['openDocx', 'saveDocx', 'shareDocx']);
      expect((calls[1].arguments as Map)['bytes'], bytes);
    },
  );
  for (final lang in ['bn', 'en']) {
    testWidgets(
      'DOCX editor fits small screen, large text, dark mode and keyboard: $lang',
      (t) async {
        t.view.physicalSize = const Size(320, 700);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final settings = AppSettings(store: MemorySettingsStore());
        await settings.setLanguage(lang);
        await settings.setThemeMode(ThemeMode.dark);
        await t.pumpWidget(
          settingsApp(
            settings,
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: 240),
              ),
              child: DocxEditorScreen(
                files: FakeFiles(),
                processor: LocalProcessor(),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        editor(t).replaceText(
          0,
          0,
          'বাংলা English',
          const TextSelection.collapsed(offset: 0),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byType(QuillEditor));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
