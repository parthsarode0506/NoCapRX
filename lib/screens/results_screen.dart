import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_profile.dart';
import '../models/personalized_side_effect_risk.dart';
import '../models/pgx_report.dart';
import '../providers/app_providers.dart';
import '../services/pdf_export_service.dart';
import '../services/personalized_side_effect_engine.dart';
import '../services/universal_medicine_safety_engine.dart';
import 'chatbot_screen.dart';
import 'patient_profile_screen.dart';

class ResultsScreen extends ConsumerWidget {
  final PgxMultiReport report;

  const ResultsScreen({super.key, required this.report});

  Color _getRiskColor(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
      case 'No major risk identified':
        return Colors.green.shade700;
      case 'Adjust Dosage':
      case 'Use with caution':
        return Colors.amber.shade800;
      case 'Additional medical review required':
        return Colors.orange.shade800;
      case 'Toxic':
      case 'Ineffective':
      case 'High-risk finding':
      case 'CONTRAINDICATED':
      case 'Contraindication identified':
      case 'DRUG_INTERACTION_DETECTED':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Color _getRiskBgColor(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
      case 'No major risk identified':
        return Colors.green.shade50;
      case 'Adjust Dosage':
      case 'Use with caution':
        return Colors.amber.shade50;
      case 'Additional medical review required':
        return Colors.orange.shade50;
      case 'Toxic':
      case 'Ineffective':
      case 'High-risk finding':
      case 'CONTRAINDICATED':
      case 'Contraindication identified':
      case 'DRUG_INTERACTION_DETECTED':
        return Colors.red.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  IconData _getRiskIcon(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
      case 'No major risk identified':
        return Icons.check_circle;
      case 'Adjust Dosage':
      case 'Use with caution':
        return Icons.tune;
      case 'Additional medical review required':
        return Icons.help_outline;
      case 'Toxic':
      case 'High-risk finding':
      case 'CONTRAINDICATED':
      case 'Contraindication identified':
      case 'DRUG_INTERACTION_DETECTED':
        return Icons.dangerous;
      case 'Ineffective':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

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

  void _showRawJsonBottomSheet(BuildContext context) {
    final jsonStr = report.toFormattedJson();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Derived JSON (Hackathon Contract)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.white70),
                        tooltip: 'Copy JSON',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: jsonStr));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('JSON copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller,
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'VCF File: ${report.vcfFilename}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
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
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
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
              ...report.drugReports.map((drugReport) => _buildDrugAssessmentCard(
                    context,
                    ref,
                    drugReport,
                    patientProfile,
                  )),
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

  Widget _buildDrugAssessmentCard(
    BuildContext context,
    WidgetRef ref,
    PgxReport d,
    PatientProfile patientProfile,
  ) {
    final clinicalData = patientProfile.toClinicalDataMap();
    final clinicalFindings = UniversalMedicineSafetyEngine.evaluateAll(d.drug, clinicalData);

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
              border: Border(bottom: BorderSide(color: statusColor.withValues(alpha: 0.3))),
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
                          if (evidence != null && evidence.displayName.isNotEmpty)
                            Text(
                              evidence.displayName,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getRiskIcon(overallStatus), color: Colors.white, size: 16),
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
              body: 'No validated pharmacogenomic relationship was found for ${d.drug}. Genetic testing is not required for this drug. Assessment completed using clinical profile, allergies, and drug interactions.',
            ),
          if (category == _ReportCategory.insufficientData)
            _buildInfoBanner(
              icon: Icons.warning_amber_rounded,
              color: Colors.orange.shade800,
              bgColor: Colors.orange.shade50,
              title: 'INSUFFICIENT PATIENT DATA',
              body: 'This medicine has established pharmacogenomic evidence, but your uploaded VCF does not contain confirmed data for the relevant gene (${d.pharmacogenomicProfile.primaryGene}).',
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
                          const Icon(Icons.verified_outlined, size: 18, color: Colors.indigo),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              evidence?.displayName ?? d.drug,
                              softWrap: true,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          if (evidence?.verifiedMedicine == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(8)),
                              child: const Text('Verified', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      if (evidence?.uses.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text('What is it used for?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        ...evidence!.uses.map((use) => Text('• $use', style: const TextStyle(fontSize: 12))),
                      ],
                      if (evidence?.activeIngredients.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text('Active ingredient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(evidence!.activeIngredients.join(', '), style: const TextStyle(fontSize: 12)),
                      ],
                      if (evidence?.precautions.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text('Important Precautions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        ...evidence!.precautions.map((p) => Text('• $p', style: const TextStyle(fontSize: 12, color: Colors.black87))),
                      ],
                      if (evidence?.commonSideEffects.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text('Common side effects', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        ...evidence!.commonSideEffects.map((effect) => Text('• $effect', style: const TextStyle(fontSize: 12))),
                      ],
                      if (evidence?.seriousSideEffects.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        const Text('Get medical help quickly for', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                        const SizedBox(height: 4),
                        ...evidence!.seriousSideEffects.map((effect) => Text('• $effect', style: const TextStyle(fontSize: 12, color: Colors.red))),
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
                      Icon(Icons.personal_injury_outlined, size: 20, color: Colors.deepOrange.shade800),
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
                  ...personalizedSideEffects.map((risk) => _buildPersonalizedSideEffectCard(risk)),
                  const SizedBox(height: 14),
                ],

                _buildAiExplanationCard(d),
                const SizedBox(height: 14),
                _buildProfessionalReviewBanner(overallStatus),
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
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

  Widget _buildPatientSnapshotCard(BuildContext context, PatientProfile profile) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.badge_outlined, size: 18, color: Colors.blueGrey),
                  SizedBox(width: 6),
                  Text('Your Profile Context', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PatientProfileScreen()),
                  );
                },
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Update Profile', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (profile.age.isNotEmpty) _chip('Age: ${profile.age}'),
              if (profile.sex.isNotEmpty) _chip('Sex: ${profile.sex}'),
              if (profile.weight.isNotEmpty) _chip('Weight: ${profile.weight} kg'),
              if (profile.conditions.isNotEmpty)
                _chip('Conditions: ${profile.conditions.join(", ")}', isAlert: true),
              if (profile.currentMedicines.isNotEmpty)
                _chip('Meds: ${profile.currentMedicines.join(", ")}'),
              if (profile.allergies.isNotEmpty)
                _chip('Allergies: ${profile.allergies.join(", ")}', isAlert: true),
              if (profile.kidneyFunction.isNotEmpty)
                _chip('Kidney: ${profile.kidneyFunction}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAlert ? Colors.amber.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isAlert ? Colors.amber.shade400 : Colors.grey.shade300),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: isAlert ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _buildAllergySection(String medicine, List<ClinicalSafetyFinding> findings, PatientProfile profile) {
    final allergyFinding = findings.where((f) => f.status == 'CONTRAINDICATED' && f.title.contains('Allergy')).firstOrNull;

    if (allergyFinding != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dangerous, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'ALLERGY CONCERN',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(allergyFinding.explanation, style: TextStyle(fontSize: 12, color: Colors.red.shade900, height: 1.3)),
            const SizedBox(height: 6),
            const Text(
              'Your reported allergy may make this medicine inappropriate. Seek professional medical advice before taking it.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ALLERGY CHECK: No matching allergy detected for $medicine in your reported profile.',
              style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionsSection(String medicine, List<ClinicalSafetyFinding> findings, PatientProfile profile) {
    final interactionFindings = findings.where((f) => f.status == 'DRUG_INTERACTION_DETECTED').toList();

    if (interactionFindings.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'DRUG INTERACTION DETECTED',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...interactionFindings.map((finding) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ${finding.title}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red.shade900)),
                      Text(finding.explanation, style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
                      const Text('Patient relevance: HIGH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                )),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              profile.currentMedicines.isEmpty
                  ? 'DRUG INTERACTIONS: No current medicines were reported in your profile.'
                  : 'DRUG INTERACTIONS: No known interactions detected between $medicine and your current medicines.',
              style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalizedSideEffectCard(PersonalizedSideEffectRisk risk) {
    final isHigh = risk.relevance == 'HIGHER_CONCERN' || risk.relevance == 'CRITICAL_CONCERN';
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cardColor),
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
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'WHO MAY BE AT HIGHER RISK?',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cardColor),
          ),
          const SizedBox(height: 2),
          ...risk.higherRiskGroups.map((g) => Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text('• $g', style: const TextStyle(fontSize: 12)),
              )),
          const SizedBox(height: 8),
          Text(
            'HOW DOES THIS APPLY TO YOU?',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cardColor),
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
            ...risk.patientRiskFactors.map((rf) => Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text('⚠ $rf', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cardColor)),
                )),
          const SizedBox(height: 8),
          Text(
            risk.explanation,
            style: const TextStyle(fontSize: 12, height: 1.35, fontStyle: FontStyle.italic),
          ),
          if (risk.evidenceSources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Evidence: ${risk.evidenceSources.join("; ")}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _buildPgxSection(PgxReport d, _ReportCategory category) {
    if (category == _ReportCategory.noPgxRelationship) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.teal.shade700, size: 18),
                const SizedBox(width: 8),
                Text(
                  'PHARMACOGENOMICS (VCF / PGx)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal.shade900),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'No actionable pharmacogenomic relationship identified for ${d.drug}. Prescribing decisions do not require genetic testing. Overall safety guided by clinical factors.',
              style: TextStyle(fontSize: 12, color: Colors.teal.shade900),
            ),
          ],
        ),
      );
    }

    return ExpansionTile(
      leading: const Icon(Icons.biotech, color: Colors.teal),
      title: const Text('Pharmacogenomic (VCF) Profile & Variants', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      initiallyExpanded: category == _ReportCategory.standard,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Primary Gene: ${d.pharmacogenomicProfile.primaryGene}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Diplotype Call: ${d.pharmacogenomicProfile.diplotype}'),
              Text('Phenotype Class: ${d.pharmacogenomicProfile.phenotype}'),
              const SizedBox(height: 6),
              Text('CPIC Recommendation: ${d.clinicalRecommendation.dosingRecommendation}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              const Text('Detected rsIDs in VCF:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              if (d.pharmacogenomicProfile.detectedVariants.isEmpty)
                const Text('No variant rsIDs listed in file', style: TextStyle(fontSize: 11, color: Colors.grey))
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
    );
  }

  Widget _buildSimpleSafetySummary(PgxReport d, String overallStatus) {
    final isUnknown = overallStatus == 'Unknown' ||
        d.riskAssessment.riskLabel == 'Medicine not verified';
    final message = isUnknown
        ? 'There is not enough verified information to say this medicine is safe or unsafe for you.'
        : overallStatus == 'No major risk identified'
            ? 'No major risk was found from the information checked. This does not mean the medicine is completely risk-free.'
            : 'This medicine may need extra care for you. Do not start, stop, or change it without a doctor or pharmacist.';

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
              Text(
                'Simple explanation',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            d.llmGeneratedExplanation.patientFriendly,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text('Why this result:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text(d.llmGeneratedExplanation.mechanism, style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35)),
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
    final isHigh = overallStatus == 'High-risk finding' || overallStatus == 'Contraindication identified';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHigh ? Colors.red.shade50 : Colors.orange.shade50,
        border: Border.all(color: isHigh ? Colors.red.shade300 : Colors.orange.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.medical_information_outlined, color: isHigh ? Colors.red : Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isHigh
                  ? 'HIGH-RISK FINDING: A factor associated with increased medication risk was identified for your profile. Seek advice from a qualified doctor or pharmacist before taking or changing this medicine.'
                  : 'IMPORTANT: This is a medication-safety decision-support assessment. Do not start, stop, or change a medicine or dose based only on this application. Always consult a qualified doctor or pharmacist.',
              style: TextStyle(fontSize: 12, height: 1.35, color: isHigh ? Colors.red.shade900 : Colors.orange.shade900, fontWeight: FontWeight.w500),
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
          _chainStep('🔍', 'Database Search', 'CPIC / PharmGKB / FDA Catalog'),
          _chainArrow(),
          _chainStep('📋', 'Result', 'No actionable PGx relationship found'),
          _chainArrow(),
          _chainStep('🩺', 'Clinical Stratification', 'Allergies, conditions & drug interactions evaluated'),
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
}

enum _ReportCategory {
  standard,
  noPgxRelationship,
  insufficientData,
  unknown,
}
