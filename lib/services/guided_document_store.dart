import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'guided_document_model.dart';

abstract class GuidedDraftStore {
  Future<String?> read(String owner, String type);
  Future<void> write(String owner, String type, String value);
  Future<void> clearOwner(String owner);
}

class DeviceGuidedDraftStore implements GuidedDraftStore {
  final _prefs = SharedPreferencesAsync();
  String _key(String owner, String type) {
    if (owner.isEmpty ||
        owner.length > 128 ||
        !guidedDocumentTypes.contains(type)) {
      throw const FormatException('draft-owner');
    }
    return 'jiggo.guided.v1.${base64Url.encode(utf8.encode(owner))}.${guidedDocumentTypes.indexOf(type)}';
  }

  @override
  Future<String?> read(String owner, String type) =>
      _prefs.getString(_key(owner, type));
  @override
  Future<void> write(String owner, String type, String value) =>
      _prefs.setString(_key(owner, type), value);
  @override
  Future<void> clearOwner(String owner) async {
    for (final type in guidedDocumentTypes) {
      await _prefs.remove(_key(owner, type));
    }
  }
}

final guidedDrafts = DeviceGuidedDraftStore();
