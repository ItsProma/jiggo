import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/guided_document_screen.dart';
import 'package:jiggo/services/guided_document_model.dart';

import 'bd_cv_test.dart' show sampleCv;
import 'guided_document_screen_test.dart' show boot;
import 'support/memory_guided_drafts.dart';

void main() {
  testWidgets(
    'App bar and system Back visit previous steps and persist every field',
    (t) async {
      final store = MemoryGuidedDrafts();
      final doc = sampleCv()..step = 3;
      doc.values['_entry'] = 'form';
      doc.preview = doc.localContent;
      await store.write('A', doc.type, jsonEncode(doc.toJson()));
      await boot(t, doc.type, store);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('Finish your CV'), findsOneWidget);
      expect(find.byType(GuidedDocumentScreen), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('More details'), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('Basic details'), findsOneWidget);
      final saved = GuidedDocument.decode(
        doc.type,
        await store.read('A', doc.type),
      );
      expect(saved.step, 0);
      expect(saved.v('name'), doc.v('name'));
      expect(saved.education, doc.education);
    },
  );
}
