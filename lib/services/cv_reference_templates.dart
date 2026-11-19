import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:flutter/rendering.dart';

import 'bd_cv_pdf.dart';

const referenceCvDesigns = ['Modern Sidebar', 'BD Classic'];
const cvPalette = {
  'Teal': 0xff2f7085,
  'Navy': 0xff243b63,
  'Charcoal': 0xff37474f,
};

class CvTemplateBlock {
  final String kind, text;
  const CvTemplateBlock(this.kind, this.text);
}

class CvTemplateData {
  final CvPaperParts person;
  final List<CvTemplateBlock> side, body;
  const CvTemplateData(this.person, this.side, this.body);
  factory CvTemplateData.parse(String content, {required bool sidebar}) {
    final person = CvPaperParts.parse(content);
    final sections = <_Section>[];
    var current = _Section('');
    sections.add(current);
    for (final node in md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
    ).parseLines(person.body.split('\n'))) {
      if (node is! md.Element) continue;
      if (node.tag == 'h2') {
        current = _Section(node.textContent);
        sections.add(current);
        continue;
      }
      if (node.tag == 'table') {
        final rows = <List<String>>[];
        void visit(md.Node n) {
          if (n is md.Element) {
            if (n.tag == 'tr') {
              rows.add([
                for (final c in n.children ?? <md.Node>[])
                  if (c is md.Element && (c.tag == 'th' || c.tag == 'td'))
                    c.textContent,
              ]);
            } else {
              for (final c in n.children ?? <md.Node>[]) {
                visit(c);
              }
            }
          }
        }

        visit(node);
        if (rows.isNotEmpty) {
          final headers = rows.first;
          for (final row in rows.skip(1)) {
            if (row.isEmpty) continue;
            current.blocks.add(CvTemplateBlock('degree', row.first));
            for (var i = 1; i < row.length; i++) {
              if (row[i].trim().isNotEmpty) {
                current.blocks.add(
                  CvTemplateBlock(
                    'detail',
                    '${i < headers.length ? headers[i] : ''}: ${row[i]}',
                  ),
                );
              }
            }
            current.blocks.add(const CvTemplateBlock('space', ''));
          }
        }
      } else if (node.tag == 'ul' || node.tag == 'ol') {
        for (final child in node.children ?? <md.Node>[]) {
          if (child is md.Element && child.tag == 'li') {
            current.blocks.add(CvTemplateBlock('bullet', child.textContent));
          }
        }
      } else {
        current.blocks.add(
          CvTemplateBlock(
            RegExp(r'^h[1-6]$').hasMatch(node.tag) ? 'degree' : 'text',
            node.textContent,
          ),
        );
      }
    }
    final side = <CvTemplateBlock>[], body = <CvTemplateBlock>[];
    bool onSide(String title) => [
      'personal information',
      'languages',
      'hobbies',
      'travel details',
      'ব্যক্তিগত তথ্য',
      'ভাষা',
      'শখ',
      'ভ্রমণসংক্রান্ত তথ্য',
    ].contains(title.trim().toLowerCase());
    for (final section in sections) {
      final target = sidebar && onSide(section.title) ? side : body;
      if (section.title.isNotEmpty) {
        target.add(CvTemplateBlock('heading', section.title));
      }
      target.addAll(section.blocks);
    }
    return CvTemplateData(
      person,
      _split(side, 360),
      _split(body, sidebar ? 650 : 1000),
    );
  }
  static List<CvTemplateBlock> _split(List<CvTemplateBlock> blocks, int limit) {
    final output = <CvTemplateBlock>[];
    for (final b in blocks) {
      final chars = b.text.characters.toList();
      if (!['text', 'bullet', 'detail'].contains(b.kind) ||
          chars.length <= limit) {
        output.add(b);
        continue;
      }
      for (var i = 0; i < chars.length; i += limit) {
        output.add(
          CvTemplateBlock(
            i == 0 ? b.kind : 'text',
            chars.skip(i).take(limit).join(),
          ),
        );
      }
    }
    return output;
  }
}

class _Section {
  final String title;
  final blocks = <CvTemplateBlock>[];
  _Section(this.title);
}

class CvTemplatePage {
  final List<CvTemplateBlock> side, body;
  const CvTemplatePage(this.side, this.body);
}

String _text(String value) => md.Document()
    .parseLines(value.split('\n'))
    .map((n) => n.textContent)
    .join('\n');

class CvReferencePaper extends StatelessWidget {
  final String content, design, color;
  final Uint8List? photo;
  const CvReferencePaper({
    super.key,
    required this.content,
    required this.design,
    this.color = 'Teal',
    this.photo,
  });
  @override
  Widget build(BuildContext context) {
    final sidebar = design == 'Modern Sidebar';
    final data = CvTemplateData.parse(content, sidebar: sidebar);
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 595,
          child: _theme(
            Material(
              color: Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 842),
                child: sidebar
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 215,
                              color: Color(
                                cvPalette[color] ?? cvPalette['Teal']!,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 28,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final b in _sideBlocks(data))
                                    _block(
                                      b,
                                      side: true,
                                      photo: photo,
                                      person: data.person,
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 28,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final b in data.body)
                                      _block(
                                        b,
                                        person: data.person,
                                        photo: photo,
                                        classic: false,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _block(
                              const CvTemplateBlock('classicHeader', ''),
                              person: data.person,
                              photo: photo,
                            ),
                            for (final b in _classicOrder(data.body))
                              _block(b, person: data.person, photo: photo),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<CvTemplateBlock> _sideBlocks(CvTemplateData d) => [
  const CvTemplateBlock('portrait', ''),
  CvTemplateBlock('name', _text(d.person.name)),
  if (d.person.contacts.isNotEmpty) ...[
    CvTemplateBlock(
      'heading',
      RegExp(r'[\u0980-\u09ff]').hasMatch(d.person.name)
          ? 'যোগাযোগ'
          : 'Contact',
    ),
    ...CvTemplateData._split([
      CvTemplateBlock('text', _text(d.person.contacts)),
    ], 300),
  ],
  ...d.side,
];
List<CvTemplateBlock> _classicOrder(List<CvTemplateBlock> blocks) {
  // Keep user-edited sections intact; move an existing experience section ahead of education.
  final result = List<CvTemplateBlock>.of(blocks);
  final exp = result.indexWhere(
    (b) =>
        b.kind == 'heading' &&
        ['experience', 'অভিজ্ঞতা'].contains(b.text.trim().toLowerCase()),
  );
  final edu = result.indexWhere(
    (b) =>
        b.kind == 'heading' &&
        [
          'educational qualifications',
          'education',
          'শিক্ষাগত যোগ্যতা',
          'শিক্ষা',
        ].contains(b.text.trim().toLowerCase()),
  );
  if (exp > edu && edu >= 0) {
    var end = exp + 1;
    while (end < result.length && result[end].kind != 'heading') {
      end++;
    }
    final section = result.sublist(exp, end);
    result.removeRange(exp, end);
    result.insertAll(edu, section);
  }
  return result;
}

Widget _theme(Widget child) => Theme(
  data: ThemeData(
    fontFamily: 'JiggoSans',
    fontFamilyFallback: const ['JiggoBengali'],
    textTheme: Typography.material2021().englishLike.merge(
      Typography.material2021().black,
    ),
  ),
  child: child,
);
TextStyle _style(double size, {bool side = false, bool bold = false}) =>
    TextStyle(
      fontFamily: 'JiggoSans',
      fontFamilyFallback: const ['JiggoBengali'],
      fontSize: size,
      height: 1.65,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: side ? Colors.white : Colors.black,
    );
Widget _block(
  CvTemplateBlock b, {
  bool side = false,
  bool classic = true,
  Uint8List? photo,
  required CvPaperParts person,
}) {
  if (b.kind == 'space') return const SizedBox(height: 10);
  if (b.kind == 'portrait') {
    return photo == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: ClipOval(
                child: Container(
                  width: 140,
                  height: 140,
                  color: Colors.white,
                  child: Image.memory(
                    photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                ),
              ),
            ),
          );
  }
  if (b.kind == 'classicHeader') {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  _text(person.name),
                  textAlign: TextAlign.center,
                  style: _style(18, bold: true),
                ),
                Text(
                  _text(person.contacts),
                  textAlign: TextAlign.center,
                  style: _style(10.5),
                ),
              ],
            ),
          ),
          if (photo != null) ...[
            const SizedBox(width: 15),
            SizedBox(
              width: 90,
              height: 115,
              child: Image.memory(
                photo,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            ),
          ],
        ],
      ),
    );
  }
  if (b.kind == 'heading' && !side && !classic) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 9),
      child: Text(
        b.text.toUpperCase(),
        style: _style(14, bold: true).copyWith(letterSpacing: 1.1),
      ),
    );
  }
  if (b.kind == 'detail' && b.text.contains(': ')) {
    final split = b.text.indexOf(': ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: classic ? 130 : 100,
            child: Text(
              b.text.substring(0, split),
              style: _style(10.5, side: side),
            ),
          ),
          Expanded(
            child: Text(
              ': ${b.text.substring(split + 2)}',
              style: _style(10.5, side: side),
            ),
          ),
        ],
      ),
    );
  }
  if (b.kind == 'heading') {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 9),
      child: side
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.text.toUpperCase(),
                  style: _style(
                    13,
                    side: true,
                    bold: true,
                  ).copyWith(letterSpacing: 1.1),
                ),
                Container(width: 44, height: 2, color: const Color(0xffe8cb86)),
              ],
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: .6),
              ),
              child: Text(
                b.text.toUpperCase(),
                style: _style(12.5, bold: true),
              ),
            ),
    );
  }
  return Padding(
    padding: EdgeInsets.only(bottom: b.kind == 'detail' ? 3 : 8),
    child: Text(
      '${b.kind == 'bullet' ? '• ' : ''}${b.text}',
      textAlign: b.kind == 'name' ? TextAlign.center : TextAlign.start,
      style: _style(
        b.kind == 'name' ? 17 : (side ? 10.5 : 11),
        side: side,
        bold: ['name', 'degree'].contains(b.kind),
      ),
    ),
  );
}

class CvReferencePdf {
  static Future<List<CvTemplatePage>> paginate(
    String content, {
    required String design,
    Uint8List? photo,
  }) async {
    if(!referenceCvDesigns.contains(design))throw const FormatException('cv-design');
    final sidebar = design == 'Modern Sidebar';
    final data = CvTemplateData.parse(content, sidebar: sidebar);
    Future<List<List<CvTemplateBlock>>> column(
      List<CvTemplateBlock> input,
      double width,
      bool side,
    ) async {
      final pages = <List<CvTemplateBlock>>[];
      var current = <CvTemplateBlock>[];
      var used = 0.0;
      for (var i = 0; i < input.length; i++) {
        final block = input[i];
        final height = await _height(
          _block(
            block,
            side: side,
            photo: photo,
            person: data.person,
            classic: !sidebar,
          ),
          width,
        );
        if (height > 750) {
          throw StateError('A CV section is too long. Shorten this entry.');
        }
        var reserve = height;
        if (['heading', 'degree'].contains(block.kind) &&
            i + 1 < input.length) {
          reserve += await _height(
            _block(
              input[i + 1],
              side: side,
              photo: photo,
              person: data.person,
              classic: !sidebar,
            ),
            width,
          );
        }
        if (current.isNotEmpty && used + reserve > 750) {
          pages.add(current);
          current = [];
          used = 0;
        }
        current.add(block);
        used += height;
      }
      if (current.isNotEmpty) pages.add(current);
      return pages;
    }

    final left = sidebar
        ? await column(_sideBlocks(data), 167, true)
        : <List<CvTemplateBlock>>[];
    final right = await column(
      sidebar
          ? data.body
          : [
              const CvTemplateBlock('classicHeader', ''),
              ..._classicOrder(data.body),
            ],
      sidebar ? 332 : 515,
      false,
    );
    final count = [
      left.length,
      right.length,
      1,
    ].reduce((a, b) => a > b ? a : b);
    if (count > 30) throw StateError('CV exceeds 30 pages.');
    return [
      for (var i = 0; i < count; i++)
        CvTemplatePage(
          i < left.length ? left[i] : [],
          i < right.length ? right[i] : [],
        ),
    ];
  }

  static Future<Uint8List> build({
    required String content,
    required String design,
    String color = 'Teal',
    Uint8List? photo,
  }) async {
    final sidebar = design == 'Modern Sidebar';
    final data = CvTemplateData.parse(content, sidebar: sidebar);
    final pages = await paginate(content, design: design, photo: photo);
    final pdf = pw.Document();
    if (RegExp(r'[\u0980-\u09ff]').hasMatch(content)) {
      for (var i = 0; i < pages.length; i++) {
        final bytes = await ScreenshotController().captureFromWidget(
          _page(pages[i], data, sidebar, color, photo, i, pages.length),
          targetSize: const Size(1190, 1684),
          pixelRatio: 2,
          delay: const Duration(milliseconds: 20),
        );
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
            ),
          ),
        );
      }
    } else {
      final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      );
      final accent = PdfColor.fromInt(cvPalette[color] ?? cvPalette['Teal']!);
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            theme: pw.ThemeData.withFont(base: font, bold: font),
            build: (_) => pw.Stack(
              children: [
                if (sidebar)
                  pw.Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    right: 380,
                    child: pw.Container(color: accent),
                  ),
                if (sidebar)
                  pw.Positioned(
                    left: 24,
                    top: 28,
                    right: 404,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        for (final b in page.side)
                          _pdfBlock(b, data.person, photo, side: true),
                      ],
                    ),
                  ),
                pw.Positioned(
                  left: sidebar ? 239 : 40,
                  top: 28,
                  right: sidebar ? 24 : 40,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      for (final b in page.body)
                        _pdfBlock(b, data.person, photo, classic: !sidebar),
                    ],
                  ),
                ),
                pw.Positioned(
                  right: 20,
                  bottom: 12,
                  child: pw.Text(
                    '${i + 1} / ${pages.length}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return pdf.save();
  }
}

Widget _page(
  CvTemplatePage page,
  CvTemplateData data,
  bool sidebar,
  String color,
  Uint8List? photo,
  int index,
  int count,
) => _theme(
  Material(
    color: Colors.white,
    child: SizedBox(
      width: 595,
      height: 842,
      child: Stack(
        children: [
          if (sidebar)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 215,
              child: ColoredBox(
                color: Color(cvPalette[color] ?? cvPalette['Teal']!),
              ),
            ),
          if (sidebar)
            Positioned(
              left: 24,
              top: 28,
              width: 167,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in page.side)
                    _block(b, side: true, photo: photo, person: data.person),
                ],
              ),
            ),
          Positioned(
            left: sidebar ? 239 : 40,
            top: 28,
            width: sidebar ? 332 : 515,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in page.body)
                  _block(
                    b,
                    photo: photo,
                    person: data.person,
                    classic: !sidebar,
                  ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: 12,
            child: Text('${index + 1} / $count', style: _style(8)),
          ),
        ],
      ),
    ),
  ),
);

pw.Widget _pdfBlock(
  CvTemplateBlock b,
  CvPaperParts person,
  Uint8List? photo, {
  bool side = false,
  bool classic = true,
}) {
  pw.TextStyle style(double size, {bool bold = false}) => pw.TextStyle(
    fontSize: size,
    lineSpacing: 3,
    color: side ? PdfColors.white : PdfColors.black,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  if (b.kind == 'space') return pw.SizedBox(height: 10);
  if (b.kind == 'portrait') {
    return photo == null
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 16),
            child: pw.Center(
              child: pw.ClipOval(
                child: pw.Container(
                  width: 140,
                  height: 140,
                  color: PdfColors.white,
                  child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.cover),
                ),
              ),
            ),
          );
  }
  if (b.kind == 'classicHeader') {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(
                  _text(person.name),
                  textAlign: pw.TextAlign.center,
                  style: style(18, bold: true),
                ),
                pw.Text(
                  _text(person.contacts),
                  textAlign: pw.TextAlign.center,
                  style: style(10.5),
                ),
              ],
            ),
          ),
          if (photo != null) ...[
            pw.SizedBox(width: 15),
            pw.SizedBox(
              width: 90,
              height: 115,
              child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.contain),
            ),
          ],
        ],
      ),
    );
  }
  if (b.kind == 'heading' && !side && !classic) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 9),
      child: pw.Text(
        b.text.toUpperCase(),
        style: style(14, bold: true).copyWith(letterSpacing: 1.1),
      ),
    );
  }
  if (b.kind == 'detail' && b.text.contains(': ')) {
    final split = b.text.indexOf(': ');
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: classic ? 130 : 100,
            child: pw.Text(b.text.substring(0, split), style: style(10.5)),
          ),
          pw.Expanded(
            child: pw.Text(
              ': ${b.text.substring(split + 2)}',
              style: style(10.5),
            ),
          ),
        ],
      ),
    );
  }
  if (b.kind == 'heading') {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 9),
      child: side
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  b.text.toUpperCase(),
                  style: style(13, bold: true).copyWith(letterSpacing: 1.1),
                ),
                pw.Container(
                  width: 44,
                  height: 2,
                  color: PdfColor.fromHex('#e8cb86'),
                ),
              ],
            )
          : pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: .6)),
              child: pw.Text(
                b.text.toUpperCase(),
                style: style(12.5, bold: true),
              ),
            ),
    );
  }
  return pw.Padding(
    padding: pw.EdgeInsets.only(bottom: b.kind == 'detail' ? 3 : 8),
    child: pw.Text(
      '${b.kind == 'bullet' ? '- ' : ''}${b.text}',
      textAlign: b.kind == 'name' ? pw.TextAlign.center : pw.TextAlign.left,
      style: style(
        b.kind == 'name' ? 17 : (side ? 10.5 : 11),
        bold: ['name', 'degree'].contains(b.kind),
      ),
    ),
  );
}

Future<double> _height(Widget widget, double width) async {
  var height = 0.0;
  await ScreenshotController().captureFromWidget(
    SizedBox(
      width: width,
      height: 1,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: double.infinity,
        child: _Probe(
          onHeight: (v) => height = v,
          child: _theme(Material(color: Colors.white, child: widget)),
        ),
      ),
    ),
    targetSize: Size(width, 1),
    pixelRatio: 1,
    delay: const Duration(milliseconds: 10),
  );
  if (!height.isFinite || height < 0) throw StateError('Unable to measure CV.');
  return height;
}

class _Probe extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _Probe({required this.onHeight, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ProbeRender(onHeight);
}

class _ProbeRender extends RenderProxyBox {
  final ValueChanged<double> onHeight;
  _ProbeRender(this.onHeight);
  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
