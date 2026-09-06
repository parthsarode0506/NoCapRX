import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../rules_engine/cpic_rule_engine.dart';
import '../services/groq_ai_service.dart';
import '../services/firebase_service.dart';
import '../services/drug_repository.dart';
import '../services/online_evidence_service.dart';
import '../services/medicine_normalization_service.dart';
import '../models/pgx_report.dart';
import '../models/drug_evidence.dart';
import '../models/patient_profile.dart';
import '../models/personalized_side_effect_risk.dart';
import '../services/patient_profile_service.dart';
import '../services/personalized_side_effect_engine.dart';
import '../services/universal_medicine_safety_engine.dart';
import '../services/medicine_analysis_service.dart';
import '../theme/app_theme.dart';
import 'prescription_scan_screen.dart';
import 'results_screen.dart';

class DrugInputScreen extends ConsumerStatefulWidget {
  const DrugInputScreen({super.key});

  @override
  ConsumerState<DrugInputScreen> createState() => _DrugInputScreenState();
}

class _DrugInputScreenState extends ConsumerState<DrugInputScreen> {
  final TextEditingController _customDrugController = TextEditingController();
  bool _isAnalyzing = false;
  final List<_ProgressStep> _progressSteps = [];
  String? _onlineEvidenceMessage;
  Uri? _onlineEvidenceUrl;

  // Map to hold discovered evidence per drug for the current analysis run
  final Map<String, DrugEvidence> _discoveredEvidence = {};
  final Map<String, String> _clinicalData = {};

  @override
  void initState() {
    super.initState();
    // Sync from the shared provider (in case it was set elsewhere)
    _customDrugController.text = ref.read(customDrugTextProvider);
    _customDrugController.addListener(() {
      ref.read(customDrugTextProvider.notifier).state =
          _customDrugController.text;
    });
  }

  @override
  void dispose() {
    _customDrugController.dispose();
    super.dispose();
  }

  // ─── Progress helpers ────────────────────────────────────────────────────

  void _addProgress(String emoji, String text, {bool done = false}) {
    if (!mounted) return;
    setState(() {
      _progressSteps.add(_ProgressStep(emoji: emoji, text: text, done: done));
    });
  }

  void _markLastDone() {
    if (!mounted || _progressSteps.isEmpty) return;
    setState(() {
      _progressSteps.last = _ProgressStep(
        emoji: '✓',
        text: _progressSteps.last.text,
        done: true,
      );
    });
  }

  // ─── OCR prescription scan ───────────────────────────────────────────────

  Future<void> _openPrescriptionScanner() async {
    final result = await Navigator.of(context).push<PrescriptionScanResult>(
      MaterialPageRoute(
        builder: (_) => const PrescriptionScanScreen(),
      ),
    );

    if (!mounted || result == null) return;

    if (result.medicines.isEmpty) {
      // User closed or got an error — show manual entry hint
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No medicines identified from scan. Enter the name manually below.'),
          backgroundColor: AppTheme.warningAmber,
        ),
      );
      return;
    }

    setState(() {
      _customDrugController.text = result.medicines.join(', ');
      _onlineEvidenceMessage = null;
      _onlineEvidenceUrl = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.medicines.length} medicine(s) loaded from prescription. '
          'Tap Analyse to continue.',
        ),
        backgroundColor: AppTheme.primaryEmerald,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Analysis pipeline ───────────────────────────────────────────────────

  Future<void> _runPipeline() async {
    await MedicineAnalysisService.instance.ensureReady();
    if (!mounted) return;

    final parseResult = ref.read(vcfParseResultProvider);
    final selectedDrugs = ref.read(selectedDrugsProvider);
    final customDrugText = _customDrugController.text.trim();
    final enteredMedicines = customDrugText
        .split(RegExp(r'[,\n]'))
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();

    if (parseResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No VCF data found. Please re-upload your VCF file.'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
      return;
    }

    final drugsToEvaluate = List<String>.from(selectedDrugs);
    _discoveredEvidence.clear();
    _clinicalData.clear();
    final savedProfile = await PatientProfileService.load();
    _clinicalData.addAll(_profileToClinicalData(savedProfile));
    if (mounted) {
      ref.read(patientProfileProvider.notifier).state = savedProfile;
    }

    if (enteredMedicines.isNotEmpty) {
      setState(() {
        _isAnalyzing = true;
        _progressSteps.clear();
      });

      for (final enteredMedicine in enteredMedicines) {
        _addProgress('🔎', 'Identifying $enteredMedicine...');
        await Future.delayed(const Duration(milliseconds: 300));

        final identity = MedicineNormalizationService.identify(enteredMedicine);

        if (identity.isAmbiguous && mounted) {
          _markLastDone();
          setState(() => _isAnalyzing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Ambiguous name: "$enteredMedicine". Please be more specific.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        final metadata = DrugRepository.resolve(enteredMedicine);
        _markLastDone();
        _addProgress('🌐', 'Searching medicine information online...');
        await Future.delayed(const Duration(milliseconds: 200));

        final online = await OnlineEvidenceService.discover(enteredMedicine);
        final localEvidence = metadata == null
            ? null
            : DrugRepository.toDrugEvidence(metadata);
        final evidence = online.evidence == null
            ? localEvidence
            : _mergeEvidence(localEvidence, online.evidence!);

        if (mounted) {
          _markLastDone();
          if (evidence != null) {
            final drugKey = evidence.genericName.toUpperCase();
            if (evidence.hasPgxRelationship && evidence.genes.isNotEmpty) {
              _addProgress('🧬', 'PGx evidence found: ${evidence.genes.join(", ")}', done: true);
            } else {
              _addProgress('📋', 'Medicine facts found; no actionable PGx rule', done: true);
            }
            _discoveredEvidence[drugKey] = evidence;
            drugsToEvaluate.add(drugKey);
            setState(() {
              _onlineEvidenceMessage = online.message;
              _onlineEvidenceUrl = online.sourceUrl;
            });
          } else {
            _addProgress('⚠️', online.message, done: true);
            setState(() => _isAnalyzing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Medicine could not be verified online or locally.'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
        }
      }
    }

    if (!mounted) return;
    if (drugsToEvaluate.isEmpty) {
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter at least one medicine to analyse.')),
      );
      return;
    }

    setState(() => _isAnalyzing = true);
    if (_progressSteps.isEmpty) {
      _addProgress('⚙️', 'Starting pharmacogenomic analysis...');
    }

    try {
      final List<PgxReport> generatedReports = [];

      for (int i = 0; i < drugsToEvaluate.length; i++) {
        final drug = drugsToEvaluate[i];
        _addProgress(
            '🔒',
            'Analysing $drug on-device '
            '(${i + 1}/${drugsToEvaluate.length})...');
        await Future.delayed(const Duration(milliseconds: 200));

        DrugEvidence? evidence = _discoveredEvidence[drug];
        if (evidence == null) {
          final meta = DrugRepository.resolve(drug);
          if (meta != null) {
            evidence = DrugRepository.toDrugEvidence(meta);
          }
        }

        final initialReport = CpicRuleEngine.evaluateDrug(
          drugName: drug,
          parseResult: parseResult,
          evidence: evidence,
          clinicalData: _clinicalData,
        );

        _markLastDone();
        _addProgress('⚙️', 'Applying CPIC rule for $drug...');
        await Future.delayed(const Duration(milliseconds: 150));

        final personalizedSideEffects = evidence == null
            ? <PersonalizedSideEffectRisk>[]
            : PersonalizedSideEffectEngine.evaluate(evidence, _clinicalData);

        final clinicalFindings =
            UniversalMedicineSafetyEngine.evaluateAll(drug, _clinicalData);

        _addProgress('🤖', 'Generating AI explanation...');
        final gene = initialReport.pharmacogenomicProfile.primaryGene;
        final phenotype = initialReport.pharmacogenomicProfile.phenotype;
        final riskLabel = initialReport.riskAssessment.riskLabel;
        final cpicRec = initialReport.clinicalRecommendation.dosingRecommendation;

        final llmResultMap = await GroqAIService().generateExplanation(
          userRole: 'patient',
          medicalResult: {
            'medicine': drug,
            'verificationStatus': evidence?.verifiedMedicine == false
                ? 'Medicine Not Verified'
                : 'verified',
            'riskLabel': riskLabel,
            'severity': initialReport.riskAssessment.severity,
            'gene': gene,
            if (phenotype != 'Unknown') 'phenotype': phenotype,
            if (initialReport.pharmacogenomicProfile.diplotype != 'Unknown')
              'diplotype': initialReport.pharmacogenomicProfile.diplotype,
            'recommendation': cpicRec,
            'interactions':
                clinicalFindings.map((f) => f.toJson()).toList(),
            'personalizedSideEffects':
                personalizedSideEffects.map((r) => r.toJson()).toList(),
            if (evidence != null) 'evidenceSources': evidence.evidenceSources,
            if (evidence != null) 'uses': evidence.uses,
            if (evidence != null) 'commonSideEffects': evidence.commonSideEffects,
            if (evidence != null) 'seriousSideEffects': evidence.seriousSideEffects,
            if (evidence != null) 'precautions': evidence.precautions,
          },
        );
        _markLastDone();

        final fullReport = PgxReport(
          patientId: initialReport.patientId,
          drug: initialReport.drug,
          timestamp: initialReport.timestamp,
          riskAssessment: initialReport.riskAssessment,
          pharmacogenomicProfile: initialReport.pharmacogenomicProfile,
          clinicalRecommendation: initialReport.clinicalRecommendation,
          llmGeneratedExplanation: LlmExplanation.fromJson(llmResultMap),
          qualityMetrics: initialReport.qualityMetrics,
          evidence: evidence,
          personalizedSideEffects: personalizedSideEffects,
        );

        generatedReports.add(fullReport);
      }

      _addProgress('✅', 'Analysis complete!', done: true);
      await Future.delayed(const Duration(milliseconds: 400));

      final reportId = 'PGX_${DateTime.now().millisecondsSinceEpoch}';
      final vcfFilename =
          ref.read(selectedVcfFilenameProvider) ?? 'patient.vcf';

      final multiReport = PgxMultiReport(
        reportId: reportId,
        patientId: parseResult.patientId,
        vcfFilename: vcfFilename,
        timestamp: DateTime.now().toIso8601String(),
        drugReports: generatedReports,
      );

      await FirebaseService.saveReport(multiReport);
      ref.read(currentReportProvider.notifier).state = multiReport;

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => ResultsScreen(report: multiReport)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // ─── Profile helpers ─────────────────────────────────────────────────────

    DrugEvidence _mergeEvidence(DrugEvidence? local, DrugEvidence online) {
    if (local == null) return online;
    return DrugEvidence(
      genericName: local.genericName,
      displayName: local.displayName,
      aliases: {...local.aliases, ...online.aliases}.toList(),
      genes: local.genes.isNotEmpty ? local.genes : online.genes,
      relevantVariants: local.relevantVariants.isNotEmpty
        ? local.relevantVariants
        : online.relevantVariants,
      phenotypes: local.phenotypes.isNotEmpty ? local.phenotypes : online.phenotypes,
      guidelineCitation: local.guidelineCitation.isNotEmpty
        ? local.guidelineCitation
        : online.guidelineCitation,
      dosingRecommendation: local.dosingRecommendation.isNotEmpty
        ? local.dosingRecommendation
        : online.dosingRecommendation,
      alternativeDrugs: local.alternativeDrugs.isNotEmpty
        ? local.alternativeDrugs
        : online.alternativeDrugs,
      monitoringAdvice: local.monitoringAdvice.isNotEmpty
        ? local.monitoringAdvice
        : online.monitoringAdvice,
      mechanism: local.mechanism.isNotEmpty ? local.mechanism : online.mechanism,
      evidenceLevel: local.evidenceLevel,
      source: online.source.isNotEmpty ? online.source : local.source,
      clinicallyActionable: local.clinicallyActionable || online.clinicallyActionable,
      hasPgxRelationship: local.hasPgxRelationship || online.hasPgxRelationship,
      requiredClinicalData: local.requiredClinicalData.isNotEmpty
        ? local.requiredClinicalData
        : online.requiredClinicalData,
      retrievalTimestamp: online.retrievalTimestamp,
      isOnlineDiscovered: true,
      activeIngredients: online.activeIngredients.isNotEmpty
        ? online.activeIngredients
        : local.activeIngredients,
      strength: online.strength ?? local.strength,
      dosageForm: online.dosageForm ?? local.dosageForm,
      verifiedMedicine: local.verifiedMedicine && online.verifiedMedicine,
      identityConfidence: online.identityConfidence > 0
        ? online.identityConfidence
        : local.identityConfidence,
      uses: online.uses.isNotEmpty ? online.uses : local.uses,
      commonSideEffects: online.commonSideEffects.isNotEmpty
        ? online.commonSideEffects
        : local.commonSideEffects,
      seriousSideEffects: online.seriousSideEffects.isNotEmpty
        ? online.seriousSideEffects
        : local.seriousSideEffects,
      precautions: online.precautions.isNotEmpty ? online.precautions : local.precautions,
      evidenceSources: {...local.evidenceSources, ...online.evidenceSources}.toList(),
    );
    }

  Map<String, String> _profileToClinicalData(PatientProfile p) => {
        if (p.age.isNotEmpty) 'Age': p.age,
        if (p.weight.isNotEmpty) 'Weight': p.weight,
        if (p.sex.isNotEmpty) 'Sex': p.sex,
        if (p.allergies.isNotEmpty) 'Known allergies': p.allergies.join(', '),
        if (p.currentMedicines.isNotEmpty)
          'Current medicines': p.currentMedicines.join(', '),
        if (p.conditions.isNotEmpty)
          'Relevant conditions': p.conditions.join(', '),
        if (p.pregnancyStatus.isNotEmpty)
          'Pregnancy/breastfeeding': p.pregnancyStatus,
        if (p.kidneyFunction.isNotEmpty) 'Kidney function': p.kidneyFunction,
        if (p.liverFunction.isNotEmpty) 'Liver function': p.liverFunction,
      };

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = _customDrugController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check Medicine Safety',
              style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.deepInk),
            ),
            Text(
              'PharmaGuard • On-device PGx analysis',
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppTheme.secondaryInk),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main scrollable content ──────────────────────────────────
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── OCR Scan banner ──────────────────────────────────
                  _buildScanBanner(),
                  const SizedBox(height: 20),

                  // ── Manual entry ─────────────────────────────────────
                  _buildManualEntrySection(theme),
                  const SizedBox(height: 16),

                  // ── Autocomplete suggestions ─────────────────────────
                  if (hasText) _buildSuggestions(),

                  // ── Online evidence note ─────────────────────────────
                  if (_onlineEvidenceMessage != null)
                    _buildOnlineEvidenceBanner(),

                  const SizedBox(height: 8),

                  // ── Privacy note ─────────────────────────────────────
                  _buildPrivacyNote(),
                ],
              ),
            ),

            // ── Sticky bottom Analyse button ─────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildAnalyseButton(hasText),
            ),

            // ── Full-screen analysis overlay ─────────────────────────
            if (_isAnalyzing) _buildAnalysisOverlay(theme),
          ],
        ),
      ),
    );
  }

  // ─── Section builders ─────────────────────────────────────────────────────

  Widget _buildScanBanner() {
    return InkWell(
      onTap: _isAnalyzing ? null : _openPrescriptionScanner,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryDarkEmerald,
              AppTheme.accentEmerald.withValues(alpha: 0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.document_scanner_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan a Prescription',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Photograph or upload a prescription image — AI reads the medicines automatically.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Scan →',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntrySection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.edit_outlined,
                size: 18, color: AppTheme.accentEmerald),
            const SizedBox(width: 6),
            Text(
              'Or enter medicine name manually',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.deepInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Use a generic name, brand name, or alias. '
          'Separate multiple medicines with commas.',
          style: GoogleFonts.inter(
              fontSize: 12, color: AppTheme.secondaryInk),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _customDrugController,
          enabled: !_isAnalyzing,
          onChanged: (_) => setState(() {
            _onlineEvidenceMessage = null;
            _onlineEvidenceUrl = null;
          }),
          style: GoogleFonts.inter(
              fontSize: 14.5, color: AppTheme.deepInk),
          decoration: InputDecoration(
            hintText: 'e.g. Clopidogrel, Codeine, Warfarin',
            hintStyle: GoogleFonts.inter(
                fontSize: 13.5, color: AppTheme.mutedGrey),
            prefixIcon: const Icon(Icons.medication_outlined,
                color: AppTheme.accentEmerald),
            suffixIcon: _customDrugController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() {
                      _customDrugController.clear();
                      _onlineEvidenceMessage = null;
                    }),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    final suggestions = DrugRepository.search(_customDrugController.text);

    if (suggestions.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_outlined, color: Colors.blue.shade700, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Not in local database — online PGx evidence discovery will be attempted.',
                style: GoogleFonts.inter(
                    fontSize: 12, color: Colors.blue.shade800),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ...suggestions.take(5).map(
              (drug) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.medication_outlined,
                      color: AppTheme.accentEmerald, size: 20),
                  title: Text(
                    drug.displayName,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(
                    drug.genes.isEmpty
                        ? drug.aliases.take(3).join(' · ')
                        : '${drug.genes.join(', ')} · ${drug.aliases.take(2).join(', ')}',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppTheme.secondaryInk),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: drug.genes.isEmpty
                          ? Colors.grey.shade100
                          : AppTheme.mintSurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      drug.genes.isEmpty ? 'No PGx' : 'PGx',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: drug.genes.isEmpty
                            ? AppTheme.mutedGrey
                            : AppTheme.primaryEmerald,
                      ),
                    ),
                  ),
                  onTap: () => setState(() {
                    _customDrugController.text = drug.aliases.isNotEmpty
                        ? drug.aliases.first
                        : drug.genericName;
                    _onlineEvidenceMessage = null;
                    _onlineEvidenceUrl = null;
                  }),
                ),
              ),
            ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildOnlineEvidenceBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  color: Colors.orange.shade700, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _onlineEvidenceMessage!,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.orange.shade900),
                ),
              ),
            ],
          ),
          if (_onlineEvidenceUrl != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => launchUrl(_onlineEvidenceUrl!,
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('View source evidence'),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: Colors.orange.shade800),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.mintSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.accentEmerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline,
                  size: 16, color: AppTheme.primaryEmerald),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Genomic Privacy Guarantee',
                  softWrap: true,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDarkEmerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _privacyRow('VCF processing', 'On Device ✓'),
          _privacyRow('Raw VCF uploaded', '0 KB'),
          _privacyRow('Raw genetic data', 'Never uploaded'),
          _privacyRow('AI receives', 'Derived findings only'),
        ],
      ),
    );
  }

  Widget _privacyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              '$label: ',
              softWrap: true,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppTheme.secondaryInk),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryEmerald,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyseButton(bool hasText) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppTheme.bgLight,
        border: const Border(top: BorderSide(color: AppTheme.cardBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: hasText && !_isAnalyzing ? _runPipeline : null,
        icon: const Icon(Icons.biotech_outlined),
        label: const Text('Analyse Medicine Safety'),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryEmerald,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.cardBorder,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(
              fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildAnalysisOverlay(ThemeData theme) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.mintSurface,
                  shape: BoxShape.circle,
                ),
                child: CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Analysing on-device…',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.deepInk,
                ),
              ),
              Text(
                'Raw VCF never leaves your phone.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.secondaryInk,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _progressSteps.map((step) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            vertical: 3, horizontal: 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                step.done ? '✓' : step.emoji,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: step.done
                                      ? AppTheme.safeGreen
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                step.text,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: step.done
                                      ? AppTheme.secondaryInk
                                      : AppTheme.deepInk,
                                  fontWeight: step.done
                                      ? FontWeight.normal
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────

class _ProgressStep {
  final String emoji;
  final String text;
  final bool done;

  const _ProgressStep({
    required this.emoji,
    required this.text,
    this.done = false,
  });
}
