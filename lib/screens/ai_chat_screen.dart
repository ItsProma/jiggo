import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/ai_eligibility_service.dart';
import '../services/ai_limit_messages.dart';
import '../services/app_strings.dart';
import '../services/app_theme.dart';
import '../services/chat_gateway.dart';
import '../widgets/ai_report_button.dart';
import 'chat_history_sheet.dart';

class AiChatScreen extends StatefulWidget {
  final String initialQuestion;
  final ChatGateway? gateway;
  final bool showHistoryOnOpen;
  const AiChatScreen({
    super.key,
    this.initialQuestion = '',
    this.gateway,
    this.showHistoryOnOpen = false,
  });
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  late final ChatGateway _gateway;
  late final _input = TextEditingController(text: widget.initialQuestion);
  final _scroll = ScrollController();
  String _chatId = newChatId();
  List<ChatMessage> _messages = [];
  Map<String, dynamic>? _pending;
  bool _busy = false;
  bool _unsaved = false;
  bool _initialized = false;
  String _language = 'Bangla';
  String? _error;
  int? _remaining;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseChatGateway();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _language = Localizations.localeOf(context).languageCode == 'bn'
        ? 'Bangla'
        : 'English';
    if (widget.initialQuestion.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send();
      });
    } else if (widget.showHistoryOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _history();
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _revealLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  String _messageFor(Object error) {
    if (error is FirebaseFunctionsException) {
      final reason = error.details is Map
          ? (error.details as Map)['reason']
          : null;
      final specific = switch (reason) {
        'chat-daily' =>
          'You have used today’s 20 chat replies. Try again tomorrow.',
        'chat-full' =>
          'This chat has reached 20 replies. Start a new chat to continue.',
        'chat-busy' =>
          'Another message is still being answered. Wait, then check history.',
        'chat-pending' => 'The previous request is still pending or its outcome is unknown. Check history before sending again.',
        'chat-missing' =>
          'This chat was deleted or is unavailable. Start a new chat.',
        _ => null,
      };
      if (specific != null) return specific;
      final safety = aiSafetyMessage(error.details);
      if (safety != null) return safety;
      if (error.code == 'resource-exhausted') {
        return aiLimitMessage(error.details);
      }
      if (error.code == 'unauthenticated') return 'Please log in first.';
      if (error.code == 'not-found') {
        return 'Chat service is not available yet. Complete the server setup first.';
      }
    }
    return 'Unable to send. Retry checks the same request. Check history if it timed out.';
  }

  Future<void> _send({bool retry = false}) async {
    if (_busy || _unsaved || (!retry && _pending != null)) return;
    final text = retry
        ? (_pending?['message'] as String? ?? '')
        : _input.text.trim();
    if (text.isEmpty || text.length > 2000) {
      setState(() => _error = 'Write a message using 1–2000 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.gateway == null &&
          !await AiEligibilityService.ensure(context)) {
        return;
      }
      if (!mounted) return;
      _pending ??= {
        'action': 'send',
        'chatId': _chatId,
        'requestId': newChatId(),
        'message': text,
        'language': _language,
      };
      setState(() => _input.clear());
      _revealLatest();
      final result = await _gateway.call(_pending!);
      final chat = ChatConversation.fromMap(result['chat'] as Map);
      if (!mounted) return;
      if (chat.id != _chatId) throw const FormatException('Chat changed');
      setState(() {
        _messages = chat.messages;
        _pending = null;
        _unsaved = result['saved'] != true;
        _remaining = (result['remainingToday'] as num?)?.toInt();
      });
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _revealLatest();
      }
    }
  }

  Future<bool> _confirmLeavingDraft() async {
    if (_pending == null && !_unsaved && _input.text.trim().isEmpty) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(context.tr('Leave this draft?')),
            content: Text(
              context.tr(
                'Copy any unsaved text first. A request already sent may still finish and appear in history.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr('Continue')),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _reset() => setState(() {
    _chatId = newChatId();
    _messages = [];
    _pending = null;
    _unsaved = false;
    _input.clear();
    _error = null;
    _remaining = null;
  });

  Future<void> _newChat() async {
    if (_busy || !await _confirmLeavingDraft() || !mounted) return;
    _reset();
  }

  Future<void> _read(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _gateway.call({'action': 'read', 'chatId': id});
      final chat = ChatConversation.fromMap(result['chat'] as Map);
      if (!mounted) return;
      if (chat.id != id) throw const FormatException('Chat changed');
      setState(() {
        _chatId = id;
        _messages = chat.messages;
        _unsaved = false;
        _pending = null;
        _input.clear();
        _remaining = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _revealLatest();
      }
    }
  }

  Future<void> _checkCurrent() async {
    if (_busy) return;
    // Keep a pending request ID if it has not appeared in history yet. This
    // prevents a history refresh from silently turning Retry into a new charge.
    if (_unsaved && !await _confirmLeavingDraft()) return;
    if (!mounted) return;
    final pending = _pending;
    setState(() => _busy = true);
    try {
      final result = await _gateway.call({'action': 'read', 'chatId': _chatId});
      final data = result['chat'] as Map;
      final chat = ChatConversation.fromMap(data);
      if (!mounted) return;
      if (chat.id != _chatId) throw const FormatException('Chat changed');
      final found = (data['messages'] as List).any(
        (m) =>
            m['role'] == 'assistant' && m['requestId'] == pending?['requestId'],
      );
      setState(() {
        _messages = chat.messages;
        _unsaved = false;
        if (found) _pending = null;
        _error = _pending == null ? null : 'The previous request is still pending or its outcome is unknown. Check history before sending again.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _history() async {
    if (_busy || !await _confirmLeavingDraft() || !mounted) return;
    FocusScope.of(context).unfocus();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChatHistorySheet(gateway: _gateway, activeId: _chatId),
    );
    if (!mounted || id == null) return;
    if (id.isEmpty) {
      _reset();
    } else {
      await _read(id);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('Copied'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = [
      ..._messages,
      if (_pending != null) ChatMessage('user', _pending!['message'] as String),
    ];
    return Scaffold(
      backgroundColor: context.pageColor,
      appBar: AppBar(
        title: Text(context.tr('AI Chat')),
        actions: [
          IconButton(
            key: const ValueKey('chat-history'),
            tooltip: context.tr('Chat history'),
            onPressed: _busy ? null : _history,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            key: const ValueKey('chat-new'),
            tooltip: context.tr('New chat'),
            onPressed: _busy ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    context.tr(
                      'Ask a question or continue a conversation. Recent messages provide context. AI answers can be wrong.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final message in displayed)
                    Card(
                      color: message.role == 'user'
                          ? Theme.of(context).colorScheme.primaryContainer
                          : context.cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    context.tr(
                                      message.role == 'user' ? 'You' : 'Jiggo',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('Copy'),
                                  onPressed: () => _copy(message.text),
                                  icon: const Icon(
                                    Icons.copy_outlined,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                            MarkdownBody(data: message.text, selectable: true),
                            if (message.role == 'assistant')
                              AiReportButton(
                                source: 'chat',
                                content: message.text,
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_busy)
                    Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(context.tr('Please wait...'))),
                      ],
                    ),
                  if (_remaining != null)
                    Text(
                      context.tr('Chat replies remaining today: {count}', {
                        'count': _remaining,
                      }),
                    ),
                  if (_unsaved)
                    Text(
                      context.tr(
                        'This reply could not be saved. Copy it before leaving. Check history before continuing.',
                      ),
                    ),
                  if (_error != null)
                    Text(
                      context.tr(_error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_pending != null || _unsaved)
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_pending != null)
                          TextButton(
                            key: const ValueKey('chat-retry'),
                            onPressed: _busy ? null : () => _send(retry: true),
                            child: Text(context.tr('Retry')),
                          ),
                        TextButton(
                          key: const ValueKey('chat-check'),
                          onPressed: _busy ? null : _checkCurrent,
                          child: Text(context.tr('Check history')),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: const ValueKey('chat-language'),
                    initialValue: _language,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('Reply language'),
                    ),
                    items: [
                      for (final language in ['Bangla', 'English'])
                        DropdownMenuItem(
                          value: language,
                          child: Text(context.tr(language)),
                        ),
                    ],
                    onChanged: _busy || _pending != null || _unsaved
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _language = value);
                            }
                          },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-input'),
                          controller: _input,
                          enabled: !_busy && _pending == null && !_unsaved,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          maxLengthEnforcement: MaxLengthEnforcement.none,
                          buildCounter: (
                            context, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => Text('${_input.text.length}/2000'),
                          decoration: InputDecoration(
                            hintText: context.tr('Write a message...'),
                          ),
                        ),
                      ),
                      IconButton.filled(
                        key: const ValueKey('chat-send'),
                        tooltip: context.tr('Send message'),
                        onPressed: _busy || _pending != null || _unsaved
                            ? null
                            : _send,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
