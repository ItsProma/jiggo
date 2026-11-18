import '../services/app_theme.dart';
import '../services/app_strings.dart';
import 'ai_document_screen.dart';

import 'package:flutter/material.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  void _comingSoon(BuildContext context, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiDocumentScreen(documentType: title),
      ),
    );
  }

  Widget _documentTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
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
        onTap: () => _comingSoon(context, title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageColor,
      appBar: AppBar(
        backgroundColor: context.pageColor,
        title: Text(
          context.tr('Document Maker'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.tr('Create with AI'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Choose a document type and let Jiggo help you write it.',
            ),
            style: TextStyle(color: context.mutedColor),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.adaptiveTint(const Color(0xFFE6E9FF)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 32, color: context.accentColor),
                const SizedBox(height: 12),
                Text(
                  context.tr('Custom AI Document'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Describe what you need and Jiggo will help you create it.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _comingSoon(context, 'Custom AI Document'),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('Create Document')),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          Text(
            context.tr('Popular Documents'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),

          _documentTile(
            context,
            title: 'CV / Resume',
            subtitle: 'Create a professional CV',
            icon: Icons.badge_outlined,
            color: context.adaptiveTint(const Color(0xFFE6E9FF)),
          ),
          _documentTile(
            context,
            title: 'Job Application',
            subtitle: 'Write a job application letter',
            icon: Icons.work_outline,
            color: context.adaptiveTint(const Color(0xFFDFF5ED)),
          ),
          _documentTile(
            context,
            title: 'Leave Application',
            subtitle: 'School, college or office leave',
            icon: Icons.edit_document,
            color: context.adaptiveTint(const Color(0xFFFFF0DD)),
          ),
          _documentTile(
            context,
            title: 'Formal Letter',
            subtitle: 'Official and personal letters',
            icon: Icons.mail_outline,
            color: context.adaptiveTint(const Color(0xFFF6E7FF)),
          ),
          _documentTile(
            context,
            title: 'Invoice',
            subtitle: 'Create a business invoice',
            icon: Icons.receipt_long_outlined,
            color: context.adaptiveTint(const Color(0xFFE0F2FE)),
          ),
          _documentTile(
            context,
            title: 'Assignment',
            subtitle: 'Create an academic document',
            icon: Icons.menu_book_outlined,
            color: context.adaptiveTint(const Color(0xFFFFE4E6)),
          ),
        ],
      ),
    );
  }
}
