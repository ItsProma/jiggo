import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jiggo/screens/pdf_markup_screen.dart';
import 'package:jiggo/services/pdf_markup_model.dart';
import 'package:jiggo/services/image_edit_model.dart';
import 'package:jiggo/services/image_edit_files.dart';
import 'package:jiggo/services/image_edit_processor.dart';

import 'dart:typed_data';

import 'package:jiggo/services/app_settings.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

EditedImage background() {
  final i = img.Image(width: 320, height: 440, numChannels: 4);
  img.fill(i, color: img.ColorRgba8(255, 255, 255, 255));
  return EditedImage(img.encodePng(i), 320, 440);
}

Future<void> reveal(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  if (f.evaluate().isEmpty) {
    final scroll = find.byType(Scrollable).first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await t.pumpAndSettle();
    for (var i = 0; i < 50 && f.evaluate().isEmpty; i++) {
      final position = t.state<ScrollableState>(scroll).position;
      position.jumpTo(
        (position.pixels + 150).clamp(0.0, position.maxScrollExtent),
      );
      await t.pumpAndSettle();
    }
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  await reveal(t, find.text(label));
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

Future<void> draw(WidgetTester t) async {
  final f = find.byKey(const ValueKey('pdf-markup-board'));
  await reveal(t, f);
  final rect = t.getRect(f);
  final gesture = await t.startGesture(
    rect.topLeft + Offset(rect.width * .2, rect.height * .25),
  );
  await gesture.moveBy(Offset(rect.width * .4, rect.height * .15));
  await gesture.up();
  await t.pumpAndSettle();
}

class ImageFiles implements ImageEditFiles {
  bool cancel = true;
  @override
  Future<PickedEditorImage?> pick() async =>
      cancel ? null : PickedEditorImage('tiny.png', background().bytes);
  @override
  Future<PdfDelivery> save(Uint8List b, String n) async => PdfDelivery.saved;
  @override
  Future<PdfDelivery> share(Uint8List b, String n) async =>
      PdfDelivery.shareOpened;
}

class Processor extends ImageEditProcessor {
  @override
  Future<ImportedImage> prepare(Uint8List b, String name) async =>
      ImportedImage(background(), name, 'png', reduced: false);
}

void main() {
  testWidgets(
    'text draw highlight signature undo redo delete apply pass exact marks',
    (t) async {
      final settings = AppSettings(store: MemorySettingsStore());
      await settings.setLanguage('en');
      List<PdfMark>? output;
      await t.pumpWidget(
        settingsApp(
          settings,
          PdfMarkupScreen(
            background: background(),
            render: (image, marks) async {
              output = List.of(marks);
              return image;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Add text');
      await t.enterText(
        find.byKey(const ValueKey('pdf-markup-text')),
        'বাংলা Hello',
      );
      await tap(t, 'Next');
      await draw(t);
      await tap(t, 'Draw');
      await draw(t);
      await tap(t, 'Highlight area');
      await draw(t);
      await tap(t, 'Draw signature');
      await draw(t);
      await tap(t, 'Undo');
      await tap(t, 'Redo');
      await tap(t, 'Delete item');
      await tap(t, 'Undo');
      await tap(t, 'Apply to page');
      expect(output!.map((m) => m.kind), [
        PdfMarkKind.text,
        PdfMarkKind.pen,
        PdfMarkKind.highlight,
        PdfMarkKind.signature,
      ]);
      expect(output!.first.text, 'বাংলা Hello');
    },
  );
  testWidgets('apply error retains marks and can retry', (t) async {
    var fail = true;
    var count = 0;
    final settings = AppSettings(store: MemorySettingsStore());
    await settings.setLanguage('en');
    await t.pumpWidget(
      settingsApp(
        settings,
        PdfMarkupScreen(
          background: background(),
          render: (image, marks) async {
            count++;
            if (fail) throw const FormatException();
            return image;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Draw');
    await draw(t);
    await tap(t, 'Apply to page');
    await reveal(
      t,
      find.text('Could not apply markup. Your page changes are kept here.'),
    );
    expect(
      find.text('Could not apply markup. Your page changes are kept here.'),
      findsOneWidget,
    );
    fail = false;
    await tap(t, 'Apply to page');
    expect(count, 2);
  });
  testWidgets(
    'image picker cancellation keeps draft; image can be placed and applied',
    (t) async {
      final settings = AppSettings(store: MemorySettingsStore());
      await settings.setLanguage('en');
      final files = ImageFiles();
      List<PdfMark>? result;
      await t.pumpWidget(
        settingsApp(
          settings,
          PdfMarkupScreen(
            background: background(),
            imageFiles: files,
            processor: Processor(),
            render: (i, m) async {
              result = List.of(m);
              return i;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Add image');
      expect(
        find.text('Tap or drag on the page to place your item.'),
        findsNothing,
      );
      files.cancel = false;
      await reveal(t, find.text('Add image'));
      final button = t.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Add image'),
          matching: find.byType(OutlinedButton),
        ),
      );
      await t.runAsync(() async {
        final dynamic action = button.onPressed;
        await action();
      });
      await t.pumpAndSettle();
      await draw(t);
      await tap(t, 'Apply to page');
      expect(result!.single.kind, PdfMarkKind.image);
      expect(result!.single.image, isNotNull);
    },
  );
  testWidgets('scroll mode lets a touch on the board scroll the page', (
    t,
  ) async {
    final settings = AppSettings(store: MemorySettingsStore());
    await settings.setLanguage('en');
    await t.pumpWidget(
      settingsApp(settings, PdfMarkupScreen(background: background())),
    );
    await t.pumpAndSettle();
    await tap(t, 'Draw');
    await draw(t);
    await tap(t, 'Scroll page');
    final scroll = find.byType(Scrollable).first;
    final position = t.state<ScrollableState>(scroll).position;
    await reveal(t, find.byKey(const ValueKey('pdf-markup-board')));
    final before = position.pixels;
    await t.drag(
      find.byKey(const ValueKey('pdf-markup-board')),
      const Offset(0, -80),
    );
    await t.pumpAndSettle();
    expect(position.pixels, greaterThan(before));
  });
  for (final language in ['en', 'bn']) {
    testWidgets('loaded markup at 320px large font dark keyboard $language', (
      t,
    ) async {
      await t.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final settings = AppSettings(store: MemorySettingsStore());
      await settings.setLanguage(language);
      await settings.setThemeMode(ThemeMode.dark);
      await t.pumpWidget(
        settingsApp(
          settings,
          MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 200),
            ),
            child: PdfMarkupScreen(
              background: background(),
              render: (image, marks) async => image,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, language == 'en' ? 'Draw' : 'আঁকো');
      await draw(t);
      await tap(t, language == 'en' ? 'Undo' : 'আগের অবস্থায় ফেরাও');
      await tap(t, language == 'en' ? 'Add text' : 'লেখা যোগ করো');
      await t.enterText(
        find.byKey(const ValueKey('pdf-markup-text')),
        'বাংলা Test',
      );
      await tap(t, language == 'en' ? 'Next' : 'পরের ধাপ');
      await draw(t);
      expect(t.takeException(), isNull);
    });
  }
}
