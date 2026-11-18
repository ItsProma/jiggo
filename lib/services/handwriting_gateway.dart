import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'scan_image.dart';

abstract class HandwritingGateway {
  Future<Map<String, dynamic>> recognize(Uint8List bytes, String language);
  Future<void> save(String id, String title, String text);
}

class FirebaseHandwritingGateway implements HandwritingGateway {
  FirebaseHandwritingGateway({String? expectedUid})
    : _uid = expectedUid ?? FirebaseAuth.instance.currentUser?.uid;
  final String? _uid;
  void _check() {
    if (_uid == null || FirebaseAuth.instance.currentUser?.uid != _uid) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Account changed.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> recognize(
    Uint8List bytes,
    String language,
  ) async {
    _check();
    final mime = ScanImage.validate(bytes);
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'recognizeHandwriting',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call({
          'expectedUid': _uid,
          'imageBase64': base64Encode(bytes),
          'mimeType': mime,
          'language': language,
        });
    _check();
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<void> save(String id, String title, String text) async {
    _check();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        title.trim().length < 3 ||
        title.length > 150 ||
        text.trim().isEmpty ||
        text.length > 20000) {
      throw const FormatException('Invalid handwriting note');
    }
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('documents')
        .doc(id);
    final document = await ref.get().timeout(const Duration(seconds: 15));
    _check();
    if (!document.exists ||
        document.data()?['documentType'] != 'Handwriting Recognition') {
      throw const FormatException('Note unavailable');
    }
    await ref
        .update({'title': title.trim(), 'content': text})
        .timeout(const Duration(seconds: 20));
    _check();
  }
}
