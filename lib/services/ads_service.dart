import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

/// Advertising is disabled in this release. No advertising SDK is included.
/// Keeps existing screen hooks so adding ads later is a separate change.
class AdsService {
  AdsService._();
  static final instance = AdsService._();
  final ready = foundation.ValueNotifier<bool>(false);
  final privacyOptionsRequired = foundation.ValueNotifier<bool>(false);

  static bool get supported => false;
  String? get bannerId => null;

  Future<void> start({bool afterDeclaration = false}) async {
    ready.value = false;
    privacyOptionsRequired.value = false;
  }

  Future<void> showPrivacyOptions() async {
    privacyOptionsRequired.value = false;
  }
}

class HomeBannerAd extends StatelessWidget {
  const HomeBannerAd({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
