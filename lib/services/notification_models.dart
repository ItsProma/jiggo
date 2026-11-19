import 'dart:convert';

enum NoticePermission { notAsked, granted, denied, unsupported }

const notificationTargets = ['home', 'scan', 'create', 'library', 'profile'];

class JiggoNotice {
  final String id;
  final String ownerUid;
  final String title;
  final String body;
  final String target;
  final DateTime sentAt;
  final int revision;
  const JiggoNotice({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.body,
    required this.target,
    required this.sentAt,
    this.revision = 0,
  });

  static JiggoNotice? fromData(
    Map<String, dynamic> data, {
    DateTime? now,
    Duration maxAge = const Duration(days: 1),
  }) {
    final id = data['id'];
    final uid = data['ownerUid'];
    final title = data['title'];
    final body = data['body'];
    final target = data['target'];
    final time = int.tryParse('${data['sentAt']}');
    final revision = int.tryParse('${data['revision']}');
    if (data['v'] != '1' ||
        id is! String ||
        id.isEmpty ||
        id.length > 120 ||
        uid is! String ||
        uid.isEmpty ||
        uid.length > 128 ||
        title is! String ||
        title.isEmpty ||
        title.length > 120 ||
        body is! String ||
        body.length > 500 ||
        !notificationTargets.contains(target) ||
        time == null ||
        revision == null ||
        revision < 0) {
      return null;
    }
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (time < current - maxAge.inMilliseconds ||
        time > current + const Duration(minutes: 5).inMilliseconds) {
      return null;
    }
    return JiggoNotice(
      id: id,
      ownerUid: uid,
      title: title,
      body: body,
      target: target as String,
      sentAt: DateTime.fromMillisecondsSinceEpoch(time),
      revision: revision,
    );
  }

  static JiggoNotice? decode(String raw) {
    if (raw.length > 6000) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map ? fromData(Map<String, dynamic>.from(value)) : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Map<String, String> get data => {
    'v': '1',
    'id': id,
    'ownerUid': ownerUid,
    'title': title,
    'body': body,
    'target': target,
    'sentAt': '${sentAt.millisecondsSinceEpoch}',
    'revision': '$revision',
  };
  String encode() => jsonEncode(data);
}

abstract interface class NotificationDriver {
  bool get web;
  bool get pushConfigured;
  Future<void> initialize({
    required void Function(JiggoNotice) onMessage,
    required void Function(JiggoNotice) onOpen,
    required void Function() onRegistrationChanged,
  });
  Future<NoticePermission> permission();
  Future<NoticePermission> requestPermission();
  Future<String?> fid();
  Future<void> unregister();
  Future<void> show(JiggoNotice notice);
  Future<void> cancelAll();
  Future<bool> openSettings();
  Future<void> updateAccount(String? uid, bool enabled, int revision);
  Future<void> dispose();
}

abstract interface class NotificationRegistry {
  Future<void> register({
    required String uid,
    required String installationId,
    required String fid,
    required String language,
    required String platform,
    required int revision,
  });
  Future<void> unregister({
    required String uid,
    required String installationId,
    required int revision,
  });
  Future<void> sendTest({
    required String uid,
    required String installationId,
    required String target,
  });
}
