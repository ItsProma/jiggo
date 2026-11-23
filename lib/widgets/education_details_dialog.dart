import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/document_selections.dart';
import '../services/cv_education.dart';

import 'dart:convert';

class EducationDetailsDialog extends StatefulWidget {
  final String language;
  final Map<String, String>? initial;
  const EducationDetailsDialog({
    super.key,
    required this.language,
    this.initial,
  });
  @override
  State<EducationDetailsDialog> createState() => _EducationDetailsDialogState();
}

class _EducationDetailsDialogState extends State<EducationDetailsDialog> {
  final institution = TextEditingController(),
      other = TextEditingController(),
      subject = TextEditingController(),
      board = TextEditingController(),
      result = TextEditingController();
  final form = GlobalKey<FormState>();
  String? qualification;
  int? year;
  bool missing = false;
  @override
  void initState() {
    super.initState();
    final row = widget.initial;
    if (row == null) return;
    final degree = row['degree'] ?? '';
    qualification =
        educationChoices
            .where(
              (q) =>
                  q == degree ||
                  AppStrings.text(
                        q,
                        widget.language == 'Bangla' ? 'bn' : 'en',
                      ) ==
                      degree,
            )
            .firstOrNull ??
        'Other';
    if (qualification == 'Other') other.text = degree;
    institution.text = row['institution'] ?? '';
    subject.text = row['subject'] ?? '';
    board.text = row['board'] ?? '';
    result.text = row['result'] ?? '';
    final storedYear = int.tryParse(row['year'] ?? '');
    if (storedYear != null &&
        storedYear >= 1950 &&
        storedYear <= DateTime.now().year) {
      year = storedYear;
    }
  }

  @override
  void dispose() {
    subject.dispose();
    board.dispose();
    result.dispose();
    institution.dispose();
    other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(context.tr('Add education')),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Highest qualification')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final q in educationChoices)
                ChoiceChip(
                  label: Text(context.tr(q)),
                  selected: qualification == q,
                  onSelected: (v) =>
                      setState(() => qualification = v ? q : null),
                ),
            ],
          ),
          if (missing && qualification == null)
            Text(context.tr('Choose the required options to continue.')),
          if (qualification == 'Other')
            TextFormField(
              controller: other,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: context.tr('Qualification name'),
              ),
              validator: (v) => v!.trim().isEmpty
                  ? context.tr('This field is required.')
                  : null,
            ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('education-institution'),
            controller: institution,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: context.tr('Institution name'),
            ),
            validator: (v) => v!.trim().isEmpty
                ? context.tr('This field is required.')
                : null,
          ),
          ExpansionTile(
            title: Text(context.tr('Subject, board and result (optional)')),
            children: [
              for (final item in [
                ('Subject / Group', subject),
                ('Board / University', board),
                ('Result / GPA', result),
              ])
                TextFormField(
                  controller: item.$2,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: context.tr(item.$1)),
                ),
            ],
          ),
          DropdownButtonFormField<int>(
            initialValue: year,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr('Passing year (optional)'),
            ),
            items: [
              for (var y = DateTime.now().year; y >= 1950; y--)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (y) => setState(() => year = y),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Cancel')),
      ),
      FilledButton(
        onPressed: () {
          setState(() => missing = true);
          if (!form.currentState!.validate() || qualification == null) return;
          final label = qualification == 'Other'
              ? other.text.trim()
              : AppStrings.text(
                  qualification!,
                  widget.language == 'Bangla' ? 'bn' : 'en',
                );
          Navigator.pop(
            context,
            cvEducationPrefix +
                jsonEncode({
                  'degree': label,
                  'institution': institution.text.trim(),
                  'year': year?.toString() ?? '',
                  'subject': subject.text.trim(),
                  'board': board.text.trim(),
                  'result': result.text.trim(),
                }),
          );
        },
        child: Text(context.tr('Add')),
      ),
    ],
  );
}
