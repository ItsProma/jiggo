import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Deliberately limited import. Unsupported document content is never dropped.
class DocxCodec {
  static const maxBytes = 2 * 1024 * 1024;
  static const maxText = 20000;
  static const w =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const rel =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  static const mainType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';

  static Never unsupported() => throw const FormatException('docx-unsupported');
  static XmlElement? child(XmlElement? e, String name) =>
      e?.getElement(name, namespaceUri: w);
  static String? val(XmlElement? e, [String name = 'val']) =>
      e?.getAttribute(name, namespaceUri: w);
  static bool on(XmlElement e) =>
      !['0', 'false', 'off'].contains(val(e)?.toLowerCase());

  List<Map<String, dynamic>> decode(Uint8List bytes) {
    if (bytes.length > maxBytes || bytes.length < 4) unsupported();
    final names = <String>{};
    var total = 0, count = 0;
    // Inspect the central directory without inflating entries first.
    final directory = ZipDirectory();
    for (final h in directory.headers(
      InputMemoryStream(bytes),
      files: false,
      verify: true,
    )) {
      if (++count > 128 ||
          !names.add(h.filename) ||
          h.filename.startsWith('/') ||
          h.filename.contains('\\') ||
          h.filename.split('/').contains('..') ||
          h.uncompressedSize < 0 ||
          (h.uncompressedSize == 0 && !h.filename.endsWith('/')) ||
          h.uncompressedSize > maxBytes ||
          (total += h.uncompressedSize) > 8 * 1024 * 1024 ||
          h.generalPurposeBitFlag & 1 != 0 ||
          ![0, 8].contains(h.compressionMethod) ||
          ((h.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
        unsupported();
      }
    }
    if (!names.contains('word/document.xml') ||
        !names.contains('[Content_Types].xml')) {
      unsupported();
    }
    if (names.any(
      (n) =>
          n.startsWith('word/media/') ||
          RegExp(
            r'^word/(header|footer|footnotes|endnotes|comments|vbaProject)',
          ).hasMatch(n),
    )) {
      unsupported();
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    XmlDocument? read(String name) {
      final f = archive.findFile(name);
      if (f == null) return null;
      final content = f.readBytes();
      if (content == null || content.length > maxBytes) unsupported();
      final source = utf8.decode(content);
      if (RegExp(
        r'<!DOCTYPE|<!ENTITY',
        caseSensitive: false,
      ).hasMatch(source)) {
        unsupported();
      }
      return XmlDocument.parse(source);
    }

    for (final name in names.where((n) => n.endsWith('.rels'))) {
      final doc = read(name)!;
      if (doc.descendants.whereType<XmlElement>().any(
        (e) => e.getAttribute('TargetMode') == 'External',
      )) {
        unsupported();
      }
    }
    final rootRelations = read('_rels/.rels');
    final mains = rootRelations?.descendants
        .whereType<XmlElement>()
        .where(
          (e) => e.getAttribute('Type') == 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
        )
        .toList();
    if (mains == null ||
        mains.length != 1 ||
        mains.single.getAttribute('Target') != 'word/document.xml') {
      unsupported();
    }
    final types = read('[Content_Types].xml')!;
    if (!types.descendants.whereType<XmlElement>().any(
      (e) =>
          e.name.local == 'Override' &&
          e.getAttribute('PartName') == '/word/document.xml' &&
          e.getAttribute('ContentType') == mainType,
    )) {
      unsupported();
    }
    final settings = read('word/settings.xml');
    if (settings
            ?.findAllElements('documentProtection', namespaceUri: w)
            .any(on) ==
        true) {
      unsupported();
    }
    final xml = read('word/document.xml')!;
    if (xml.rootElement.name.namespaceUri != w ||
        xml.rootElement.name.local != 'document') {
      unsupported();
    }
    final body = child(xml.rootElement, 'body');
    if (body == null) unsupported();
    final stylesDoc = read('word/styles.xml');
    final styles = <String, XmlElement>{};
    String? normal;
    for (final s
        in stylesDoc?.findAllElements('style', namespaceUri: w) ??
            <XmlElement>[]) {
      final id = val(s, 'styleId');
      if (id == null || styles.containsKey(id)) unsupported();
      styles[id] = s;
      if (val(s, 'type') == 'paragraph' && val(s, 'default') == '1') {
        normal = id;
      }
    }
    final defaults = stylesDoc
        ?.findAllElements('docDefaults', namespaceUri: w)
        .firstOrNull;
    final defaultRun = child(child(defaults, 'rPrDefault'), 'rPr');
    final defaultParagraph = child(child(defaults, 'pPrDefault'), 'pPr');
    List<XmlElement> chain(String? id, [Set<String>? seen]) {
      if (id == null) return [];
      final visited = seen ?? <String>{};
      if (!visited.add(id) || visited.length > 16 || !styles.containsKey(id)) {
        unsupported();
      }
      final style = styles[id]!;
      return [...chain(val(child(style, 'basedOn')), visited), style];
    }

    Map<String, dynamic> runStyle(
      Iterable<XmlElement?> styles,
      XmlElement? direct,
    ) {
      final state = <String, bool>{};
      void apply(XmlElement? pr, {required bool toggle}) {
        if (pr == null) return;
        if (pr.childElements.any(
          (e) => ['vanish', 'webHidden'].contains(e.name.local) && on(e),
        )) {
          unsupported();
        }
        for (final (name, cs, key) in [
          ('b', 'bCs', 'bold'),
          ('i', 'iCs', 'italic'),
        ]) {
          final latin = child(pr, name), complex = child(pr, cs);
          if (latin != null && complex != null && on(latin) != on(complex)) {
            unsupported(); // This basic editor cannot represent script-specific formatting.
          }
          final value = latin ?? complex;
          if (value == null) continue;
          if (!toggle) {
            state[key] = on(value);
          } else if (on(value)) {
            state[key] = !(state[key] ?? false);
          }
        }
      }

      apply(defaultRun, toggle: false);
      for (final pr in styles) {
        apply(pr, toggle: true);
      }
      apply(direct, toggle: false);
      return {
        for (final e in state.entries)
          if (e.value) e.key: true,
      };
    }

    final numbering = read('word/numbering.xml');
    String listType(int numId, int level) {
      if (level != 0) unsupported();
      final num = numbering
          ?.findAllElements('num', namespaceUri: w)
          .where((e) => val(e, 'numId') == '$numId')
          .firstOrNull;
      if (num == null ||
          num.findAllElements('lvlOverride', namespaceUri: w).isNotEmpty) {
        unsupported();
      }
      final id = val(child(num, 'abstractNumId'));
      final abstract = numbering
          ?.findAllElements('abstractNum', namespaceUri: w)
          .where((e) => val(e, 'abstractNumId') == id)
          .firstOrNull;
      final lvl = abstract
          ?.findElements('lvl', namespaceUri: w)
          .where((e) => val(e, 'ilvl') == '0')
          .firstOrNull;
      if (lvl == null) unsupported();
      return switch (val(child(lvl, 'numFmt'))) {
        'bullet' => 'bullet',
        'decimal' => 'ordered',
        _ => unsupported(),
      };
    }

    final delta = <Map<String, dynamic>>[];
    var textLength = 0;
    void insert(String s, Map<String, dynamic> a) {
      textLength += s.length;
      if (textLength > maxText) unsupported();
      delta.add({'insert': s, if (a.isNotEmpty) 'attributes': a});
    }

    final paragraphs = body.childElements.toList();
    if (paragraphs.length > 1001) unsupported();
    for (final p in paragraphs) {
      if (p.name.namespaceUri != w) unsupported();
      if (p.name.local == 'sectPr') {
        if (p != paragraphs.last ||
            p.childElements.any(
              (e) => ![
                'pgSz',
                'pgMar',
                'cols',
                'docGrid',
                'type',
                'titlePg',
              ].contains(e.name.local),
            ) ||
            (child(p, 'cols')?.getAttribute('num', namespaceUri: w) ?? '1') !=
                '1') {
          unsupported();
        }
        continue;
      }
      if (p.name.local != 'p') unsupported();
      final direct = child(p, 'pPr');
      final styleId = val(child(direct, 'pStyle')) ?? normal;
      final inherited = chain(styleId);
      final props = [
        defaultParagraph,
        ...inherited.map((s) => child(s, 'pPr')),
        direct,
      ].whereType<XmlElement>().toList();
      var heading = 0;
      XmlElement? num;
      for (final pr in props) {
        if (child(pr, 'sectPr') != null || child(pr, 'framePr') != null) {
          unsupported();
        }
        final outline = val(child(pr, 'outlineLvl'));
        if (outline != null) {
          final n = int.tryParse(outline);
          if (n == null || (n > 2 && n != 9)) unsupported();
          heading = n == 9 ? 0 : n + 1;
        }
        num = child(pr, 'numPr') ?? num;
      }
      final inferred = RegExp(
        r'^Heading([1-9])$',
        caseSensitive: false,
      ).firstMatch(styleId ?? '');
      if (heading == 0 && inferred != null) heading = int.parse(inferred[1]!);
      if (heading > 3) unsupported();
      final block = <String, dynamic>{if (heading > 0) 'header': heading};
      if (num != null) {
        final id = int.tryParse(val(child(num, 'numId')) ?? '');
        final level = int.tryParse(val(child(num, 'ilvl')) ?? '0');
        if (id == null || level == null) unsupported();
        if (id != 0) {
          if (heading > 0) unsupported();
          block['list'] = listType(id, level);
        }
      }
      for (final r in p.childElements) {
        if (r.name.namespaceUri != w) unsupported();
        if ([
          'pPr',
          'bookmarkStart',
          'bookmarkEnd',
          'proofErr',
        ].contains(r.name.local)) {
          continue;
        }
        if (r.name.local != 'r') unsupported();
        final pr = child(r, 'rPr');
        final character = chain(val(child(pr, 'rStyle')));
        final attrs = runStyle([
          ...inherited.map((s) => child(s, 'rPr')),
          ...character.map((s) => child(s, 'rPr')),
        ], pr);
        for (final t in r.childElements) {
          if (t.name.namespaceUri != w) unsupported();
          switch (t.name.local) {
            case 'rPr':
            case 'lastRenderedPageBreak':
              break;
            case 't':
              insert(t.innerText, attrs);
              break;
            case 'tab':
              insert('\t', attrs);
              break;
            case 'cr':
              insert('\u2028', attrs);
              break;
            case 'br':
              if (!['textWrapping', null].contains(val(t, 'type'))) {
                unsupported();
              }
              insert('\u2028', attrs);
              break;
            default:
              unsupported();
          }
        }
      }
      insert('\n', block);
    }
    if (delta.isEmpty) delta.add({'insert': '\n'});
    return delta;
  }

  Uint8List encode(List<Map<String, dynamic>> delta) {
    final paragraphs = <String>[];
    final runs = <String>[];
    var textLength = 0, nextNumberingId = 1;
    String? previousList;
    final numbering = <(int, String)>[];
    var activeListId = 0;
    String esc(String text) =>
        const HtmlEscape(HtmlEscapeMode.element).convert(text);
    for (final op in delta) {
      final insert = op['insert'];
      final attrs = Map<String, dynamic>.from(op['attributes'] as Map? ?? {});
      if (insert is! String ||
          op.keys.any((k) => !['insert', 'attributes'].contains(k)) ||
          attrs.keys.any(
            (k) => !['bold', 'italic', 'header', 'list'].contains(k),
          )) {
        unsupported();
      }
      if ((attrs['bold'] != null && attrs['bold'] is! bool) ||
          (attrs['italic'] != null && attrs['italic'] is! bool)) {
        unsupported();
      }
      final header = attrs['header'];
      final list = attrs['list'];
      if (header != null && (header is! int || header < 1 || header > 3)) {
        unsupported();
      }
      if (list != null && !['bullet', 'ordered'].contains(list)) unsupported();
      if (header != null && list != null) unsupported();
      textLength += insert.length;
      if (textLength > maxText ||
          insert.codeUnits.any((c) => c < 32 && ![9, 10, 13].contains(c))) {
        unsupported();
      }
      final chunks = insert.split('\n');
      for (var i = 0; i < chunks.length; i++) {
        final text = chunks[i];
        if (text.isNotEmpty) {
          final props =
              '${attrs['bold'] == true ? '<w:b/><w:bCs/>' : ''}${attrs['italic'] == true ? '<w:i/><w:iCs/>' : ''}';
          final parts = text.split(RegExp('[\t\u2028]'));
          final controls = RegExp('[\t\u2028]').allMatches(text).toList();
          final content = StringBuffer();
          for (var k = 0; k < parts.length; k++) {
            if (parts[k].isNotEmpty) {
              content.write('<w:t xml:space="preserve">${esc(parts[k])}</w:t>');
            }
            if (k < controls.length) {
              content.write(controls[k][0] == '\t' ? '<w:tab/>' : '<w:br/>');
            }
          }
          runs.add('<w:r><w:rPr>$props</w:rPr>$content</w:r>');
        }
        if (i < chunks.length - 1) {
          var properties = header == null
              ? ''
              : '<w:pStyle w:val="Heading$header"/>';
          if (list != null) {
            if (list != previousList) {
              activeListId = nextNumberingId++;
              numbering.add((activeListId, list as String));
            }
            properties +=
                '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="$activeListId"/></w:numPr>';
          }
          previousList = list as String?;
          paragraphs.add('<w:p><w:pPr>$properties</w:pPr>${runs.join()}</w:p>');
          runs.clear();
          if (paragraphs.length > 1000) unsupported();
        }
      }
    }
    if (runs.isNotEmpty || paragraphs.isEmpty) unsupported();
    const declaration =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final files = <String, String>{
      '[Content_Types].xml':
          '$declaration<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="$mainType"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>',
      '_rels/.rels':
          '$declaration<Relationships xmlns="$rel"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/document.xml':
          '$declaration<w:document xmlns:w="$w"><w:body>${paragraphs.join()}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body></w:document>',
      'word/_rels/document.xml.rels':
          '$declaration<Relationships xmlns="$rel"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>',
      'word/styles.xml':
          '$declaration<w:styles xmlns:w="$w"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Noto Sans" w:hAnsi="Noto Sans" w:cs="Noto Sans Bengali"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:style>${[
            for (var i = 1; i <= 3; i++) '<w:style w:type="paragraph" w:styleId="Heading$i"><w:name w:val="heading $i"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="${i - 1}"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="${[36, 30, 26][i - 1]}"/><w:szCs w:val="${[36, 30, 26][i - 1]}"/></w:rPr></w:style>',
          ].join()}</w:styles>',
      'word/numbering.xml':
          '$declaration<w:numbering xmlns:w="$w">${[for (final (id, type) in numbering) '<w:abstractNum w:abstractNumId="$id"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="${type == 'bullet' ? 'bullet' : 'decimal'}"/><w:lvlText w:val="${type == 'bullet' ? '•' : '%1.'}"/><w:lvlJc w:val="left"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="$id"><w:abstractNumId w:val="$id"/></w:num>'].join()}</w:numbering>',
    };
    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    if (bytes.length > maxBytes) unsupported();
    return bytes;
  }
}
