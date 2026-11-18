import 'notification_models.dart';

NotificationDriver createDriver() => UnsupportedNotificationDriver();

class UnsupportedNotificationDriver implements NotificationDriver {
  @override
  bool get web => false;
  @override
  bool get pushConfigured => false;
  @override
  Future<void> initialize({
    required void Function(JiggoNotice) onMessage,
    required void Function(JiggoNotice) onOpen,
    required void Function() onRegistrationChanged,
  }) async {}
  @override
  Future<NoticePermission> permission() async => NoticePermission.unsupported;
  @override
  Future<NoticePermission> requestPermission() => permission();
  @override
  Future<String?> fid() async => null;
  @override
  Future<void> unregister() async {}
  @override
  Future<void> show(JiggoNotice notice) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<bool> openSettings() async => false;
  @override
  Future<void> updateAccount(String? uid, bool enabled, int revision) async {}
  @override
  Future<void> dispose() async {}
}
