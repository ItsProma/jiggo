import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/ai_chat_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/chat_gateway.dart';
import 'package:jiggo/widgets/home_overview.dart';
import 'package:jiggo/widgets/ai_report_button.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

class FakeChatGateway implements ChatGateway {
  final calls = <Map<String, dynamic>>[];
  final conversations = <String, Map<String, dynamic>>{};
  Completer<Map<String, dynamic>>? waiting;
  bool failSend = false;
  bool failList = false;
  bool saved = true;
  int listPages = 1;
  Map<String, dynamic> conversation(String id) => conversations.putIfAbsent(
    id,
    () => {'id': id, 'title': 'Saved chat', 'messages': <dynamic>[]},
  );

  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    calls.add(Map.from(data));
    switch (data['action']) {
      case 'send':
        if (failSend) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Offline',
          );
        }
        if (waiting != null) return waiting!.future;
        final chat = conversation(data['chatId'] as String);
        (chat['messages'] as List).addAll([
          {
            'role': 'user',
            'text': data['message'],
            'requestId': data['requestId'],
          },
          {'role': 'assistant', 'text': 'Home', 'requestId': data['requestId']},
        ]);
        return {'chat': chat, 'saved': saved, 'remainingToday': 19};
      case 'list':
        if (failList) throw StateError('Offline');
        return {
          'chats': conversations.values
              .map((c) => {'id': c['id'], 'title': c['title']})
              .toList(),
          'nextCursor': listPages-- > 1 ? 'older-page' : null,
        };
      case 'read':
        return {'chat': conversation(data['chatId'] as String)};
      case 'delete':
        conversations.remove(data['chatId']);
        return {'deleted': true};
    }
    throw StateError('Unknown action');
  }
}

Future<void> openChat(
  WidgetTester tester,
  FakeChatGateway gateway, {
  String initial = '',
  String language = 'en',
}) async {
  await tester.binding.setSurfaceSize(const Size(700, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    settingsApp(
      AppSettings(store: MemorySettingsStore(), language: language),
      AiChatScreen(initialQuestion: initial, gateway: gateway),
    ),
  );
  if (gateway.waiting == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Library entry opens saved history without generating a reply', (
    tester,
  ) async {
    final gateway = FakeChatGateway();
    gateway.conversation('saved-history-chat');
    await tester.pumpWidget(
      settingsApp(
        AppSettings(store: MemorySettingsStore(), language: 'en'),
        AiChatScreen(gateway: gateway, showHistoryOnOpen: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.calls.single['action'], 'list');
    expect(find.text('Saved chat'), findsOneWidget);
  });

  testWidgets(
    'Home submission forwards the exact question without a duplicate history link',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? submitted;
      await tester.binding.setSurfaceSize(const Size(700, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        settingsApp(
          AppSettings(store: MemorySettingsStore(), language: 'en'),
          Scaffold(
            body: HomeOverview(
              promptController: controller,
              onToolSelected: (_) {},
              onUnavailable: (_) {},
              onOpenLibrary: () {},
              onSubmit: (text) => submitted = text,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Explain photosynthesis');
      await tester.tap(find.byKey(const ValueKey('home-chat-send')));
      expect(submitted, 'Explain photosynthesis');
      expect(find.byKey(const ValueKey('home-chat-history')), findsNothing);
    },
  );

  testWidgets(
    'Home initial message sends once in UI language and does not translate AI text',
    (tester) async {
      final gateway = FakeChatGateway();
      await openChat(
        tester,
        gateway,
        initial: 'সালোকসংশ্লেষণ কী?',
        language: 'bn',
      );
      expect(gateway.calls.length, 1);
      expect(gateway.calls.single['message'], 'সালোকসংশ্লেষণ কী?');
      expect(gateway.calls.single['language'], 'Bangla');
      expect(find.text('Home', findRichText: true), findsOneWidget);
      expect(
        tester.widget<AiReportButton>(find.byType(AiReportButton)).source,
        'chat',
      );
      await tester.pumpAndSettle();
      expect(gateway.calls.length, 1);
    },
  );

  testWidgets(
    'Busy blocks duplicate sends; retry keeps the same request and prompt',
    (tester) async {
      final gateway = FakeChatGateway()..failSend = true;
      await openChat(tester, gateway);
      await send(tester, 'My first question');
      final first = Map<String, dynamic>.from(gateway.calls.single);
      gateway.failSend = false;
      gateway.waiting = Completer<Map<String, dynamic>>();
      await tester.ensureVisible(find.byKey(const ValueKey('chat-retry')));
      await tester.tap(find.byKey(const ValueKey('chat-retry')));
      await tester.pump();
      expect(gateway.calls.last, first);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
            .onPressed,
        isNull,
      );
      gateway.waiting!.complete({
        'saved': true,
        'chat': {
          'id': first['chatId'],
          'title': 'Recovered',
          'messages': [
            {
              'role': 'user',
              'text': first['message'],
              'requestId': first['requestId'],
            },
            {
              'role': 'assistant',
              'text': 'Recovered reply',
              'requestId': first['requestId'],
            },
          ],
        },
      });
      await tester.pumpAndSettle();
      expect(gateway.calls.length, 2);
      expect(find.text('Recovered reply', findRichText: true), findsOneWidget);
    },
  );

  testWidgets(
    'History refresh keeps pending request identity until its saved answer exists',
    (tester) async {
      final gateway = FakeChatGateway()..failSend = true;
      await openChat(tester, gateway);
      await send(tester, 'An uncertain request');
      final request = gateway.calls.first;
      final chat = gateway.conversation(request['chatId'] as String);
      await tester.ensureVisible(find.byKey(const ValueKey('chat-check')));
      await tester.tap(find.byKey(const ValueKey('chat-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-retry')), findsOneWidget);
      (chat['messages'] as List).addAll([
        {
          'role': 'user',
          'text': request['message'],
          'requestId': request['requestId'],
        },
        {
          'role': 'assistant',
          'text': 'Saved after timeout',
          'requestId': request['requestId'],
        },
      ]);
      await tester.ensureVisible(find.byKey(const ValueKey('chat-check')));
      await tester.tap(find.byKey(const ValueKey('chat-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-retry')), findsNothing);
      expect(
        find.text('Saved after timeout', findRichText: true),
        findsOneWidget,
      );
      expect(gateway.calls.where((c) => c['action'] == 'send').length, 1);
    },
  );

  testWidgets(
    'New chat uses a new ID; history opens and deletes saved conversations without AI',
    (tester) async {
      final gateway = FakeChatGateway();
      await openChat(tester, gateway);
      await send(tester, 'A saved question');
      final id = gateway.calls.single['chatId'];
      await tester.tap(find.byKey(const ValueKey('chat-new')));
      await tester.pumpAndSettle();
      await send(tester, 'Another question');
      expect(gateway.calls.last['chatId'], isNot(id));
      await tester.tap(find.byKey(const ValueKey('chat-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved chat').first);
      await tester.pumpAndSettle();
      expect(gateway.calls.last['action'], 'read');
      await tester.tap(find.byKey(const ValueKey('chat-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete chat').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(gateway.calls.last['action'], 'delete');
      expect(gateway.conversations.containsKey(id), isFalse);
      expect(gateway.calls.where((c) => c['action'] == 'send').length, 2);
    },
  );

  testWidgets('Unsaved answer is copyable and blocks a new paid request', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final gateway = FakeChatGateway()..saved = false;
    await openChat(tester, gateway);
    await send(tester, 'A question worth keeping');
    expect(
      find.textContaining('This reply could not be saved.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-send')))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byTooltip('Copy').last);
    await tester.tap(find.byTooltip('Copy').last);
    await tester.pumpAndSettle();
    expect(copied, 'Home');
  });

  testWidgets('History load failure can retry and load older pages', (
    tester,
  ) async {
    final gateway = FakeChatGateway()
      ..failList = true
      ..listPages = 2;
    gateway.conversation('old-chat-123456789');
    await openChat(tester, gateway);
    await tester.tap(find.byKey(const ValueKey('chat-history')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to load chats'), findsOneWidget);
    gateway.failList = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load older chats'));
    await tester.pumpAndSettle();
    expect(gateway.calls.last['cursor'], 'older-page');
    expect(find.text('Saved chat'), findsOneWidget);
  });

  testWidgets('Oversized message is preserved and never sent', (tester) async {
    final gateway = FakeChatGateway();
    await openChat(tester, gateway);
    await send(tester, 'কি' * 1001);
    expect(gateway.calls, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      'কি' * 1001,
    );
  });

  testWidgets(
    'A late reply after leaving the screen does not update disposed state',
    (tester) async {
      final gateway = FakeChatGateway()
        ..waiting = Completer<Map<String, dynamic>>();
      await openChat(tester, gateway, initial: 'A slow question');
      await tester.pump();
      final id = gateway.calls.single['chatId'];
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gateway.waiting!.complete({
        'saved': true,
        'chat': {'id': id, 'title': 'Late', 'messages': []},
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['bn', 'en']) {
    testWidgets(
      'Chat fits small screen, large text, dark theme and keyboard: $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          settingsApp(
            AppSettings(
              store: MemorySettingsStore(),
              language: language,
              themeMode: ThemeMode.dark,
            ),
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 200),
                ),
                child: AiChatScreen(gateway: FakeChatGateway()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await send(tester, 'Explain photosynthesis simply.');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
