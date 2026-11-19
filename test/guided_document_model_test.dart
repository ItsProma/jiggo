import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/guided_document_model.dart';

void main() {
  test('Invoice rounds each line and tax using exact minor units, including Bangla digits', () {
    final t = InvoiceTotals.calculate(
      [
        {'name': 'Design', 'quantity': '৩', 'rate': '০.১০'},
        {'name': 'Half', 'quantity': '0.5', 'rate': '0.01'},
      ],
      discount: '0.01',
      tax: '10',
    );
    expect(t.lines, [BigInt.from(30), BigInt.one]);
    expect(money(t.subtotal), '0.31');
    expect(money(t.tax), '0.03');
    expect(money(t.total), '0.33');
  });
  test('Invalid invoice values, tax, quantities and excessive discounts are rejected', () {
    final item = {'name': 'Work', 'quantity': '1', 'rate': '20'};
    for (final items in [
      <Map<String, String>>[],
      [...List.generate(21, (_) => item)],
      [
        {...item, 'quantity': '0'},
      ],
      [
        {...item, 'rate': '-1'},
      ],
      [
        {...item, 'rate': '1.001'},
      ],
      [
        {...item, 'name': ''},
      ],
      [
        {...item, 'quantity': 'NaN'},
      ],
    ]) {
      expect(() => InvoiceTotals.calculate(items), throwsFormatException);
    }
    expect(
      () => InvoiceTotals.calculate([item], discount: '21'),
      throwsFormatException,
    );
    expect(
      () => InvoiceTotals.calculate([item], tax: '100.01'),
      throwsFormatException,
    );
  });
  test('Large currency values never use floating point arithmetic', () {
    final t = InvoiceTotals.calculate([
      {'name': 'Work', 'quantity': '99999999.99', 'rate': '99999999.99'},
    ]);
    expect(
      t.total,
      (BigInt.parse('9999999999') * BigInt.parse('9999999999') +
              BigInt.from(50)) ~/
          BigInt.from(100),
    );
  });
  test('Leave dates are inclusive, calendar-based, strict, and reject reverse ranges', () {
    expect(leaveDays('2026-03-28', '2026-03-30'), 3);
    expect(leaveDays('২০২৬-১২-১০', '২০২৬-১২-১২'), 3);
    expect(leaveDays('2024-02-29', '2024-02-29'), 1);
    for (final pair in [
      ('2026-02-29', '2026-03-01'),
      ('2026-12-12', '2026-12-10'),
      ('2026-2-01', '2026-02-02'),
    ]) {
      expect(() => leaveDays(pair.$1, pair.$2), throwsFormatException);
    }
  });
  test(
    'CV renders only supplied facts and omits explicitly excluded experience',
    () {
      final d = GuidedDocument('CV / Resume')
        ..values.addAll({
          'name': 'A Person',
          'email': 'a@example.test',
          'noExperience': 'yes',
          'skills': 'Design',
        });
      d.experience.add('Secret old job');
      d.education.add('User supplied course');
      expect(d.localContent, contains('User supplied course'));
      expect(d.localContent, isNot(contains('Secret old job')));
      expect(d.localContent, isNot(contains('Bachelor')));
      expect(d.validation(), isNull);
      d.values['email'] = '';
      expect(d.validation(), isNotNull);
    },
  );
  test('Draft retains text, repeated inputs, language, design and exact invoice strings', () {
    final d = GuidedDocument('CV / Resume')
      ..language = 'Bangla'
      ..design = 'Modern'
      ..step = 3
      ..preview = 'বাংলা draft'
      ..aiGenerated = true;
    d.values.addAll({'name': 'বাংলা নাম', 'phone': '12345678'});
    d.education.add('College 2022');
    final restored = GuidedDocument.decode(d.type, jsonEncode(d.toJson()));
    expect(restored.toJson(), d.toJson());
    final other = GuidedDocument('Invoice');
    other.items.single.addAll({
      'name': 'Service',
      'quantity': '0.5',
      'rate': '2.30',
    });
    expect(
      GuidedDocument.decode(
        other.type,
        jsonEncode(other.toJson()),
      ).items.single['rate'],
      '2.30',
    );
  });
  test('Corrupt, mismatched and oversized drafts are rejected without reinterpreting them', () {
    final d = GuidedDocument('Invoice');
    for (final raw in [
      'not json',
      jsonEncode({...d.toJson(), 'type': 'CV / Resume'}),
      jsonEncode({...d.toJson(), 'items': []}),
      jsonEncode({
        ...d.toJson(),
        'values': {'x': 'a' * 2001},
      }),
      'x' * 100001,
    ]) {
      expect(() => GuidedDocument.decode('Invoice', raw), throwsA(anything));
    }
  });
  test(
    'Invoice text uses calculated totals and explicitly selected Paid state',
    () {
      final d = GuidedDocument('Invoice')
        ..values.addAll({
          'seller': 'Seller',
          'buyer': 'Buyer',
          'date': '2026-11-19',
          'currency': 'SEK',
          'status': 'Paid',
          'discount': '5',
          'tax': '25',
        });
      d.items.single.addAll({'name': 'Service', 'quantity': '2', 'rate': '10'});
      expect(d.validation(), isNull);
      expect(d.localContent, contains('SEK 18.75'));
      expect(d.localContent, contains('Amount due: SEK 0.00'));
    },
  );
  test('Guided AI prompt carries only nonempty data and explicit no-invention instructions', () {
    final d = GuidedDocument('Job Application')
      ..values.addAll({
        'name': 'Applicant',
        'role': 'Assistant',
        'company': 'Company',
        'qualification': 'Real skill',
        'jobAd': 'Five years required',
        'empty': '',
      });
    expect(d.instructions, contains('Do not invent'));
    expect(
      d.instructions,
      contains('Do not include job-ad text as applicant achievements'),
    );
    expect(d.instructions, isNot(contains('"empty"')));
  });
}
