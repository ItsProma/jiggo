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

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  String _target = 'library';
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
        builder: (context) => AlertDialog(
          title: Text(context.tr('Browser notification settings')),
          content: Text(
            context.tr(
              'Open the site controls beside the address bar, choose Site settings, and allow Notifications. Then return here and tap Refresh.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('OK')),
            ),
          ],
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final controller = NotificationScope.of(context);
    final on =
        controller.enabled && controller.permission == NoticePermission.granted;
    final status = !controller.supported
        ? 'Notifications are not supported on this device.'
        : controller.permission == NoticePermission.denied
        ? 'Permission is blocked in device or browser settings.'
        : on
        ? 'Notifications are on for this device.'
        : 'Notifications are off. You can still use Jiggo.';
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Notifications'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            on
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(context.tr(status), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (controller.busy) const LinearProgressIndicator(),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.tr(controller.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (controller.supported) ...[
            FilledButton.icon(
              onPressed: controller.busy
                  ? null
                  : on
                  ? controller.disable
                  : controller.enable,
              icon: Icon(
                on
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
              ),
              label: Text(
                context.tr(
                  on ? 'Turn off on this device' : 'Enable notifications',
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => _settings(controller),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(context.tr('Open permission settings')),
                ),
                TextButton.icon(
                  onPressed: controller.busy ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.tr('Refresh')),
                ),
              ],
            ),
            const Divider(height: 32),
            Text(
              context.tr('Test on this device'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('A test notification opens your Library when tapped.'),
            ),
            OutlinedButton.icon(
              onPressed: on && !controller.busy
                  ? () => controller.testDevice(
                      title: context.tr('Jiggo test notification'),
                      body: context.tr('This is a test. Tap to open Library.'),
                    )
                  : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(context.tr('Show device test')),
            ),
            const Divider(height: 32),
            Text(
              context.tr('Remote notifications'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                !controller.pushConfigured
                    ? 'Web push needs the public Firebase web-push key. Device testing is available without it.'
                    : controller.registered
                    ? 'This device is connected for remote notifications.'
                    : 'Enable notifications and reconnect to register this device.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _target,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Test opens')),
              items: [
                for (final target in notificationTargets)
                  DropdownMenuItem(
                    value: target,
                    child: Text(context.tr(notificationTargetLabel(target))),
                  ),
              ],
              onChanged: controller.busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _target = value);
                    },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: on && controller.registered && !controller.busy
                  ? () => controller.testPush(_target)
                  : null,
              icon: const Icon(Icons.cloud_outlined),
              label: Text(context.tr('Send push test')),
            ),
            Text(
              context.tr(
                'Up to 5 push tests per day. Allow 30 seconds between tests.',
              ),
            ),
          ],
          const Divider(height: 32),
          Text(
            context.tr('Received in this session'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (controller.notices.isEmpty)
            Text(context.tr('No notifications received in this session.')),
          for (final notice in controller.notices)
            Card(
              child: ListTile(
                isThreeLine: true,
                title: Text(notice.title),
                subtitle: Text(notice.body),
                leading: const Icon(Icons.notifications_outlined),
                onTap: () => controller.open(notice),
              ),
            ),
        ],
      ),
    );
  }
}
