import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jiggo/screens/email_auth_screen.dart';
import 'package:jiggo/screens/guest_explore_screen.dart';
import 'package:jiggo/services/auth_service.dart';
import 'package:jiggo/widgets/home_tools.dart';

class Provider implements UserInfo {
  @override
  final String providerId;
  Provider(this.providerId);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Member implements User {
  @override
  final bool isAnonymous, emailVerified;
  @override
  final String uid = 'member';
  @override
  final List<UserInfo> providerData;
  @override
  String get email => 'sample@example.com';
  Member({
    this.isAnonymous = false,
    this.emailVerified = false,
    String provider = 'password',
  }) : providerData = [Provider(provider)];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Account extends AuthService {
  String? action;
  List<String>? values;
  bool fail = false;
  @override
  Future<void> createEmailAccount(String n, String e, String p) async {
    action = 'create';
    values = [n, e, p];
  }

  @override
  Future<void> signInWithEmail(String e, String p) async {
    if (fail) throw FirebaseAuthException(code: 'invalid-credential');
    action = 'login';
    values = [e, p];
  }

  @override
  Future<void> resetPassword(String e) async {
    action = 'reset';
  }

  @override
  User get currentUser => Member();
  @override
  Future<void> sendVerification() async {
    action = 'verify';
  }

  @override
  Future<void> reloadUser() async {
    action = 'reload';
  }
}

Future<void> press(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  test('Only members with verified password accounts may work', () {
    expect(AuthService.isMember(null), false);
    expect(AuthService.isMember(Member(isAnonymous: true)), false);
    expect(AuthService.isMember(Member()), false);
    expect(AuthService.isMember(Member(emailVerified: true)), true);
    expect(AuthService.isMember(Member(provider: 'google.com')), true);
    expect(AuthService.validateEmail('bad'), isNotNull);
    expect(AuthService.validatePassword('short'), isNotNull);
  });
  testWidgets(
    'Sign up rejects mismatched passwords and submits the user supplied credentials',
    (t) async {
      final auth = Account();
      await t.pumpWidget(MaterialApp(home: EmailAuthScreen(service: auth)));
      await press(t, find.byKey(const ValueKey('auth-switch')));
      await t.enterText(
        find.byKey(const ValueKey('auth-name')),
        'Sample Applicant',
      );
      await t.enterText(
        find.byKey(const ValueKey('auth-email')),
        'sample@example.com',
      );
      await t.enterText(
        find.byKey(const ValueKey('auth-password')),
        'LongerPass123',
      );
      await t.enterText(
        find.byKey(const ValueKey('auth-confirm')),
        'different',
      );
      await press(t, find.byKey(const ValueKey('auth-submit')));
      expect(auth.action, isNull);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('auth-confirm')),
        'LongerPass123',
      );
      await press(t, find.byKey(const ValueKey('auth-submit')));
      expect(auth.values, [
        'Sample Applicant',
        'sample@example.com',
        'LongerPass123',
      ]);
    },
  );
  testWidgets(
    'Failed sign in keeps the email and supports a private password reset message',
    (t) async {
      final auth = Account()..fail = true;
      await t.pumpWidget(MaterialApp(home: EmailAuthScreen(service: auth)));
      await t.enterText(
        find.byKey(const ValueKey('auth-email')),
        'sample@example.com',
      );
      await t.enterText(
        find.byKey(const ValueKey('auth-password')),
        'LongerPass123',
      );
      await press(t, find.byKey(const ValueKey('auth-submit')));
      expect(
        find.textContaining('Email or password is incorrect'),
        findsOneWidget,
      );
      await press(t, find.text('Forgot password?'));
      expect(auth.action, 'reset');
      expect(
        find.textContaining('If this email has an account'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Verification can resend and refresh without an AI eligibility request',
    (t) async {
      final auth = Account();
      await t.pumpWidget(MaterialApp(home: VerifyEmailScreen(service: auth)));
      await press(t, find.text('Send verification email'));
      expect(auth.action, 'verify');
      await press(t, find.text('Send verification email'));
      expect(find.textContaining('Wait one minute'), findsOneWidget);
      await press(t, find.text('I have verified my email'));
      expect(auth.action, 'reload');
    },
  );
  testWidgets('Guest can explore without Firebase or access to saved files', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: GuestExploreScreen()));
    await t.pumpAndSettle();
    await press(t, find.byKey(const ValueKey(HomeTool.fileEditor)));
    expect(find.text('Sign in or create account'), findsOneWidget);
    expect(find.text('Open PDF'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
