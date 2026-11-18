import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only device preferences belong here. Account IDs and secrets are never saved.
abstract interface class SettingsStore {
  Future<String?> read();
  Future<void> write(String value);
}

class DeviceSettingsStore implements SettingsStore {
  static const key = 'jiggo.appearance.v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(key);

  @override
  Future<void> write(String value) => _preferences.setString(key, value);
}

class AppSettings extends ChangeNotifier {
  final SettingsStore store;
  String? _language;
  ThemeMode _themeMode;
  bool _saving = false;

  AppSettings({
    required this.store,
    String? language,
    ThemeMode? themeMode,
  }) : _language = language == 'bn' || language == 'en' ? language : null,
       _themeMode = themeMode ?? ThemeMode.light;

  bool get hasLanguage => _language != null;
  Locale get locale => Locale(_language ?? 'en');
  ThemeMode get themeMode => _themeMode;
  bool get saving => _saving;

  Future<void> load() async {
    final raw = await store.read();
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final language = data['language'];
      _language = language == 'bn' || language == 'en'
          ? language as String
          : null;
      _themeMode = switch (data['theme']) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
    } on FormatException {
      // A damaged or old preference must not stop login or change account data.
      _language = null;
      _themeMode = ThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> setLanguage(String language) {
    if (language != 'en' && language != 'bn') {
      throw ArgumentError.value(language, 'language');
    }
    return _save(language: language);
  }

  Future<void> setThemeMode(ThemeMode mode) => _save(themeMode: mode);

  Future<void> _save({String? language, ThemeMode? themeMode}) async {
    if (_saving) return;
    _saving = true;
    notifyListeners();
    final nextLanguage = language ?? _language;
    final nextTheme = themeMode ?? _themeMode;
    try {
      // One record prevents partially saved language/theme combinations.
      await store.write(
        jsonEncode({'language': nextLanguage, 'theme': nextTheme.name}),
      );
      _language = nextLanguage;
      _themeMode = nextTheme;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()!.notifier!;
}
