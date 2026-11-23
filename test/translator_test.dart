import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/translator_screen.dart';
import 'package:jiggo/services/translation_gateway.dart';

class Gateway implements TranslationGateway {
  int calls = 0;
  bool fail = false;
  List<String>? args;
  @override
  Future<Map<String, dynamic>> translate(
    String text,
    String source,
    String target,
  ) async {
    calls++;
    args = [text, source, target];
    if (fail) throw Exception('offline');
    return {'text': 'হ্যালো', 'remainingToday': 9};
  }
}

Future<void> press(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Translator validates, swaps output into the next input and invalidates stale results',
    (t) async {
      final g = Gateway();
      await t.pumpWidget(MaterialApp(home: TranslatorScreen(gateway: g)));
      await press(t, find.byKey(const ValueKey('translate-send')));
      expect(g.calls, 0);
      await t.enterText(find.byKey(const ValueKey('translate-input')), 'Hello');
      await press(t, find.byKey(const ValueKey('translate-send')));
      expect(g.args, ['Hello', 'en', 'bn']);
      expect(find.text('হ্যালো'), findsOneWidget);
      await press(t, find.byKey(const ValueKey('translate-swap')));
      expect(find.byType(SelectableText), findsNothing);
      await press(t, find.byKey(const ValueKey('translate-send')));
      expect(g.args, ['হ্যালো', 'bn', 'en']);
      g.fail = true;
      await t.enterText(
        find.byKey(const ValueKey('translate-input')),
        'Keep this',
      );
      await press(t, find.byKey(const ValueKey('translate-send')));
      expect(find.textContaining('Your text is kept'), findsOneWidget);
      expect(find.text('Keep this'), findsOneWidget);
    },
  );
  testWidgets('Languages fit a narrow screen with larger text', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: TranslatorScreen(gateway: Gateway()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
