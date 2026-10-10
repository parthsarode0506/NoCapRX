class PatientProfile {
  final String fullName;
  final String patientId;
  final String email;
  final String phoneNumber;
  final String dateOfBirth;
  final String age;
  final String sex;
  final String weight;
  final String height;
  final List<String> allergies;
  final List<String> currentMedicines;
  final List<String> conditions;
  final String pregnancyStatus;
  final String kidneyFunction;
  final String liverFunction;
  final String? vcfFilename;

  const PatientProfile({
    this.fullName = '',
    this.patientId = '',
    this.email = '',
    this.phoneNumber = '',
    this.dateOfBirth = '',
    this.age = '',
    this.sex = '',
    this.weight = '',
    this.height = '',
    this.allergies = const [],
    this.currentMedicines = const [],
    this.conditions = const [],
    this.pregnancyStatus = '',
    this.kidneyFunction = '',
    this.liverFunction = '',
    this.vcfFilename,
  });

  bool get hasData =>
      fullName.isNotEmpty ||
      patientId.isNotEmpty ||
      email.isNotEmpty ||
      phoneNumber.isNotEmpty ||
      dateOfBirth.isNotEmpty ||
      age.isNotEmpty ||
      sex.isNotEmpty ||
      weight.isNotEmpty ||
      height.isNotEmpty ||
      allergies.isNotEmpty ||
      currentMedicines.isNotEmpty ||
      conditions.isNotEmpty ||
      pregnancyStatus.isNotEmpty ||
      kidneyFunction.isNotEmpty ||
      liverFunction.isNotEmpty;

  /// The dashboard uses this to decide whether the signed-in patient needs
  /// to complete the local intake before starting a VCF or medicine check.
  bool get hasCompletedIntake =>
      fullName.trim().isNotEmpty &&
      patientId.trim().isNotEmpty &&
      email.trim().isNotEmpty &&
      phoneNumber.trim().isNotEmpty &&
      dateOfBirth.trim().isNotEmpty;

  PatientProfile copyWith({
    String? fullName,
    String? patientId,
    String? email,
    String? phoneNumber,
    String? dateOfBirth,
    String? age,
    String? sex,
    String? weight,
    String? height,
    List<String>? allergies,
    List<String>? currentMedicines,
    List<String>? conditions,
    String? pregnancyStatus,
    String? kidneyFunction,
    String? liverFunction,
    String? vcfFilename,
  }) {
    return PatientProfile(
      fullName: fullName ?? this.fullName,
      patientId: patientId ?? this.patientId,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      age: age ?? this.age,
      sex: sex ?? this.sex,
      weight: weight ?? this.weight,
      height: height ?? this.height,
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

  Map<String, String> get dashboardSummaryEntries {
    final map = <String, String>{};

    if (fullName.trim().isNotEmpty) map['Name'] = fullName.trim();
    if (patientId.trim().isNotEmpty) map['Patient ID'] = patientId.trim();
    if (email.trim().isNotEmpty) map['Email'] = email.trim();
    if (phoneNumber.trim().isNotEmpty) map['Phone'] = phoneNumber.trim();
    if (age.trim().isNotEmpty) map['Age'] = age.trim();
    if (sex.trim().isNotEmpty) map['Sex'] = sex.trim();
    if (weight.trim().isNotEmpty) map['Weight'] = weight.trim();
    if (height.trim().isNotEmpty) map['Height'] = height.trim();
    if (allergies.isNotEmpty) map['Allergies'] = allergies.join(', ');
    if (currentMedicines.isNotEmpty) {
      map['Current medicines'] = currentMedicines.join(', ');
    }
    if (conditions.isNotEmpty) map['Conditions'] = conditions.join(', ');
    if (pregnancyStatus.trim().isNotEmpty) {
      map['Pregnancy'] = pregnancyStatus.trim();
    }
    if (kidneyFunction.trim().isNotEmpty) {
      map['Kidney'] = kidneyFunction.trim();
    }
    if (liverFunction.trim().isNotEmpty) {
      map['Liver'] = liverFunction.trim();
    }

    return map;
  }

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'patient_id': patientId,
    'email': email,
    'phone_number': phoneNumber,
    'date_of_birth': dateOfBirth,
    'age': age,
    'sex': sex,
    'weight': weight,
    'height': height,
    'allergies': allergies,
    'current_medicines': currentMedicines,
    'conditions': conditions,
    'pregnancy_status': pregnancyStatus,
    'kidney_function': kidneyFunction,
    'liver_function': liverFunction,
    'vcf_filename': vcfFilename,
  };

  factory PatientProfile.fromJson(Map<String, dynamic> json) => PatientProfile(
    fullName: json['full_name'] as String? ?? '',
    patientId: json['patient_id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phoneNumber: json['phone_number'] as String? ?? '',
    dateOfBirth: json['date_of_birth'] as String? ?? '',
    age: json['age'] as String? ?? '',
    sex: json['sex'] as String? ?? '',
    weight: json['weight'] as String? ?? '',
    height: json['height'] as String? ?? '',
    allergies: _strings(json['allergies']),
    currentMedicines: _strings(json['current_medicines']),
    conditions: _strings(json['conditions']),
    pregnancyStatus: json['pregnancy_status'] as String? ?? '',
    kidneyFunction: json['kidney_function'] as String? ?? '',
    liverFunction: json['liver_function'] as String? ?? '',
    vcfFilename: json['vcf_filename'] as String?,
  );

  static List<String> _strings(dynamic value) =>
      value is List ? value.map((item) => item.toString()).toList() : const [];
}
