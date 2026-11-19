import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'guided_document_model.dart';

abstract class GuidedDocumentGateway {
  Future<Map<String, dynamic>> generate(GuidedDocument document);
}

class FirebaseGuidedDocumentGateway implements GuidedDocumentGateway {
  final String owner;
  FirebaseGuidedDocumentGateway(this.owner);
  @override
  Future<Map<String, dynamic>> generate(GuidedDocument document) async {
    void check() {
      if (FirebaseAuth.instance.currentUser?.uid != owner) {
        throw StateError('account-changed');
      }
    }

    check();
    final instructions = document.instructions;
    if (instructions.length > 8000) throw const FormatException('brief-size');
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'generateDocument',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call({
          'expectedUid': owner,
          'title': document.title,
          'instructions': instructions,
          'documentType': document.type,
          'language': document.language,
          'previewOnly': true,
        });
    check();
    return Map<String, dynamic>.from(result.data as Map);
  }
}

abstract class DocumentDetailsGateway {
  Future<Map<String, dynamic>> extract(GuidedDocument document, String input);
}

class FirebaseDocumentDetailsGateway implements DocumentDetailsGateway {
  final String owner;
  FirebaseDocumentDetailsGateway(this.owner);
  @override
  Future<Map<String, dynamic>> extract(
    GuidedDocument document,
    String input,
  ) async {
    void check() {
      if (FirebaseAuth.instance.currentUser?.uid != owner) {
        throw StateError('account-changed');
      }
    }

    check();
    if (input.trim().length < 10 || input.length > 2000) {
      throw const FormatException('details-input');
    }
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'generateDocument',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call({
          'expectedUid': owner,
          'title': document.title,
          'documentType': document.type,
          'language': document.language,
          'instructions': input,
          'previewOnly': true,
          'extractOnly': true,
        });
    check();
    return Map<String, dynamic>.from(result.data as Map);
  }
}
