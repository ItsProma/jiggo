String aiLimitMessage(Object? details) {
  final reason = details is Map ? details['reason'] : null;
  switch (reason) {
    case 'rate-limit':
      final seconds = details is Map ? details['retryAfterSeconds'] : null;
      final wait = seconds is num && seconds.isFinite && seconds > 0
          ? seconds.ceil().clamp(1, 120) : 60;
      return 'Please wait about $wait seconds before sending another AI request.';
    case 'concurrency-limit':
      return 'An AI request is still running. Wait for it to finish and try again.';
    case 'global-budget':
      return "Today's app-wide AI limit has been reached. Please try again tomorrow.";
    case 'daily-attempts':
      return 'Too many AI attempts today. Please try again tomorrow.';
    case 'ai-paused':
      return 'AI is temporarily paused. Please try again later.';
    default:
      return 'Daily limit reached. Please try again tomorrow.';
  }
}

String? aiSafetyMessage(Object? details) {
  final reason = details is Map ? details['reason'] : null;
  return switch (reason) {
    'safety-blocked' => 'Jiggo could not help with this request safely. Please use a school question or an appropriate document request.',
    'safety-unavailable' => 'The safety check is unavailable. Nothing was saved. Please try again later.',
    'provider-incomplete' => 'The AI response was incomplete. Nothing was saved. Please try a shorter request.',
    'account-changed' => 'The signed-in account changed. Please try again.',
    'age-eligibility' => 'Complete the 13+ AI eligibility check before generating content.',
    _ => null,
  };
}
