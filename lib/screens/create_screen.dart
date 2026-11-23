import 'guided_document_screen.dart';
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
        builder: (context) => title == 'Custom AI Document'
            ? const AiDocumentScreen()
            : GuidedDocumentScreen(documentType: title),
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
            context.tr('Create a document'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('Choose a type and answer a few simple questions.'),
            style: TextStyle(color: context.mutedColor),
          ),
          const SizedBox(height: 24),

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
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(context.tr('Custom AI Document')),
              subtitle: Text(context.tr('Write your own instructions')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _comingSoon(context, 'Custom AI Document'),
            ),
          ),
        ],
      ),
    );
  }
}
