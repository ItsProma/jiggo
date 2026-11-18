import 'package:jiggo/services/app_settings.dart';

class MemorySettingsStore implements SettingsStore {
  String? value;
  bool failWrites = false;
  MemorySettingsStore([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('Storage unavailable');
    this.value = value;
  }
}
