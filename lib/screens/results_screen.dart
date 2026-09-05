import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pgx_report.dart';
import '../providers/app_providers.dart';
import '../services/pdf_export_service.dart';
import 'chatbot_screen.dart';

class ResultsScreen extends ConsumerWidget {
  final PgxMultiReport report;

  const ResultsScreen({super.key, required this.report});

  Color _getRiskColor(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
        return Colors.green.shade700;
      case 'Adjust Dosage':
        return Colors.amber.shade800;
      case 'Toxic':
      case 'Ineffective':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Color _getRiskBgColor(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
        return Colors.green.shade50;
      case 'Adjust Dosage':
        return Colors.amber.shade50;
      case 'Toxic':
      case 'Ineffective':
        return Colors.red.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  IconData _getRiskIcon(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
        return Icons.check_circle;
      case 'Adjust Dosage':
        return Icons.tune;
      case 'Toxic':
        return Icons.dangerous;
      case 'Ineffective':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  /// Detect if this report is a "No PGx Relationship" or "Insufficient Patient Data" result.
  _ReportCategory _categorize(PgxReport d) {
    final gene = d.pharmacogenomicProfile.primaryGene;
    final summary = d.llmGeneratedExplanation.summary;

    if (summary.contains('INSUFFICIENT PATIENT DATA') ||
        summary.contains('REQUIRED CLINICAL DATA MISSING') ||
        (gene != 'UNMAPPED' &&
            gene != 'NON-PGX' &&
            d.riskAssessment.confidenceScore == 0.0 &&
            d.pharmacogenomicProfile.phenotype == 'Unknown')) {
      return _ReportCategory.insufficientData;
    }
    if (gene == 'NON-PGX' ||
        summary.contains('NO KNOWN PHARMACOGENOMIC RELATIONSHIP') ||
        summary.contains('NO ACTIONABLE PGX FINDING')) {
      return _ReportCategory.noPgxRelationship;
    }
    if (gene == 'UNMAPPED') {
      return _ReportCategory.unknown;
    }
    return _ReportCategory.standard;
  }

  void _showRawJsonBottomSheet(BuildContext context) {
    final jsonStr = report.toFormattedJson();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Raw JSON Output Contract',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.blueAccent),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: jsonStr));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Raw JSON copied to clipboard!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: SelectableText(
                        jsonStr,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isClinicianView = ref.watch(isClinicianViewProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Risk Prediction Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF Report',
            onPressed: () => PdfExportService.sharePdfReport(report),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Print / Export PDF',
            onPressed: () => PdfExportService.printPdfReport(report),
          ),
          IconButton(
            icon: const Icon(Icons.data_object_outlined),
            tooltip: 'Share derived JSON report',
            onPressed: () => PdfExportService.shareJsonReport(report),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient: ${report.patientId}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'VCF File: ${report.vcfFilename}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${report.drugReports.length} Drug(s) Evaluated',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          report.timestamp.split('T').first,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(child: Text('Genomic privacy: VCF processing stayed on this device. Raw VCF uploaded: 0 KB. This prototype is decision support and does not replace a clinician, pharmacist, or prescribing information.', style: TextStyle(fontSize: 12))),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // View Mode Toggle (Patient-friendly vs Clinician note)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Language Perspective',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Patient')),
                      ButtonSegment(value: true, label: Text('Clinician')),
                    ],
                    selected: {isClinicianView},
                    onSelectionChanged: (val) {
                      ref.read(isClinicianViewProvider.notifier).state = val.first;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Drug Result Cards List
              ...report.drugReports.map((drugReport) => _buildDrugResultCard(context, ref, drugReport, isClinicianView)),

              const SizedBox(height: 20),

              // View Raw JSON CTA Button
              OutlinedButton.icon(
                onPressed: () => _showRawJsonBottomSheet(context),
                icon: const Icon(Icons.code),
                label: const Text('View Raw Hackathon JSON Output Contract'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatbotScreen(report: report),
            ),
          );
        },
        icon: const Icon(Icons.smart_toy_rounded),
        label: const Text('Report AI Chatbot'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildDrugResultCard(BuildContext context, WidgetRef ref, PgxReport d, bool isClinicianView) {
    final color = _getRiskColor(d.riskAssessment.riskLabel);
    final bgColor = _getRiskBgColor(d.riskAssessment.riskLabel);
    final category = _categorize(d);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Column(
        children: [
          // Color-coded Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.drug,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          if (d.pharmacogenomicProfile.primaryGene != 'NON-PGX' &&
                              d.pharmacogenomicProfile.primaryGene != 'UNMAPPED')
                            Text(
                              '${d.pharmacogenomicProfile.primaryGene} • ${d.pharmacogenomicProfile.phenotype} (${d.pharmacogenomicProfile.diplotype})',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getRiskIcon(d.riskAssessment.riskLabel),
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                d.riskAssessment.riskLabel.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (d.riskAssessment.confidenceScore > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${(d.riskAssessment.confidenceScore * 100).toInt()}% confidence',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Special badge for non-PGx, insufficient data, or online-discovered
          if (category == _ReportCategory.noPgxRelationship)
            _buildInfoBanner(
              icon: Icons.info_outline,
              color: Colors.teal,
              bgColor: Colors.teal.shade50,
              title: 'NO KNOWN PHARMACOGENOMIC RELATIONSHIP',
              body: 'PharmaGuard found no validated pharmacogenomic relationship that allows a genetic safety assessment for this medicine. This does NOT mean the medicine is universally safe or unsafe.',
            ),
          if (category == _ReportCategory.insufficientData)
            _buildInfoBanner(
              icon: Icons.warning_amber_rounded,
              color: Colors.orange.shade800,
              bgColor: Colors.orange.shade50,
              title: d.llmGeneratedExplanation.summary.contains('REQUIRED CLINICAL DATA')
                  ? 'ASSESSMENT INCOMPLETE — PATIENT DATA REQUIRED'
                  : 'UNKNOWN — INSUFFICIENT PATIENT DATA',
              body: d.llmGeneratedExplanation.summary.contains('REQUIRED CLINICAL DATA')
                  ? d.clinicalRecommendation.dosingRecommendation
                  : 'This medicine has known pharmacogenomic evidence, but the patient\'s uploaded VCF does not contain enough data for the relevant gene to determine phenotype.',
            ),
          if (category == _ReportCategory.unknown)
            _buildInfoBanner(
              icon: Icons.help_outline,
              color: Colors.grey.shade700,
              bgColor: Colors.grey.shade100,
              title: 'UNKNOWN — UNRECOGNIZED DRUG',
              body: 'PharmaGuard was unable to locate validated pharmacogenomic evidence for this drug in local databases or online sources.',
            ),

          // Online Evidence Badge
          if (_isOnlineDiscovered(d))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.blue.shade200, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_done_outlined, color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '🌐 ONLINE EVIDENCE  ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                              fontSize: 11,
                            ),
                          ),
                          TextSpan(
                            text: 'Source: ${d.clinicalRecommendation.cpicGuidelineCitation.length > 60 ? '${d.clinicalRecommendation.cpicGuidelineCitation.substring(0, 60)}...' : d.clinicalRecommendation.cpicGuidelineCitation}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Card Body Accordion Sections
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Section 1: LLM Explanation
                ExpansionTile(
                  leading: const Icon(Icons.psychology, color: Colors.purple),
                  title: const Text('LLM Explanation', style: TextStyle(fontWeight: FontWeight.bold)),
                  initiallyExpanded: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isClinicianView ? 'Clinician Note:' : 'Patient Summary:',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isClinicianView
                                ? d.llmGeneratedExplanation.clinicianNote
                                : d.llmGeneratedExplanation.patientFriendly,
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Molecular Mechanism:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            d.llmGeneratedExplanation.mechanism,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Section 2: Clinical Recommendation
                ExpansionTile(
                  leading: const Icon(Icons.local_hospital, color: Colors.blue),
                  title: const Text('Clinical Recommendation', style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dosing: ${d.clinicalRecommendation.dosingRecommendation}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          if (d.clinicalRecommendation.alternativeDrugs.isNotEmpty)
                            Text('Alternative Drugs: ${d.clinicalRecommendation.alternativeDrugs.join(', ')}', style: const TextStyle(fontSize: 13, color: Colors.blue)),
                          const SizedBox(height: 6),
                          Text('Monitoring: ${d.clinicalRecommendation.monitoringAdvice}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 6),
                          Text('CPIC Citation: ${d.clinicalRecommendation.cpicGuidelineCitation}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),

                // Section 3: Pharmacogenomic Profile & Detected Variants
                if (category == _ReportCategory.standard ||
                    category == _ReportCategory.insufficientData)
                  ExpansionTile(
                    leading: const Icon(Icons.dns, color: Colors.teal),
                    title: const Text('Detected Variants & Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Primary Gene: ${d.pharmacogenomicProfile.primaryGene}'),
                            Text('Diplotype Call: ${d.pharmacogenomicProfile.diplotype}'),
                            Text('Phenotype Class: ${d.pharmacogenomicProfile.phenotype}'),
                            const SizedBox(height: 8),
                            const Text('Detected rsIDs:', style: TextStyle(fontWeight: FontWeight.bold)),
                            if (d.pharmacogenomicProfile.detectedVariants.isEmpty)
                              const Text('No specific variant rsIDs listed (wildtype/inferred)', style: TextStyle(fontSize: 12, color: Colors.grey))
                            else
                              Wrap(
                                spacing: 6,
                                children: d.pharmacogenomicProfile.detectedVariants
                                    .map((v) => Chip(label: Text(v.rsid, style: const TextStyle(fontSize: 11))))
                                    .toList(),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                // Evidence Chain — always visible
                ExpansionTile(
                  leading: const Icon(Icons.account_tree_outlined, color: Colors.indigo),
                  title: const Text('Evidence Chain', style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildEvidenceChain(d, category),
                    ),
                  ],
                ),

                // Section 4: Quality Metrics
                ExpansionTile(
                  leading: const Icon(Icons.verified, color: Colors.orange),
                  title: const Text('Quality Metrics & Confidence', style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Confidence Score: ${(d.riskAssessment.confidenceScore * 100).toInt()}%'),
                          Text('VCF Parsing Success: ${d.qualityMetrics.vcfParsingSuccess}'),
                          Text('Diplotype Inferred: ${d.qualityMetrics.diplotypeInferred}'),
                          Text('Annotation Completeness: ${(d.qualityMetrics.annotationCompleteness * 100).toInt()}%'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(fontSize: 11, color: color, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceChain(PgxReport d, _ReportCategory category) {
    if (category == _ReportCategory.noPgxRelationship) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chainStep('💊', 'Drug', d.drug),
          _chainArrow(),
          _chainStep('🔍', 'Database Search', 'CPIC / PharmGKB / FDA'),
          _chainArrow(),
          _chainStep('📋', 'Result', 'No validated PGx relationship found'),
          _chainArrow(),
          _chainStep('⚖️', 'Classification', 'No pharmacogenomic assessment possible'),
        ],
      );
    }

    if (category == _ReportCategory.insufficientData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chainStep('💊', 'Drug', d.drug),
          _chainArrow(),
          _chainStep('🧬', 'Required Gene', d.pharmacogenomicProfile.primaryGene),
          _chainArrow(),
          _chainStep('📂', 'Patient VCF', 'Insufficient data for ${d.pharmacogenomicProfile.primaryGene}'),
          _chainArrow(),
          _chainStep('⚠️', 'Classification', 'Unknown — cannot determine phenotype'),
        ],
      );
    }

    // Standard evidence chain
    final variants = d.pharmacogenomicProfile.detectedVariants.isEmpty
        ? 'no callable variant'
        : d.pharmacogenomicProfile.detectedVariants.map((v) => v.rsid).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chainStep('📂', 'VCF Parsed', variants),
        _chainArrow(),
        _chainStep('🧬', 'Gene', d.pharmacogenomicProfile.primaryGene),
        _chainArrow(),
        _chainStep('🔬', 'Diplotype', d.pharmacogenomicProfile.diplotype),
        _chainArrow(),
        _chainStep('📊', 'Phenotype', d.pharmacogenomicProfile.phenotype),
        _chainArrow(),
        _chainStep('💊', 'Drug', d.drug),
        _chainArrow(),
        _chainStep('📚', 'Guideline', d.clinicalRecommendation.cpicGuidelineCitation.length > 50
            ? '${d.clinicalRecommendation.cpicGuidelineCitation.substring(0, 50)}...'
            : d.clinicalRecommendation.cpicGuidelineCitation),
        _chainArrow(),
        _chainStep('⚖️', 'Risk', d.riskAssessment.riskLabel),
      ],
    );
  }

  Widget _chainStep(String emoji, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  Widget _chainArrow() {
    return const Padding(
      padding: EdgeInsets.only(left: 6, top: 2, bottom: 2),
      child: Text('  ↓', style: TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }

  bool _isOnlineDiscovered(PgxReport d) {
    if (d.evidence != null) {
      return d.evidence!.isOnlineDiscovered;
    }

    // Heuristic: if the citation mentions "FDA" or "PharmGKB" or "Online" and the gene is not
    // from the core 6-drug panel, mark as online-discovered
    final coreDrugs = {'CODEINE', 'CLOPIDOGREL', 'WARFARIN', 'SIMVASTATIN', 'AZATHIOPRINE', 'FLUOROURACIL'};
    final gene = d.pharmacogenomicProfile.primaryGene;
    final drug = d.drug.toUpperCase();

    if (coreDrugs.contains(drug)) return false;
    if (gene == 'NON-PGX' || gene == 'UNMAPPED') {
      // These are non-PGx or unknown drugs, check if evidence was found
      return d.clinicalRecommendation.cpicGuidelineCitation.contains('FDA') ||
          d.clinicalRecommendation.cpicGuidelineCitation.contains('PharmGKB');
    }
    // If it's a gene not in the core panel or a drug not in the core panel
    return !coreDrugs.contains(drug);
  }
}

enum _ReportCategory {
  standard,
  noPgxRelationship,
  insufficientData,
  unknown,
}
