import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/parser/vcf_parser.dart';
import 'package:ondevicerx/rules_engine/cpic_rule_engine.dart';

void main() {
  const vcfHeader = '''##fileformat=VCFv4.2
##INFO=<ID=GENE,Number=1,Type=String,Description="Gene Symbol">
##INFO=<ID=STAR,Number=1,Type=String,Description="Star Allele">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
''';

  test('does not call a drug Safe when its pharmacogene is absent', () {
    final parsed = VcfParser.parseVcfContent(vcfHeader);
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'warfarin',
      parseResult: parsed,
    );

    expect(report.riskAssessment.riskLabel, 'Unknown');
    expect(report.pharmacogenomicProfile.phenotype, 'Unknown');
  });

  test('uses the detected poor-metabolizer CYP2D6 call for a brand alias', () {
    final parsed = VcfParser.parseVcfContent(
      '${vcfHeader}chr22\t1\trs1\tA\tG\t.\tPASS\tGENE=CYP2D6;STAR=*4\n'
      'chr22\t2\trs2\tA\tG\t.\tPASS\tGENE=CYP2D6;STAR=*4\n',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'Tylenol #3',
      parseResult: parsed,
    );

    expect(report.drug, 'CODEINE');
    expect(report.pharmacogenomicProfile.phenotype, 'PM');
    expect(report.riskAssessment.riskLabel, 'Ineffective');
  });

  test('reads an explicit diplotype from one VCF record', () {
    final parsed = VcfParser.parseVcfContent(
      '${vcfHeader}chr22\t1\trs1\tA\tG\t.\tPASS\tGENE=CYP2D6;STAR=*4/*4\n',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'codeine',
      parseResult: parsed,
    );

    expect(report.pharmacogenomicProfile.diplotype, '*4/*4');
    expect(report.pharmacogenomicProfile.phenotype, 'PM');
    expect(report.riskAssessment.riskLabel, 'Ineffective');
  });

  test('does not treat raw FORMAT GT calls as normal metabolism', () {
    final parsed = VcfParser.parseVcfContent(
      '${vcfHeader}chr22\t1\trs1\tA\tG\t.\tPASS\tGENE=CYP2D6\tGT\t1/1\n',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'codeine',
      parseResult: parsed,
    );

    expect(report.riskAssessment.riskLabel, 'Unknown');
    expect(report.pharmacogenomicProfile.phenotype, 'Unknown');
  });

  test('maps a validated rsID and FORMAT GT to a poor-metabolizer call', () {
    final parsed = VcfParser.parseVcfContent(
      '''##fileformat=VCFv4.2
##INFO=<ID=GENE,Number=1,Type=String,Description="Gene Symbol">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSAMPLE
chr22\t1\trs3892097\tA\tG\t.\tPASS\tGENE=CYP2D6\tGT\t1/1
''',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'codeine',
      parseResult: parsed,
    );

    expect(report.pharmacogenomicProfile.diplotype, '*4/*4');
    expect(report.riskAssessment.riskLabel, 'Ineffective');
  });

  test('maps validated reference genotypes to a normal-metabolizer call', () {
    final parsed = VcfParser.parseVcfContent(
      '''##fileformat=VCFv4.2
##INFO=<ID=GENE,Number=1,Type=String,Description="Gene Symbol">
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSAMPLE
chr22\t1\trs3892097\tC\tT\t.\tPASS\tGENE=CYP2D6\tGT\t0/0
chr22\t2\trs1065852\tC\tT\t.\tPASS\tGENE=CYP2D6\tGT\t0/0
''',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'codeine',
      parseResult: parsed,
    );

    expect(report.pharmacogenomicProfile.diplotype, '*1/*1');
    expect(report.pharmacogenomicProfile.phenotype, 'NM');
    expect(report.riskAssessment.riskLabel, 'Safe');
  });

  test('finds a supported gene from a validated rsID without GENE INFO', () {
    final parsed = VcfParser.parseVcfContent(
      '''##fileformat=VCFv4.2
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSAMPLE
10\t1\trs4244285\tG\tA\t.\tPASS\t.\tGT\t1/1
''',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'Plavix',
      parseResult: parsed,
    );
    expect(report.pharmacogenomicProfile.primaryGene, 'CYP2C19');
    expect(report.riskAssessment.riskLabel, 'Ineffective');
  });

  test('does not issue a warfarin risk label from CYP2C9 alone', () {
    final parsed = VcfParser.parseVcfContent(
      '${vcfHeader}10\t1\trs1057910\tA\tG\t.\tPASS\tGENE=CYP2C9\tGT\t0/1\n',
    );
    final report = CpicRuleEngine.evaluateDrug(
      drugName: 'warfarin',
      parseResult: parsed,
    );
    expect(report.riskAssessment.riskLabel, 'Unknown');
    expect(report.clinicalRecommendation.dosingRecommendation, contains('Do not derive'));
  });

  test('rejects an empty VCF', () {
    expect(() => VcfParser.parseVcfContent('  '), throwsA(isA<VcfParseException>()));
  });
}
