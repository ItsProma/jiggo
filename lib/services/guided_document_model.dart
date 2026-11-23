import 'dart:convert';

import 'document_brief.dart';
import 'cv_education.dart';

const guidedDocumentTypes = [
  'CV / Resume',
  'Job Application',
  'Leave Application',
  'Formal Letter',
  'Invoice',
  'Assignment',
];

class GuidedField {
  final String id, label, hint;
  final int step, max;
  final bool required, multiline;
  const GuidedField(
    this.id,
    this.label,
    this.hint, {
    this.step = 0,
    this.max = 120,
    this.required = false,
    this.multiline = false,
  });
}

class GuidedDocument {
  final String type;
  String language = 'English', design = 'Simple', preview = '', cvPhoto = '';
  int step = 0;
  bool aiGenerated = false;
  final Map<String, String> values = {};
  final List<String> education = [], experience = [];
  final List<Map<String, String>> items = [
    {'name': '', 'quantity': '1', 'rate': ''},
  ];
  GuidedDocument(this.type) {
    if (!guidedDocumentTypes.contains(type)) {
      throw const FormatException('document-type');
    }
    switch (type) {
      case 'CV / Resume':
        design = 'BD Traditional';
        values.addAll({'mode': 'Student', 'noExperience': 'yes'});
      case 'Leave Application':
        values['context'] = 'School';
      case 'Formal Letter':
        values['purpose'] = 'Request';
      case 'Invoice':
        values.addAll({'currency': 'BDT', 'status': 'Unpaid'});
      case 'Assignment':
        values['length'] = '500';
    }
  }
  bool get bn => language == 'Bangla';
  String get title => values['title']?.trim().isNotEmpty == true
      ? values['title']!.trim()
      : DocumentBrief(type).title(language);
  String v(String key) => values[key]?.trim() ?? '';
  String label(String en, String bn) => this.bn ? bn : en;
  List<GuidedField> get fields => switch (type) {
    'CV / Resume' => const [
      GuidedField(
        'name',
        'Your name',
        'Name as it should appear',
        required: true,
      ),
      GuidedField(
        'email',
        'Email address',
        'Optional if you provide a phone number',
      ),
      GuidedField('phone', 'Phone number', 'Optional if you provide an email'),
      GuidedField('role', 'Target job', 'For example: Graphic Designer'),
      GuidedField(
        'cvAddress',
        'Present address',
        'Optional',
        max: 300,
        multiline: true,
      ),
      GuidedField('cvDob', 'Date of birth', 'Optional: YYYY-MM-DD', max: 10),
      GuidedField('cvNationality', 'Nationality', 'Optional', max: 80),
      GuidedField(
        'cvPersonal',
        'Additional personal details',
        'Optional: details you want to include',
        max: 500,
        multiline: true,
      ),
      GuidedField(
        'cvTravel',
        'Travel details',
        'Optional: details relevant to your application',
        max: 300,
        multiline: true,
      ),
      GuidedField(
        'cvHobbies',
        'Hobbies',
        'Optional',
        step: 2,
        max: 200,
        multiline: true,
      ),

      GuidedField(
        'cvObjective',
        'Career objective',
        'Optional: what role do you want?',
        step: 2,
        max: 600,
        multiline: true,
      ),
      GuidedField(
        'cvReferences',
        'References',
        'Optional: names and contact details you can share',
        step: 2,
        max: 600,
        multiline: true,
      ),
      GuidedField(
        'skills',
        'Skills',
        'For example: Photoshop, customer service',
        step: 2,
        max: 500,
        multiline: true,
      ),
      GuidedField(
        'languages',
        'Languages you know',
        'For example: Bangla, English',
        step: 2,
        max: 200,
      ),
      GuidedField(
        'projects',
        'Projects or training',
        'Optional: include only your real work or training',
        step: 2,
        max: 500,
        multiline: true,
      ),
    ],
    'Job Application' => const [
      GuidedField(
        'name',
        'Your name',
        'Name as it should appear',
        required: true,
      ),
      GuidedField('email', 'Email address', 'Optional'),
      GuidedField('phone', 'Phone number', 'Optional'),
      GuidedField(
        'role',
        'Job title',
        'Which job are you applying for?',
        required: true,
      ),
      GuidedField(
        'company',
        'Company name',
        'Where are you applying?',
        required: true,
      ),
      GuidedField(
        'qualification',
        'Your qualifications',
        'Education or skills relevant to this job',
        step: 1,
        required: true,
        max: 600,
        multiline: true,
      ),
      GuidedField(
        'experience',
        'Relevant experience',
        'Write No experience if this is your first job',
        step: 1,
        max: 500,
        multiline: true,
      ),
      GuidedField(
        'jobAd',
        'Job advertisement',
        'Optional: paste the important requirements',
        step: 1,
        max: 2000,
        multiline: true,
      ),
    ],
    'Leave Application' => const [
      GuidedField(
        'name',
        'Your name',
        'Name as it should appear',
        required: true,
      ),
      GuidedField(
        'institution',
        'School, college or workplace',
        'Institution name',
        required: true,
      ),
      GuidedField(
        'recipient',
        'Who will receive it?',
        'For example: Class teacher or Manager',
        required: true,
      ),
      GuidedField(
        'start',
        'Leave starts',
        'YYYY-MM-DD',
        step: 1,
        required: true,
      ),
      GuidedField('end', 'Leave ends', 'YYYY-MM-DD', step: 1, required: true),
      GuidedField(
        'reason',
        'Reason for leave',
        'Share only what the recipient needs to know',
        step: 1,
        max: 600,
        multiline: true,
        required: true,
      ),
    ],
    'Formal Letter' => const [
      GuidedField(
        'recipient',
        'Recipient name or role',
        'For example: Manager',
        required: true,
      ),
      GuidedField('organization', 'Recipient organization', 'Optional'),
      GuidedField(
        'name',
        'Your name',
        'Name as it should appear',
        required: true,
      ),
      GuidedField(
        'address',
        'Your address',
        'Optional: include only if needed',
        max: 200,
        multiline: true,
      ),
      GuidedField(
        'subject',
        'Letter subject',
        'What is the letter about?',
        step: 1,
        required: true,
      ),
      GuidedField(
        'message',
        'What would you like to say?',
        'Describe your request or problem',
        step: 1,
        max: 1200,
        multiline: true,
        required: true,
      ),
      GuidedField('date', 'Letter date', 'Optional: YYYY-MM-DD', step: 1),
    ],
    'Invoice' => const [
      GuidedField(
        'seller',
        'Business or seller name',
        'Who is issuing this invoice?',
        required: true,
      ),
      GuidedField(
        'sellerContact',
        'Seller contact',
        'Email or phone number',
        max: 180,
      ),
      GuidedField(
        'buyer',
        'Customer name',
        'Who is this invoice for?',
        required: true,
      ),
      GuidedField('number', 'Invoice number', 'Optional: your own reference'),
      GuidedField('date', 'Invoice date', 'YYYY-MM-DD', required: true),
      GuidedField(
        'notes',
        'Notes',
        'Optional: payment instructions',
        step: 2,
        max: 300,
        multiline: true,
      ),
    ],
    _ => const [
      GuidedField('subject', 'Subject', 'For example: Biology', required: true),
      GuidedField(
        'level',
        'Class or course',
        'For example: HSC or Nursing',
        required: true,
      ),
      GuidedField(
        'question',
        'Assignment question',
        'Type, paste or read it from a photo',
        required: true,
        max: 2000,
        multiline: true,
      ),
      GuidedField(
        'instructions',
        'Teacher instructions',
        'Optional: required sections or special rules',
        step: 1,
        max: 1000,
        multiline: true,
      ),
      GuidedField(
        'sources',
        'Sources you already have',
        'Optional: real book titles or links',
        step: 1,
        max: 800,
        multiline: true,
      ),
      GuidedField(
        'outline',
        'Review your outline',
        'Edit the sections before creating the draft',
        step: 2,
        max: 900,
        multiline: true,
        required: true,
      ),
    ],
  };
  String? validation({int? onlyStep}) {
    for (final field in fields) {
      if (onlyStep != null && field.step != onlyStep) continue;
      if (field.required && v(field.id).isEmpty) {
        return 'Complete the required fields.';
      }
      if (v(field.id).length > field.max) {
        return 'Some details are too long. Shorten them to continue.';
      }
    }
    if ((onlyStep == null || onlyStep == 0) &&
        type == 'CV / Resume' &&
        v('email').isEmpty &&
        v('phone').isEmpty) {
      return 'Add an email address or phone number.';
    }
    if (type == 'Leave Application' && (onlyStep == null || onlyStep == 1)) {
      try {
        leaveDays(v('start'), v('end'));
      } catch (_) {
        return 'Choose valid leave dates. The end must not be before the start.';
      }
    }
    if (type == 'Formal Letter' &&
        v('date').isNotEmpty &&
        (onlyStep == null || onlyStep == 1)) {
      try {
        parseDocumentDate(v('date'));
      } catch (_) {
        return 'Choose a valid date.';
      }
    }
    if (type == 'Invoice') {
      if (onlyStep == null || onlyStep == 0) {
        try {
          parseDocumentDate(v('date'));
        } catch (_) {
          return 'Choose a valid date.';
        }
      }
      if (onlyStep == null || onlyStep >= 1) {
        try {
          invoice;
        } catch (_) {
          return 'Check item names, quantities, prices, discount and tax.';
        }
      }
    }
    return null;
  }

  InvoiceTotals get invoice =>
      InvoiceTotals.calculate(items, discount: v('discount'), tax: v('tax'));
  String get instructions {
    final data = jsonEncode({
      if (type == 'CV / Resume' && preview.isNotEmpty)
        'draftToImprove': preview,
      'facts': {
        for (final e in values.entries)
          if (!e.key.startsWith('_') && e.value.trim().isNotEmpty)
            e.key: e.value.trim(),
      },
      if (education.isNotEmpty)
        'education': education.map((e) => readCvEducation(e) ?? e).toList(),
      if (v('noExperience') != 'yes' && experience.isNotEmpty)
        'workExperience': experience,
      if (type == 'Leave Application')
        'calendarDaysInclusive': leaveDays(v('start'), v('end')),
    });
    return 'Create this $type using ONLY the supplied facts. Do not invent degrees, skills, experience, dates, statistics or citations. Omit missing optional details. Do not include job-ad text as applicant achievements. Assignment: follow the reviewed outline, distinguish supplied sources from sources not verified, and never fabricate references. Data: $data';
  }

  String get localContent {
    if (type == 'CV / Resume') {
      return [
        '# ${safe(v('name'))}',
        [
          if (v('role').isNotEmpty) '**${safe(v('role'))}**',
          [
            v('email'),
            v('phone'),
          ].where((s) => s.isNotEmpty).map(safe).join(' · '),
          if (v('cvAddress').isNotEmpty)
            '${label('Address', 'ঠিকানা')}: ${safe(v('cvAddress'))}',
        ].where((s) => s.isNotEmpty).join('\n'),
        if (v('cvObjective').isNotEmpty)
          '## ${label('Career Objective', 'পেশাগত লক্ষ্য')}\n\n${safe(v('cvObjective'))}',
        if (education.isNotEmpty)
          '## ${label('Educational Qualifications', 'শিক্ষাগত যোগ্যতা')}\n\n${['BD Traditional', 'Modern Sidebar', 'BD Classic'].contains(design) ? cvEducationMarkdown(education, bn) : education.map((s) => '- ${safe(cvEducationSummary(s))}').join('\n')}',
        if (v('noExperience') != 'yes' && experience.isNotEmpty)
          '## ${label('Experience', 'অভিজ্ঞতা')}\n\n${experience.map((s) => '- ${safe(s)}').join('\n')}',
        if (v('skills').isNotEmpty)
          '## ${label('Skills', 'দক্ষতা')}\n\n${safe(v('skills'))}',
        if (v('languages').isNotEmpty)
          '## ${label('Languages', 'ভাষা')}\n\n${safe(v('languages'))}',
        if (v('projects').isNotEmpty)
          '## ${label('Projects and training', 'প্রজেক্ট ও প্রশিক্ষণ')}\n\n${safe(v('projects'))}',
        if (v('cvDob').isNotEmpty ||
            v('cvNationality').isNotEmpty ||
            v('cvPersonal').isNotEmpty)
          '## ${label('Personal Information', 'ব্যক্তিগত তথ্য')}\n\n${[if (v('cvDob').isNotEmpty) '${label('Date of Birth', 'জন্মতারিখ')}: ${safe(v('cvDob'))}', if (v('cvNationality').isNotEmpty) '${label('Nationality', 'জাতীয়তা')}: ${safe(v('cvNationality'))}', if (v('cvPersonal').isNotEmpty) safe(v('cvPersonal'))].join('\n\n')}',
        if (v('cvTravel').isNotEmpty)
          '## ${label('Travel Details', 'ভ্রমণসংক্রান্ত তথ্য')}\n\n${safe(v('cvTravel'))}',
        if (v('cvHobbies').isNotEmpty)
          '## ${label('Hobbies', 'শখ')}\n\n${safe(v('cvHobbies'))}',
        if (v('cvReferences').isNotEmpty)
          '## ${label('References', 'তথ্যসূত্র / রেফারেন্স')}\n\n${safe(v('cvReferences'))}',
        if (v('_cvDeclaration') == 'yes')
          '## ${label('Declaration', 'ঘোষণা')}\n\n${label('I declare that the information provided in this CV is true to the best of my knowledge.', 'আমার জানা মতে এই জীবনবৃত্তান্তের সব তথ্য সত্য।')}\n\n${label('Signature', 'স্বাক্ষর')}: ____________________\n\n${safe(v('name'))}',
      ].where((s) => s.isNotEmpty).join('\n\n');
    }
    if (type != 'Invoice') throw StateError('ai-document');
    final totals = invoice,
        currency = v('currency').isEmpty ? 'BDT' : v('currency');
    final lines = <String>[
      '## ${safe(v('seller'))}',
      safe(v('sellerContact')),
      '${label('Customer', 'ক্রেতা')}: ${safe(v('buyer'))}',
      if (v('number').isNotEmpty)
        '${label('Invoice number', 'ইনভয়েস নম্বর')}: ${safe(v('number'))}',
      '${label('Date', 'তারিখ')}: ${v('date')}',
      '${label('Status', 'অবস্থা')}: ${v('status') == 'Paid' ? label('Paid', 'পরিশোধিত') : label('Unpaid', 'অপরিশোধিত')}',
    ];
    for (var i = 0; i < items.length; i++) {
      lines.add(
        '### ${i + 1}. ${safe(items[i]['name'] ?? '')}\n\n${label('Quantity', 'পরিমাণ')}: ${items[i]['quantity']} · ${label('Unit price', 'একক মূল্য')}: $currency ${money(parseFixed(items[i]['rate'] ?? ''))}\n\n**${label('Amount', 'মূল্য')}: $currency ${money(totals.lines[i])}**',
      );
    }
    lines.add(
      '## ${label('Totals', 'হিসাব')}\n\n${label('Subtotal', 'উপমোট')}: $currency ${money(totals.subtotal)}\n\n${label('Discount', 'ছাড়')}: $currency ${money(totals.discount)}\n\n${label('Tax', 'কর')}: $currency ${money(totals.tax)}\n\n**${label('Total', 'সর্বমোট')}: $currency ${money(totals.total)}**\n\n${label('Amount due', 'বকেয়া')}: $currency ${money(v('status') == 'Paid' ? BigInt.zero : totals.total)}',
    );
    if (v('notes').isNotEmpty) {
      lines.add('${label('Notes', 'মন্তব্য')}: ${safe(v('notes'))}');
    }
    return lines.where((s) => s.isNotEmpty).join('\n\n');
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'type': type,
    'language': language,
    'design': design,
    'step': step,
    'values': values,
    'education': education,
    'experience': experience,
    'items': items,
    'preview': preview,
    'aiGenerated': aiGenerated,
    'cvPhoto': cvPhoto,
  };
  static GuidedDocument decode(String type, String? raw) {
    final result = GuidedDocument(type);
    if (raw == null) return result;
    if (raw.length > 220000) throw const FormatException('draft-size');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['v'] != 1 || j['type'] != type) {
      throw const FormatException('draft-version');
    }
    if (j['values'] is! Map || j['items'] is! List) {
      throw const FormatException('draft-data');
    }
    final values = Map<String, String>.from(j['values']);
    if (values.length > 40 ||
        values.entries.any((e) => e.key.length > 40 || e.value.length > 2000)) {
      throw const FormatException('draft-values');
    }
    result.values
      ..clear()
      ..addAll(values);
    for (final entry in [
      ('education', result.education),
      ('experience', result.experience),
    ]) {
      final data = List<String>.from(j[entry.$1] ?? []);
      if (data.length > 8 ||
          data.any((s) => s.length > (entry.$1 == 'education' ? 1000 : 500))) {
        throw const FormatException('draft-entries');
      }
      entry.$2.addAll(data);
    }
    final items = (j['items'] as List)
        .map((v) => Map<String, String>.from(v as Map))
        .toList();
    if (items.isEmpty ||
        items.length > 20 ||
        items.any(
          (i) =>
              i.length != 3 ||
              !i.keys.toSet().containsAll(['name', 'quantity', 'rate']) ||
              i.values.any((s) => s.length > 120),
        )) {
      throw const FormatException('draft-items');
    }
    result.items
      ..clear()
      ..addAll(items);
    result.aiGenerated = j['aiGenerated'] == true;
    result.language = ['Bangla', 'English'].contains(j['language'])
        ? j['language']
        : 'English';
    result.design =
        [
          'Simple',
          'Modern',
          'BD Traditional',
          'Modern Sidebar',
          'BD Classic',
        ].contains(j['design'])
        ? j['design']
        : (type == 'CV / Resume' ? 'BD Traditional' : 'Simple');
    final photo = j['cvPhoto'] ?? '';
    if (photo is! String ||
        photo.length > 90000 ||
        (type != 'CV / Resume' && photo.isNotEmpty)) {
      throw const FormatException('cv-photo');
    }
    if (photo.isNotEmpty) {
      final bytes = base64Decode(photo);
      if (bytes.length < 3 ||
          bytes[0] != 255 ||
          bytes[1] != 216 ||
          bytes[2] != 255) {
        throw const FormatException('cv-photo');
      }
    }
    result.cvPhoto = photo;
    result.preview = j['preview'] is String && j['preview'].length <= 20000
        ? j['preview']
        : '';
    result.step = j['step'] is int
        ? (j['step'] as int).clamp(0, result.preview.isEmpty ? 2 : 3)
        : 0;
    return result;
  }
}

String safe(String s) => s
    .replaceAllMapped(RegExp(r'([\\`*_{}\[\]<>#+!|])'), (m) => '\\${m[0]}')
    .replaceAll('\r', '');
String asciiDigits(String s) {
  const bn = '০১২৩৪৫৬৭৮৯';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(bn[i], '$i');
  }
  return s;
}

DateTime parseDocumentDate(String value) {
  final s = asciiDigits(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    throw const FormatException('date');
  }
  final parts = s.split('-').map(int.parse).toList();
  final d = DateTime.utc(parts[0], parts[1], parts[2]);
  if (d.year != parts[0] ||
      d.month != parts[1] ||
      d.day != parts[2] ||
      d.year < 2000 ||
      d.year > 2100) {
    throw const FormatException('date');
  }
  return d;
}

int leaveDays(String start, String end) {
  final days =
      parseDocumentDate(end).difference(parseDocumentDate(start)).inDays + 1;
  if (days < 1 || days > 3660) throw const FormatException('leave-range');
  return days;
}

BigInt parseFixed(String raw, {bool emptyZero = false}) {
  final s = asciiDigits(raw.trim());
  if (s.isEmpty && emptyZero) return BigInt.zero;
  if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(s)) {
    throw const FormatException('decimal');
  }
  final parts = s.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
}

String money(BigInt minor) =>
    '${minor ~/ BigInt.from(100)}.${(minor % BigInt.from(100)).toString().padLeft(2, '0')}';

class InvoiceTotals {
  final List<BigInt> lines;
  final BigInt subtotal, discount, tax, total;
  const InvoiceTotals(
    this.lines,
    this.subtotal,
    this.discount,
    this.tax,
    this.total,
  );
  factory InvoiceTotals.calculate(
    List<Map<String, String>> items, {
    String discount = '',
    String tax = '',
  }) {
    if (items.isEmpty || items.length > 20) {
      throw const FormatException('items');
    }
    final lines = <BigInt>[];
    for (final item in items) {
      if ((item['name'] ?? '').trim().isEmpty ||
          (item['name'] ?? '').length > 120) {
        throw const FormatException('item-name');
      }
      final q = parseFixed(item['quantity'] ?? ''),
          r = parseFixed(item['rate'] ?? '');
      if (q <= BigInt.zero) throw const FormatException('quantity');
      lines.add((q * r + BigInt.from(50)) ~/ BigInt.from(100));
    }
    final subtotal = lines.fold(BigInt.zero, (a, b) => a + b),
        disc = parseFixed(discount, emptyZero: true),
        pct = parseFixed(tax, emptyZero: true);
    if (disc > subtotal || pct > BigInt.from(10000)) {
      throw const FormatException('discount-tax');
    }
    final taxValue =
        ((subtotal - disc) * pct + BigInt.from(5000)) ~/ BigInt.from(10000);
    return InvoiceTotals(
      lines,
      subtotal,
      disc,
      taxValue,
      subtotal - disc + taxValue,
    );
  }
}
