class ChatSafetyFilter {
  static const footer =
      'This is general medicine information, not medical advice. Confirm with a doctor or pharmacist.';

  static const _bannedPhrases = [
    'stop taking',
    'you are cured',
    'safe to combine',
    'change your dose',
    'increase your dose',
    'decrease your dose',
    'you are safe',
  ];

  static String? validate(String text) {
    final normalized = text.toLowerCase();
    if (text.trim().isEmpty || text.length > 1200) return null;
    if (_bannedPhrases.any(normalized.contains)) return null;
    return text.trim();
  }

  static String withFooter(String text) =>
      '$text\n\n$footer';
}