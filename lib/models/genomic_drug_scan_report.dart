import 'pgx_report.dart';
import '../parser/vcf_parser.dart';

class GenomicDrugScanReport {
  final String reportId;
  final String patientId;
  final String vcfFilename;
  final String timestamp;
  final VcfParseResult parseResult;
  final List<PgxReport> drugReports;

  const GenomicDrugScanReport({
    required this.reportId,
    required this.patientId,
    required this.vcfFilename,
    required this.timestamp,
    required this.parseResult,
    required this.drugReports,
  });

  List<PgxReport> get actionableReports => drugReports
      .where((report) => report.riskAssessment.riskLabel != 'Safe')
      .toList();

  Map<String, dynamic> toJson() => {
        'report_id': reportId,
        'patient_id': patientId,
        'vcf_filename': vcfFilename,
        'timestamp': timestamp,
        'quality_metrics': parseResult.qualityMetrics.toJson(),
        'drug_reports': drugReports.map((report) => report.toJson()).toList(),
      };
}
