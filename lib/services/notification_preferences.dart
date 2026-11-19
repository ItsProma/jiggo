import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'notification_models.dart';

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
  final List<JiggoNotice> history;
  final Set<String> readIds;
  const NotificationPreferences({
    required this.prompted,
    required this.enabled,
    required this.installationId,
    this.ownerUid,
    this.revision = 0,
    this.cleanupPending = false,
    this.history = const [],
    this.readIds = const {},
  });

  factory NotificationPreferences.empty() => NotificationPreferences(
    prompted: false,
    enabled: false,
    installationId: newInstallationId(),
  );

  factory NotificationPreferences.decode(String? value) {
    try {
      final data = value == null || value.length > 180000
          ? null
          : jsonDecode(value);
      if (data is Map &&
          data['installationId'] is String &&
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ).hasMatch(data['installationId'])) {
        final history = <JiggoNotice>[];
        if (data['history'] is List) {
          for (final raw in (data['history'] as List).take(50)) {
            if (raw is! Map) continue;
            final notice = JiggoNotice.fromData(
              Map<String, dynamic>.from(raw),
              maxAge: const Duration(days: 30),
            );
            if (notice != null &&
                notice.ownerUid == data['ownerUid'] &&
                !history.any((n) => n.id == notice.id)) {
              history.add(notice);
            }
          }
        }
        final read = data['readIds'] is List
            ? (data['readIds'] as List)
                  .whereType<String>()
                  .where((id) => history.any((n) => n.id == id))
                  .toSet()
            : <String>{};
        return NotificationPreferences(
          history: history,
          readIds: read,
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
    } catch (_) {
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
    List<JiggoNotice>? history,
    Set<String>? readIds,
  }) => NotificationPreferences(
    history: history ?? (ownerUid == this.ownerUid ? this.history : const []),
    readIds: readIds ?? (ownerUid == this.ownerUid ? this.readIds : const {}),
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
    'history': history.take(50).map((n) => n.data).toList(),
    'readIds': readIds.where((id) => history.any((n) => n.id == id)).toList(),
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
