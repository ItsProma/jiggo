import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/local_file_store.dart';
import 'package:jiggo/services/local_file_saver.dart';
import 'package:jiggo/services/local_file_backend_native.dart';
import 'package:jiggo/services/local_file_openers.dart';
import 'package:jiggo/services/docx_codec.dart';
import 'package:image/image.dart' as image;

import 'support/memory_local_files.dart';

Uint8List textBytes(String text) => Uint8List.fromList(utf8.encode(text));
void main() {
  test('Names keep Bengali, remove paths, constrain bytes, and retain the real extension', () {
    expect(
      localFileName(' ../বাংলা: file.PDF ', LocalFileKind.pdf),
      '.._বাংলা_ file.pdf',
    );
    expect(localFileName('... ', LocalFileKind.txt), 'Jiggo.txt');
    final name = localFileName('বা' * 100, LocalFileKind.docx);
    expect(utf8.encode(name).length, lessThanOrEqualTo(185));
    expect(name.endsWith('.docx'), isTrue);
    expect(localOwnerKey('../../other/account'), isNot(contains('/')));
    expect(() => localOwnerKey(''), throwsFormatException);
    expect(() => checkLocalId('../data'), throwsFormatException);
  });
  test('Invalid signatures, malformed UTF8, empty and oversized content are rejected', () {
    for (final kind in LocalFileKind.values) {
      expect(
        () => validateLocalBytes(kind, Uint8List(0)),
        throwsFormatException,
      );
    }
    expect(
      () => validateLocalBytes(LocalFileKind.pdf, textBytes('not PDF')),
      throwsFormatException,
    );
    expect(
      () => validateLocalBytes(LocalFileKind.docx, textBytes('not ZIP')),
      throwsFormatException,
    );
    expect(
      () => validateLocalBytes(LocalFileKind.txt, Uint8List.fromList([255])),
      throwsFormatException,
    );
    expect(
      () => validateLocalBytes(LocalFileKind.txt, textBytes('a' * 20001)),
      throwsFormatException,
    );
    expect(
      () => validateLocalBytes(
        LocalFileKind.pdf,
        Uint8List(LocalFileInfo.maxFileBytes + 1),
      ),
      throwsFormatException,
    );
  });
  test('Persist, rename and reopen without rewriting bytes; account data is isolated', () async {
    final backend = MemoryLocalFiles();
    var now = 100;
    final store = LocalFileStore(backend, clock: () => now);
    final input = textBytes('বাংলা English\n');
    final saving = store.save(
      'A',
      'notes',
      LocalFileKind.txt,
      input,
      'Text Editor',
    );
    input[0] = 0;
    final info = await saving;
    expect(utf8.decode(await store.read('A', info.id)), 'বাংলা English\n');
    expect(await store.list('B'), isEmpty);
    final bytesBefore = backend.data['A']![info.id];
    now = 90;
    await store.rename('A', info.id, 'নতুন');
    final restarted = LocalFileStore(backend);
    final renamed = (await restarted.list('A')).single;
    expect(renamed.name, 'নতুন.txt');
    expect(renamed.updated, 101);
    expect(identical(backend.data['A']![info.id], bytesBefore), isTrue);
    expect(() => store.read('B', info.id), throwsStateError);
    await store.save(
      'B',
      'other',
      LocalFileKind.txt,
      textBytes('other'),
      'Text Editor',
    );
    await store.clear('A');
    expect(await store.list('A'), isEmpty);
    expect(await store.list('B'), hasLength(1));
    await restarted.dispose();
    await store.dispose();
  });
  test('Reads return copies and listing never loads binary contents', () async {
    final backend = MemoryLocalFiles(),
        store = LocalFileStore(MemoryLocalFiles());
    final actual = LocalFileStore(backend);
    final info = await actual.save(
      'A',
      'note',
      LocalFileKind.txt,
      textBytes('original'),
      'Text',
    );
    await actual.list('A');
    expect(backend.reads, 0);
    final first = await actual.read('A', info.id);
    first[0] = 0;
    expect(utf8.decode(await actual.read('A', info.id)), 'original');
    await actual.dispose();
    await store.dispose();
  });
  test(
    'A failed write keeps the queue usable and emits no false save event',
    () async {
      final backend = MemoryLocalFiles()..failNextAdd = true;
      final store = LocalFileStore(backend);
      final events = <String>[];
      final subscription = store.changes('A').listen(events.add);
      await expectLater(
        store.save('A', 'failed', LocalFileKind.txt, textBytes('one'), 'Text'),
        throwsStateError,
      );
      expect(await store.list('A'), isEmpty);
      await store.save(
        'B',
        'other',
        LocalFileKind.txt,
        textBytes('two'),
        'Text',
      );
      await store.save(
        'A',
        'good',
        LocalFileKind.txt,
        textBytes('three'),
        'Text',
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['A']);
      await subscription.cancel();
      await store.dispose();
    },
  );
  test('Concurrent operations cannot exceed 100 files; failed quota check keeps files', () async {
    final store = LocalFileStore(MemoryLocalFiles());
    for (var i = 0; i < 99; i++) {
      await store.save('A', 'f$i', LocalFileKind.txt, textBytes('a'), 'Text');
    }
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        store
            .save('A', 'last$i', LocalFileKind.txt, textBytes('b'), 'Text')
            .then((_) => true, onError: (_) => false),
    ]);
    expect(results.where((v) => v), hasLength(1));
    expect(await store.list('A'), hasLength(100));
    await store.dispose();
  });
  test(
    '64 MB total cap applies to the owner; deleting releases capacity',
    () async {
      final backend = MemoryLocalFiles(),
          bytes = Uint8List(LocalFileInfo.maxFileBytes);
      bytes.setAll(0, '%PDF-'.codeUnits);
      final store = LocalFileStore(backend);
      final first = await store.save(
        'A',
        'one',
        LocalFileKind.pdf,
        bytes,
        'PDF',
      );
      await store.save('A', 'two', LocalFileKind.pdf, bytes, 'PDF');
      await expectLater(
        store.save('A', 'extra', LocalFileKind.txt, textBytes('x'), 'Text'),
        throwsStateError,
      );
      await store.remove('A', first.id);
      await store.save('A', 'extra', LocalFileKind.txt, textBytes('x'), 'Text');
      expect(await store.list('A'), hasLength(2));
      await store.dispose();
    },
  );
  test('Captured owner prevents a save being redirected to another or signed-out account', () async {
    String? owner = 'A';
    final store = LocalFileStore(MemoryLocalFiles());
    final saver = AccountLocalFileSaver(
      store: store,
      expectedOwner: 'A',
      currentOwner: () => owner,
    );
    owner = 'B';
    await expectLater(
      saver.save('one', LocalFileKind.txt, textBytes('secret'), 'Text'),
      throwsStateError,
    );
    owner = null;
    await expectLater(
      saver.save('one', LocalFileKind.txt, textBytes('secret'), 'Text'),
      throwsStateError,
    );
    expect(await store.list('B'), isEmpty);
    expect(await store.list('A'), isEmpty);
    owner = 'A';
    await saver.save('one', LocalFileKind.txt, textBytes('secret'), 'Text');
    expect(await store.list('A'), hasLength(1));
    await store.dispose();
  });
  test('Native disk store survives restart, renames atomically, and clears only one owner', () async {
    final directory = await Directory.systemTemp.createTemp(
      'jiggo-library-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    DeviceLocalFileBackend backend() =>
        DeviceLocalFileBackend(directory: () async => directory);
    final first = LocalFileStore(backend());
    final text = await first.save(
      '../A',
      'বাংলা',
      LocalFileKind.txt,
      textBytes('লেখা\r\nEnglish'),
      'Text',
    );
    await first.save('B', 'keep', LocalFileKind.txt, textBytes('keep'), 'Text');
    await first.dispose();
    final second = LocalFileStore(backend());
    expect(utf8.decode(await second.read('../A', text.id)), 'লেখা\r\nEnglish');
    await second.rename('../A', text.id, 'renamed');
    expect((await second.list('../A')).single.name, 'renamed.txt');
    await second.clear('../A');
    expect(await second.list('../A'), isEmpty);
    expect(await second.list('B'), hasLength(1));
    await second.dispose();
  });
  test('Native store drops interrupted temporary writes without listing them', () async {
    final directory = await Directory.systemTemp.createTemp(
      'jiggo-library-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final temp = Directory(
      '${directory.path}/jiggo_local_files_v1/${localOwnerKey('A')}/.tmp-${'a' * 32}',
    );
    await temp.create(recursive: true);
    await File('${temp.path}/data').writeAsString('partial');
    final store = LocalFileStore(
      DeviceLocalFileBackend(directory: () async => directory),
    );
    expect(await store.list('A'), isEmpty);
    expect(await temp.exists(), isFalse);
    await store.dispose();
  });
  test('Every saved format roundtrips byte-for-byte and can feed its editor picker', () async {
    final directory = await Directory.systemTemp.createTemp(
      'jiggo-library-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalFileStore(
      DeviceLocalFileBackend(directory: () async => directory),
    );
    final docx = DocxCodec().encode([
      {'insert': 'বাংলা English\n'},
    ]);
    final png = Uint8List.fromList(
      image.encodePng(image.Image(width: 4, height: 3)),
    );
    final jpg = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 4, height: 3)),
    );
    final data = {
      LocalFileKind.txt: textBytes('বাংলা English'),
      LocalFileKind.pdf: textBytes('%PDF-1.7'),
      LocalFileKind.docx: docx,
      LocalFileKind.png: png,
      LocalFileKind.jpg: jpg,
    };
    for (final entry in data.entries) {
      final info = await store.save(
        'A',
        'file',
        entry.key,
        entry.value,
        'Tool',
      );
      expect(await store.read('A', info.id), entry.value);
    }
    expect(
      (await SavedTextPicker(
        'file.txt',
        data[LocalFileKind.txt]!,
      ).pick())!.text,
      'বাংলা English',
    );
    expect(
      (await SavedPdfPicker('file.pdf', data[LocalFileKind.pdf]!).pick())!.name,
      'file.pdf',
    );
    expect(
      DocxCodec()
          .decode((await SavedDocxFiles('file.docx', docx).pick())!.bytes)
          .map((op) => op['insert'])
          .join(),
      'বাংলা English\n',
    );
    expect(
      image
          .decodeImage((await SavedImageFiles('file.png', png).pick())!.bytes)!
          .width,
      4,
    );
    await store.dispose();
  });
}
