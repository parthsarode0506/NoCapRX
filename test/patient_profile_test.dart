import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/models/patient_profile.dart';

void main() {
  test('requires identity and contact details for completed intake', () {
    const incomplete = PatientProfile(fullName: 'Asha Rao');
    const complete = PatientProfile(
      fullName: 'Asha Rao',
      patientId: 'PAT-1024',
      email: 'asha@example.com',
      phoneNumber: '+919876543210',
      dateOfBirth: '18/06/1990',
    );

    expect(incomplete.hasCompletedIntake, isFalse);
    expect(complete.hasCompletedIntake, isTrue);
  });

  test('persists intake, measurements, and clinical details', () {
    const profile = PatientProfile(
      fullName: 'Asha Rao',
      patientId: 'PAT-1024',
      email: 'asha@example.com',
      phoneNumber: '+919876543210',
      dateOfBirth: '18/06/1990',
      height: '165',
      weight: '62',
      allergies: ['Penicillin'],
      currentMedicines: ['Metformin'],
    );

    final restored = PatientProfile.fromJson(profile.toJson());

    expect(restored.fullName, 'Asha Rao');
    expect(restored.dateOfBirth, '18/06/1990');
    expect(restored.height, '165');
    expect(restored.allergies, ['Penicillin']);
  });

  test('keeps patient details available for later dashboard display', () {
    const profile = PatientProfile(
      fullName: 'Asha Rao',
      patientId: 'PAT-1024',
      email: 'asha@example.com',
      phoneNumber: '+919876543210',
      age: '35',
      sex: 'Female',
      allergies: ['Penicillin'],
      currentMedicines: ['Metformin'],
      conditions: ['Asthma'],
    );

    final summary = profile.dashboardSummaryEntries;

    expect(summary['Name'], 'Asha Rao');
    expect(summary['Patient ID'], 'PAT-1024');
    expect(summary['Email'], 'asha@example.com');
    expect(summary['Phone'], '+919876543210');
    expect(summary['Age'], '35');
    expect(summary['Allergies'], 'Penicillin');
    expect(summary['Current medicines'], 'Metformin');
    expect(summary['Conditions'], 'Asthma');
  });
}
