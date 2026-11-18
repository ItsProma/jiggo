import 'notification_models.dart';
import 'notification_driver_stub.dart'
    if (dart.library.io) 'notification_driver_native.dart'
    if (dart.library.js_interop) 'notification_driver_web.dart'
    as platform;

NotificationDriver createNotificationDriver() => platform.createDriver();
