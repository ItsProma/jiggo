import 'dart:typed_data';

import 'local_file_model.dart';

abstract class LocalFileBackend {
  Future<List<LocalFileInfo>> list(String owner);
  Future<Uint8List> read(String owner, String id);
  Future<void> add(String owner, LocalFileInfo info, Uint8List bytes);
  Future<void> rename(String owner, LocalFileInfo info);
  Future<void> remove(String owner, String id);
  Future<void> clear(String owner);
}
