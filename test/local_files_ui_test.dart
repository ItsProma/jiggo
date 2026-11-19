import 'package:jiggo/services/docx_files.dart' show DocxPicked;
import 'package:jiggo/services/image_edit_files.dart' show PickedEditorImage;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/file_editor_screen.dart';
import 'package:jiggo/screens/docx_editor_screen.dart';
import 'package:jiggo/screens/image_editor_screen.dart';
import 'package:jiggo/screens/pdf_editor_screen.dart';
import 'package:jiggo/screens/scan_pdf_screen.dart';
import 'package:jiggo/screens/local_file_details_screen.dart';
import 'package:jiggo/screens/all_library_items.dart' show LibrarySort;
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/local_file_store.dart';
import 'package:jiggo/services/local_file_saver.dart';
import 'package:jiggo/services/local_file_delivery.dart';
import 'package:jiggo/services/docx_codec.dart';
import 'package:jiggo/widgets/local_files_panel.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';
import 'support/memory_local_files.dart';
import 'file_editor_test.dart' as txt;
import 'docx_editor_test.dart' as docx;
import 'image_editor_test.dart' as image;
import 'image_edit_processing_test.dart' show transparentPhoto;
import 'pdf_editor_test.dart' as pdf;
import 'scan_pdf_screen_test.dart' as scan;

Uint8List textBytes(String s) => Uint8List.fromList(utf8.encode(s));
Future<void> boot(
  WidgetTester t,
  Widget screen, {
  String language = 'en',
}) async {
  final settings = AppSettings(store: MemorySettingsStore());
  await settings.setLanguage(language);
  await t.pumpWidget(settingsApp(settings, screen));
  await t.pumpAndSettle();
}

Future<void> saveToLibrary(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  final button = find.byKey(const ValueKey('local-library-save'));
  if (button.evaluate().isEmpty &&
      find.byType(PdfEditorScreen).evaluate().isNotEmpty) {
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
  }
  await t.ensureVisible(button);
  await t.pumpAndSettle();
  await t.tap(button);
  await t.pumpAndSettle();
}

LocalFileStore memoryStore() {
  return LocalFileStore(MemoryLocalFiles());
}

LocalFileSaver saver(LocalFileStore store) => AccountLocalFileSaver(
  store: store,
  expectedOwner: 'A',
  currentOwner: () => 'A',
);

class FailingSaver implements LocalFileSaver {
  @override
  Future<void> save(
    String name,
    LocalFileKind kind,
    Uint8List bytes,
    String source,
  ) async => throw StateError('disk full');
}

class TestDelivery extends LocalFileDelivery {
  Uint8List? bytes;
  bool? share;
  PdfDelivery result = PdfDelivery.downloadRequested;
  @override
  Future<PdfDelivery> deliver(
    LocalFileInfo info,
    Uint8List data, {
    required bool share,
  }) async {
    bytes = Uint8List.fromList(data);
    this.share = share;
    return result;
  }
}

class DelayedBackend extends MemoryLocalFiles {
  final waiting = Completer<void>();
  @override
  Future<List<LocalFileInfo>> list(String owner) async {
    if (owner == 'A') await waiting.future;
    return super.list(owner);
  }
}

void main() {
  testWidgets(
    'TXT Save to Library preserves Bengali and can reopen for editing as a new copy',
    (t) async {
      final store = memoryStore();
      await boot(
        t,
        FileEditorScreen(
          library: saver(store),
          picker: txt.FakePicker(),
          files: txt.FakeFiles(),
        ),
      );
      await t.enterText(txt.body(), 'বাংলা English\n');
      await saveToLibrary(t);
      expect(find.text('Saved to Library on this device.'), findsOneWidget);
      final original = (await store.list('A')).single;
      expect(
        utf8.decode(await store.read('A', original.id)),
        'বাংলা English\n',
      );
      await boot(
        t,
        LocalFileDetailsScreen(
          info: original,
          userId: 'A',
          store: store,
          currentOwner: () => 'A',
        ),
      );
      expect(find.text('বাংলা English\n'), findsOneWidget);
      await t.tap(find.text('Open in editor'));
      await t.pumpAndSettle();
      expect(txt.controller(t).text, 'বাংলা English\n');
      await t.enterText(txt.body(), 'Changed বাংলা');
      await saveToLibrary(t);
      expect(await store.list('A'), hasLength(2));
      expect(
        utf8.decode(await store.read('A', original.id)),
        'বাংলা English\n',
      );
      await t.pumpWidget(const SizedBox.shrink());
      await store.dispose();
    },
  );
  testWidgets(
    'Failed Library save leaves the TXT draft intact and still warns on leaving',
    (t) async {
      await boot(
        t,
        FileEditorScreen(
          library: FailingSaver(),
          picker: txt.FakePicker(),
          files: txt.FakeFiles(),
        ),
      );
      await t.enterText(txt.body(), 'Keep me');
      await saveToLibrary(t);
      expect(txt.controller(t).text, 'Keep me');
      expect(find.textContaining('Could not save to Library.'), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Use Save to Library'), findsOneWidget);
    },
  );
  testWidgets(
    'DOCX auto-open and local save preserve editable rich-text content',
    (t) async {
      final store = memoryStore();
      final bytes = DocxCodec().encode([
        {'insert': 'বাংলা English\n'},
      ]);
      final files = docx.FakeFiles()..picked = DocxPicked('sample.docx', bytes);
      await boot(
        t,
        DocxEditorScreen(
          autoOpen: true,
          files: files,
          processor: docx.LocalProcessor(),
          library: saver(store),
        ),
      );
      expect(docx.editor(t).document.toPlainText(), 'বাংলা English\n');
      await saveToLibrary(t);
      final info = (await store.list('A')).single;
      expect(info.kind, LocalFileKind.docx);
      expect(docx.plain(await store.read('A', info.id)), 'বাংলা English\n');
      expect(files.saved, isNull);
    },
  );
  testWidgets(
    'Image auto-open saves its rendered PNG into Library, without downloading',
    (t) async {
      final store = memoryStore(),
          files = image.FakeFiles()
            ..next = PickedEditorImage('sample.png', transparentPhoto());
      await boot(
        t,
        ImageEditorScreen(
          autoOpen: true,
          files: files,
          processor: image.FakeProcessor(),
          library: saver(store),
        ),
      );
      await saveToLibrary(t);
      final info = (await store.list('A')).single;
      expect(info.kind, LocalFileKind.png);
      expect((await store.read('A', info.id)).take(4), [137, 80, 78, 71]);
      expect(files.saved, isNull);
    },
  );
  testWidgets('PDF auto-open exports the current page plan into Library', (
    t,
  ) async {
    final store = memoryStore(), engine = pdf.Engine(), files = pdf.Files();
    await boot(
      t,
      PdfEditorScreen(
        autoOpen: true,
        picker: pdf.Picker(),
        engine: engine,
        files: files,
        library: saver(store),
      ),
    );
    await pdf.tap(t, 'Rotate page');
    await saveToLibrary(t);
    final info = (await store.list('A')).single;
    expect(info.kind, LocalFileKind.pdf);
    expect(engine.saved!.first.turns, 1);
    expect(files.name, isNull);
  });
  testWidgets(
    'Scan to PDF creates a reusable Library PDF without opening a download',
    (t) async {
      await t.binding.setSurfaceSize(const Size(700, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final store = memoryStore(),
          photos = scan.FakePhotos()..next = [scan.photo('one.jpg')],
          files = scan.FakePdfFiles();
      await boot(
        t,
        ScanPdfScreen(
          photos: photos,
          images: scan.FakeImages(),
          builder: scan.FakePdfBuilder(),
          files: files,
          library: saver(store),
        ),
      );
      await scan.tapKey(t, 'scan-pdf-gallery');
      await scan.tapKey(t, 'scan-pdf-create');
      await saveToLibrary(t);
      final info = (await store.list('A')).single;
      expect(info.kind, LocalFileKind.pdf);
      expect(info.source, 'Scan to PDF');
      expect(files.saves, 0);
    },
  );
  testWidgets(
    'Local files refresh live, rename without changing contents, and confirm deletion',
    (t) async {
      final store = memoryStore();
      final file = await store.save(
        'A',
        'Original',
        LocalFileKind.txt,
        textBytes('keep content'),
        'Text',
      );
      await boot(
        t,
        Scaffold(
          body: LocalFilesPanel(userId: 'A', store: store),
        ),
      );
      expect(find.text('Original.txt'), findsOneWidget);
      await t.tap(find.byType(PopupMenuButton<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Rename'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'নতুন');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('নতুন.txt'), findsOneWidget);
      expect(utf8.decode(await store.read('A', file.id)), 'keep content');
      await store.save(
        'A',
        'Second',
        LocalFileKind.txt,
        textBytes('second'),
        'Text',
      );
      await t.pumpAndSettle();
      expect(find.text('Second.txt'), findsOneWidget);
      await t.tap(find.byType(PopupMenuButton<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(await store.list('A'), hasLength(2));
      await t.tap(find.byType(PopupMenuButton<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(await store.list('A'), hasLength(1));
    },
  );
  testWidgets(
    'Search and title sort use names; compact Recent Activity shows at most three',
    (t) async {
      final store = memoryStore();
      for (final name in ['Zebra', 'Alpha', 'বাংলা', 'More']) {
        await store.save('A', name, LocalFileKind.txt, textBytes('x'), 'Text');
      }
      await boot(
        t,
        Scaffold(
          body: LocalFilesPanel(
            userId: 'A',
            store: store,
            sort: LibrarySort.titleAZ,
          ),
        ),
      );
      final tiles = t.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect((tiles.first.title as Text).data, 'Alpha.txt');
      await boot(
        t,
        Scaffold(
          body: LocalFilesPanel(userId: 'A', store: store, search: 'বাংলা'),
        ),
      );
      expect(find.text('বাংলা.txt'), findsOneWidget);
      expect(find.text('Zebra.txt'), findsNothing);
      await boot(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: LocalFilesPanel(userId: 'A', store: store, compact: true),
          ),
        ),
      );
      expect(find.byType(ListTile), findsNWidgets(3));
    },
  );
  testWidgets(
    'Late results from a previous owner never populate the new owner panel',
    (t) async {
      final backend = DelayedBackend();
      final info = LocalFileInfo(
        id: 'a' * 32,
        name: 'Secret.txt',
        kind: LocalFileKind.txt,
        size: 1,
        created: 1,
        updated: 1,
        source: 'Text',
      );
      await backend.add('A', info, textBytes('x'));
      final store = LocalFileStore(backend);

      final settings = AppSettings(store: MemorySettingsStore());
      await settings.setLanguage('en');
      await t.pumpWidget(
        settingsApp(
          settings,
          Scaffold(
            body: LocalFilesPanel(userId: 'A', store: store),
          ),
        ),
      );
      await t.pump();
      await t.pumpWidget(
        settingsApp(
          settings,
          Scaffold(
            body: LocalFilesPanel(userId: 'B', store: store),
          ),
        ),
      );
      await t.pump();
      backend.waiting.complete();
      await t.pumpAndSettle();
      expect(find.text('Secret.txt'), findsNothing);
      expect(find.textContaining('No local files yet'), findsOneWidget);
    },
  );
  testWidgets(
    'Preview download and share use the exact stored file, with honest completion notices',
    (t) async {
      final store = memoryStore(), delivery = TestDelivery();
      final file = await store.save(
        'A',
        'Note',
        LocalFileKind.txt,
        textBytes('বাংলা'),
        'Text',
      );
      await boot(
        t,
        LocalFileDetailsScreen(
          info: file,
          userId: 'A',
          store: store,
          delivery: delivery,
        ),
      );
      await t.tap(find.text('Download copy'));
      await t.pumpAndSettle();
      expect(utf8.decode(delivery.bytes!), 'বাংলা');
      expect(delivery.share, false);
      expect(
        find.text('Download requested. Check your Downloads folder.'),
        findsOneWidget,
      );
      delivery.result = PdfDelivery.shareOpened;
      await t.tap(find.text('Share file'));
      await t.pumpAndSettle();
      expect(delivery.share, true);
      expect(await store.list('A'), hasLength(1));
    },
  );
  testWidgets('Bangla controls fit a narrow screen with a large font', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final store = memoryStore();
    await store.save(
      'A',
      'অনেক বড় নামের ফাইল',
      LocalFileKind.txt,
      textBytes('লেখা'),
      'Text',
    );
    await boot(
      t,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.7)),
          child: Scaffold(
            body: LocalFilesPanel(userId: 'A', store: store),
          ),
        ),
      ),
      language: 'bn',
    );
    expect(find.text('এই ডিভাইসের লোকাল ফাইল'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
