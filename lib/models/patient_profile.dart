class PatientProfile {
  final String patientId;
  final String age;
  final String sex;
  final String weight;
  final List<String> allergies;
  final List<String> currentMedicines;
  final List<String> conditions;
  final String pregnancyStatus;
  final String kidneyFunction;
  final String liverFunction;
  final String? vcfFilename;

  const PatientProfile({
    this.patientId = 'PATIENT_001',
    this.age = '',
    this.sex = '',
    this.weight = '',
    this.allergies = const [],
    this.currentMedicines = const [],
    this.conditions = const [],
    this.pregnancyStatus = '',
    this.kidneyFunction = '',
    this.liverFunction = '',
    this.vcfFilename,
  });

  bool get hasData =>
      age.isNotEmpty ||
      sex.isNotEmpty ||
      weight.isNotEmpty ||
      allergies.isNotEmpty ||
      currentMedicines.isNotEmpty ||
      conditions.isNotEmpty ||
      pregnancyStatus.isNotEmpty ||
      kidneyFunction.isNotEmpty ||
      liverFunction.isNotEmpty;

  PatientProfile copyWith({
    String? patientId,
    String? age,
    String? sex,
    String? weight,
    List<String>? allergies,
    List<String>? currentMedicines,
    List<String>? conditions,
    String? pregnancyStatus,
    String? kidneyFunction,
    String? liverFunction,
    String? vcfFilename,
  }) {
    return PatientProfile(
      patientId: patientId ?? this.patientId,
      age: age ?? this.age,
      sex: sex ?? this.sex,
      weight: weight ?? this.weight,
      allergies: allergies ?? this.allergies,
      currentMedicines: currentMedicines ?? this.currentMedicines,
      conditions: conditions ?? this.conditions,
      pregnancyStatus: pregnancyStatus ?? this.pregnancyStatus,
      kidneyFunction: kidneyFunction ?? this.kidneyFunction,
      liverFunction: liverFunction ?? this.liverFunction,
      vcfFilename: vcfFilename ?? this.vcfFilename,
    );
  }

  Map<String, String> toClinicalDataMap() {
    final map = <String, String>{};
    if (age.trim().isNotEmpty) map['Age'] = age.trim();
    if (sex.trim().isNotEmpty) map['Sex'] = sex.trim();
    if (weight.trim().isNotEmpty) map['Weight'] = weight.trim();
    if (allergies.isNotEmpty) {
      map['Known allergies'] = allergies.join(', ');
    }
    if (currentMedicines.isNotEmpty) {
      map['Current medicines'] = currentMedicines.join(', ');
    }
    if (conditions.isNotEmpty) {
      map['Relevant conditions'] = conditions.join(', ');
    }
    if (pregnancyStatus.trim().isNotEmpty) {
      map['Pregnancy/breastfeeding'] = pregnancyStatus.trim();
    }
    if (kidneyFunction.trim().isNotEmpty) {
      map['Kidney function'] = kidneyFunction.trim();
    }
    if (liverFunction.trim().isNotEmpty) {
      map['Liver function'] = liverFunction.trim();
    }
    return map;
  }

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'age': age,
        'sex': sex,
        'weight': weight,
        'allergies': allergies,
        'current_medicines': currentMedicines,
        'conditions': conditions,
        'pregnancy_status': pregnancyStatus,
        'kidney_function': kidneyFunction,
        'liver_function': liverFunction,
        'vcf_filename': vcfFilename,
      };

  factory PatientProfile.fromJson(Map<String, dynamic> json) => PatientProfile(
        patientId: json['patient_id'] as String? ?? 'PATIENT_001',
        age: json['age'] as String? ?? '',
        sex: json['sex'] as String? ?? '',
        weight: json['weight'] as String? ?? '',
        allergies: _strings(json['allergies']),
        currentMedicines: _strings(json['current_medicines']),
        conditions: _strings(json['conditions']),
        pregnancyStatus: json['pregnancy_status'] as String? ?? '',
        kidneyFunction: json['kidney_function'] as String? ?? '',
        liverFunction: json['liver_function'] as String? ?? '',
        vcfFilename: json['vcf_filename'] as String?,
      );

  static List<String> _strings(dynamic value) => value is List
      ? value.map((item) => item.toString()).toList()
      : const [];
}