import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/ai_document_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/app_strings.dart';
import 'package:jiggo/services/document_brief.dart';
import 'package:jiggo/services/document_speech.dart';
import 'package:jiggo/widgets/document_details_dialog.dart';
import 'package:jiggo/widgets/document_voice_dialog.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

class FakeDocumentSpeech implements DocumentSpeech {
  bool available = true;
  List<String> languages = ['bn_BD', 'en_US'];
  Completer<bool>? permission;
  int starts = 0;
  int cancellations = 0;
  String? locale;
  void Function(String)? text;
  void Function(bool)? status;
  void Function()? error;

  @override
  Future<bool> initialize() async {
    if (permission != null) return permission!.future;
    return available;
  }

  @override
  Future<List<String>> locales() async => languages;
  @override
  Future<void> listen({
    required String locale,
    required void Function(String) onText,
    required void Function(bool) onListening,
    required void Function() onError,
  }) async {
    starts++;
    this.locale = locale;
    text = onText;
    status = onListening;
    error = onError;
    onListening(true);
  }

  @override
  Future<void> stop() async => status?.call(false);
  @override
  Future<void> cancel() async => cancellations++;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;

Future<void> openMaker(
  WidgetTester tester, {
  String type = 'Custom AI Document',
  String language = 'en',
  FakeDocumentSpeech? speech,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? generator,
  Future<void> Function({required String title, required String content})? pdf,
}) async {
  await tester.binding.setSurfaceSize(const Size(700, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    settingsApp(
      AppSettings(store: MemorySettingsStore(), language: language),
      AiDocumentScreen(
        documentType: type,
        speech: speech,
        generator:
            generator ??
            (_) async => {'document': 'A draft', 'savedToLibrary': false},
        pdfExporter: pdf,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Brief preserves real user details and does not add example facts', () {
    const brief = DocumentBrief('Leave Application');
    final input = 'Need leave for my family event.';
    final text = brief.compose(input, {'dates': '10–12 January 2027'});
    expect(text, contains(input));
    expect(text, contains('10–12 January 2027'));
    expect(text, isNot(contains('December 2026')));
    expect(brief.compose('x' * 2000, {}), 'x' * 2000);
    expect(
      brief.compose('x' * 2000, {'dates': 'Tomorrow'}).length,
      greaterThan(2000),
    );
  });

  test(
    'Short category drafts use placeholders and all guides are localized',
    () {
      for (final type in [
        'CV / Resume',
        'Job Application',
        'Leave Application',
        'Formal Letter',
        'Invoice',
        'Assignment',
        'Custom AI Document',
      ]) {
        final brief = DocumentBrief(type);
        expect(brief.compose('', {}), contains('editable placeholders'));
        expect(brief.questionsFor('').length, lessThanOrEqualTo(3));
        expect(brief.title('Bangla'), isNot(brief.title('English')));
        for (final message in [
          brief.example,
          ...brief.questions.expand((q) => [q.label, q.hint]),
        ]) {
          expect(
            AppStrings.text(message, 'bn'),
            isNot(message),
            reason: message,
          );
        }
      }
    },
  );

  testWidgets(
    'Automatic title follows output language, manual title is preserved',
    (tester) async {
      await openMaker(tester, type: 'Leave Application', language: 'bn');
      expect(fieldText(tester, 'document-title'), 'ছুটির আবেদন');
      Future<void> choose(String label) async {
        await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await choose('ইংরেজি');
      expect(fieldText(tester, 'document-title'), 'Leave Application');
      await tester.enterText(
        find.byKey(const ValueKey('document-title')),
        'My own title',
      );
      await choose('বাংলা');
      expect(fieldText(tester, 'document-title'), 'My own title');
    },
  );

  testWidgets(
    'Cancel questions makes no paid request; missing private data can stay blank',
    (tester) async {
      var calls = 0;
      Map<String, dynamic>? sent;
      await openMaker(
        tester,
        type: 'CV / Resume',
        generator: (payload) async {
          calls++;
          sent = payload;
          return {'document': 'Resume draft', 'savedToLibrary': false};
        },
      );
      await tapVisible(tester, find.text('Generate with AI'));
      expect(find.byType(DocumentDetailsDialog), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tapVisible(tester, find.text('Generate with AI'));
      await tester.tap(find.byKey(const ValueKey('confirm-document-details')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(sent?['instructions'], contains('editable placeholders'));
      expect(sent?['documentType'], 'CV / Resume');
      expect(
        find.textContaining('Library saving could not be confirmed'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Custom document asks for purpose; example never becomes user content',
    (tester) async {
      Map<String, dynamic>? sent;
      await openMaker(
        tester,
        generator: (p) async {
          sent = p;
          return {'document': 'My study plan', 'savedToLibrary': false};
        },
      );
      await tapVisible(tester, find.byKey(const ValueKey('document-example')));
      expect(fieldText(tester, 'document-details'), isEmpty);
      await tapVisible(tester, find.text('Generate with AI'));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('confirm-document-details')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('brief-purpose')),
        'Make a weekly study plan.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-document-details')));
      await tester.pumpAndSettle();
      expect(sent?['instructions'], contains('Make a weekly study plan.'));
      expect(sent?['instructions'], isNot(contains('one hour each evening')));
    },
  );

  testWidgets(
    'Combined brief limit blocks overflow without truncating user answers',
    (tester) async {
      var calls = 0;
      await openMaker(
        tester,
        type: 'Leave Application',
        generator: (_) async {
          calls++;
          return {};
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('document-details')),
        'x' * 1950,
      );
      await tapVisible(tester, find.text('Generate with AI'));
      await tester.enterText(
        find.byKey(const ValueKey('brief-dates')),
        'D' * 100,
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('confirm-document-details')),
            )
            .onPressed,
        isNull,
      );
      expect(fieldText(tester, 'brief-dates'), 'D' * 100);
      expect(calls, 0);
      await tester.enterText(find.byKey(const ValueKey('brief-dates')), '');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('confirm-document-details')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'Retry retains answers, busy prevents duplicates, PDF uses generated snapshot',
    (tester) async {
      final waiting = Completer<Map<String, dynamic>>();
      var calls = 0;
      String? exportedTitle;
      String? exportedContent;
      await openMaker(
        tester,
        type: 'Leave Application',
        generator: (p) async {
          calls++;
          if (calls == 1) throw StateError('Offline');
          expect(p['instructions'], contains('5 January 2027'));
          return waiting.future;
        },
        pdf: ({required title, required content}) async {
          exportedTitle = title;
          exportedContent = content;
        },
      );
      await tapVisible(tester, find.text('Generate with AI'));
      await tester.enterText(
        find.byKey(const ValueKey('brief-dates')),
        '5 January 2027',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-document-details')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      final generate = find.ancestor(
        of: find.text('Generate with AI'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pump();
      expect(find.byType(DocumentDetailsDialog), findsNothing);
      expect(tester.widget<FilledButton>(generate).onPressed, isNull);
      expect(calls, 2);
      waiting.complete({
        'document': 'Leave draft result',
        'title': 'Saved generated title',
        'language': 'English',
        'savedToLibrary': false,
      });
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('document-title')),
        'Next document title',
      );
      await tapVisible(tester, find.text('Download PDF'));
      expect(exportedTitle, 'Saved generated title');
      expect(exportedContent, 'Leave draft result');
    },
  );

  testWidgets(
    'Voice preview replaces partial results, preserves manual corrections, appends on consent',
    (tester) async {
      final speech = FakeDocumentSpeech();
      await openMaker(tester, speech: speech);
      await tester.enterText(
        find.byKey(const ValueKey('document-details')),
        'Existing details',
      );
      await tapVisible(tester, find.byKey(const ValueKey('document-voice')));
      expect(speech.starts, 0);
      await tester.tap(find.byKey(const ValueKey('voice-start-stop')));
      await tester.pumpAndSettle();
      speech.text!('My');
      speech.text!('My new details');
      await tester.pump();
      expect(fieldText(tester, 'voice-transcript'), 'My new details');
      await tester.tap(find.byKey(const ValueKey('voice-start-stop')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('voice-transcript')),
        'Corrected details',
      );
      speech.text!('Late result must not overwrite');
      await tester.pump();
      expect(fieldText(tester, 'voice-transcript'), 'Corrected details');
      await tester.tap(find.byKey(const ValueKey('voice-use-text')));
      await tester.pumpAndSettle();
      expect(
        fieldText(tester, 'document-details'),
        'Existing details\nCorrected details',
      );
      expect(speech.cancellations, greaterThan(0));
    },
  );

  testWidgets(
    'Denied voice and cancelled permission request preserve typed data',
    (tester) async {
      final speech = FakeDocumentSpeech()..available = false;
      await openMaker(tester, speech: speech);
      await tester.enterText(
        find.byKey(const ValueKey('document-details')),
        'Keep these details',
      );
      await tapVisible(tester, find.byKey(const ValueKey('document-voice')));
      await tester.tap(find.byKey(const ValueKey('voice-start-stop')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('microphone permission was denied'),
        findsOneWidget,
      );
      expect(speech.starts, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'document-details'), 'Keep these details');
      speech.permission = Completer<bool>();
      await tapVisible(tester, find.byKey(const ValueKey('document-voice')));
      await tester.tap(find.byKey(const ValueKey('voice-start-stop')));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      speech.permission!.complete(true);
      await tester.pumpAndSettle();
      expect(speech.starts, 0);
      expect(fieldText(tester, 'document-details'), 'Keep these details');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Speech language fallback, restart and background pause stop capture',
    (tester) async {
      final speech = FakeDocumentSpeech()..languages = ['bn_IN'];
      await openMaker(tester, speech: speech, language: 'bn');
      await tapVisible(tester, find.byKey(const ValueKey('document-voice')));
      await tester.tap(find.byKey(const ValueKey('voice-start-stop')));
      await tester.pumpAndSettle();
      expect(speech.locale, 'bn_IN');
      speech.text!('আমার তথ্য');
      speech.status!(false);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-start-stop')));
      await tester.pumpAndSettle();
      speech.text!('আরও তথ্য');
      await tester.pump();
      expect(fieldText(tester, 'voice-transcript'), 'আমার তথ্য\nআরও তথ্য');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      speech.text!('Background late result');
      await tester.pump();
      expect(fieldText(tester, 'voice-transcript'), 'আমার তথ্য\nআরও তথ্য');
      expect(speech.cancellations, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets(
    'Long Bangla input is preserved and rejected before a paid request',
    (tester) async {
      var calls = 0;
      await openMaker(
        tester,
        generator: (_) async {
          calls++;
          return {};
        },
      );
      final details = 'কি' * 1001;
      await tester.enterText(
        find.byKey(const ValueKey('document-details')),
        details,
      );
      expect(fieldText(tester, 'document-details'), details);
      await tapVisible(tester, find.text('Generate with AI'));
      expect(calls, 0);
      expect(find.text('Use 2000 characters or fewer'), findsOneWidget);
    },
  );

  testWidgets(
    'Overlong speech stays editable and cannot overflow the existing brief',
    (tester) async {
      final speech = FakeDocumentSpeech();
      await openMaker(tester, speech: speech);
      final existing = 'a' * 1995;
      await tester.enterText(
        find.byKey(const ValueKey('document-details')),
        existing,
      );
      await tapVisible(tester, find.byKey(const ValueKey('document-voice')));
      await tester.tap(find.byKey(const ValueKey('voice-start-stop')));
      await tester.pumpAndSettle();
      speech.text!('Too long to add');
      speech.status!(false);
      await tester.pump();
      expect(fieldText(tester, 'voice-transcript'), 'Too long to add');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('voice-use-text')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('voice-transcript')),
        'OK',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-use-text')));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'document-details'), '$existing\nOK');
    },
  );

  for (final language in ['en', 'bn']) {
    testWidgets(
      'Document form and dialogs fit 320px with large text and keyboard: $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final settings = AppSettings(
          store: MemorySettingsStore(),
          language: language,
          themeMode: ThemeMode.dark,
        );
        await tester.pumpWidget(
          settingsApp(
            settings,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 200),
                ),
                child: const AiDocumentScreen(documentType: 'Invoice'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final dialog in <Widget>[
          DocumentDetailsDialog(
            brief: const DocumentBrief('Invoice'),
            details: '',
            answers: const {},
            questions: const DocumentBrief('Invoice').questions,
          ),
          DocumentVoiceDialog(
            speech: FakeDocumentSpeech(),
            initialLanguage: language,
            maxCharacters: 2000,
          ),
        ]) {
          await tester.pumpWidget(
            settingsApp(
              settings,
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                    viewInsets: const EdgeInsets.only(bottom: 200),
                  ),
                  child: Scaffold(body: dialog),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
