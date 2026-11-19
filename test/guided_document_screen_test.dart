import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/guided_document_screen.dart';
import 'package:jiggo/services/guided_document_model.dart';
import 'package:jiggo/services/document_selections.dart';
import 'package:jiggo/services/guided_document_gateway.dart';
import 'package:jiggo/services/local_file_saver.dart';
import 'package:jiggo/services/local_file_model.dart';
import 'package:jiggo/services/app_settings.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';
import 'support/memory_guided_drafts.dart';

class Gateway implements GuidedDocumentGateway {
  int calls = 0;
  bool fails = false;
  String? brief;
  Completer<Map<String, dynamic>>? waiting;
  @override
  Future<Map<String, dynamic>> generate(GuidedDocument doc) async {
    calls++;
    brief = doc.instructions;
    if (fails) throw StateError('offline');
    return waiting != null
        ? waiting!.future
        : {'document': '## Draft\n\nSupplied facts only.', 'remainingToday': 9};
  }
}

class Details implements DocumentDetailsGateway {
  int calls = 0;
  bool fails = false;
  Completer<Map<String, dynamic>>? waiting;
  Map<String, dynamic> result = {
    'details': {
      'values': {'name': 'Rina', 'reason': 'Ill'},
      'education': <String>[],
      'experience': <String>[],
    },
    'remainingToday': 9,
  };
  @override
  Future<Map<String, dynamic>> extract(
    GuidedDocument document,
    String input,
  ) async {
    calls++;
    if (fails) throw StateError('offline');
    return waiting != null ? waiting!.future : result;
  }
}

class Saver implements LocalFileSaver {
  int calls = 0;
  String? name;
  bool fails = false;
  @override
  Future<void> save(
    String filename,
    LocalFileKind kind,
    Uint8List bytes,
    String source,
  ) async {
    if (fails) throw StateError('full');
    calls++;
    name = filename;
    expect(kind, LocalFileKind.pdf);
  }
}

Future<void> tap(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> next(WidgetTester t) async {
  // Existing workflow tests use these explicit answers; product forms start blank.
  t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
  await t.pumpAndSettle();
  for (final pick in [
    ('mode', 'Student'),
    ('noExperience', 'yes'),
    ('context', 'College'),
    ('purpose', 'Request'),
    ('length', '500'),
  ]) {
    final chip = find.byKey(ValueKey('select-${pick.$1}-${pick.$2}'));
    if (chip.evaluate().isNotEmpty && !t.widget<FilterChip>(chip).selected) {
      await tap(t, chip);
    }
  }
  await tap(t, find.byKey(const ValueKey('guided-next')));
}

Future<void> enter(WidgetTester t, String key, String value) async {
  final f = find.byKey(ValueKey('guided-$key'));
  if (key != 'quick-input' && f.evaluate().isEmpty) {
    final screen = t.widget<GuidedDocumentScreen>(
      find.byType(GuidedDocumentScreen),
    );
    final spec = documentSelections(GuidedDocument(screen.documentType))
        .where((s) => s.id == key);
    if (spec.isNotEmpty && spec.first.options.contains('Other')) {
      await tap(t, find.byKey(ValueKey('select-$key-Other')));
    } else {
      final optional = find.byKey(ValueKey('optional-$key'));
      if (optional.evaluate().isNotEmpty) {
        await tap(
          t,
          find.descendant(of: optional, matching: find.byType(ListTile)).first,
        );
      }
    }
  }
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pump();
}

Future<void> boot(
  WidgetTester t,
  String type,
  MemoryGuidedDrafts store, {
  Gateway? gateway,
  Saver? saver,
  String language = 'en',
  String? Function()? owner,
  bool startQuick = false,
  DocumentDetailsGateway? details,
}) async {
  await t.pumpWidget(
    settingsApp(
      AppSettings(store: MemorySettingsStore(), language: language),
      GuidedDocumentScreen(
        documentType: type,
        ownerId: 'A',
        currentOwner: owner ?? () => 'A',
        store: store,
        gateway: gateway ?? Gateway(),
        detailsGateway: details,
        saver: saver,
        pdfBuilder: ({
          required title,
          required content,
          bool modern = false,
        }) async => Uint8List.fromList('%PDF-1.7'.codeUnits),
      ),
    ),
  );
  await t.pumpAndSettle();
  if (startQuick &&
      find.byKey(const ValueKey('guided-quick-input')).evaluate().isEmpty) {
    await tap(t, find.text('Write or say it instead'));
  }
  if (!startQuick &&
      find.byKey(const ValueKey('guided-manual')).evaluate().isNotEmpty) {
    await tap(t, find.byKey(const ValueKey('guided-manual')));
  }
}

void main() {
  testWidgets(
    'Quick entry requires confirmation, asks for missing fields and retains typing focus',
    (t) async {
      final store = MemoryGuidedDrafts(),
          details = Details(),
          gateway = Gateway();
      await boot(
        t,
        'Leave Application',
        store,
        startQuick: true,
        details: details,
        gateway: gateway,
      );
      expect(find.byKey(const ValueKey('guided-next')), findsNothing);
      await enter(t, 'quick-input', 'I am Rina, I am ill and need leave.');
      await tap(t, find.byKey(const ValueKey('guided-arrange')));
      expect(find.text('Check the suggested details'), findsOneWidget);
      await tap(t, find.text('Cancel'));
      expect(find.byKey(const ValueKey('guided-quick-input')), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('guided-arrange')));
      await tap(t, find.text('Use these details'));
      expect(details.calls, 1);
      expect(gateway.calls, 0);
      expect(find.text('Fill in the missing details below.'), findsOneWidget);
      expect(find.byKey(const ValueKey('guided-name')), findsNothing);
      await enter(t, 'institution', 'My college');
      expect(find.byKey(const ValueKey('guided-institution')), findsOneWidget);
      await enter(t, 'recipient', 'Principal');
      await next(t);
      expect(find.byKey(const ValueKey('guided-start')), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final saved = GuidedDocument.decode(
        'Leave Application',
        await store.read('A', 'Leave Application'),
      );
      expect(saved.v('name'), 'Rina');
      expect(saved.v('institution'), 'My college');
      expect(saved.v('start'), '');
    },
  );
  testWidgets(
    'Extraction failure preserves raw input and leaves manual entry available',
    (t) async {
      final details = Details()..fails = true;
      await boot(
        t,
        'CV / Resume',
        MemoryGuidedDrafts(),
        startQuick: true,
        details: details,
      );
      await enter(t, 'quick-input', 'Keep my original details here.');
      await tap(t, find.byKey(const ValueKey('guided-arrange')));
      expect(
        find.textContaining('Could not arrange your details.'),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextFormField>(
              find.byKey(const ValueKey('guided-quick-input')),
            )
            .controller!
            .text,
        'Keep my original details here.',
      );
      await tap(t, find.byKey(const ValueKey('guided-manual')));
      expect(find.byKey(const ValueKey('guided-name')), findsOneWidget);
    },
  );
  testWidgets(
    'Late extraction after account switch never opens a review or fills another account',
    (t) async {
      String? owner = 'A';
      final details = Details()..waiting = Completer<Map<String, dynamic>>();
      final store = MemoryGuidedDrafts();
      await boot(
        t,
        'Leave Application',
        store,
        startQuick: true,
        details: details,
        owner: () => owner,
      );
      await enter(t, 'quick-input', 'I am Rina and need sick leave.');
      final button = find.byKey(const ValueKey('guided-arrange'));
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pump();
      owner = 'B';
      details.waiting!.complete(details.result);
      await t.pumpAndSettle();
      expect(find.text('Check the suggested details'), findsNothing);
      expect(await store.read('B', 'Leave Application'), isNull);
    },
  );

  for (final language in ['en', 'bn']) {
    testWidgets('Quick entry fits a small screen with large text $language', (
      t,
    ) async {
      await t.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        settingsApp(
          AppSettings(store: MemorySettingsStore(), language: language),
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: GuidedDocumentScreen(
              documentType: 'Leave Application',
              ownerId: 'A',
              store: MemoryGuidedDrafts(),
              detailsGateway: Details(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(
        t,
        find.text(
          language == 'bn'
              ? 'নিজের ভাষায় লিখব বা বলব'
              : 'Write or say it instead',
        ),
      );
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('guided-manual')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'CV goes from short fields to local preview, title edits keep the body, and saves PDF',
    (t) async {
      final store = MemoryGuidedDrafts(), gateway = Gateway(), saver = Saver();
      await boot(t, 'CV / Resume', store, gateway: gateway, saver: saver);
      await enter(t, 'name', 'Name');
      await enter(t, 'email', 'name@example.test');
      await next(t);
      await next(t);
      await enter(t, 'skills', 'Design');
      await next(t);
      expect(gateway.calls, 0);
      expect(find.text('Preview'), findsOneWidget);
      await enter(t, 'title', 'My resume');
      await tap(t, find.byKey(const ValueKey('guided-save-library')));
      expect(saver.calls, 1);
      expect(saver.name, 'My resume.pdf');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final restored = GuidedDocument.decode(
        'CV / Resume',
        await store.read('A', 'CV / Resume'),
      );
      expect(restored.preview, contains('Name'));
      expect(restored.values['skills'], 'Design');
    },
  );
  testWidgets('Start new confirms before replacing the saved form', (t) async {
    final store = MemoryGuidedDrafts();
    await boot(t, 'CV / Resume', store);
    await enter(t, 'name', 'Previous name');
    await tap(t, find.byTooltip('Document options'));
    await tap(t, find.text('Start new'));
    await tap(t, find.text('Cancel'));
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('guided-name')))
          .controller!
          .text,
      'Previous name',
    );
    await tap(t, find.byTooltip('Document options'));
    await tap(t, find.text('Start new'));
    await tap(t, find.widgetWithText(FilledButton, 'Start new'));
    if (find.byKey(const ValueKey('guided-manual')).evaluate().isNotEmpty) {
      await tap(t, find.byKey(const ValueKey('guided-manual')));
    }
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('guided-name')))
          .controller!
          .text,
      '',
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    final restored = GuidedDocument.decode(
      'CV / Resume',
      await store.read('A', 'CV / Resume'),
    );
    expect(restored.v('name'), '');
    expect(restored.step, 0);
  });
  testWidgets('Required fields stop navigation and leave typed text intact', (
    t,
  ) async {
    await boot(t, 'Job Application', MemoryGuidedDrafts());
    await enter(t, 'name', 'Applicant');
    await next(t);
    expect(find.text('Basic details'), findsOneWidget);
    expect(
      find.text('Choose the required options to continue.'),
      findsOneWidget,
    );
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('guided-name')))
          .controller!
          .text,
      'Applicant',
    );
  });
  testWidgets(
    'Job form imports CV only after confirmation and AI failure keeps all facts',
    (t) async {
      final store = MemoryGuidedDrafts(),
          cv = GuidedDocument('CV / Resume')
            ..values.addAll({
              'name': 'Saved Name',
              'email': 'a@example.test',
              'skills': 'Actual skill',
            });
      cv.education.add('Real course');
      await store.write('A', cv.type, jsonEncode(cv.toJson()));
      final gateway = Gateway()..fails = true;
      await boot(t, 'Job Application', store, gateway: gateway);
      await tap(t, find.text('Use saved CV details'));
      await tap(t, find.text('Cancel'));
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('guided-name')))
            .controller!
            .text,
        '',
      );
      await tap(t, find.text('Use saved CV details'));
      await tap(t, find.text('Use details'));
      await enter(t, 'role', 'Assistant');
      await enter(t, 'company', 'Company');
      await next(t);
      await next(t);
      await next(t);
      expect(gateway.calls, 1);
      expect(gateway.brief, contains('Actual skill'));
      expect(find.textContaining('Unable to create the draft'), findsOneWidget);
    },
  );
  testWidgets(
    'Assignment reviews an editable outline before AI and reuses the result on return',
    (t) async {
      final gateway = Gateway();
      await boot(t, 'Assignment', MemoryGuidedDrafts(), gateway: gateway);
      await enter(t, 'subject', 'Biology');
      await enter(t, 'level', 'College');
      await enter(t, 'question', 'Explain photosynthesis');
      await next(t);
      await next(t);
      expect(gateway.calls, 0);
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('guided-outline')))
            .controller!
            .text,
        contains('Introduction'),
      );
      await next(t);
      expect(gateway.calls, 1);
      await tap(t, find.text('Edit details'));
      await next(t);
      await next(t);
      await next(t);
      expect(gateway.calls, 1);
    },
  );
  testWidgets(
    'A late AI response after account change cannot enter preview or save to another owner',
    (t) async {
      String? owner = 'A';
      final gateway = Gateway()..waiting = Completer<Map<String, dynamic>>();
      final store = MemoryGuidedDrafts();
      final d = GuidedDocument('Formal Letter')
        ..step = 2
        ..values.addAll({
          'recipient': 'Manager',
          'name': 'Name',
          'subject': 'Repair',
          'message': 'Please repair the tap',
        });
      await store.write('A', d.type, jsonEncode(d.toJson()));
      await boot(t, d.type, store, gateway: gateway, owner: () => owner);
      final f = find.byKey(const ValueKey('guided-next'));
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pump();
      owner = 'B';
      gateway.waiting!.complete({'document': 'Private result'});
      await t.pumpAndSettle();
      expect(find.text('Private result'), findsNothing);
      expect(await store.read('B', d.type), isNull);
    },
  );
  for (final language in ['en', 'bn']) {
    testWidgets(
      'Invoice preview stays readable at narrow width and large font $language',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final store = MemoryGuidedDrafts();
        final d = GuidedDocument('Invoice')
          ..step = 3
          ..language = language == 'bn' ? 'Bangla' : 'English'
          ..values.addAll({
            'seller': 'Seller',
            'buyer': 'Buyer',
            'date': '2026-11-19',
          });
        d.items.single.addAll({
          'name': 'Service',
          'quantity': '2',
          'rate': '10',
        });
        d.preview = d.localContent;
        await store.write('A', d.type, jsonEncode(d.toJson()));
        await t.pumpWidget(
          settingsApp(
            AppSettings(store: MemorySettingsStore(), language: language),
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: GuidedDocumentScreen(
                documentType: d.type,
                ownerId: 'A',
                store: store,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
