class MedicineIdentity {
  final String inputName;
  final String genericName;
  final String displayName;
  final List<String> aliases;
  final List<String> activeIngredients;
  final String? strength;
  final String? dosageForm;
  final bool verified;
  final double confidence;
  final String? drugClass;
  final bool foundLocally;
  final bool foundOnline;
  final bool isAmbiguous;
  final List<String> ambiguousMatches;

  const MedicineIdentity({
    required this.inputName,
    required this.genericName,
    required this.displayName,
    this.aliases = const [],
    this.activeIngredients = const [],
    this.strength,
    this.dosageForm,
    this.verified = false,
    this.confidence = 0.0,
    this.drugClass,
    this.foundLocally = false,
    this.foundOnline = false,
    this.isAmbiguous = false,
    this.ambiguousMatches = const [],
  });

  Map<String, dynamic> toJson() => {
        'input_name': inputName,
        'generic_name': genericName,
        'display_name': displayName,
        'aliases': aliases,
        'active_ingredients': activeIngredients,
        'strength': strength,
        'dosage_form': dosageForm,
        'verified': verified,
        'confidence': confidence,
        'drug_class': drugClass,
        'found_locally': foundLocally,
        'found_online': foundOnline,
        'is_ambiguous': isAmbiguous,
        'ambiguous_matches': ambiguousMatches,
      };

  factory MedicineIdentity.fromJson(Map<String, dynamic> json) =>
      MedicineIdentity(
        inputName: json['input_name'] as String? ?? '',
        genericName: json['generic_name'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        aliases: (json['aliases'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
            activeIngredients: (json['active_ingredients'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
              const [],
            strength: json['strength'] as String?,
            dosageForm: json['dosage_form'] as String?,
            verified: json['verified'] as bool? ?? false,
            confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        drugClass: json['drug_class'] as String?,
        foundLocally: json['found_locally'] as bool? ?? false,
        foundOnline: json['found_online'] as bool? ?? false,
        isAmbiguous: json['is_ambiguous'] as bool? ?? false,
        ambiguousMatches: (json['ambiguous_matches'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
