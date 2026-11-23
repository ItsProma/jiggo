import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/guided_document_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/guided_document_model.dart';
import 'package:jiggo/services/document_selections.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'guided_document_screen_test.dart' show boot, tap, enter, next, Gateway;
import 'support/memory_guided_drafts.dart';
import 'support/memory_settings_store.dart';

Future<void> pick(WidgetTester t, String field, String option) async {
  t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
  await t.pumpAndSettle();
  await tap(t, find.byKey(ValueKey('select-$field-$option')));
}

void main() {
  testWidgets(
    'New CV starts unselected; education is added from short fields and selected skills reach preview',
    (t) async {
      final store = MemoryGuidedDrafts();
      final gateway = Gateway();
      await boot(t, 'CV / Resume', store, gateway: gateway);
      expect(
        t
            .widget<FilterChip>(
              find.byKey(const ValueKey('select-mode-Student')),
            )
            .selected,
        isFalse,
      );
      await pick(t, 'mode', 'Student');
      await enter(t, 'name', 'Actual Name');
      await enter(t, 'email', 'a@example.com');
      await next(t);
      await tap(t, find.text('Add education'));
      await tap(t, find.text('HSC'));
      await t.enterText(
        find.byKey(const ValueKey('education-institution')),
        'Actual College',
      );
      await tap(t, find.widgetWithText(FilledButton, 'Add'));
      expect(find.textContaining('Actual College'), findsWidgets);
      await next(t);
      await pick(t, 'skills', 'Microsoft Word');
      await next(t);
      expect(gateway.calls, 0);
      expect(find.text('Preview'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final d = GuidedDocument.decode(
        'CV / Resume',
        await store.read('A', 'CV / Resume'),
      );
      expect(d.preview, contains('Microsoft Word'));
      expect(d.preview, isNot(contains('Microsoft Excel')));
    },
  );
  testWidgets(
    'Other opens a short input, and picking a preset removes the custom reason from facts',
    (t) async {
      final store = MemoryGuidedDrafts();
      final d = GuidedDocument('Leave Application')
        ..step = 1
        ..values.addAll({
          'name': 'Name',
          'institution': 'College',
          'recipient': 'Principal',
          'context': 'College',
          'start': '2026-11-20',
          'end': '2026-11-22',
        });
      await store.write('A', d.type, jsonEncode(d.toJson()));
      await boot(t, d.type, store);
      expect(find.byKey(const ValueKey('guided-reason')), findsNothing);
      await pick(t, 'reason', 'Other');
      await enter(t, 'reason', 'Private custom reason');
      await pick(t, 'reason', 'Illness');
      expect(find.byKey(const ValueKey('guided-reason')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final saved = GuidedDocument.decode(
        d.type,
        await store.read('A', d.type),
      );
      expect(saved.v('reason'), 'Illness');
      expect(saved.instructions, isNot(contains('Private custom reason')));
    },
  );
  testWidgets(
    'Invoice remembered customers/items can be explicitly chosen in a fresh form',
    (t) async {
      final store = MemoryGuidedDrafts();
      final d = GuidedDocument('Invoice')
        ..values.addAll({'buyer': 'Saved buyer', 'currency': 'SEK'});
      d.items.single.addAll({'name': 'Saved service', 'rate': '25.50'});
      rememberInvoiceChoices(d);
      final fresh = GuidedDocument('Invoice');
      prepareDocumentSelections(fresh, fresh: true);
      fresh.values['_customers'] = d.v('_customers');
      fresh.values['_products'] = d.v('_products');
      await store.write('A', fresh.type, jsonEncode(fresh.toJson()));
      await boot(t, fresh.type, store);
      await tap(t, find.text('Choose saved customer'));
      await tap(t, find.text('Saved buyer'));
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('guided-buyer')))
            .controller!
            .text,
        'Saved buyer',
      );
      await pick(t, 'currency', 'SEK');
      await pick(t, 'status', 'Unpaid');
      await enter(t, 'seller', 'Seller');
      // Reopen at the items step with a real date to isolate the product chooser.
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final saved = GuidedDocument.decode(
        'Invoice',
        await store.read('A', 'Invoice'),
      )..step = 1;
      saved.values['date'] = '2026-11-19';
      await store.write('A', saved.type, jsonEncode(saved.toJson()));
      await boot(t, saved.type, store);
      await tap(t, find.text('Choose saved item'));
      await tap(t, find.text('Saved service · SEK 25.50'));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final result = GuidedDocument.decode(
        'Invoice',
        await store.read('A', 'Invoice'),
      );
      expect(result.items.single['name'], 'Saved service');
      expect(result.items.single['rate'], '25.50');
    },
  );
  testWidgets(
    'Remember invoice stores the local catalogue and Start new keeps it without selecting values',
    (t) async {
      final store = MemoryGuidedDrafts();
      final d = GuidedDocument('Invoice')
        ..step = 2
        ..values.addAll({
          'seller': 'Seller',
          'buyer': 'Buyer',
          'date': '2026-11-19',
          'currency': 'SEK',
          'status': 'Unpaid',
        });
      d.items.single.addAll({
        'name': 'Actual service',
        'rate': '50',
        'quantity': '1',
      });
      await store.write('A', d.type, jsonEncode(d.toJson()));
      await boot(t, d.type, store);
      await tap(t, find.text('Remember customer and items'));
      expect(
        find.text('Customer and items remembered on this device.'),
        findsWidgets,
      );
      await tap(t, find.byTooltip('Document options'));
      await tap(t, find.text('Start new'));
      await tap(t, find.widgetWithText(FilledButton, 'Start new'));
      expect(
        t
            .widget<FilterChip>(
              find.byKey(const ValueKey('select-currency-SEK')),
            )
            .selected,
        isFalse,
      );
      await tap(t, find.text('Choose saved customer'));
      expect(find.text('Buyer'), findsOneWidget);
      await tap(t, find.text('Buyer'));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      final saved = GuidedDocument.decode(
        'Invoice',
        await store.read('A', 'Invoice'),
      );
      expect(savedInvoiceProducts(saved).single['name'], 'Actual service');
      expect(saved.v('currency'), '');
    },
  );
  for (final type in guidedDocumentTypes) {
    for (final language in ['en', 'bn']) {
      testWidgets(
        'Selection form fits small screens and large type: $type $language',
        (t) async {
          await t.binding.setSurfaceSize(const Size(320, 700));
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(
            settingsApp(
              AppSettings(store: MemorySettingsStore(), language: language),
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
                child: GuidedDocumentScreen(
                  documentType: type,
                  ownerId: 'A',
                  store: MemoryGuidedDrafts(),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const ValueKey('guided-next')),
            150,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 60,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
