import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/file_editor_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/text_document_picker.dart';
import 'package:jiggo/services/text_document_picker_native.dart' as native;
import 'package:jiggo/services/text_file_actions.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

class FakePicker implements TextDocumentPicker {
  TextDocument? result;
  bool fails = false;
  @override
  Future<TextDocument?> pick() async {
    if (fails) throw const FormatException();
    return result;
  }
}

class FakeFiles implements TextFileActions {
  String? text, filename, shared;
  bool fails = false;
  @override
  Future<PdfDelivery> save(String value, String name) async {
    text = value;
    filename = name;
    if (fails) throw StateError('save failed');
    return PdfDelivery.downloadRequested;
  }

  @override
  Future<PdfDelivery> share(String value, String title) async {
    shared = value;
    return PdfDelivery.shareOpened;
  }
}

Finder body() => find.byWidgetPredicate(
  (w) => w is TextField && w.key.toString().contains('text-file-body'),
);
TextEditingController controller(WidgetTester t) =>
    t.widget<TextField>(body()).controller!;
Future<void> boot(WidgetTester t, FakePicker picker, FakeFiles files) async {
  final settings = AppSettings(store: MemorySettingsStore());
  await settings.setLanguage('en');
  await t.pumpWidget(
    settingsApp(settings, FileEditorScreen(picker: picker, files: files)),
  );
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(text));
  await t.pumpAndSettle();
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

void main() {
  test(
    'UTF-8 preserves Bangla, literal markup and line endings; BOM removed',
    () {
      final bytes = Uint8List.fromList(
        utf8.encode('\uFEFF  বাংলা **note**\r\nSecond line'),
      );
      expect(
        TextDocument.decode('note.TXT', bytes).text,
        '  বাংলা **note**\r\nSecond line',
      );
      expect(TextDocument.decode('empty.txt', Uint8List(0)).text, '');
    },
  );
  test('Unsupported, binary, malformed and oversized files rejected without lossy decoding', () {
    for (final item in [
      ('note.pdf', utf8.encode('hello')),
      ('note.txt', [0xff, 0xfe]),
      ('note.txt', [0, 65]),
      ('note.txt', List.filled(TextDocument.maxBytes + 1, 65)),
      ('note.txt', utf8.encode('a' * 20001)),
    ]) {
      expect(
        () => TextDocument.decode(item.$1, Uint8List.fromList(item.$2)),
        throwsFormatException,
      );
    }
  });
  testWidgets(
    'Export uses edited copy and new filename; failed export preserves edits',
    (t) async {
      final picker = FakePicker()
        ..result = const TextDocument('notes.txt', '  বাংলা\nOriginal');
      final files = FakeFiles();
      await boot(t, picker, files);
      await tapText(t, 'Open TXT');
      expect(controller(t).text, '  বাংলা\nOriginal');
      await t.enterText(body(), '  বাংলা\nChanged **literal**');
      files.fails = true;
      await tapText(t, 'Save TXT copy');
      expect(
        find.text('Unable to export text. Copy it or try again.'),
        findsOneWidget,
      );
      expect(files.text, '  বাংলা\nChanged **literal**');
      expect(files.filename, 'notes_edited.txt');
      files.fails = false;
      await tapText(t, 'Save TXT copy');
      expect(
        find.text('TXT download requested. Check Downloads before leaving.'),
        findsOneWidget,
      );
      await tapText(t, 'Share text');
      expect(files.shared, '  বাংলা\nChanged **literal**');
      expect(picker.result!.text, '  বাংলা\nOriginal');
    },
  );
  testWidgets(
    'Cancelled and failed picker keep current text; undo and redo restore typing',
    (t) async {
      final picker = FakePicker();
      await boot(t, picker, FakeFiles());
      await t.ensureVisible(body());
      await t.pumpAndSettle();
      expect(body().hitTestable(), findsOneWidget);
      await t.tap(body());
      await t.enterText(body(), 'first');
      await t.pump(const Duration(milliseconds: 600));
      await t.enterText(body(), 'second');
      await t.pump(const Duration(milliseconds: 600));
      await t.ensureVisible(find.byTooltip('Undo'));
      await t.tap(find.byTooltip('Undo'));
      await t.pumpAndSettle();
      expect(controller(t).text, 'first');
      await t.tap(find.byTooltip('Redo'));
      await t.pumpAndSettle();
      expect(controller(t).text, 'second');
      await tapText(t, 'Open TXT');
      await tapText(t, 'Continue');
      expect(controller(t).text, 'second');
      picker.fails = true;
      await tapText(t, 'Open TXT');
      await tapText(t, 'Continue');
      expect(controller(t).text, 'second');
      expect(find.textContaining('Could not open this file.'), findsOneWidget);
    },
  );
  testWidgets('Opening a different file resets undo history', (t) async {
    final picker = FakePicker();
    await boot(t, picker, FakeFiles());
    await t.ensureVisible(body());
    await t.pumpAndSettle();
    expect(body().hitTestable(), findsOneWidget);
    await t.tap(body());
    await t.enterText(body(), 'private old text');
    await t.pump(const Duration(milliseconds: 600));
    picker.result = const TextDocument('new.txt', 'new text');
    await tapText(t, 'Open TXT');
    await tapText(t, 'Continue');
    expect(controller(t).text, 'new text');
    final undo = t.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip('Undo'),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(undo.onPressed, isNull);
  });
  testWidgets('Paste replaces selected text; copy preserves literal text', (
    t,
  ) async {
    String clipboard = 'বাংলা';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await boot(t, FakePicker(), FakeFiles());
    await t.enterText(body(), 'hello world');
    controller(t).selection = const TextSelection(
      baseOffset: 6,
      extentOffset: 11,
    );
    await tapText(t, 'Paste text');
    expect(controller(t).text, 'hello বাংলা');
    await tapText(t, 'Copy text');
    expect(clipboard, 'hello বাংলা');
  });
  testWidgets('Oversized typed text stays intact and cannot be exported', (
    t,
  ) async {
    final files = FakeFiles();
    await boot(t, FakePicker(), files);
    await t.enterText(body(), 'a' * 20001);
    await tapText(t, 'Save TXT copy');
    expect(files.text, isNull);
    expect(
      find.text(
        'Enter a title of 1–140 characters and text of 1–20000 characters.',
      ),
      findsOneWidget,
    );
    await t.ensureVisible(body());
    expect(controller(t).text.length, 20001);
  });
  testWidgets('Android picker decodes bounded UTF-8 and handles cancel', (
    t,
  ) async {
    const channel = MethodChannel('jiggo/pdf_files');
    Object? result = {
      'name': 'bn.txt',
      'bytes': Uint8List.fromList(utf8.encode('বাংলা')),
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'openText');
          return result;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect((await native.pickTextDocument())!.text, 'বাংলা');
    result = null;
    expect(await native.pickTextDocument(), isNull);
  });
  for (final lang in ['bn', 'en']) {
    testWidgets('Narrow screen, large font, dark theme and keyboard: $lang', (
      t,
    ) async {
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
            child: FileEditorScreen(picker: FakePicker(), files: FakeFiles()),
          ),
        ),
      );
      await t.pumpAndSettle();
      if (lang == 'bn') {
        expect(find.byTooltip('আগের অবস্থায় ফেরাও'), findsOneWidget);
        expect(find.byTooltip('আবার প্রয়োগ করো'), findsOneWidget);
      }
      await t.ensureVisible(body());
      await t.enterText(body(), 'বাংলা English');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
