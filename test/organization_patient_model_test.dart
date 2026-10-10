import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/models/organization_patient.dart';

void main() {
  test(
    'parses an authorized patient summary without inventing report data',
    () {
      final patient = OrganizationPatient.fromCallable({
        'patientId': 'patient-123',
        'name': 'Asha Rao',
        'birthYear': 1988,
        'vcfStatus': 'not_uploaded',
        'analysisStatus': 'not_started',
        'reportCount': 0,
        'prescriptionCount': 0,
      });

      expect(patient.patientId, 'patient-123');
      expect(patient.name, 'Asha Rao');
      expect(patient.birthYear, 1988);
      expect(patient.vcfStatus, 'not_uploaded');
      expect(patient.analysisStatus, 'not_started');
      expect(patient.reportCount, 0);
      expect(patient.prescriptionCount, 0);
    },
  );

  test('uses explicit unavailable defaults for absent remote fields', () {
    final patient = OrganizationPatient.fromCallable({
      'patientId': 'patient-456',
      'name': 'Mira Shah',
    });

    expect(patient.vcfStatus, 'not_uploaded');
    expect(patient.analysisStatus, 'not_started');
    expect(patient.latestReportAt, isNull);
  });
}
