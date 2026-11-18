class ReleaseConfig {
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL', defaultValue: 'https://jiggo.debcreatives.net/privacy.html');
  static const accountDeletionUrl = String.fromEnvironment('ACCOUNT_DELETION_URL', defaultValue: 'https://jiggo.debcreatives.net/delete-account.html');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'jiggo800@gmail.com');
  static const bannerId = String.fromEnvironment('ADMOB_BANNER_ID');
  static const productionAdsEnabled = bool.fromEnvironment('ENABLE_PRODUCTION_ADS');
  static const underAgeSetting = String.fromEnvironment('ADMOB_UNDER_AGE_OF_CONSENT');

  static bool validHttps(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }

  static bool validEmail(String value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  static bool? get underAgeOfConsent => switch (underAgeSetting) {
    'true' => true,
    'false' => false,
    _ => null,
  };
}
