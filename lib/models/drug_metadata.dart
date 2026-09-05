/// Describes a medicine supported by the immutable, on-device evidence panel.
/// This is intentionally metadata only: patient-specific conclusions belong in
/// the deterministic rule engine, never in a widget or an LLM.
class DrugMetadata {
  final String genericName;
  final String displayName;
  final List<String> aliases;
  final List<String> genes;
  final List<String> requiredClinicalData;
  final String evidenceSource;
  final bool ruleAvailable;
  final List<String> uses;
  final List<String> commonSideEffects;
  final List<String> seriousSideEffects;
  final List<String> precautions;

  const DrugMetadata({
    required this.genericName,
    required this.displayName,
    required this.aliases,
    required this.genes,
    required this.requiredClinicalData,
    required this.evidenceSource,
    this.ruleAvailable = true,
    this.uses = const [],
    this.commonSideEffects = const [],
    this.seriousSideEffects = const [],
    this.precautions = const [],
  });

  bool matches(String query) {
    final normalized = _normalize(query);
    return _normalize(genericName) == normalized ||
        _normalize(displayName) == normalized ||
        aliases.any((alias) => _normalize(alias) == normalized);
  }

  static String _normalize(String value) => value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
      .trim();
}
