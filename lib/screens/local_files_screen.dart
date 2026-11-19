import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../widgets/local_files_panel.dart';

class LocalFilesScreen extends StatelessWidget {
  final String userId;
  final String? Function()? currentOwner;
  const LocalFilesScreen({super.key, required this.userId, this.currentOwner});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Local files'))),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LocalFilesPanel(userId: userId, currentOwner: currentOwner),
      ),
    ),
  );
}
