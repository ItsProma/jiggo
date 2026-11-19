import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/notification_controller.dart';
import '../services/notification_models.dart';

String notificationTargetLabel(String target) => switch (target) {
  'scan' => 'Scan',
  'create' => 'Document Maker',
  'library' => 'Library',
  'profile' => 'Profile',
  _ => 'Home',
};

class NotificationPermissionScreen extends StatelessWidget {
  const NotificationPermissionScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = NotificationScope.of(context);
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
                    Icons.notifications_active_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.tr('Stay updated with Jiggo'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr(
                      'Allow useful updates. You can use every feature without notification permission.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (controller.busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  FilledButton(
                    onPressed: controller.busy ? null : controller.enable,
                    child: Text(context.tr('Enable notifications')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: controller.busy ? null : controller.later,
                    child: Text(context.tr('Later')),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('Change this later in Profile → Notifications.'),
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

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const NotificationsScreen(settingsOnly: true);
}

class NotificationsScreen extends StatefulWidget {
  final bool settingsOnly;
  const NotificationsScreen({super.key, this.settingsOnly = false});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationScope.of(context).refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      NotificationScope.of(context).refresh();
    }
  }

  Future<void> _settings(NotificationController controller) async {
    try {
      final opened = await controller.openSettings();
      if (!mounted || opened) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(c.tr('Allow notifications')),
          content: Text(
            c.tr(
              'In your browser, open the controls beside the address bar and allow Notifications. Then return to Jiggo.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(c.tr('OK')),
            ),
          ],
        ),
      );
      if (mounted) await controller.refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Open Jiggo notification permission in your device settings.',
              ),
            ),
          ),
        );
      }
    }
  }

  Widget _permission(NotificationController controller, bool on) {
    final blocked = controller.permission == NoticePermission.denied;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(
                blocked
                    ? 'Notifications are blocked. Allow them in settings.'
                    : 'Turn on notifications for important updates.',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: controller.busy
                  ? null
                  : blocked
                  ? () => _settings(controller)
                  : controller.enable,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                context.tr(blocked ? 'Open settings' : 'Enable notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = NotificationScope.of(context);
    final on =
        controller.enabled && controller.permission == NoticePermission.granted;
    final localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            widget.settingsOnly ? 'Notification settings' : 'Notifications',
          ),
        ),
        actions: [
          if (!widget.settingsOnly) ...[
            IconButton(
              tooltip: context.tr('Mark all as read'),
              onPressed: controller.notices.isEmpty
                  ? null
                  : controller.markAllRead,
              icon: const Icon(Icons.done_all),
            ),
            IconButton(
              tooltip: context.tr('Notification settings'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.busy) const LinearProgressIndicator(),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.tr(
                    'Notifications could not update. Check your connection and try again.',
                  ),
                ),
              ),
            if (widget.settingsOnly) ...[
              Icon(
                on
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Allow notifications')),
                subtitle: Text(
                  context.tr(on ? 'On for this device' : 'Off for this device'),
                ),
                value: on,
                onChanged: controller.busy || !controller.supported
                    ? null
                    : (value) {
                        if (value) {
                          if (controller.permission ==
                              NoticePermission.denied) {
                            _settings(controller);
                          } else {
                            controller.enable();
                          }
                        } else {
                          controller.disable();
                        }
                      },
              ),
              Text(
                context.tr(
                  'You can use every tool with notifications turned off.',
                ),
              ),
              if (controller.permission == NoticePermission.denied)
                TextButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => _settings(controller),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(context.tr('Open settings')),
                ),
              if (!controller.supported)
                Text(
                  context.tr('Notifications are not supported on this device.'),
                ),
              if (on && !controller.pushConfigured)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    context.tr(
                      'Updates are not ready on this device. Try updating Jiggo.',
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: controller.busy ? null : controller.refresh,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('Check again')),
              ),
            ] else ...[
              if (!on && controller.supported) _permission(controller, on),
              if (controller.notices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 64,
                    horizontal: 20,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr('No notifications yet'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr('Your updates will appear here.'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final notice in controller.notices)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    leading: Icon(
                      controller.isRead(notice.id)
                          ? Icons.notifications_none
                          : Icons.notifications_active_outlined,
                      color: controller.isRead(notice.id)
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      notice.title,
                      style: TextStyle(
                        fontWeight: controller.isRead(notice.id)
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (notice.body.isNotEmpty) Text(notice.body),
                        const SizedBox(height: 4),
                        Text(
                          '${localizations.formatShortDate(notice.sentAt.toLocal())} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(notice.sentAt.toLocal()))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    onTap: () => controller.openSaved(notice),
                    trailing: PopupMenuButton<String>(
                      tooltip: context.tr('Notification options'),
                      onSelected: (_) => controller.removeNotice(notice.id),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(context.tr('Delete')),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
