import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/organization_patient.dart';
import '../models/prescription.dart';
import '../parser/vcf_parser.dart';
import '../providers/app_providers.dart';
import '../rules_engine/cpic_rule_engine.dart';
import '../services/firebase_service.dart';
import '../services/prescription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class CreatePrescriptionScreen extends ConsumerStatefulWidget {
  const CreatePrescriptionScreen({
    super.key,
    required this.patient,
    this.parseResult,
  });

  final OrganizationPatient patient;
  final VcfParseResult? parseResult;

  @override
  ConsumerState<CreatePrescriptionScreen> createState() =>
      _CreatePrescriptionScreenState();
}

class _CreatePrescriptionScreenState
    extends ConsumerState<CreatePrescriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  final List<PrescriptionItem> _items = [];
  bool _isSaving = false;

  // Medicine entry form controllers
  final _medicineController = TextEditingController();
  final _dosageController = TextEditingController();
  final _frequencyController = TextEditingController(text: 'Once daily');
  final _durationController = TextEditingController(text: '30 days');
  final _instructionsController = TextEditingController();

  PrescriptionItem? _evaluatedPreview;
  bool _showAddMedicineModal = false;

  final List<String> _cpicDrugs = [
    'Clopidogrel',
    'Warfarin',
    'Simvastatin',
    'Codeine',
    'Azathioprine',
    'Fluorouracil',
    'Tacrolimus',
    'Abacavir',
    'Carbamazepine',
    'Phenytoin',
    'Tamoxifen',
    'Ondansetron',
    'Irinotecan',
    'Celecoxib',
    'Ibuprofen',
    'Amitriptyline',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    _medicineController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _durationController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  VcfParseResult? _getPatientParseResult() {
    if (widget.parseResult != null) return widget.parseResult;
    return ref.read(vcfParseResultProvider);
  }

  void _evaluateInputMedicine(String drugName) {
    final parseResult = _getPatientParseResult();
    if (drugName.trim().isEmpty) {
      setState(() => _evaluatedPreview = null);
      return;
    }

    if (parseResult == null) {
      // Patient has no genetic profile yet
      setState(() {
        _evaluatedPreview = PrescriptionItem(
          medicineName: drugName.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Standard',
          severity: 'none',
          recommendation:
              'No genetic file on record for this patient. Standard clinical dosing applies.',
        );
      });
      return;
    }

    try {
      final report = CpicRuleEngine.evaluateDrug(
        drugName: drugName.trim(),
        parseResult: parseResult,
      );

      final risk = report.riskAssessment;
      final cpic = report.clinicalRecommendation;
      final pgxProfile = report.pharmacogenomicProfile;

      setState(() {
        _evaluatedPreview = PrescriptionItem(
          medicineName: drugName.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: risk.riskLabel,
          severity: risk.severity,
          gene: pgxProfile.primaryGene,
          phenotype: pgxProfile.phenotype,
          recommendation: cpic.dosingRecommendation,
          alternativeDrugs: cpic.alternativeDrugs,
        );
      });
    } catch (_) {
      setState(() {
        _evaluatedPreview = PrescriptionItem(
          medicineName: drugName.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Standard',
          severity: 'none',
          recommendation: 'No CPIC gene-drug contraindication detected.',
        );
      });
    }
  }

  void _addCurrentMedicine() {
    if (_medicineController.text.trim().isEmpty) return;
    if (_dosageController.text.trim().isEmpty) {
      _dosageController.text = 'As directed';
    }

    _evaluateInputMedicine(_medicineController.text);
    final itemToAdd = _evaluatedPreview ??
        PrescriptionItem(
          medicineName: _medicineController.text.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
        );

    setState(() {
      _items.add(itemToAdd);
      _medicineController.clear();
      _dosageController.clear();
      _instructionsController.clear();
      _evaluatedPreview = null;
      _showAddMedicineModal = false;
    });
  }

  void _replaceItemWithAlternative(int index, String alternativeDrug) {
    setState(() {
      _medicineController.text = alternativeDrug;
      _evaluateInputMedicine(alternativeDrug);
      if (_evaluatedPreview != null) {
        _items[index] = _evaluatedPreview!.copyWith(
          dosage: _items[index].dosage,
          frequency: _items[index].frequency,
          duration: _items[index].duration,
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Replaced with safer alternative: $alternativeDrug'),
      ),
    );
  }

  Future<void> _savePrescription({required bool issue}) async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one medication to the prescription.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseService.currentUser;
      final profile = ref.read(userProfileProvider);
      final prescriberName =
          user?.displayName ?? profile?.displayName ?? 'Dr. Clinician';
      final prescriberId = user?.uid ?? 'DOC-${DateTime.now().millisecondsSinceEpoch % 10000}';
      final orgName = profile?.organizationName.isNotEmpty == true
          ? profile!.organizationName
          : 'Clinical Center';

      final prescriptionId = 'RX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      final prescription = Prescription(
        prescriptionId: prescriptionId,
        patientId: widget.patient.patientId,
        patientName: widget.patient.name,
        patientUid: widget.patient.patientUid,
        organizationId: user?.uid ?? 'ORG_DEFAULT',
        organizationName: orgName,
        prescriberId: prescriberId,
        prescriberName: prescriberName,
        items: List.from(_items),
        status: issue ? 'issued' : 'draft',
        notes: _notesController.text.trim(),
        createdAt: DateTime.now(),
        issuedAt: issue ? DateTime.now() : null,
      );


      await PrescriptionService.instance.savePrescription(prescription);

      if (!mounted) return;
      setState(() => _isSaving = false);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          icon: Icon(
            issue ? Icons.check_circle_rounded : Icons.save_rounded,
            color: issue ? AppTheme.safeGreen : AppTheme.primaryEmerald,
            size: 48,
          ),
          title: Text(issue ? 'Prescription Issued' : 'Draft Saved'),
          content: Text(
            issue
                ? 'Prescription ${prescription.prescriptionId} has been formally signed and issued. The patient can immediately access it in My Prescriptions.'
                : 'Prescription ${prescription.prescriptionId} saved as draft for future clinical review.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(); // dialog
                Navigator.of(context).pop(prescription); // screen
              },
              child: const Text('Return to Patient Profile'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving prescription: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActionable = _items.any((i) => i.isActionableRisk);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Create Prescription'),
        actions: [
          if (_items.isNotEmpty)
            TextButton.icon(
              onPressed: _isSaving ? null : () => _savePrescription(issue: false),
              icon: const Icon(Icons.bookmark_outline, size: 18),
              label: const Text('Save Draft'),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              // Patient Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      radius: 22,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.patient.name,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Patient ID: ${widget.patient.patientId}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'CPIC Monitored',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Actionable Safety Warning Banner if any high-risk medicine is added
              if (hasActionable) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.dangerRed.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppTheme.dangerRed, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Actionable Pharmacogenomic Alert',
                              style: GoogleFonts.inter(
                                color: AppTheme.dangerRed,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'One or more prescribed drugs are contraindicated by the patient’s genetic profile. Review CPIC guidance or switch to recommended alternative drugs below.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.dangerRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Medicines Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionHeader(
                    title: 'Prescribed Medications',
                    subtitle: 'Medicines checked dynamically against genes.',
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() => _showAddMedicineModal = true);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Drug'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Add Medicine Card / Modal
              if (_showAddMedicineModal) ...[
                _buildAddMedicineCard(theme),
                const SizedBox(height: 16),
              ],

              // Medication List
              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.medication_liquid_outlined,
                            size: 44, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text(
                          'No medicines added yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "+ Add Drug" to enter medications with instant genetic checks.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _buildMedicationItemCard(context, index, item);
                  },
                ),

              const SizedBox(height: 24),

              // Clinical Notes
              const SectionHeader(
                title: 'Clinical Instructions & Notes',
                subtitle: 'Directions for patient adherence.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. Take with full glass of water. Report unusual bruising or muscle aches.',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 32),

              // Bottom Action Buttons: Approve & Issue
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isSaving ? null : () => _savePrescription(issue: true),
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isSaving
                      ? 'Finalizing Prescription…'
                      : 'Approve & Issue Prescription',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isSaving ? null : () => _savePrescription(issue: false),
                child: const Text('Save as Draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddMedicineCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryEmerald, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Add Medication',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _showAddMedicineModal = false),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Autocomplete or Drug Name field
          Autocomplete<String>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return _cpicDrugs;
              }
              return _cpicDrugs.where((drug) => drug
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase()));
            },
            onSelected: (selection) {
              _medicineController.text = selection;
              _evaluateInputMedicine(selection);
            },
            fieldViewBuilder:
                (context, textController, focusNode, onFieldSubmitted) {
              return TextField(
                controller: textController,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: 'Medicine name (generic/brand)',
                  hintText: 'e.g. Clopidogrel, Warfarin, Simvastatin',
                  prefixIcon: Icon(Icons.medication),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  _medicineController.text = val;
                  _evaluateInputMedicine(val);
                },
              );
            },
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dosageController,
                  decoration: const InputDecoration(
                    labelText: 'Dosage',
                    hintText: 'e.g. 75 mg',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _frequencyController,
                  decoration: const InputDecoration(
                    labelText: 'Frequency',
                    hintText: 'e.g. Once daily',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _durationController,
            decoration: const InputDecoration(
              labelText: 'Duration',
              hintText: 'e.g. 30 days, Ongoing',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _instructionsController,
            decoration: const InputDecoration(
              labelText: 'Special instructions',
              hintText: 'e.g. Take with breakfast',
              border: OutlineInputBorder(),
            ),
          ),

          // Live PGx Preview card if evaluated
          if (_evaluatedPreview != null) ...[
            const SizedBox(height: 16),
            _buildLivePgxPreview(_evaluatedPreview!),
          ],

          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _addCurrentMedicine,
            icon: const Icon(Icons.check),
            label: const Text('Add to Prescription'),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePgxPreview(PrescriptionItem preview) {
    Color badgeColor = AppTheme.safeGreen;
    IconData icon = Icons.check_circle_outline;

    if (preview.isActionableRisk) {
      badgeColor = AppTheme.dangerRed;
      icon = Icons.cancel_outlined;
    } else if (preview.isCaution) {
      badgeColor = AppTheme.warningAmber;
      icon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: badgeColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Genetic Risk: ${preview.pgxRiskLabel}',
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (preview.gene != null)
                Text(
                  '${preview.gene}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (preview.recommendation != null) ...[
            const SizedBox(height: 6),
            Text(
              preview.recommendation!,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ],
          if (preview.alternativeDrugs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Guideline Alternatives: ${preview.alternativeDrugs.join(", ")}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryEmerald,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicationItemCard(
      BuildContext context, int index, PrescriptionItem item) {
    final theme = Theme.of(context);
    Color riskColor = AppTheme.safeGreen;
    if (item.isActionableRisk) {
      riskColor = AppTheme.dangerRed;
    } else if (item.isCaution) {
      riskColor = AppTheme.warningAmber;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isActionableRisk
              ? AppTheme.dangerRed.withValues(alpha: 0.6)
              : AppTheme.cardBorder,
          width: item.isActionableRisk ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.medicineName,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.dosage} · ${item.frequency} · ${item.duration}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  item.pgxRiskLabel,
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.dangerRed, size: 20),
                onPressed: () {
                  setState(() => _items.removeAt(index));
                },
              ),
            ],
          ),
          if (item.instructions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Instructions: ${item.instructions}',
              style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          if (item.recommendation != null && item.recommendation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'CPIC Note: ${item.recommendation}',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],

          // If actionable risk, present quick buttons to replace with guideline alternatives
          if (item.isActionableRisk && item.alternativeDrugs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Switch to:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryEmerald,
                  ),
                ),
                for (final alt in item.alternativeDrugs)
                  ActionChip(
                    avatar: const Icon(Icons.swap_horiz, size: 14),
                    label: Text(alt),
                    onPressed: () => _replaceItemWithAlternative(index, alt),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
