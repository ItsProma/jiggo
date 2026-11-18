import 'support/notification_fakes.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/main.dart';
import 'package:jiggo/services/app_settings.dart';

import 'support/memory_settings_store.dart';

import 'package:jiggo/services/ai_eligibility_service.dart';
import 'package:jiggo/services/release_config.dart';
import 'package:jiggo/widgets/responsive_tools_grid.dart';
import 'package:jiggo/services/auth_service.dart';
import 'package:jiggo/services/ai_limit_messages.dart';
import 'package:jiggo/screens/all_library_items.dart';

LibraryEntry entry(
  String id, {
  String title = 'Document',
  String content = '',
  String type = 'Document',
  String language = 'English',
  DateTime? date,
  bool isDocument = true,
}) {
  return LibraryEntry(
    id: id,
    isDocument: isDocument,
    title: title,
    content: content,
    type: type,
    language: language,
    createdAt: date,
  );
}

void main() {
  testWidgets('Shows loading while checking authentication', (tester) async {
    final controller = StreamController<User?>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      JiggoApp(
        notifications: skippedNotifications(),
        settings: AppSettings(store: MemorySettingsStore(), language: 'en'),
        authStateChanges: controller.stream,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Continue as Guest'), findsNothing);
  });

  testWidgets('Shows login when no user is signed in', (tester) async {
    await tester.pumpWidget(
      JiggoApp(
        notifications: skippedNotifications(),
        settings: AppSettings(store: MemorySettingsStore(), language: 'en'),
        authStateChanges: Stream<User?>.value(null),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Jiggo'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('What can I help you with?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shows an error when authentication stream fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      JiggoApp(
        notifications: skippedNotifications(),
        settings: AppSettings(store: MemorySettingsStore(), language: 'en'),
        authStateChanges: Stream<User?>.error(
          StateError('Test authentication failure'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to check login status.'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('Library search and ordering', () {
    final older = DateTime.utc(2026, 1, 1);
    final newer = DateTime.utc(2026, 1, 2);

    test('Newest first sorts documents and scans together', () {
      final selected = selectLibraryEntries([
        entry('a', date: older),
        entry('b', date: newer, isDocument: false),
      ]);
      expect(selected.map((e) => e.id), ['b', 'a']);
    });

    test('Oldest first reverses chronological ordering', () {
      final selected = selectLibraryEntries([
        entry('b', date: newer),
        entry('a', date: older),
      ], sort: LibrarySort.oldest);
      expect(selected.map((e) => e.id), ['a', 'b']);
    });

    test('Unknown dates stay at the bottom in both chronological orders', () {
      final source = [entry('missing'), entry('dated', date: older)];
      for (final order in [LibrarySort.newest, LibrarySort.oldest]) {
        expect(selectLibraryEntries(source, sort: order).last.id, 'missing');
      }
    });

    test('Title sorting ignores English case in both directions', () {
      final source = [entry('z', title: 'zebra'), entry('a', title: 'Apple')];
      expect(
        selectLibraryEntries(source, sort: LibrarySort.titleAZ).first.id,
        'a',
      );
      expect(
        selectLibraryEntries(source, sort: LibrarySort.titleZA).first.id,
        'z',
      );
    });

    test('Equal titles and dates have deterministic ordering', () {
      final source = [entry('b', date: older), entry('a', date: older)];
      expect(selectLibraryEntries(source).map((e) => e.id), ['a', 'b']);
    });

    test('Search and sorting do not mutate source entries', () {
      final source = [entry('b', title: 'Zebra'), entry('a', title: 'Apple')];
      final selected = selectLibraryEntries(source, sort: LibrarySort.titleAZ);
      expect(selected.first.id, 'a');
      expect(source.first.id, 'b');
    });

    test('Search trims surrounding whitespace and ignores English case', () {
      expect(
        selectLibraryEntries([
          entry('a', title: 'My Resume'),
        ], query: '  RESUME  ').length,
        1,
      );
    });

    test('Bangla content is searchable', () {
      expect(
        selectLibraryEntries([
          entry('a', content: 'ছুটির আবেদন'),
        ], query: 'ছুটির').length,
        1,
      );
    });

    test('Search checks type, language and content as well as title', () {
      final source = [
        entry('a', type: 'Invoice', language: 'Bangla', content: 'Logo design'),
      ];
      for (final query in ['invoice', 'bangla', 'logo']) {
        expect(selectLibraryEntries(source, query: query).length, 1);
      }
    });

    test('Unmatched search and an empty library return no rows', () {
      expect(selectLibraryEntries([entry('a')], query: 'no-match'), isEmpty);
      expect(selectLibraryEntries([]), isEmpty);
    });
  });

  group('Library legacy record handling', () {
    test(
      'Legacy scan without title uses its answer without changing content',
      () {
        final scan = LibraryEntry.fromData(
          id: 's',
          isDocument: false,
          data: {'answer': 'A solution\nwith steps', 'language': 'English'},
        );
        expect(scan.title, 'A solution with steps');
        expect(scan.content, 'A solution\nwith steps');
        expect(scan.collection, 'scanHistory');
      },
    );

    test('Renamed scan uses title while keeping the original answer', () {
      final scan = LibraryEntry.fromData(
        id: 's',
        isDocument: false,
        data: {'title': '  My algebra  ', 'answer': 'Original solution'},
      );
      expect(scan.title, 'My algebra');
      expect(scan.content, 'Original solution');
    });

    test('Malformed optional fields use safe fallbacks', () {
      final document = LibraryEntry.fromData(
        id: 'd',
        isDocument: true,
        data: {
          'title': 123,
          'content': null,
          'createdAt': 'invalid',
          'language': {},
        },
      );
      expect(document.title, 'Untitled document');
      expect(document.content, '');
      expect(document.createdAt, isNull);
      expect(document.language, '');
    });

    test('Empty scan has a readable fallback title', () {
      final scan = LibraryEntry.fromData(id: 's', isDocument: false, data: {});
      expect(scan.title, 'Untitled scan');
    });

    test('Document and scan IDs do not collide in pending-action keys', () {
      expect(entry('same').key, isNot(entry('same', isDocument: false).key));
    });
  });
  group('Account profile validation and errors', () {
    test('Blank names are rejected', () {
      expect(AuthService.validateDisplayName('   '), isNotNull);
    });
    test('Bangla and English names are accepted', () {
      expect(AuthService.validateDisplayName('প্রমা দেব'), isNull);
      expect(AuthService.validateDisplayName('Proma Deb'), isNull);
    });
    test('Names longer than 80 characters are rejected', () {
      expect(AuthService.validateDisplayName('a' * 81), isNotNull);
      expect(AuthService.validateDisplayName('a' * 80), isNull);
    });
    test('Google collision explains that guest data is preserved', () {
      final message = AuthService.errorMessage(
        FirebaseAuthException(code: 'credential-already-in-use'),
      );
      expect(message, contains('guest data is unchanged'));
    });
    test('Popup cancellation has a readable message', () {
      expect(
        AuthService.errorMessage(
          FirebaseAuthException(code: 'popup-closed-by-user'),
        ),
        contains('cancelled'),
      );
    });
    test('Network error does not expose provider details', () {
      final message = AuthService.errorMessage(
        FirebaseAuthException(
          code: 'network-request-failed',
          message: 'private provider details',
        ),
      );
      expect(message, contains('internet'));
      expect(message, isNot(contains('private provider details')));
    });
  });

  group('AI request limit messages', () {
    test('Burst limit shows server wait time', () {
      expect(
        aiLimitMessage({'reason': 'rate-limit', 'retryAfterSeconds': 17}),
        contains('17 seconds'),
      );
    });
    test('Concurrent request limit explains waiting for completion', () {
      expect(
        aiLimitMessage({'reason': 'concurrency-limit'}),
        contains('still running'),
      );
    });
    test('App-wide cap is not described as a personal quota', () {
      expect(aiLimitMessage({'reason': 'global-budget'}), contains('app-wide'));
    });
    test('Failed-attempt cap has a separate message', () {
      expect(
        aiLimitMessage({'reason': 'daily-attempts'}),
        contains('attempts today'),
      );
    });
    test('Pause switch is not described as a network failure', () {
      expect(
        aiLimitMessage({'reason': 'ai-paused'}),
        contains('temporarily paused'),
      );
    });
    test('Older backend quota responses retain a daily-limit fallback', () {
      expect(aiLimitMessage(null), contains('Daily limit'));
    });
  });

  group('Release configuration validation', () {
    test('Privacy links require HTTPS and a host without credentials', () {
      expect(ReleaseConfig.validHttps('https://example.org/privacy'), isTrue);
      for (final url in [
        '',
        'http://example.org',
        'https:',
        'https://user:pass@example.org',
      ]) {
        expect(ReleaseConfig.validHttps(url), isFalse);
      }
    });
    test('Support email rejects whitespace and missing domains', () {
      expect(ReleaseConfig.validEmail('support@example.org'), isTrue);
      for (final email in ['', 'support', 'a@b', 'a b@example.org']) {
        expect(ReleaseConfig.validEmail(email), isFalse);
      }
    });
  });

  testWidgets('Tool tiles fit a narrow screen at large text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ResponsiveToolsGrid(
                  children: List.generate(
                    4,
                    (index) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.description),
                            Text('Document creation tool $index'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final first = tester.getRect(find.byType(Card).at(0));
    final second = tester.getRect(find.byType(Card).at(1));
    expect(second.left, greaterThan(first.left));
    expect(second.top, first.top);
  });

  group('13+ AI declaration', () {
    test('Under-13 declaration cannot authorize AI', () {
      expect(
        const AgeDeclaration(
          ageBand: 'under-13',
          guardianPermission: true,
          privacyAccepted: true,
        ).eligible,
        isFalse,
      );
    });
    test('A teen must declare guardian permission and accept the policy', () {
      expect(
        const AgeDeclaration(
          ageBand: '13-17',
          guardianPermission: false,
          privacyAccepted: true,
        ).eligible,
        isFalse,
      );
      expect(
        const AgeDeclaration(
          ageBand: '13-17',
          guardianPermission: true,
          privacyAccepted: false,
        ).eligible,
        isFalse,
      );
      expect(
        const AgeDeclaration(
          ageBand: '13-17',
          guardianPermission: true,
          privacyAccepted: true,
        ).eligible,
        isTrue,
      );
    });
    test('An adult must accept the policy', () {
      expect(
        const AgeDeclaration(
          ageBand: '18-plus',
          guardianPermission: false,
          privacyAccepted: true,
        ).eligible,
        isTrue,
      );
      expect(
        const AgeDeclaration(
          ageBand: '18-plus',
          guardianPermission: false,
          privacyAccepted: false,
        ).eligible,
        isFalse,
      );
    });
    test('Malformed or under-13 eligibility responses fail closed', () {
      for (final band in [null, 123, 'unknown', 'under-13']) {
        expect(
          AiEligibility.fromData({'eligible': true, 'ageBand': band}).eligible,
          isFalse,
        );
      }
    });
    test('Only declared adult accounts are eligible for banner requests', () {
      expect(
        const AiEligibility(eligible: true, ageBand: '13-17').adult,
        isFalse,
      );
      expect(
        const AiEligibility(eligible: false, ageBand: '18-plus').adult,
        isFalse,
      );
      expect(
        const AiEligibility(eligible: true, ageBand: '18-plus').adult,
        isTrue,
      );
    });
    test('Safety failures have separate useful messages', () {
      expect(aiSafetyMessage({'reason': 'safety-blocked'}), contains('safely'));
      expect(
        aiSafetyMessage({'reason': 'safety-unavailable'}),
        contains('Nothing was saved'),
      );
      expect(
        aiSafetyMessage({'reason': 'provider-incomplete'}),
        contains('incomplete'),
      );
    });
  });

  testWidgets('Under-13 age group cannot continue the eligibility dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgeDeclarationDialog(initialAgeBand: 'under-13')),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNull,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('Teen dialog requires both permission declarations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgeDeclarationDialog(initialAgeBand: '13-17')),
      ),
    );
    final button = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile).at(0));
    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile).at(1));
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
