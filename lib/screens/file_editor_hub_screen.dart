import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import 'file_editor_screen.dart';
import 'docx_editor_screen.dart';
import 'image_editor_screen.dart';
import 'pdf_editor_screen.dart';

enum FileEditorKind { pdf, docx, image, text }

class FileEditorHubScreen extends StatelessWidget {
  final ValueChanged<FileEditorKind>? onSelected;
  const FileEditorHubScreen({super.key, this.onSelected});
  void _open(BuildContext context, FileEditorKind kind) {
    if (onSelected != null) {
      onSelected!(kind);
      return;
    }
    final Widget screen = switch (kind) {
      FileEditorKind.pdf => const PdfEditorScreen(autoOpen: true),
      FileEditorKind.docx => const DocxEditorScreen(),
      FileEditorKind.image => const ImageEditorScreen(),
      FileEditorKind.text => const FileEditorScreen(),
    };
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('File Editor'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              context.tr('What would you like to edit?'),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(context.tr('Choose a file type to get started.')),
            const SizedBox(height: 24),
            Card(
              color: colors.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 44,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('PDF Editor'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'Arrange pages. Add text, images and signatures.',
                      ),
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _open(context, FileEditorKind.pdf),
                      icon: const Icon(Icons.folder_open),
                      label: Text(context.tr('Open PDF')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final kind in [
              FileEditorKind.docx,
              FileEditorKind.image,
              FileEditorKind.text,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Icon(switch (kind) {
                      FileEditorKind.docx => Icons.description_outlined,
                      FileEditorKind.image => Icons.image_outlined,
                      _ => Icons.text_fields,
                    }, color: colors.primary),
                    title: Text(
                      context.tr(switch (kind) {
                        FileEditorKind.docx => 'Word Document',
                        FileEditorKind.image => 'Image Editor',
                        _ => 'Text Editor',
                      }),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      context.tr(switch (kind) {
                        FileEditorKind.docx => 'Edit DOCX text and formatting.',
                        FileEditorKind.image =>
                          'Crop, rotate, resize and add text.',
                        _ => 'Write, paste or open a TXT file.',
                      }),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, kind),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
