import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_driver_stub.dart';
import 'notification_models.dart';

const jiggoNotificationChannel = AndroidNotificationChannel(
  'jiggo_updates',
  'Jiggo updates',
  description: 'Updates and test notifications from Jiggo',
  importance: Importance.high,
);

NotificationDriver createDriver() => Platform.isAndroid
    ? AndroidNotificationDriver()
    : UnsupportedNotificationDriver();

class AndroidNotificationDriver implements NotificationDriver {
  final _local = FlutterLocalNotificationsPlugin();
  String? _fid;
  Completer<String>? _registration;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  @override
  bool get web => false;
  @override
  bool get pushConfigured => true;

  @override
  Future<void> initialize({
    required void Function(JiggoNotice) onMessage,
    required void Function(JiggoNotice) onOpen,
    required void Function() onRegistrationChanged,
  }) async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final notice = JiggoNotice.decode(response.payload ?? '');
        if (notice != null) onOpen(notice);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(jiggoNotificationChannel);
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final notice = JiggoNotice.decode(
        launch?.notificationResponse?.payload ?? '',
      );
      if (notice != null) onOpen(notice);
    }
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((message) {
        final notice = JiggoNotice.fromData(message.data);
        if (notice != null) onMessage(notice);
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final notice = JiggoNotice.fromData(message.data);
        if (notice != null) onOpen(notice);
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.instance.onRegistered.listen((fid) {
        _fid = fid;
        if (_registration?.isCompleted == false) _registration!.complete(fid);
        onRegistrationChanged();
      }),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final notice = JiggoNotice.fromData(initial.data);
      if (notice != null) onOpen(notice);
    }
  }

  NoticePermission _convert(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => NoticePermission.granted,
    AuthorizationStatus.denied => NoticePermission.denied,
    _ => NoticePermission.notAsked,
  };

  @override
  Future<NoticePermission> permission() async => _convert(
    (await FirebaseMessaging.instance.getNotificationSettings())
        .authorizationStatus,
  );
  @override
  Future<NoticePermission> requestPermission() async => _convert(
    (await FirebaseMessaging.instance.requestPermission()).authorizationStatus,
  );
  @override
  Future<String?> fid() async {
    final pending = _registration = Completer<String>();
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await FirebaseMessaging.instance.register();
    return _fid ?? await pending.future.timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> unregister() async {
    _fid = null;
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.unregister();
  }

  @override
  Future<void> show(JiggoNotice notice) => _local.show(
    id: notice.id.hashCode & 0x7fffffff,
    title: notice.title,
    body: notice.body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        jiggoNotificationChannel.id,
        jiggoNotificationChannel.name,
        channelDescription: jiggoNotificationChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
        autoCancel: true,
      ),
    ),
    payload: notice.encode(),
  );
  @override
  Future<void> cancelAll() => _local.cancelAll();
  @override
  Future<bool> openSettings() async =>
      await const MethodChannel('jiggo/notification_settings')
          .invokeMethod<bool>('open') ??
      false;
  @override
  Future<void> updateAccount(String? uid, bool enabled, int revision) async {}
  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
