import '../services/app_theme.dart';
import '../services/app_strings.dart';
import '../widgets/ai_report_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class ScanHistoryDetailsScreen extends StatelessWidget {
  final String answer;
  final String language;
  final String date;

  const ScanHistoryDetailsScreen({
    super.key,
    required this.answer,
    required this.language,
    required this.date,
  });

  List<Widget> _buildAnswerParts(String content) {
    final regex = RegExp(
      r'(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)|\$[^$\n]+\$)',
    );

    final widgets = <Widget>[];
    var lastEnd = 0;

    for (final match in regex.allMatches(content)) {
      if (match.start > lastEnd) {
        final text = content.substring(lastEnd, match.start);
        if (text.trim().isNotEmpty) {
          widgets.add(MarkdownBody(data: text, selectable: true));
        }
      }

      final raw = match.group(0)!;
      String latex;

      if (raw.startsWith(r'$$')) {
        latex = raw.substring(2, raw.length - 2);
      } else if (raw.startsWith(r'\[') || raw.startsWith(r'\(')) {
        latex = raw.substring(2, raw.length - 2);
      } else {
        latex = raw.substring(1, raw.length - 1);
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              latex,
              textStyle: const TextStyle(fontSize: 18),
              onErrorFallback: (_) => SelectableText(latex),
            ),
          ),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      widgets.add(
        MarkdownBody(data: content.substring(lastEnd), selectable: true),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageColor,
      appBar: AppBar(
        backgroundColor: context.pageColor,
        title: Text(context.tr('Scan Details')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('AI Solution'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${context.tr(language)} • ${context.tr(date)}',
              style: TextStyle(color: context.mutedColor),
            ),
            AiReportButton(source: 'scan', content: answer),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildAnswerParts(answer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
