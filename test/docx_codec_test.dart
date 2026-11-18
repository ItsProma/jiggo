import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/docx_codec.dart';
import 'package:jiggo/services/docx_files.dart' show docxFilename;

final basicDelta = <Map<String, dynamic>>[
  {'insert': 'Jiggo DOCX'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {
    'insert': '  বাংলা & <English> "text"\t',
    'attributes': {'bold': true},
  },
  {
    'insert': 'italic',
    'attributes': {'italic': true},
  },
  {'insert': '\n'},
  {'insert': 'প্রথম'},
  {
    'insert': '\n',
    'attributes': {'list': 'bullet'},
  },
  {'insert': 'Second'},
  {
    'insert': '\n',
    'attributes': {'list': 'bullet'},
  },
  {'insert': 'Numbered'},
  {
    'insert': '\n',
    'attributes': {'list': 'ordered'},
  },
];
String plain(List<Map<String, dynamic>> d) => d.map((o) => o['insert']).join();
Uint8List changed(
  Uint8List bytes,
  String path,
  String Function(String) update,
) {
  final input = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final f in input.files) {
    final content = f.readBytes()!;
    final next = f.name == path
        ? utf8.encode(update(utf8.decode(content)))
        : content;
    output.addFile(ArchiveFile(f.name, next.length, next));
  }
  return Uint8List.fromList(ZipEncoder().encode(output));
}

void main() {
  final codec = DocxCodec();
  test('Bilingual DOCX round-trip preserves text, literal XML chars, B/I, headings and lists', () {
    final doc = codec.encode(basicDelta);
    final imported = codec.decode(doc);
    expect(plain(imported), plain(basicDelta));
    expect(
      imported.any(
        (o) =>
            (o['attributes'] as Map?)?['bold'] == true &&
            (o['insert'] as String).contains('বাংলা'),
      ),
      isTrue,
    );
    expect(
      imported.any(
        (o) =>
            (o['attributes'] as Map?)?['italic'] == true &&
            o['insert'] == 'italic',
      ),
      isTrue,
    );
    expect(
      imported.where((o) => (o['attributes'] as Map?)?['header'] == 1).length,
      1,
    );
    expect(
      imported
          .where((o) => (o['attributes'] as Map?)?['list'] == 'bullet')
          .length,
      2,
    );
    expect(
      imported
          .where((o) => (o['attributes'] as Map?)?['list'] == 'ordered')
          .length,
      1,
    );
    expect(plain(codec.decode(codec.encode(imported))), plain(basicDelta));
  });
  test('Paragraph and character style inheritance including explicit false are applied', () {
    var bytes = codec.encode([
      {'insert': 'Styled\n'},
    ]);
    bytes = changed(
      bytes,
      'word/styles.xml',
      (s) => s.replaceFirst(
        '</w:styles>',
        '<w:style w:type="paragraph" w:styleId="Custom"><w:basedOn w:val="Normal"/><w:rPr><w:b/></w:rPr></w:style><w:style w:type="character" w:styleId="Emphasis"><w:rPr><w:i/></w:rPr></w:style></w:styles>',
      ),
    );
    bytes = changed(
      bytes,
      'word/document.xml',
      (s) => s
          .replaceFirst(
            '<w:pPr></w:pPr>',
            '<w:pPr><w:pStyle w:val="Custom"/></w:pPr>',
          )
          .replaceFirst(
            '<w:rPr></w:rPr>',
            '<w:rPr><w:rStyle w:val="Emphasis"/><w:b w:val="0"/></w:rPr>',
          ),
    );
    final result = codec.decode(bytes).first;
    expect(result['attributes'], {'italic': true});
    expect(result['insert'], 'Styled');
  });
  test(
    'Soft line breaks, tabs, empty paragraphs and disabled list survive',
    () {
      final delta = <Map<String, dynamic>>[
        {'insert': 'A\u2028B\tC\n\n'},
      ];
      expect(plain(codec.decode(codec.encode(delta))), plain(delta));
      var bytes = codec.encode([
        {'insert': 'Plain\n'},
      ]);
      bytes = changed(
        bytes,
        'word/document.xml',
        (s) => s.replaceFirst(
          '<w:pPr></w:pPr>',
          '<w:pPr><w:numPr><w:numId w:val="0"/></w:numPr></w:pPr>',
        ),
      );
      expect(plain(codec.decode(bytes)), 'Plain\n');
    },
  );
  test(
    'Unsupported visible content is rejected rather than silently removed',
    () {
      final bytes = codec.encode([
        {'insert': 'Text\n'},
      ]);
      for (final node in [
        '<w:tbl/>',
        '<w:hyperlink><w:r><w:t>link</w:t></w:r></w:hyperlink>',
        '<w:ins><w:r><w:t>changed</w:t></w:r></w:ins>',
        '<w:sdt/>',
        '<w:r><w:drawing/></w:r>',
        '<w:r><w:fldChar/></w:r>',
        '<w:r><w:footnoteReference/></w:r>',
      ]) {
        final bad = changed(
          bytes,
          'word/document.xml',
          (s) => s.replaceFirst('</w:p>', '$node</w:p>'),
        );
        expect(() => codec.decode(bad), throwsFormatException, reason: node);
      }
    },
  );
  test('Unsupported heading, nested numbering, hidden text and cyclic styles fail closed', () {
    final bytes = codec.encode(basicDelta);
    final cases = [
      changed(
        bytes,
        'word/document.xml',
        (s) => s.replaceFirst('Heading1', 'Heading9'),
      ),
      changed(
        bytes,
        'word/document.xml',
        (s) => s.replaceFirst('<w:ilvl w:val="0"/>', '<w:ilvl w:val="1"/>'),
      ),
      changed(
        bytes,
        'word/document.xml',
        (s) => s.replaceFirst('<w:rPr>', '<w:rPr><w:vanish/>'),
      ),
      changed(
        bytes,
        'word/styles.xml',
        (s) => s.replaceFirst(
          '<w:basedOn w:val="Normal"/>',
          '<w:basedOn w:val="Heading1"/>',
        ),
      ),
      changed(
        bytes,
        'word/numbering.xml',
        (s) => s.replaceFirst('w:val="decimal"', 'w:val="upperRoman"'),
      ),
    ];
    for (final bad in cases) {
      expect(() => codec.decode(bad), throwsFormatException);
    }
  });
  test('DTD, external relationships, wrong main document and wrong content type are rejected', () {
    final bytes = codec.encode(basicDelta);
    final cases = [
      changed(
        bytes,
        'word/document.xml',
        (s) => s.replaceFirst('<w:document', '<!DOCTYPE foo><w:document'),
      ),
      changed(
        bytes,
        '_rels/.rels',
        (s) => s.replaceFirst(
          'Target="word/document.xml"',
          'Target="word/document.xml" TargetMode="External"',
        ),
      ),
      changed(
        bytes,
        '_rels/.rels',
        (s) => s.replaceFirst(
          'Target="word/document.xml"',
          'Target="word/other.xml"',
        ),
      ),
      changed(
        bytes,
        '[Content_Types].xml',
        (s) => s.replaceFirst(
          DocxCodec.mainType,
          'application/vnd.ms-word.document.macroEnabled.main+xml',
        ),
      ),
    ];
    for (final bad in cases) {
      expect(() => codec.decode(bad), throwsFormatException);
    }
  });
  test('Export refuses embeds, unsupported attributes, invalid XML controls and oversize text', () {
    for (final d in <List<Map<String, dynamic>>>[
      [
        {
          'insert': {'image': 'https://example.invalid/x'},
        },
        {'insert': '\n'},
      ],
      [
        {
          'insert': 'red',
          'attributes': {'color': '#ff0000'},
        },
        {'insert': '\n'},
      ],
      [
        {'insert': '\u0000\n'},
      ],
      [
        {'insert': 'a' * DocxCodec.maxText + '\n'},
      ],
      [
        {'insert': 'missing final newline'},
      ],
    ]) {
      expect(() => codec.encode(d), throwsFormatException);
    }
  });
  test('ZIP resource limits and damaged data are rejected before unbounded inflation', () {
    final bytes = codec.encode(basicDelta);
    expect(
      () => codec.decode(Uint8List(DocxCodec.maxBytes + 1)),
      throwsFormatException,
    );
    final bomb = Uint8List.fromList(bytes);
    final data = ByteData.sublistView(bomb);
    for (var i = 0; i < bomb.length - 28; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        data.setUint32(i + 24, 5 * 1024 * 1024, Endian.little);
        break;
      }
    }
    expect(() => codec.decode(bomb), throwsFormatException);
    final many = ZipDecoder().decodeBytes(bytes);
    for (var i = 0; i < 129; i++) {
      many.addFile(ArchiveFile('extra/$i.xml', 1, [65]));
    }
    expect(
      () => codec.decode(Uint8List.fromList(ZipEncoder().encode(many))),
      throwsFormatException,
    );
    expect(
      () => codec.decode(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(anything),
    );
  });
  test('Inherited style toggles and script-specific contradictions are handled explicitly', () {
    for (final flag in ['1', '0']) {
      var bytes = codec.encode([
        {'insert': 'Style text\n'},
      ]);
      bytes = changed(
        bytes,
        'word/styles.xml',
        (s) => s.replaceFirst(
          '</w:styles>',
          '<w:style w:type="paragraph" w:styleId="Parent"><w:basedOn w:val="Normal"/><w:rPr><w:b/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Child"><w:basedOn w:val="Parent"/><w:rPr><w:b w:val="$flag"/></w:rPr></w:style></w:styles>',
        ),
      );
      bytes = changed(
        bytes,
        'word/document.xml',
        (s) => s.replaceFirst(
          '<w:pPr></w:pPr>',
          '<w:pPr><w:pStyle w:val="Child"/></w:pPr>',
        ),
      );
      expect(
        (codec.decode(bytes).first['attributes'] as Map?)?['bold'] == true,
        flag == '0',
      );
    }
    var bytes = codec.encode([
      {'insert': 'বাংলা English\n'},
    ]);
    bytes = changed(
      bytes,
      'word/document.xml',
      (s) => s.replaceFirst('<w:rPr>', '<w:rPr><w:b/><w:bCs w:val="0"/>'),
    );
    expect(() => codec.decode(bytes), throwsFormatException);
  });
  test(
    'DOCX copy names retain their suffix and fit Unicode filesystem limits',
    () {
      for (final title in [
        'report.docx',
        '../bad/name.docx',
        'বাংলা' * 40,
        '😀' * 140,
      ]) {
        final name = docxFilename(title);
        expect(name.endsWith('_edited.docx'), isTrue);
        expect(utf8.encode(name).length, lessThanOrEqualTo(200));
        expect(name.contains('/'), isFalse);
      }
      expect(docxFilename('report.docx'), 'report_edited.docx');
    },
  );
}
