import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiggo/screens/file_editor_hub_screen.dart';
import 'package:jiggo/services/app_settings.dart';
import 'package:jiggo/services/app_strings.dart';

import 'app_preferences_test.dart' show settingsApp;
import 'support/memory_settings_store.dart';

void main() {
  for (final language in ['en', 'bn']) {
    testWidgets(
      'Editor hub prioritizes PDF and labels every destination at narrow large font $language',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final chosen = <FileEditorKind>[];
        await t.pumpWidget(
          settingsApp(
            AppSettings(store: MemorySettingsStore(), language: language),
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
              child: FileEditorHubScreen(onSelected: chosen.add),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        for (final entry in [
          (FileEditorKind.pdf, 'Open PDF'),
          (FileEditorKind.docx, 'Word Document'),
          (FileEditorKind.image, 'Image Editor'),
          (FileEditorKind.text, 'Text Editor'),
        ]) {
          final f = find.text(AppStrings.text(entry.$2, language));
          if (f.evaluate().isEmpty) {
            await t.scrollUntilVisible(
              f,
              220,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await t.ensureVisible(f);
          await t.pumpAndSettle();
          await t.tap(f);
          await t.pumpAndSettle();
        }
        expect(chosen, [
          FileEditorKind.pdf,
          FileEditorKind.docx,
          FileEditorKind.image,
          FileEditorKind.text,
        ]);
        expect(t.takeException(), isNull);
      },
    );
  }
}
