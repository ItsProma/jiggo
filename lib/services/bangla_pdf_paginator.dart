import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:markdown/markdown.dart' as md;

class BanglaPdfPaginator {
  static const double pageWidth = 595;
  static const double pageHeight = 842;
  static const double pagePadding = 36;

  static const double contentWidth = pageWidth - pagePadding * 2;
  static const double contentHeight = pageHeight - pagePadding * 2 - 100;
  static const double blockSpacing = 12;

  static final ScreenshotController _controller = ScreenshotController();

  static MarkdownStyleSheet get documentStyle =>
      MarkdownStyleSheet.fromTheme(
        ThemeData(
          textTheme: Typography.material2021().englishLike.merge(
            Typography.material2021().black,
          ),
          fontFamily: 'JiggoSans',
          fontFamilyFallback: const ['JiggoBengali'],
        ),
      ).copyWith(
        p: const TextStyle(
          fontSize: 13,
          height: 1.6,
          fontFamily: 'JiggoSans',
          fontFamilyFallback: ['JiggoBengali'],
          color: Colors.black,
        ),
        h1: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          fontFamily: 'JiggoSans',
          fontFamilyFallback: ['JiggoBengali'],
          color: Colors.black,
        ),
        h2: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'JiggoSans',
          fontFamilyFallback: ['JiggoBengali'],
          color: Colors.black,
        ),
        listBullet: const TextStyle(
          fontSize: 13,
          fontFamily: 'JiggoSans',
          fontFamilyFallback: ['JiggoBengali'],
          color: Colors.black,
        ),
        tableHead: const TextStyle(
          fontFamily: 'JiggoSans',
          fontFamilyFallback: ['JiggoBengali'],
          fontSize: 10,
          height: 1.35,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        tableBody: const TextStyle(
          fontFamily: 'JiggoSans',
          fontFamilyFallback: ['JiggoBengali'],
          fontSize: 10,
          height: 1.35,
          color: Colors.black,
        ),
        tableCellsPadding: const EdgeInsets.all(4),
        tableBorder: TableBorder.all(color: Colors.black54),
        strong: const TextStyle(fontWeight: FontWeight.bold),
        em: const TextStyle(fontStyle: FontStyle.italic),
      );

  static List<String> splitMarkdownBlocks(String content) {
    final blocks = <String>[];
    final current = <String>[];

    void saveBlock() {
      if (current.isEmpty) return;
      blocks.add(current.join('\n'));
      current.clear();
    }

    for (final line in content.split('\n')) {
      if (line.trim().isEmpty) {
        saveBlock();
      } else {
        current.add(line);
      }
    }

    saveBlock();
    return blocks;
  }

  static Widget _markdownBlock(
    String content,
    bool modern, {
    bool traditional = false,
  }) {
    return MarkdownBody(
      data: content,
      builders: traditional ? {'h2': CvSectionHeading()} : const {},
      selectable: false,
      imageBuilder: (uri, title, alt) => Text(alt ?? ''),
      styleSheet: modern
          ? documentStyle.copyWith(
              h1: documentStyle.h1?.copyWith(color: const Color(0xff4355c8)),
              h2: documentStyle.h2?.copyWith(color: const Color(0xff4355c8)),
              h2Padding: const EdgeInsets.only(top: 8, bottom: 6),
            )
          : documentStyle,
    );
  }

  static Widget _buildContent(
    List<String> blocks,
    bool modern, {
    bool traditional = false,
  }) {
    return Theme(
      data: ThemeData.light().copyWith(
        textTheme: Typography.material2021().englishLike.merge(
          Typography.material2021().black,
        ),
      ),
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: contentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) const SizedBox(height: blockSpacing),
                _markdownBlock(blocks[i], modern, traditional: traditional),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Future<double> _measureContent(
    List<String> blocks,
    bool modern, {
    bool traditional = false,
  }) async {
    if (blocks.isEmpty) return 0;
    return _measureWidget(
      _buildContent(blocks, modern, traditional: traditional),
    );
  }

  static Future<double> _measureWidget(Widget widget) async {
    double measured = 0;
    await _controller.captureFromWidget(
      SizedBox(
        width: contentWidth,
        height: 1,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: contentWidth,
          maxWidth: contentWidth,
          minHeight: 0,
          maxHeight: double.infinity,
          child: _HeightProbe(
            onHeight: (height) => measured = height,
            child: widget,
          ),
        ),
      ),
      pixelRatio: 1,
      targetSize: const Size(contentWidth, 1),
      delay: const Duration(milliseconds: 20),
    );
    if (!measured.isFinite || measured <= 0) {
      throw StateError('Unable to measure document content.');
    }
    return measured;
  }

  static Widget _buildPage(
    List<String> blocks,
    bool modern, {
    Widget? header,
    bool traditional = false,
  }) {
    return Material(
      color: Colors.white,
      child: SizedBox(
        width: pageWidth,
        height: pageHeight,

        child: Padding(
          padding: const EdgeInsets.all(pagePadding),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null) ...[header, const SizedBox(height: 20)],
                  _buildContent(blocks, modern, traditional: traditional),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<List<Uint8List>> renderPages({
    required String content,
    bool modern = false,
    Widget? firstPageHeader,
    bool traditional = false,
  }) async {
    final headerHeight = firstPageHeader == null
        ? 0
        : await _measureWidget(firstPageHeader) + 20;
    final pageContentHeight = traditional
        ? pageHeight - pagePadding * 2
        : contentHeight;
    final blocks = splitMarkdownBlocks(content);
    final pages = <Uint8List>[];
    final currentBlocks = <String>[];

    Future<void> savePage() async {
      if (currentBlocks.isEmpty) return;

      final image = await _controller.captureFromWidget(
        _buildPage(
          currentBlocks,
          modern,
          header: pages.isEmpty ? firstPageHeader : null,
          traditional: traditional,
        ),
        pixelRatio: 2,
        targetSize: const Size(pageWidth * 2, pageHeight * 2),
        delay: const Duration(milliseconds: 20),
      );

      pages.add(image);
      if (pages.length > 30) throw StateError('Document exceeds 30 PDF pages.');
      currentBlocks.clear();
    }

    final pending = List<String>.of(blocks);
    for (var index = 0; index < pending.length; index++) {
      final block = pending[index];
      final candidate = [...currentBlocks, block];

      final candidateHeight = await _measureContent(
        candidate,
        modern,
        traditional: traditional,
      );

      final available = pageContentHeight - (pages.isEmpty ? headerHeight : 0);
      if (candidateHeight <= available) {
        currentBlocks.add(block);
        continue;
      }

      if (currentBlocks.isNotEmpty) {
        await savePage();
      }

      final blockHeight = await _measureContent(
        [block],
        modern,
        traditional: traditional,
      );

      if (blockHeight >
          pageContentHeight - (pages.isEmpty ? headerHeight : 0)) {
        var pieces = block.split('\n').where((s) => s.isNotEmpty).toList();
        if (pieces.length < 2) {
          pieces = [];
          var part = StringBuffer();
          var length = 0;
          for (final character in block.characters) {
            part.write(character);
            length++;
            if (length >= 450) {
              pieces.add(part.toString());
              part = StringBuffer();
              length = 0;
            }
          }
          if (part.isNotEmpty) pieces.add(part.toString());
        }
        if (pieces.length < 2) {
          throw StateError('A document section cannot fit on one A4 page.');
        }
        pending.insertAll(index + 1, pieces);
        continue;
      }

      currentBlocks.add(block);
    }

    await savePage();

    if (pages.isEmpty) {
      pages.add(
        await _controller.captureFromWidget(
          _buildPage(
            const [],
            modern,
            header: firstPageHeader,
            traditional: traditional,
          ),
          pixelRatio: 2,
          targetSize: const Size(pageWidth * 2, pageHeight * 2),
          delay: const Duration(milliseconds: 20),
        ),
      );
    }

    return pages;
  }
}

class _HeightProbe extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _HeightProbe({required this.onHeight, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HeightProbeRender(onHeight);
}

class _HeightProbeRender extends RenderProxyBox {
  final ValueChanged<double> onHeight;
  _HeightProbeRender(this.onHeight);
  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

class CvSectionHeading extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      Container(
        width: double.infinity,
        color: const Color(0xffeeeeee),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Text(
          element.textContent,
          style: const TextStyle(
            fontFamily: 'JiggoSans',
            fontFamilyFallback: ['JiggoBengali'],
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      );
}
