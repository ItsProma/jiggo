@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/local_file_backend_web.dart';
import 'package:jiggo/services/local_file_store.dart';

Uint8List textBytes(String s) => Uint8List.fromList(utf8.encode(s));
void main() {
  test('Real IndexedDB persists binary files across instances with separate owners', () async {
    final owner = 'web-${DateTime.now().microsecondsSinceEpoch}';
    final first = LocalFileStore(DeviceLocalFileBackend()),
        second = LocalFileStore(DeviceLocalFileBackend());
    final a = await first.save(
      owner,
      'বাংলা',
      LocalFileKind.txt,
      textBytes('বাংলা English\n'),
      'Text',
    );
    expect(utf8.decode(await second.read(owner, a.id)), 'বাংলা English\n');
    await second.rename(owner, a.id, 'renamed');
    expect((await first.list(owner)).single.name, 'renamed.txt');
    await first.save(
      '${owner}B',
      'keep',
      LocalFileKind.txt,
      textBytes('keep'),
      'Text',
    );
    await second.clear(owner);
    expect(await first.list(owner), isEmpty);
    expect(await first.list('${owner}B'), hasLength(1));
    await first.clear('${owner}B');
    await first.dispose();
    await second.dispose();
  });
  test(
    'Real IndexedDB transactions enforce quota across independent stores/tabs',
    () async {
      final owner = 'quota-${DateTime.now().microsecondsSinceEpoch}';
      final first = LocalFileStore(DeviceLocalFileBackend()),
          second = LocalFileStore(DeviceLocalFileBackend());
      for (var i = 0; i < 99; i++) {
        await first.save(
          owner,
          'f$i',
          LocalFileKind.txt,
          textBytes('a'),
          'Text',
        );
      }
      final results = await Future.wait(
        [first, second].map(
          (s) => s
              .save(owner, 'last', LocalFileKind.txt, textBytes('b'), 'Text')
              .then((_) => true, onError: (_) => false),
        ),
      );
      expect(results.where((v) => v), hasLength(1));
      expect(await first.list(owner), hasLength(100));
      final info = (await first.list(owner)).first;
      await second.remove(owner, info.id);
      await first.save(
        owner,
        'retry',
        LocalFileKind.txt,
        textBytes('ok'),
        'Text',
      );
      expect(await second.list(owner), hasLength(100));
      await first.clear(owner);
      await first.dispose();
      await second.dispose();
    },
  );
}
