import 'notifications_screen.dart';
import '../services/app_theme.dart';
import '../services/app_strings.dart';
import '../services/app_settings.dart';
import 'app_preferences_screen.dart';
import '../services/ads_service.dart';
import 'privacy_screen.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'library_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = AuthService();
  late final Stream<User?> _users;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _users = FirebaseAuth.instance.userChanges();
  }

  void _message(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.tr(text))));
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy != null) {
      return;
    }
    setState(() => _busy = label);
    try {
      await action();
    } catch (error) {
      _message(AuthService.errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = null);
      }
    }
  }

  Future<void> _editName(User user) async {
    final formKey = GlobalKey<FormState>();
    var name = user.displayName ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void save() {
          if (formKey.currentState?.validate() == true) {
            Navigator.pop(dialogContext, name.trim());
          }
        }

        return AlertDialog(
          title: Text(context.tr('Edit profile')),
          content: Form(
            key: formKey,
            child: TextFormField(
              initialValue: name,
              autofocus: true,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: context.tr('Display name'),
              ),
              validator: (value) => context.trNullable(
                AuthService.validateDisplayName(value ?? ''),
              ),
              onChanged: (value) => name = value,
              onFieldSubmitted: (_) => save(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(onPressed: save, child: Text(context.tr('Save'))),
          ],
        );
      },
    );
    if (!mounted || result == null) {
      return;
    }
    if (_service.currentUser?.uid != user.uid) {
      _message('Account changed. Please reopen your profile.');
      return;
    }
    await _run('Saving profile…', () async {
      await _service.updateDisplayName(result);
      _message('Profile updated');
    });
  }

  Future<void> _linkGoogle() async {
    await _run('Connecting Google…', () async {
      await _service.linkGuestWithGoogle();
      _message('Google connected. Your saved work stays in this account.');
    });
  }

  Future<void> _logout(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Log Out?')),
        content: Text(
          context.tr(
            user.isAnonymous
                ? 'Guest files may become inaccessible after logout. Connect Google first to keep access, or continue logging out.'
                : 'Are you sure you want to log out?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Log Out')),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        _service.currentUser?.uid != user.uid) {
      return;
    }
    await _run('Logging out…', _service.signOut);
  }

  Future<void> _deleteAccount(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Delete account permanently?')),
        content: Text(
          context.tr(
                'Your documents, scan history and AI usage records will be deleted. This cannot be undone.',
              ) +
              (user.isAnonymous
                  ? ''
                  : ' ${context.tr('Google will ask you to confirm your identity.')}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Delete permanently')),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        _service.currentUser?.uid != user.uid) {
      return;
    }
    await _run('Deleting account…', _service.deleteAccount);
  }

  Widget _settingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Card(
      color: context.cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: context.accentColor),
        title: Text(
          context.tr(title),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(context.tr(subtitle)),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy != null
            ? null
            : onTap ??
                  () => _message(
                    context.tr('{feature} is coming soon', {
                      'feature': context.tr(title),
                    }),
                  ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _users,
      initialData: _service.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final isGuest = user?.isAnonymous ?? true;
        final name = user?.displayName?.trim();
        final displayName = name != null && name.isNotEmpty
            ? name
            : context.tr(isGuest ? 'Guest User' : 'Jiggo User');
        final email = isGuest
            ? context.tr('You are using a guest account')
            : user?.email ?? context.tr('Google Account');
        return Scaffold(
          backgroundColor: context.pageColor,
          appBar: AppBar(
            backgroundColor: context.pageColor,
            title: Text(
              context.tr('My Profile'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: context.adaptiveTint(
                        const Color(0xFFE6E9FF),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        size: 38,
                        color: context.accentColor,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      email,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.mutedColor),
                    ),
                  ],
                ),
              ),
              if (_busy != null) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(context.tr(_busy!), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 28),
              Text(
                context.tr('Account'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (user != null) ...[
                _settingTile(
                  title: 'Edit Profile',
                  subtitle: 'Change your display name',
                  icon: Icons.edit_outlined,
                  onTap: () => _editName(user),
                ),
                if (isGuest)
                  _settingTile(
                    title: 'Connect Google',
                    subtitle: 'Keep access to your guest documents and scans',
                    icon: Icons.link,
                    onTap: _linkGoogle,
                  ),
              ],
              _settingTile(
                title: 'My Documents',
                subtitle: 'Manage your saved files',
                icon: Icons.folder_outlined,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const LibraryScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('Preferences'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _settingTile(
                title: 'Language',
                subtitle:
                    AppSettingsScope.of(context).locale.languageCode == 'bn'
                    ? 'বাংলা'
                    : 'English',
                icon: Icons.language,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AppPreferencesScreen(
                      section: PreferenceSection.language,
                    ),
                  ),
                ),
              ),
              _settingTile(
                title: 'Appearance',
                subtitle: switch (AppSettingsScope.of(context).themeMode) {
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                  ThemeMode.system => 'System',
                },
                icon: Icons.dark_mode_outlined,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AppPreferencesScreen(
                      section: PreferenceSection.appearance,
                    ),
                  ),
                ),
              ),
              _settingTile(
                title: 'Notifications',
                subtitle: 'Manage notifications',
                icon: Icons.notifications_outlined,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('Support & Legal'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _settingTile(
                title: 'Help & Support',
                subtitle: 'Get help with Jiggo',
                icon: Icons.help_outline,
                onTap: () => openJiggoSupport(context),
              ),
              _settingTile(
                title: 'Privacy Policy',
                subtitle: 'How your data is handled',
                icon: Icons.privacy_tip_outlined,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacyScreen(),
                  ),
                ),
              ),
              _settingTile(
                title: 'About Jiggo',
                subtitle: 'App information',
                icon: Icons.info_outline,
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Jiggo',
                  children: [
                    Text(
                      context.tr(
                        'AI question solving and document creation. Review AI responses before relying on them.',
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AdsService.instance.privacyOptionsRequired,
                builder: (context, isRequired, _) => isRequired
                    ? _settingTile(
                        title: 'Ads privacy options',
                        subtitle: 'Manage your advertising choices',
                        icon: Icons.privacy_tip_outlined,
                        onTap: () => _run(
                          'Opening privacy options…',
                          AdsService.instance.showPrivacyOptions,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                child: OutlinedButton.icon(
                  onPressed: user == null || _busy != null
                      ? null
                      : () => _logout(user),
                  icon: const Icon(Icons.logout),
                  label: Text(context.tr('Log Out')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: user == null || _busy != null
                    ? null
                    : () => _deleteAccount(user),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(context.tr('Delete Account')),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
