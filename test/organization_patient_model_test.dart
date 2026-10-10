import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/models/organization_access.dart';
import 'package:ondevicerx/models/organization_patient.dart';

void main() {
  test('self-registered organizations are discoverable but not verified', () {
    final organization = OrganizationDirectoryEntry.fromJson({
      'organizationId': 'org-uid',
      'name': 'Sample Hospital',
      'city': 'Pune',
      'selfRegistered': true,
    });

    expect(organization.selfRegistered, isTrue);
    expect(organization.canRequestAccess, isFalse);
  });

  test(
    'parses an authorized patient summary without inventing report data',
    () {
      final patient = OrganizationPatient.fromCallable({
        'patientId': 'patient-123',
        'name': 'Asha Rao',
        'birthYear': 1988,
        'vcfStatus': 'not_shared',
        'analysisStatus': 'not_available',
        'reportCount': 0,
        'prescriptionCount': 0,
      });

      expect(patient.patientId, 'patient-123');
      expect(patient.name, 'Asha Rao');
      expect(patient.birthYear, 1988);
      expect(patient.vcfStatus, 'not_shared');
      expect(patient.analysisStatus, 'not_available');
      expect(patient.reportCount, 0);
      expect(patient.prescriptionCount, 0);
    },
  );

  test('uses explicit unavailable defaults for absent remote fields', () {
    final patient = OrganizationPatient.fromCallable({
      'patientId': 'patient-456',
      'name': 'Mira Shah',
    });

    expect(patient.vcfStatus, 'not_shared');
    expect(patient.analysisStatus, 'not_available');
    expect(patient.latestReportAt, isNull);
    expect(patient.reportCount, isNull);
    expect(patient.prescriptionCount, isNull);
  });

  test('parses an invitation preview for explicit patient review', () {
    final invitation = PatientInvitationPreview.fromCallable({
      'patientId': 'patient-789',
      'patientName': 'Anaya Patel',
      'organizationName': 'Sample Hospital',
      'organizationCity': 'Pune',
    });

    expect(invitation.patientId, 'patient-789');
    expect(invitation.patientName, 'Anaya Patel');
    expect(invitation.organizationName, 'Sample Hospital');
    expect(invitation.organizationCity, 'Pune');
  });

  test('parses the two-stage organization access invitation state', () {
    final invitation = PatientOrganizationInvitation.fromCallable({
      'organizationId': 'org-123',
      'organizationName': 'Sample Hospital',
      'patientUid': 'patient-uid',
      'patientId': 'patient-record',
      'patientName': 'Asha Rao',
      'status': 'awaiting_patient_confirmation',
      'consentActive': true,
      'requestedAt': '2026-02-03T04:05:06.000Z',
    });

    expect(invitation.organizationId, 'org-123');
    expect(invitation.patientUid, 'patient-uid');
    expect(invitation.patientId, 'patient-record');
    expect(invitation.patientName, 'Asha Rao');
    expect(invitation.status, 'awaiting_patient_confirmation');
    expect(invitation.consentActive, isTrue);
    expect(invitation.requestedAt, DateTime.utc(2026, 2, 3, 4, 5, 6));
  });

  test('keeps organization consent independent for multiple organizations', () {
    final first = PatientOrganizationInvitation.fromCallable({
      'organizationId': 'org-a',
      'organizationName': 'Hospital A',
      'status': 'accepted',
      'consentActive': true,
    });
    final second = PatientOrganizationInvitation.fromCallable({
      'organizationId': 'org-b',
      'organizationName': 'Hospital B',
      'status': 'accepted',
      'consentActive': true,
    });

    expect(first.organizationId, isNot(second.organizationId));
    expect(first.consentActive, isTrue);
    expect(second.consentActive, isTrue);
  });
}
