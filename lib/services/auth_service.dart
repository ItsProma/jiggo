import 'guided_document_store.dart';
import 'local_file_store.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static Future<void> Function()? beforeSignOut;
  // Keep Firebase access lazy so constructing the login UI needs no connection.
  FirebaseAuth get _auth => FirebaseAuth.instance;
  static Future<void>? _googleInitialization;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  static String? validateDisplayName(String value) {
    if (value.trim().isEmpty) {
      return 'Enter your name';
    }
    if (value.length > 80) {
      return 'Use 80 characters or fewer';
    }
    return null;
  }

  static String errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'credential-already-in-use' ||
        'email-already-in-use' ||
        'account-exists-with-different-credential' => 'This Google account already has a Jiggo account. Your guest data is unchanged. Use another Google account, or log out to open the existing account.',
        'popup-closed-by-user' ||
        'cancelled-popup-request' => 'Google sign-in was cancelled.',
        'popup-blocked' => 'Allow the Google sign-in popup and try again.',
        'network-request-failed' =>
          'Check your internet connection and try again.',
        'requires-recent-login' =>
          'Please sign in again to confirm this action.',
        'user-mismatch' =>
          'Choose the Google account that is currently signed in.',
        'operation-not-allowed' =>
          'This sign-in method is not available right now.',
        'user-disabled' || 'user-token-expired' || 'invalid-user-token' =>
          'Your session is no longer valid. Please sign in again.',
        _ => 'Unable to complete this account action. Please try again.',
      };
    }
    if (error is FirebaseFunctionsException) {
      return switch (error.code) {
        'not-found' || 'unimplemented' => 'Account deletion is not available yet. Please try again after the service is updated.',
        'already-exists' => 'Account deletion is already in progress. Please wait before retrying.',
        'failed-precondition' || 'unauthenticated' =>
          'Please sign in again to confirm account deletion.',
        'unavailable' => 'Unable to connect. Check your internet connection.',
        'permission-denied' =>
          'App verification failed. Please reopen the app and try again.',
        'invalid-argument' => 'Account confirmation did not match. Please reopen your profile and try again.',
        'deadline-exceeded' => 'Deletion status could not be confirmed. Some data may already be deleted. Please reopen the app and check before retrying.',
        _ => 'Account deletion could not be completed. Some data may already be deleted. Please retry.',
      };
    }
    return 'The account action was not completed. Please try again.';
  }

  Future<void> _initializeGoogle() async {
    final initialization = _googleInitialization ??= GoogleSignIn.instance
        .initialize();
    try {
      await initialization;
    } catch (_) {
      _googleInitialization = null;
      rethrow;
    }
  }

  Future<OAuthCredential> _googleCredential() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
      throw UnsupportedError(
        'Native Google sign-in is configured for Android only.',
      );
    }
    await _initializeGoogle();
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw FirebaseAuthException(code: 'invalid-credential');
    }
    return GoogleAuthProvider.credential(idToken: token);
  }

  GoogleAuthProvider _googleProvider() {
    return GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
  }

  Future<UserCredential> signInAsGuest() => _auth.signInAnonymously();

  Future<UserCredential> signInWithGoogle() async {
    // If called while a guest is signed in, preserve that guest UID.
    if (_auth.currentUser?.isAnonymous == true) {
      return linkGuestWithGoogle();
    }
    if (kIsWeb) {
      return _auth.signInWithPopup(_googleProvider());
    }
    return _auth.signInWithCredential(await _googleCredential());
  }

  Future<UserCredential> linkGuestWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw FirebaseAuthException(code: 'not-anonymous');
    }
    final credential = kIsWeb
        ? await user.linkWithPopup(_googleProvider())
        : await user.linkWithCredential(await _googleCredential());
    // No signInWithCredential fallback: collisions must not switch accounts.
    await credential.user?.reload();
    return credential;
  }

  Future<void> updateDisplayName(String value) async {
    final validation = validateDisplayName(value);
    if (validation != null) {
      throw FormatException(validation);
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    await user.updateDisplayName(value.trim());
    await user.reload();
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    final uid = user.uid;
    if (!user.isAnonymous) {
      if (kIsWeb) {
        await user.reauthenticateWithPopup(_googleProvider());
      } else {
        await user.reauthenticateWithCredential(await _googleCredential());
      }
    }
    if (_auth.currentUser?.uid != uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    await user.getIdToken(true);
    if (_auth.currentUser?.uid != uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'deleteMyAccount',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 560)),
        );
    await deviceLocalFiles.clear(uid);
    await guidedDrafts.clearOwner(uid);
    if (_auth.currentUser?.uid != uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    final result = await callable.call<Map<String, dynamic>>({
      'confirm': true,
      'expectedUid': uid,
    });
    if (result.data['deleted'] != true) {
      throw StateError('Account deletion was not confirmed.');
    }
    if (_auth.currentUser?.uid == uid) {
      await signOut();
    }
  }

  Future<void> signOut() async {
    try {
      await beforeSignOut?.call();
    } catch (_) {
      /* Notifications cannot prevent logout. */
    }
    await _auth.signOut();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _initializeGoogle();
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase sign-out succeeded even if provider cleanup is unavailable.
      }
    }
  }
}
