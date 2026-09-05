import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/models/patient_profile.dart';
import 'package:ondevicerx/models/drug_evidence.dart';
import 'package:ondevicerx/services/personalized_side_effect_engine.dart';
import 'package:ondevicerx/services/universal_medicine_safety_engine.dart';

void main() {
  group('PatientProfile Model Tests', () {
    test('serializes and deserializes correctly', () {
      const profile = PatientProfile(
        patientId: 'PATIENT_101',
        age: '65',
        sex: 'Male',
        weight: '75',
        allergies: ['Penicillin', 'Sulfa'],
        currentMedicines: ['Warfarin', 'Lisinopril'],
        conditions: ['Hypertension', 'Peptic Ulcer'],
        pregnancyStatus: '',
        kidneyFunction: 'Mild renal impairment',
        liverFunction: 'Normal function',
      );

      final json = profile.toJson();
      final reconstructed = PatientProfile.fromJson(json);

      expect(reconstructed.patientId, 'PATIENT_101');
      expect(reconstructed.age, '65');
      expect(reconstructed.allergies, contains('Penicillin'));
      expect(reconstructed.currentMedicines, contains('Warfarin'));
      expect(reconstructed.conditions, contains('Peptic Ulcer'));
      expect(reconstructed.hasData, isTrue);

      final clinicalMap = reconstructed.toClinicalDataMap();
      expect(clinicalMap['Age'], '65');
      expect(clinicalMap['Known allergies'], contains('Penicillin'));
      expect(clinicalMap['Current medicines'], contains('Warfarin'));
      expect(clinicalMap['Relevant conditions'], contains('Peptic Ulcer'));
    });

    test('copyWith creates updated instances without mutating original', () {
      const original = PatientProfile(age: '50', sex: 'Female');
      final updated = original.copyWith(weight: '60', allergies: ['Aspirin']);

      expect(updated.age, '50');
      expect(updated.sex, 'Female');
      expect(updated.weight, '60');
      expect(updated.allergies, ['Aspirin']);
      expect(original.weight, '');
    });
  });

  group('UniversalMedicineSafetyEngine Tests', () {
    test('detects serious NSAID allergy contraindication', () {
      final findings = UniversalMedicineSafetyEngine.evaluateAll('Ibuprofen', {
        'Known allergies': 'Aspirin, NSAIDs',
      });

      expect(findings.any((f) => f.status == 'CONTRAINDICATED'), isTrue);
      expect(findings.first.title, contains('NSAID / Aspirin Allergy'));
    });

    test('detects penicillin allergy with amoxicillin', () {
      final findings = UniversalMedicineSafetyEngine.evaluateAll('Amoxicillin', {
        'Known allergies': 'Penicillin',
      });

      expect(findings.any((f) => f.status == 'CONTRAINDICATED'), isTrue);
      expect(findings.first.title, contains('Penicillin'));
    });

    test('detects major anticoagulant drug-drug interaction with Aspirin', () {
      final findings = UniversalMedicineSafetyEngine.evaluateAll('Aspirin', {
        'Current medicines': 'Warfarin, Metformin',
      });

      expect(findings.any((f) => f.status == 'DRUG_INTERACTION_DETECTED'), isTrue);
      expect(findings.any((f) => f.title.contains('Anticoagulant Interaction')), isTrue);
    });

    test('detects statin CYP3A4 inhibitor interaction', () {
      final findings = UniversalMedicineSafetyEngine.evaluateAll('Simvastatin', {
        'Current medicines': 'Clarithromycin, Amlodipine',
      });

      expect(findings.any((f) => f.status == 'CONTRAINDICATED'), isTrue);
    });

    test('detects peptic ulcer condition precaution', () {
      final findings = UniversalMedicineSafetyEngine.evaluateAll('Ibuprofen', {
        'Relevant conditions': 'History of peptic ulcer and gastrointestinal bleeding',
      });

      expect(findings.any((f) => f.status == 'USE_WITH_CAUTION'), isTrue);
      expect(findings.first.title, contains('Peptic Ulcer'));
    });

    test('determines overall assessment correctly', () {
      final contraStatus = UniversalMedicineSafetyEngine.determineOverallStatus(
        pgxRiskLabel: 'Safe',
        clinicalFindings: [
          const ClinicalSafetyFinding(
            status: 'CONTRAINDICATED',
            title: 'Allergy',
            explanation: 'Allergic',
            evidenceSource: 'FDA',
          )
        ],
        hasMissingData: false,
      );
      expect(contraStatus, 'Contraindication identified');

      final safeStatus = UniversalMedicineSafetyEngine.determineOverallStatus(
        pgxRiskLabel: 'Safe',
        clinicalFindings: const [],
        hasMissingData: false,
      );
      expect(safeStatus, 'No major risk identified');
    });
  });

  group('PersonalizedSideEffectEngine Tests', () {
    const ibuprofenEvidence = DrugEvidence(
      genericName: 'IBUPROFEN',
      displayName: 'Ibuprofen',
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    );

    test('personalizes bleeding risk when ulcer and anticoagulant present', () {
      final results = PersonalizedSideEffectEngine.evaluate(ibuprofenEvidence, {
        'Relevant conditions': 'Peptic ulcer',
        'Current medicines': 'Warfarin',
        'Age': '68',
      });

      final bleeding = results.firstWhere((r) => r.sideEffect.toLowerCase().contains('bleed'));
      expect(bleeding.relevance, 'HIGHER_CONCERN');
      expect(bleeding.patientRiskFactors, contains('Reported ulcer or bleeding history'));
      expect(bleeding.patientRiskFactors, contains('Reported anticoagulant medicine'));
      expect(bleeding.patientRiskFactors, contains('Age 65 or older'));
      expect(bleeding.higherRiskGroups, isNotEmpty);
      expect(bleeding.explanation, contains('Your profile contains factors associated with increased risk'));
    });

    test('reports no specific risk factor found when profile is negative', () {
      final results = PersonalizedSideEffectEngine.evaluate(ibuprofenEvidence, {
        'Relevant conditions': 'None',
        'Current medicines': 'None',
        'Age': '25',
      });

      final bleeding = results.firstWhere((r) => r.sideEffect.toLowerCase().contains('bleed'));
      expect(bleeding.relevance, 'NO_SPECIFIC_RISK_FACTOR_IDENTIFIED');
      expect(bleeding.patientRiskFactors, isEmpty);
      expect(bleeding.explanation, contains('No corresponding risk factor was identified'));
    });

    test('personalizes Codeine respiratory depression risk with concurrent sedatives', () {
      const codeineEvidence = DrugEvidence(
        genericName: 'CODEINE',
        displayName: 'Codeine',
        retrievalTimestamp: '2026-09-05T00:00:00Z',
      );

      final results = PersonalizedSideEffectEngine.evaluate(codeineEvidence, {
        'Current medicines': 'Lorazepam, Diazepam',
        'Relevant conditions': 'Asthma',
      });

      final resp = results.firstWhere((r) => r.sideEffect.toLowerCase().contains('respiratory'));
      expect(resp.relevance, 'HIGHER_CONCERN');
      expect(resp.patientRiskFactors, contains('Reported concurrent sedative or CNS depressant medication'));
      expect(resp.patientRiskFactors, contains('Reported respiratory condition'));
    });
  });
}
