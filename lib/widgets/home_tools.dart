import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/app_theme.dart';
import 'responsive_tools_grid.dart';

enum HomeTool { fileEditor, scanSolve, documentMaker, translator }

class HomeTools extends StatelessWidget {
  final ValueChanged<HomeTool> onSelected;
  const HomeTools({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const tools = [
      (
        HomeTool.fileEditor,
        'File Editor',
        'Edit text, documents & images',
        Icons.edit_document,
      ),
      (
        HomeTool.scanSolve,
        'Scan & Solve',
        'Solve questions',
        Icons.document_scanner_outlined,
      ),
      (
        HomeTool.documentMaker,
        'Document Maker',
        'CV, letters & more',
        Icons.description_outlined,
      ),
      (
        HomeTool.translator,
        'Translator',
        'Translate between languages',
        Icons.translate,
      ),
    ];
    return ResponsiveToolsGrid(
      children: [
        for (final (id, title, subtitle, icon) in tools)
          Material(
            key: ValueKey(id),
            color: context.cardColor,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelected(id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(title),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(subtitle),
                      style: TextStyle(fontSize: 12, color: context.mutedColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
