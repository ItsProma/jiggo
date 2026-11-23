import 'dart:convert';

import 'guided_document_model.dart';

/// Validated proposal only. The caller must ask before applying it to a form.
class DocumentDetails {
  final Map<String, String> values;
  final List<String> education, experience;
  DocumentDetails._(this.values, this.education, this.experience);

  static DocumentDetails parse(GuidedDocument document, Object? raw) {
    if (raw is! Map ||
        raw.keys.any(
          (key) => !['values', 'education', 'experience'].contains(key),
        )) {
      throw const FormatException('details-shape');
    }
    final values = Map<String, String>.from(raw['values'] as Map);
    final fields = {for (final f in document.fields) f.id: f.max};
    final choices = switch (document.type) {
      'CV / Resume' => {
        'mode': ['Student', 'First job', 'Experienced'],
        'noExperience': ['yes', 'no'],
      },
      'Leave Application' => {
        'context': ['School', 'College', 'Office'],
      },
      'Formal Letter' => {
        'purpose': ['Request', 'Complaint', 'Permission', 'Other'],
      },
      'Assignment' => {
        'length': ['250', '500', '1000', '1500'],
      },
      _ => <String, List<String>>{},
    };
    for (final e in values.entries) {
      if ((!fields.containsKey(e.key) && !choices.containsKey(e.key)) ||
          e.value.trim().isEmpty ||
          e.value.length > (fields[e.key] ?? 30) ||
          (choices.containsKey(e.key) && !choices[e.key]!.contains(e.value))) {
        throw const FormatException('details-field');
      }
      if (['date', 'start', 'end'].contains(e.key)) parseDocumentDate(e.value);
    }
    final education = List<String>.from(raw['education'] as List);
    final experience = List<String>.from(raw['experience'] as List);
    for (final list in [education, experience]) {
      if (list.length > 8 ||
          list.any((s) => s.trim().isEmpty || s.length > 500) ||
          (document.type != 'CV / Resume' && list.isNotEmpty)) {
        throw const FormatException('details-list');
      }
    }
    if (values.isEmpty && education.isEmpty && experience.isEmpty) {
      throw const FormatException('details-empty');
    }
    return DocumentDetails._(values, education, experience);
  }

  GuidedDocument proposed(GuidedDocument source) {
    final copy = GuidedDocument.decode(
      source.type,
      jsonEncode(source.toJson()),
    );
    copy.values.addAll(values);
    for (final key in values.keys) {
      copy.values.remove('_pick_$key');
      copy.values.remove('_other_$key');
    }
    if (education.isNotEmpty) {
      copy.education
        ..clear()
        ..addAll(education);
    }
    if (experience.isNotEmpty) {
      copy.experience
        ..clear()
        ..addAll(experience);
      if (!values.containsKey('noExperience')) {
        copy.values['noExperience'] = 'no';
      }
    }
    copy.preview = '';
    copy.aiGenerated = false;
    copy.values['_entry'] = 'form';
    copy.step = 0;
    return copy;
  }
}
