import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/document_details.dart';
import 'package:jiggo/services/guided_document_model.dart';

void main() {
  test(
    'Proposal never mutates original data and applies only supplied facts',
    () {
      final original = GuidedDocument('CV / Resume')
        ..values.addAll({
          'name': 'Old name',
          'email': 'old@example.com',
          '_input': 'Private unstructured input',
        });
      original.education.add('Real course');
      final proposal = DocumentDetails.parse(original, {
        'values': {'name': 'Confirmed name'},
        'education': <String>[],
        'experience': ['Actual job'],
      });
      final copy = proposal.proposed(original);
      expect(original.v('name'), 'Old name');
      expect(original.experience, isEmpty);
      expect(copy.v('name'), 'Confirmed name');
      expect(copy.education, ['Real course']);
      expect(copy.v('noExperience'), 'no');
      expect(copy.instructions, isNot(contains('Private unstructured input')));
      expect(copy.instructions, isNot(contains('_entry')));
    },
  );
  test('Unknown fields, invalid choices, impossible dates and excessive data are rejected', () {
    for (final values in [
      <String, String>{'apiKey': 'secret'},
      {'mode': 'Invented'},
      {'skills': 'x' * 501},
    ]) {
      expect(
        () => DocumentDetails.parse(GuidedDocument('CV / Resume'), {
          'values': values,
          'education': <String>[],
          'experience': <String>[],
        }),
        throwsFormatException,
      );
    }
    expect(
      () => DocumentDetails.parse(GuidedDocument('Leave Application'), {
        'values': {'start': '2026-02-30'},
        'education': <String>[],
        'experience': <String>[],
      }),
      throwsFormatException,
    );
  });
  test('Non-CV lists and an empty response cannot silently replace a form', () {
    final d = GuidedDocument('Formal Letter');
    expect(
      () => DocumentDetails.parse(d, {
        'values': {'name': 'Name'},
        'education': ['Course'],
        'experience': <String>[],
      }),
      throwsFormatException,
    );
    expect(
      () => DocumentDetails.parse(d, {
        'values': <String, String>{},
        'education': <String>[],
        'experience': <String>[],
      }),
      throwsFormatException,
    );
  });
}
