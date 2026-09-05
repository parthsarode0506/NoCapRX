import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../rules_engine/cpic_rule_engine.dart';
import '../services/llm_service.dart';
import '../services/firebase_service.dart';
import '../services/drug_repository.dart';
import '../services/online_evidence_service.dart';
import '../services/medicine_normalization_service.dart';
import '../models/pgx_report.dart';
import '../models/drug_evidence.dart';
import '../theme/app_theme.dart';
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

  final Map<String, DrugEvidence> _discoveredEvidence = {};
  final Map<String, String> _clinicalData = {};

  static const List<Map<String, String>> supportedDrugs = [
    {'drug': 'CODEINE', 'gene': 'CYP2D6', 'type': 'Opioid Analgesic'},
    {'drug': 'WARFARIN', 'gene': 'CYP2C9', 'type': 'Anticoagulant'},
    {'drug': 'CLOPIDOGREL', 'gene': 'CYP2C19', 'type': 'Antiplatelet'},
    {'drug': 'SIMVASTATIN', 'gene': 'SLCO1B1', 'type': 'Statin Lipid Lowering'},
    {'drug': 'AZATHIOPRINE', 'gene': 'TPMT', 'type': 'Immunosuppressant'},
    {'drug': 'FLUOROURACIL', 'gene': 'DPYD', 'type': 'Oncology Chemotherapy'},
  ];

  @override
  void dispose() {
    _customDrugController.dispose();
    super.dispose();
  }

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

  Future<void> _runPipeline() async {
    final parseResult = ref.read(vcfParseResultProvider);
    final selectedDrugs = ref.read(selectedDrugsProvider);
    final customDrugText = _customDrugController.text.trim();

    if (parseResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No VCF data found. Please re-upload VCF file.'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
      return;
    }

    final drugsToEvaluate = List<String>.from(selectedDrugs);
    _discoveredEvidence.clear();
    _clinicalData.clear();

    if (customDrugText.isNotEmpty) {
      setState(() {
        _isAnalyzing = true;
        _progressSteps.clear();
      });

      _addProgress('🔎', 'Searching local medicine database...');
      await Future.delayed(const Duration(milliseconds: 300));

      final identity = MedicineNormalizationService.identify(customDrugText);

      if (identity.isAmbiguous && mounted) {
        _markLastDone();
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ambiguous medicine name: "$customDrugText". Please enter a more specific name.',
            ),
            backgroundColor: AppTheme.warningAmber,
          ),
        );
        return;
      }

      final metadata = DrugRepository.resolve(customDrugText);
      final resolvedLocal = CpicRuleEngine.resolveDrugName(customDrugText) ??
          metadata?.genericName;

      if (resolvedLocal != null && metadata?.ruleAvailable == true) {
        _markLastDone();
        _addProgress('✓', 'Found in local validated database', done: true);
        drugsToEvaluate.add(resolvedLocal);

        if (metadata != null) {
          _discoveredEvidence[resolvedLocal] = DrugRepository.toDrugEvidence(metadata);
        }
      } else {
        _markLastDone();
        _addProgress('🌐', 'Identifying medicine online...');
        await Future.delayed(const Duration(milliseconds: 200));

        final online = await OnlineEvidenceService.discover(customDrugText);

        if (mounted) {
          _markLastDone();

          if (online.evidence != null) {
            final evidence = online.evidence!;
            final drugKey = evidence.genericName.toUpperCase();

            if (evidence.hasPgxRelationship && evidence.genes.isNotEmpty) {
              _addProgress('🧬', 'PGx evidence found: ${evidence.genes.join(", ")}', done: true);
              _addProgress('📚', 'Source: ${evidence.source}', done: true);
            } else {
              _addProgress('📋', 'No pharmacogenomic relationship found', done: true);
            }

            _discoveredEvidence[drugKey] = evidence;
            drugsToEvaluate.add(drugKey);

            setState(() {
              _onlineEvidenceMessage = online.message;
              _onlineEvidenceUrl = online.sourceUrl;
            });
          } else {
            _addProgress('⚠️', online.message, done: true);
            drugsToEvaluate.add(customDrugText.toUpperCase());
          }
        }
      }
    }

    if (!mounted) return;
    if (drugsToEvaluate.isEmpty) {
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one drug to analyze.'),
          backgroundColor: AppTheme.warningAmber,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    if (_progressSteps.isEmpty) {
      _addProgress('⚙️', 'Starting pharmacogenomic analysis...');
    }

    try {
      final List<PgxReport> generatedReports = [];

      for (int i = 0; i < drugsToEvaluate.length; i++) {
        final drug = drugsToEvaluate[i];
        _addProgress('🔒', 'Analyzing $drug on device (${i + 1}/${drugsToEvaluate.length})...');
        await Future.delayed(const Duration(milliseconds: 200));

        DrugEvidence? evidence = _discoveredEvidence[drug];
        if (evidence == null) {
          final meta = DrugRepository.resolve(drug);
          if (meta != null) {
            evidence = DrugRepository.toDrugEvidence(meta);
          }
        }

        if (evidence != null && evidence.requiredClinicalData.isNotEmpty) {
          _addProgress('🩺', 'Collecting required clinical inputs...');
          final collected = await _collectClinicalData(evidence);
          if (collected != null) {
            _clinicalData.addAll(collected);
          }
          _markLastDone();
        }

        final initialReport = CpicRuleEngine.evaluateDrug(
          drugName: drug,
          parseResult: parseResult,
          evidence: evidence,
          clinicalData: _clinicalData,
        );

        _markLastDone();
        _addProgress('⚙️', 'Applying clinical rule for $drug...');
        await Future.delayed(const Duration(milliseconds: 150));

        final gene = initialReport.pharmacogenomicProfile.primaryGene;
        final phenotype = initialReport.pharmacogenomicProfile.phenotype;
        final riskLabel = initialReport.riskAssessment.riskLabel;
        final mechanism = initialReport.llmGeneratedExplanation.mechanism;
        final cpicRec =
            initialReport.clinicalRecommendation.dosingRecommendation;

        final llmResultMap = await LlmService.generateExplanation(
          gene: gene,
          phenotype: phenotype,
          drug: drug,
          riskLabel: riskLabel,
          mechanism: mechanism,
          cpicRec: cpicRec,
        );

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
        );

        generatedReports.add(fullReport);
        _markLastDone();
      }

      _addProgress('✓', 'Analysis complete!', done: true);
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
          MaterialPageRoute(builder: (_) => ResultsScreen(report: multiReport)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis Pipeline Error: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<Map<String, String>?> _collectClinicalData(DrugEvidence evidence) async {
    final controllers = <String, TextEditingController>{
      for (final field in evidence.requiredClinicalData)
        field: TextEditingController(text: _clinicalData[field] ?? ''),
    };

    try {
      if (!mounted) return null;
      return await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(
              'Clinical inputs for ${evidence.displayName}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: evidence.requiredClinicalData.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: controllers[field],
                      decoration: InputDecoration(
                        labelText: field,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () {
                  final values = <String, String>{};
                  for (final entry in controllers.entries) {
                    final value = entry.value.text.trim();
                    if (value.isNotEmpty) values[entry.key] = value;
                  }
                  Navigator.of(dialogContext).pop(values);
                },
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDrugs = ref.watch(selectedDrugsProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Text(
          'Select Target Drugs',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: AppTheme.deepInk,
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.lightEmeraldPill,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'STEP 2 OF 2',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryDarkEmerald,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select Medications to Evaluate',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: AppTheme.deepInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Evaluate against validated CPIC pharmacogenomic rules locally on-device.',
                    style: GoogleFonts.inter(
                      color: AppTheme.secondaryInk,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Supported Panel Drugs List
                  Text(
                    'Supported Panel Drugs (6)',
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.deepInk,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Column(
                    children: supportedDrugs.map((item) {
                      final drug = item['drug']!;
                      final gene = item['gene']!;
                      final type = item['type']!;
                      final isSelected = selectedDrugs.contains(drug);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.mintSurface : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryEmerald
                                : AppTheme.cardBorder,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: isSelected,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          title: Row(
                            children: [
                              Text(
                                drug,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: isSelected
                                      ? AppTheme.primaryEmerald
                                      : AppTheme.deepInk,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.lightEmeraldPill,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  gene,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryDarkEmerald,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            type,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: AppTheme.secondaryInk,
                            ),
                          ),
                          activeColor: AppTheme.primaryEmerald,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onChanged: (bool? checked) {
                            final current = Set<String>.from(
                              ref.read(selectedDrugsProvider),
                            );
                            if (checked == true) {
                              current.add(drug);
                            } else {
                              current.remove(drug);
                            }
                            ref.read(selectedDrugsProvider.notifier).state = current;
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Optional Custom Free-Text Drug Field
                  Text(
                    'Any Medicine (Generic or Brand Name)',
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.deepInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter any medicine — NoCapRX searches validated clinical evidence.',
                    style: GoogleFonts.inter(
                      color: AppTheme.secondaryInk,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customDrugController,
                    style: GoogleFonts.inter(fontSize: 14, color: AppTheme.deepInk),
                    onChanged: (_) => setState(() {
                      _onlineEvidenceMessage = null;
                      _onlineEvidenceUrl = null;
                    }),
                    decoration: InputDecoration(
                      hintText: 'e.g. Tacrolimus, Plavix, Ibuprofen, Azithromycin',
                      prefixIcon: const Icon(
                        Icons.medication_outlined,
                        color: AppTheme.secondaryInk,
                      ),
                    ),
                  ),
                  if (_customDrugController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...DrugRepository.search(_customDrugController.text).map(
                      (drug) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.medication_outlined,
                            color: AppTheme.primaryEmerald,
                          ),
                          title: Text(
                            drug.displayName,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          subtitle: Text(
                            '${drug.aliases.join(', ')} • ${drug.genes.join(', ')}',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.secondaryInk),
                          ),
                          trailing: const Icon(
                            Icons.verified_outlined,
                            size: 18,
                            color: AppTheme.safeGreen,
                          ),
                          onTap: () => setState(() {
                            _customDrugController.text = drug.displayName;
                            _onlineEvidenceMessage = null;
                            _onlineEvidenceUrl = null;
                          }),
                        ),
                      ),
                    ),
                    if (DrugRepository.search(_customDrugController.text).isEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.lightEmeraldPill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.accentEmerald.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_outlined,
                                color: AppTheme.primaryEmerald, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Not in local DB. Online pharmacogenomic evidence discovery will be attempted.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.primaryDarkEmerald,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (_onlineEvidenceMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _onlineEvidenceMessage!,
                      style: GoogleFonts.inter(
                        color: AppTheme.warningAmber,
                        fontSize: 12,
                      ),
                    ),
                    if (_onlineEvidenceUrl != null)
                      TextButton.icon(
                        onPressed: () => launchUrl(
                          _onlineEvidenceUrl!,
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_browser, size: 18),
                        label: const Text('Open official FDA label in browser'),
                      ),
                  ],
                  const SizedBox(height: 28),

                  // Analyze Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: selectedDrugs.isEmpty &&
                              _customDrugController.text.trim().isEmpty
                          ? null
                          : _runPipeline,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryEmerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Check Medicine Safety',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Loading Overlay with Multi-Stage Progress
            if (_isAnalyzing)
              Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(28),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryEmerald,
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Analyzing Genomic Risk...',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.deepInk,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _progressSteps.map((step) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Text(
                                        step.done ? '✓' : step.emoji,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: step.done
                                              ? AppTheme.safeGreen
                                              : AppTheme.warningAmber,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          step.text,
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: step.done
                                                ? AppTheme.secondaryInk
                                                : AppTheme.deepInk,
                                            fontWeight: step.done
                                                ? FontWeight.w400
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
              ),
          ],
        ),
      ),
    );
  }
}

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
