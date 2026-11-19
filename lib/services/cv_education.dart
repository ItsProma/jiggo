import 'dart:convert';

import 'guided_document_model.dart';

const cvEducationPrefix = 'JIGGO_EDU_V1:';
Map<String, String>? readCvEducation(String entry) {
  if (!entry.startsWith(cvEducationPrefix)) return null;
  try {
    final data = Map<String, String>.from(
      jsonDecode(entry.substring(cvEducationPrefix.length)) as Map,
    );
    if (data.keys.any(
          (k) => ![
            'degree',
            'institution',
            'subject',
            'board',
            'year',
            'result',
          ].contains(k),
        ) ||
        data.values.any((v) => v.length > 120)) {
      return null;
    }
    return data;
  } catch (_) {
    return null;
  }
}

String cvEducationSummary(String entry) {
  final row = readCvEducation(entry);
  if (row == null) return entry;
  return [
    row['degree'] ?? '',
    row['institution'] ?? '',
    row['year'] ?? '',
    row['subject'] ?? '',
    row['board'] ?? '',
    row['result'] ?? '',
  ].where((s) => s.isNotEmpty).join(' — ');
}

String cvEducationMarkdown(List<String> entries, bool bn) {
  final rows = entries
      .map(readCvEducation)
      .whereType<Map<String, String>>()
      .toList();
  final legacy = entries
      .where((s) => s.trim().isNotEmpty && readCvEducation(s) == null)
      .toList();
  if (rows.isEmpty) return legacy.map((s) => '- ${safe(s)}').join('\n');
  final labels = bn
      ? [
          'পরীক্ষা / ডিগ্রি',
          'প্রতিষ্ঠান',
          'বিভাগ / বিষয়',
          'বোর্ড / বিশ্ববিদ্যালয়',
          'পাসের বছর',
          'ফলাফল',
        ]
      : [
          'Exam / Degree',
          'Institution',
          'Subject',
          'Board / University',
          'Year',
          'Result',
        ];
  String cell(String s) => safe(s).replaceAll('\n', ' ').replaceAll('\r', ' ');
  final tables = <String>[];
  for (var i = 0; i < rows.length;) {
    final long = rows[i].values.any((v) => v.length > 60);
    final count = long
        ? 1
        : ((i + 1 < rows.length &&
                  !rows[i + 1].values.any((v) => v.length > 60))
              ? 2
              : 1);
    final chunk = rows.skip(i).take(count);
    i += count;
    tables.add(
      '| ${labels.join(' | ')} |\n| ${List.filled(6, '---').join(' | ')} |\n${chunk.map((r) => '| ${['degree', 'institution', 'subject', 'board', 'year', 'result'].map((k) => cell(r[k] ?? '')).join(' | ')} |').join('\n')}',
    );
  }
  return [
    ...tables,
    if (legacy.isNotEmpty) legacy.map((s) => '- ${safe(s)}').join('\n'),
  ].join('\n\n');
}
