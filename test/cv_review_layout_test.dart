import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/guided_document_model.dart';

import 'bd_cv_test.dart' show sampleCv;
import 'guided_document_screen_test.dart' show boot, tap;
import 'support/memory_guided_drafts.dart';

void main() {
  testWidgets(
    'CV review keeps optional facts hidden, selectable skills and a visible preview action',
    (t) async {
      await t.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final store = MemoryGuidedDrafts();
      final doc = sampleCv()..step = 2;
      doc.values['cvHobbies'] = 'Reading';
      await store.write('A', doc.type, jsonEncode(doc.toJson()));
      await boot(t, doc.type, store);
      expect(find.text('Finish your CV'), findsOneWidget);
      expect(
        find.text('Use a simple career objective').hitTestable(),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('guided-next')).hitTestable(),
        findsOneWidget,
      );
      await tap(t, find.byKey(const ValueKey('select-skills-Microsoft Excel')));
      await tap(t, find.byKey(const ValueKey('select-languages-Swedish')));
      await tap(t, find.byKey(const ValueKey('cv-extra-details')));
      expect(find.byKey(const ValueKey('optional-cvHobbies')), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('guided-next')));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final saved = GuidedDocument.decode(
        doc.type,
        await store.read('A', doc.type),
      );
      expect(saved.step, 3);
      expect(saved.v('skills'), contains('Microsoft Excel'));
      expect(saved.v('languages'), contains('Swedish'));
      expect(saved.v('cvHobbies'), 'Reading');
      expect(saved.v('cvObjective'), doc.v('cvObjective'));
      expect(saved.v('_cvDeclaration'), 'yes');
    },
  );
}
