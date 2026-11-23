import 'dart:convert';

import 'app_strings.dart';
import 'guided_document_model.dart';

class DocumentSelection {
  final String id, label;
  final List<String> options;
  final int step;
  final bool multiple, required;
  const DocumentSelection(
    this.id,
    this.label,
    this.options, {
    this.step = 0,
    this.multiple = false,
    this.required = false,
  });
}

const educationChoices = [
  'SSC',
  'HSC',
  'Diploma',
  "Bachelor's",
  "Master's",
  'Other',
];
List<DocumentSelection> documentSelections(GuidedDocument d) =>
    switch (d.type) {
      'CV / Resume' => const [
        DocumentSelection('mode', 'Which describes you?', [
          'Student',
          'First job',
          'Experienced',
        ], required: true),
        DocumentSelection(
          'noExperience',
          'Do you have work experience?',
          ['yes', 'no'],
          step: 1,
          required: true,
        ),
        DocumentSelection(
          'skills',
          'Choose your real skills',
          [
            'Graphic design',
            'Customer service',
            'Microsoft Word',
            'Microsoft Excel',
            'Communication',
            'Computer basics',
            'Other',
          ],
          step: 2,
          multiple: true,
        ),
        DocumentSelection(
          'languages',
          'Languages you know',
          ['Bangla', 'English', 'Swedish', 'Hindi', 'Other'],
          step: 2,
          multiple: true,
        ),
      ],
      'Job Application' => const [
        DocumentSelection('role', 'Choose a job', [
          'Sales assistant',
          'Office assistant',
          'Graphic designer',
          'Customer service',
          'Other',
        ], required: true),
        DocumentSelection(
          'qualification',
          'Highest qualification',
          educationChoices,
          step: 1,
          required: true,
        ),
        DocumentSelection('experience', 'Relevant experience', [
          'No experience',
          'Less than 1 year',
          '1–2 years',
          '3–5 years',
          'More than 5 years',
          'Other',
        ], step: 1),
      ],
      'Leave Application' => [
        const DocumentSelection('context', 'Where do you need leave?', [
          'School',
          'College',
          'Office',
        ], required: true),
        DocumentSelection('recipient', 'Who will receive it?', switch (d.v(
          'context',
        )) {
          'School' => ['Class teacher', 'Head teacher', 'Other'],
          'College' => ['Teacher', 'Principal', 'Other'],
          'Office' => ['Manager', 'HR department', 'Other'],
          _ => [
            'Teacher',
            'Head teacher',
            'Principal',
            'Manager',
            'HR department',
            'Other',
          ],
        }, required: true),
        const DocumentSelection(
          'reason',
          'Reason for leave',
          ['Illness', 'Family matter', 'Personal matter', 'Other'],
          step: 1,
          required: true,
        ),
      ],
      'Formal Letter' => const [
        DocumentSelection('purpose', 'Letter type', [
          'Request',
          'Complaint',
          'Permission',
          'Other',
        ], required: true),
        DocumentSelection('recipient', 'Who will receive it?', [
          'Manager',
          'Landlord',
          'Principal',
          'Local authority',
          'Other',
        ], required: true),
        DocumentSelection(
          'subject',
          'What is the letter about?',
          [
            'Repair request',
            'Payment issue',
            'Service complaint',
            'Request for information',
            'Permission request',
            'Other',
          ],
          step: 1,
          required: true,
        ),
      ],
      'Invoice' => const [
        DocumentSelection('currency', 'Currency', [
          'BDT',
          'USD',
          'EUR',
          'SEK',
          'GBP',
        ], required: true),
        DocumentSelection('status', 'Payment status', [
          'Unpaid',
          'Paid',
        ], required: true),
      ],
      _ => const [
        DocumentSelection('level', 'Class or course', [
          'Primary school',
          'Secondary school',
          'SSC',
          'HSC',
          'Diploma',
          'University',
          'Nursing',
          'Other',
        ], required: true),
        DocumentSelection('subject', 'Subject', [
          'Bangla',
          'English',
          'Mathematics',
          'Biology',
          'Chemistry',
          'Physics',
          'ICT',
          'Nursing',
          'Business studies',
          'Accounting',
          'Other',
        ], required: true),
        DocumentSelection(
          'length',
          'Approximate word count',
          ['250', '500', '1000', '1500'],
          step: 1,
          required: true,
        ),
      ],
    };

void prepareDocumentSelections(GuidedDocument d, {bool fresh = false}) {
  if (fresh) {
    for (final key in [
      'mode',
      'noExperience',
      'context',
      'purpose',
      'currency',
      'status',
      'length',
    ]) {
      d.values.remove(key);
    }
  }
  d.values['_entry'] = 'form';
  d.values['_select_v1'] = 'yes';
}

List<String> selectedOptions(GuidedDocument d, DocumentSelection spec) {
  final stored = d.v('_pick_${spec.id}');
  if (stored.isNotEmpty) {
    try {
      return List<String>.from(jsonDecode(stored) as List)
          .where(spec.options.contains)
          .toList();
    } catch (_) {
      return [];
    }
  }
  final value = d.v(spec.id);
  if (value.isEmpty) return [];
  if (spec.options.contains(value)) return [value];
  return spec.options.contains('Other') ? ['Other'] : [];
}

String otherSelectionText(GuidedDocument d, DocumentSelection spec) =>
    d.values['_other_${spec.id}'] ??
    (selectedOptions(d, spec).contains('Other') ? d.v(spec.id) : '');

void applyDocumentSelection(
  GuidedDocument d,
  DocumentSelection spec,
  List<String> selected,
  String other,
) {
  if (selected.any((s) => !spec.options.contains(s)) ||
      (!spec.multiple && selected.length > 1)) {
    throw const FormatException('selection');
  }
  d.values['_pick_${spec.id}'] = jsonEncode(selected);
  d.values['_other_${spec.id}'] = other;
  final fragments = [
    for (final item in selected)
      if (item != 'Other')
        ([
              'mode',
              'noExperience',
              'context',
              'purpose',
              'currency',
              'status',
              'length',
            ].contains(spec.id)
            ? item
            : AppStrings.text(item, d.bn ? 'bn' : 'en')),
    if (selected.contains('Other') && other.trim().isNotEmpty) other.trim(),
  ];
  d.values[spec.id] = fragments.join(', ');
}

void syncSelectionLanguage(GuidedDocument d) {
  for (final spec in documentSelections(d)) {
    if (d.values.containsKey('_pick_${spec.id}')) {
      applyDocumentSelection(
        d,
        spec,
        selectedOptions(d, spec),
        otherSelectionText(d, spec),
      );
    }
  }
}

String? selectionValidation(GuidedDocument d, {int? step}) {
  if (d.v('_select_v1') != 'yes') return null;
  for (final spec in documentSelections(
    d,
  ).where((s) => step == null || s.step == step)) {
    final chosen = selectedOptions(d, spec);
    // A legacy custom value can still be reviewed and edited without being discarded.
    if (spec.required && d.v(spec.id).isEmpty) {
      return 'Choose the required options to continue.';
    }
    if (chosen.contains('Other') &&
        otherSelectionText(d, spec).trim().isEmpty) {
      return 'Write a short detail for Other.';
    }
  }
  return null;
}

List<String> savedInvoiceCustomers(GuidedDocument d) {
  try {
    return List<String>.from(jsonDecode(d.v('_customers')) as List)
        .where((s) => s.isNotEmpty && s.length <= 120)
        .take(8)
        .toList();
  } catch (_) {
    return [];
  }
}

List<Map<String, String>> savedInvoiceProducts(GuidedDocument d) {
  try {
    return (jsonDecode(d.v('_products')) as List)
        .map((m) => Map<String, String>.from(m as Map))
        .where(
          (m) =>
              m['name'] != null && m['rate'] != null && m['currency'] != null,
        )
        .take(8)
        .toList();
  } catch (_) {
    return [];
  }
}

void rememberInvoiceChoices(GuidedDocument d) {
  final customers = savedInvoiceCustomers(d)..remove(d.v('buyer'));
  if (d.v('buyer').isNotEmpty) customers.insert(0, d.v('buyer'));
  final products = savedInvoiceProducts(d);
  for (final item in d.items) {
    if ((item['name'] ?? '').trim().isEmpty) continue;
    parseFixed(item['rate'] ?? '');
    products.removeWhere(
      (m) => m['name'] == item['name'] && m['currency'] == d.v('currency'),
    );
    products.insert(0, {
      'name': item['name']!,
      'rate': item['rate']!,
      'currency': d.v('currency'),
    });
  }
  d.values['_customers'] = jsonEncode(customers.take(8).toList());
  // Keep local draft values within the existing 2000-character storage bound.
  while (products.isNotEmpty && jsonEncode(products).length > 1900) {
    products.removeLast();
  }
  d.values['_products'] = jsonEncode(products.take(8).toList());
}
