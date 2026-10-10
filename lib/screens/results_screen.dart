import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_profile.dart';
import '../models/personalized_side_effect_risk.dart';
import '../models/pgx_report.dart';
import '../providers/app_providers.dart';
import '../services/pdf_export_service.dart';
import '../services/personalized_side_effect_engine.dart';
import '../services/universal_medicine_safety_engine.dart';
import '../theme/severity_style.dart';
import '../widgets/compliance_footer.dart';
import 'chatbot_screen.dart';

class ResultsScreen extends ConsumerWidget {
  final PgxMultiReport report;

  const ResultsScreen({super.key, required this.report});

  // Severity tokens now come from the canonical NoCapRx model so the UI
  // matches the pack's severity language and stays colour- and icon-safe.
  Color _getRiskColor(String riskLabel) =>
      SeverityStyle.fromRiskLabel(riskLabel).color;

  Color _getRiskBgColor(String riskLabel) =>
      SeverityStyle.fromRiskLabel(riskLabel).background;

  IconData _getRiskIcon(String riskLabel) =>
      SeverityStyle.fromRiskLabel(riskLabel).icon;

  _ReportCategory _categorize(PgxReport d) {
    final gene = d.pharmacogenomicProfile.primaryGene;
    final summary = d.llmGeneratedExplanation.summary;

    if (d.riskAssessment.riskLabel == 'Medicine not verified' ||
        summary.contains('MEDICINE NOT VERIFIED')) {
      return _ReportCategory.unknown;
    }

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final patientProfile = ref.watch(patientProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personalized Medicine Assessment'),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Summary Card with Patient & VCF Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient: ${report.patientId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'VCF File: ${report.vcfFilename}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
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
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Genomic privacy callout
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Genomic Privacy: VCF analysis executed strictly on this device CPU. Raw genetic data was never uploaded.',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Render Each Drug Evaluation
              ...report.drugReports.map(
                (drugReport) => _buildDrugAssessmentCard(
                  context,
                  ref,
                  drugReport,
                  patientProfile,
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
            MaterialPageRoute(builder: (_) => ChatbotScreen(report: report)),
          );
        },
        icon: const Icon(Icons.smart_toy_rounded),
        label: const Text('Report AI Chatbot'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildDrugAssessmentCard(
    BuildContext context,
    WidgetRef ref,
    PgxReport d,
    PatientProfile patientProfile,
  ) {
    final clinicalData = patientProfile.toClinicalDataMap();
    final clinicalFindings = UniversalMedicineSafetyEngine.evaluateAll(
      d.drug,
      clinicalData,
    );

    // Compute overall assessment status string
    final overallStatus = UniversalMedicineSafetyEngine.determineOverallStatus(
      pgxRiskLabel: d.riskAssessment.riskLabel,
      clinicalFindings: clinicalFindings,
      hasMissingData: d.riskAssessment.confidenceScore == 0.0,
    );

    final statusColor = _getRiskColor(overallStatus);
    final statusBgColor = _getRiskBgColor(overallStatus);
    final category = _categorize(d);
    final evidence = d.evidence;
    final personalizedSideEffects = evidence == null
        ? d.personalizedSideEffects
        : PersonalizedSideEffectEngine.evaluate(evidence, clinicalData);

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. OVERALL ASSESSMENT BANNER (Requirement 13)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusBgColor,
              border: Border(
                bottom: BorderSide(color: statusColor.withValues(alpha: 0.3)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.drug.toUpperCase(),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                          if (evidence != null &&
                              evidence.displayName.isNotEmpty)
                            Text(
                              evidence.displayName,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade800,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getRiskIcon(overallStatus),
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            overallStatus.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'OVERALL ASSESSMENT: $overallStatus',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Informational category banners (No-PGx, Insufficient data, etc.)
          if (category == _ReportCategory.noPgxRelationship)
            _buildInfoBanner(
              icon: Icons.info_outline,
              color: Colors.teal.shade800,
              bgColor: Colors.teal.shade50,
              title: 'NO ACTIONABLE PHARMACOGENOMIC RELATIONSHIP',
              body:
                  'No validated pharmacogenomic relationship was found for ${d.drug}. Genetic testing is not required for this drug. Assessment completed using clinical profile, allergies, and drug interactions.',
            ),
          if (category == _ReportCategory.insufficientData)
            _buildInfoBanner(
              icon: Icons.warning_amber_rounded,
              color: Colors.orange.shade800,
              bgColor: Colors.orange.shade50,
              title: 'INSUFFICIENT PATIENT DATA',
              body:
                  'This medicine has established pharmacogenomic evidence, but your uploaded VCF does not contain confirmed data for the relevant gene (${d.pharmacogenomicProfile.primaryGene}).',
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─────────────────────────────────────────────────────────
                // QUESTION 1: WHAT CAN THIS MEDICINE DO? (Requirement 29)
                // ─────────────────────────────────────────────────────────
                _buildSectionHeader(
                  title: 'About this medicine',
                  subtitle: 'What it is used for and what to watch for',
                  icon: Icons.medication,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),

                // Medicine identity & uses card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_outlined,
                            size: 18,
                            color: Colors.indigo,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              evidence?.displayName ?? d.drug,
                              softWrap: true,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (evidence?.verifiedMedicine == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Verified',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (evidence?.uses.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'What is it used for?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...evidence!.uses.map(
                          (use) => Text(
                            '• $use',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      if (evidence?.activeIngredients.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Active ingredient',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          evidence!.activeIngredients.join(', '),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      if (evidence?.precautions.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Important Precautions:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...evidence!.precautions.map(
                          (p) => Text(
                            '• $p',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                      if (evidence?.commonSideEffects.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Common side effects',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...evidence!.commonSideEffects.map(
                          (effect) => Text(
                            '• $effect',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      if (evidence?.seriousSideEffects.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Get medical help quickly for',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...evidence!.seriousSideEffects.map(
                          (effect) => Text(
                            '• $effect',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                      if (evidence != null &&
                          evidence.uses.isEmpty &&
                          evidence.commonSideEffects.isEmpty &&
                          evidence.seriousSideEffects.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Detailed uses and side effects were not verified for this brand. Ask a pharmacist before taking it.',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ─────────────────────────────────────────────────────────
                // QUESTION 2: HOW DOES THIS APPLY TO ME? (Requirement 29)
                // ─────────────────────────────────────────────────────────
                _buildSectionHeader(
                  title: 'Is it safe for me?',
                  subtitle: 'Your result in simple language',
                  icon: Icons.health_and_safety_outlined,
                  color: Colors.teal.shade800,
                ),
                const SizedBox(height: 12),

                // A. Patient Clinical Snapshot Card
                _buildSimpleSafetySummary(d, overallStatus),
                const SizedBox(height: 14),

                // D. PATIENT-SPECIFIC SIDE-EFFECT RISKS (Requirements 5, 6, 7, 8, 12, 15, 16)
                if (personalizedSideEffects.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.personal_injury_outlined,
                        size: 20,
                        color: Colors.deepOrange.shade800,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PATIENT-SPECIFIC SIDE-EFFECT RISKS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.deepOrange.shade900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...personalizedSideEffects.map(
                    (risk) => _buildPersonalizedSideEffectCard(risk),
                  ),
                  const SizedBox(height: 14),
                ],

                _buildAiExplanationCard(d),
                const SizedBox(height: 14),
                _buildProfessionalReviewBanner(overallStatus),
                const SizedBox(height: 14),
                _buildComplianceFooter(d),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalizedSideEffectCard(PersonalizedSideEffectRisk risk) {
    final isHigh =
        risk.relevance == 'HIGHER_CONCERN' ||
        risk.relevance == 'CRITICAL_CONCERN';
    final cardColor = isHigh ? Colors.red.shade700 : Colors.teal.shade700;
    final cardBg = isHigh ? Colors.red.shade50 : Colors.teal.shade50;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  risk.sideEffect,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: cardColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  risk.relevance.replaceAll('_', ' '),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'WHO MAY BE AT HIGHER RISK?',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: cardColor,
            ),
          ),
          const SizedBox(height: 2),
          ...risk.higherRiskGroups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text('• $g', style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'HOW DOES THIS APPLY TO YOU?',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: cardColor,
            ),
          ),
          const SizedBox(height: 2),
          if (risk.patientRiskFactors.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                '✓ No corresponding risk factor was identified from the information provided.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            )
          else
            ...risk.patientRiskFactors.map(
              (rf) => Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  '⚠ $rf',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cardColor,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            risk.explanation,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (risk.evidenceSources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Evidence: ${risk.evidenceSources.join("; ")}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleSafetySummary(PgxReport d, String overallStatus) {
    final isUnknown =
        overallStatus == 'Unknown' ||
        d.riskAssessment.riskLabel == 'Medicine not verified';
    final message = isUnknown
        ? 'There is not enough verified information to say this medicine is safe or unsafe for you.'
        : overallStatus == 'No major risk identified'
        ? 'No major risk was found from the information checked. This does not mean the medicine is completely risk-free.'
        : 'This medicine may need extra care for you. Discuss any change with your prescriber or pharmacist.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
    );
  }

  Widget _buildAiExplanationCard(PgxReport d) {
    final isAi = d.llmGeneratedExplanation.source == 'ai';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Colors.purple, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Simple explanation',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.purple,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isAi ? Colors.purple.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAi ? 'AI-simplified' : 'Template',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isAi ? Colors.purple : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            d.llmGeneratedExplanation.patientFriendly,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Why this result:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            d.llmGeneratedExplanation.mechanism,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              height: 1.35,
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

  Widget _buildProfessionalReviewBanner([String? overallStatus]) {
    final isHigh =
        overallStatus == 'High-risk finding' ||
        overallStatus == 'Contraindication identified';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHigh ? Colors.red.shade50 : Colors.orange.shade50,
        border: Border.all(
          color: isHigh ? Colors.red.shade300 : Colors.orange.shade300,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.medical_information_outlined,
            color: isHigh ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isHigh
                  ? 'HIGH-RISK FINDING: A factor associated with increased medication risk was identified for your profile. Review this with a qualified prescriber or pharmacist before changing anything.'
                  : 'IMPORTANT: This is a medication-safety decision-support assessment. Always discuss a medicine or dose change with a qualified prescriber or pharmacist.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isHigh ? Colors.red.shade900 : Colors.orange.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceFooter(PgxReport d) {
    final retrievedAt = d.clinicalRecommendation.evidenceRetrievedAt;
    return ComplianceFooter(
      cpicReference: d.clinicalRecommendation.cpicGuidelineCitation,
      snapshotDate: retrievedAt.isEmpty ? null : retrievedAt.split('T').first,
      aiSimplified: d.llmGeneratedExplanation.source == 'ai',
    );
  }

}

enum _ReportCategory { standard, noPgxRelationship, insufficientData, unknown }
