import 'dart:typed_data';

import 'package:jiggo/services/local_file_backend.dart';
import 'package:jiggo/services/local_file_model.dart';

class MemoryLocalFiles implements LocalFileBackend {
  final records = <String, Map<String, LocalFileInfo>>{};
  final data = <String, Map<String, Uint8List>>{};
  bool failNextAdd = false;
  int reads = 0;
  @override
  Future<List<LocalFileInfo>> list(String owner) async =>
      (records[owner] ?? {}).values.toList();
  @override
  Future<Uint8List> read(String owner, String id) async {
    reads++;
    return data[owner]![id]!;
  }

  @override
  Future<void> add(String owner, LocalFileInfo info, Uint8List bytes) async {
    if (failNextAdd) {
      failNextAdd = false;
      throw StateError('disk full');
    }
    (records[owner] ??= {})[info.id] = info;
    (data[owner] ??= {})[info.id] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> rename(String owner, LocalFileInfo info) async {
    records[owner]![info.id] = info;
  }

  @override
  Future<void> remove(String owner, String id) async {
    records[owner]?.remove(id);
    data[owner]?.remove(id);
  }

  @override
  Future<void> clear(String owner) async {
    records.remove(owner);
    data.remove(owner);
  }
}
