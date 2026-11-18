/// Local guidance only. All generation still uses the protected server endpoint.
class BriefQuestion {
  final String id;
  final String label;
  final String hint;
  final List<String> markers;
  const BriefQuestion(this.id, this.label, this.hint, this.markers);
}

class DocumentBrief {
  final String type;
  const DocumentBrief(this.type);

  String title(String language) {
    final bangla = language == 'Bangla';
    return switch (type) {
      'CV / Resume' => bangla ? 'জীবনবৃত্তান্ত' : 'Resume',
      'Job Application' => bangla ? 'চাকরির আবেদনপত্র' : 'Job Application',
      'Leave Application' => bangla ? 'ছুটির আবেদন' : 'Leave Application',
      'Formal Letter' => bangla ? 'আনুষ্ঠানিক চিঠি' : 'Formal Letter',
      'Invoice' => bangla ? 'ইনভয়েস' : 'Invoice',
      'Assignment' => bangla ? 'অ্যাসাইনমেন্ট' : 'Assignment',
      _ => bangla ? 'নতুন ডকুমেন্ট' : 'New Document',
    };
  }

  String get example => switch (type) {
    'CV / Resume' => 'Example: I need a CV for a graphic design job. Include my education, design skills and work experience. I will add my contact details later.',
    'Job Application' => 'Example: Write an application for a sales assistant role. I have one year of retail experience. Leave spaces for my name and the company name.',
    'Leave Application' => 'Example: Write to my teacher asking for leave from 10 to 12 December 2026 because of a family event. Leave a space for my name.',
    'Formal Letter' => 'Example: Write to my landlord asking for a repair to the kitchen tap. Use a polite tone. Leave spaces for names and the address.',
    'Invoice' => 'Example: Make an invoice for logo design, quantity 1, price BDT 2000. Do not add tax. Leave spaces for the customer and invoice date.',
    'Assignment' => 'Example: Write a 500-word assignment about water pollution for college students. Include causes, effects and possible solutions.',
    _ => 'Example: Write a short study plan for my English exam. I can study for one hour each evening for two weeks.',
  };

  List<BriefQuestion> get questions => switch (type) {
    'CV / Resume' => const [
      BriefQuestion(
        'name',
        'What name should appear?',
        'You can leave this blank and add it later.',
        ['my name', 'name:', 'নাম'],
      ),
      BriefQuestion(
        'education',
        'What is your education or experience?',
        'Course, qualification or relevant work.',
        [
          'education',
          'experience',
          'qualification',
          'শিক্ষা',
          'অভিজ্ঞ',
          'পড়',
          'পড়',
        ],
      ),
      BriefQuestion(
        'skills',
        'Which skills should be included?',
        'For example: design, customer service or languages.',
        ['skills', 'skill:', 'দক্ষতা'],
      ),
    ],
    'Job Application' => const [
      BriefQuestion(
        'role',
        'Which job are you applying for?',
        'Role and company, if known.',
        ['role', 'position', 'applying for', 'পদে', 'চাকরি'],
      ),
      BriefQuestion(
        'experience',
        'What relevant experience or skills do you have?',
        'A short sentence is enough.',
        ['experience', 'skills', 'অভিজ্ঞ', 'দক্ষতা'],
      ),
      BriefQuestion(
        'name',
        'What name should appear?',
        'You can leave this blank and add it later.',
        ['my name', 'name:', 'নাম'],
      ),
    ],
    'Leave Application' => const [
      BriefQuestion(
        'dates',
        'Which dates do you need leave for?',
        'Give exact dates; otherwise a space will be left.',
        ['date:', 'dates:', 'from ', 'তারিখ', 'থেকে'],
      ),
      BriefQuestion(
        'reason',
        'What is the reason for leave?',
        'Share only what you want in the document.',
        ['because', 'reason', 'কারণ', 'অসুস্থ'],
      ),
      BriefQuestion(
        'recipient',
        'Who is the document for?',
        'For example: teacher, manager or office.',
        [
          'teacher',
          'manager',
          'principal',
          'বরাবর',
          'শিক্ষক',
          'অধ্যক্ষ',
          'ম্যানেজার',
        ],
      ),
    ],
    'Formal Letter' => const [
      BriefQuestion(
        'purpose',
        'What should the letter request or explain?',
        'Describe the purpose in one sentence.',
        ['request', 'asking', 'purpose', 'চাই', 'আবেদন', 'অনুরোধ'],
      ),
      BriefQuestion(
        'recipient',
        'Who is the document for?',
        'For example: teacher, manager or office.',
        [' to ', 'recipient', 'বরাবর', 'কাছে'],
      ),
    ],
    'Invoice' => const [
      BriefQuestion(
        'parties',
        'Who is the seller and customer?',
        'Leave unknown names blank.',
        ['seller', 'customer', 'বিক্রেতা', 'ক্রেতা'],
      ),
      BriefQuestion(
        'items',
        'Which items, quantities and prices should be included?',
        'Include the currency. Unknown amounts will stay blank.',
        ['quantity', 'price', 'bdt', 'usd', 'দাম', 'টাকা', 'পরিমাণ'],
      ),
      BriefQuestion(
        'reference',
        'Any invoice number, date or tax details?',
        'Only include real details you already know.',
        ['invoice number', 'date:', 'tax', 'তারিখ', 'ভ্যাট'],
      ),
    ],
    'Assignment' => const [
      BriefQuestion(
        'topic',
        'What is the assignment topic?',
        'Name the topic or paste the question.',
        ['about ', 'topic', 'বিষয়', 'বিষয়', 'সম্পর্কে'],
      ),
      BriefQuestion(
        'level',
        'What level and length do you need?',
        'For example: college, 500 words.',
        [
          'words',
          'college',
          'school',
          'university',
          'শব্দ',
          'কলেজ',
          'শ্রেণি',
          'বিশ্ববিদ্যাল',
        ],
      ),
      BriefQuestion(
        'requirements',
        'Are there any teacher instructions?',
        'Add required headings or sources, if any.',
        ['instructions', 'headings', 'sources', 'নির্দেশ', 'উৎস'],
      ),
    ],
    _ => const [
      BriefQuestion(
        'purpose',
        'What would you like to create?',
        'For example: a study plan, notice or short report.',
        [''],
      ),
    ],
  };

  /// Explicit labels are hints, not a claim to understand every user's text.
  List<BriefQuestion> questionsFor(String details) {
    final text = details.trim().toLowerCase();
    if (type == 'Custom AI Document') {
      return text.length >= 10 ? const [] : questions;
    }
    return questions.where((q) => !q.markers.any(text.contains)).toList();
  }

  String compose(String details, Map<String, String> answers) {
    final parts = <String>[
      if (details.trim().isNotEmpty) details.trim(),
      for (final q in questions)
        if ((answers[q.id] ?? '').trim().isNotEmpty)
          '${q.label}: ${answers[q.id]!.trim()}',
    ];
    // Do not add an invisible suffix that can push a valid 2000-char brief
    // over the server limit. The server already enforces placeholder guidance.
    final text = parts.join('\n\n');
    return text.length >= 10
        ? text
        : 'Create a $type draft. Use editable placeholders for missing details. $text'
              .trim();
  }
}
