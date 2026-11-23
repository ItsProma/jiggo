import 'package:jiggo/services/guided_document_store.dart';

class MemoryGuidedDrafts implements GuidedDraftStore {
  final Map<String, String> data = {};
  bool failWrites = false;
  @override
  Future<String?> read(String owner, String type) async => data['$owner/$type'];
  @override
  Future<void> write(String owner, String type, String value) async {
    if (failWrites) throw StateError('storage-full');
    data['$owner/$type'] = value;
  }

  @override
  Future<void> clearOwner(String owner) async =>
      data.removeWhere((key, _) => key.startsWith('$owner/'));
}
