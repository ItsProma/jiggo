import '../services/app_theme.dart';
import '../services/app_strings.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'all_library_items.dart';
import 'ai_chat_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  late final Stream<User?> _authChanges;
  int _selectedFilter = 0;
  String _searchQuery = '';
  LibrarySort _sort = LibrarySort.newest;
  static const _filters = ['All', 'Documents', 'Scans', 'AI Chats'];

  @override
  void initState() {
    super.initState();
    _authChanges = FirebaseAuth.instance.authStateChanges();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: context.pageColor,
      appBar: AppBar(
        backgroundColor: context.pageColor,
        title: Text(
          context.tr('My Library'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedFilter != 3)
            PopupMenuButton<LibrarySort>(
              tooltip: context.tr('Sort library'),
              icon: const Icon(Icons.sort),
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (_) => LibrarySort.values.map((sort) {
                return CheckedPopupMenuItem<LibrarySort>(
                  value: sort,
                  checked: _sort == sort,
                  child: Text(context.tr(librarySortLabel(sort))),
                );
              }).toList(),
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(keyboardOpen ? 8 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!keyboardOpen) ...[
              Text(
                context.tr('Your saved work'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('Find your documents, scans and conversations.'),
                style: TextStyle(color: context.mutedColor),
              ),
              const SizedBox(height: 22),
            ],
            if (_selectedFilter != 3)
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: context.tr('Search your library...'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('Clear search'),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  filled: true,
                  fillColor: context.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            SizedBox(height: keyboardOpen ? 8 : 20),
            SizedBox(
              height: 45,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ChoiceChip(
                  label: Text(context.tr(_filters[index])),
                  selected: _selectedFilter == index,
                  onSelected: (_) => setState(() => _selectedFilter = index),
                ),
              ),
            ),
            if (!keyboardOpen && _selectedFilter != 3) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(librarySortLabel(_sort)),
                style: TextStyle(color: context.mutedColor),
              ),
            ],
            SizedBox(height: keyboardOpen ? 8 : 16),
            Expanded(
              child: StreamBuilder<User?>(
                stream: _authChanges,
                initialData: FirebaseAuth.instance.currentUser,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        context.tr(
                          'Unable to check your account. Please reopen the app.',
                        ),
                      ),
                    );
                  }
                  final user = snapshot.data;
                  if (user == null) {
                    return Center(
                      child: Text(
                        context.tr('Please log in to view your saved work.'),
                      ),
                    );
                  }
                  if (_selectedFilter == 3) {
                    return Center(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const AiChatScreen(showHistoryOnOpen: true),
                          ),
                        ),
                        icon: const Icon(Icons.history),
                        label: Text(context.tr('Open chat history')),
                      ),
                    );
                  }
                  return AllLibraryItems(
                    key: ValueKey(user.uid),
                    userId: user.uid,
                    searchQuery: _searchQuery,
                    filter: _selectedFilter,
                    sort: _sort,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
