import 'support/notification_fakes.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/main.dart';
import 'package:jiggo/screens/ai_document_screen.dart';
import 'package:jiggo/screens/app_preferences_screen.dart';
import 'package:jiggo/screens/login_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/app_strings.dart';
import 'package:jiggo/services/app_theme.dart';
import 'package:jiggo/widgets/home_tools.dart';
import 'package:jiggo/widgets/home_overview.dart';

import 'support/memory_settings_store.dart';

Widget settingsApp(AppSettings settings, Widget home) => AppSettingsScope(
  settings: settings,
  child: AnimatedBuilder(
    animation: settings,
    builder: (context, _) => MaterialApp(
      locale: settings.locale,
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      theme: jiggoTheme(Brightness.light),
      darkTheme: jiggoTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: home,
    ),
  ),
);

void main() {
  test('Fresh install requires language and defaults to light', () async {
    final settings = AppSettings(store: MemorySettingsStore());
    await settings.load();
    expect(settings.hasLanguage, isFalse);
    expect(settings.themeMode, ThemeMode.light);
  });

  test('Language and appearance survive a cold settings instance', () async {
    final store = MemorySettingsStore();
    final first = AppSettings(store: store);
    await first.setLanguage('bn');
    await first.setThemeMode(ThemeMode.dark);
    final reopened = AppSettings(store: store);
    await reopened.load();
    expect(reopened.locale, const Locale('bn'));
    expect(reopened.themeMode, ThemeMode.dark);
    await reopened.setThemeMode(ThemeMode.system);
    final again = AppSettings(store: store);
    await again.load();
    expect(again.locale, const Locale('bn'));
    expect(again.themeMode, ThemeMode.system);
  });

  test('Failed persistence leaves the previous preference intact', () async {
    final store = MemorySettingsStore();
    final settings = AppSettings(store: store);
    await settings.setLanguage('en');
    store.failWrites = true;
    await expectLater(settings.setLanguage('bn'), throwsStateError);
    expect(settings.locale, const Locale('en'));
    expect(settings.saving, isFalse);
    final reopened = AppSettings(store: store);
    await reopened.load();
    expect(reopened.locale, const Locale('en'));
  });

  test(
    'Malformed and unsupported saved values fail back to language choice',
    () async {
      for (final value in [
        'bad json',
        '[]',
        '{"language":"xx","theme":"invalid"}',
      ]) {
        final settings = AppSettings(store: MemorySettingsStore(value));
        await settings.load();
        expect(settings.hasLanguage, isFalse);
        expect(settings.themeMode, ThemeMode.light);
      }
    },
  );

  testWidgets('First launch saves Bangla before showing login', (tester) async {
    final settings = AppSettings(store: MemorySettingsStore());
    await tester.pumpWidget(
      JiggoApp(
        notifications: skippedNotifications(),
        settings: settings,
        authStateChanges: Stream<User?>.value(null),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LanguageSelectionScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('বাংলা'));
    await tester.pump();
    await tester.tap(find.text('এগিয়ে যাও / Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguageSelectionScreen), findsNothing);
    expect(find.text('গেস্ট হিসেবে শুরু করো'), findsOneWidget);
    expect(settings.locale, const Locale('bn'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Failed first choice stays on onboarding and permits retry', (
    tester,
  ) async {
    final store = MemorySettingsStore()..failWrites = true;
    final settings = AppSettings(store: store);
    await tester.pumpWidget(
      JiggoApp(
        notifications: skippedNotifications(),
        settings: settings,
        authStateChanges: Stream<User?>.value(null),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.tap(find.text('এগিয়ে যাও / Continue'));
    await tester.pumpAndSettle();
    expect(settings.hasLanguage, isFalse);
    expect(find.textContaining('Could not save.'), findsOneWidget);
    store.failWrites = false;
    await tester.tap(find.text('এগিয়ে যাও / Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Continue as Guest'), findsOneWidget);
  });

  testWidgets('Changing language keeps the preferences route open', (
    tester,
  ) async {
    final settings = AppSettings(store: MemorySettingsStore(), language: 'en');
    await tester.pumpWidget(
      settingsApp(
        settings,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AppPreferencesScreen(
                    section: PreferenceSection.language,
                  ),
                ),
              ),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();
    expect(find.byType(AppPreferencesScreen), findsOneWidget);
    expect(find.text('ভাষা'), findsOneWidget);
    final navigator = Navigator.of(
      tester.element(find.byType(AppPreferencesScreen)),
    );
    expect(navigator.canPop(), isTrue);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Light overrides system; System follows brightness changes', (
    tester,
  ) async {
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    final settings = AppSettings(store: MemorySettingsStore(), language: 'en');
    await tester.pumpWidget(
      settingsApp(
        settings,
        const AppPreferencesScreen(section: PreferenceSection.appearance),
      ),
    );
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(AppPreferencesScreen))).brightness;
    expect(brightness(), Brightness.light);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'bn']) {
    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 390.0, 768.0]) {
        testWidgets('Two tool columns, $language, width $width, scale $scale', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final settings = AppSettings(
            store: MemorySettingsStore(),
            language: language,
            themeMode: ThemeMode.dark,
          );
          HomeTool? selected;
          await tester.pumpWidget(
            settingsApp(
              settings,
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: HomeTools(onSelected: (tool) => selected = tool),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final first = tester.getRect(
            find.byKey(const ValueKey(HomeTool.fileEditor)),
          );
          final second = tester.getRect(
            find.byKey(const ValueKey(HomeTool.scanSolve)),
          );
          final third = tester.getRect(
            find.byKey(const ValueKey(HomeTool.documentMaker)),
          );
          final fourth = tester.getRect(
            find.byKey(const ValueKey(HomeTool.pdfScanner)),
          );
          expect(first.top, second.top);
          expect(second.left, greaterThan(first.left));
          expect(third.top, fourth.top);
          expect(third.top, greaterThanOrEqualTo(first.bottom));
          expect(fourth.right, lessThanOrEqualTo(width - 15));
          await tester.tap(find.byKey(const ValueKey(HomeTool.scanSolve)));
          expect(selected, HomeTool.scanSolve);
          expect(find.text('Translate'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'Bangla UI preserves English document type, language and content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Map<String, dynamic>? sent;
      final settings = AppSettings(
        store: MemorySettingsStore(),
        language: 'bn',
      );
      await tester.pumpWidget(
        settingsApp(
          settings,
          AiDocumentScreen(
            documentType: 'CV / Resume',
            generator: (payload) async {
              sent = payload;
              return {
                'title': payload['title'],
                'document': 'Home',
                'language': payload['language'],
                'savedToLibrary': false,
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('সিভি / জীবনবৃত্তান্ত'), findsOneWidget);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'My Resume');
      await tester.enterText(
        fields.at(1),
        'Create a resume for an experienced designer.',
      );
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ইংরেজি').last);
      await tester.pumpAndSettle();
      final generate = find.text('এআই দিয়ে তৈরি করো');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-document-details')));
      await tester.pumpAndSettle();
      expect(sent?['documentType'], 'CV / Resume');
      expect(sent?['language'], 'English');
      expect(sent?['title'], 'My Resume');
      expect(find.text('My Resume'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['en', 'bn']) {
    for (final keyboard in [false, true]) {
      testWidgets(
        'Home scrolls to the last tool, $language, keyboard $keyboard',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          final settings = AppSettings(
            store: MemorySettingsStore(),
            language: language,
          );
          var openedLibrary = false;
          await tester.pumpWidget(
            settingsApp(
              settings,
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                    viewInsets: EdgeInsets.only(bottom: keyboard ? 280 : 0),
                  ),
                  child: Scaffold(
                    body: HomeOverview(
                      promptController: controller,
                      onToolSelected: (_) {},
                      onUnavailable: (_) {},
                      onOpenLibrary: () => openedLibrary = true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey(HomeTool.pdfScanner)),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final library = find.text(AppStrings.text('My Documents', language));
          await tester.scrollUntilVisible(
            library,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(library);
          expect(openedLibrary, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets('Login labels fit a narrow screen with large $language text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
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
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: const LoginScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text(AppStrings.text('Continue with Google', language)),
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('Rate limits and safety helpers have Bangla app messages', () {
    expect(
      AppStrings.text(
        'Please wait about 17 seconds before sending another AI request.',
        'bn',
      ),
      contains('17 সেকেন্ড'),
    );
    expect(
      AppStrings.text('Remaining scans today: {count}', 'bn', {'count': 3}),
      contains('3'),
    );
  });
}
