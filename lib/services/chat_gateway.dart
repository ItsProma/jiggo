import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract class ChatGateway {
  Future<Map<String, dynamic>> call(Map<String, dynamic> data);
}

class FirebaseChatGateway implements ChatGateway {
  FirebaseChatGateway() : _uid = FirebaseAuth.instance.currentUser?.uid;
  final String? _uid;

  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    void checkAccount() {
      if (_uid == null || FirebaseAuth.instance.currentUser?.uid != _uid) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Account changed.',
        );
      }
    }

    checkAccount();
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'aiChat',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call({...data, 'expectedUid': _uid});
    checkAccount();
    return Map<String, dynamic>.from(result.data as Map);
  }
}

class ChatMessage {
  final String role;
  final String text;
  const ChatMessage(this.role, this.text);
}

class ChatConversation {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  const ChatConversation(this.id, this.title, this.messages);
  factory ChatConversation.fromMap(Map data) {
    if (data['id'] is! String ||
        data['title'] is! String ||
        data['messages'] is! List) {
      throw const FormatException('Invalid chat');
    }
    final messages = (data['messages'] as List).map((m) {
      if (m is! Map ||
          !['user', 'assistant'].contains(m['role']) ||
          m['text'] is! String) {
        throw const FormatException('Invalid message');
      }
      return ChatMessage(m['role'] as String, m['text'] as String);
    }).toList();
    return ChatConversation(
      data['id'] as String,
      data['title'] as String,
      messages,
    );
  }
}

String newChatId() {
  final random = math.Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
