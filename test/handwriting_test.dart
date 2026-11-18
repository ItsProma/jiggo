import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/handwriting_screen.dart';
import 'package:jiggo/screens/handwriting_text_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/handwriting_gateway.dart';
import 'package:jiggo/services/text_file_actions.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';
import 'scan_pdf_screen_test.dart' show FakePhotos, FakeImages, photo;

class FakeHandwriting implements HandwritingGateway {
  int recognitions = 0;
  String? language;
  Object? error;
  bool saveFails = false;
  bool saved = true;
  Completer<Map<String, dynamic>>? waiting;
  final updates = <List<String>>[];
  @override
  Future<Map<String, dynamic>> recognize(
    Uint8List bytes,
    String language,
  ) async {
    recognitions++;
    this.language = language;
    if (error != null) throw error!;
    if (waiting != null) return waiting!.future;
    return {
      'text': '  বাংলা নোট\nHome [unclear]',
      'title': 'Handwritten notes',
      'savedToLibrary': saved,
      'documentId': saved ? 'note-1' : null,
      'remainingToday': 9,
    };
  }

  @override
  Future<void> save(String id, String title, String text) async {
    updates.add([id, title, text]);
    if (saveFails) throw StateError('Offline');
  }
}

class FakeTextFiles implements TextFileActions {
  String? text, filename;
  PdfDelivery result = PdfDelivery.saved;
  bool fail = false;
  @override
  Future<PdfDelivery> save(String text, String filename) async {
    this.text = text;
    this.filename = filename;
    if (fail) throw StateError('Failed');
    return result;
  }

  @override
  Future<PdfDelivery> share(String text, String title) async {
    this.text = text;
    if (fail) throw StateError('Failed');
    return result;
  }
}

Future<void> tapHandwriting(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> sourceApp(
  WidgetTester tester,
  FakeHandwriting gateway,
  FakePhotos photos,
) async {
  await tester.binding.setSurfaceSize(const Size(700, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    settingsApp(
      AppSettings(store: MemorySettingsStore(), language: 'en'),
      HandwritingScreen(photos: photos, images: FakeImages(), gateway: gateway),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> resultApp(
  WidgetTester tester,
  FakeHandwriting gateway,
  FakeTextFiles files, {
  String? id = 'note-1',
}) async {
  await tester.binding.setSurfaceSize(const Size(700, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    settingsApp(
      AppSettings(store: MemorySettingsStore(), language: 'en'),
      HandwritingTextScreen(
        documentId: id,
        title: 'Notes',
        text: '# বাংলা\n* literal writing',
        gateway: gateway,
        files: files,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String writtenText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('handwriting-text')))
    .controller!
    .text;

void main() {
  testWidgets(
    'Photo picking does not call AI; recognition keeps exact original-script text editable',
    (tester) async {
      final gateway = FakeHandwriting(),
          photos = FakePhotos()..next = [photo('notes.jpg')];
      await sourceApp(tester, gateway, photos);
      await tapHandwriting(tester, 'handwriting-gallery');
      expect(gateway.recognitions, 0);
      await tapHandwriting(tester, 'handwriting-recognize');
      expect(gateway.language, 'auto');
      expect(writtenText(tester), '  বাংলা নোট\nHome [unclear]');
      expect(find.byType(HandwritingTextScreen), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('handwriting-save')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Unreadable image reports a useful error and permits another photo',
    (tester) async {
      final gateway = FakeHandwriting()
        ..error = FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Unreadable',
          details: {'reason': 'handwriting-unreadable'},
        );
      final photos = FakePhotos()..next = [photo('notes.jpg')];
      await sourceApp(tester, gateway, photos);
      await tapHandwriting(tester, 'handwriting-gallery');
      await tapHandwriting(tester, 'handwriting-recognize');
      expect(find.textContaining('No readable handwriting'), findsOneWidget);
      expect(find.byType(HandwritingTextScreen), findsNothing);
      await tapHandwriting(tester, 'handwriting-camera');
      expect(photos.camera, true);
    },
  );

  testWidgets('Failed or cancelled picking preserves the selected photo', (
    tester,
  ) async {
    final gateway = FakeHandwriting(),
        photos = FakePhotos()..next = [photo('notes.jpg')];
    await sourceApp(tester, gateway, photos);
    await tapHandwriting(tester, 'handwriting-gallery');
    photos.next = [];
    await tapHandwriting(tester, 'handwriting-gallery');
    photos.fail = true;
    await tapHandwriting(tester, 'handwriting-camera');
    expect(find.byType(Image), findsOneWidget);
    expect(gateway.recognitions, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('handwriting-recognize')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'Busy recognition blocks duplicate charges and ignores a late reply after exit',
    (tester) async {
      final gateway = FakeHandwriting()
        ..waiting = Completer<Map<String, dynamic>>();
      final photos = FakePhotos()..next = [photo('notes.jpg')];
      await sourceApp(tester, gateway, photos);
      await tapHandwriting(tester, 'handwriting-gallery');
      final button = find.byKey(const ValueKey('handwriting-recognize'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(gateway.recognitions, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gateway.waiting!.complete({
        'text': 'Late',
        'title': 'Notes',
        'savedToLibrary': true,
        'documentId': 'note-1',
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Corrected text and title save to the same Library note and survive save failure',
    (tester) async {
      final gateway = FakeHandwriting()..saveFails = true;
      await resultApp(tester, gateway, FakeTextFiles());
      await tester.enterText(
        find.byKey(const ValueKey('handwriting-title')),
        'My corrected notes',
      );
      await tester.enterText(
        find.byKey(const ValueKey('handwriting-text')),
        'সংশোধিত লেখা\nLiteral ** text',
      );
      await tapHandwriting(tester, 'handwriting-save');
      expect(writtenText(tester), 'সংশোধিত লেখা\nLiteral ** text');
      expect(find.textContaining('Unable to save changes'), findsOneWidget);
      gateway.saveFails = false;
      await tapHandwriting(tester, 'handwriting-save');
      expect(gateway.updates.last, [
        'note-1',
        'My corrected notes',
        'সংশোধিত লেখা\nLiteral ** text',
      ]);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('handwriting-save')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Unconfirmed Library save still permits text copy and export without fake cloud saving',
    (tester) async {
      final gateway = FakeHandwriting(), files = FakeTextFiles();
      await resultApp(tester, gateway, files, id: null);
      expect(
        find.textContaining('Library saving was not confirmed'),
        findsOneWidget,
      );
      await tapHandwriting(tester, 'handwriting-download');
      expect(files.text, '# বাংলা\n* literal writing');
      expect(files.filename, 'Notes.txt');
      expect(gateway.updates, isEmpty);
      files.result = PdfDelivery.cancelled;
      await tapHandwriting(tester, 'handwriting-share');
      expect(writtenText(tester), '# বাংলা\n* literal writing');
    },
  );

  testWidgets('Copy preserves literal text and malformed edits are not saved', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final gateway = FakeHandwriting();
    await resultApp(tester, gateway, FakeTextFiles());
    await tapHandwriting(tester, 'handwriting-copy');
    expect(copied, '# বাংলা\n* literal writing');
    await tester.enterText(
      find.byKey(const ValueKey('handwriting-text')),
      'x' * 20001,
    );
    await tapHandwriting(tester, 'handwriting-save');
    expect(gateway.updates, isEmpty);
    expect(writtenText(tester).length, 20001);
  });

  test(
    'Native TXT saving encodes Bangla as UTF-8 and shares plain text',
    () async {
      const channel = MethodChannel('jiggo/pdf_files');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final files = DeviceTextFileActions();
      expect(await files.save('বাংলা\nText', 'নোট.txt'), PdfDelivery.saved);
      expect(calls.single.method, 'saveText');
      expect(
        utf8.decode((calls.single.arguments as Map)['bytes'] as Uint8List),
        'বাংলা\nText',
      );
      await files.share('বাংলা\nText', 'Notes');
      expect(calls.last.method, 'shareText');
      expect((calls.last.arguments as Map)['text'], 'বাংলা\nText');
    },
  );

  for (final language in ['bn', 'en']) {
    testWidgets(
      'Handwriting note editor supports narrow screens, large text and keyboard: $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final exported = FakeTextFiles();
        await tester.pumpWidget(
          settingsApp(
            AppSettings(
              store: MemorySettingsStore(),
              language: language,
              themeMode: ThemeMode.dark,
            ),
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 200),
                ),
                child: HandwritingTextScreen(
                  title: 'My notes',
                  text: 'বাংলা\nEnglish [unclear]',
                  documentId: 'note-1',
                  gateway: FakeHandwriting(),
                  files: exported,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapHandwriting(tester, 'handwriting-download');
        expect(exported.text, 'বাংলা\nEnglish [unclear]');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
