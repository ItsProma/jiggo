import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/main.dart';
import 'package:jiggo/screens/login_screen.dart';
import 'package:jiggo/screens/notifications_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/notification_controller.dart';
import 'package:jiggo/services/notification_models.dart';
import 'package:jiggo/services/notification_preferences.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';
import 'support/notification_fakes.dart';

class Fixture {
  final store = MemorySettingsStore();
  final driver = FakeNotificationDriver();
  final registry = FakeNotificationRegistry();
  String? uid = 'user-1';
  late final controller = NotificationController(
    store: store,
    driver: driver,
    registry: registry,
    currentUid: () => uid,
  );
  Future<void> start() async {
    await controller.initialize();
    await controller.bindAccount(uid, 'en');
  }

  int get revision => NotificationPreferences.decode(store.value).revision;
  JiggoNotice notice({String id = 'one', String? owner, int? rev}) =>
      JiggoNotice(
        id: id,
        ownerUid: owner ?? uid!,
        title: 'Jiggo',
        body: 'Test',
        target: 'library',
        sentAt: DateTime.now(),
        revision: rev ?? revision,
      );
}

void main() {
  test('Inbox persists read state, reopens while disabled, and deletion survives restart', () async {
    final f=Fixture();await f.start();await f.controller.enable();f.driver.receive(f.notice());
    f.controller.markAllRead();await f.controller.flushInbox();
    final restarted=NotificationController(store:f.store,driver:FakeNotificationDriver(),registry:f.registry,currentUid:()=>f.uid);
    await restarted.initialize();await restarted.bindAccount(f.uid,'en');
    expect(restarted.notices,hasLength(1));expect(restarted.isRead('one'),isTrue);
    await restarted.disable();restarted.openSaved(restarted.notices.single);expect(restarted.pendingOpen?.target,'library');
    restarted.consumeOpen();restarted.openSaved(restarted.notices.single);expect(restarted.pendingOpen?.target,'library');
    restarted.removeNotice('one');await restarted.flushInbox();
    expect(NotificationPreferences.decode(f.store.value).history,isEmpty);
    restarted.dispose();f.controller.dispose();
  });
  test('Notification history keeps recent days without accepting stale push payloads', () {
    final f=Fixture();final older=JiggoNotice(id:'old',ownerUid:f.uid!,title:'Older update',body:'',target:'library',sentAt:DateTime.now().subtract(const Duration(days:3)));
    expect(JiggoNotice.fromData(older.data),isNull);
    final prefs=NotificationPreferences.empty().copy(ownerUid:f.uid,history:[older],readIds:{'old'});
    expect(NotificationPreferences.decode(prefs.encode()).history.single.id,'old');
    expect(NotificationPreferences.decode(prefs.copy(ownerUid:'other').encode()).history,isEmpty);
  });

  test('Later followed by logout never contacts the push registry', () async {
    final f = Fixture();
    await f.start();
    await f.controller.later();
    await f.controller.detachBeforeSignOut();
    expect(f.registry.registrations, isEmpty);
    expect(f.registry.removals, isEmpty);
    expect(f.driver.registrations, 0);
    expect(f.driver.unregisters, 0);
  });
  test(
    'Startup does not request permission, register, or contact the server',
    () async {
      final f = Fixture();
      await f.start();
      expect(f.driver.requests, 0);
      expect(f.driver.registrations, 0);
      expect(f.registry.registrations, isEmpty);
    },
  );
  test('Later is persisted without a permission request', () async {
    final f = Fixture();
    await f.start();
    await f.controller.later();
    expect(f.controller.prompted, isTrue);
    expect(f.controller.enabled, isFalse);
    final reopened = NotificationController(
      store: f.store,
      driver: FakeNotificationDriver(),
      registry: f.registry,
      currentUid: () => f.uid,
    );
    await reopened.initialize();
    expect(reopened.prompted, isTrue);
    expect(reopened.enabled, isFalse);
    expect(f.driver.requests, 0);
  });
  test(
    'Denied permission completes the optional prompt without registration',
    () async {
      final f = Fixture();
      f.driver.requestedStatus = NoticePermission.denied;
      await f.start();
      await f.controller.enable();
      expect(f.controller.prompted, isTrue);
      expect(f.controller.enabled, isFalse);
      expect(f.registry.registrations, isEmpty);
    },
  );
  test(
    'Consent registers only the current account and chosen language',
    () async {
      final f = Fixture();
      await f.start();
      f.controller.updateLanguage('bn');
      await f.controller.enable();
      expect(f.controller.registered, isTrue);
      expect(f.registry.registrations.last['uid'], 'user-1');
      expect(f.registry.registrations.last['language'], 'bn');
      expect(f.registry.registrations.last['revision'], f.revision);
    },
  );
  test(
    'Web without VAPID supports a local test without claiming remote readiness',
    () async {
      final f = Fixture();
      f.driver.isWeb = true;
      f.driver.configured = false;
      await f.start();
      await f.controller.enable();
      await f.controller.testDevice(title: 'Jiggo', body: 'Test');
      expect(f.driver.shown.single.target, 'library');
      expect(f.controller.registered, isFalse);
      expect(f.registry.registrations, isEmpty);
    },
  );
  test('Remote failure keeps optional device notifications usable', () async {
    final f = Fixture();
    f.registry.error = StateError('Offline');
    await f.start();
    await f.controller.enable();
    expect(f.controller.enabled, isTrue);
    expect(f.controller.registered, isFalse);
    expect(f.controller.error, isNotNull);
    await f.controller.testDevice(title: 'Jiggo', body: 'Test');
    expect(f.driver.shown, hasLength(1));
  });
  test(
    'Duplicate and other-account foreground notices are not displayed',
    () async {
      final f = Fixture();
      await f.start();
      await f.controller.enable();
      f.driver.receive(f.notice(owner: 'someone-else'));
      f.driver.receive(f.notice());
      f.driver.receive(f.notice());
      await Future<void>.delayed(Duration.zero);
      expect(f.driver.shown, hasLength(1));
      expect(f.controller.notices, hasLength(1));
    },
  );
  test('Opt-out rejects already queued notifications and invalidates the server registration', () async {
    final f = Fixture();
    await f.start();
    await f.controller.enable();
    final old = f.notice();
    await f.controller.disable();
    f.driver.receive(old);
    f.driver.opened(old);
    expect(f.driver.shown, isEmpty);
    expect(f.controller.pendingOpen, isNull);
    expect(f.registry.removals.last['revision'], greaterThan(old.revision));
    expect(f.driver.unregisters, greaterThan(0));
  });
  test('Re-enabling does not accept notices from before opt-out', () async {
    final f = Fixture();
    await f.start();
    await f.controller.enable();
    final old = f.notice();
    await f.controller.disable();
    await f.controller.enable();
    f.driver.receive(old);
    f.driver.opened(old);
    expect(f.driver.shown, isEmpty);
    expect(f.controller.pendingOpen, isNull);
  });
  test('An in-flight registration cannot reconnect after opt-out', () async {
    final f = Fixture();
    await f.start();
    f.driver.registrationWait = Completer<String?>();
    final enabling = f.controller.enable();
    await Future<void>.delayed(Duration.zero);
    // Authentication can change even while an OS permission/token request is pending.
    f.uid = null;
    await f.controller.detachBeforeSignOut();
    f.driver.registrationWait!.complete('cExampleInstallation12');
    await enabling;
    expect(f.registry.registrations, isEmpty);
    expect(f.controller.registered, isFalse);
  });
  test(
    'Sign-out fences background display and clears session notices',
    () async {
      final f = Fixture();
      await f.start();
      await f.controller.enable();
      f.driver.receive(f.notice());
      await f.controller.detachBeforeSignOut();
      expect(NotificationPreferences.decode(f.store.value).ownerUid, isNull);
      expect(f.controller.notices, isEmpty);
      expect(f.controller.pendingOpen, isNull);
      expect(f.driver.accounts.last.$1, isNull);
      expect(f.driver.accounts.last.$2, isFalse);
    },
  );
  test(
    'Clicking a current-account notice preserves the allowed destination',
    () async {
      final f = Fixture();
      await f.start();
      await f.controller.enable();
      f.driver.opened(f.notice());
      expect(f.controller.pendingOpen?.target, 'library');
      f.controller.consumeOpen();
      expect(f.controller.pendingOpen, isNull);
      f.driver.opened(f.notice(owner: 'other'));
      expect(f.controller.pendingOpen, isNull);
    },
  );
  test('Malformed, external-link, stale, future, and oversized payloads are rejected', () {
    final f = Fixture();
    final valid = f.notice().data;
    expect(JiggoNotice.fromData(valid), isNotNull);
    for (final data in [
      {...valid, 'target': 'https://example.org'},
      {...valid, 'ownerUid': ''},
      {...valid, 'title': 'x' * 121},
      {...valid, 'revision': '-1'},
      {...valid, 'sentAt': '0'},
      {
        ...valid,
        'sentAt':
            '${DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch}',
      },
    ]) {
      expect(JiggoNotice.fromData(data), isNull);
    }
    expect(JiggoNotice.decode('not-json'), isNull);
    expect(JiggoNotice.decode('x' * 6001), isNull);
  });
  test('A storage failure cannot silently enable registration', () async {
    final f = Fixture();
    await f.start();
    f.store.failWrites = true;
    await f.controller.enable();
    expect(f.controller.enabled, isFalse);
    expect(f.controller.prompted, isTrue);
    expect(f.registry.registrations, isEmpty);
    expect(f.controller.error, isNotNull);
  });
  test('An offline opt-out retries its server revocation on refresh', () async {
    final f = Fixture();
    await f.start();
    await f.controller.enable();
    f.registry.error = StateError('Offline');
    await f.controller.disable();
    expect(
      NotificationPreferences.decode(f.store.value).cleanupPending,
      isTrue,
    );
    f.registry.error = null;
    await f.controller.refresh();
    expect(f.registry.removals, hasLength(1));
    expect(
      NotificationPreferences.decode(f.store.value).cleanupPending,
      isFalse,
    );
    expect(f.controller.enabled, isFalse);
  });
  test(
    'Permission revoked outside Jiggo unregisters the device on refresh',
    () async {
      final f = Fixture();
      await f.start();
      await f.controller.enable();
      f.driver.status = NoticePermission.denied;
      await f.controller.refresh();
      expect(f.controller.enabled, isFalse);
      expect(f.registry.removals, hasLength(1));
    },
  );
  testWidgets(
    'Bangla notification settings fit a narrow screen at large font',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = Fixture();
      await f.start();
      final settings = AppSettings(
        store: MemorySettingsStore(),
        language: 'bn',
        themeMode: ThemeMode.dark,
      );
      await tester.pumpWidget(
        NotificationScope(
          controller: f.controller,
          child: settingsApp(
            settings,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: const NotificationsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('এখনো কোনো নোটিফিকেশন নেই'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Language choice is followed by optional notification choice, then login',
    (tester) async {
      final f = Fixture();
      f.uid = null;
      final settings = AppSettings(store: MemorySettingsStore());
      await tester.pumpWidget(
        JiggoApp(
          settings: settings,
          notifications: f.controller,
          authStateChanges: Stream<User?>.value(null),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('বাংলা'));
      await tester.pump();
      await tester.tap(find.text('এগিয়ে যাও / Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationPermissionScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      await tester.tap(find.text('পরে'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(f.driver.requests, 0);
      expect(settings.locale, const Locale('bn'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Inbox hides setup and developer tests, settings show a simple permission switch',
    (tester) async {
      final f = Fixture();
      f.driver.isWeb = true;
      f.driver.configured = false;
      await f.start();
      await f.controller.enable();
      await tester.pumpWidget(
        NotificationScope(
          controller: f.controller,
          child: settingsApp(
            AppSettings(store: MemorySettingsStore(), language: 'en'),
            const NotificationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('public Firebase web-push key'), findsNothing);
      expect(find.text('Show device test'), findsNothing);
      expect(find.text('Send push test'), findsNothing);
      expect(find.text('No notifications yet'), findsOneWidget);
      await tester.tap(find.byTooltip('Notification settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('On for this device'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
