import 'package:cloud_functions/cloud_functions.dart';

import 'notification_models.dart';

class FirebaseNotificationRegistry implements NotificationRegistry {
  Future<void> _call(String name, Map<String, dynamic> data) async {
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call<Map<String, dynamic>>(data);
    if (result.data['ok'] != true) {
      throw StateError('Notification action not confirmed');
    }
  }

  @override
  Future<void> register({
    required String uid,
    required String installationId,
    required String fid,
    required String language,
    required String platform,
    required int revision,
  }) => _call('registerNotificationDevice', {
    'expectedUid': uid,
    'installationId': installationId,
    'fid': fid,
    'language': language,
    'platform': platform,
    'revision': revision,
  });

  @override
  Future<void> unregister({
    required String uid,
    required String installationId,
    required int revision,
  }) => _call('unregisterNotificationDevice', {
    'expectedUid': uid,
    'installationId': installationId,
    'revision': revision,
  });

  @override
  Future<void> sendTest({
    required String uid,
    required String installationId,
    required String target,
  }) => _call('sendNotificationTest', {
    'expectedUid': uid,
    'installationId': installationId,
    'target': target,
  });
}
