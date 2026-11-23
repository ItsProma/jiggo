import 'handwriting_screen.dart';
import 'scan_pdf_screen.dart';
import '../services/app_theme.dart';
import '../services/app_strings.dart';

import 'dart:async' as async_utils;

import '../services/ai_eligibility_service.dart';
import '../services/ads_service.dart';
import '../widgets/ai_report_button.dart';

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../services/scan_image.dart';
import '../services/ai_limit_messages.dart';
import 'recent_scans.dart';

class ScanScreen extends StatefulWidget {
  final ImageSource? initialSource;
  const ScanScreen({super.key, this.initialSource});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _selectedImage;
  String? _selectedFileName;
  String _language = 'bn';
  String? _historyWarning;
  bool _isPicking = false;
  bool _isSolving = false;
  String? _aiAnswer;
  String? _aiError;
  int? _remainingScans;

  @override
  void initState() {
    super.initState();
    if (widget.initialSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickImage(widget.initialSource!);
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPicking || _isSolving) return;

    setState(() => _isPicking = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );

      if (image == null) return;

      final originalBytes = await image.readAsBytes();
      final bytes = await ScanImage.prepare(originalBytes);

      if (!mounted) return;

      setState(() {
        _selectedImage = bytes;
        _selectedFileName = image.name;
        _aiAnswer = null;
        _aiError = null;
        _remainingScans = null;
        _historyWarning = null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr(error.message))));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Unable to select an image. Check camera or photo permission and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _solveWithAI() async {
    if (_isSolving || _isPicking || _selectedImage == null) return;

    final imageBytes = _selectedImage!;
    final ownerUid = AiEligibilityService.currentUid;

    late final String mimeType;
    try {
      mimeType = ScanImage.validate(imageBytes);
    } on FormatException catch (error) {
      setState(() => _aiError = error.message);
      return;
    }

    setState(() {
      _isSolving = true;
      _historyWarning = null;
      _aiError = null;
      _aiAnswer = null;
    });

    try {
      if (!await AiEligibilityService.ensure(context)) {
        return;
      }
      if (!mounted || AiEligibilityService.currentUid != ownerUid) {
        return;
      }
      async_utils.unawaited(AdsService.instance.start());
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

      final callable = functions.httpsCallable(
        'solveQuestion',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
      );

      final result = await callable.call<Map<String, dynamic>>({
        'imageBase64': base64Encode(imageBytes),
        'expectedUid': ownerUid,
        'mimeType': mimeType,
        'language': _language,
      });

      if (!mounted) return;

      if (AiEligibilityService.currentUid != ownerUid) {
        return;
      }
      final data = result.data;
      final answer = data['answer'];
      if (answer is! String || answer.trim().isEmpty) {
        throw const FormatException('Empty AI response');
      }
      setState(() {
        _aiAnswer = answer;
        _remainingScans = (data['remainingToday'] as num?)?.toInt();
        // Older deployed functions do not return historySaved. Do not claim
        // that those results were saved until the backend update is deployed.
        _historyWarning = data['historySaved'] == true ? null : 'History saving could not be confirmed. Copy this answer before leaving.';
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      setState(() {
        _aiError = _solveError(e.code, e.details);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _aiError = 'Unable to solve the question. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSolving = false);
      }
    }
  }

  void _removeImage() {
    if (_isSolving || _isPicking) return;

    setState(() {
      _selectedImage = null;
      _selectedFileName = null;
      _aiAnswer = null;
      _aiError = null;
      _remainingScans = null;
      _historyWarning = null;
    });
  }

  String _solveError(String code, [Object? details]) {
    final safety = aiSafetyMessage(details);
    if (safety != null) {
      return safety;
    }
    switch (code) {
      case 'resource-exhausted':
        return aiLimitMessage(details);
      case 'unauthenticated':
        return 'Sign-in or app verification failed. Reopen Jiggo and try again.';
      case 'failed-precondition':
        if (details is Map && details['reason'] == 'account-deletion') {
          return 'This account is being deleted. AI requests are blocked.';
        }
        return 'Unable to verify this account. Please reopen the app.';
      case 'permission-denied':
        return 'App verification failed. Please reopen the app and try again.';
      case 'deadline-exceeded':
        return 'The request timed out. Check Library before trying again; the scan may have finished.';
      case 'unavailable':
        return 'Unable to connect. Check your internet connection and try again.';
      case 'invalid-argument':
        return 'Please choose a valid JPG, PNG or WebP image, 2 MB or smaller.';
      default:
        return 'Unable to solve this image right now. Please try again later.';
    }
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('{feature} is coming soon', {
            'feature': context.tr(feature),
          }),
        ),
      ),
    );
  }

  Widget _toolTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      color: context.cardColor,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.adaptiveTint(color),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: context.accentColor),
        ),
        title: Text(
          context.tr(title),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(context.tr(subtitle)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ?? () => _comingSoon(title),
      ),
    );
  }

  String? _extractFinalAnswer(String answer) {
    for (final line in answer.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.startsWith('FINAL_ANSWER:')) {
        final result = trimmed.substring('FINAL_ANSWER:'.length).trim();
        return result.isEmpty ? null : result;
      }
    }

    return null;
  }

  List<Widget> _buildAnswerParts(String answer) {
    final widgets = <Widget>[];

    final mathPattern = RegExp(
      r'(\$\$[\s\S]+?\$\$|\$[^\$\n]+\$|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\))',
    );

    int lastEnd = 0;

    for (final match in mathPattern.allMatches(answer)) {
      if (match.start > lastEnd) {
        final textPart = answer.substring(lastEnd, match.start);

        if (textPart.trim().isNotEmpty) {
          widgets.add(
            MarkdownBody(
              data: textPart.replaceAll('---', ''),
              selectable: true,
              softLineBreak: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, height: 1.6),
                pPadding: const EdgeInsets.only(bottom: 12),
              ),
            ),
          );
        }
      }

      String formula = match.group(0)!;

      if (formula.startsWith(r'$$')) {
        formula = formula.substring(2, formula.length - 2);
      } else if (formula.startsWith(r'\[') || formula.startsWith(r'\(')) {
        formula = formula.substring(2, formula.length - 2);
      } else {
        formula = formula.substring(1, formula.length - 1);
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              formula.replaceAllMapped(
                RegExp(r'(?<!\\)\bfrac(?=\s*\{)'),
                (match) => r'\frac',
              ),
              textStyle: const TextStyle(fontSize: 18),
              onErrorFallback: (error) => SelectableText(formula),
            ),
          ),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < answer.length) {
      final remainingText = answer.substring(lastEnd);

      if (remainingText.trim().isNotEmpty) {
        widgets.add(
          MarkdownBody(
            data: remainingText.replaceAll('---', ''),
            selectable: true,
            softLineBreak: true,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(fontSize: 16, height: 1.6),
              pPadding: const EdgeInsets.only(bottom: 12),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageColor,
      appBar: AppBar(
        backgroundColor: context.pageColor,
        title: Text(
          context.tr('AI Scan'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.tr('Scan anything'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Upload questions or documents only. Avoid faces and personal details.',
            ),
            style: TextStyle(color: context.mutedColor),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.adaptiveTint(const Color(0xFFE6E9FF)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                if (_selectedImage == null) ...[
                  Icon(
                    Icons.document_scanner_outlined,
                    size: 64,
                    color: context.accentColor,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.tr('Scan & Solve'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'Take a photo of a question and get a step-by-step explanation.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      _selectedImage!,
                      height: 240,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stackTrace) => Text(
                        context.tr(
                          'Unable to preview this image. Please choose another photo.',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr(_selectedFileName ?? 'Selected image'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  TextButton.icon(
                    onPressed: _isSolving || _isPicking ? null : _removeImage,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(context.tr('Remove Image')),
                  ),
                ],

                const SizedBox(height: 20),

                FilledButton.icon(
                  onPressed: _isPicking || _isSolving
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(context.tr('Take Photo')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isPicking || _isSolving
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(context.tr('Upload from Gallery')),
                ),

                if (_isPicking) ...[
                  const SizedBox(height: 14),
                  const CircularProgressIndicator(),
                ],

                if (_selectedImage != null) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration: InputDecoration(
                      labelText: context.tr('Explanation language'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'bn',
                        child: Text(context.tr('বাংলা')),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(context.tr('English')),
                      ),
                    ],
                    onChanged: _isSolving || _isPicking
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _language = value);
                            }
                          },
                  ),
                  const SizedBox(height: 16),

                  FilledButton.icon(
                    onPressed: _isSolving || _isPicking ? null : _solveWithAI,
                    icon: _isSolving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      context.tr(_isSolving ? 'Solving...' : 'Solve with AI'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (_aiError != null) ...[
            Card(
              color: context.adaptiveTint(const Color(0xFFFFEBEE)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.tr(_aiError!),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_historyWarning != null) ...[
            Card(
              color: context.adaptiveTint(const Color(0xFFFFF4DE)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.tr(_historyWarning!)),
              ),
            ),
          ],
          if (_aiAnswer != null) ...[
            Card(
              elevation: 0,
              color: context.adaptiveTint(const Color(0xFFFAFBFF)),
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: context.adaptiveTint(const Color(0xFFE0E5FF)),
                  width: 1.2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.adaptiveTint(
                              const Color(0xFFEEF0FF),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            color: context.accentColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('AI Solution'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                context.tr('Step-by-step explanation'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.mutedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.check_circle,
                          color: Color(0xFF16A34A),
                          size: 22,
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(context.tr('Copy answer')),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(text: _aiAnswer!),
                          );
                          if (!mounted ||
                              !context.mounted ||
                              !messenger.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(context.tr('Answer copied')),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    AiReportButton(source: 'scan', content: _aiAnswer!),
                    ..._buildAnswerParts(
                      _aiAnswer!
                          .split('\n')
                          .where(
                            (line) => !line.trim().startsWith('FINAL_ANSWER:'),
                          )
                          .join('\n'),
                    ),
                    if (_extractFinalAnswer(_aiAnswer!) != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.adaptiveTint(const Color(0xFFEAF8EF)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: context.adaptiveTint(
                              const Color(0xFFBBE7C8),
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  context.tr('Final Answer'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _extractFinalAnswer(_aiAnswer!)!,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_remainingScans != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        context.tr('Remaining scans today: {count}', {
                          'count': _remainingScans,
                        }),
                        style: TextStyle(
                          color: context.mutedColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 28),
          Text(
            context.tr('More Scan Tools'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),

          _toolTile(
            title: 'Scan to PDF',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const ScanPdfScreen()),
            ),
            subtitle: 'Convert documents into PDF files',
            icon: Icons.picture_as_pdf_outlined,
            color: context.adaptiveTint(const Color(0xFFFFF0DD)),
          ),
          _toolTile(
            title: 'Handwriting Recognition',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const HandwritingScreen(),
              ),
            ),
            subtitle: 'Convert handwritten notes into text',
            icon: Icons.draw_outlined,
            color: context.adaptiveTint(const Color(0xFFF6E7FF)),
          ),

          const SizedBox(height: 20),
          Text(
            context.tr('Recent Scans'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const RecentScans(),
        ],
      ),
    );
  }
}
