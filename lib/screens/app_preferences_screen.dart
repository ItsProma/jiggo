import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/app_strings.dart';

enum PreferenceSection { language, appearance }

class AppPreferencesScreen extends StatelessWidget {
  final PreferenceSection section;
  const AppPreferencesScreen({super.key, required this.section});

  Future<void> _save(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Could not save your preference. Please try again.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final language = section == PreferenceSection.language;
    Widget choice(String label, bool selected, VoidCallback onTap) => Semantics(
      selected: selected,
      child: ListTile(
        title: Text(label),
        selected: selected,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
        onTap: settings.saving ? null : onTap,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(language ? 'Language' : 'Appearance')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr(
              language
                  ? 'Choose the language for menus and messages.'
                  : 'Choose how Jiggo looks on this device.',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (settings.saving) const LinearProgressIndicator(),
          if (language) ...[
            choice(
              'বাংলা',
              settings.locale.languageCode == 'bn',
              () => _save(context, () => settings.setLanguage('bn')),
            ),
            choice(
              'English',
              settings.locale.languageCode == 'en',
              () => _save(context, () => settings.setLanguage('en')),
            ),
          ] else ...[
            for (final mode in const [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
              choice(
                context.tr(switch (mode) {
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                  ThemeMode.system => 'System',
                }),
                settings.themeMode == mode,
                () => _save(context, () => settings.setThemeMode(mode)),
              ),
          ],
        ],
      ),
    );
  }
}

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});
  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String? _selected;
  bool _failed = false;

  Future<void> _continue() async {
    if (_selected == null) return;
    setState(() => _failed = false);
    try {
      await AppSettingsScope.of(context).setLanguage(_selected!);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Jiggo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'ভাষা বেছে নাও\nChoose your language',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  for (final entry in const {
                    'bn': 'বাংলা',
                    'en': 'English',
                  }.entries)
                    Card(
                      child: Semantics(
                        selected: _selected == entry.key,
                        child: ListTile(
                          title: Text(entry.value),
                          leading: Icon(
                            _selected == entry.key
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          onTap: settings.saving
                              ? null
                              : () => setState(() => _selected = entry.key),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_failed)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'পছন্দ সেভ হয়নি। আবার চেষ্টা করো।\nCould not save. Please try again.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  FilledButton(
                    onPressed: settings.saving || _selected == null
                        ? null
                        : _continue,
                    child: settings.saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(),
                          )
                        : const Text('এগিয়ে যাও / Continue'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'পরে Profile থেকে বদলাতে পারবে।\nYou can change this later in Profile.',
                    textAlign: TextAlign.center,
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
