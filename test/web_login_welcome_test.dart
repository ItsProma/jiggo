import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/widgets/web_login_welcome.dart';
import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

void main() {
  for (final language in ['en', 'bn']) {
    for (final width in [320.0, 390.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('Web welcome fits $width, $language, scale $scale', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final settings = AppSettings(store: MemorySettingsStore(), language: language);
          var google = 0, email = 0, guest = 0, privacy = 0;
          await tester.pumpWidget(settingsApp(settings, Builder(builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: WebLoginWelcome(
              showGuest: true, busy: false,
              onGoogle: () => google++, onEmail: () => email++,
              onGuest: () => guest++, onPrivacy: () => privacy++,
            )),
          ))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final key in ['welcome-google', 'welcome-email', 'welcome-guest']) {
            final target = find.byKey(ValueKey(key));
            await tester.ensureVisible(target);
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          expect([google, email, guest], [1, 1, 1]);
          final policy = find.byType(TextButton).last;
          await tester.ensureVisible(policy);
          await tester.tap(policy);
          expect(privacy, 1);
        });
      }
    }
  }
  testWidgets('Busy sign-in disables duplicate actions and guest can be hidden', (tester) async {
    final settings = AppSettings(store: MemorySettingsStore(), language: 'en');
    await tester.pumpWidget(settingsApp(settings, Scaffold(body: WebLoginWelcome(
      showGuest: false, busy: true, error: 'Unable to check login status.',
      onGoogle: () => fail('busy Google'), onEmail: () => fail('busy email'),
      onGuest: () => fail('guest hidden'), onPrivacy: () {},
    ))));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('welcome-google'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('welcome-email'))).onPressed, isNull);
    expect(find.byKey(const ValueKey('welcome-guest')), findsNothing);
    expect(find.text('Unable to check login status.'), findsOneWidget);
  });
}
