import 'package:flutter/material.dart';

/// UI text only. Never pass document bodies, user names or saved titles here.
class AppStrings {
  static String text(
    String message,
    String languageCode, [
    Map<String, Object?> values = const {},
  ]) {
    var key = message;
    var parameters = values;
    // Legacy AI helpers return a formatted wait message. Restrict matching to
    // this app-owned sentence; other dynamic messages use explicit parameters.
    final wait = RegExp(
      r'^Please wait about (\d+) seconds before sending another AI request\.$',
    ).firstMatch(message);
    if (wait != null) {
      key = 'Please wait about {count} seconds before sending another AI request.';
      parameters = {'count': wait.group(1)!};
    }
    var result = languageCode == 'bn' ? bangla[key] ?? key : key;
    for (final entry in parameters.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }

  static const Map<String, String> bangla = {
    "PDF Editor": "পিডিএফ এডিটর",
    "Open PDF": "PDF খোলো",
    "Add PDF / Merge": "PDF যোগ / একত্র করো",
    "Add blank page": "ফাঁকা পৃষ্ঠা যোগ করো",
    "PDF preview": "PDF প্রিভিউ",
    "Previous page": "আগের পৃষ্ঠা",
    "Next page": "পরের পৃষ্ঠা",
    "Zoom": "বড় করে দেখো",
    "Move earlier": "আগে নাও",
    "Move later": "পরে নাও",
    "Delete page": "পৃষ্ঠা মুছো",
    "Page order": "পৃষ্ঠার ক্রম",
    "Save PDF copy": "PDF কপি সেভ করো",
    "Leave this PDF?": "এই PDF থেকে বের হবে?",
    "Save a new PDF copy before leaving. This draft is not saved in Library.": "বের হওয়ার আগে PDF-এর নতুন কপি সেভ করো। এই খসড়া লাইব্রেরিতে সেভ হয়নি।",
    "Arrange PDF pages locally. Text, images and signatures cannot be edited in this step.": "নিজের ডিভাইসে PDF-এর পৃষ্ঠা সাজাও। এই ধাপে লেখা, ছবি ও স্বাক্ষর পরিবর্তন করা যাবে না।",
    "Page copies may lose bookmarks, links between pages, forms and digital signatures. Keep your original.": "পৃষ্ঠার কপিতে বুকমার্ক, পৃষ্ঠার মধ্যকার লিংক, ফর্ম ও ডিজিটাল স্বাক্ষর হারাতে পারে। মূল ফাইল রেখে দাও।",
    "Page {number} of {count}": "মোট {count} পৃষ্ঠার মধ্যে {number}",
    "Opened a local PDF copy. The original file is unchanged.": "ডিভাইসের PDF-এর কপি খোলা হয়েছে। মূল ফাইল বদলায়নি।",
    "Could not open this PDF. Use an unencrypted PDF under 10 MB, up to 100 total pages and 10 source files. Your current PDF is kept.": "PDF খোলা যায়নি। পাসওয়ার্ড ছাড়া ১০ MB-এর কম PDF দাও। সর্বোচ্চ মোট ১০০ পৃষ্ঠা ও ১০টি সোর্স ফাইল যোগ করা যাবে। বর্তমান PDF অক্ষত আছে।",
    "PDF copy saved.": "PDF কপি সেভ হয়েছে।",
    "PDF download requested. Check Downloads before leaving.": "PDF ডাউনলোডের অনুরোধ করা হয়েছে। বের হওয়ার আগে Downloads দেখো।",
    "PDF share sheet opened. Finish sharing before leaving.": "PDF শেয়ার করার অপশন খোলা হয়েছে। বের হওয়ার আগে শেয়ার সম্পন্ন করো।",
    "Cancelled. Your PDF draft is kept.": "বাতিল হয়েছে। PDF খসড়া অক্ষত আছে।",
    "Could not export PDF. Your draft is kept. Try a smaller PDF.": "PDF এক্সপোর্ট হয়নি। খসড়া অক্ষত আছে। ছোট PDF দিয়ে চেষ্টা করো।",
    "Edit text locally and save a new TXT copy before closing or refreshing. Use Word DOCX or Image Editor for other files. Use PDF Editor to arrange PDF pages.": "ডিভাইসে লেখা সম্পাদনা করে বন্ধ বা রিফ্রেশ করার আগে নতুন TXT কপি সেভ করো। অন্য ফাইলের জন্য Word DOCX বা Image Editor ব্যবহার করো। PDF-এর পৃষ্ঠা সাজাতে PDF Editor খোলো।",

    "Home": "হোম",
    "Scan": "স্ক্যান",
    "Create": "তৈরি",
    "Library": "লাইব্রেরি",
    "Profile": "প্রোফাইল",
    "Language": "ভাষা",
    "Appearance": "অ্যাপের থিম",
    "Light": "লাইট",
    "Dark": "ডার্ক",
    "System": "সিস্টেম",
    "Choose the language for menus and messages.":
        "মেনু ও বার্তার ভাষা বেছে নাও।",
    "Choose how Jiggo looks on this device.":
        "এই ডিভাইসে Jiggo কেমন দেখাবে বেছে নাও।",
    "Could not save your preference. Please try again.":
        "পছন্দ সেভ করা যায়নি। আবার চেষ্টা করো।",
    "Could not load your preferences. Please try again.":
        "পছন্দ লোড করা যায়নি। আবার চেষ্টা করো।",
    "Unable to check login status.": "লগইনের অবস্থা যাচাই করা যায়নি।",
    "Retry": "আবার চেষ্টা",
    "What can I help you with?": "কীভাবে সাহায্য করতে পারি?",
    "Ask anything, scan a question or create a document.":
        "প্রশ্ন করো, প্রশ্নের ছবি স্ক্যান করো বা ডকুমেন্ট তৈরি করো।",
    "Ask Jiggo anything...": "Jiggo-কে প্রশ্ন করো...",
    "Explore Tools": "টুলগুলো দেখো",
    "Edit text & TXT files": "লেখা ও TXT ফাইল সম্পাদনা",
    "Text and TXT files": "লেখা ও TXT ফাইল",
    "Edit locally. Save a new TXT copy before closing or refreshing. DOCX, PDF and image editing are not available here yet.": "নিজের ডিভাইসে লেখা সম্পাদনা করো। বন্ধ বা refresh করার আগে নতুন TXT কপি সেভ করো। DOCX, PDF ও ছবি সম্পাদনা এখানে এখনো নেই।",
    "Open TXT": "TXT খোলো",
    "Paste text": "লেখা পেস্ট করো",
    "File title": "ফাইলের নাম",
    "Your text": "তোমার লেখা",
    "Save TXT copy": "TXT কপি সেভ করো",
    "Copy text": "লেখা কপি করো",
    "Leave this text?": "এই লেখা ছেড়ে যাবে?",
    "Save a TXT copy or copy your text before continuing. This draft is not saved in Library.": "এগোনোর আগে TXT কপি সেভ করো বা লেখা কপি করো। এই খসড়া Library-তে সেভ হয় না।",
    "Opened a local copy. Your original file is unchanged.":
        "সম্পাদনার জন্য কপি খোলা হয়েছে। মূল ফাইল একই আছে।",
    "Could not open this file. Choose a UTF-8 TXT file under 128 KB and 20000 characters. Your current text is kept.": "ফাইল খোলা যায়নি। ১২৮ KB ও ২০০০০ অক্ষরের মধ্যে UTF-8 TXT ফাইল বেছে নাও। বর্তমান লেখা রাখা আছে।",
    "Text is too long. Keep it within 20000 characters.":
        "লেখা বেশি বড়। ২০০০০ অক্ষরের মধ্যে রাখো।",
    "Clipboard access failed. Paste directly into the text field.":
        "Clipboard খোলা যায়নি। লেখার ঘরে সরাসরি পেস্ট করো।",
    "Enter a title of 1–140 characters and text of 1–20000 characters.":
        "নাম ১–১৪০ অক্ষর এবং লেখা ১–২০০০০ অক্ষরের মধ্যে রাখো।",
    "TXT copy saved. Your original file is unchanged.":
        "TXT কপি সেভ হয়েছে। মূল ফাইল একই আছে।",
    "TXT download requested. Check Downloads before leaving.":
        "TXT download শুরু করার অনুরোধ গেছে। বের হওয়ার আগে Downloads দেখো।",
    "Unable to copy text. Try saving a TXT copy.":
        "লেখা কপি করা যায়নি। TXT কপি সেভ করার চেষ্টা করো।",
    "Undo": "আগের অবস্থায় ফেরাও",
    "Redo": "আবার প্রয়োগ করো",
    "Text copied.": "লেখা কপি হয়েছে।",
    "Edit text, TXT & DOCX": "লেখা, TXT ও DOCX সম্পাদনা",
    "Edit text locally and save a new TXT copy before closing or refreshing. For Word files, open Word DOCX. PDF and image editing are not available here yet.": "ডিভাইসেই লেখা সম্পাদনা করো। বন্ধ বা refresh করার আগে TXT কপি সেভ করো। Word ফাইলের জন্য Word DOCX খোলো। PDF ও ছবি সম্পাদনা এখানে এখনো নেই।",
    "Word DOCX": "Word DOCX",
    "Basic DOCX copy editor": "সাধারণ DOCX কপি সম্পাদনা",
    "Keeps text, Bold, Italic, Heading 1–3 and single-level lists. Fonts, colors and page layout are normalized. Lists restart from 1. Save a new copy before closing or refreshing.": "লেখা, গাঢ়/বাঁকা অক্ষর, ১–৩ স্তরের শিরোনাম ও এক স্তরের তালিকা রাখা হয়। Font, রং ও পেজের layout নতুন কপিতে বদলাবে। সংখ্যার তালিকা ১ থেকে শুরু হয়। বন্ধ বা refresh করার আগে নতুন কপি সেভ করো।",
    "Open DOCX": "DOCX খোলো",
    "New document": "নতুন ডকুমেন্ট",
    "Leave this document?": "এই ডকুমেন্ট ছেড়ে যাবে?",
    "Save a DOCX copy before continuing. This local draft is not saved in Library.":
        "এগোনোর আগে DOCX কপি সেভ করো। এই খসড়া Library-তে সেভ হয় না।",
    "Opened a basic editable copy. Review formatting before saving.": "সম্পাদনার জন্য সাধারণ কপি খোলা হয়েছে। সেভ করার আগে formatting মিলিয়ে দেখো।",
    "This file could not be opened. Use a basic DOCX under 2 MB without tables, images, links, tracked changes or nested lists. Your current document is kept.": "ফাইলটি খোলা যায়নি। Table, ছবি, link, tracked changes বা একাধিক স্তরের তালিকা ছাড়া ২ MB-এর মধ্যে সাধারণ DOCX বেছে নাও। বর্তমান ডকুমেন্ট রাখা আছে।",
    "Use plain text within 20000 characters. Your current document is kept.": "২০০০০ অক্ষরের মধ্যে সাধারণ লেখা ব্যবহার করো। বর্তমান ডকুমেন্ট রাখা আছে।",
    "Use a title of 1–140 characters and text within 20000 characters.":
        "নাম ১–১৪০ অক্ষর ও লেখা ২০০০০ অক্ষরের মধ্যে রাখো।",
    "DOCX copy saved.": "DOCX কপি সেভ হয়েছে।",
    "DOCX download requested. Check Downloads before leaving.":
        "DOCX download শুরু করার অনুরোধ গেছে। বের হওয়ার আগে Downloads দেখো।",
    "DOCX sharing opened.": "DOCX শেয়ার করার অপশন খোলা হয়েছে।",
    "Sharing or saving did not finish. Your document is kept.":
        "সেভ বা শেয়ার শেষ হয়নি। ডকুমেন্ট রাখা আছে।",
    "Unable to export DOCX. Use only Bold, Italic, Heading and single-level lists. Your document is kept; copy the text if needed.": "DOCX তৈরি হয়নি। শুধু গাঢ়/বাঁকা লেখা, শিরোনাম ও এক স্তরের তালিকা ব্যবহার করো। ডকুমেন্ট রাখা আছে; প্রয়োজনে লেখা কপি করো।",
    "Unable to copy text. Try saving a DOCX copy.":
        "লেখা কপি হয়নি। DOCX কপি সেভ করার চেষ্টা করো।",
    "Bold": "গাঢ় লেখা",
    "Italic": "বাঁকা লেখা",
    "Bullet list": "বুলেট তালিকা",
    "Numbered list": "সংখ্যার তালিকা",
    "Paragraph style": "অনুচ্ছেদের ধরন",
    "Normal text": "সাধারণ লেখা",
    "Heading 1": "শিরোনাম ১",
    "Heading 2": "শিরোনাম ২",
    "Heading 3": "শিরোনাম ৩",
    "Write or paste your document text here.":
        "এখানে ডকুমেন্টের লেখা লিখো বা পেস্ট করো।",
    "Save DOCX copy": "DOCX কপি সেভ করো",
    "Share DOCX": "DOCX শেয়ার করো",
    "Image Editor": "ছবি সম্পাদনা",
    "Edit text locally and save a new TXT copy before closing or refreshing. Use Word DOCX or Image Editor for other files. PDF editing is not available here yet.": "ডিভাইসেই লেখা সম্পাদনা করো। বন্ধ বা refresh করার আগে TXT কপি সেভ করো। অন্য ফাইলের জন্য Word DOCX বা ছবি সম্পাদনা খোলো। PDF সম্পাদনা এখানে এখনো নেই।",
    "Edit JPG and PNG locally. Save a new copy before closing or refreshing.": "ডিভাইসেই JPG ও PNG সম্পাদনা করো। বন্ধ বা refresh করার আগে নতুন কপি সেভ করো।",
    "Open image": "ছবি খোলো",
    "Crop image": "ছবি কাটছাঁট করো",
    "Rotate image": "ছবি ঘোরাও",
    "Resize image": "ছবির মাপ বদলাও",
    "Add text": "লেখা যোগ করো",
    "Reset image": "ছবি আগের অবস্থায় ফেরাও",
    "Leave this image?": "এই ছবি ছেড়ে যাবে?",
    "Save a new image copy before continuing. This local draft is not saved in Library.":
        "এগোনোর আগে ছবির নতুন কপি সেভ করো। এই খসড়া Library-তে সেভ হয় না।",
    "Opened a smaller working copy: at most 4096 pixels per side and 6 megapixels. Your original file is unchanged.": "সম্পাদনার জন্য ছোট কপি খোলা হয়েছে: প্রতি পাশে সর্বোচ্চ ৪০৯৬ pixel ও মোট ৬ megapixel। মূল ফাইল একই আছে।",
    "Could not open this image. Choose a non-animated JPG or PNG under 15 MB and 32 megapixels. Your current image is kept.": "ছবি খোলা যায়নি। Animation ছাড়া ১৫ MB ও ৩২ megapixel-এর মধ্যে JPG বা PNG বেছে নাও। বর্তমান ছবি রাখা আছে।",
    "Unable to apply this edit. Your image is kept. Try a smaller size or shorter text.": "পরিবর্তনটি করা যায়নি। ছবি রাখা আছে। ছোট মাপ বা ছোট লেখা দিয়ে চেষ্টা করো।",
    "Use 1–4096 pixels per side, up to 6 megapixels.":
        "প্রতি পাশে ১–৪০৯৬ pixel এবং মোট সর্বোচ্চ ৬ megapixel রাখো।",
    "Width in pixels": "প্রস্থ (pixel)",
    "Height in pixels": "উচ্চতা (pixel)",
    "Keep proportions": "অনুপাত একই রাখো",
    "Different proportions can stretch the image.":
        "অনুপাত বদলালে ছবি টানা বা চ্যাপ্টা হতে পারে।",
    "Choose valid dimensions within 4096 pixels and 6 megapixels.":
        "৪০৯৬ pixel ও মোট ৬ megapixel-এর মধ্যে সঠিক মাপ দাও।",
    "Apply resize": "নতুন মাপ প্রয়োগ করো",
    "Enter an image title of 1–140 characters.":
        "ছবির নাম ১–১৪০ অক্ষরের মধ্যে দাও।",
    "Image copy saved.": "ছবির কপি সেভ হয়েছে।",
    "Image download requested. Check Downloads before leaving.":
        "ছবি download শুরু করার অনুরোধ গেছে। বের হওয়ার আগে Downloads দেখো।",
    "Image sharing opened.": "ছবি শেয়ার করার অপশন খোলা হয়েছে।",
    "Sharing or saving did not finish. Your image is kept.":
        "সেভ বা শেয়ার শেষ হয়নি। ছবি রাখা আছে।",
    "Unable to save or share this image. Your edits are kept; try again.":
        "ছবি সেভ বা শেয়ার হয়নি। সম্পাদনা রাখা আছে; আবার চেষ্টা করো।",
    "Text becomes part of the picture after applying. Use Undo to change it. Undo history is limited for large images.": "Apply করার পর লেখা ছবির অংশ হয়ে যায়। বদলাতে Undo ব্যবহার করো। বড় ছবিতে আগের অবস্থায় ফেরার ধাপ কম থাকতে পারে।",
    "Image format": "ছবির format",
    "PNG keeps transparent areas.": "PNG স্বচ্ছ অংশ ঠিক রাখে।",
    "JPG uses quality 95. Transparent areas become white.":
        "JPG-এর quality ৯৫ রাখা হয়। স্বচ্ছ অংশ সাদা হয়ে যায়।",
    "Save image copy": "ছবির কপি সেভ করো",
    "Share image": "ছবি শেয়ার করো",
    "Add text to image": "ছবিতে লেখা যোগ করো",
    "Write your text, then tap or drag on the photo to position it.":
        "লেখা লিখে ছবিতে চাপ দিয়ে বা টেনে জায়গা ঠিক করো।",
    "Text on image": "ছবির ওপর লেখা",
    "Text size": "লেখার মাপ",
    "Text color": "লেখার রং",
    "White": "সাদা",
    "Black": "কালো",
    "Purple": "বেগুনি",
    "Text background": "লেখার পেছনের রং",
    "The text does not fit. Shorten it or reduce its size.":
        "লেখা ছবিতে ধরছে না। লেখা ছোট করো বা মাপ কমাও।",
    "Apply text": "লেখা বসাও",
    "File Editor": "ফাইল এডিটর",
    "Edit text, documents & images": "লেখা, ডকুমেন্ট ও ছবি সম্পাদনা",
    "Scan & Solve": "স্ক্যান ও সমাধান",
    "Solve questions": "প্রশ্নের সমাধান",
    "Document Maker": "ডকুমেন্ট তৈরি",
    "CV, letters & more": "সিভি, চিঠি ও আরও",
    "PDF Scanner": "পিডিএফ স্ক্যানার",
    "Scan and export": "স্ক্যান ও এক্সপোর্ট",
    "This tool will be added in a later update.":
        "এই টুলটি পরের আপডেটে যোগ করা হবে।",
    "Recent Activity": "সাম্প্রতিক কাজ",
    "My Documents": "আমার ডকুমেন্ট",
    "Open your saved documents and scans": "সেভ করা ডকুমেন্ট ও স্ক্যান দেখো",
    "Notifications": "নোটিফিকেশন",
    "Attachment": "ফাইল সংযুক্তি",
    "Camera": "ক্যামেরা",
    "Voice Input": "ভয়েস ইনপুট",
    "AI Chat": "এআই চ্যাট",
    "{feature} is coming soon": "{feature} শিগগিরই যোগ হবে",
    "Ask. Scan. Create.": "প্রশ্ন করো। স্ক্যান করো। তৈরি করো।",
    "Welcome to Jiggo": "Jiggo-তে স্বাগতম",
    "Your AI assistant for questions, documents and everyday tasks.":
        "প্রশ্ন, ডকুমেন্ট ও দৈনন্দিন কাজে তোমার এআই সহকারী।",
    "Please wait...": "একটু অপেক্ষা করো...",
    "Continue as Guest": "গেস্ট হিসেবে শুরু করো",
    "Continue with Google": "Google দিয়ে শুরু করো",
    "Privacy Policy": "গোপনীয়তা নীতি",
    "Jiggo is for ages 13+. Use AI responsibly and review its answers.": "Jiggo ব্যবহার করতে বয়স ১৩ বা বেশি হতে হবে। দায়িত্বের সঙ্গে এআই ব্যবহার করো এবং উত্তর যাচাই করো।",
    "My Profile": "আমার প্রোফাইল",
    "Guest User": "গেস্ট ব্যবহারকারী",
    "Jiggo User": "Jiggo ব্যবহারকারী",
    "You are using a guest account": "তুমি গেস্ট অ্যাকাউন্ট ব্যবহার করছ",
    "Google Account": "Google অ্যাকাউন্ট",
    "Account": "অ্যাকাউন্ট",
    "Edit Profile": "প্রোফাইল সম্পাদনা",
    "Edit profile": "প্রোফাইল সম্পাদনা",
    "Display name": "প্রদর্শিত নাম",
    "Change your display name": "তোমার প্রদর্শিত নাম বদলাও",
    "Connect Google": "Google যুক্ত করো",
    "Keep access to your guest documents and scans":
        "গেস্ট ডকুমেন্ট ও স্ক্যানের অ্যাক্সেস ধরে রাখো",
    "Manage your saved files": "সেভ করা ফাইল পরিচালনা করো",
    "Preferences": "পছন্দসমূহ",
    "Manage notifications": "নোটিফিকেশন পরিচালনা",
    "Support & Legal": "সহায়তা ও নীতিমালা",
    "Help & Support": "সহায়তা",
    "Get help with Jiggo": "Jiggo ব্যবহারে সাহায্য নাও",
    "How your data is handled": "তোমার তথ্য যেভাবে ব্যবহৃত হয়",
    "About Jiggo": "Jiggo সম্পর্কে",
    "App information": "অ্যাপের তথ্য",
    "AI question solving and document creation. Review AI responses before relying on them.": "এআই দিয়ে প্রশ্নের সমাধান ও ডকুমেন্ট তৈরি। এআইয়ের উত্তরের ওপর নির্ভর করার আগে যাচাই করো।",
    "Ads privacy options": "বিজ্ঞাপনের গোপনীয়তা সেটিংস",
    "Manage your advertising choices": "বিজ্ঞাপনের পছন্দ পরিচালনা",
    "Opening privacy options…": "গোপনীয়তা সেটিংস খোলা হচ্ছে…",
    "Log Out": "লগ আউট",
    "Log Out?": "লগ আউট করবে?",
    "Guest files may become inaccessible after logout. Connect Google first to keep access, or continue logging out.": "লগ আউটের পরে গেস্ট ফাইলের অ্যাক্সেস হারাতে পারো। অ্যাক্সেস রাখতে আগে Google যুক্ত করো, অথবা লগ আউট করো।",
    "Are you sure you want to log out?": "তুমি কি লগ আউট করতে চাও?",
    "Delete Account": "অ্যাকাউন্ট মুছো",
    "Delete account permanently?": "অ্যাকাউন্ট স্থায়ীভাবে মুছবে?",
    "Your documents, scan history and AI usage records will be deleted. This cannot be undone.": "তোমার ডকুমেন্ট, স্ক্যান ইতিহাস ও এআই ব্যবহারের রেকর্ড মুছে যাবে। এটি আর ফেরানো যাবে না।",
    "Google will ask you to confirm your identity.":
        "Google তোমার পরিচয় নিশ্চিত করতে বলবে।",
    "Delete permanently": "স্থায়ীভাবে মুছো",
    "Cancel": "বাতিল",
    "Save": "সেভ",
    "Saving profile…": "প্রোফাইল সেভ হচ্ছে…",
    "Profile updated": "প্রোফাইল আপডেট হয়েছে",
    "Connecting Google…": "Google যুক্ত হচ্ছে…",
    "Google connected. Your saved work stays in this account.":
        "Google যুক্ত হয়েছে। সেভ করা কাজ এই অ্যাকাউন্টেই থাকবে।",
    "Logging out…": "লগ আউট হচ্ছে…",
    "Deleting account…": "অ্যাকাউন্ট মুছে ফেলা হচ্ছে…",
    "Account changed. Please reopen your profile.":
        "অ্যাকাউন্ট বদলেছে। প্রোফাইল আবার খোলো।",
    "Create with AI": "এআই দিয়ে তৈরি করো",
    "Choose a document type and let Jiggo help you write it.":
        "ডকুমেন্টের ধরন বেছে নাও, Jiggo লিখতে সাহায্য করবে।",
    "Custom AI Document": "নিজের মতো এআই ডকুমেন্ট",
    "Describe what you need and Jiggo will help you create it.":
        "কী দরকার লিখে দাও, Jiggo তৈরি করতে সাহায্য করবে।",
    "Create Document": "ডকুমেন্ট তৈরি করো",
    "Popular Documents": "জনপ্রিয় ডকুমেন্ট",
    "CV / Resume": "সিভি / জীবনবৃত্তান্ত",
    "Create a professional CV": "পেশাদার সিভি তৈরি করো",
    "Job Application": "চাকরির আবেদন",
    "Write a job application letter": "চাকরির আবেদনপত্র লেখো",
    "Leave Application": "ছুটির আবেদন",
    "School, college or office leave": "স্কুল, কলেজ বা অফিসের ছুটি",
    "Formal Letter": "আনুষ্ঠানিক চিঠি",
    "Official and personal letters": "দাপ্তরিক ও ব্যক্তিগত চিঠি",
    "Invoice": "ইনভয়েস",
    "Create a business invoice": "ব্যবসার ইনভয়েস তৈরি করো",
    "Assignment": "অ্যাসাইনমেন্ট",
    "Create an academic document": "পড়াশোনার ডকুমেন্ট তৈরি করো",
    "Tell Jiggo what you want to create.": "কী তৈরি করতে চাও Jiggo-কে বলো।",
    "Document Title": "ডকুমেন্টের শিরোনাম",
    "Example: Leave Application": "উদাহরণ: ছুটির আবেদন",
    "Enter a title with at least 3 characters":
        "কমপক্ষে ৩ অক্ষরের শিরোনাম লেখো",
    "Use 150 characters or fewer": "১৫০ অক্ষরের মধ্যে লেখো",
    "Describe your document": "ডকুমেন্টের বিস্তারিত লেখো",
    "Write the details, purpose, and information you want included...":
        "যে তথ্য রাখতে চাও, উদ্দেশ্য ও বিস্তারিত লেখো...",
    "Describe your document using at least 10 characters":
        "কমপক্ষে ১০ অক্ষরে ডকুমেন্টের বিস্তারিত লেখো",
    "Use 2000 characters or fewer": "২০০০ অক্ষরের মধ্যে লেখো",
    "Document Language": "ডকুমেন্টের ভাষা",
    "Bangla": "বাংলা",
    "English": "ইংরেজি",
    "Generate with AI": "এআই দিয়ে তৈরি করো",
    "Generating your document...": "তোমার ডকুমেন্ট তৈরি হচ্ছে...",
    "Saved to Library": "লাইব্রেরিতে সেভ হয়েছে",
    "Library saving could not be confirmed. Copy or export this document before leaving.": "লাইব্রেরিতে সেভ নিশ্চিত করা যায়নি। বের হওয়ার আগে ডকুমেন্ট কপি বা এক্সপোর্ট করো।",
    "Remaining documents today: {count}":
        "আজ আরও ডকুমেন্ট তৈরি করা যাবে: {count}",
    "Copy": "কপি",
    "Document copied successfully": "ডকুমেন্ট কপি হয়েছে",
    "Preparing PDF...": "পিডিএফ তৈরি হচ্ছে...",
    "Download PDF": "পিডিএফ ডাউনলোড",
    "Opening...": "খোলা হচ্ছে...",
    "Edit Document": "ডকুমেন্ট সম্পাদনা",
    "Your AI-generated document will appear here after generation.":
        "তৈরি হলে তোমার এআই ডকুমেন্ট এখানে দেখাবে।",
    "Please log in first.": "আগে লগইন করো।",
    "Please log in first": "আগে লগইন করো",
    "Check the title and document instructions.":
        "শিরোনাম ও ডকুমেন্টের নির্দেশনা যাচাই করো।",
    "Request timed out. Check Library before generating again.":
        "সময়সীমা শেষ হয়েছে। আবার তৈরি করার আগে লাইব্রেরি দেখো।",
    "Check your internet connection and try again.":
        "ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করো।",
    "This account is unavailable for AI requests. Please check your account status.":
        "এই অ্যাকাউন্টে এআই ব্যবহার করা যাচ্ছে না। অ্যাকাউন্টের অবস্থা দেখো।",
    "Unable to generate document. Please try again later.":
        "ডকুমেন্ট তৈরি করা যায়নি। পরে আবার চেষ্টা করো।",
    "Unable to generate document. Please try again.":
        "ডকুমেন্ট তৈরি করা যায়নি। আবার চেষ্টা করো।",
    "Unable to export PDF. Please try again.":
        "পিডিএফ এক্সপোর্ট করা যায়নি। আবার চেষ্টা করো।",
    "Log in with the account that created this document.":
        "যে অ্যাকাউন্টে ডকুমেন্ট তৈরি করেছিলে, সেটিতে লগইন করো।",
    "Unable to open or refresh this document. Check Library.":
        "ডকুমেন্ট খোলা বা আপডেট করা যায়নি। লাইব্রেরি দেখো।",
    "AI Scan": "এআই স্ক্যান",
    "Scan anything": "প্রশ্ন বা ডকুমেন্ট স্ক্যান করো",
    "Upload questions or documents only. Avoid faces and personal details.": "শুধু প্রশ্ন বা ডকুমেন্ট দাও। মুখের ছবি ও ব্যক্তিগত তথ্য দেওয়া এড়িয়ে চলো।",
    "Take a photo of a question and get a step-by-step explanation.":
        "প্রশ্নের ছবি তুলে ধাপে ধাপে ব্যাখ্যা পাও।",
    "Unable to preview this image. Please choose another photo.":
        "ছবিটি দেখানো যায়নি। অন্য ছবি বেছে নাও।",
    "Selected image": "বেছে নেওয়া ছবি",
    "Remove Image": "ছবি সরাও",
    "Take Photo": "ছবি তোলো",
    "Upload from Gallery": "গ্যালারি থেকে ছবি দাও",
    "Explanation language": "ব্যাখ্যার ভাষা",
    "Solving...": "সমাধান হচ্ছে...",
    "Solve with AI": "এআই দিয়ে সমাধান",
    "AI Solution": "এআই সমাধান",
    "Step-by-step explanation": "ধাপে ধাপে ব্যাখ্যা",
    "Copy answer": "উত্তর কপি",
    "Answer copied": "উত্তর কপি হয়েছে",
    "Final Answer": "চূড়ান্ত উত্তর",
    "Remaining scans today: {count}": "আজ আরও স্ক্যান করা যাবে: {count}",
    "More Scan Tools": "আরও স্ক্যান টুল",
    "Scan to PDF": "স্ক্যান থেকে পিডিএফ",
    "Convert documents into PDF files": "ডকুমেন্ট পিডিএফে রূপান্তর",
    "Image to Text": "ছবি থেকে লেখা",
    "Extract text from images": "ছবি থেকে লেখা বের করো",
    "Handwriting Recognition": "হাতের লেখা শনাক্তকরণ",
    "Convert handwritten notes into text": "হাতের লেখা টাইপ করা লেখায় রূপান্তর",
    "Recent Scans": "সাম্প্রতিক স্ক্যান",
    "History saving could not be confirmed. Copy this answer before leaving.":
        "ইতিহাস সেভ নিশ্চিত করা যায়নি। বের হওয়ার আগে উত্তর কপি করো।",
    "Unable to solve the question. Please try again.":
        "প্রশ্নের সমাধান করা যায়নি। আবার চেষ্টা করো।",
    "Sign-in or app verification failed. Reopen Jiggo and try again.":
        "লগইন বা অ্যাপ যাচাই ব্যর্থ হয়েছে। Jiggo আবার খুলে চেষ্টা করো।",
    "This account is being deleted. AI requests are blocked.":
        "অ্যাকাউন্ট মুছে ফেলা হচ্ছে। এআই অনুরোধ বন্ধ আছে।",
    "Unable to verify this account. Please reopen the app.":
        "অ্যাকাউন্ট যাচাই করা যায়নি। অ্যাপ আবার খোলো।",
    "App verification failed. Please reopen the app and try again.":
        "অ্যাপ যাচাই ব্যর্থ হয়েছে। অ্যাপ আবার খুলে চেষ্টা করো।",
    "The request timed out. Check Library before trying again; the scan may have finished.": "সময়সীমা শেষ হয়েছে। স্ক্যান শেষ হয়ে থাকতে পারে, আবার চেষ্টা করার আগে লাইব্রেরি দেখো।",
    "Unable to connect. Check your internet connection and try again.":
        "সংযোগ করা যায়নি। ইন্টারনেট দেখে আবার চেষ্টা করো।",
    "Please choose a valid JPG, PNG or WebP image, 2 MB or smaller.":
        "২ এমবি বা ছোট সঠিক JPG, PNG বা WebP ছবি বেছে নাও।",
    "Unable to solve this image right now. Please try again later.":
        "এখন ছবিটির সমাধান করা যাচ্ছে না। পরে আবার চেষ্টা করো।",
    "Unable to select an image. Check camera or photo permission and try again.":
        "ছবি নেওয়া যায়নি। ক্যামেরা বা ছবির অনুমতি দেখে আবার চেষ্টা করো।",
    "My Library": "আমার লাইব্রেরি",
    "Your saved work": "তোমার সেভ করা কাজ",
    "Find your documents, scans and conversations.":
        "তোমার ডকুমেন্ট, স্ক্যান ও কথোপকথন খুঁজে নাও।",
    "Sort library": "লাইব্রেরি সাজাও",
    "Newest first": "নতুনগুলো আগে",
    "Oldest first": "পুরোনোগুলো আগে",
    "Title A–Z": "শিরোনাম: ঊর্ধ্বক্রমে",
    "Title Z–A": "শিরোনাম: অধঃক্রমে",
    "Search your library...": "লাইব্রেরিতে খোঁজো...",
    "Clear search": "সার্চ মুছো",
    "All": "সব",
    "Documents": "ডকুমেন্ট",
    "Scans": "স্ক্যান",
    "AI Chats": "এআই চ্যাট",
    "Unable to check your account. Please reopen the app.":
        "অ্যাকাউন্ট যাচাই করা যায়নি। অ্যাপ আবার খোলো।",
    "Please log in to view your saved work.": "সেভ করা কাজ দেখতে লগইন করো।",
    "AI chat history is not available yet.":
        "এআই চ্যাটের ইতিহাস এখনো চালু হয়নি।",
    "Document": "ডকুমেন্ট",
    "Untitled document": "শিরোনামহীন ডকুমেন্ট",
    "Untitled scan": "শিরোনামহীন স্ক্যান",
    "Unknown date": "তারিখ জানা নেই",
    "Some items could not be loaded. Check connection and account access.":
        "কিছু আইটেম লোড হয়নি। সংযোগ ও অ্যাকাউন্টের অ্যাক্সেস দেখো।",
    "Unable to show all saved items.": "সব সেভ করা আইটেম দেখানো যায়নি।",
    "Loading saved items…": "সেভ করা আইটেম লোড হচ্ছে…",
    "No matching results. Try another search.":
        "কিছু পাওয়া যায়নি। অন্যভাবে খোঁজো।",
    "Nothing saved yet": "এখনো কিছু সেভ হয়নি",
    "Rename item": "নাম বদলাও",
    "Delete item": "আইটেম মুছো",
    "Rename document": "ডকুমেন্টের নাম বদলাও",
    "Rename scan": "স্ক্যানের নাম বদলাও",
    "Title": "শিরোনাম",
    "Enter a title": "শিরোনাম লেখো",
    "Please log in with the account that owns this item.":
        "এই আইটেমের মালিক অ্যাকাউন্টে লগইন করো।",
    "Account changed. Please reopen your Library.":
        "অ্যাকাউন্ট বদলেছে। লাইব্রেরি আবার খোলো।",
    "Item renamed successfully": "নাম বদলানো হয়েছে",
    "Delete document?": "ডকুমেন্ট মুছবে?",
    "Delete scan?": "স্ক্যান মুছবে?",
    "This item will be permanently deleted.": "আইটেমটি স্থায়ীভাবে মুছে যাবে।",
    "Delete": "মুছো",
    "Item deleted successfully": "আইটেম মুছে ফেলা হয়েছে",
    "This item no longer exists.": "আইটেমটি আর নেই।",
    "Unable to connect. Check your internet connection.":
        "সংযোগ করা যায়নি। ইন্টারনেট সংযোগ দেখো।",
    "rename": "নাম বদলানো",
    "Your current account is not allowed to rename this item. Check account access.": "এই অ্যাকাউন্টে আইটেমের নাম বদলানোর অনুমতি নেই। অ্যাকাউন্টের অ্যাক্সেস দেখো।",
    "Your current account is not allowed to delete this item. Check account access.":
        "এই অ্যাকাউন্টে আইটেম মোছার অনুমতি নেই। অ্যাকাউন্টের অ্যাক্সেস দেখো।",
    "Unable to rename this item. Please try again.":
        "আইটেমের নাম বদলানো যায়নি। আবার চেষ্টা করো।",
    "Unable to delete this item. Please try again.":
        "আইটেম মোছা যায়নি। আবার চেষ্টা করো।",
    "Document Details": "ডকুমেন্টের বিস্তারিত",
    "Copy document": "ডকুমেন্ট কপি",
    "Scan Details": "স্ক্যানের বিস্তারিত",
    "Discard changes?": "পরিবর্তন বাতিল করবে?",
    "You have unsaved changes. Do you want to discard them?":
        "কিছু পরিবর্তন সেভ হয়নি। সেগুলো বাতিল করবে?",
    "Keep Editing": "সম্পাদনা চালিয়ে যাও",
    "Discard": "বাতিল করো",
    "Enter a document title using 1 to 150 characters":
        "১ থেকে ১৫০ অক্ষরে ডকুমেন্টের শিরোনাম লেখো",
    "Document saved successfully": "ডকুমেন্ট সেভ হয়েছে",
    "Unable to save your document. Check your connection and try again.":
        "ডকুমেন্ট সেভ হয়নি। ইন্টারনেট দেখে আবার চেষ্টা করো।",
    "Saving...": "সেভ হচ্ছে...",
    "Save Changes": "পরিবর্তন সেভ",
    "Enter document title": "ডকুমেন্টের শিরোনাম লেখো",
    "Start writing your document...": "ডকুমেন্ট লেখা শুরু করো...",
    "Log in to view your recent scans.": "সাম্প্রতিক স্ক্যান দেখতে লগইন করো।",
    "Unable to load recent scans. Check your connection and account access.":
        "সাম্প্রতিক স্ক্যান লোড হয়নি। সংযোগ ও অ্যাকাউন্টের অ্যাক্সেস দেখো।",
    "No scans yet": "এখনো স্ক্যান নেই",
    "Just now": "এইমাত্র",
    "Report AI content": "এআই কনটেন্ট রিপোর্ট",
    "The text and note you choose below will be sent to the developer for review. Remove personal information you do not want to share.": "নিচে বেছে নেওয়া লেখা ও নোট ডেভেলপারের কাছে যাচাইয়ের জন্য যাবে। যে ব্যক্তিগত তথ্য দিতে চাও না, তা সরিয়ে দাও।",
    "Reason": "কারণ",
    "Inappropriate content": "অনুপযুক্ত কনটেন্ট",
    "Harmful or unsafe": "ক্ষতিকর বা অনিরাপদ",
    "Incorrect information": "ভুল তথ্য",
    "Personal information": "ব্যক্তিগত তথ্য",
    "Other": "অন্যান্য",
    "Reported text": "রিপোর্টের লেখা",
    "Include the text you want to report": "যে লেখা রিপোর্ট করতে চাও তা দাও",
    "Additional details (optional)": "অতিরিক্ত তথ্য (ঐচ্ছিক)",
    "Sending…": "পাঠানো হচ্ছে…",
    "Submit report": "রিপোর্ট পাঠাও",
    "Report received. Thank you.": "রিপোর্ট পাওয়া গেছে। ধন্যবাদ।",
    "Daily report limit reached. Please try again tomorrow.":
        "আজকের রিপোর্টের সীমা শেষ। আগামীকাল চেষ্টা করো।",
    "Reporting is not available yet. Please try again after the service is updated.":
        "রিপোর্ট পাঠানো এখনো চালু হয়নি। সেবা আপডেট হলে চেষ্টা করো।",
    "Please sign in before submitting a report.":
        "রিপোর্ট পাঠানোর আগে লগইন করো।",
    "Unable to send your report. Please try again.":
        "রিপোর্ট পাঠানো যায়নি। আবার চেষ্টা করো।",
    "Jiggo is for ages 13+": "Jiggo ব্যবহার করতে বয়স ১৩ বা বেশি হতে হবে",
    "Choose your age group truthfully. We store your declaration, not your full date of birth.":
        "সঠিক বয়সের গ্রুপ বেছে নাও। আমরা তোমার ঘোষণা রাখি, পুরো জন্মতারিখ নয়।",
    "Age group / বয়স": "বয়সের গ্রুপ",
    "Under 13": "১৩ বছরের কম",
    "13–17": "১৩–১৭",
    "18 or older": "১৮ বা বেশি",
    "Jiggo is not available to children under 13. Please do not upload images or other personal information. Contact jiggo800@gmail.com if your account needs help.": "১৩ বছরের কম বয়সীদের জন্য Jiggo নয়। ছবি বা ব্যক্তিগত তথ্য দিও না। অ্যাকাউন্টের সাহায্যের জন্য jiggo800@gmail.com-এ যোগাযোগ করো।",
    "My parent or guardian has reviewed Jiggo and permitted me to use it.":
        "আমার অভিভাবক Jiggo দেখে আমাকে ব্যবহারের অনুমতি দিয়েছেন।",
    "I have read the Privacy Policy and understand that submitted content is sent to the AI provider. AI answers can be wrong.": "আমি গোপনীয়তা নীতি পড়েছি এবং বুঝেছি যে দেওয়া কনটেন্ট এআই সেবাদাতার কাছে যায়। এআইয়ের উত্তর ভুল হতে পারে।",
    "Read Privacy Policy": "গোপনীয়তা নীতি পড়ো",
    "Continue": "এগিয়ে যাও",
    "Unable to open the privacy policy.": "গোপনীয়তা নীতি খোলা যায়নি।",
    "Contact jiggo800@gmail.com to correct your age declaration.":
        "বয়সের ঘোষণা সংশোধন করতে jiggo800@gmail.com-এ যোগাযোগ করো।",
    "The AI eligibility service is not available yet. Please try again after the service is updated.": "এআই ব্যবহারের যোগ্যতা যাচাই এখনো চালু হয়নি। সেবা আপডেট হলে চেষ্টা করো।",
    "Unable to confirm AI eligibility. Please check your connection and try again.":
        "এআই ব্যবহারের যোগ্যতা নিশ্চিত করা যায়নি। সংযোগ দেখে আবার চেষ্টা করো।",
    "Please wait about {count} seconds before sending another AI request.":
        "পরের এআই অনুরোধের আগে প্রায় {count} সেকেন্ড অপেক্ষা করো।",
    "An AI request is still running. Wait for it to finish and try again.":
        "একটি এআই অনুরোধ চলছে। শেষ হলে আবার চেষ্টা করো।",
    "Today's app-wide AI limit has been reached. Please try again tomorrow.":
        "পুরো অ্যাপের আজকের এআই সীমা শেষ হয়েছে। আগামীকাল চেষ্টা করো।",
    "Too many AI attempts today. Please try again tomorrow.":
        "আজ অনেকবার এআই অনুরোধ করা হয়েছে। আগামীকাল চেষ্টা করো।",
    "AI is temporarily paused. Please try again later.":
        "এআই সাময়িক বন্ধ আছে। পরে চেষ্টা করো।",
    "Daily limit reached. Please try again tomorrow.":
        "আজকের সীমা শেষ হয়েছে। আগামীকাল চেষ্টা করো।",
    "Jiggo could not help with this request safely. Please use a school question or an appropriate document request.": "এই অনুরোধে Jiggo নিরাপদভাবে সাহায্য করতে পারেনি। পড়াশোনার প্রশ্ন বা উপযুক্ত ডকুমেন্টের অনুরোধ দাও।",
    "The safety check is unavailable. Nothing was saved. Please try again later.":
        "নিরাপত্তা যাচাই করা যাচ্ছে না। কিছু সেভ হয়নি। পরে আবার চেষ্টা করো।",
    "The AI response was incomplete. Nothing was saved. Please try a shorter request.": "এআইয়ের উত্তর অসম্পূর্ণ ছিল। কিছু সেভ হয়নি। ছোট অনুরোধ দিয়ে চেষ্টা করো।",
    "The signed-in account changed. Please try again.":
        "লগইন করা অ্যাকাউন্ট বদলেছে। আবার চেষ্টা করো।",
    "Complete the 13+ AI eligibility check before generating content.":
        "কনটেন্ট তৈরির আগে ১৩+ এআই যোগ্যতা যাচাই শেষ করো।",
    "Enter your name": "তোমার নাম লেখো",
    "Use 80 characters or fewer": "৮০ অক্ষরের মধ্যে লেখো",
    "Google sign-in was cancelled.": "Google লগইন বাতিল হয়েছে।",
    "This Google account already has a Jiggo account. Your guest data is unchanged. Use another Google account, or log out to open the existing account.": "এই Google অ্যাকাউন্টে আগে থেকেই Jiggo অ্যাকাউন্ট আছে। তোমার গেস্ট তথ্য অক্ষত আছে। অন্য Google অ্যাকাউন্ট ব্যবহার করো, অথবা লগ আউট করে পুরোনো অ্যাকাউন্ট খোলো।",
    "Allow the Google sign-in popup and try again.":
        "Google লগইনের পপআপ অনুমতি দিয়ে আবার চেষ্টা করো।",
    "Please sign in again to confirm this action.":
        "কাজটি নিশ্চিত করতে আবার লগইন করো।",
    "This sign-in method is not available right now.":
        "এই লগইন পদ্ধতি এখন চালু নেই।",
    "Your session is no longer valid. Please sign in again.":
        "তোমার সেশন শেষ হয়েছে। আবার লগইন করো।",
    "Choose the Google account that is currently signed in.":
        "বর্তমানে লগইন করা Google অ্যাকাউন্ট বেছে নাও।",
    "Account confirmation did not match. Please reopen your profile and try again.":
        "অ্যাকাউন্ট নিশ্চিতকরণ মেলেনি। প্রোফাইল আবার খুলে চেষ্টা করো।",
    "Please sign in again to confirm account deletion.":
        "অ্যাকাউন্ট মোছা নিশ্চিত করতে আবার লগইন করো।",
    "Account deletion is already in progress. Please wait before retrying.":
        "অ্যাকাউন্ট মুছে ফেলা চলছে। আবার চেষ্টা করার আগে অপেক্ষা করো।",
    "Account deletion could not be completed. Some data may already be deleted. Please retry.": "অ্যাকাউন্ট পুরোপুরি মোছা যায়নি। কিছু তথ্য মুছে গিয়ে থাকতে পারে। আবার চেষ্টা করো।",
    "Account deletion is not available yet. Please try again after the service is updated.":
        "অ্যাকাউন্ট মোছার সেবা এখনো চালু হয়নি। সেবা আপডেট হলে চেষ্টা করো।",
    "Deletion status could not be confirmed. Some data may already be deleted. Please reopen the app and check before retrying.": "মোছার অবস্থা নিশ্চিত করা যায়নি। কিছু তথ্য মুছে গিয়ে থাকতে পারে। আবার চেষ্টা করার আগে অ্যাপ খুলে যাচাই করো।",
    "Unable to complete this account action. Please try again.":
        "অ্যাকাউন্টের কাজটি করা যায়নি। আবার চেষ্টা করো।",
    "The account action was not completed. Please try again.":
        "অ্যাকাউন্টের কাজটি শেষ হয়নি। আবার চেষ্টা করো।",
    "Native Google sign-in is configured for Android only.":
        "অ্যাপের Google লগইন শুধু Android-এর জন্য সেট করা আছে।",
    "The selected image is empty.": "বেছে নেওয়া ছবিতে তথ্য নেই।",
    "Image must be 2 MB or smaller after compression.":
        "ছোট করার পরে ছবির আকার ২ এমবি বা কম হতে হবে।",
    "Please select a valid JPG, PNG or WebP image.":
        "সঠিক JPG, PNG বা WebP ছবি বেছে নাও।",
    "Unable to compress this image. Please choose another photo.":
        "ছবিটি ছোট করা যায়নি। অন্য ছবি বেছে নাও।",
    "This image could not be reduced enough. Please crop it to show only the question and try again.": "ছবিটি যথেষ্ট ছোট করা যায়নি। শুধু প্রশ্নের অংশ রেখে কেটে আবার চেষ্টা করো।",
    "Unable to process this image. Please choose another photo.":
        "ছবিটি প্রক্রিয়া করা যায়নি। অন্য ছবি বেছে নাও।",
    "Email": "ইমেইল",
    "You must be at least 13 to use Jiggo.":
        "Jiggo ব্যবহার করতে বয়স অন্তত ১৩ বছর হতে হবে।",
    "If you are 13–17, review Jiggo and the Privacy Policy with a parent or guardian and get their permission. Additional consent may be needed where you live.": "তোমার বয়স ১৩–১৭ হলে অভিভাবকের সঙ্গে Jiggo ও গোপনীয়তা নীতি পড়ে অনুমতি নাও। তোমার বসবাসের জায়গায় বাড়তি সম্মতির প্রয়োজন হতে পারে।",
    "Jiggo Privacy & Data": "Jiggo-এর গোপনীয়তা ও তথ্য",
    "Privacy and data use": "গোপনীয়তা ও তথ্যের ব্যবহার",
    "Age and permission": "বয়স ও অনুমতি",
    "Jiggo is for ages 13 and older. We store your age-group and permission declarations, not your full date of birth. Ages 13–17 require a parent or guardian permission declaration. This is self-declared information, not verified identity or verified parental consent. Contact support to correct a recorded age group.": "Jiggo ব্যবহারের বয়স ১৩ বা বেশি। আমরা বয়সের গ্রুপ ও অনুমতির ঘোষণা রাখি, পুরো জন্মতারিখ নয়। ১৩–১৭ বছর হলে অভিভাবকের অনুমতির ঘোষণা লাগে। এগুলো নিজের দেওয়া তথ্য; পরিচয় বা অভিভাবকের সম্মতি যাচাই করা হয় না। নথিভুক্ত বয়সের গ্রুপ সংশোধন করতে সহায়তায় যোগাযোগ করো।",
    "Your account": "তোমার অ্যাকাউন্ট",
    "Google sign-in provides account details such as your name and email. Guest accounts use an anonymous account ID. Your edited display name is stored in Firebase Authentication.": "Google দিয়ে লগইন করলে নাম ও ইমেইলের মতো তথ্য পাওয়া যায়। গেস্ট অ্যাকাউন্টে একটি বেনামী অ্যাকাউন্ট আইডি থাকে। বদলানো প্রদর্শিত নাম Firebase Authentication-এ সেভ হয়।",
    "AI processing and saved work": "এআই প্রক্রিয়াকরণ ও সেভ করা কাজ",
    "Selected images and document instructions are sent through Jiggo’s backend to OpenAI to generate a response. Scan history stores the generated answer, language and date. Your generated or edited documents are stored in your account Library. The original scan photo is not stored in Jiggo’s Firestore history. Avoid sending sensitive information that is not needed for your request. AI answers can be incorrect.": "উত্তর তৈরির জন্য বেছে নেওয়া ছবি ও ডকুমেন্টের নির্দেশনা Jiggo-এর সার্ভার দিয়ে OpenAI-তে যায়। স্ক্যান ইতিহাসে তৈরি উত্তর, ভাষা ও তারিখ থাকে। তৈরি বা সম্পাদিত ডকুমেন্ট অ্যাকাউন্টের লাইব্রেরিতে থাকে। মূল স্ক্যানের ছবি Jiggo-এর Firestore ইতিহাসে রাখা হয় না। প্রয়োজন ছাড়া সংবেদনশীল তথ্য পাঠিও না। এআইয়ের উত্তর ভুল হতে পারে।",
    "Usage, security and reports": "ব্যবহার, নিরাপত্তা ও রিপোর্ট",
    "Jiggo records request counts, timestamps and available token-usage metadata to control costs and abuse. If you report AI content, the text and note you choose to submit are sent to the developer for review. These reports are stored under your account.": "খরচ ও অপব্যবহার নিয়ন্ত্রণে Jiggo অনুরোধের সংখ্যা, সময় ও পাওয়া গেলে টোকেন ব্যবহারের তথ্য রাখে। এআই কনটেন্ট রিপোর্ট করলে তোমার বেছে দেওয়া লেখা ও নোট যাচাইয়ের জন্য ডেভেলপারের কাছে যায়। রিপোর্টগুলো তোমার অ্যাকাউন্টের অধীনে সেভ থাকে।",
    "Advertising": "বিজ্ঞাপন",
    "This version of Jiggo does not show advertisements and does not include the Google Mobile Ads SDK. Jiggo does not request advertising identifiers for advertising.": "Jiggo-এর এই সংস্করণে বিজ্ঞাপন নেই এবং Google Mobile Ads SDK নেই। বিজ্ঞাপনের জন্য Jiggo advertising identifier চায় না।",
    "Deletion": "তথ্য মোছা",
    "Use Profile → Delete Account to delete your Jiggo account, saved documents, scan history, submitted reports, age/permission declaration and account-specific usage records. This does not delete your Google account. Limited operational or security records, including deletion status, may remain to prevent abuse and old requests recreating deleted content. Provider processing and retention follow their applicable service terms. A deletion-status marker retains the former user ID, status and timestamps with no automatic expiration to prevent old requests recreating data. App-wide usage records can remain. See the public policy for details.": "প্রোফাইল → অ্যাকাউন্ট মুছো থেকে Jiggo অ্যাকাউন্ট, সেভ করা ডকুমেন্ট, স্ক্যান ইতিহাস, পাঠানো রিপোর্ট, বয়স ও অনুমতির ঘোষণা এবং অ্যাকাউন্টভিত্তিক ব্যবহারের রেকর্ড মোছা যায়। এতে Google অ্যাকাউন্ট মুছে যায় না। অপব্যবহার ঠেকাতে ও পুরোনো অনুরোধে মুছে দেওয়া তথ্য আবার তৈরি হওয়া রোধ করতে মোছার অবস্থাসহ সীমিত পরিচালনাগত বা নিরাপত্তার রেকর্ড থাকতে পারে। সেবাদাতার প্রক্রিয়াকরণ ও তথ্য রাখার ক্ষেত্রে তাদের প্রযোজ্য শর্ত চলে। পুরোনো অনুরোধে তথ্য আবার তৈরি হওয়া ঠেকাতে মোছার চিহ্নে আগের ব্যবহারকারী আইডি, অবস্থা ও সময় থাকে, যা স্বয়ংক্রিয়ভাবে মুছে যায় না। পুরো অ্যাপের ব্যবহারের রেকর্ড থাকতে পারে। বিস্তারিত প্রকাশিত নীতিতে দেখো।",
    "A public privacy-policy link is not configured in this test build.":
        "এই পরীক্ষামূলক build-এ প্রকাশিত গোপনীয়তা নীতির লিংক সেট করা নেই।",
    "Open public privacy policy": "প্রকাশিত গোপনীয়তা নীতি খোলো",
    "Account deletion website": "অ্যাকাউন্ট মোছার ওয়েবসাইট",
    "Contact support": "সহায়তায় যোগাযোগ করো",
    "Support contact is not configured in this test build.":
        "এই পরীক্ষামূলক build-এ সহায়তার ঠিকানা সেট করা নেই।",
    "Unable to open this link.": "লিংকটি খোলা যায়নি।",
    "Stay updated with Jiggo": "Jiggo-এর খবর পেতে নোটিফিকেশন",
    "Allow useful updates. You can use every feature without notification permission.": "দরকারি আপডেট পেতে অনুমতি দিতে পারো। অনুমতি ছাড়াও অ্যাপের সব সুবিধা ব্যবহার করা যাবে।",
    "Enable notifications": "নোটিফিকেশন চালু করুন",
    "Later": "পরে",
    "Change this later in Profile → Notifications.":
        "পরে প্রোফাইল → নোটিফিকেশন থেকে বদলাতে পারবে।",
    "Notification settings could not be loaded. You can still use Jiggo.":
        "নোটিফিকেশন সেটিংস লোড হয়নি। তবু Jiggo ব্যবহার করতে পারবে।",
    "Remote notifications need server setup. Device notifications can still be tested.": "দূর থেকে নোটিফিকেশন পেতে সার্ভার সেটআপ প্রয়োজন। এই ডিভাইসের পরীক্ষা করা যাবে।",
    "Notification registration failed verification. Reopen Jiggo and try again.": "নোটিফিকেশনের জন্য অ্যাপ যাচাই ব্যর্থ হয়েছে। Jiggo আবার খুলে চেষ্টা করো।",
    "Too many notification requests. Please try again later.":
        "অনেকবার নোটিফিকেশনের অনুরোধ করা হয়েছে। পরে চেষ্টা করো।",
    "This account or device is not ready for remote notifications.":
        "দূর থেকে নোটিফিকেশন পাওয়ার জন্য এই অ্যাকাউন্ট বা ডিভাইস প্রস্তুত নয়।",
    "Remote notifications could not connect. Check your internet and retry.":
        "দূরের নোটিফিকেশন সংযোগ হয়নি। ইন্টারনেট দেখে আবার চেষ্টা করো।",
    "Notification action failed. Check permission and try again.":
        "নোটিফিকেশনের কাজটি করা যায়নি। অনুমতি দেখে আবার চেষ্টা করো।",
    "Your notification choice could not be saved. You can still continue.":
        "নোটিফিকেশনের পছন্দ সেভ হয়নি। তবু এগিয়ে যেতে পারবে।",
    "Device notifications are off. Remote cleanup will retry when you reconnect.": "এই ডিভাইসে নোটিফিকেশন বন্ধ। সংযোগ ফিরলে রিমোট নিবন্ধন সরানোর চেষ্টা হবে।",
    "Browser notification settings": "ব্রাউজারের নোটিফিকেশন সেটিংস",
    "Open the site controls beside the address bar, choose Site settings, and allow Notifications. Then return here and tap Refresh.": "অ্যাড্রেস বারের পাশের সাইট নিয়ন্ত্রণ খুলে Site settings-এ Notifications অনুমতি দাও। এরপর এখানে ফিরে রিফ্রেশ চাপো।",
    "OK": "ঠিক আছে",
    "Open Jiggo notification permission in your device settings.":
        "ডিভাইসের সেটিংসে Jiggo-এর নোটিফিকেশন অনুমতি খোলো।",
    "Notifications are not supported on this device.":
        "এই ডিভাইসে নোটিফিকেশন সমর্থিত নয়।",
    "Permission is blocked in device or browser settings.":
        "ডিভাইস বা ব্রাউজারের সেটিংসে অনুমতি বন্ধ আছে।",
    "Notifications are on for this device.": "এই ডিভাইসে নোটিফিকেশন চালু আছে।",
    "Notifications are off. You can still use Jiggo.":
        "নোটিফিকেশন বন্ধ আছে। তবু Jiggo ব্যবহার করতে পারবে।",
    "Turn off on this device": "এই ডিভাইসে বন্ধ করো",
    "Open permission settings": "অনুমতির সেটিংস খোলো",
    "Refresh": "রিফ্রেশ",
    "Test on this device": "এই ডিভাইসে পরীক্ষা",
    "A test notification opens your Library when tapped.":
        "পরীক্ষার নোটিফিকেশনে চাপলে তোমার লাইব্রেরি খুলবে।",
    "Jiggo test notification": "Jiggo পরীক্ষামূলক নোটিফিকেশন",
    "This is a test. Tap to open Library.":
        "এটি একটি পরীক্ষা। লাইব্রেরি খুলতে চাপো।",
    "Show device test": "ডিভাইসে পরীক্ষার নোটিফিকেশন দেখাও",
    "Remote notifications": "দূর থেকে নোটিফিকেশন",
    "Web push needs the public Firebase web-push key. Device testing is available without it.": "ওয়েব পুশের জন্য Firebase-এর public web-push key প্রয়োজন। সেটি ছাড়াও এই ডিভাইসে পরীক্ষা করা যাবে।",
    "This device is connected for remote notifications.":
        "দূর থেকে নোটিফিকেশন পাওয়ার সংযোগ আছে।",
    "Enable notifications and reconnect to register this device.":
        "এই ডিভাইস যুক্ত করতে নোটিফিকেশন চালু করে আবার সংযোগ করো।",
    "Test opens": "পরীক্ষায় যে পেজ খুলবে",
    "Send push test": "পুশ পরীক্ষা পাঠাও",
    "Up to 5 push tests per day. Allow 30 seconds between tests.":
        "দিনে সর্বোচ্চ ৫টি পুশ পরীক্ষা। প্রতিটির মাঝে ৩০ সেকেন্ড অপেক্ষা করো।",
    "Received in this session": "এবার অ্যাপ খোলার পর পাওয়া নোটিফিকেশন",
    "No notifications received in this session.":
        "এবার অ্যাপ খোলার পর নোটিফিকেশন আসেনি।",
    "Open": "খোলো",
    "Optional notifications": "ঐচ্ছিক নোটিফিকেশন",
    "Notification permission is optional. If enabled, Jiggo uses Firebase Cloud Messaging to register this installation and stores its messaging installation ID, device registration ID, language, platform and last connection time under your account. Your notification preference is also stored on this device. Turning notifications off removes the messaging ID from the server and keeps a small revocation record to block old requests. Account deletion removes these account-specific records. No advertising SDK is added.": "নোটিফিকেশনের অনুমতি ঐচ্ছিক। চালু করলে Firebase Cloud Messaging দিয়ে এই অ্যাপটি নিবন্ধিত হয় এবং তোমার অ্যাকাউন্টে মেসেজিং ইনস্টলেশন আইডি, ডিভাইস নিবন্ধন আইডি, ভাষা, প্ল্যাটফর্ম ও শেষ সংযোগের সময় রাখা হয়। পছন্দটি এই ডিভাইসেও থাকে। বন্ধ করলে সার্ভার থেকে মেসেজিং আইডি সরানো হয়; পুরোনো অনুরোধ ঠেকাতে ছোট একটি বন্ধ থাকার রেকর্ড থাকে। অ্যাকাউন্ট মুছলে অ্যাকাউন্টভিত্তিক এসব রেকর্ডও মুছে যায়। কোনো বিজ্ঞাপনের SDK যোগ করা হয়নি।",
    "Write a few details. Jiggo will help you make a draft.":
        "কিছু তথ্য লিখো। জিগ্গো তোমাকে খসড়া তৈরি করতে সাহায্য করবে।",
    "A title is filled in for you. You can change it.":
        "শিরোনাম বসানো আছে। চাইলে বদলে নিতে পারো।",
    "Write or say your details": "তোমার তথ্য লিখো বা বলে দাও",
    "Tell us what you need. Do not include sensitive details that are not needed.":
        "কী দরকার লিখে দাও। প্রয়োজন ছাড়া সংবেদনশীল তথ্য দিয়ো না।",
    "See a simple example": "সহজ উদাহরণ দেখো",
    "Say your details": "তোমার তথ্য বলে দাও",
    "Review added details": "অতিরিক্ত তথ্য দেখো বা বদলাও",
    "A few details to confirm": "কয়েকটি তথ্য নিশ্চিত করে নিই",
    "Already explained above? Leave it blank. Unknown details will use editable placeholders.":
        "ওপরে বলা থাকলে ফাঁকা রাখো। অজানা তথ্যের জায়গা পরে পূরণ করা যাবে।",
    "Total details: {count}/2000": "মোট তথ্য: {count}/২০০০ অক্ষর",
    "Shorten your details or answers to continue.":
        "এগোতে তথ্য বা উত্তর একটু ছোট করো।",
    "Describe what to create using at least 10 characters.":
        "কী তৈরি করতে চাও অন্তত ১০ অক্ষরে বলো।",
    "Shorten your details before adding voice text.":
        "বলে দেওয়া লেখা যোগ করার আগে তথ্য একটু ছোট করো।",
    "What name should appear?": "কোন নাম বসবে?",
    "You can leave this blank and add it later.":
        "ফাঁকা রেখে পরে যোগ করতে পারো।",
    "What is your education or experience?":
        "তোমার শিক্ষাগত যোগ্যতা বা অভিজ্ঞতা কী?",
    "Course, qualification or relevant work.":
        "পড়াশোনা, যোগ্যতা বা কাজের অভিজ্ঞতা।",
    "Which skills should be included?": "কোন দক্ষতাগুলো থাকবে?",
    "For example: design, customer service or languages.":
        "যেমন: ডিজাইন, কাস্টমার সার্ভিস বা ভাষা।",
    "Which job are you applying for?": "কোন চাকরির জন্য আবেদন করবে?",
    "Role and company, if known.": "পদ ও প্রতিষ্ঠানের নাম জানা থাকলে বলো।",
    "What relevant experience or skills do you have?":
        "এই কাজের জন্য তোমার কী অভিজ্ঞতা বা দক্ষতা আছে?",
    "A short sentence is enough.": "একটি ছোট বাক্যই যথেষ্ট।",
    "Which dates do you need leave for?": "কোন তারিখগুলোতে ছুটি প্রয়োজন?",
    "Give exact dates; otherwise a space will be left.":
        "সঠিক তারিখ বলো। না দিলে পরে পূরণের জায়গা থাকবে।",
    "What is the reason for leave?": "ছুটির কারণ কী?",
    "Share only what you want in the document.":
        "ডকুমেন্টে যতটুকু রাখতে চাও ততটুকুই বলো।",
    "Who is the document for?": "কাকে ডকুমেন্টটি দেবে?",
    "For example: teacher, manager or office.":
        "যেমন: শিক্ষক, ম্যানেজার বা অফিস।",
    "What should the letter request or explain?":
        "চিঠিতে কী অনুরোধ বা ব্যাখ্যা থাকবে?",
    "Describe the purpose in one sentence.": "উদ্দেশ্য এক বাক্যে বলো।",
    "Who is the seller and customer?": "বিক্রেতা ও ক্রেতা কে?",
    "Leave unknown names blank.": "অজানা নামের জায়গা ফাঁকা রাখো।",
    "Which items, quantities and prices should be included?":
        "কোন পণ্য বা সেবা, পরিমাণ ও দাম থাকবে?",
    "Include the currency. Unknown amounts will stay blank.":
        "মুদ্রার নামও বলো। অজানা অঙ্ক ফাঁকা থাকবে।",
    "Any invoice number, date or tax details?":
        "ইনভয়েস নম্বর, তারিখ বা করের তথ্য আছে?",
    "Only include real details you already know.": "শুধু জানা সঠিক তথ্য দাও।",
    "What is the assignment topic?": "অ্যাসাইনমেন্টের বিষয় কী?",
    "Name the topic or paste the question.": "বিষয় বলো অথবা প্রশ্ন পেস্ট করো।",
    "What level and length do you need?":
        "কোন শ্রেণি বা পর্যায় ও কতটুকু লেখা দরকার?",
    "For example: college, 500 words.": "যেমন: কলেজ, ৫০০ শব্দ।",
    "Are there any teacher instructions?": "শিক্ষকের কোনো নির্দেশনা আছে?",
    "Add required headings or sources, if any.":
        "প্রয়োজনীয় শিরোনাম বা উৎস জানা থাকলে দাও।",
    "What would you like to create?": "কী তৈরি করতে চাও?",
    "For example: a study plan, notice or short report.":
        "যেমন: পড়ার পরিকল্পনা, নোটিশ বা ছোট রিপোর্ট।",
    "Example: I need a CV for a graphic design job. Include my education, design skills and work experience. I will add my contact details later.": "উদাহরণ: গ্রাফিক ডিজাইনের চাকরির জন্য সিভি চাই। আমার শিক্ষা, ডিজাইনের দক্ষতা ও কাজের অভিজ্ঞতা থাকবে। যোগাযোগের তথ্য পরে বসাব।",
    "Example: Write an application for a sales assistant role. I have one year of retail experience. Leave spaces for my name and the company name.": "উদাহরণ: সেলস অ্যাসিস্ট্যান্ট পদের জন্য আবেদন লিখো। আমার দোকানে কাজের এক বছরের অভিজ্ঞতা আছে। নিজের ও প্রতিষ্ঠানের নামের জায়গা ফাঁকা রাখো।",
    "Example: Write to my teacher asking for leave from 10 to 12 December 2026 because of a family event. Leave a space for my name.": "উদাহরণ: পারিবারিক অনুষ্ঠানের জন্য ১০ থেকে ১২ ডিসেম্বর ২০২৬ পর্যন্ত ছুটি চেয়ে শিক্ষককে আবেদন লিখো। আমার নামের জায়গা ফাঁকা রাখো।",
    "Example: Write to my landlord asking for a repair to the kitchen tap. Use a polite tone. Leave spaces for names and the address.": "উদাহরণ: রান্নাঘরের কল মেরামতের অনুরোধ করে বাড়িওয়ালাকে ভদ্রভাবে চিঠি লিখো। নাম ও ঠিকানার জায়গা ফাঁকা রাখো।",
    "Example: Make an invoice for logo design, quantity 1, price BDT 2000. Do not add tax. Leave spaces for the customer and invoice date.": "উদাহরণ: লোগো ডিজাইনের ইনভয়েস বানাও। পরিমাণ ১, দাম ২০০০ টাকা। কর যোগ কোরো না। ক্রেতা ও তারিখের জায়গা ফাঁকা রাখো।",
    "Example: Write a 500-word assignment about water pollution for college students. Include causes, effects and possible solutions.": "উদাহরণ: কলেজের জন্য পানিদূষণ সম্পর্কে ৫০০ শব্দের অ্যাসাইনমেন্ট লিখো। কারণ, প্রভাব ও সম্ভাব্য সমাধান থাকবে।",
    "Example: Write a short study plan for my English exam. I can study for one hour each evening for two weeks.": "উদাহরণ: আমার ইংরেজি পরীক্ষার পড়ার ছোট পরিকল্পনা বানাও। দুই সপ্তাহ প্রতিদিন সন্ধ্যায় এক ঘণ্টা পড়তে পারব।",
    "Voice uses your device or browser speech service, which may process audio online. Jiggo does not save audio files. Review the text before adding it.": "বলে লিখতে ডিভাইস বা ব্রাউজারের স্পিচ সেবা ব্যবহার হয়; অডিও অনলাইনে প্রক্রিয়া হতে পারে। জিগ্গো অডিও ফাইল সেভ করে না। যোগ করার আগে লেখা দেখে নাও।",
    "Speaking language": "যে ভাষায় বলবে",
    "Opening microphone...": "মাইক্রোফোন চালু হচ্ছে...",
    "Stopping...": "বন্ধ হচ্ছে...",
    "Stop listening": "শোনা বন্ধ করো",
    "Start listening": "বলা শুরু করো",
    "Listening... Speak a short sentence.": "শুনছি… ছোট একটি বাক্য বলো।",
    "Review and edit text": "লেখা দেখে ঠিক করে নাও",
    "Space available: {count} characters": "আর {count} অক্ষর যোগ করা যাবে",
    "Shorten the recognised text before adding it.":
        "যোগ করার আগে শনাক্ত করা লেখা একটু ছোট করো।",
    "Use text": "লেখাটি যোগ করো",
    "Voice is unavailable or microphone permission was denied. You can still type your details.": "ভয়েস চালু হয়নি অথবা মাইক্রোফোনের অনুমতি নেই। তোমার তথ্য লিখে দিতে পারো।",
    "This speech language is unavailable on this device. Try another language or type instead.": "এই ডিভাইসে ওই ভাষার স্পিচ সেবা পাওয়া যায়নি। অন্য ভাষা চেষ্টা করো অথবা লিখে দাও।",
    "Speech could not be recognised. Check microphone permission and your connection, then try again or type.": "কথা শনাক্ত করা যায়নি। মাইক্রোফোনের অনুমতি ও ইন্টারনেট দেখে আবার চেষ্টা করো অথবা লিখে দাও।",
    "Optional voice input": "ঐচ্ছিক ভয়েস ইনপুট",
    "When you start voice input, your device or browser speech service processes microphone audio and may send it to its provider online. Availability and language support depend on that service. Jiggo does not save audio files. Only text you accept is added to your document details; it is sent for AI processing when you choose to generate. You can type instead.": "ভয়েস শুরু করলে ডিভাইস বা ব্রাউজারের স্পিচ সেবা মাইক্রোফোনের অডিও প্রক্রিয়া করে এবং অনলাইনে তাদের সেবায় পাঠাতে পারে। ভাষা ও সুবিধা ওই সেবার ওপর নির্ভর করে। জিগ্গো অডিও ফাইল সেভ করে না। তুমি গ্রহণ করা লেখাটিই ডকুমেন্টের তথ্যে যোগ হয়; তৈরি করার বোতামে চাপলে এআইয়ের কাছে পাঠানো হয়। চাইলে লিখে দিতে পারো।",
    "AI Chat & history": "এআই চ্যাট ও আগের কথোপকথন",
    "Send message": "বার্তা পাঠাও",
    "Chat history": "আগের কথোপকথন",
    "New chat": "নতুন চ্যাট",
    "Delete chat": "চ্যাট মুছো",
    "Delete chat?": "চ্যাট মুছবে?",
    "This removes the saved conversation and cannot be undone.":
        "সেভ করা কথোপকথন মুছে যাবে। পরে ফিরিয়ে আনা যাবে না।",
    "Unable to delete chat. Try again.": "চ্যাট মোছা যায়নি। আবার চেষ্টা করো।",
    "No saved chats yet.": "এখনো কোনো চ্যাট সেভ হয়নি।",
    "Unable to load chats. Check your connection.":
        "আগের চ্যাট আনা যায়নি। ইন্টারনেট সংযোগ দেখো।",
    "Load older chats": "আরও পুরোনো চ্যাট দেখো",
    "You have used today’s 20 chat replies. Try again tomorrow.":
        "আজকের ২০টি চ্যাট উত্তরের সীমা শেষ। আগামীকাল আবার চেষ্টা করো।",
    "This chat has reached 20 replies. Start a new chat to continue.":
        "এই কথোপকথনে ২০টি উত্তর হয়েছে। চালিয়ে যেতে নতুন চ্যাট খোলো।",
    "Another message is still being answered. Wait, then check history.":
        "আরেকটি বার্তার উত্তর তৈরি হচ্ছে। অপেক্ষা করে আগের কথোপকথন দেখো।",
    "The previous request is still pending or its outcome is unknown. Check history before sending again.": "আগের অনুরোধ এখনো চলছে অথবা ফল নিশ্চিত নয়। আবার পাঠানোর আগে আগের কথোপকথন দেখো।",
    "This chat was deleted or is unavailable. Start a new chat.":
        "এই চ্যাট মুছে গেছে অথবা পাওয়া যাচ্ছে না। নতুন চ্যাট খোলো।",
    "Chat service is not available yet. Complete the server setup first.":
        "চ্যাট সেবা এখনো পাওয়া যাচ্ছে না। আগে সার্ভারের সেটআপ শেষ করতে হবে।",
    "Unable to send. Retry checks the same request. Check history if it timed out.": "পাঠানো নিশ্চিত হয়নি। আবার চেষ্টায় একই অনুরোধ যাচাই হবে। সময় শেষ হয়ে গেলে আগে আগের কথোপকথন দেখো।",
    "Write a message using 1–2000 characters.":
        "১ থেকে ২০০০ অক্ষরের মধ্যে একটি বার্তা লিখো।",
    "Leave this draft?": "এই খসড়া ছেড়ে যাবে?",
    "Copy any unsaved text first. A request already sent may still finish and appear in history.": "সেভ না হওয়া লেখা আগে কপি করো। পাঠানো অনুরোধের উত্তর পরে তৈরি হয়ে আগের কথোপকথনে দেখা যেতে পারে।",
    "Ask a question or continue a conversation. Recent messages provide context. AI answers can be wrong.": "প্রশ্ন করো বা কথোপকথন চালিয়ে যাও। সাম্প্রতিক বার্তাগুলো ধরে উত্তর দেওয়া হয়। এআইয়ের উত্তরে ভুল থাকতে পারে।",
    "You": "তুমি",
    "Chat replies remaining today: {count}":
        "আজ আর {count}টি চ্যাট উত্তর পাওয়া যাবে",
    "This reply could not be saved. Copy it before leaving. Check history before continuing.": "এই উত্তর সেভ হয়নি। বের হওয়ার আগে কপি করে নাও। চালিয়ে যাওয়ার আগে আগের কথোপকথন দেখো।",
    "Check history": "আগের কথোপকথন দেখো",
    "Reply language": "উত্তরের ভাষা",
    "Write a message...": "একটি বার্তা লিখো...",
    "Chat messages": "চ্যাটের বার্তা",
    "Chat messages and AI replies are sent through Jiggo’s backend to OpenAI and saved under your account. Only a limited recent part of the conversation is supplied for each reply; Jiggo does not remember every older message. You can delete a chat from Chat history. Deletion removes its message text; small deletion and request metadata may remain to prevent old requests recreating it. Account deletion removes account-specific chats, request records and chat usage limits.": "চ্যাটের বার্তা ও এআইয়ের উত্তর জিগ্গোর সার্ভার দিয়ে OpenAI-তে পাঠানো হয় এবং তোমার অ্যাকাউন্টে সেভ থাকে। প্রতিটি উত্তরের জন্য সীমিত সাম্প্রতিক কথোপকথন দেওয়া হয়; জিগ্গো সব পুরোনো কথা মনে রাখে না। আগের কথোপকথন থেকে চ্যাট মুছতে পারো। এতে বার্তার লেখা মুছে যায়; পুরোনো অনুরোধে আবার তৈরি হওয়া ঠেকাতে কিছু মোছার রেকর্ড ও অনুরোধের তথ্য থাকতে পারে। অ্যাকাউন্ট মুছলে অ্যাকাউন্টের চ্যাট, অনুরোধের রেকর্ড ও চ্যাট ব্যবহারের সীমার তথ্যও মুছে যায়।",
    "Open chat history": "আগের চ্যাট খোলো",
    "Copied": "কপি হয়েছে",
    "Close": "বন্ধ করো",
    "Scanned document": "স্ক্যান করা ডকুমেন্ট",
    "Added {added} page(s). Skipped {skipped} file(s).":
        "{added}টি পৃষ্ঠা যোগ হয়েছে। {skipped}টি ফাইল বাদ গেছে।",
    "Unable to open photos or camera. Check permission and try again.":
        "ছবি বা ক্যামেরা খোলা যায়নি। অনুমতি দেখে আবার চেষ্টা করো।",
    "These photos need too much memory. Remove a page or choose smaller photos.": "ছবিগুলোর জন্য বেশি মেমোরি প্রয়োজন। একটি পৃষ্ঠা সরাও অথবা ছোট ছবি বেছে নাও।",
    "Unable to edit this page. The previous version is kept.":
        "এই পৃষ্ঠাটি বদলানো যায়নি। আগের অবস্থাটি রাখা হয়েছে।",
    "Use 80 characters or fewer for the file name.":
        "ফাইলের নাম ৮০ অক্ষরের মধ্যে রাখো।",
    "PDF ready: {count} page(s). Save a copy before leaving.":
        "পিডিএফ তৈরি: {count}টি পৃষ্ঠা। বের হওয়ার আগে একটি কপি সেভ করো।",
    "Unable to create the PDF. Try fewer or smaller photos. Your pages are kept.": "পিডিএফ তৈরি হয়নি। কম বা ছোট ছবি দিয়ে চেষ্টা করো। তোমার পৃষ্ঠাগুলো রাখা আছে।",
    "PDF saved successfully.": "পিডিএফ সেভ হয়েছে।",
    "PDF download requested. Check your Downloads folder.":
        "পিডিএফ ডাউনলোডের অনুরোধ পাঠানো হয়েছে। Downloads ফোল্ডারে দেখো।",
    "Share sheet opened. Save a copy if you want to keep this PDF.":
        "শেয়ার করার অপশন খোলা হয়েছে। পিডিএফটি রাখতে চাইলে একটি কপি সেভ করো।",
    "Save or sharing was cancelled. Your PDF is still ready.":
        "সেভ বা শেয়ার বাতিল হয়েছে। তোমার পিডিএফ এখনো প্রস্তুত আছে।",
    "Unable to save or share. Your PDF is still ready; try again.":
        "সেভ বা শেয়ার হয়নি। পিডিএফটি প্রস্তুত আছে; আবার চেষ্টা করো।",
    "Leave these pages?": "এই পৃষ্ঠাগুলো ছেড়ে যাবে?",
    "Save a PDF first if you want to keep these pages. Unsaved pages are cleared when you leave.": "পৃষ্ঠাগুলো রাখতে চাইলে আগে পিডিএফ সেভ করো। বের হলে সেভ না করা পৃষ্ঠাগুলো মুছে যাবে।",
    "Leave": "বের হও",
    "Page {number}": "পৃষ্ঠা {number}",
    "Create a PDF from photos on this device. No AI request is made.": "এই ডিভাইসেই ছবি থেকে পিডিএফ তৈরি করো। এআইয়ের কাছে কোনো অনুরোধ পাঠানো হয় না।",
    "PDF file name": "পিডিএফ ফাইলের নাম",
    "Take photo": "ছবি তোলো",
    "Add photos": "ছবি যোগ করো",
    "JPG, PNG or WebP. Up to 20 pages. Very large, damaged or unsupported files are skipped.": "JPG, PNG বা WebP ছবি। সর্বোচ্চ ২০টি পৃষ্ঠা। খুব বড়, নষ্ট বা অসমর্থিত ফাইল বাদ যাবে।",
    "Pages: {count}/20": "পৃষ্ঠা: {count}/২০",
    "Drag the handle or use the arrows to change page order. Tap a photo to zoom.": "পৃষ্ঠার ক্রম বদলাতে হ্যান্ডেল ধরে টানো অথবা তীর চিহ্ন ব্যবহার করো। বড় করে দেখতে ছবিতে চাপো।",
    "Add your first page to begin.": "শুরু করতে প্রথম পৃষ্ঠার ছবি যোগ করো।",
    "Drag to reorder": "ক্রম বদলাতে টানো",
    "Crop page": "পৃষ্ঠা ক্রপ করো",
    "Rotate page": "পৃষ্ঠা ঘোরাও",
    "Reset page": "পৃষ্ঠার বদল বাতিল করো",
    "Move page up": "পৃষ্ঠা ওপরে নাও",
    "Move page down": "পৃষ্ঠা নিচে নাও",
    "Remove page": "পৃষ্ঠা সরাও",
    "Create PDF": "পিডিএফ তৈরি করো",
    "Save PDF": "পিডিএফ সেভ করো",
    "Share PDF": "পিডিএফ শেয়ার করো",
    "Drag the corners to crop, or drag inside the box to move it.":
        "ক্রপ করতে কোণগুলো ধরে টানো। বক্স সরাতে এর ভেতরে ধরে টানো।",
    "Reset crop": "ক্রপ বাতিল করো",
    "Trim edges": "চারপাশ একটু কাটো",
    "Apply crop": "ক্রপ প্রয়োগ করো",
    "Photo PDFs": "ছবি থেকে পিডিএফ",
    "Scan to PDF processes the photos you select on your device or browser, without an AI request. It may resize photos and removes camera EXIF metadata from the prepared copies. Draft pages are temporary until you save or download a PDF. Saving opens the Android document picker or a browser download. If you choose a cloud storage provider or share a PDF, that provider or app receives the file. These PDFs are not automatically uploaded to your Jiggo account Library.": "স্ক্যান টু পিডিএফে বেছে নেওয়া ছবি ডিভাইস বা ব্রাউজারেই প্রক্রিয়া হয়; এআইয়ের কাছে পাঠানো হয় না। বড় ছবি ছোট করা হতে পারে এবং তৈরি করা কপি থেকে ক্যামেরার EXIF তথ্য সরানো হয়। পিডিএফ সেভ বা ডাউনলোড না করা পর্যন্ত পৃষ্ঠাগুলো অস্থায়ী। সেভ করতে Android-এর ফাইল বাছাই বা ব্রাউজারের ডাউনলোড অপশন খোলে। ক্লাউড স্টোরেজে রাখলে বা শেয়ার করলে সেই সেবা বা অ্যাপটি ফাইল পায়। এই পিডিএফগুলো তোমার জিগ্গো অ্যাকাউন্টের লাইব্রেরিতে নিজে থেকে আপলোড হয় না।",
    "Handwriting text": "হাতের লেখা থেকে পাওয়া টেক্সট",
    "Use a title of 3–150 characters and text of 1–20000 characters.":
        "শিরোনাম ৩–১৫০ অক্ষর এবং লেখা ১–২০০০০ অক্ষরের মধ্যে রাখো।",
    "Changes saved to Library.": "পরিবর্তন লাইব্রেরিতে সেভ হয়েছে।",
    "Unable to save changes. Your edited text is kept; copy or download it.": "সেভ নিশ্চিত করা যায়নি। সংশোধিত লেখা রাখা আছে; কপি বা ডাউনলোড করে লাইব্রেরি যাচাই করো।",
    "Text file saved.": "টেক্সট ফাইল সেভ হয়েছে।",
    "Text download requested. Check Downloads.":
        "টেক্সট ডাউনলোডের অনুরোধ পাঠানো হয়েছে। Downloads দেখো।",
    "Text sharing opened.": "টেক্সট শেয়ার করার অপশন খোলা হয়েছে।",
    "Sharing or saving did not finish. Your text is kept.":
        "শেয়ার বা সেভ সম্পূর্ণ হয়নি। তোমার লেখা রাখা আছে।",
    "Unable to export text. Copy it or try again.":
        "লেখা এক্সপোর্ট হয়নি। কপি করো অথবা আবার চেষ্টা করো।",
    "Leave edited text?": "সংশোধিত লেখা ছেড়ে যাবে?",
    "Save changes, copy or download your text before leaving.":
        "বের হওয়ার আগে পরিবর্তন সেভ করো অথবা লেখা কপি বা ডাউনলোড করো।",
    "Review every line. AI can misread handwriting. [unclear] marks text it could not read.": "প্রতিটি লাইন মিলিয়ে দেখো। এআই হাতের লেখা ভুল পড়তে পারে। পড়তে না পারা অংশে [unclear] থাকবে।",
    "Library saving was not confirmed. Copy or download this text before leaving.": "লাইব্রেরিতে সেভ নিশ্চিত হয়নি। বের হওয়ার আগে এই লেখা কপি বা ডাউনলোড করো।",
    "This note is saved in Library. Save changes after editing.":
        "নোটটি লাইব্রেরিতে আছে। সংশোধনের পরে পরিবর্তন সেভ করো।",
    "Note title": "নোটের শিরোনাম",
    "Recognized text": "শনাক্ত করা লেখা",
    "Save changes": "পরিবর্তন সেভ করো",
    "Save TXT": "TXT সেভ করো",
    "Share text": "লেখা শেয়ার করো",
    "Choose a clear JPG, PNG or WebP photo under 15 MB. Check camera or photo permission.": "১৫ MB-এর কম পরিষ্কার JPG, PNG বা WebP ছবি বেছে নাও। ক্যামেরা বা ছবির অনুমতি দেখো।",
    "No readable handwriting found. Take a sharper, closer photo and try again.": "পড়ার মতো হাতের লেখা পাওয়া যায়নি। কাছ থেকে পরিষ্কার ছবি তুলে আবার চেষ্টা করো।",
    "Handwriting service is not available yet. Complete the server setup first.": "হাতের লেখা শনাক্ত করার সেবা এখনো পাওয়া যাচ্ছে না। আগে সার্ভারের সেটআপ শেষ করতে হবে।",
    "The request timed out. Check Library before trying again.":
        "অনুরোধের সময় শেষ হয়েছে। আবার চেষ্টা করার আগে লাইব্রেরি দেখো।",
    "Unable to recognize handwriting. Check Library before trying again; a note may already have been saved.": "হাতের লেখা শনাক্ত করা নিশ্চিত হয়নি। আবার চেষ্টা করার আগে লাইব্রেরি দেখো; নোট ইতিমধ্যে সেভ হয়ে থাকতে পারে।",
    "Turn handwritten Bangla or English notes into editable text. Upload only the page you need; avoid personal details.": "বাংলা বা ইংরেজি হাতের লেখা থেকে সংশোধনযোগ্য টেক্সট তৈরি করো। প্রয়োজনীয় পৃষ্ঠাটিই দাও; ব্যক্তিগত তথ্য এড়িয়ে চলো।",
    "The selected photo is sent to Jiggo’s AI service only when you press Recognize handwriting.": "হাতের লেখা শনাক্ত করার বোতামে চাপলেই বেছে নেওয়া ছবিটি জিগ্গোর এআই সেবায় পাঠানো হয়।",
    "Choose photo": "ছবি বেছে নাও",
    "Handwriting language hint": "হাতের লেখার ভাষা",
    "Bangla & English": "বাংলা ও ইংরেজি",
    "Text stays in its original language. AI may misread words. Scan & Solve and handwriting share the daily 10-scan allowance.": "লেখা মূল ভাষাতেই থাকবে। এআই শব্দ ভুল পড়তে পারে। Scan & Solve ও হাতের লেখা শনাক্ত করা মিলিয়ে দিনে সর্বোচ্চ ১০টি সফল স্ক্যান।",
    "Recognize handwriting": "হাতের লেখা শনাক্ত করো",
    "Handwritten notes": "হাতের লেখার নোট",
    "Handwriting notes": "হাতের লেখার নোট",
    "For handwriting recognition, the selected prepared photo is sent through Jiggo’s backend to OpenAI. Recognized text is saved as a Library document; corrections are saved when you choose Save changes. Original handwriting photos are not saved in Firestore history. You can copy, export a TXT file or share the text with an app you choose. Account or Library-item deletion removes saved notes under the existing deletion process.": "হাতের লেখা শনাক্ত করতে প্রস্তুত করা ছবিটি জিগ্গোর সার্ভার দিয়ে OpenAI-তে পাঠানো হয়। শনাক্ত করা লেখা লাইব্রেরিতে ডকুমেন্ট হিসেবে থাকে; পরিবর্তন সেভ করার বোতামে চাপলে সংশোধন রাখা হয়। হাতের লেখার মূল ছবি Firestore history-তে রাখা হয় না। লেখা কপি, TXT হিসেবে এক্সপোর্ট অথবা নিজের বেছে নেওয়া অ্যাপে শেয়ার করতে পারো। অ্যাকাউন্ট বা লাইব্রেরির আইটেম মুছলে আগের মোছার প্রক্রিয়া অনুযায়ী সেভ করা নোটও মোছে।",
  };
}

extension JiggoStrings on BuildContext {
  String tr(String message, [Map<String, Object?> values = const {}]) =>
      AppStrings.text(
        message,
        Localizations.maybeLocaleOf(this)?.languageCode ?? 'en',
        values,
      );

  String? trNullable(String? message) => message == null ? null : tr(message);
}
