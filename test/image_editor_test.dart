import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/screens/image_editor_screen.dart';
import 'package:jiggo/services/image_edit_files.dart';
import 'package:jiggo/services/image_edit_files_native.dart' as native;
import 'package:jiggo/services/image_edit_model.dart';
import 'package:jiggo/services/image_edit_processor.dart';
import 'package:jiggo/services/pdf_scan_image.dart' show ScanCrop;
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/widgets/image_text_editor.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';
import 'image_edit_processing_test.dart' show transparentPhoto;

class FakeFiles implements ImageEditFiles {
  PickedEditorImage? next;
  Completer<PickedEditorImage?>? waiting;
  Uint8List? saved, shared;
  String? name;
  bool fails = false;
  PdfDelivery result = PdfDelivery.downloadRequested;
  @override
  Future<PickedEditorImage?> pick() async =>
      waiting == null ? next : await waiting!.future;
  @override
  Future<PdfDelivery> save(Uint8List bytes, String filename) async {
    saved = bytes;
    name = filename;
    if (fails) throw StateError('failure');
    return result;
  }

  @override
  Future<PdfDelivery> share(Uint8List bytes, String filename) async {
    shared = bytes;
    name = filename;
    return PdfDelivery.shareOpened;
  }
}

class FakeProcessor extends ImageEditProcessor {
  bool failPrepare = false;
  int prepares = 0, textEdits = 0;
  ImageLabel? lastLabel;
  EditedImage frame(img.Image image) =>
      EditedImage(img.encodePng(image), image.width, image.height);
  @override
  Future<ImportedImage> prepare(Uint8List bytes, String name) async {
    prepares++;
    if (failPrepare) throw const FormatException();
    final image = img.decodePng(bytes)!;
    return ImportedImage(frame(image), name, 'png');
  }

  @override
  Future<EditedImage> rotate(EditedImage image) async =>
      frame(img.copyRotate(img.decodePng(image.bytes)!, angle: 90));
  @override
  Future<EditedImage> resize(EditedImage image, int w, int h) async =>
      frame(img.copyResize(img.decodePng(image.bytes)!, width: w, height: h));
  @override
  Future<EditedImage> crop(EditedImage image, ScanCrop crop) async => frame(
    img.copyCrop(
      img.decodePng(image.bytes)!,
      x: 0,
      y: 0,
      width: 120,
      height: 80,
    ),
  );
  @override
  Future<EditedImage> addText(EditedImage image, ImageLabel label) async {
    textEdits++;
    lastLabel = label;
    final copy = img.decodePng(image.bytes)!;
    copy.setPixelRgba(0, 0, 0, 255, 0, 255);
    return frame(copy);
  }

  @override
  Future<Uint8List> export(EditedImage image, String format) async =>
      image.bytes;
}

Future<void> boot(
  WidgetTester t,
  FakeFiles files,
  FakeProcessor processor,
) async {
  final settings = AppSettings(store: MemorySettingsStore());
  await settings.setLanguage('en');
  await t.pumpWidget(
    settingsApp(
      settings,
      ImageEditorScreen(files: files, processor: processor),
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

Future<void> toolbar(WidgetTester t, String tooltip) async {
  await t.ensureVisible(find.byTooltip(tooltip));
  await t.pumpAndSettle();
  await t.tap(find.byTooltip(tooltip));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Open, rotate, undo/redo and PNG export retain edits without changing source',
    (t) async {
      final source = transparentPhoto();
      final files = FakeFiles()..next = PickedEditorImage('photo.png', source);
      await boot(t, files, FakeProcessor());
      await tap(t, 'Open image');
      expect(find.text('240 × 160 px'), findsOneWidget);
      await tap(t, 'Rotate image');
      expect(find.text('160 × 240 px'), findsOneWidget);
      await toolbar(t, 'Undo');
      expect(find.text('240 × 160 px'), findsOneWidget);
      await toolbar(t, 'Redo');
      expect(find.text('160 × 240 px'), findsOneWidget);
      await tap(t, 'Save image copy');
      expect(files.name, 'photo_edited.png');
      expect(img.decodePng(files.saved!)!.height, 240);
      expect(files.next!.bytes, orderedEquals(source));
      await tap(t, 'Share image');
      expect(files.shared, orderedEquals(files.saved!));
    },
  );
  testWidgets(
    'Crop applies through the shared crop UI and reset can itself be undone',
    (t) async {
      final files = FakeFiles()
        ..next = PickedEditorImage('photo.png', transparentPhoto());
      await boot(t, files, FakeProcessor());
      await tap(t, 'Open image');
      await tap(t, 'Crop image');
      await tap(t, 'Apply crop');
      expect(find.text('120 × 80 px'), findsOneWidget);
      await tap(t, 'Reset image');
      expect(find.text('240 × 160 px'), findsOneWidget);
      await toolbar(t, 'Undo');
      expect(find.text('120 × 80 px'), findsOneWidget);
    },
  );
  testWidgets(
    'Resize preserves proportions, rejects invalid dimensions and cancels without losing edits',
    (t) async {
      final files = FakeFiles()
        ..next = PickedEditorImage('photo.png', transparentPhoto());
      await boot(t, files, FakeProcessor());
      await tap(t, 'Open image');
      await tap(t, 'Resize image');
      await t.enterText(
        find.byKey(const ValueKey('image-resize-width')),
        '120',
      );
      expect(
        t
            .widget<TextField>(
              find.byKey(const ValueKey('image-resize-height')),
            )
            .controller!
            .text,
        '80',
      );
      await tap(t, 'Apply resize');
      expect(find.text('120 × 80 px'), findsOneWidget);
      await tap(t, 'Resize image');
      await t.enterText(
        find.byKey(const ValueKey('image-resize-width')),
        '9999',
      );
      await tap(t, 'Apply resize');
      expect(
        find.text(
          'Choose valid dimensions within 4096 pixels and 6 megapixels.',
        ),
        findsOneWidget,
      );
      await tap(t, 'Cancel');
      expect(find.text('120 × 80 px'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Text preview applies only on confirmation and its pixels can be undone',
    (t) async {
      final processor = FakeProcessor();
      final files = FakeFiles()
        ..next = PickedEditorImage('photo.png', transparentPhoto());
      await boot(t, files, processor);
      await tap(t, 'Open image');
      await tap(t, 'Add text');
      await t.enterText(
        find.byKey(const ValueKey('image-label-text')),
        'বাংলা Hello',
      );
      await t.pumpAndSettle();
      final placement = find.byKey(const ValueKey('image-label-placement'));
      await t.ensureVisible(placement);
      await t.pumpAndSettle();
      final rect = t.getRect(placement);
      await t.tapAt(
        Offset(rect.left + rect.width * .8, rect.top + rect.height * .2),
      );
      await t.pumpAndSettle();
      await tap(t, 'Apply text');
      expect(processor.textEdits, 1);
      expect(processor.lastLabel!.x, closeTo(.8, .01));
      expect(processor.lastLabel!.y, closeTo(.2, .01));
      await tap(t, 'Save image copy');
      final added = Uint8List.fromList(files.saved!);
      await toolbar(t, 'Undo');
      await tap(t, 'Save image copy');
      expect(files.saved, isNot(orderedEquals(added)));
      await toolbar(t, 'Redo');
      await tap(t, 'Save image copy');
      expect(files.saved, orderedEquals(added));
    },
  );
  testWidgets(
    'Failed export, failed opening and cancelled picker keep current edited image',
    (t) async {
      final processor = FakeProcessor();
      final files = FakeFiles()
        ..next = PickedEditorImage('photo.png', transparentPhoto());
      await boot(t, files, processor);
      await tap(t, 'Open image');
      await tap(t, 'Rotate image');
      files.fails = true;
      await tap(t, 'Save image copy');
      expect(
        find.textContaining('Unable to save or share this image.'),
        findsOneWidget,
      );
      files.next = null;
      await tap(t, 'Open image');
      await tap(t, 'Continue');
      expect(find.text('160 × 240 px'), findsOneWidget);
      processor.failPrepare = true;
      files.next = PickedEditorImage('bad.png', Uint8List.fromList([1]));
      await tap(t, 'Open image');
      await tap(t, 'Continue');
      expect(find.textContaining('Could not open this image.'), findsOneWidget);
      expect(find.text('160 × 240 px'), findsOneWidget);
    },
  );
  testWidgets(
    'Pending picker blocks duplicate opening and ignores late replies after leaving',
    (t) async {
      final processor = FakeProcessor();
      final files = FakeFiles()..waiting = Completer<PickedEditorImage?>();
      await boot(t, files, processor);
      await t.tap(find.text('Open image'));
      await t.pump();
      final button = t.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('Open image'),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(button.onPressed, isNull);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      files.waiting!.complete(
        PickedEditorImage('late.png', transparentPhoto()),
      );
      await t.pumpAndSettle();
      expect(processor.prepares, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Native image save/share methods deliver binary data and retain cancellation state',
    (t) async {
      const channel = MethodChannel('jiggo/pdf_files');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'saveImage' ? false : true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final files = native.PlatformImageFiles(), bytes = transparentPhoto();
      expect(await files.save(bytes, 'test_edited.png'), PdfDelivery.cancelled);
      expect(
        await files.share(bytes, 'test_edited.png'),
        PdfDelivery.shareOpened,
      );
      expect(calls.map((c) => c.method), ['saveImage', 'shareImage']);
      expect((calls.first.arguments as Map)['bytes'], bytes);
    },
  );
  for (final lang in ['bn', 'en']) {
    testWidgets(
      'Image editing and text placement fit a narrow screen, large fonts and dark mode: $lang',
      (t) async {
        t.view.physicalSize = const Size(320, 700);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final settings = AppSettings(store: MemorySettingsStore());
        await settings.setLanguage(lang);
        await settings.setThemeMode(ThemeMode.dark);
        final files = FakeFiles()
          ..next = PickedEditorImage('photo.png', transparentPhoto());
        await t.pumpWidget(
          settingsApp(
            settings,
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: 180),
              ),
              child: ImageEditorScreen(
                files: files,
                processor: FakeProcessor(),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await tap(t, lang == 'bn' ? 'ছবি খোলো' : 'Open image');
        await tap(t, lang == 'bn' ? 'লেখা যোগ করো' : 'Add text');
        await t.enterText(
          find.byKey(const ValueKey('image-label-text')),
          'বাংলা English',
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await tap(t, lang == 'bn' ? 'লেখা বসাও' : 'Apply text');
        expect(t.takeException(), isNull);
        await t.pumpWidget(
          settingsApp(
            settings,
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: 180),
              ),
              child: ImageTextEditor(
                image: EditedImage(transparentPhoto(), 240, 160),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('image-label-text')),
          'বাংলা English',
        );
        await t.pumpAndSettle();
        await t.ensureVisible(
          find.text(lang == 'bn' ? 'লেখা বসাও' : 'Apply text'),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
