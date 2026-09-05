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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${d.drug} (${d.pharmacogenomicProfile.primaryGene})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      'Phenotype: ${d.pharmacogenomicProfile.phenotype} (${d.pharmacogenomicProfile.diplotype})',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    d.riskAssessment.riskLabel.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
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
}
