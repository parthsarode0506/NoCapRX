import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result for the deliberately narrow online discovery boundary.
class OnlineEvidenceResult {
  final bool evidenceValidated;
  final String message;
  final Uri? sourceUrl;

  const OnlineEvidenceResult(
    this.evidenceValidated,
    this.message, {
    this.sourceUrl,
  });
}

/// Looks up public FDA labeling for an entered medicine. This is general drug
/// information only; it never creates or changes a patient-specific PGx rule.
class OnlineEvidenceService {
  static Future<OnlineEvidenceResult> discover(String medicine) async {
    final query = medicine.trim();
    if (query.isEmpty) {
      return const OnlineEvidenceResult(
        false,
        'Enter a medicine name to search official labeling.',
      );
    }

    final uri = Uri.https('api.fda.gov', '/drug/label.json', {
      'search': 'openfda.generic_name:$query OR openfda.brand_name:$query',
      'limit': '1',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return OnlineEvidenceResult(
          false,
          'No official FDA label was found for "$query".',
          sourceUrl: uri,
        );
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      final result =
          (body['results'] as List<dynamic>?)?.firstOrNull
              as Map<String, dynamic>?;
      if (result == null) {
        return OnlineEvidenceResult(
          false,
          'No official FDA label was found for "$query".',
          sourceUrl: uri,
        );
      }

      final openFda = result['openfda'] as Map<String, dynamic>?;
      final genericName = _first(openFda?['generic_name']) ?? query;
      final purpose =
          _first(result['purpose']) ?? _first(result['indications_and_usage']);
      final warnings =
          _first(result['warnings']) ?? _first(result['boxed_warning']);
      final details = <String>[
        'Official FDA label found for $genericName.',
        if (purpose != null) 'Use: $purpose',
        if (warnings != null) 'Warnings: $warnings',
        'This label is general drug information and cannot determine whether the medicine is safe for this patient.',
      ].join(' ');
      return OnlineEvidenceResult(true, details, sourceUrl: uri);
    } catch (_) {
      return OnlineEvidenceResult(
        false,
        'The official drug-label search is unavailable. The PGx result was not changed.',
        sourceUrl: uri,
      );
    }
  }

  static String? _first(dynamic value) {
    if (value is List && value.isNotEmpty) return value.first.toString();
    if (value is String && value.isNotEmpty) return value;
    return null;
  }
}
