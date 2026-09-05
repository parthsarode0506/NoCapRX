class RequiredPatientData {
  final List<String> geneticRequirements;
  final List<String> clinicalRequirements;

  const RequiredPatientData({
    this.geneticRequirements = const [],
    this.clinicalRequirements = const [],
  });

  bool get requiresClinicalInput => clinicalRequirements.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'genetic_requirements': geneticRequirements,
        'clinical_requirements': clinicalRequirements,
      };

  factory RequiredPatientData.fromJson(Map<String, dynamic> json) =>
      RequiredPatientData(
        geneticRequirements: (json['genetic_requirements'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        clinicalRequirements: (json['clinical_requirements'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
