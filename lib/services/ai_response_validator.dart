import 'dart:convert';

/// Validates explanatory text without allowing it to become a medical result.
class AIResponseValidator {
  static const _requiredFields = <String>[
    'title',
    'summary',
    'whatItMeans',
    'whyThisResult',
    'importantRisks',
    'sideEffectExplanation',
    'whatToDiscussWithDoctor',
    'technicalDetails',
    'limitations',
  ];

  static Map<String, String>? validate(
    Map<String, dynamic> response,
    Map<String, dynamic> medicalResult,
  ) {
    for (final field in _requiredFields) {
      if (!response.containsKey(field)) return null;
    }

    final text = _flatten(response).toLowerCase();
    if (text.contains('100% safe') ||
        text.contains('100 percent safe') ||
        _containsMedicationChangeInstruction(text)) {
      return null;
    }

    final expectedRisk = _risk(medicalResult['riskLabel']);
    final mentionedRisks = <String>{
      _risk(response['title']),
      _risk(response['summary']),
      _risk(response['whatItMeans']),
      _risk(response['limitations']),
    };
    if (_contradicts(expectedRisk, mentionedRisks)) return null;

    final missingState = _missingState(medicalResult);
    if (missingState != null && !text.contains(missingState)) return null;

    final phenotype = _knownValue(medicalResult['phenotype']);
    final diplotype = _knownValue(medicalResult['diplotype']);
    if (phenotype == null && _mentionsTechnicalField(text, 'phenotype')) return null;
    if (diplotype == null && _mentionsTechnicalField(text, 'diplotype')) return null;

    final summary = _string(response['summary']);
    final patientFriendly = _string(response['whatItMeans']);
    if (summary == null || patientFriendly == null) return null;

    return {
      'summary': summary,
      'mechanism': _string(response['whyThisResult']) ?? '',
      'patient_friendly': patientFriendly,
      'clinician_note': _string(response['technicalDetails']) ?? '',
    };
  }

  static Map<String, dynamic>? decodeObject(String raw) {
    final cleaned = raw
        .replaceFirst(RegExp(r'^\s*```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```\s*$'), '')
        .trim();
    try {
      final decoded = jsonDecode(cleaned);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _missingState(Map<String, dynamic> result) {
    final verification = result['verificationStatus']?.toString().toLowerCase();
    if (verification == 'medicine not verified') return 'medicine not verified';
    final risk = result['riskLabel']?.toString().toLowerCase() ?? '';
    if (risk.contains('unknown') || risk.contains('insufficient')) {
      return risk.contains('insufficient') ? 'insufficient' : 'unknown';
    }
    return null;
  }

  static bool _containsMedicationChangeInstruction(String text) {
    final matches = RegExp(
      r'\b(start|stop|change|increase|decrease|skip|switch)\b.{0,35}\b(medicine|medication|dose|drug)\b',
    ).allMatches(text);
    return matches.any((match) {
      final before = text.substring(0, match.start);
      return !before.endsWith('do not ') && !before.endsWith('never ');
    });
  }

  static bool _contradicts(String expected, Set<String> mentioned) {
    if (expected.isEmpty) return false;
    if (expected == 'high risk' && mentioned.contains('safe')) return true;
    if (expected == 'safe' && (mentioned.contains('high risk') || mentioned.contains('unsafe'))) return true;
    if (expected == 'unknown' && (mentioned.contains('safe') || mentioned.contains('high risk'))) return true;
    if (expected == 'adjust dosage' && mentioned.contains('safe')) return true;
    if (expected == 'ineffective' && mentioned.contains('safe')) return true;
    return false;
  }

  static String _risk(dynamic value) {
    final text = value?.toString().toLowerCase() ?? '';
    if (text.contains('high') || text.contains('contraindicat') || text.contains('toxic')) return 'high risk';
    if (text.contains('adjust') || text.contains('dose')) return 'adjust dosage';
    if (text.contains('ineffective') || text.contains('reduced')) return 'ineffective';
    if (text.contains('unknown') || text.contains('insufficient')) return 'unknown';
    if (text.contains('safe') || text.contains('no major')) return 'safe';
    return '';
  }

  static String _flatten(dynamic value) {
    if (value is Map) return value.values.map(_flatten).join(' ');
    if (value is Iterable) return value.map(_flatten).join(' ');
    return value?.toString() ?? '';
  }

  static String? _string(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _knownValue(dynamic value) {
    final text = _string(value)?.toLowerCase();
    if (text == null || text.isEmpty || text == 'unknown' || text == 'unavailable') return null;
    return text;
  }

  static bool _mentionsTechnicalField(String text, String field) => text.contains(field);
}