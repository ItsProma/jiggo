import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../widgets/home_overview.dart';
import '../widgets/home_tools.dart';
import 'login_screen.dart';

/// Browsing creates no Firebase anonymous account and never opens stored data.
class GuestExploreScreen extends StatefulWidget {
  const GuestExploreScreen({super.key});
  @override
  State<GuestExploreScreen> createState() => _GuestExploreScreenState();
}

class _GuestExploreScreenState extends State<GuestExploreScreen> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _login() => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const LoginScreen(showGuest: false)),
  );
  void _tool(HomeTool tool) {
    final title = switch (tool) {
      HomeTool.fileEditor => 'File Editor',
      HomeTool.scanSolve => 'Scan & Solve',
      HomeTool.documentMaker => 'Document Maker',
      HomeTool.translator => 'Translator',
    };
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(title: Text(c.tr(title))),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    c.tr(
                      'Sign in to use Jiggo tools and keep your work in your own account.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.push<void>(
                      c,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(showGuest: false),
                      ),
                    ),
                    child: Text(c.tr('Sign in or create account')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.tr('Explore Jiggo')),
      actions: [
        TextButton(onPressed: _login, child: Text(context.tr('Sign in'))),
      ],
    ),
    body: HomeOverview(
      promptController: _input,
      onToolSelected: _tool,
      onUnavailable: (_) => _login(),
      onOpenLibrary: _login,
      onSubmit: (_) => _login(),
      onAttachment: _login,
      onCamera: _login,
      onVoice: _login,
      recentFiles: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.tr('Sign in to see your own saved work.')),
      ),
    ),
  );
}
