import 'dart:async';

import 'package:jiggo/services/notification_controller.dart';
import 'package:jiggo/services/notification_models.dart';

import 'memory_settings_store.dart';

class FakeNotificationDriver implements NotificationDriver {
  NoticePermission status = NoticePermission.notAsked;
  NoticePermission requestedStatus = NoticePermission.granted;
  bool configured = true;
  bool isWeb = false;
  int requests = 0;
  int unregisters = 0;
  int cancellations = 0;
  int registrations = 0;
  Completer<String?>? registrationWait;
  final List<JiggoNotice> shown = [];
  final List<(String?, bool, int)> accounts = [];
  late void Function(JiggoNotice) receive;
  late void Function(JiggoNotice) opened;
  @override
  bool get web => isWeb;
  @override
  bool get pushConfigured => configured;
  @override
  Future<void> initialize({
    required void Function(JiggoNotice) onMessage,
    required void Function(JiggoNotice) onOpen,
    required void Function() onRegistrationChanged,
  }) async {
    receive = onMessage;
    opened = onOpen;
  }

  @override
  Future<NoticePermission> permission() async => status;
  @override
  Future<NoticePermission> requestPermission() async {
    requests++;
    status = requestedStatus;
    return status;
  }

  @override
  Future<String?> fid() async {
    registrations++;
    return registrationWait == null
        ? 'cExampleInstallation12'
        : registrationWait!.future;
  }

  @override
  Future<void> unregister() async {
    unregisters++;
  }

  @override
  Future<void> show(JiggoNotice notice) async {
    shown.add(notice);
  }

  @override
  Future<void> cancelAll() async {
    cancellations++;
  }

  @override
  Future<bool> openSettings() async => false;
  @override
  Future<void> updateAccount(String? uid, bool enabled, int revision) async {
    accounts.add((uid, enabled, revision));
  }

  @override
  Future<void> dispose() async {}
}

class FakeNotificationRegistry implements NotificationRegistry {
  final List<Map<String, dynamic>> registrations = [];
  final List<Map<String, dynamic>> removals = [];
  final List<String> tests = [];
  Object? error;
  @override
  Future<void> register({
    required String uid,
    required String installationId,
    required String fid,
    required String language,
    required String platform,
    required int revision,
  }) async {
    if (error != null) throw error!;
    registrations.add({
      'uid': uid,
      'installationId': installationId,
      'fid': fid,
      'language': language,
      'platform': platform,
      'revision': revision,
    });
  }

  @override
  Future<void> unregister({
    required String uid,
    required String installationId,
    required int revision,
  }) async {
    if (error != null) throw error!;
    removals.add({
      'uid': uid,
      'installationId': installationId,
      'revision': revision,
    });
  }

  @override
  Future<void> sendTest({
    required String uid,
    required String installationId,
    required String target,
  }) async {
    if (error != null) throw error!;
    tests.add(target);
  }
}

NotificationController skippedNotifications() {
  return NotificationController(
      store: MemorySettingsStore(),
      driver: FakeNotificationDriver(),
      registry: FakeNotificationRegistry(),
      currentUid: () => null,
    )
    ..ready = true
    ..permission = NoticePermission.unsupported;
}
