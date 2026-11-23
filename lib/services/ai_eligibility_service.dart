import 'auth_service.dart';
import 'app_strings.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'release_config.dart';

class AgeDeclaration {
  final String ageBand;
  final bool guardianPermission;
  final bool privacyAccepted;
  const AgeDeclaration({
    required this.ageBand,
    required this.guardianPermission,
    required this.privacyAccepted,
  });

  bool get eligible =>
      privacyAccepted &&
      (ageBand == '18-plus' || (ageBand == '13-17' && guardianPermission));

  Map<String, dynamic> payload(String uid) => {
    'expectedUid': uid,
    'ageBand': ageBand,
    'guardianPermission': guardianPermission,
    'privacyAccepted': privacyAccepted,
    'version': 1,
  };
}

class AiEligibility {
  final bool eligible;
  final String? ageBand;
  const AiEligibility({required this.eligible, this.ageBand});
  bool get adult => eligible && ageBand == '18-plus';
  factory AiEligibility.fromData(Map<String, dynamic> data) {
    final value = data['ageBand'];
    final band = ['under-13', '13-17', '18-plus'].contains(value)
        ? value as String
        : null;
    return AiEligibility(
      eligible:
          data['eligible'] == true && (band == '13-17' || band == '18-plus'),
      ageBand: band,
    );
  }
}

class AiEligibilityService {
  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<AiEligibility> load() async {
    final uid = currentUid;
    if (uid == null) {
      return const AiEligibility(eligible: false);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (!AuthService.isMember(user)) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    await user!.getIdToken(true);
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'getAiEligibility',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call<Map<String, dynamic>>({'expectedUid': uid});
    if (currentUid != uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    return AiEligibility.fromData(result.data);
  }

  static Future<bool> submit(AgeDeclaration declaration, String uid) async {
    if (currentUid != uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (!AuthService.isMember(user)) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    await user!.getIdToken(true);
    final result = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable(
          'setAiEligibility',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call<Map<String, dynamic>>(declaration.payload(uid));
    return currentUid == uid && result.data['eligible'] == true;
  }

  static Future<AgeDeclaration?> collect(
    BuildContext context, {
    String? ageBand,
  }) => showDialog<AgeDeclaration>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AgeDeclarationDialog(initialAgeBand: ageBand),
  );

  static Future<bool> ensure(BuildContext context) async {
    final uid = currentUid;
    if (uid == null) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    AgeDeclaration? declaration;
    while (context.mounted && currentUid == uid) {
      try {
        if (declaration != null) return await submit(declaration, uid);
        final status = await load();
        if (!context.mounted || currentUid != uid) return false;
        if (status.eligible) return true;
        declaration = await collect(context, ageBand: status.ageBand);
        if (declaration == null || !declaration.eligible) return false;
      } catch (error) {
        if (!context.mounted || currentUid != uid) return false;
        final retry = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(c.tr('Could not confirm your eligibility')),
            content: Text(c.tr(errorMessage(error))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(c.tr('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(c.tr('Retry')),
              ),
            ],
          ),
        );
        if (retry != true) return false;
      }
    }
    return false;
  }

  static String errorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.details is Map && error.details['reason'] == 'age-correction') {
        return 'Contact jiggo800@gmail.com to correct your age declaration.';
      }
      if (error.code == 'not-found' || error.code == 'unimplemented') {
        return 'The AI eligibility service is not available yet. Please try again after the service is updated.';
      }
      if (error.code == 'permission-denied') {
        if (error.details is Map &&
            error.details['reason'] == 'email-verification') {
          return 'Verify your email before using Jiggo tools.';
        }
        return 'App verification failed. Update Jiggo from Google Play, or reopen the website and try again.';
      }
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        return 'The eligibility service could not be reached. Check your connection and retry.';
      }
      if (error.code == 'invalid-argument') {
        return 'The eligibility request was not accepted. Update Jiggo and try again.';
      }
      if (error.code == 'resource-exhausted') {
        return 'Too many attempts. Wait a while and try again.';
      }
      if (error.code == 'unauthenticated') {
        return 'Sign-in or app verification failed. Reopen Jiggo and try again.';
      }
    }
    return 'Unable to confirm AI eligibility. Please check your connection and try again.';
  }
}

class AgeDeclarationDialog extends StatefulWidget {
  final String? initialAgeBand;
  const AgeDeclarationDialog({super.key, this.initialAgeBand});
  @override
  State<AgeDeclarationDialog> createState() => _AgeDeclarationDialogState();
}

class _AgeDeclarationDialogState extends State<AgeDeclarationDialog> {
  String? _ageBand;
  bool _guardian = false;
  bool _privacy = false;

  @override
  void initState() {
    super.initState();
    _ageBand = widget.initialAgeBand;
  }

  Future<void> _openPolicy() async {
    try {
      final opened = await launchUrl(
        Uri.parse(ReleaseConfig.privacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Unable to open the privacy policy.')),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Unable to open the privacy policy.')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final declaration = AgeDeclaration(
      ageBand: _ageBand ?? '',
      guardianPermission: _guardian,
      privacyAccepted: _privacy,
    );
    return AlertDialog(
      scrollable: true,
      title: Text(context.tr('Jiggo is for ages 13+')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('You must be at least 13 to use Jiggo.')),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'Choose your age group truthfully. We store your declaration, not your full date of birth.',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _ageBand,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('Age group / বয়স'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'under-13',
                  child: Text(context.tr('Under 13')),
                ),
                DropdownMenuItem(
                  value: '13-17',
                  child: Text(context.tr('13–17')),
                ),
                DropdownMenuItem(
                  value: '18-plus',
                  child: Text(context.tr('18 or older')),
                ),
              ],
              onChanged: widget.initialAgeBand != null
                  ? null
                  : (value) => setState(() {
                      _ageBand = value;
                      _guardian = false;
                      _privacy = false;
                    }),
            ),
            if (_ageBand == 'under-13') ...[
              const SizedBox(height: 12),
              Text(
                context.tr(
                  'Jiggo is not available to children under 13. Please do not upload images or other personal information. Contact jiggo800@gmail.com if your account needs help.',
                ),
              ),
            ],
            if (_ageBand == '13-17') ...[
              const SizedBox(height: 12),
              Text(
                context.tr(
                  'If you are 13–17, review Jiggo and the Privacy Policy with a parent or guardian and get their permission. Additional consent may be needed where you live.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  context.tr(
                    'My parent or guardian has reviewed Jiggo and permitted me to use it.',
                  ),
                ),
                value: _guardian,
                onChanged: (value) => setState(() => _guardian = value == true),
              ),
            ],
            if (_ageBand == '13-17' || _ageBand == '18-plus') ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  context.tr(
                    'I have read the Privacy Policy and understand that submitted content is sent to the AI provider. AI answers can be wrong.',
                  ),
                ),
                value: _privacy,
                onChanged: (value) => setState(() => _privacy = value == true),
              ),
              TextButton(
                onPressed: _openPolicy,
                child: Text(context.tr('Read Privacy Policy')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: declaration.eligible
              ? () => Navigator.pop(context, declaration)
              : null,
          child: Text(context.tr('Continue')),
        ),
      ],
    );
  }
}
