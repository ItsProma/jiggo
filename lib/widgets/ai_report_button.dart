import '../services/app_strings.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class AiReportButton extends StatelessWidget {
  final String source;
  final String content;
  const AiReportButton({
    super.key,
    required this.source,
    required this.content,
  });

  Future<void> _report(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    var text = content.length > 20000 ? content.substring(0, 20000) : content;
    var reason = 'inappropriate';
    var note = '';
    var sending = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: !sending,
          child: AlertDialog(
            scrollable: true,
            title: Text(context.tr('Report AI content')),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr(
                        'The text and note you choose below will be sent to the developer for review. Remove personal information you do not want to share.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: InputDecoration(
                        labelText: context.tr('Reason'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'inappropriate',
                          child: Text(context.tr('Inappropriate content')),
                        ),
                        DropdownMenuItem(
                          value: 'harmful',
                          child: Text(context.tr('Harmful or unsafe')),
                        ),
                        DropdownMenuItem(
                          value: 'incorrect',
                          child: Text(context.tr('Incorrect information')),
                        ),
                        DropdownMenuItem(
                          value: 'personal-data',
                          child: Text(context.tr('Personal information')),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text(context.tr('Other')),
                        ),
                      ],
                      onChanged: sending
                          ? null
                          : (value) {
                              if (value != null) {
                                reason = value;
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: text,
                      enabled: !sending,
                      maxLength: 20000,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: context.tr('Reported text'),
                      ),
                      onChanged: (value) => text = value,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? context.tr('Include the text you want to report')
                          : null,
                    ),
                    TextFormField(
                      enabled: !sending,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: context.tr('Additional details (optional)'),
                      ),
                      onChanged: (value) => note = value,
                    ),
                    if (error != null)
                      Text(
                        context.tr(error!),
                        style: const TextStyle(color: Colors.red),
                      ),
                    if (sending) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(dialogContext),
                child: Text(context.tr('Cancel')),
              ),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (formKey.currentState?.validate() != true) {
                          return;
                        }
                        setDialogState(() {
                          sending = true;
                          error = null;
                        });
                        try {
                          final callable =
                              FirebaseFunctions.instanceFor(
                                region: 'europe-west1',
                              ).httpsCallable(
                                'reportAiContent',
                                options: HttpsCallableOptions(
                                  timeout: const Duration(seconds: 40),
                                ),
                              );
                          final result = await callable
                              .call<Map<String, dynamic>>({
                                'source': source,
                                'content': text.trim(),
                                'reason': reason,
                                'note': note.trim(),
                              });
                          if (result.data['received'] != true) {
                            throw StateError('Report not confirmed');
                          }
                          if (!dialogContext.mounted) {
                            return;
                          }
                          Navigator.pop(dialogContext);
                          if (messenger.mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.tr('Report received. Thank you.'),
                                ),
                              ),
                            );
                          }
                        } on FirebaseFunctionsException catch (failure) {
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {
                            error = switch (failure.code) {
                              'resource-exhausted' => 'Daily report limit reached. Please try again tomorrow.',
                              'not-found' || 'unimplemented' => 'Reporting is not available yet. Please try again after the service is updated.',
                              'unauthenticated' =>
                                'Please sign in before submitting a report.',
                              _ =>
                                'Unable to send your report. Please try again.',
                            };
                          });
                        } catch (_) {
                          if (dialogContext.mounted) {
                            setDialogState(
                              () => error = 'Unable to send your report. Please try again.',
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => sending = false);
                          }
                        }
                      },
                child: Text(context.tr(sending ? 'Sending…' : 'Submit report')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: content.trim().isEmpty ? null : () => _report(context),
      icon: const Icon(Icons.flag_outlined, size: 18),
      label: Text(context.tr('Report AI content')),
    );
  }
}
