import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/models/prescription.dart';
import 'package:ondevicerx/services/prescription_service.dart';
import 'package:ondevicerx/services/audit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pharmacogenomics Prescription Engine & Lifecycle', () {
    test('new prescription items default to an honest indeterminate status', () {
      const item = PrescriptionItem(
        medicineName: 'Synthetic medicine',
        dosage: 'clinician-entered',
        frequency: 'clinician-entered',
        duration: 'clinician-entered',
      );

      expect(item.pgxRiskLabel, 'Indeterminate');
      expect(item.isActionableRisk, isFalse);
      expect(item.isCaution, isFalse);
      expect(item.alternativeDrugs, isEmpty);
    });

    test('PrescriptionItem correctly classifies high-risk and caution drugs', () {
      const toxicItem = PrescriptionItem(
        medicineName: 'Clopidogrel',
        dosage: '75mg',
        frequency: 'Once daily',
        duration: '30 days',
        pgxRiskLabel: 'Ineffective',
        severity: 'critical',
        gene: 'CYP2C19',
        phenotype: 'CYP2C19 Poor Metabolizer',
        alternativeDrugs: ['Prasugrel', 'Ticagrelor'],
      );

      expect(toxicItem.isActionableRisk, isTrue);
      expect(toxicItem.alternativeDrugs, contains('Prasugrel'));

      const safeItem = PrescriptionItem(
        medicineName: 'Prasugrel',
        dosage: '10mg',
        frequency: 'Once daily',
        duration: '30 days',
        pgxRiskLabel: 'Safe',
        severity: 'none',
      );

      expect(safeItem.isActionableRisk, isFalse);
      expect(safeItem.isCaution, isFalse);
    });

    test('Prescription model creates, updates, and detects actionable risks', () {
      final rx = Prescription(
        prescriptionId: 'RX-TEST-001',
        patientId: 'PATIENT_001',
        patientName: 'Alex Mercer',
        organizationId: 'ORG-APOLLO',
        organizationName: 'Apollo Hospital',
        prescriberId: 'DOC-1',
        prescriberName: 'Dr. Test',
        status: 'draft',
        createdAt: DateTime.now(),
        items: const [
          PrescriptionItem(
            medicineName: 'Clopidogrel',
            dosage: '75mg',
            frequency: 'Once daily',
            duration: '30 days',
            pgxRiskLabel: 'Ineffective',
            severity: 'critical',
          ),
        ],
      );

      expect(rx.isDraft, isTrue);
      expect(rx.isIssued, isFalse);
      expect(rx.hasActionableRisks, isTrue);

      final issued = rx.copyWith(status: 'issued', issuedAt: DateTime.now());
      expect(issued.isIssued, isTrue);
      expect(issued.issuedAt, isNotNull);
    });

    test('PrescriptionService can save, retrieve, and issue prescriptions', () async {
      final service = PrescriptionService.instance;
      final newRx = Prescription(
        prescriptionId: 'RX-TEST-999',
        patientId: 'PATIENT_TEST_99',
        patientName: 'Unit Test Patient',
        organizationId: 'ORG-TEST',
        organizationName: 'Test Clinic',
        prescriberId: 'DOC-TEST',
        prescriberName: 'Dr. Unit Test',
        status: 'draft',
        createdAt: DateTime.now(),
        items: const [
          PrescriptionItem(
            medicineName: 'Rosuvastatin',
            dosage: '10mg',
            frequency: 'Once daily',
            duration: '30 days',
          ),
        ],
      );

      await service.savePrescription(newRx);

      final patientStream = service.streamPatientPrescriptions('PATIENT_TEST_99');
      final list = await patientStream.first;
      expect(list.any((p) => p.prescriptionId == 'RX-TEST-999'), isTrue);

      await service.issuePrescription('RX-TEST-999');
      final updatedList = await service.streamPatientPrescriptions('PATIENT_TEST_99').first;
      final issuedRx = updatedList.firstWhere((p) => p.prescriptionId == 'RX-TEST-999');
      expect(issuedRx.isIssued, isTrue);
    });

    test('AuditService records security and clinical events', () async {
      final audit = AuditService.instance;
      await audit.recordLog(
        action: 'prescription_issued',
        actorUid: 'DOC-123',
        actorRole: 'doctor',
        organizationId: 'ORG-1',
        targetId: 'PATIENT-1',
        description: 'Test prescription issued for PATIENT-1.',
      );

      final stream = audit.streamAuditLogs();
      final logs = await stream.first;
      expect(logs.any((l) => l.description.contains('Test prescription issued')), isTrue);
    });
  });
}
