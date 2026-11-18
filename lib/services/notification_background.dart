import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'notification_driver.dart';
import 'notification_models.dart';
import 'notification_preferences.dart';

@pragma('vm:entry-point')
Future<void> jiggoBackgroundNotification(RemoteMessage message) async {
  if (kIsWeb) return; // The web service worker handles its own background work.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final notice = JiggoNotice.fromData(message.data);
  if (notice == null) return;
  final settings = NotificationPreferences.decode(
    await NotificationPreferencesStore().read(),
  );
  if (!settings.enabled ||
      settings.revision != notice.revision ||
      settings.ownerUid != notice.ownerUid ||
      FirebaseAuth.instance.currentUser?.uid != notice.ownerUid) {
    return;
  }
  final driver = createNotificationDriver();
  try {
    await driver.initialize(
      onMessage: (_) {},
      onOpen: (_) {},
      onRegistrationChanged: () {},
    );
    if (await driver.permission() == NoticePermission.granted) {
      await driver.show(notice);
    }
  } finally {
    await driver.dispose();
  }
}
