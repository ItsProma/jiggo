import '../services/app_theme.dart';
import '../services/app_strings.dart';

import 'dart:async' as async_utils;

import '../services/ai_eligibility_service.dart';
import '../services/ads_service.dart';
import 'privacy_screen.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  Future<void> _guestLogin() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final declaration = await AiEligibilityService.collect(context);
      if (declaration == null) {
        return;
      }
      final credential = await _authService.signInAsGuest();
      final uid = credential.user?.uid;
      if (uid != null) {
        await AiEligibilityService.submit(declaration, uid);
        async_utils.unawaited(
          AdsService.instance.start(afterDeclaration: true),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(AuthService.errorMessage(error)))),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr(AiEligibilityService.errorMessage(error))),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _googleLogin() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final declaration = await AiEligibilityService.collect(context);
      if (declaration == null) {
        return;
      }
      final credential = await _authService.signInWithGoogle();
      final uid = credential.user?.uid;
      if (uid != null) {
        await AiEligibilityService.submit(declaration, uid);
        async_utils.unawaited(
          AdsService.instance.start(afterDeclaration: true),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(AuthService.errorMessage(error)))),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr(AiEligibilityService.errorMessage(error))),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.adaptiveTint(const Color(0xFFE6E9FF)),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 58,
                      color: context.accentColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.tr('Jiggo'),
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: context.accentColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('Ask. Scan. Create.'),
                    style: TextStyle(fontSize: 17, color: context.mutedColor),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    context.tr('Welcome to Jiggo'),
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr(
                      'Your AI assistant for questions, documents and everyday tasks.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.mutedColor),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,

                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _guestLogin,
                      icon: const Icon(Icons.person_outline),
                      label: Text(
                        context.tr(
                          _isLoading ? 'Please wait...' : 'Continue as Guest',
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,

                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _googleLogin,
                      icon: const Icon(Icons.login),
                      label: Text(context.tr('Continue with Google')),
                    ),
                  ),

                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
                    ),
                    child: Text(context.tr('Privacy Policy')),
                  ),
                  Text(
                    context.tr(
                      'Jiggo is for ages 13+. Use AI responsibly and review its answers.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.mutedColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
