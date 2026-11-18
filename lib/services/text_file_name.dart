import 'scan_pdf_builder.dart';

String handwritingFilename(String title) => scanPdfFilename(
  title.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), ''),
).replaceFirst(RegExp(r'\.pdf$'), '.txt');
