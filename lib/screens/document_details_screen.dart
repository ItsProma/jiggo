import '../services/app_theme.dart';
import '../services/app_strings.dart';
import '../widgets/ai_report_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'document_editor_screen.dart';

import '../services/pdf_export_service.dart';

class DocumentDetailsScreen extends StatefulWidget {
  final String documentId;
  final String title;
  final String content;
  final String documentType;
  final String language;

  const DocumentDetailsScreen({
    super.key,
    required this.documentId,
    required this.title,
    required this.content,
    required this.documentType,
    required this.language,
  });

  @override
  State<DocumentDetailsScreen> createState() => _DocumentDetailsScreenState();
}

class _DocumentDetailsScreenState extends State<DocumentDetailsScreen> {
  bool _isExporting = false;

  Future<void> _downloadPdf() async {
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
    });

    try {
      await PdfExportService.exportDocument(
        title: widget.title,
        content: widget.content,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('Unable to export PDF. Please try again.')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageColor,
      appBar: AppBar(
        backgroundColor: context.pageColor,
        title: Text(context.tr('Document Details')),
        actions: [
          IconButton(
            tooltip: context.tr('Copy document'),
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.content));

              if (!context.mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.tr('Document copied successfully')),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${context.tr(widget.documentType)} • ${context.tr(widget.language)}',
            style: TextStyle(color: context.mutedColor),
          ),
          AiReportButton(source: 'document', content: widget.content),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isExporting ? null : _downloadPdf,
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                context.tr(_isExporting ? 'Preparing PDF...' : 'Download PDF'),
              ),
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DocumentEditorScreen(
                      documentId: widget.documentId,
                      title: widget.title,
                      content: widget.content,
                    ),
                  ),
                );

                if (saved == true && context.mounted) {
                  Navigator.pop(context);
                }
              },

              icon: const Icon(Icons.edit_outlined),
              label: Text(context.tr('Edit Document')),
            ),
          ),
          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: MarkdownBody(data: widget.content, selectable: true),
          ),
        ],
      ),
    );
  }
}
