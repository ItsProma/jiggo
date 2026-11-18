import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

class NotificationPreferencesStore implements SettingsStore {
  static const key = 'jiggo.notifications.v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String value) => _preferences.setString(key, value);
}

class NotificationPreferences {
  final bool prompted;
  final bool enabled;
  final String installationId;
  final String? ownerUid;
  final int revision;
  final bool cleanupPending;
  const NotificationPreferences({
    required this.prompted,
    required this.enabled,
    required this.installationId,
    this.ownerUid,
    this.revision = 0,
    this.cleanupPending = false,
  });

  factory NotificationPreferences.empty() => NotificationPreferences(
    prompted: false,
    enabled: false,
    installationId: newInstallationId(),
  );

  factory NotificationPreferences.decode(String? value) {
    try {
      final data = value == null ? null : jsonDecode(value);
      if (data is Map &&
          data['installationId'] is String &&
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ).hasMatch(data['installationId'])) {
        return NotificationPreferences(
          prompted: data['prompted'] == true,
          enabled: data['enabled'] == true,
          installationId: data['installationId'],
          ownerUid: data['ownerUid'] is String ? data['ownerUid'] : null,
          revision: data['revision'] is int && data['revision'] >= 0
              ? data['revision']
              : 0,
          cleanupPending: data['cleanupPending'] == true,
        );
      }
    } on FormatException {
      /* Recover without blocking login. */
    }
    return NotificationPreferences.empty();
  }

  NotificationPreferences copy({
    bool? prompted,
    bool? enabled,
    required String? ownerUid,
    int? revision,
    bool? cleanupPending,
  }) => NotificationPreferences(
    prompted: prompted ?? this.prompted,
    enabled: enabled ?? this.enabled,
    installationId: installationId,
    ownerUid: ownerUid,
    revision: revision ?? this.revision,
    cleanupPending: cleanupPending ?? this.cleanupPending,
  );

  String encode() => jsonEncode({
    'prompted': prompted,
    'enabled': enabled,
    'installationId': installationId,
    'ownerUid': ownerUid,
    'revision': revision,
    'cleanupPending': cleanupPending,
  });

  static String newInstallationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
