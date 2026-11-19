import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'local_file_backend.dart';
import 'local_file_model.dart';

class DeviceLocalFileBackend implements LocalFileBackend {
  final Future<Directory> Function()? directory;
  DeviceLocalFileBackend({this.directory});
  Future<Directory> _owner(String owner) async {
    final base = await (directory?.call() ?? getApplicationSupportDirectory());
    return Directory(
      '${base.path}/jiggo_local_files_v1/${localOwnerKey(owner)}',
    );
  }

  Future<Directory> _entry(String owner, String id) async {
    checkLocalId(id);
    return Directory('${(await _owner(owner)).path}/$id');
  }

  @override
  Future<List<LocalFileInfo>> list(String owner) async {
    final root = await _owner(owner);
    if (!await root.exists()) return [];
    final result = <LocalFileInfo>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (RegExp(r'^\.tmp-[a-f0-9]{32}$').hasMatch(name)) {
        await entry.delete(recursive: true);
        continue;
      }
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(name)) continue;
      final info = LocalFileInfo.fromJson(
        jsonDecode(await File('${entry.path}/meta.json').readAsString())
            as Map<String, dynamic>,
      );
      if (info.id != name) throw const FormatException();
      result.add(info);
    }
    return result;
  }

  @override
  Future<Uint8List> read(String owner, String id) async {
    final root = await _entry(owner, id);
    final data = File('${root.path}/data');
    if (await data.length() > LocalFileInfo.maxFileBytes) {
      throw const FormatException();
    }
    return data.readAsBytes();
  }

  @override
  Future<void> add(String owner, LocalFileInfo info, Uint8List bytes) async {
    final root = await _owner(owner);
    await root.create(recursive: true);
    final target = await _entry(owner, info.id);
    if (await target.exists()) throw StateError('local-exists');
    final temp = Directory('${root.path}/.tmp-${info.id}');
    try {
      await temp.create();
      await File('${temp.path}/data').writeAsBytes(bytes, flush: true);
      await File('${temp.path}/meta.json')
          .writeAsString(jsonEncode(info.toJson()), flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  @override
  Future<void> rename(String owner, LocalFileInfo info) async {
    final root = await _entry(owner, info.id);
    if (!await File('${root.path}/data').exists()) {
      throw StateError('local-missing');
    }
    final temp = File('${root.path}/meta.tmp');
    try {
      await temp.writeAsString(jsonEncode(info.toJson()), flush: true);
      await temp.rename('${root.path}/meta.json');
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> remove(String owner, String id) async {
    final root = await _entry(owner, id);
    if (await root.exists()) await root.delete(recursive: true);
  }

  @override
  Future<void> clear(String owner) async {
    final root = await _owner(owner);
    if (await root.exists()) await root.delete(recursive: true);
  }
}
