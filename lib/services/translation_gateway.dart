import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'auth_service.dart';

const translationLanguages = {
  'bn': 'Bangla',
  'en': 'English',
  'sv': 'Swedish',
  'hi': 'Hindi',
  'ur': 'Urdu',
  'ar': 'Arabic',
  'fr': 'French',
  'de': 'German',
  'es': 'Spanish',
  'it': 'Italian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ta': 'Tamil',
};

abstract class TranslationGateway {
  Future<Map<String, dynamic>> translate(
    String text,
    String source,
    String target,
  );
}

class FirebaseTranslationGateway implements TranslationGateway {
  @override
  Future<Map<String, dynamic>> translate(
    String text,
    String source,
    String target,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!AuthService.isMember(user)) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    final uid = user!.uid;
    await user.getIdToken(true);
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'translateText',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call<Map<String, dynamic>>({
          'expectedUid': uid,
          'text': text,
          'source': source,
          'target': target,
        });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    return result.data;
  }
}
