import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_models.dart';

@JS('jiggoNotifications.supported')
external JSBoolean _supported();
@JS('jiggoNotifications.permission')
external JSString _permission();
@JS('jiggoNotifications.request')
external JSPromise<JSString> _request();
@JS('jiggoNotifications.bind')
external void _bind(JSFunction callback);
@JS('jiggoNotifications.unbind')
external void _unbind();
@JS('jiggoNotifications.show')
external JSPromise<JSAny?> _show(JSString notice);
@JS('jiggoNotifications.cancelAll')
external JSPromise<JSAny?> _cancel();
@JS('jiggoNotifications.account')
external JSPromise<JSAny?> _account(
  JSString uid,
  JSBoolean enabled,
  JSNumber revision,
);

NotificationDriver createDriver() => WebNotificationDriver();

class WebNotificationDriver implements NotificationDriver {
  static const vapidKey = String.fromEnvironment('WEB_PUSH_VAPID_KEY');
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _fid;
  Completer<String>? _registration;
  @override
  bool get web => true;
  @override
  bool get pushConfigured =>
      RegExp(r'^[A-Za-z0-9_-]{80,120}$').hasMatch(vapidKey);

  @override
  Future<void> initialize({
    required void Function(JiggoNotice) onMessage,
    required void Function(JiggoNotice) onOpen,
    required void Function() onRegistrationChanged,
  }) async {
    _bind(
      ((JSString raw) {
        final notice = JiggoNotice.decode(raw.toDart);
        if (notice != null) onOpen(notice);
      }).toJS,
    );
    if (!_supported().toDart) return;
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((message) {
        final notice = JiggoNotice.fromData(message.data);
        if (notice != null) onMessage(notice);
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.instance.onRegistered.listen((fid) {
        _fid = fid;
        if (_registration?.isCompleted == false) _registration!.complete(fid);
        onRegistrationChanged();
      }),
    );
  }

  NoticePermission _convert(String value) => switch (value) {
    'granted' => NoticePermission.granted,
    'denied' => NoticePermission.denied,
    _ => NoticePermission.notAsked,
  };
  @override
  Future<NoticePermission> permission() async => !_supported().toDart
      ? NoticePermission.unsupported
      : _convert(_permission().toDart);
  @override
  Future<NoticePermission> requestPermission() async {
    if (!_supported().toDart) return NoticePermission.unsupported;
    return _convert((await _request().toDart).toDart);
  }

  @override
  Future<String?> fid() async {
    if (!pushConfigured) return null;
    final pending = _registration = Completer<String>();
    await FirebaseMessaging.instance.register(
      vapidKey: vapidKey,
      serviceWorkerScriptPath: 'firebase-messaging-sw.js',
    );
    return _fid ?? await pending.future.timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> unregister() async {
    _fid = null;
    if (pushConfigured) await FirebaseMessaging.instance.unregister();
  }

  @override
  Future<void> show(JiggoNotice notice) async {
    await _show(notice.encode().toJS).toDart;
  }

  @override
  Future<void> cancelAll() async {
    if (_supported().toDart) await _cancel().toDart;
  }

  @override
  Future<bool> openSettings() async => false;
  @override
  Future<void> updateAccount(String? uid, bool enabled, int revision) async {
    if (_supported().toDart) {
      await _account((uid ?? '').toJS, enabled.toJS, revision.toJS).toDart;
    }
  }

  @override
  Future<void> dispose() async {
    _unbind();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
