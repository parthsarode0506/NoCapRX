import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/parser/vcf_parser.dart';
import 'package:ondevicerx/services/genomic_drug_scan_service.dart';
import 'package:ondevicerx/services/pgx_drug_rule_registry.dart';

void main() {
  test('evaluates every registered local PGx rule without uploading VCF', () {
    final parsed = VcfParser.parseVcfContent('''
##fileformat=VCFv4.2
##INFO=<ID=GENE,Number=1,Type=String,Description="Gene">
##INFO=<ID=STAR,Number=1,Type=String,Description="Star allele">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
1\t1\trs3892097\tA\tG\t.\tPASS\tGENE=CYP2D6;STAR=*4
''');

    final report = GenomicDrugScanService.scan(
      parseResult: parsed,
      vcfFilename: 'synthetic.vcf',
    );

    expect(report.drugReports.length, PgxDrugRuleRegistry.rules.length);
    expect(report.vcfFilename, 'synthetic.vcf');
    expect(
      report.drugReports.any((drug) => drug.drug == 'CODEINE'),
      isTrue,
    );
    expect(report.parseResult.geneProfiles['CYP2D6']!.variants, isNotEmpty);
  });
}
