import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../rules_engine/cpic_rule_engine.dart';
import '../services/llm_service.dart';
import '../services/firebase_service.dart';
import '../services/drug_repository.dart';
import '../services/online_evidence_service.dart';
import '../models/pgx_report.dart';
import 'results_screen.dart';

class DrugInputScreen extends ConsumerStatefulWidget {
  const DrugInputScreen({super.key});

  @override
  ConsumerState<DrugInputScreen> createState() => _DrugInputScreenState();
}

class _DrugInputScreenState extends ConsumerState<DrugInputScreen> {
  final TextEditingController _customDrugController = TextEditingController();
  bool _isAnalyzing = false;
  String _analysisProgressStatus = '';
  String? _onlineEvidenceMessage;
  Uri? _onlineEvidenceUrl;

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
    if (customDrugText.isNotEmpty) {
      setState(() {
        _isAnalyzing = true;
        _analysisProgressStatus =
            'Matching $customDrugText to validated medication rules...';
      });

      // Medicine identity must come from the local, validated catalogue. An
      // LLM is never used to map a medicine or create a clinical rule.
      final metadata = DrugRepository.resolve(customDrugText);
      final resolvedLocal =
          CpicRuleEngine.resolveDrugName(customDrugText) ??
          metadata?.genericName;
      if (resolvedLocal == null || metadata?.ruleAvailable == false) {
        final online = await OnlineEvidenceService.discover(customDrugText);
        if (mounted) {
          setState(() {
            _onlineEvidenceMessage = online.message;
            _onlineEvidenceUrl = online.sourceUrl;
          });
        }
      }
      drugsToEvaluate.add(resolvedLocal ?? customDrugText.toUpperCase());
    }

    if (!mounted) return;
    if (drugsToEvaluate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one drug to analyze.'),
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisProgressStatus =
          'Cross-referencing genes against CPIC guidelines...';
    });

    try {
      final List<PgxReport> generatedReports = [];

      for (int i = 0; i < drugsToEvaluate.length; i++) {
        final drug = drugsToEvaluate[i];
        if (mounted) {
          setState(() {
            _analysisProgressStatus =
                'Evaluating $drug (${i + 1}/${drugsToEvaluate.length})...';
          });
        }

        // 1. CPIC Rule Engine Evaluation
        final initialReport = CpicRuleEngine.evaluateDrug(
          drugName: drug,
          parseResult: parseResult,
        );

        // 2. LLM Explanation Generation (with offline asset fallback)
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
        );

        generatedReports.add(fullReport);
      }

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
                    'Other Drug (Generic or Brand Name)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customDrugController,
                    onChanged: (_) => setState(() {
                      _onlineEvidenceMessage = null;
                      _onlineEvidenceUrl = null;
                    }),
                    decoration: InputDecoration(
                      hintText: 'e.g. Aspirin, Ibuprofen, Tacrolimus',
                      prefixIcon: const Icon(Icons.medication_outlined),
                      helperText:
                          'Recognizes supported generic and brand names. Unmapped drugs remain Unknown; the app will never guess a Safe result.',
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
                      const ListTile(
                        dense: true,
                        leading: Icon(Icons.search_off_outlined),
                        title: Text(
                          'Not in the offline validated evidence database',
                        ),
                        subtitle: Text(
                          'A clinical classification will remain Unknown unless a validated backend evidence service is configured.',
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
                            'Run Risk Analysis Engine',
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

            // Fullscreen Loading Overlay during Analysis Pipeline
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
                          const SizedBox(height: 8),
                          Text(
                            _analysisProgressStatus,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
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
