
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:screenshot/screenshot.dart';

class BanglaPdfPaginator {
  static const double pageWidth = 595;
  static const double pageHeight = 842;
  static const double pagePadding = 36;

  static const double contentWidth = pageWidth - pagePadding * 2;
  static const double contentHeight = pageHeight - pagePadding * 2 - 100;
  static const double blockSpacing = 12;

  static final ScreenshotController _controller =
      ScreenshotController();

  static MarkdownStyleSheet get documentStyle =>
      MarkdownStyleSheet(
        p: const TextStyle(
          fontSize: 13,
          height: 1.6,
          color: Colors.black,
        ),
        h1: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        h2: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        strong: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
        em: const TextStyle(
          fontStyle: FontStyle.italic,
        ),
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

  static Widget _markdownBlock(String content) {
    return MarkdownBody(
      data: content,
      selectable: false,
      styleSheet: documentStyle,
    );
  }

  static Widget _buildContent(List<String> blocks) {
    return Material(
      color: Colors.white,
      child: SizedBox(
        width: contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < blocks.length; i++) ...[
              if (i > 0)
                const SizedBox(height: blockSpacing),
              _markdownBlock(blocks[i]),
            ],
          ],
        ),
      ),
    );
  }

  static Future<double> _measureContent(
    List<String> blocks,
  ) async {
    if (blocks.isEmpty) return 0;

    
final bytes = await _controller.captureFromWidget(
  Material(
    color: Colors.white,
    child: SizedBox(
      width: contentWidth,
      child: _buildContent(blocks),
    ),
  ),
  pixelRatio: 1,
);

    final codec = await ui.instantiateImageCodec(bytes);

    try {
      final frame = await codec.getNextFrame();

      try {
        return frame.image.height.toDouble();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static Widget _buildPage(List<String> blocks) {
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
      child: _buildContent(blocks),
    ),
  ),
),

      ),
    );
  }

  static Future<List<Uint8List>> renderPages({
    required String content,
  }) async {
    final blocks = splitMarkdownBlocks(content);
    final pages = <Uint8List>[];
    final currentBlocks = <String>[];

    Future<void> savePage() async {
      if (currentBlocks.isEmpty) return;

      final image = await _controller.captureFromWidget(
        _buildPage(currentBlocks),
        pixelRatio: 2,
      );

      pages.add(image);
      currentBlocks.clear();
    }

    for (final block in blocks) {
      final candidate = [...currentBlocks, block];

      final candidateHeight =
          await _measureContent(candidate);

      if (candidateHeight <= contentHeight) {
        currentBlocks.add(block);
        continue;
      }

      if (currentBlocks.isNotEmpty) {
        await savePage();
      }

      final blockHeight =
          await _measureContent([block]);

      if (blockHeight > contentHeight) {
        throw StateError(
          'A document section is too long for one A4 page. '
          'Please split the long paragraph or list.',
        );
      }

      currentBlocks.add(block);
    }

    await savePage();

    if (pages.isEmpty) {
      pages.add(
        await _controller.captureFromWidget(
          _buildPage(const []),
          pixelRatio: 2,
        ),
      );
    }

    return pages;
  }
}
