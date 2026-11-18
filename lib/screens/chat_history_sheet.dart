import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/chat_gateway.dart';

/// Returns a chat ID to open, or an empty string after deleting the active chat.
class ChatHistorySheet extends StatefulWidget {
  final ChatGateway gateway;
  final String activeId;
  const ChatHistorySheet({
    super.key,
    required this.gateway,
    required this.activeId,
  });
  @override
  State<ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<ChatHistorySheet> {
  final List<Map<String, dynamic>> _chats = [];
  bool _busy = false;
  bool _failed = false;
  String? _cursor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await widget.gateway.call({
        'action': 'list',
        if (_cursor != null) 'cursor': _cursor,
      });
      final page = (result['chats'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        for (final item in page) {
          if (!_chats.any((c) => c['id'] == item['id'])) _chats.add(item);
        }
        _cursor = result['nextCursor'] as String?;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.tr('Delete chat?')),
        content: Text(
          context.tr(
            'This removes the saved conversation and cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.call({'action': 'delete', 'chatId': id});
      if (!mounted) return;
      if (id == widget.activeId) {
        Navigator.pop(context, '');
      } else {
        setState(() => _chats.removeWhere((c) => c['id'] == id));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Unable to delete chat. Try again.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          ListTile(
            title: Text(context.tr('Chat history')),
            trailing: IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final chat in _chats)
                  ListTile(
                    title: Text(
                      chat['title'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: _busy
                        ? null
                        : () => Navigator.pop(context, chat['id'] as String),
                    trailing: IconButton(
                      tooltip: context.tr('Delete chat'),
                      onPressed: _busy
                          ? null
                          : () => _delete(chat['id'] as String),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                if (!_busy && !_failed && _chats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.tr('No saved chats yet.')),
                  ),
                if (_busy) const Center(child: CircularProgressIndicator()),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.tr(
                        'Unable to load chats. Check your connection.',
                      ),
                    ),
                  ),
                if (_failed || _cursor != null)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: Text(
                      context.tr(_failed ? 'Retry' : 'Load older chats'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
