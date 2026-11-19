import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/document_selections.dart';
import 'package:jiggo/services/guided_document_model.dart';

void main() {
  test('Unselected choices remain empty after a page refresh', () {
    for (final type in guidedDocumentTypes) {
      final d = GuidedDocument(type);
      prepareDocumentSelections(d, fresh: true);
      final restored = GuidedDocument.decode(type, jsonEncode(d.toJson()));
      expect(
        documentSelections(restored)
            .every((s) => selectedOptions(restored, s).isEmpty),
        isTrue,
        reason: type,
      );
    }
  });

  test('Every new document has its own required choices, with no facts preselected', () {
    final signatures = <String>{};
    for (final type in guidedDocumentTypes) {
      final d = GuidedDocument(type);
      prepareDocumentSelections(d, fresh: true);
      final specs = documentSelections(d);
      signatures.add(specs.map((s) => s.id).join(','));
      expect(specs.any((s) => s.required), isTrue);
      expect(
        specs.every((s) => selectedOptions(d, s).isEmpty),
        isTrue,
        reason: type,
      );
      expect(selectionValidation(d), isNotNull);
    }
    expect(signatures.length, 6);
  });
  test(
    'Only selected skills are included; Other is required only while selected',
    () {
      final d = GuidedDocument('CV / Resume');
      prepareDocumentSelections(d, fresh: true);
      final spec = documentSelections(d).firstWhere((s) => s.id == 'skills');
      applyDocumentSelection(d, spec, ['Graphic design', 'Other'], '');
      expect(selectionValidation(d, step: 2), isNotNull);
      applyDocumentSelection(d, spec, [
        'Graphic design',
        'Other',
      ], 'A real skill');
      expect(d.v('skills'), 'Graphic design, A real skill');
      applyDocumentSelection(d, spec, ['Graphic design'], 'A real skill');
      expect(d.v('skills'), isNot(contains('A real skill')));
      expect(d.localContent, isNot(contains('Microsoft Excel')));
      expect(d.instructions, isNot(contains('_pick_')));
    },
  );
  test(
    'Switching document language translates chosen presets, never custom facts',
    () {
      final d = GuidedDocument('Leave Application');
      prepareDocumentSelections(d, fresh: true);
      final reason = documentSelections(d).firstWhere((s) => s.id == 'reason');
      applyDocumentSelection(d, reason, ['Illness'], '');
      d.language = 'Bangla';
      syncSelectionLanguage(d);
      expect(d.v('reason'), isNot('Illness'));
      applyDocumentSelection(d, reason, ['Other'], 'My exact private reason');
      d.language = 'English';
      syncSelectionLanguage(d);
      expect(d.v('reason'), 'My exact private reason');
    },
  );
  test('Invoice catalogue remembers explicit names/rates, is bounded and survives serialization', () {
    final d = GuidedDocument('Invoice')
      ..values.addAll({'buyer': 'Real buyer', 'currency': 'SEK'});
    d.items.single.addAll({'name': 'Real item', 'rate': '25.50'});
    rememberInvoiceChoices(d);
    expect(savedInvoiceCustomers(d), ['Real buyer']);
    expect(savedInvoiceProducts(d).single['currency'], 'SEK');
    final restored = GuidedDocument.decode(d.type, jsonEncode(d.toJson()));
    expect(savedInvoiceProducts(restored).single['rate'], '25.50');
    expect(savedInvoiceProducts(GuidedDocument('Invoice')), isEmpty);
  });
}
