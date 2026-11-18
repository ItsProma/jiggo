import 'dart:typed_data';
import 'dart:ui' as ui;

class ScanImage {
  static const int maxBytes = 2 * 1024 * 1024;

  /// Keeps small images unchanged. Resizes larger images until they fit.
  static Future<Uint8List> prepare(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const FormatException('The selected image is empty.');
    }

    if (mimeType(bytes) == null) {
      throw const FormatException(
        'Please select a valid JPG, PNG or WebP image.',
      );
    }

    if (bytes.length <= maxBytes) {
      return bytes;
    }

    var targetWidth = 2048;

    try {
      for (var attempt = 0; attempt < 8; attempt++) {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: targetWidth,
          allowUpscaling: false,
        );

        late final int renderedWidth;
        Uint8List? compressed;

        try {
          final frame = await codec.getNextFrame();
          final image = frame.image;

          try {
            renderedWidth = image.width;

            final data = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );

            if (data != null) {
              compressed = data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              );
            }
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }

        if (compressed == null || compressed.isEmpty) {
          throw const FormatException(
            'Unable to process this image. Please choose another photo.',
          );
        }

        if (compressed.length <= maxBytes) {
          validate(compressed);
          return compressed;
        }

        targetWidth = (renderedWidth * 0.75).floor();

        if (targetWidth < 320) {
          break;
        }
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Unable to compress this image. Please choose another photo.',
      );
    }

    throw const FormatException(
      'This image could not be reduced enough. '
      'Please crop it to show only the question and try again.',
    );
  }

  /// Validates the final image before sending it to the backend.
  static String validate(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('The selected image is empty.');
    }

    if (bytes.length > maxBytes) {
      throw const FormatException(
        'Image must be 2 MB or smaller after compression.',
      );
    }

    final type = mimeType(bytes);

    if (type == null) {
      throw const FormatException(
        'Please select a valid JPG, PNG or WebP image.',
      );
    }

    return type;
  }

  static String? mimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }

    const png = [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ];

    if (bytes.length >= png.length &&
        List.generate(
          png.length,
          (i) => bytes[i] == png[i],
        ).every((value) => value)) {
      return 'image/png';
    }

    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }

    return null;
  }
}