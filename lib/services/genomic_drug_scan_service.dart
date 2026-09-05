import '../models/genomic_drug_scan_report.dart';
import '../parser/vcf_parser.dart';
import '../rules_engine/cpic_rule_engine.dart';
import 'pgx_drug_rule_registry.dart';

class GenomicDrugScanService {
  static GenomicDrugScanReport scan({
    required VcfParseResult parseResult,
    required String vcfFilename,
  }) {
    final reports = PgxDrugRuleRegistry.rules
        .map(
          (rule) => CpicRuleEngine.evaluateDrug(
            drugName: rule.drug,
            parseResult: parseResult,
          ),
        )
        .toList(growable: false);

    return GenomicDrugScanReport(
      reportId: 'GENOMIC_${DateTime.now().millisecondsSinceEpoch}',
      patientId: parseResult.patientId,
      vcfFilename: vcfFilename,
      timestamp: DateTime.now().toIso8601String(),
      parseResult: parseResult,
      drugReports: reports,
    );
  }
}
