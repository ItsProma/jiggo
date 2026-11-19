import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'local_file_backend.dart';
import 'local_file_model.dart';

class DeviceLocalFileBackend implements LocalFileBackend {
  Future<web.IDBDatabase>? _opening;
  Future<web.IDBDatabase> _db() {
    return _opening ??= _open().catchError((Object e) {
      _opening = null;
      throw e;
    });
  }

  Future<web.IDBDatabase> _open() async {
    final c = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open('jiggo_local_library_v1', 1);
    request.addEventListener(
      'upgradeneeded',
      ((web.Event e) {
        final db = request.result as web.IDBDatabase;
        db.createObjectStore('meta');
        db.createObjectStore('data');
      }).toJS,
    );
    request.addEventListener(
      'success',
      ((web.Event e) {
        final db = request.result as web.IDBDatabase;
        if (c.isCompleted) {
          db.close();
          return;
        }
        db.addEventListener(
          'versionchange',
          ((web.Event e) {
            db.close();
            _opening = null;
          }).toJS,
        );
        if (!c.isCompleted) c.complete(db);
      }).toJS,
    );
    request.addEventListener(
      'error',
      ((web.Event e) {
        if (!c.isCompleted) {
          c.completeError(StateError('local-storage-unavailable'));
        }
      }).toJS,
    );
    request.addEventListener(
      'blocked',
      ((web.Event e) {
        if (!c.isCompleted) {
          c.completeError(StateError('local-storage-blocked'));
        }
      }).toJS,
    );
    return c.future;
  }

  String _key(String owner, String id) {
    checkLocalId(id);
    return '${localOwnerKey(owner)}:$id';
  }

  web.IDBKeyRange _range(String owner) {
    final prefix = '${localOwnerKey(owner)}:';
    return web.IDBKeyRange.bound(prefix.toJS, '$prefix\uffff'.toJS);
  }

  Future<JSAny?> _request(web.IDBRequest r) {
    final c = Completer<JSAny?>();
    r.addEventListener(
      'success',
      ((web.Event e) {
        if (!c.isCompleted) c.complete(r.result);
      }).toJS,
    );
    r.addEventListener(
      'error',
      ((web.Event e) {
        if (!c.isCompleted) c.completeError(StateError('local-read-failed'));
      }).toJS,
    );
    return c.future;
  }

  Future<void> _finished(web.IDBTransaction tx) {
    final c = Completer<void>();
    tx.addEventListener(
      'complete',
      ((web.Event e) {
        if (!c.isCompleted) c.complete();
      }).toJS,
    );
    for (final type in ['error', 'abort']) {
      tx.addEventListener(
        type,
        ((web.Event e) {
          if (!c.isCompleted) {
            c.completeError(StateError('local-storage-full-or-failed'));
          }
        }).toJS,
      );
    }
    return c.future;
  }

  List<LocalFileInfo> _infos(JSAny? value) => (value as JSArray<JSAny?>).toDart
      .map(
        (v) => LocalFileInfo.fromJson(
          jsonDecode((v as JSString).toDart) as Map<String, dynamic>,
        ),
      )
      .toList();
  @override
  Future<List<LocalFileInfo>> list(String owner) async {
    final tx = (await _db()).transaction('meta'.toJS, 'readonly');
    return _infos(await _request(tx.objectStore('meta').getAll(_range(owner))));
  }

  @override
  Future<Uint8List> read(String owner, String id) async {
    final tx = (await _db()).transaction('data'.toJS, 'readonly');
    final result = await _request(
      tx.objectStore('data').get(_key(owner, id).toJS),
    );
    if (result == null) throw StateError('local-missing');
    return Uint8List.fromList((result as JSUint8Array).toDart);
  }

  @override
  Future<void> add(String owner, LocalFileInfo info, Uint8List bytes) async {
    final db = await _db();
    final tx = db.transaction(['meta'.toJS, 'data'.toJS].toJS, 'readwrite');
    final done = _finished(tx);
    final meta = tx.objectStore('meta');
    final request = meta.getAll(_range(owner));
    request.addEventListener(
      'success',
      ((web.Event e) {
        try {
          final infos = _infos(request.result);
          if (infos.length >= LocalFileInfo.maxFiles ||
              infos.fold<int>(0, (n, f) => n + f.size) + bytes.length >
                  LocalFileInfo.maxTotalBytes) {
            tx.abort();
            return;
          }
          final key = _key(owner, info.id).toJS;
          meta.add(jsonEncode(info.toJson()).toJS, key);
          tx.objectStore('data').add(bytes.toJS, key);
        } catch (_) {
          tx.abort();
        }
      }).toJS,
    );
    await done;
  }

  @override
  Future<void> rename(String owner, LocalFileInfo info) async {
    final tx = (await _db()).transaction('meta'.toJS, 'readwrite');
    final done = _finished(tx);
    final store = tx.objectStore('meta');
    final key = _key(owner, info.id).toJS;
    final request = store.get(key);
    request.addEventListener(
      'success',
      ((web.Event e) {
        if (request.result.dartify() == null) {
          tx.abort();
          return;
        }
        store.put(jsonEncode(info.toJson()).toJS, key);
      }).toJS,
    );
    await done;
  }

  @override
  Future<void> remove(String owner, String id) async {
    final tx = (await _db()).transaction(
      ['meta'.toJS, 'data'.toJS].toJS,
      'readwrite',
    );
    final done = _finished(tx);
    final key = _key(owner, id).toJS;
    tx.objectStore('meta').delete(key);
    tx.objectStore('data').delete(key);
    await done;
  }

  @override
  Future<void> clear(String owner) async {
    final tx = (await _db()).transaction(
      ['meta'.toJS, 'data'.toJS].toJS,
      'readwrite',
    );
    final done = _finished(tx);
    final range = _range(owner);
    tx.objectStore('meta').delete(range);
    tx.objectStore('data').delete(range);
    await done;
  }
}
