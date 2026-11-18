import '../services/app_theme.dart';
import '../services/app_strings.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' as firebase;
import 'package:flutter/material.dart';

import 'document_details_screen.dart';
import 'handwriting_text_screen.dart';
import 'scan_history_details_screen.dart';

enum LibrarySort { newest, oldest, titleAZ, titleZA }

String librarySortLabel(LibrarySort sort) {
  return switch (sort) {
    LibrarySort.newest => 'Newest first',
    LibrarySort.oldest => 'Oldest first',
    LibrarySort.titleAZ => 'Title A–Z',
    LibrarySort.titleZA => 'Title Z–A',
  };
}

class LibraryEntry {
  final String id;
  final bool isDocument;
  final String title;
  final String content;
  final String type;
  final String language;
  final DateTime? createdAt;

  const LibraryEntry({
    required this.id,
    required this.isDocument,
    required this.title,
    required this.content,
    required this.type,
    required this.language,
    this.createdAt,
  });

  String get collection => isDocument ? 'documents' : 'scanHistory';
  String get key => '$collection/$id';

  factory LibraryEntry.fromData({
    required String id,
    required bool isDocument,
    required Map<String, dynamic> data,
  }) {
    final contentValue = data[isDocument ? 'content' : 'answer'];
    final content = contentValue is String ? contentValue : '';
    final titleValue = data['title'];
    final storedTitle = titleValue is String ? titleValue.trim() : '';
    final fallback = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final timestamp = data['createdAt'];
    final date = timestamp is Timestamp
        ? timestamp.toDate()
        : timestamp is DateTime
        ? timestamp
        : null;
    final typeValue = data['documentType'];
    final languageValue = data['language'];
    return LibraryEntry(
      id: id,
      isDocument: isDocument,
      title: storedTitle.isNotEmpty
          ? storedTitle
          : isDocument
          ? 'Untitled document'
          : fallback.isEmpty
          ? 'Untitled scan'
          : fallback.substring(
              0,
              fallback.length > 150 ? 150 : fallback.length,
            ),
      content: content,
      type: isDocument && typeValue is String && typeValue.trim().isNotEmpty
          ? typeValue
          : isDocument
          ? 'Document'
          : 'AI Scan',
      language: languageValue is String ? languageValue : '',
      createdAt: date,
    );
  }
}

/// Search and sort a copy, keeping the original stream data unchanged.
List<LibraryEntry> selectLibraryEntries(
  Iterable<LibraryEntry> entries, {
  String query = '',
  LibrarySort sort = LibrarySort.newest,
}) {
  final normalized = query.trim().toLowerCase();
  final result = entries.where((entry) {
    return normalized.isEmpty ||
        [
          entry.title,
          entry.content,
          entry.type,
          entry.language,
        ].any((value) => value.toLowerCase().contains(normalized));
  }).toList();
  result.sort((a, b) {
    if (sort == LibrarySort.titleAZ || sort == LibrarySort.titleZA) {
      final comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (comparison != 0) {
        return sort == LibrarySort.titleAZ ? comparison : -comparison;
      }
    } else {
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      // Unknown dates remain at the bottom for either chronological order.
      if (aDate == null && bDate != null) {
        return 1;
      }
      if (aDate != null && bDate == null) {
        return -1;
      }
      if (aDate != null && bDate != null) {
        final comparison = aDate.compareTo(bDate);
        if (comparison != 0) {
          return sort == LibrarySort.newest ? -comparison : comparison;
        }
      }
    }
    return a.key.compareTo(b.key);
  });
  return result;
}

class AllLibraryItems extends StatefulWidget {
  final String userId;
  final String searchQuery;
  final int filter;
  final LibrarySort sort;

  const AllLibraryItems({
    super.key,
    required this.userId,
    required this.searchQuery,
    this.filter = 0,
    this.sort = LibrarySort.newest,
  });

  @override
  State<AllLibraryItems> createState() => _AllLibraryItemsState();
}

class _AllLibraryItemsState extends State<AllLibraryItems> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _documents;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _scans;
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    _createStreams();
  }

  @override
  void didUpdateWidget(covariant AllLibraryItems oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _pending.clear();
      _createStreams();
    }
  }

  void _createStreams() {
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId);
    // Keep records without createdAt visible too. Sorting happens locally.
    _documents = userRef.collection('documents').snapshots();
    _scans = userRef.collection('scanHistory').snapshots();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.tr(message))));
  }

  bool _isOwner() => FirebaseAuth.instance.currentUser?.uid == widget.userId;

  String _mutationError(Object error, String action) {
    if (error is firebase.FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Your current account is not allowed to $action this item. Check account access.';
      }
      if (error.code == 'not-found') {
        return 'This item no longer exists.';
      }
      if (error.code == 'unavailable') {
        return 'Unable to connect. Check your internet connection.';
      }
    }
    return 'Unable to $action this item. Please try again.';
  }

  Future<void> _rename(LibraryEntry item) async {
    if (_pending.contains(item.key)) {
      return;
    }
    if (!_isOwner()) {
      _showMessage('Please log in with the account that owns this item.');
      return;
    }
    final ownerId = widget.userId;
    final reference = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerId)
        .collection(item.collection)
        .doc(item.id);
    setState(() => _pending.add(item.key));
    try {
      var draft = item.title;
      final formKey = GlobalKey<FormState>();
      final title = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          void submit() {
            if (formKey.currentState?.validate() == true) {
              Navigator.pop(dialogContext, draft.trim());
            }
          }

          return AlertDialog(
            title: Text(
              context.tr(item.isDocument ? 'Rename document' : 'Rename scan'),
            ),
            content: Form(
              key: formKey,
              child: TextFormField(
                initialValue: item.title,
                autofocus: true,
                maxLength: 150,
                decoration: InputDecoration(labelText: context.tr('Title')),
                onChanged: (value) => draft = value,
                onFieldSubmitted: (_) => submit(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return context.tr('Enter a title');
                  }
                  if (value.length > 150) {
                    return context.tr('Use 150 characters or fewer');
                  }
                  return null;
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.tr('Cancel')),
              ),
              FilledButton(onPressed: submit, child: Text(context.tr('Save'))),
            ],
          );
        },
      );
      if (!mounted || title == null || title == item.title) {
        return;
      }
      if (widget.userId != ownerId || !_isOwner()) {
        _showMessage('Account changed. Please reopen your Library.');
        return;
      }
      // Update only title. Do not overwrite document content or scan answers.
      await reference.update({'title': title});
      _showMessage('Item renamed successfully');
    } catch (error) {
      _showMessage(_mutationError(error, 'rename'));
    } finally {
      if (mounted && widget.userId == ownerId) {
        setState(() => _pending.remove(item.key));
      }
    }
  }

  Future<void> _delete(LibraryEntry item) async {
    if (_pending.contains(item.key)) {
      return;
    }
    if (!_isOwner()) {
      _showMessage('Please log in with the account that owns this item.');
      return;
    }
    final ownerId = widget.userId;
    final reference = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerId)
        .collection(item.collection)
        .doc(item.id);
    setState(() => _pending.add(item.key));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            context.tr(item.isDocument ? 'Delete document?' : 'Delete scan?'),
          ),
          content: Text(context.tr('This item will be permanently deleted.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                context.tr('Delete'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) {
        return;
      }
      if (widget.userId != ownerId || !_isOwner()) {
        _showMessage('Account changed. Please reopen your Library.');
        return;
      }
      await reference.delete();
      _showMessage('Item deleted successfully');
    } catch (error) {
      _showMessage(_mutationError(error, 'delete'));
    } finally {
      if (mounted && widget.userId == ownerId) {
        setState(() => _pending.remove(item.key));
      }
    }
  }

  void _open(LibraryEntry item) {
    if (!_isOwner()) {
      _showMessage('Please log in with the account that owns this item.');
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            item.isDocument && item.type == 'Handwriting Recognition'
            ? HandwritingTextScreen(
                documentId: item.id,
                title: item.title,
                text: item.content,
                expectedUid: widget.userId,
              )
            : item.isDocument
            ? DocumentDetailsScreen(
                documentId: item.id,
                title: item.title,
                content: item.content,
                documentType: item.type,
                language: item.language,
              )
            : ScanHistoryDetailsScreen(
                answer: item.content,
                language: item.language,
                date:
                    item.createdAt?.toLocal().toString().split('.')[0] ??
                    'Unknown date',
              ),
      ),
    );
  }

  Widget _render({
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>? documents,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>? scans,
  }) {
    final snapshots = [?documents, ?scans];
    final hasError = snapshots.any((snapshot) => snapshot.hasError);
    final loading = snapshots.any(
      (snapshot) => !snapshot.hasData && !snapshot.hasError,
    );
    final entries = <LibraryEntry>[
      for (final doc
          in documents?.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        LibraryEntry.fromData(id: doc.id, isDocument: true, data: doc.data()),
      for (final doc
          in scans?.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        LibraryEntry.fromData(id: doc.id, isDocument: false, data: doc.data()),
    ];
    final visible = selectLibraryEntries(
      entries,
      query: widget.searchQuery,
      sort: widget.sort,
    );
    if (loading && entries.isEmpty && !hasError) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  context.tr(
                    'Some items could not be loaded. Check connection and account access.',
                  ),
                ),
                TextButton(
                  onPressed: () => setState(_createStreams),
                  child: Text(context.tr('Retry')),
                ),
              ],
            ),
          ),
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: context.adaptiveTint(
                              const Color(0xFFE6E9FF),
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.folder_open_outlined,
                            size: 56,
                            color: context.accentColor,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          context.tr(
                            hasError
                                ? 'Unable to show all saved items.'
                                : loading
                                ? 'Loading saved items…'
                                : widget.searchQuery.trim().isNotEmpty
                                ? 'No matching results. Try another search.'
                                : 'Nothing saved yet',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    final pending = _pending.contains(item.key);
                    return Card(
                      color: context.cardColor,
                      elevation: 0,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        leading: CircleAvatar(
                          backgroundColor: context.adaptiveTint(
                            const Color(0xFFE6E9FF),
                          ),
                          child: Icon(
                            item.isDocument
                                ? Icons.description_outlined
                                : Icons.document_scanner_outlined,
                            color: context.accentColor,
                          ),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${context.tr(item.type)} · ${context.tr(item.language)}',
                        ),
                        trailing: pending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: context.tr('Rename item'),
                                    icon: const Icon(
                                      Icons.drive_file_rename_outline,
                                    ),
                                    onPressed: () => _rename(item),
                                  ),
                                  IconButton(
                                    tooltip: context.tr('Delete item'),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () => _delete(item),
                                  ),
                                ],
                              ),
                        onTap: pending ? null : () => _open(item),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filter == 1) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey('documents-${widget.userId}'),
        stream: _documents,
        builder: (_, snapshot) => _render(documents: snapshot),
      );
    }
    if (widget.filter == 2) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey('scans-${widget.userId}'),
        stream: _scans,
        builder: (_, snapshot) => _render(scans: snapshot),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey('all-${widget.userId}'),
      stream: _documents,
      builder: (_, documents) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey('all-scans-${widget.userId}'),
            stream: _scans,
            builder: (_, scans) => _render(documents: documents, scans: scans),
          ),
    );
  }
}
