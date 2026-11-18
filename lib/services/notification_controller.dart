import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'notification_models.dart';
import 'notification_preferences.dart';

class NotificationController extends ChangeNotifier {
  final SettingsStore store;
  final NotificationDriver driver;
  final NotificationRegistry registry;
  final String? Function() currentUid;
  final List<JiggoNotice> _notices = [];
  NotificationPreferences _preferences = NotificationPreferences.empty();
  NoticePermission permission = NoticePermission.notAsked;
  bool ready = false;
  bool busy = false;
  bool registered = false;
  String? error;
  JiggoNotice? pendingOpen;
  JiggoNotice? foregroundNotice;
  String _language = 'en';
  String? _account;
  int _session = 0;
  bool _disposed = false;
  Future<void> _accountWork = Future<void>.value();

  NotificationController({
    required this.store,
    required this.driver,
    required this.registry,
    required this.currentUid,
  });

  bool get prompted => _preferences.prompted;
  bool get enabled => _preferences.enabled;
  bool get supported => permission != NoticePermission.unsupported;
  bool get web => driver.web;
  bool get pushConfigured => driver.pushConfigured;
  List<JiggoNotice> get notices => List.unmodifiable(_notices);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      _preferences = NotificationPreferences.decode(
        await store.read().timeout(const Duration(seconds: 3)),
      );
      _account = _preferences.ownerUid;
      await driver
          .initialize(
            onMessage: _receive,
            onOpen: open,
            onRegistrationChanged: () {
              registered = false;
              _queueConnect();
            },
          )
          .timeout(const Duration(seconds: 5));
      permission = await driver.permission().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      // Optional notifications must never stop account access.
      error =
          'Notification settings could not be loaded. You can still use Jiggo.';
      permission = NoticePermission.unsupported;
    }
    ready = true;
    _changed();
  }

  String _message(Object failure) {
    if (failure is FirebaseFunctionsException) {
      return switch (failure.code) {
        'not-found' || 'unimplemented' => 'Remote notifications need server setup. Device notifications can still be tested.',
        'unauthenticated' || 'permission-denied' => 'Notification registration failed verification. Reopen Jiggo and try again.',
        'resource-exhausted' =>
          'Too many notification requests. Please try again later.',
        'failed-precondition' =>
          'This account or device is not ready for remote notifications.',
        _ => 'Remote notifications could not connect. Check your internet and retry.',
      };
    }
    return 'Notification action failed. Check permission and try again.';
  }

  Future<void> _persist() => store.write(_preferences.encode());

  Future<void> later() async {
    _preferences = _preferences.copy(
      prompted: true,
      enabled: false,
      ownerUid: currentUid(),
      revision: _preferences.revision + 1,
    );
    try {
      await _persist();
    } catch (_) {
      error = 'Your notification choice could not be saved. You can still continue.';
    }
    _changed();
  }

  Future<void> enable() async {
    if (busy) return;
    ++_session;
    busy = true;
    error = null;
    _changed();
    try {
      // Keep the permission request directly inside the user's button gesture.
      permission = await driver.requestPermission();
      _preferences = _preferences.copy(
        prompted: true,
        enabled: permission == NoticePermission.granted,
        ownerUid: currentUid(),
        revision: _preferences.revision + 1,
      );
      try {
        await _persist();
      } catch (_) {
        _preferences = _preferences.copy(
          enabled: false,
          ownerUid: currentUid(),
        );
        error = 'Your notification choice could not be saved. You can still continue.';
        return;
      }
      _changed();
      await driver.updateAccount(currentUid(), enabled, _preferences.revision);
      if (enabled) await _connect(_session);
    } catch (failure) {
      error = _message(failure);
      // A permission or connection error is not a login gate.
      _preferences = _preferences.copy(prompted: true, ownerUid: currentUid());
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _revoke() async {
    var complete = true;
    final uid = currentUid();
    if (uid != null) {
      try {
        await registry.unregister(
          uid: uid,
          installationId: _preferences.installationId,
          revision: _preferences.revision,
        );
      } catch (_) {
        complete = false;
      }
    }
    try {
      await driver.unregister().timeout(const Duration(seconds: 8));
    } catch (_) {
      complete = false;
    }
    registered = false;
    if (complete && uid != null) {
      _preferences = _preferences.copy(ownerUid: uid, cleanupPending: false);
      try {
        await _persist();
      } catch (_) {
        /* Retry persistence next time. */
      }
    } else {
      error ??= 'Device notifications are off. Remote cleanup will retry when you reconnect.';
    }
  }

  Future<void> disable() async {
    if (busy) return;
    ++_session;
    busy = true;
    error = null;
    _changed();
    _preferences = _preferences.copy(
      prompted: true,
      enabled: false,
      ownerUid: currentUid(),
      revision: _preferences.revision + 1,
      cleanupPending: true,
    );
    try {
      await _persist();
    } catch (_) {
      error = 'Your notification choice could not be saved. You can still continue.';
    }
    try {
      await driver.updateAccount(currentUid(), false, _preferences.revision);
    } catch (_) {
      error ??= 'Notification action failed. Check permission and try again.';
    }
    try {
      await driver.cancelAll();
    } catch (_) {
      /* Server and account fences still apply. */
    }
    await _revoke();
    busy = false;
    _changed();
  }

  Future<void> refresh() async {
    if (!ready || busy) return;
    busy = true;
    error = null;
    _changed();
    try {
      permission = await driver.permission();
      if (permission != NoticePermission.granted && enabled) {
        _preferences = _preferences.copy(
          enabled: false,
          ownerUid: currentUid(),
          revision: _preferences.revision + 1,
          cleanupPending: true,
        );
        ++_session;
        await _persist();
        registered = false;
        await driver.updateAccount(currentUid(), false, _preferences.revision);
      }
      await driver.updateAccount(currentUid(), enabled, _preferences.revision);
      if (!enabled && _preferences.cleanupPending) await _revoke();
      await _connect(_session);
    } catch (failure) {
      error = _message(failure);
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> bindAccount(String? uid, String language) {
    _language = language == 'bn' ? 'bn' : 'en';
    if (_account == uid && _preferences.ownerUid == uid) {
      _queueConnect();
      return _accountWork;
    }
    final previous = _account;
    _account = uid;
    final session = ++_session;
    registered = false;
    _notices.clear();
    foregroundNotice = null;
    _accountWork = _accountWork
        .then((_) async {
          if (_disposed || session != _session) return;
          await driver.cancelAll();
          // Rotate the registration when an installation changes account.
          if (previous != null && previous != uid && (enabled || _preferences.cleanupPending)) {
            try {
              await driver.unregister();
            } catch (_) {
              /* Local account fence still applies. */
            }
          }
          if (_disposed || session != _session) return;
          _preferences = _preferences.copy(
            ownerUid: uid,
            revision: _preferences.revision + 1,
          );
          await _persist();
          await driver.updateAccount(uid, enabled, _preferences.revision);
          if (!enabled && _preferences.cleanupPending) await _revoke();
          await _connect(session);
        })
        .catchError((Object failure) {
          error = _message(failure);
          _changed();
        });
    _changed();
    return _accountWork;
  }

  void updateLanguage(String language) {
    if (_language == language) return;
    _language = language == 'bn' ? 'bn' : 'en';
    registered = false;
    _queueConnect();
  }

  void _queueConnect() {
    final session = _session;
    _accountWork = _accountWork.then((_) => _connect(session)).catchError((
      Object failure,
    ) {
      error = _message(failure);
      _changed();
    });
  }

  Future<void> _connect(int session) async {
    if (!ready ||
        _disposed ||
        session != _session ||
        !enabled ||
        permission != NoticePermission.granted ||
        !pushConfigured ||
        registered) {
      return;
    }
    final uid = currentUid();
    if (uid == null || uid != _account) return;
    final fid = await driver.fid();
    if (fid == null ||
        fid.isEmpty ||
        session != _session ||
        !enabled ||
        currentUid() != uid) {
      return;
    }
    await registry.register(
      uid: uid,
      installationId: _preferences.installationId,
      fid: fid,
      language: _language,
      platform: web ? 'web' : 'android',
      revision: _preferences.revision,
    );
    if (session != _session || currentUid() != uid) return;
    registered = true;
    error = null;
    _changed();
  }

  Future<void> detachBeforeSignOut() async {
    final uid = currentUid();
    final needsCleanup = registered || enabled || _preferences.cleanupPending;
    ++_session;
    _account = null;
    registered = false;
    _notices.clear();
    pendingOpen = null;
    foregroundNotice = null;
    _preferences = _preferences.copy(
      ownerUid: null,
      revision: _preferences.revision + 1,
    );
    // Persist the local fence before asynchronous remote cleanup.
    try {
      await _persist();
    } catch (_) {
      /* Auth still signs out. */
    }
    try {
      await driver.updateAccount(null, false, _preferences.revision);
    } catch (_) {
      /* Optional. */
    }
    try {
      await driver.cancelAll();
    } catch (_) {
      /* Optional. */
    }
    if (uid != null && needsCleanup) {
      try {
        await registry
            .unregister(
              uid: uid,
              installationId: _preferences.installationId,
              revision: _preferences.revision,
            )
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        /* Deletion markers and fid rotation remain in force. */
      }
    }
    try {
      if (needsCleanup) {
        await driver.unregister().timeout(const Duration(seconds: 4));
      }
    } catch (_) {
      /* Data-only background handlers also check the account. */
    }
    _changed();
  }

  void _remember(JiggoNotice notice) {
    if (_notices.any((item) => item.id == notice.id)) return;
    _notices.insert(0, notice);
    if (_notices.length > 20) _notices.removeLast();
  }

  void _receive(JiggoNotice notice) {
    if (!enabled ||
        permission != NoticePermission.granted ||
        notice.ownerUid != currentUid() ||
        notice.revision != _preferences.revision) {
      return;
    }
    if (_notices.any((item) => item.id == notice.id)) return;
    _remember(notice);
    foregroundNotice = notice;
    unawaited(
      driver.show(notice).catchError((Object failure) {
        error = _message(failure);
        _changed();
      }),
    );
    _changed();
  }

  void open(JiggoNotice notice) {
    if (!enabled || notice.revision != _preferences.revision) return;
    final uid = currentUid();
    if (uid != null && uid != notice.ownerUid) return;
    pendingOpen = notice;
    if (uid != null) _remember(notice);
    _changed();
  }

  void consumeOpen() {
    pendingOpen = null;
  }

  void consumeForeground() {
    foregroundNotice = null;
  }

  Future<void> testDevice({required String title, required String body}) async {
    if (busy || !enabled || permission != NoticePermission.granted) return;
    final uid = currentUid();
    if (uid == null) return;
    error = null;
    try {
      final notice = JiggoNotice(
        id: NotificationPreferences.newInstallationId(),
        ownerUid: uid,
        title: title,
        body: body,
        target: 'library',
        sentAt: DateTime.now(),
        revision: _preferences.revision,
      );
      await driver.updateAccount(uid, enabled, _preferences.revision);
      if (currentUid() != uid || !enabled) { return; }
      await driver.show(notice);
      _remember(notice);
    } catch (failure) {
      error = _message(failure);
    }
    _changed();
  }

  Future<void> testPush(String target) async {
    if (busy ||
        !enabled ||
        !registered ||
        !notificationTargets.contains(target)) {
      return;
    }
    final uid = currentUid();
    if (uid == null) return;
    busy = true;
    error = null;
    _changed();
    try {
      await registry.sendTest(
        uid: uid,
        installationId: _preferences.installationId,
        target: target,
      );
    } catch (failure) {
      error = _message(failure);
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<bool> openSettings() => driver.openSettings();

  @override
  void dispose() {
    _disposed = true;
    ++_session;
    unawaited(driver.dispose());
    super.dispose();
  }
}

class NotificationScope extends InheritedNotifier<NotificationController> {
  const NotificationScope({
    super.key,
    required NotificationController controller,
    required super.child,
  }) : super(notifier: controller);
  static NotificationController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NotificationScope>()!
      .notifier!;
}
