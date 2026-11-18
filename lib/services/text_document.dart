import 'dart:convert';
import 'dart:typed_data';

/// Plain text only. Opening never modifies the source file.
class TextDocument {
  static const maxBytes = 128 * 1024;
  static const maxCharacters = 20000;
  final String name, text;
  const TextDocument(this.name, this.text);
  factory TextDocument.decode(String name, Uint8List bytes) {
    if (!name.toLowerCase().endsWith('.txt') || bytes.length > maxBytes) {
      throw const FormatException('unsupported-text');
    }
    var text = utf8.decode(bytes, allowMalformed: false);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    if (text.length > maxCharacters ||
        text.codeUnits.any(
          (c) => c < 32 && c != 9 && c != 10 && c != 13 && c != 12,
        )) {
      throw const FormatException('unsupported-text');
    }
    return TextDocument(name, text);
  }
}
