import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/pgx_report.dart';
import '../providers/app_providers.dart';
import '../services/pdf_export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/security_cards.dart';
import 'chatbot_screen.dart';

class ResultsScreen extends ConsumerWidget {
  final PgxMultiReport report;

  const ResultsScreen({super.key, required this.report});

  Color _getRiskColor(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
        return AppTheme.safeGreen;
      case 'Adjust Dosage':
        return AppTheme.warningAmber;
      case 'Toxic':
      case 'Ineffective':
        return AppTheme.dangerRed;
      default:
        return AppTheme.unknownSlate;
    }
  }

  Color _getRiskBgColor(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
        return AppTheme.safeGreenBg;
      case 'Adjust Dosage':
        return AppTheme.warningAmberBg;
      case 'Toxic':
      case 'Ineffective':
        return AppTheme.dangerRedBg;
      default:
        return AppTheme.unknownSlateBg;
    }
  }

  IconData _getRiskIcon(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
        return Icons.check_circle_rounded;
      case 'Adjust Dosage':
        return Icons.tune_rounded;
      case 'Toxic':
        return Icons.dangerous_rounded;
      case 'Ineffective':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

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
      backgroundColor: const Color(0xFF121C18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'JSON Output Contract',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: AppTheme.vibrantMint),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: jsonStr));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Report JSON copied to clipboard!'),
                              backgroundColor: AppTheme.safeGreen,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF263D34)),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: SelectableText(
                        jsonStr,
                        style: const TextStyle(
                          color: Color(0xFF6EE7B7),
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
    final isClinicianView = ref.watch(isClinicianViewProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Text(
          'Risk Assessment Results',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: AppTheme.deepInk,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share PDF Report',
            onPressed: () => PdfExportService.sharePdfReport(report),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Print / Export PDF',
            onPressed: () => PdfExportService.printPdfReport(report),
          ),
          IconButton(
            icon: const Icon(Icons.data_object_rounded),
            tooltip: 'Share JSON report',
            onPressed: () => PdfExportService.shareJsonReport(report),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Summary Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient: ${report.patientId}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppTheme.deepInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'VCF: ${report.vcfFilename}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.secondaryInk,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.lightEmeraldPill,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${report.drugReports.length} Drug(s) Evaluated',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryDarkEmerald,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          report.timestamp.split('T').first,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.mutedGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // On-Device Privacy Banner
              const OnDevicePrivacyMicroCard(),
              const SizedBox(height: 16),

              // View Mode Toggle (Patient vs Clinician)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Language Perspective',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: AppTheme.deepInk,
                    ),
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
              ...report.drugReports.map(
                (drugReport) => _buildDrugResultCard(
                  context,
                  ref,
                  drugReport,
                  isClinicianView,
                ),
              ),

              const SizedBox(height: 14),

              // View Raw JSON CTA Button
              OutlinedButton.icon(
                onPressed: () => _showRawJsonBottomSheet(context),
                icon: const Icon(Icons.code_rounded, size: 18),
                label: const Text('View Raw JSON Output Contract'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 80),
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
        icon: const Icon(Icons.smart_toy_outlined),
        label: Text(
          'Report AI Assistant',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppTheme.primaryEmerald,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildDrugResultCard(
    BuildContext context,
    WidgetRef ref,
    PgxReport d,
    bool isClinicianView,
  ) {
    final color = _getRiskColor(d.riskAssessment.riskLabel);
    final bgColor = _getRiskBgColor(d.riskAssessment.riskLabel);
    final category = _categorize(d);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Color-coded Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.25), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.drug,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: color,
                        ),
                      ),
                      if (d.pharmacogenomicProfile.primaryGene != 'NON-PGX' &&
                          d.pharmacogenomicProfile.primaryGene != 'UNMAPPED')
                        Text(
                          '${d.pharmacogenomicProfile.primaryGene} • ${d.pharmacogenomicProfile.phenotype} (${d.pharmacogenomicProfile.diplotype})',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.deepInk,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getRiskIcon(d.riskAssessment.riskLabel),
                              color: Colors.white, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            d.riskAssessment.riskLabel.toUpperCase(),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (d.riskAssessment.confidenceScore > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${(d.riskAssessment.confidenceScore * 100).toInt()}% confidence',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: AppTheme.secondaryInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Informational Banner for edge cases
          if (category == _ReportCategory.noPgxRelationship)
            _buildInfoBanner(
              icon: Icons.info_outline,
              color: AppTheme.primaryEmerald,
              bgColor: AppTheme.mintSurface,
              title: 'NO KNOWN PHARMACOGENOMIC RELATIONSHIP',
              body:
                  'No validated pharmacogenomic relationship exists to determine a genetic risk for this medicine.',
            ),
          if (category == _ReportCategory.insufficientData)
            _buildInfoBanner(
              icon: Icons.warning_amber_rounded,
              color: AppTheme.warningAmber,
              bgColor: AppTheme.warningAmberBg,
              title: d.llmGeneratedExplanation.summary.contains('REQUIRED CLINICAL DATA')
                  ? 'PATIENT CLINICAL DATA REQUIRED'
                  : 'UNKNOWN — INSUFFICIENT PATIENT DATA',
              body: d.llmGeneratedExplanation.summary.contains('REQUIRED CLINICAL DATA')
                  ? d.clinicalRecommendation.dosingRecommendation
                  : 'The uploaded VCF does not contain sufficient data for ${d.pharmacogenomicProfile.primaryGene}.',
            ),
          if (category == _ReportCategory.unknown)
            _buildInfoBanner(
              icon: Icons.help_outline_rounded,
              color: AppTheme.unknownSlate,
              bgColor: AppTheme.unknownSlateBg,
              title: 'UNKNOWN — UNRECOGNIZED DRUG',
              body: 'No validated pharmacogenomic evidence found in CPIC or FDA databases.',
            ),

          // Card Body Accordion Sections
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Section 1: LLM Explanation
                ExpansionTile(
                  leading: const Icon(Icons.psychology_outlined, color: AppTheme.primaryEmerald),
                  title: Text(
                    'Clinical Explanation',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  initiallyExpanded: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isClinicianView ? 'Clinician Note:' : 'Patient Summary:',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isClinicianView
                                ? d.llmGeneratedExplanation.clinicianNote
                                : d.llmGeneratedExplanation.patientFriendly,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.4,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Molecular Mechanism:',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            d.llmGeneratedExplanation.mechanism,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.secondaryInk,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Section 2: Clinical Recommendation
                ExpansionTile(
                  leading: const Icon(Icons.local_hospital_outlined, color: AppTheme.accentEmerald),
                  title: Text(
                    'Clinical Recommendation',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dosing: ${d.clinicalRecommendation.dosingRecommendation}',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 6),
                          if (d.clinicalRecommendation.alternativeDrugs.isNotEmpty)
                            Text(
                              'Alternative Drugs: ${d.clinicalRecommendation.alternativeDrugs.join(', ')}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.primaryEmerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            'Monitoring: ${d.clinicalRecommendation.monitoringAdvice}',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.secondaryInk),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'CPIC Citation: ${d.clinicalRecommendation.cpicGuidelineCitation}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppTheme.mutedGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Section 3: Evidence Chain
                ExpansionTile(
                  leading: const Icon(Icons.account_tree_outlined, color: AppTheme.primaryDarkEmerald),
                  title: Text(
                    'Evidence Chain',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildEvidenceChain(d, category),
                    ),
                  ],
                ),

                // Section 4: Quality Metrics
                ExpansionTile(
                  leading: const Icon(Icons.verified_outlined, color: AppTheme.safeGreen),
                  title: Text(
                    'Quality & Transparency Metrics',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMetricRow('Confidence Score', '${(d.riskAssessment.confidenceScore * 100).toInt()}%'),
                          _buildMetricRow('VCF Parsing Success', '${d.qualityMetrics.vcfParsingSuccess}'),
                          _buildMetricRow('Diplotype Inferred', '${d.qualityMetrics.diplotypeInferred}'),
                          _buildMetricRow('Annotation Completeness', '${(d.qualityMetrics.annotationCompleteness * 100).toInt()}%'),
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

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.secondaryInk)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.deepInk)),
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
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.inter(fontSize: 11, color: color, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceChain(PgxReport d, _ReportCategory category) {
    final variants = d.pharmacogenomicProfile.detectedVariants.isEmpty
        ? 'Wildtype / Inferred reference'
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
        _chainStep(
          '📚',
          'Guideline',
          d.clinicalRecommendation.cpicGuidelineCitation.length > 50
              ? '${d.clinicalRecommendation.cpicGuidelineCitation.substring(0, 50)}...'
              : d.clinicalRecommendation.cpicGuidelineCitation,
        ),
        _chainArrow(),
        _chainStep('⚖️', 'Risk', d.riskAssessment.riskLabel),
      ],
    );
  }

  Widget _chainStep(String emoji, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: AppTheme.deepInk,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.secondaryInk),
          ),
        ),
      ],
    );
  }

  Widget _chainArrow() {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 1, bottom: 1),
      child: Text(
        '  ↓',
        style: GoogleFonts.inter(
          fontSize: 11,
          color: AppTheme.accentEmerald,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

enum _ReportCategory {
  standard,
  noPgxRelationship,
  insufficientData,
  unknown,
}
