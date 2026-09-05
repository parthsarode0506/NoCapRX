import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/models/drug_evidence.dart';
import 'package:ondevicerx/parser/vcf_parser.dart';
import 'package:ondevicerx/rules_engine/cpic_rule_engine.dart';
import 'package:ondevicerx/services/online_evidence_service.dart';
import 'package:ondevicerx/services/medicine_normalization_service.dart';
import 'package:ondevicerx/services/personalized_side_effect_engine.dart';
import 'package:ondevicerx/services/drug_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves a brand name only through the local catalogue', () {
    expect(DrugRepository.resolve('plavix')?.genericName, 'CLOPIDOGREL');
  });

  test('does not guess an unsupported medicine', () {
    expect(DrugRepository.resolve('made up medicine'), isNull);
  });

  test('corrects Aspirine to verified Aspirin identity', () {
    final identity = MedicineNormalizationService.identify('Aspirine');

    expect(identity.genericName, 'ASPIRIN');
    expect(identity.displayName, contains('Aspirin'));
    expect(identity.activeIngredients, contains('Aspirin'));
    expect(identity.verified, isTrue);
  });

  test('discovers verified Aspirin without turning no-PGx into unknown medicine', () async {
    final result = await OnlineEvidenceService.discover('Aspirine');

    expect(result.evidence?.genericName, 'ASPIRIN');
    expect(result.evidence?.verifiedMedicine, isTrue);
    expect(result.evidence?.hasPgxRelationship, isFalse);
    expect(result.evidence?.requiredClinicalData, contains('Known allergies'));
  });

  test('keeps Aspirin PGx status separate from the overall assessment', () async {
    final evidence = (await OnlineEvidenceService.discover('Aspirine')).evidence!;
    final parsed = VcfParser.parseVcfContent('''##fileformat=VCFv4.2
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
''');
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'Aspirine',
      parseResult: parsed,
      evidence: evidence,
      clinicalData: {
        'Known allergies': 'None known',
        'Current medicines': 'None',
        'Relevant conditions': 'None known',
        'Dose and route': '81 mg oral tablet',
      },
    );

    expect(report.riskAssessment.riskLabel, 'No major risk identified');
    expect(report.pharmacogenomicProfile.primaryGene, 'NON-PGX');
    expect(report.evidence?.hasPgxRelationship, isFalse);
    expect(report.toJson()['final_assessment']['status'],
        'NO_MAJOR_RISK_IDENTIFIED');
  });

  test('clinical allergy finding overrides PGx outcome', () async {
    final evidence = (await OnlineEvidenceService.discover('Aspirin')).evidence!;
    final parsed = VcfParser.parseVcfContent('''##fileformat=VCFv4.2
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
''');
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'Aspirin',
      parseResult: parsed,
      evidence: evidence,
      clinicalData: {'Known allergies': 'Aspirin', 'Current medicines': 'None'},
    );

    expect(report.riskAssessment.riskLabel, 'CONTRAINDICATED');
    expect(report.llmGeneratedExplanation.summary, contains('CONTRAINDICATED'));
  });

  test('matches patient factors to serious side-effect risks', () async {
    final evidence = (await OnlineEvidenceService.discover('Ibuprofen')).evidence!;
    final findings = PersonalizedSideEffectEngine.evaluate(evidence, {
      'Relevant conditions': 'Previous stomach ulcer',
      'Current medicines': 'Warfarin',
      'Kidney function': 'No known kidney disease',
      'Age': '62',
    });

    final bleeding = findings.firstWhere(
      (finding) => finding.sideEffect.toLowerCase().contains('bleed'),
    );
    expect(bleeding.relevance, 'HIGHER_CONCERN');
    expect(bleeding.patientRiskFactors, contains('Reported ulcer or bleeding history'));
    expect(bleeding.patientRiskFactors, contains('Reported anticoagulant medicine'));
    expect(bleeding.higherRiskGroups, isNotEmpty);
  });

  test('discovers an authoritative online catalog entry through a brand alias', () async {
    final result = await OnlineEvidenceService.discover('Prograf');

    expect(result.evidence?.genericName, 'TACROLIMUS');
    expect(result.evidence?.genes, contains('CYP3A5'));
    expect(result.evidence?.isOnlineDiscovered, isTrue);
  });

  test('reports no known PGx relationship explicitly', () {
    final parsed = VcfParser.parseVcfContent('''##fileformat=VCFv4.2
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
''');
    const evidence = DrugEvidence(
      genericName: 'AZITHROMYCIN',
      displayName: 'Azithromycin',
      guidelineCitation: 'No actionable PGx relationship found.',
      hasPgxRelationship: false,
      clinicallyActionable: false,
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'Azithromycin',
      parseResult: parsed,
      evidence: evidence,
    );

    expect(report.llmGeneratedExplanation.summary,
        contains('NO KNOWN PHARMACOGENOMIC RELATIONSHIP FOUND'));
    expect(report.evidence?.genericName, 'AZITHROMYCIN');
  });

  test('does not classify evidence-backed drugs without required clinical data', () {
    final parsed = VcfParser.parseVcfContent('''##fileformat=VCFv4.2
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSAMPLE
chr22\t1\trs3892097\tC\tT\t.\tPASS\tGENE=CYP2D6\tGT\t0/0
chr22\t2\trs1065852\tC\tT\t.\tPASS\tGENE=CYP2D6\tGT\t0/0
''');
    const evidence = DrugEvidence(
      genericName: 'CODEINE',
      displayName: 'Codeine',
      genes: ['CYP2D6'],
      requiredClinicalData: ['Trough Blood Level'],
      retrievalTimestamp: '2026-09-05T00:00:00Z',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'Codeine',
      parseResult: parsed,
      evidence: evidence,
    );

    expect(report.riskAssessment.riskLabel, 'Unknown');
    expect(report.llmGeneratedExplanation.summary,
        contains('REQUIRED CLINICAL DATA MISSING'));
  });
}
