import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/document_brief.dart';

class DocumentDetailsDialog extends StatefulWidget {
  final DocumentBrief brief;
  final String details;
  final Map<String, String> answers;
  final List<BriefQuestion> questions;
  const DocumentDetailsDialog({
    super.key,
    required this.brief,
    required this.details,
    required this.answers,
    required this.questions,
  });

  @override
  State<DocumentDetailsDialog> createState() => _DocumentDetailsDialogState();
}

class _DocumentDetailsDialogState extends State<DocumentDetailsDialog> {
  late final _controllers = {
    for (final q in widget.questions)
      q.id: TextEditingController(text: widget.answers[q.id] ?? ''),
  };

  Map<String, String> get _answers => {
    ...widget.answers,
    for (final entry in _controllers.entries)
      entry.key: entry.value.text.trim(),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final length = widget.brief.compose(widget.details, _answers).length;
    final needsPurpose =
        widget.brief.type == 'Custom AI Document' &&
        widget.details.trim().length < 10 &&
        (_answers['purpose'] ?? '').length < 10;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      title: Text(context.tr('A few details to confirm')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'Already explained above? Leave it blank. Unknown details will use editable placeholders.',
                ),
              ),
              const SizedBox(height: 16),
              for (final q in widget.questions) ...[
                Text(context.tr(q.label)),
                const SizedBox(height: 6),
                TextFormField(
                  key: ValueKey('brief-${q.id}'),
                  controller: _controllers[q.id],
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: context.tr(q.hint),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                context.tr('Total details: {count}/2000', {'count': length}),
              ),
              if (length > 2000)
                Text(
                  context.tr('Shorten your details or answers to continue.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (needsPurpose)
                Text(
                  context.tr(
                    'Describe what to create using at least 10 characters.',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('confirm-document-details'),
          onPressed: length > 2000 || needsPurpose
              ? null
              : () => Navigator.pop(context, _answers),
          child: Text(context.tr('Continue')),
        ),
      ],
    );
  }
}
