import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/app_strings.dart';

class EmailAuthScreen extends StatefulWidget {
  final AuthService? service;
  const EmailAuthScreen({super.key, this.service});
  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  late final _auth = widget.service ?? AuthService();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _signup = false, _busy = false, _hide = true;
  String? _message;
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_signup) {
        await _auth.createEmailAccount(_name.text, _email.text, _password.text);
      } else {
        await _auth.signInWithEmail(_email.text, _password.text);
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() => _message = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final validation = AuthService.validateEmail(_email.text);
    if (validation != null) {
      setState(() => _message = validation);
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.resetPassword(_email.text);
      if (mounted) {
        setState(
          () => _message = 'If this email has an account, a password reset link has been sent. Check your inbox and spam folder.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        context.tr(_signup ? 'Create account' : 'Sign in with email'),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              if (_signup)
                TextFormField(
                  key: const ValueKey('auth-name'),
                  controller: _name,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: context.tr('Your name'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final e = AuthService.validateDisplayName(v ?? '');
                    return e == null ? null : context.tr(e);
                  },
                ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('auth-email'),
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: context.tr('Email address'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final e = AuthService.validateEmail(v ?? '');
                  return e == null ? null : context.tr(e);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('auth-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: _hide,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.tr('Password'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: context.tr('Show or hide password'),
                    onPressed: () => setState(() => _hide = !_hide),
                    icon: Icon(
                      _hide
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) {
                  final e = _signup
                      ? AuthService.validatePassword(v ?? '')
                      : ((v ?? '').isEmpty ? 'Enter your password.' : null);
                  return e == null ? null : context.tr(e);
                },
              ),
              if (_signup) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('auth-confirm'),
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: context.tr('Confirm password'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => v != _password.text
                      ? context.tr('Passwords do not match.')
                      : null,
                ),
                const SizedBox(height: 8),
                Text(context.tr('Use a password with 8 to 128 characters.')),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(context.tr(_message!)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('auth-submit'),
                onPressed: _busy ? null : _submit,
                child: Text(
                  context.tr(
                    _busy
                        ? 'Please wait...'
                        : _signup
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
              ),
              if (!_signup)
                TextButton(
                  onPressed: _busy ? null : _reset,
                  child: Text(context.tr('Forgot password?')),
                ),
              TextButton(
                key: const ValueKey('auth-switch'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _signup = !_signup;
                        _message = null;
                      }),
                child: Text(
                  context.tr(
                    _signup
                        ? 'Already have an account? Sign in'
                        : 'New here? Create account',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class VerifyEmailScreen extends StatefulWidget {
  final AuthService? service;
  const VerifyEmailScreen({super.key, this.service});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final _auth = widget.service ?? AuthService();
  bool _busy = false;
  String? _message;
  DateTime? _lastSent;
  Future<void> _run(bool send) async {
    if (_busy) return;
    if (send &&
        _lastSent != null &&
        DateTime.now().difference(_lastSent!).inSeconds < 60) {
      setState(
        () => _message =
            'Wait one minute before sending another verification email.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (send) {
        await _auth.sendVerification();
        _lastSent = DateTime.now();
      } else {
        await _auth.reloadUser();
      }
      if (mounted) {
        setState(
          () => _message = send
              ? 'Verification email sent. Check your inbox and spam folder.'
              : 'If you have verified your email, your account will open. Otherwise, check your email link and try again.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = AuthService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Verify your email'))),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 60),
            const SizedBox(height: 16),
            Text(context.tr('Verify your email before using Jiggo tools.')),
            const SizedBox(height: 12),
            Text(_auth.currentUser?.email ?? ''),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(context.tr(_message!)),
              ),
            FilledButton(
              onPressed: _busy ? null : () => _run(true),
              child: Text(context.tr('Send verification email')),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(false),
              child: Text(context.tr('I have verified my email')),
            ),
            TextButton(
              onPressed: _busy ? null : _auth.signOut,
              child: Text(context.tr('Log out')),
            ),
          ],
        ),
      ),
    ),
  );
}
