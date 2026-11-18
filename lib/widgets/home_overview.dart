import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/app_theme.dart';
import 'home_tools.dart';

/// Home content without Firebase side effects, so layout can be tested directly.
class HomeOverview extends StatelessWidget {
  final TextEditingController promptController;
  final ValueChanged<HomeTool> onToolSelected;
  final ValueChanged<String> onUnavailable;
  final VoidCallback onOpenLibrary;
  final ValueChanged<String>? onSubmit;
  const HomeOverview({
    super.key,
    required this.promptController,
    required this.onToolSelected,
    required this.onUnavailable,
    required this.onOpenLibrary,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Text(
          context.tr('What can I help you with?'),
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('Ask anything, scan a question or create a document.'),
          style: TextStyle(color: context.mutedColor),
        ),
        const SizedBox(height: 16),

        // AI Chat Input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              TextField(
                controller: promptController,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  hintText: context.tr('Ask Jiggo anything...'),
                  border: InputBorder.none,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () => onUnavailable('Attachment'),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    onPressed: () => onUnavailable('Camera'),
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                  IconButton(
                    onPressed: () => onUnavailable('Voice Input'),
                    icon: const Icon(Icons.mic_none),
                  ),
                  const Spacer(),
                  IconButton.filled(
                    key: const ValueKey('home-chat-send'),
                    tooltip: context.tr('Send message'),
                    onPressed: () {
                      onSubmit?.call(promptController.text.trim());
                    },
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ],
          ),
        ),

        TextButton.icon(
          key: const ValueKey('home-chat-history'),
          onPressed: onSubmit == null ? null : () => onSubmit!(''),
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(context.tr('AI Chat & history')),
        ),
        const SizedBox(height: 20),
        Text(
          context.tr('Explore Tools'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        HomeTools(onSelected: onToolSelected),

        const SizedBox(height: 20),
        Text(
          context.tr('Recent Activity'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          color: context.cardColor,
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(context.tr('My Documents')),
            subtitle: Text(context.tr('Open your saved documents and scans')),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenLibrary,
          ),
        ),
      ],
    ),
  );
}
