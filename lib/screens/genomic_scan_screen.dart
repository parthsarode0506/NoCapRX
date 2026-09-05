import 'package:flutter/material.dart';
import '../models/genomic_drug_scan_report.dart';
import '../models/pgx_report.dart';
import '../services/pdf_report_service.dart';

class GenomicScanScreen extends StatefulWidget {
  final GenomicDrugScanReport report;

  const GenomicScanScreen({super.key, required this.report});

  @override
  State<GenomicScanScreen> createState() => _GenomicScanScreenState();
}

class _GenomicScanScreenState extends State<GenomicScanScreen> {
  bool _isGeneratingPdf = false;

  GenomicDrugScanReport get report => widget.report;

  Future<void> _generatePdf() async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GENERATING PDF...')),
    );
    try {
      final file = await PdfReportService.generateGenomicDrugSafetyPdf(report);
      if (!await file.exists()) {
        throw StateError('PDF file was not created.');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('PDF GENERATED ✓'),
          content: const Text('Your pharmacogenomic report has been created.'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await PdfReportService.openPdf(file);
              },
              child: const Text('OPEN PDF'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await PdfReportService.sharePdf(file);
              },
              child: const Text('SHARE PDF'),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('PDF generation failed: $error\n$stackTrace');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('PDF GENERATION FAILED'),
          content: Text("We couldn't create the report.\n\n$error"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CLOSE'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _generatePdf();
              },
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionable = report.actionableReports;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Genomic Drug Safety Scan'),
        actions: [
          IconButton(
            tooltip: 'Generate PDF report',
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            onPressed: _isGeneratingPdf ? null : _generatePdf,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('GENOMIC DRUG SCAN COMPLETE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('VCF: ${report.vcfFilename}'),
                  Text('Genes analyzed: ${report.parseResult.geneProfiles.length}'),
                  Text('Validated PGx rules evaluated: ${report.drugReports.length}'),
                  Text('Actionable findings: ${actionable.length}'),
                  Text('Variants matched: ${report.parseResult.qualityMetrics.variantsDetected}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (actionable.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No actionable PGx findings were identified using the available validated rules. '
                  'This does not mean every medicine is safe.',
                ),
              ),
            ),
          ...actionable.map((drug) => Card(
                child: ListTile(
                  leading: Icon(
                    drug.riskAssessment.riskLabel == 'Adjust Dosage'
                        ? Icons.warning_amber
                        : Icons.error_outline,
                    color: drug.riskAssessment.riskLabel == 'Adjust Dosage'
                        ? Colors.orange
                        : Colors.red,
                  ),
                  title: Text(drug.drug),
                  subtitle: Text(
                    '${drug.pharmacogenomicProfile.primaryGene} • '
                    '${drug.pharmacogenomicProfile.diplotype} • '
                    '${drug.pharmacogenomicProfile.phenotype}\n'
                    '${drug.riskAssessment.riskLabel}: '
                    '${drug.clinicalRecommendation.dosingRecommendation}',
                  ),
                  isThreeLine: true,
                  onTap: () => _showWhy(context, drug),
                ),
              )),
          const SizedBox(height: 16),
          const Text('COMPLETE GENOMIC PROFILE',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ...report.parseResult.geneProfiles.values.map(
            (gene) => ListTile(
              dense: true,
              title: Text(gene.gene),
              subtitle: Text(
                'Variants: ${gene.variants.isEmpty ? 'Not detected / not available in VCF' : gene.variants.map((v) => v.rsid).join(', ')}\n'
                'Diplotype: ${gene.diplotype} • Phenotype: ${gene.phenotype}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'This is pharmacogenomic decision support, not a diagnosis or prescription. '
            'Discuss actionable findings with a qualified clinician.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showWhy(BuildContext context, PgxReport drug) {
    final profile = drug.pharmacogenomicProfile;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: ListView(shrinkWrap: true, children: [
          Text('Why ${drug.drug} needs review', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text('Gene: ${profile.primaryGene}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('What was found? ${profile.phenotype} phenotype (${profile.diplotype}).'),
          const SizedBox(height: 8),
          Text('What does it mean? ${drug.clinicalRecommendation.dosingRecommendation}'),
          const SizedBox(height: 8),
          Text('What should I know? ${drug.clinicalRecommendation.monitoringAdvice}'),
          const SizedBox(height: 8),
          Text('Evidence: ${drug.clinicalRecommendation.cpicGuidelineCitation}'),
          const SizedBox(height: 16),
          const Text('This is decision support. Discuss medication decisions with a qualified healthcare professional.', style: TextStyle(color: Colors.grey)),
        ]),
      ),
    );
  }
}
