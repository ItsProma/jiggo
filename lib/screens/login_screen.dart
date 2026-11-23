import '../services/app_theme.dart';
import '../services/app_strings.dart';

import 'email_auth_screen.dart';
import 'guest_explore_screen.dart';

import 'privacy_screen.dart';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final bool showGuest;
  const LoginScreen({super.key, this.showGuest = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _error;

  void _guestLogin() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const GuestExploreScreen()),
    );
  }

  Future<void> _googleLogin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await _authService.signInWithGoogle();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (error) {
      if (mounted) setState(() => _error = AuthService.errorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
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
                  if (widget.showGuest)
                    SizedBox(
                      width: double.infinity,

                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _guestLogin,
                        icon: const Icon(Icons.person_outline),
                        label: Text(
                          context.tr(
                            _isLoading ? 'Please wait...' : 'Explore as Guest',
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

                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EmailAuthScreen(),
                              ),
                            ),
                      icon: const Icon(Icons.mail_outline),
                      label: Text(context.tr('Continue with email')),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(context.tr(_error!)),
                    TextButton(
                      onPressed: _isLoading ? null : _googleLogin,
                      child: Text(context.tr('Retry')),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const PrivacyScreen(),
                      ),
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
