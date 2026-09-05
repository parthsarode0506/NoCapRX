import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../models/patient_profile.dart';
import '../services/patient_profile_service.dart';
import '../services/personalized_side_effect_engine.dart';
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

    if (customDrugText.isNotEmpty) {
      setState(() {
        _isAnalyzing = true;
        _progressSteps.clear();
      });

      _addProgress('🔎', 'Searching local medicine database...');
      await Future.delayed(const Duration(milliseconds: 300));

      // Step 1: Normalize and resolve locally
      final identity = MedicineNormalizationService.identify(customDrugText);

      // Check if ambiguous — prompt user to pick
      if (identity.isAmbiguous && mounted) {
        _markLastDone();
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ambiguous medicine name: "$customDrugText". Please enter a more specific name.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final metadata = DrugRepository.resolve(customDrugText);
      final resolvedLocal = CpicRuleEngine.resolveDrugName(customDrugText) ??
          metadata?.genericName;

      if (resolvedLocal != null && metadata?.ruleAvailable == true) {
        // Found locally with a validated rule
        _markLastDone();
        _addProgress('✓', 'Found in local validated database', done: true);
        drugsToEvaluate.add(resolvedLocal);

        // If metadata exists, convert to DrugEvidence for the engine
        if (metadata != null) {
          _discoveredEvidence[resolvedLocal] = DrugRepository.toDrugEvidence(metadata);
        }
      } else {
        // Not found locally — go online
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
              _addProgress('🧬', 'Pharmacogenomic evidence found: ${evidence.genes.join(", ")}', done: true);
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
            // Fully unknown — still add it for a transparent Unknown report
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

        // Look up evidence: from online discovery, from local metadata, or null
        DrugEvidence? evidence = _discoveredEvidence[drug];
        if (evidence == null) {
          // For panel drugs selected via checkbox, build evidence from metadata
          final meta = DrugRepository.resolve(drug);
          if (meta != null) {
            evidence = DrugRepository.toDrugEvidence(meta);
          }
        }

        if (evidence != null && evidence.requiredClinicalData.isNotEmpty) {
          final missing = evidence.requiredClinicalData
              .where((field) => _clinicalData[field]?.trim().isNotEmpty != true)
              .toList();
          if (missing.isNotEmpty) {
            _addProgress('🩺', 'Collecting required clinical inputs for $drug...');
            final collected = await _collectClinicalData(evidence);
            if (collected != null) {
              _clinicalData.addAll(collected);
            }
            _markLastDone();
          }
        }

        // CPIC Rule Engine Evaluation — now with DrugEvidence
        final initialReport = CpicRuleEngine.evaluateDrug(
          drugName: drug,
          parseResult: parseResult,
          evidence: evidence,
          clinicalData: _clinicalData,
        );

        _markLastDone();
        _addProgress('⚙️', 'Applying clinical rule for $drug...');
        await Future.delayed(const Duration(milliseconds: 150));

        // LLM Explanation Generation (with offline asset fallback)
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
          personalizedSideEffects: evidence == null
              ? const []
              : PersonalizedSideEffectEngine.evaluate(evidence, _clinicalData),
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

      // Save derived JSON report to Firestore (never raw VCF file!)
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
            backgroundColor: Colors.red,
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
      final values = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Clinical inputs for ${evidence.displayName}'),
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
                        border: const OutlineInputBorder(),
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
              FilledButton(
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
      if (values != null) {
        final profile = await PatientProfileService.load();
        final updatedProfile = _profileWithAnswers(profile, values);
        await PatientProfileService.save(updatedProfile);
        if (mounted) {
          ref.read(patientProfileProvider.notifier).state = updatedProfile;
        }
      }
      return values;
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Map<String, String> _profileToClinicalData(PatientProfile profile) => {
        if (profile.age.isNotEmpty) 'Age': profile.age,
        if (profile.weight.isNotEmpty) 'Weight': profile.weight,
        if (profile.sex.isNotEmpty) 'Sex': profile.sex,
        if (profile.allergies.isNotEmpty) 'Known allergies': profile.allergies.join(', '),
        if (profile.currentMedicines.isNotEmpty) 'Current medicines': profile.currentMedicines.join(', '),
        if (profile.conditions.isNotEmpty) 'Relevant conditions': profile.conditions.join(', '),
        if (profile.pregnancyStatus.isNotEmpty) 'Pregnancy/breastfeeding': profile.pregnancyStatus,
        if (profile.kidneyFunction.isNotEmpty) 'Kidney function': profile.kidneyFunction,
        if (profile.liverFunction.isNotEmpty) 'Liver function': profile.liverFunction,
      };

  PatientProfile _profileWithAnswers(PatientProfile profile, Map<String, String> answers) {
    String value(String key, String fallback) => answers[key] ?? fallback;
    return PatientProfile(
      patientId: profile.patientId,
      age: value('Age', profile.age),
      sex: value('Sex', profile.sex),
      weight: value('Weight', profile.weight),
      allergies: value('Known allergies', profile.allergies.join(', ')).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      currentMedicines: value('Current medicines', profile.currentMedicines.join(', ')).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      conditions: value('Relevant conditions', profile.conditions.join(', ')).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      pregnancyStatus: value('Pregnancy/breastfeeding', profile.pregnancyStatus),
      kidneyFunction: value('Kidney function', profile.kidneyFunction),
      liverFunction: value('Liver function', profile.liverFunction),
      vcfFilename: ref.read(selectedVcfFilenameProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDrugs = ref.watch(selectedDrugsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Select Target Drugs')),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step 2: Select Medications',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select one or more supported drugs to evaluate against confirmed VCF genomic variants.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Supported Drugs Selection Chips
                  Text(
                    'Supported Panel Drugs (6)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Column(
                    children: supportedDrugs.map((item) {
                      final drug = item['drug']!;
                      final gene = item['gene']!;
                      final type = item['type']!;
                      final isSelected = selectedDrugs.contains(drug);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.4,
                                )
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.grey.shade300,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: isSelected,
                          title: Text(
                            drug,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            'Primary Gene: $gene • $type',
                            style: const TextStyle(fontSize: 12),
                          ),
                          activeColor: theme.colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
                            ref.read(selectedDrugsProvider.notifier).state =
                                current;
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Optional Custom Free-Text Drug Field
                  Text(
                    'Any Medicine (Generic or Brand Name)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter any medicine — PharmaGuard will search local & online pharmacogenomic evidence.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customDrugController,
                    onChanged: (_) => setState(() {
                      _onlineEvidenceMessage = null;
                      _onlineEvidenceUrl = null;
                    }),
                    decoration: InputDecoration(
                      hintText: 'e.g. Tacrolimus, Plavix, Ibuprofen, Azithromycin',
                      prefixIcon: const Icon(Icons.medication_outlined),
                      helperText:
                          'Supports generic names, brand names, and aliases. Online evidence discovery for unlisted drugs.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_customDrugController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...DrugRepository.search(_customDrugController.text).map(
                      (drug) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.medication_outlined),
                        title: Text(drug.displayName),
                        subtitle: Text(
                          '${drug.aliases.join(', ')} • ${drug.genes.join(', ')}',
                        ),
                        trailing: const Icon(Icons.verified_outlined, size: 18),
                        onTap: () => setState(() {
                          _customDrugController.text = drug.displayName;
                          _onlineEvidenceMessage = null;
                          _onlineEvidenceUrl = null;
                        }),
                      ),
                    ),
                    if (DrugRepository.search(
                      _customDrugController.text,
                    ).isEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cloud_outlined, color: Colors.blue, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Not in local database. Online pharmacogenomic evidence discovery will be attempted.',
                                style: TextStyle(fontSize: 12, color: Colors.blue),
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
                      style: const TextStyle(
                        color: Colors.orange,
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
                  const SizedBox(height: 36),

                  // Analyze Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          selectedDrugs.isEmpty &&
                              _customDrugController.text.trim().isEmpty
                          ? null
                          : _runPipeline,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded),
                          SizedBox(width: 8),
                          Text(
                            'Check Medicine Safety',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Fullscreen Loading Overlay with Multi-Stage Progress
            if (_isAnalyzing)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.all(32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Analyzing Genomic Risk...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Multi-stage progress list
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: SingleChildScrollView(
                              reverse: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _progressSteps.map((step) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Text(
                                          step.done ? '✓' : step.emoji,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: step.done
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            step.text,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: step.done
                                                  ? Colors.grey.shade700
                                                  : Colors.black87,
                                              fontWeight: step.done
                                                  ? FontWeight.normal
                                                  : FontWeight.w500,
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
