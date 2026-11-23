import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/services/local_file_store.dart';
import 'package:jiggo/screens/all_library_items.dart' show LibrarySort;
import 'package:jiggo/widgets/local_files_panel.dart';

import 'local_files_ui_test.dart' show boot;
import 'support/memory_local_files.dart';

void main() {
  testWidgets(
    'All embeds every local file, searches and sorts without an inner viewport',
    (t) async {
      final store = LocalFileStore(MemoryLocalFiles());
      for (final title in ['Zebra', 'Beta', 'Alpha', 'Resume']) {
        await store.save(
          'A',
          title,
          LocalFileKind.txt,
          Uint8List.fromList([65]),
          'Text',
        );
      }
      Widget page({String owner = 'A', String search = ''}) => Scaffold(
        body: ListView(
          children: [
            LocalFilesPanel(
              userId: owner,
              store: store,
              embedded: true,
              search: search,
              sort: LibrarySort.titleAZ,
              currentOwner: () => owner,
            ),
            const Text('Cloud item'),
          ],
        ),
      );
      await boot(t, page());
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(4));
      expect(find.text('Nothing saved yet'), findsNothing);
      final titles = t
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data)
          .toList();
      expect(titles, ['Alpha.txt', 'Beta.txt', 'Resume.txt', 'Zebra.txt']);
      await boot(t, page(search: 'resume'));
      expect(find.text('Resume.txt'), findsOneWidget);
      expect(find.text('Alpha.txt'), findsNothing);
      await boot(t, page(owner: 'B'));
      expect(find.text('Resume.txt'), findsNothing);
      expect(
        find.text(
          'No local files yet. Use Save to Library in an editor or Scan to PDF.',
        ),
        findsOneWidget,
      );
      await boot(t, page());
      expect(find.text('Resume.txt'), findsOneWidget);
      await store.save(
        'A',
        'New',
        LocalFileKind.txt,
        Uint8List.fromList([66]),
        'Text',
      );
      await t.pumpAndSettle();
      expect(find.text('New.txt'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('All hides the empty local message when cloud matches exist', (
    t,
  ) async {
    final store = LocalFileStore(MemoryLocalFiles());
    await boot(
      t,
      Scaffold(
        body: ListView(
          children: [
            LocalFilesPanel(
              userId: 'A',
              store: store,
              embedded: true,
              showEmpty: false,
            ),
            const Text('Cloud document'),
          ],
        ),
      ),
    );
    expect(find.text('Cloud document'), findsOneWidget);
    expect(find.text('Local files on this device'), findsNothing);
    expect(find.text('Nothing saved yet'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
