import '../services/app_strings.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'scan_history_details_screen.dart';

class RecentScans extends StatelessWidget {
  const RecentScans({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Text(context.tr('Log in to view your recent scans.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('scanHistory')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            context.tr(
              'Unable to load recent scans. Check your connection and account access.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final scans = snapshot.data!.docs;
        if (scans.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(context.tr('No scans yet'))),
            ),
          );
        }
        return Column(
          children: scans.map((scan) {
            final data = scan.data();
            final answer = (data['answer'] ?? '').toString();
            final language = (data['language'] ?? '').toString();
            final storedTitle = data['title'];
            final title = storedTitle is String && storedTitle.trim().isNotEmpty
                ? storedTitle.trim()
                : answer.replaceAll('\n', ' ');
            final timestamp = data['createdAt'];
            final date = timestamp is Timestamp
                ? timestamp.toDate().toLocal().toString().split('.')[0]
                : 'Just now';
            return Card(
              child: ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${context.tr(language)} • ${context.tr(date)}'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ScanHistoryDetailsScreen(
                      answer: answer,
                      language: language,
                      date: date,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
