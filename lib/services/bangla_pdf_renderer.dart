import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class BanglaPdfRenderer {
  static final ScreenshotController screenshotController =
      ScreenshotController();

  static Future<Uint8List> renderDocument({
    required String title,
    required String content,
  }) async {
    final widget = Material(
      color: Colors.white,
      child: Container(
        width: 595,
        padding: const EdgeInsets.all(36),
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
MarkdownBody(
  data: content,
  selectable: false,
  styleSheet: MarkdownStyleSheet(
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
  ),
),

          ],
        ),
      ),
    );

    final image = await screenshotController.captureFromWidget(
      widget,
      pixelRatio: 2,
    );

    return image;
  }
}
