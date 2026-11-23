import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/document_speech.dart';
import 'package:jiggo/widgets/document_voice_dialog.dart';

import 'document_maker_test.dart' show FakeDocumentSpeech;

class Speech extends FakeDocumentSpeech implements SpeechFailureInfo {
  @override
  String? lastFailure;
}

void main() {
  test('Speech distinguishes permission, service network, silence and language failures', () {
    expect(
      speechFailureMessage('not-allowed'),
      contains('permission is blocked'),
    );
    expect(
      speechFailureMessage('error_network'),
      contains('could not connect'),
    );
    expect(speechFailureMessage('error_no_match'), contains('No speech'));
    expect(
      speechFailureMessage('error_language_not_supported'),
      contains('language is unavailable'),
    );
  });
  testWidgets(
    'Speech failure keeps the transcript, displays a precise cause and retries',
    (t) async {
      final speech = Speech();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentVoiceDialog(
              speech: speech,
              initialLanguage: 'bn',
              maxCharacters: 2000,
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('voice-start-stop')));
      await t.pumpAndSettle();
      speech.text!('আমার আবেদন');
      speech.lastFailure = speechFailureMessage('error_network');
      speech.error!();
      await t.pumpAndSettle();
      expect(find.textContaining('could not connect'), findsOneWidget);
      expect(find.text('আমার আবেদন'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(speech.starts, 2);
      expect(speech.locale, 'bn_BD');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      expect(speech.cancellations, greaterThan(0));
    },
  );
}
