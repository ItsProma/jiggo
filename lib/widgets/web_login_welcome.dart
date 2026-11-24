import 'package:flutter/material.dart';
import '../services/app_strings.dart';
import '../services/app_theme.dart';

/// Web welcome page. Authentication stays in LoginScreen.
class WebLoginWelcome extends StatelessWidget {
  final bool showGuest, busy;
  final String? error;
  final VoidCallback onGoogle, onEmail, onGuest, onPrivacy;
  const WebLoginWelcome({
    super.key,
    required this.showGuest,
    required this.busy,
    required this.onGoogle,
    required this.onEmail,
    required this.onGuest,
    required this.onPrivacy,
    this.error,
  });

  Widget _hero(BuildContext context, bool wide) {
    return Container(
      key: const ValueKey('welcome-hero'),
      padding: EdgeInsets.all(wide ? 40 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF273284), Color(0xFF545DAD), Color(0xFF7068BA)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(context.tr('Jiggo'),
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700))),
          ]),
          SizedBox(height: wide ? 64 : 28),
          Text(context.tr('Ask. Scan. Create.'),
            style: TextStyle(color: Colors.white, fontSize: wide ? 44 : 32,
              height: 1.16, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
          const SizedBox(height: 16),
          Text(context.tr('Your AI assistant for questions, documents and everyday tasks.'),
            style: const TextStyle(color: Color(0xFFE6E8FF), fontSize: 16, height: 1.65)),
          SizedBox(height: wide ? 48 : 24),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _feature(context, Icons.chat_bubble_outline, 'AI Chat'),
            _feature(context, Icons.document_scanner_outlined, 'Scan & Solve'),
            _feature(context, Icons.description_outlined, 'Document Maker'),
          ]),
        ],
      ),
    );
  }

  Widget _feature(BuildContext context, IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white, size: 16),
      const SizedBox(width: 7),
      Flexible(child: Text(context.tr(label), style: const TextStyle(color: Colors.white, fontSize: 12))),
    ]),
  );

  Widget _actions(BuildContext context, bool wide) {
    return Container(
      key: const ValueKey('welcome-actions'),
      padding: EdgeInsets.all(wide ? 32 : 24),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Welcome to Jiggo'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25)),
          const SizedBox(height: 12),
          Text(context.tr('Sign in to use Jiggo tools and keep your work in your own account.'),
            style: TextStyle(color: context.mutedColor, height: 1.6)),
          const SizedBox(height: 28),
          FilledButton.icon(
            key: const ValueKey('welcome-google'),
            onPressed: busy ? null : onGoogle,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 54), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login, size: 20),
            label: Text(context.tr(busy ? 'Please wait...' : 'Continue with Google'), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('welcome-email'),
            onPressed: busy ? null : onEmail,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 54), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.mail_outline, size: 20),
            label: Text(context.tr('Continue with email'), textAlign: TextAlign.center),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(context.tr(error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
            Align(alignment: Alignment.centerLeft,
              child: TextButton(onPressed: busy ? null : onGoogle, child: Text(context.tr('Retry')))),
          ],
          if (showGuest) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('welcome-guest'),
              onPressed: busy ? null : onGuest,
              icon: const Icon(Icons.person_outline, size: 20),
              label: Text(context.tr('Explore as Guest'), textAlign: TextAlign.center),
            ),
          ],
          const SizedBox(height: 20),
          TextButton(onPressed: onPrivacy, child: Text(context.tr('Privacy Policy'))),
          const SizedBox(height: 4),
          Text(context.tr('Jiggo is for ages 13+. Use AI responsibly and review its answers.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.mutedColor, fontSize: 12, height: 1.6)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 860 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20;
      return SingleChildScrollView(
        padding: EdgeInsets.all(wide ? 40 : 16),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(flex: 6, child: _hero(context, true)),
                const SizedBox(width: 28),
                Expanded(flex: 5, child: _actions(context, true)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _hero(context, false),
                const SizedBox(height: 16),
                _actions(context, false),
              ]),
        )),
      );
    },
  );
}
