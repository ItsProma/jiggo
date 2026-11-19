import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'local_file_model.dart';
import 'local_file_backend.dart';
import 'local_file_backend_native.dart'
    if (dart.library.js_interop) 'local_file_backend_web.dart'
    as platform;
export 'local_file_model.dart';

final deviceLocalFiles = LocalFileStore(platform.DeviceLocalFileBackend());

class LocalFileStore {
  final LocalFileBackend backend;
  final int Function() clock;
  final String Function() newId;
  final _events = StreamController<String>.broadcast();
  Future<void> _tail = Future.value();
  LocalFileStore(
    this.backend, {
    int Function()? clock,
    String Function()? newId,
  }) : clock = clock ?? _now,
       newId = newId ?? _id;
  static int _now() => DateTime.now().millisecondsSinceEpoch;
  static String _id() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<T> _run<T>(Future<T> Function() task) {
    final future = _tail.then((_) => task());
    _tail = future.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return future;
  }

  Stream<String> changes(String owner) {
    localOwnerKey(owner);
    return _events.stream.where((v) => v == owner);
  }

  Future<List<LocalFileInfo>> list(String owner) => _run(() async {
    localOwnerKey(owner);
    final result = await backend.list(owner);
    result.sort(
      (a, b) => b.updated != a.updated
          ? b.updated.compareTo(a.updated)
          : b.id.compareTo(a.id),
    );
    return result;
  });
  Future<LocalFileInfo> save(
    String owner,
    String name,
    LocalFileKind kind,
    Uint8List data,
    String source,
  ) {
    if (data.isEmpty || data.length > LocalFileInfo.maxFileBytes) {
      return Future.error(const FormatException('local-size'));
    }
    final copy = Uint8List.fromList(data);
    return _run(() async {
      localOwnerKey(owner);
      validateLocalBytes(kind, copy);
      final all = await backend.list(owner);
      if (all.length >= LocalFileInfo.maxFiles ||
          all.fold<int>(0, (n, f) => n + f.size) + copy.length >
              LocalFileInfo.maxTotalBytes) {
        throw StateError('local-library-full');
      }
      final time = clock();
      final info = LocalFileInfo(
        id: newId(),
        name: localFileName(name, kind),
        kind: kind,
        size: copy.length,
        created: time,
        updated: time,
        source: source,
      );
      if (!info.valid || all.any((f) => f.id == info.id)) {
        throw const FormatException('local-record');
      }
      await backend.add(owner, info, copy);
      _events.add(owner);
      return info;
    });
  }

  Future<Uint8List> read(String owner, String id) => _run(() async {
    localOwnerKey(owner);
    checkLocalId(id);
    final all = await backend.list(owner);
    final info = all.where((f) => f.id == id).first;
    final data = await backend.read(owner, id);
    if (data.length != info.size) {
      throw const FormatException('local-incomplete');
    }
    validateLocalBytes(info.kind, data);
    return Uint8List.fromList(data);
  });
  Future<void> rename(String owner, String id, String name) => _run(() async {
    localOwnerKey(owner);
    checkLocalId(id);
    if (name.trim().isEmpty || name.length > 140) {
      throw const FormatException('local-name');
    }
    final all = await backend.list(owner);
    final old = all.where((f) => f.id == id).first;
    final time = clock();
    await backend.rename(
      owner,
      old.renamed(name, time > old.updated ? time : old.updated + 1),
    );
    _events.add(owner);
  });
  Future<void> remove(String owner, String id) => _run(() async {
    localOwnerKey(owner);
    checkLocalId(id);
    await backend.remove(owner, id);
    _events.add(owner);
  });
  Future<void> clear(String owner) => _run(() async {
    localOwnerKey(owner);
    await backend.clear(owner);
    _events.add(owner);
  });
  Future<void> dispose() async {
    await _tail;
    await _events.close();
  }
}
