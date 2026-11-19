import 'dart:convert';
import 'dart:typed_data';

import 'text_document.dart';

enum LocalFileKind { pdf, txt, docx, png, jpg }

class LocalFileInfo {
  static const maxFileBytes = 32 * 1024 * 1024,
      maxTotalBytes = 64 * 1024 * 1024,
      maxFiles = 100;
  final String id, name, source;
  final LocalFileKind kind;
  final int size, created, updated;
  const LocalFileInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.size,
    required this.created,
    required this.updated,
    required this.source,
  });
  bool get valid =>
      RegExp(r'^[a-f0-9]{32}$').hasMatch(id) &&
      name == localFileName(name, kind) &&
      size > 0 &&
      size <= maxFileBytes &&
      created > 0 &&
      updated >= created &&
      source.length <= 60;
  Map<String, Object> toJson() => {
    'v': 1,
    'id': id,
    'name': name,
    'kind': kind.name,
    'size': size,
    'created': created,
    'updated': updated,
    'source': source,
  };
  factory LocalFileInfo.fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('local-version');
    final value = LocalFileInfo(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: LocalFileKind.values.byName(j['kind'] as String),
      size: j['size'] as int,
      created: j['created'] as int,
      updated: j['updated'] as int,
      source: j['source'] as String,
    );
    if (!value.valid) throw const FormatException('local-metadata');
    return value;
  }
  LocalFileInfo renamed(String value, int time) => LocalFileInfo(
    id: id,
    name: localFileName(value, kind),
    kind: kind,
    size: size,
    created: created,
    updated: time < created ? created : time,
    source: source,
  );
}

String localOwnerKey(String owner) {
  if (owner.isEmpty || owner.length > 128) {
    throw const FormatException('local-owner');
  }
  return base64Url.encode(utf8.encode(owner)).replaceAll('=', '');
}

void checkLocalId(String id) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
    throw const FormatException('local-id');
  }
}

String localFileName(String input, LocalFileKind kind) {
  var name = input
      .trim()
      .replaceFirst(
        RegExp(r'\.(pdf|txt|docx|png|jpe?g)$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  final out = StringBuffer();
  var size = 0, count = 0;
  for (final rune in name.runes) {
    final part = String.fromCharCode(rune),
        bytes = utf8.encode(String.fromCharCode(rune)).length;
    if (count >= 90 || size + bytes > 180) break;
    out.write(part);
    size += bytes;
    count++;
  }
  name = out.toString().replaceAll(RegExp(r'[. ]+$'), '').trim();
  if (name.isEmpty) name = 'Jiggo';
  return '$name.${kind.name}';
}

void validateLocalBytes(LocalFileKind kind, Uint8List b) {
  if (b.isEmpty || b.length > LocalFileInfo.maxFileBytes) {
    throw const FormatException('local-size');
  }
  bool starts(List<int> magic) =>
      b.length >= magic.length &&
      List.generate(magic.length, (i) => b[i] == magic[i]).every((v) => v);
  switch (kind) {
    case LocalFileKind.pdf:
      if (!starts('%PDF-'.codeUnits)) throw const FormatException('local-pdf');
    case LocalFileKind.txt:
      TextDocument.decode('file.txt', b);
    case LocalFileKind.docx:
      if (b.length > 2 * 1024 * 1024 || !starts([80, 75, 3, 4])) {
        throw const FormatException('local-docx');
      }
    case LocalFileKind.png:
      if (!starts([137, 80, 78, 71, 13, 10, 26, 10])) {
        throw const FormatException('local-png');
      }
    case LocalFileKind.jpg:
      if (!starts([255, 216, 255])) throw const FormatException('local-jpg');
  }
}
