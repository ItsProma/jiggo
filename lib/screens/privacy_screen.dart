import '../services/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/release_config.dart';

Future<void> openJiggoSupport(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!ReleaseConfig.validEmail(ReleaseConfig.supportEmail)) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.tr('Support contact is not configured in this test build.'),
        ),
      ),
    );
    return;
  }
  final uri = Uri(
    scheme: 'mailto',
    path: ReleaseConfig.supportEmail,
    queryParameters: {'subject': 'Jiggo support'},
  );
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted && messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${context.tr('Email')}: ${ReleaseConfig.supportEmail}',
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted && messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${context.tr('Email')}: ${ReleaseConfig.supportEmail}',
          ),
        ),
      );
    }
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ) &&
          context.mounted &&
          messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.tr('Unable to open this link.'))),
        );
      }
    } catch (_) {
      if (context.mounted && messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.tr('Unable to open this link.'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Jiggo Privacy & Data'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.tr('Privacy and data use'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Age and permission'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'Jiggo is for ages 13 and older. We store your age-group and permission declarations, not your full date of birth. Ages 13–17 require a parent or guardian permission declaration. This is self-declared information, not verified identity or verified parental consent. Contact support to correct a recorded age group.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Your account'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'Google sign-in provides account details such as your name and email. Guest accounts use an anonymous account ID. Your edited display name is stored in Firebase Authentication.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('AI processing and saved work'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'Selected images and document instructions are sent through Jiggo’s backend to OpenAI to generate a response. Scan history stores the generated answer, language and date. Your generated or edited documents are stored in your account Library. The original scan photo is not stored in Jiggo’s Firestore history. Avoid sending sensitive information that is not needed for your request. AI answers can be incorrect.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Usage, security and reports'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'Jiggo records request counts, timestamps and available token-usage metadata to control costs and abuse. If you report AI content, the text and note you choose to submit are sent to the developer for review. These reports are stored under your account.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Handwriting notes'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              "For handwriting recognition, the selected prepared photo is sent through Jiggo’s backend to OpenAI. Recognized text is saved as a Library document; corrections are saved when you choose Save changes. Original handwriting photos are not saved in Firestore history. You can copy, export a TXT file or share the text with an app you choose. Account or Library-item deletion removes saved notes under the existing deletion process.",
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Photo PDFs'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              "Scan to PDF processes the photos you select on your device or browser, without an AI request. It may resize photos and removes camera EXIF metadata from the prepared copies. Draft pages are temporary until you save or download a PDF. Saving opens the Android document picker or a browser download. If you choose a cloud storage provider or share a PDF, that provider or app receives the file. These PDFs are not automatically uploaded to your Jiggo account Library.",
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Chat messages'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              "Chat messages and AI replies are sent through Jiggo’s backend to OpenAI and saved under your account. Only a limited recent part of the conversation is supplied for each reply; Jiggo does not remember every older message. You can delete a chat from Chat history. Deletion removes its message text; small deletion and request metadata may remain to prevent old requests recreating it. Account deletion removes account-specific chats, request records and chat usage limits.",
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Optional notifications'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'Notification permission is optional. If enabled, Jiggo uses Firebase Cloud Messaging to register this installation and stores its messaging installation ID, device registration ID, language, platform and last connection time under your account. Your notification preference is also stored on this device. Turning notifications off removes the messaging ID from the server and keeps a small revocation record to block old requests. Account deletion removes these account-specific records. No advertising SDK is added.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Optional voice input'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'When you start voice input, your device or browser speech service processes microphone audio and may send it to its provider online. Availability and language support depend on that service. Jiggo does not save audio files. Only text you accept is added to your document details; it is sent for AI processing when you choose to generate. You can type instead.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Advertising'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'This version of Jiggo does not show advertisements and does not include the Google Mobile Ads SDK. Jiggo does not request advertising identifiers for advertising.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Deletion'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            context.tr(
              'Use Profile → Delete Account to delete your Jiggo account, saved documents, scan history, submitted reports, age/permission declaration and account-specific usage records. This does not delete your Google account. Limited operational or security records, including deletion status, may remain to prevent abuse and old requests recreating deleted content. Provider processing and retention follow their applicable service terms. A deletion-status marker retains the former user ID, status and timestamps with no automatic expiration to prevent old requests recreating data. App-wide usage records can remain. See the public policy for details.',
            ),
          ),
          const SizedBox(height: 16),
          if (!ReleaseConfig.validHttps(ReleaseConfig.privacyPolicyUrl))
            Text(
              context.tr(
                'A public privacy-policy link is not configured in this test build.',
              ),
            ),
          if (ReleaseConfig.validHttps(ReleaseConfig.privacyPolicyUrl))
            TextButton(
              onPressed: () => _open(context, ReleaseConfig.privacyPolicyUrl),
              child: Text(context.tr('Open public privacy policy')),
            ),
          if (ReleaseConfig.validHttps(ReleaseConfig.accountDeletionUrl))
            TextButton(
              onPressed: () => _open(context, ReleaseConfig.accountDeletionUrl),
              child: Text(context.tr('Account deletion website')),
            ),
          TextButton(
            onPressed: () => openJiggoSupport(context),
            child: Text(context.tr('Contact support')),
          ),
        ],
      ),
    );
  }
}
