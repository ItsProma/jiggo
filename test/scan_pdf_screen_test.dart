import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/screens/scan_pdf_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/pdf_scan_image.dart';
import 'package:jiggo/services/scan_pdf_builder.dart';
import 'package:jiggo/services/scan_photo_source.dart';
import 'package:jiggo/services/pdf_file_actions.dart';
import 'package:jiggo/widgets/scan_crop_editor.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

final tinyJpeg = img.encodeJpg(img.Image(width: 32, height: 48));
XFile photo(String name) =>
    XFile.fromData(tinyJpeg, name: name, path: name, mimeType: 'image/jpeg');

class FakePhotos implements ScanPhotoSource {
  List<XFile> next = [];
  bool fail = false;
  bool? camera;
  int calls = 0;
  @override
  Future<List<XFile>> pick({required bool camera, required int limit}) async {
    calls++;
    this.camera = camera;
    if (fail) throw PlatformException(code: 'denied');
    return next;
  }
}

class FakeImages extends PdfScanImages {
  Completer<void>? waiting;
  @override
  Future<PdfScanPage> prepare(
    Uint8List bytes, {
    required int id,
    required String name,
  }) async {
    if (waiting != null) await waiting!.future;
    if (bytes.first == 1) throw const FormatException();
    return PdfScanPage(
      id: id,
      name: name,
      original: tinyJpeg,
      preview: tinyJpeg,
      width: 32,
      height: 48,
    );
  }

  @override
  Future<PdfScanPage> transform(
    PdfScanPage page, {
    int? quarterTurns,
    ScanCrop? crop,
  }) async => PdfScanPage(
    id: page.id,
    name: page.name,
    original: page.original,
    preview: page.preview,
    width: 32,
    height: 48,
    quarterTurns: quarterTurns ?? 0,
    crop: crop ?? ScanCrop.full,
  );
}

class FakePdfBuilder extends ScanPdfBuilder {
  final built = <List<PdfScanPage>>[];
  bool fail = false;
  @override
  Future<Uint8List> build(List<PdfScanPage> pages, String title) async {
    built.add(pages);
    if (fail) throw StateError('Failed');
    return Uint8List.fromList('%PDF-1.7 test'.codeUnits);
  }
}

class FakePdfFiles implements PdfFileActions {
  PdfDelivery result = PdfDelivery.saved;
  bool fail = false;
  int saves = 0, shares = 0;
  String? filename;
  @override
  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    saves++;
    this.filename = filename;
    if (fail) throw PlatformException(code: 'write-failed');
    return result;
  }

  @override
  Future<PdfDelivery> share(Uint8List bytes, String filename) async {
    shares++;
    this.filename = filename;
    return result;
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find
          .descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openScanner(
  WidgetTester tester,
  FakePhotos photos,
  FakePdfBuilder builder,
  FakePdfFiles files, {
  FakeImages? images,
}) async {
  await tester.binding.setSurfaceSize(const Size(700, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    settingsApp(
      AppSettings(store: MemorySettingsStore(), language: 'en'),
      ScanPdfScreen(
        photos: photos,
        images: images ?? FakeImages(),
        builder: builder,
        files: files,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Dragging the handle changes the PDF page order', (tester) async {
    final photos = FakePhotos()
      ..next = [photo('A.jpg'), photo('B.jpg'), photo('C.jpg')];
    final builder = FakePdfBuilder();
    await openScanner(tester, photos, builder, FakePdfFiles());
    await tester.binding.setSurfaceSize(const Size(700, 1600));
    await tester.pumpAndSettle();
    await tapKey(tester, 'scan-pdf-gallery');
    final from = tester.getCenter(
      find.descendant(
        of: find.byKey(const ValueKey(1)),
        matching: find.byType(ReorderableDragStartListener),
      ),
    );
    final to = tester.getCenter(
      find.descendant(
        of: find.byKey(const ValueKey(3)),
        matching: find.byType(ReorderableDragStartListener),
      ),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveBy(Offset(0, to.dy - from.dy + 60));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle();
    await tapKey(tester, 'scan-pdf-create');
    expect(builder.built.single.map((p) => p.name), [
      'B.jpg',
      'A.jpg',
      'C.jpg',
    ]);
  });

  testWidgets(
    'Import, reorder, crop, rotate and remove feed exactly the chosen PDF pages',
    (tester) async {
      final photos = FakePhotos()
        ..next = [photo('A.jpg'), photo('B.jpg'), photo('C.jpg')];
      final builder = FakePdfBuilder(), files = FakePdfFiles();
      await openScanner(tester, photos, builder, files);
      await tapKey(tester, 'scan-pdf-gallery');
      expect(photos.camera, false);
      await tapKey(tester, 'down-1');
      await tapKey(tester, 'rotate-2');
      await tapKey(tester, 'crop-1');
      await tester.tap(find.text('Trim edges'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'apply-scan-crop');
      await tapKey(tester, 'remove-3');
      await tapKey(tester, 'scan-pdf-create');
      expect(builder.built.single.map((p) => p.name), ['B.jpg', 'A.jpg']);
      expect(builder.built.single.first.quarterTurns, 1);
      expect(builder.built.single.last.crop.width, closeTo(.9, .0001));
    },
  );

  testWidgets(
    'Save cancellation and errors preserve cached PDF for a safe retry',
    (tester) async {
      final photos = FakePhotos()..next = [photo('A.jpg')];
      final builder = FakePdfBuilder(),
          files = FakePdfFiles()..result = PdfDelivery.cancelled;
      await openScanner(tester, photos, builder, files);
      await tapKey(tester, 'scan-pdf-camera');
      expect(photos.camera, true);
      await tapKey(tester, 'scan-pdf-create');
      await tapKey(tester, 'scan-pdf-save');
      expect(find.textContaining('was cancelled'), findsOneWidget);
      files.fail = true;
      await tapKey(tester, 'scan-pdf-save');
      expect(find.textContaining('Unable to save or share'), findsOneWidget);
      files.fail = false;
      files.result = PdfDelivery.saved;
      await tapKey(tester, 'scan-pdf-save');
      await tapKey(tester, 'scan-pdf-share');
      expect(builder.built.length, 1);
      expect(files.saves, 3);
      expect(files.shares, 1);
      expect(files.filename, 'Scanned document.pdf');
    },
  );

  testWidgets(
    'Changes invalidate old PDF; failed generation leaves editable pages',
    (tester) async {
      final photos = FakePhotos()..next = [photo('A.jpg')];
      final builder = FakePdfBuilder(), files = FakePdfFiles();
      await openScanner(tester, photos, builder, files);
      await tapKey(tester, 'scan-pdf-gallery');
      await tapKey(tester, 'scan-pdf-create');
      await tester.enterText(
        find.byKey(const ValueKey('scan-pdf-title')),
        'My pages',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scan-pdf-save')), findsNothing);
      builder.fail = true;
      await tapKey(tester, 'scan-pdf-create');
      expect(find.textContaining('Your pages are kept'), findsOneWidget);
      builder.fail = false;
      await tapKey(tester, 'rotate-1');
      await tapKey(tester, 'reset-1');
      await tapKey(tester, 'scan-pdf-create');
      await tapKey(tester, 'scan-pdf-save');
      expect(files.filename, 'My pages.pdf');
      expect(builder.built.last.single.quarterTurns, 0);
    },
  );

  testWidgets(
    'Bad photos, picker cancellation and denied permission keep valid pages',
    (tester) async {
      final photos = FakePhotos()
        ..next = [
          photo('good.jpg'),
          XFile.fromData(Uint8List.fromList([1, 2]), name: 'bad.txt'),
        ];
      final builder = FakePdfBuilder(), files = FakePdfFiles();
      await openScanner(tester, photos, builder, files);
      await tapKey(tester, 'scan-pdf-gallery');
      expect(find.text('Added 1 page(s). Skipped 1 file(s).'), findsOneWidget);
      photos.next = [];
      await tapKey(tester, 'scan-pdf-gallery');
      photos.fail = true;
      await tapKey(tester, 'scan-pdf-camera');
      expect(find.textContaining('Check permission'), findsOneWidget);
      await tapKey(tester, 'scan-pdf-create');
      expect(builder.built.single.single.name, 'good.jpg');
    },
  );

  testWidgets('Page cap is enforced even if picker returns too many files', (
    tester,
  ) async {
    final photos = FakePhotos()
      ..next = List.generate(22, (i) => photo('Page $i'));
    final builder = FakePdfBuilder(), files = FakePdfFiles();
    await openScanner(tester, photos, builder, files);
    await tapKey(tester, 'scan-pdf-gallery');
    expect(find.text('Added 20 page(s). Skipped 2 file(s).'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('scan-pdf-gallery')),
          )
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'scan-pdf-create');
    expect(builder.built.single.length, 20);
  });

  testWidgets(
    'Late image preparation after leaving does not touch disposed state',
    (tester) async {
      final photos = FakePhotos()..next = [photo('A.jpg')];
      final images = FakeImages()..waiting = Completer<void>();
      await openScanner(
        tester,
        photos,
        FakePdfBuilder(),
        FakePdfFiles(),
        images: images,
      );
      await tester.tap(find.byKey(const ValueKey('scan-pdf-gallery')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('scan-pdf-create')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      images.waiting!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['en', 'bn']) {
    testWidgets('Crop handles and footer fit large text: $language', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = AppSettings(
        store: MemorySettingsStore(),
        language: language,
        themeMode: ThemeMode.dark,
      );
      final page = PdfScanPage(
        id: 1,
        name: 'crop.jpg',
        original: tinyJpeg,
        preview: tinyJpeg,
        width: 32,
        height: 48,
      );
      await tester.pumpWidget(
        settingsApp(
          settings,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: ScanCropEditor(page: page),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey(ScanCropHandle.topLeft));
      final before = tester.getCenter(handle);
      await tester.drag(handle, const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(tester.getCenter(handle).dx, greaterThan(before.dx));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('apply-scan-crop')), findsOneWidget);
    });

    testWidgets(
      'Photo PDF and crop editor fit narrow screen with large text: $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final settings = AppSettings(
          store: MemorySettingsStore(),
          language: language,
          themeMode: ThemeMode.dark,
        );
        final photos = FakePhotos()..next = [photo('page.jpg')];
        await tester.pumpWidget(
          settingsApp(
            settings,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 200),
                ),
                child: ScanPdfScreen(
                  photos: photos,
                  images: FakeImages(),
                  builder: FakePdfBuilder(),
                  files: FakePdfFiles(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'scan-pdf-gallery');
        await tapKey(tester, 'crop-1');
        await tapKey(tester, 'apply-scan-crop');
        await tapKey(tester, 'scan-pdf-create');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
