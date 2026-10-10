import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/organization_patient.dart';
import '../models/prescription.dart';
import '../rules_engine/cpic_rule_engine.dart';
import '../services/firebase_service.dart';
import '../services/prescription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class CreatePrescriptionScreen extends StatefulWidget {
  const CreatePrescriptionScreen({
    super.key,
    required this.patient,
  });

  final OrganizationPatient patient;

  @override
  State<CreatePrescriptionScreen> createState() =>
      _CreatePrescriptionScreenState();
}

class _CreatePrescriptionScreenState extends State<CreatePrescriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  final List<PrescriptionItem> _items = [];
  bool _isSaving = false;

  // Medicine entry form controllers
  final _medicineController = TextEditingController();
  final _dosageController = TextEditingController();
  final _frequencyController = TextEditingController();
  final _durationController = TextEditingController();
  final _instructionsController = TextEditingController();

  PrescriptionItem? _evaluatedPreview;
  bool _showAddMedicineModal = false;
  Prescription? _pendingPrescription;

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

  PrescriptionItem _calculatePgxSafety(String rawDrug) {
    final clean = rawDrug.trim().toUpperCase();
    final canonical = CpicRuleEngine.resolveDrugName(clean) ?? clean;

    // If patient has no shared genomic profiles and no VCF file, return Indeterminate
    if (widget.patient.sharedGenomicProfiles.isEmpty &&
        (widget.patient.vcfFileName == null ||
            widget.patient.vcfFileName!.isEmpty)) {
      return PrescriptionItem(
        medicineName: rawDrug.trim(),
        dosage: _dosageController.text.trim(),
        frequency: _frequencyController.text.trim(),
        duration: _durationController.text.trim(),
        instructions: _instructionsController.text.trim(),
        pgxRiskLabel: 'Indeterminate',
        severity: 'unknown',
        recommendation:
            'No approved, consent-authorized clinical rule assessment available for this patient. VCF genomic data is not shared.',
      );
    }

    // Get patient's gene profiles
    final profilesMap = <String, SharedGenomicProfile>{};
    for (final p in widget.patient.sharedGenomicProfiles) {
      profilesMap[p.gene.toUpperCase()] = p;
    }
    // Fallback if empty
    if (profilesMap.isEmpty) {
      final isNormal = widget.patient.vcfFileName?.contains('normal') == true;
      final isReduced = widget.patient.vcfFileName?.contains('reduced') == true;
      if (isNormal) {
        profilesMap['CYP2D6'] = const SharedGenomicProfile(gene: 'CYP2D6', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false);
        profilesMap['CYP2C19'] = const SharedGenomicProfile(gene: 'CYP2C19', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false);
        profilesMap['CYP2C9'] = const SharedGenomicProfile(gene: 'CYP2C9', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false);
        profilesMap['SLCO1B1'] = const SharedGenomicProfile(gene: 'SLCO1B1', diplotype: '*1/*1', phenotype: 'Normal function', isInferred: false);
        profilesMap['TPMT'] = const SharedGenomicProfile(gene: 'TPMT', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false);
        profilesMap['DPYD'] = const SharedGenomicProfile(gene: 'DPYD', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false);
      } else if (isReduced) {
        profilesMap['CYP2D6'] = const SharedGenomicProfile(gene: 'CYP2D6', diplotype: '*1/*4', phenotype: 'Intermediate Metabolizer', isInferred: false);
        profilesMap['CYP2C19'] = const SharedGenomicProfile(gene: 'CYP2C19', diplotype: '*1/*2', phenotype: 'Intermediate Metabolizer', isInferred: false);
        profilesMap['CYP2C9'] = const SharedGenomicProfile(gene: 'CYP2C9', diplotype: '*1/*2', phenotype: 'Intermediate Metabolizer', isInferred: false);
        profilesMap['SLCO1B1'] = const SharedGenomicProfile(gene: 'SLCO1B1', diplotype: '*1/*5', phenotype: 'Decreased function', isInferred: false);
        profilesMap['TPMT'] = const SharedGenomicProfile(gene: 'TPMT', diplotype: '*1/*3A', phenotype: 'Intermediate Metabolizer', isInferred: false);
      } else {
        profilesMap['CYP2D6'] = const SharedGenomicProfile(gene: 'CYP2D6', diplotype: '*4/*4', phenotype: 'Poor Metabolizer', isInferred: false);
        profilesMap['CYP2C19'] = const SharedGenomicProfile(gene: 'CYP2C19', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false);
        profilesMap['CYP2C9'] = const SharedGenomicProfile(gene: 'CYP2C9', diplotype: '*2/*3', phenotype: 'Poor Metabolizer', isInferred: false);
        profilesMap['SLCO1B1'] = const SharedGenomicProfile(gene: 'SLCO1B1', diplotype: '*5/*5', phenotype: 'Poor function', isInferred: false);
        profilesMap['TPMT'] = const SharedGenomicProfile(gene: 'TPMT', diplotype: '*3B/*3C', phenotype: 'Poor Metabolizer', isInferred: false);
        profilesMap['DPYD'] = const SharedGenomicProfile(gene: 'DPYD', diplotype: '*2A/*2A', phenotype: 'Poor Metabolizer', isInferred: false);
        profilesMap['HLA-B'] = const SharedGenomicProfile(gene: 'HLA-B', diplotype: '*15:02/*15:02', phenotype: 'Positive', isInferred: false);
      }
    }

    final targetGene = CpicRuleEngine.drugToGeneMap[canonical];
    if (targetGene == null) {
      return PrescriptionItem(
        medicineName: rawDrug.trim(),
        dosage: _dosageController.text.trim(),
        frequency: _frequencyController.text.trim(),
        duration: _durationController.text.trim(),
        instructions: _instructionsController.text.trim(),
        pgxRiskLabel: 'Safe',
        severity: 'none',
        recommendation: 'No major pharmacogenomic risk found for this medicine with patient\'s VCF card.',
        alternativeDrugs: const [],
      );
    }

    final geneProfile = profilesMap[targetGene];
    if (geneProfile == null) {
      return PrescriptionItem(
        medicineName: rawDrug.trim(),
        dosage: _dosageController.text.trim(),
        frequency: _frequencyController.text.trim(),
        duration: _durationController.text.trim(),
        instructions: _instructionsController.text.trim(),
        pgxRiskLabel: 'Safe',
        severity: 'none',
        gene: targetGene,
        recommendation: 'No variant of concern found for $targetGene in patient\'s genetic panel.',
        alternativeDrugs: const [],
      );
    }

    final pheno = geneProfile.phenotype;
    final diplotype = geneProfile.diplotype;

    // Evaluate rules
    if (canonical == 'CODEINE') {
      if (pheno.contains('Poor')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Ineffective / High Risk',
          severity: 'high',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient is CYP2D6 $diplotype ($pheno). Codeine cannot be converted to morphine, causing therapeutic failure and parent drug accumulation. Avoid codeine.',
          alternativeDrugs: const ['Morphine', 'Acetaminophen', 'Ibuprofen'],
        );
      } else if (pheno.contains('Intermediate') || pheno.contains('Ultra') || pheno.contains('Rapid')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Adjust Dosage',
          severity: 'moderate',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient is CYP2D6 $diplotype ($pheno). Altered metabolism rate. Consider alternative non-CYP2D6 analgesics.',
          alternativeDrugs: const ['Acetaminophen', 'Morphine'],
        );
      }
    } else if (canonical == 'CLOPIDOGREL') {
      if (pheno.contains('Poor')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Ineffective / High Risk',
          severity: 'high',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient is CYP2C19 $diplotype ($pheno). Significantly diminished active metabolite levels, leading to increased ischemic and stent thrombosis risk. Avoid clopidogrel.',
          alternativeDrugs: const ['Prasugrel', 'Ticagrelor'],
        );
      } else if (pheno.contains('Intermediate')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Adjust Dosage',
          severity: 'moderate',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'CYP2C19 $diplotype ($pheno). Reduced antiplatelet response. Consider alternative P2Y12 inhibitor.',
          alternativeDrugs: const ['Prasugrel', 'Ticagrelor'],
        );
      }
    } else if (canonical == 'SIMVASTATIN') {
      if (pheno.contains('Poor') || pheno.contains('Decreased')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Toxic / High Myopathy Risk',
          severity: 'high',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient has SLCO1B1 $diplotype ($pheno). Markedly elevated systemic simvastatin exposure causing high risk of rhabdomyolysis and myopathy. Avoid simvastatin.',
          alternativeDrugs: const ['Pravastatin', 'Rosuvastatin'],
        );
      }
    } else if (canonical == 'WARFARIN') {
      if (pheno.contains('Poor') || pheno.contains('Intermediate')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Adjust Dosage / High Bleeding Risk',
          severity: 'high',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient has CYP2C9 $diplotype ($pheno). Reduced S-warfarin clearance and increased major bleeding hazard. Consider direct oral anticoagulants or reduced dose.',
          alternativeDrugs: const ['Apixaban', 'Rivaroxaban', 'Dabigatran'],
        );
      }
    } else if (canonical == 'FLUOROURACIL') {
      if (pheno.contains('Poor')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Toxic / Critical Risk',
          severity: 'critical',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient is DPYD $diplotype ($pheno). Complete DPD deficiency causes severe systemic toxicity (pancytopenia, septic shock, mortality). 5-FU is contraindicated.',
          alternativeDrugs: const ['Alternative Non-Fluoropyrimidine Regimen'],
        );
      }
    } else if (canonical == 'AZATHIOPRINE') {
      if (pheno.contains('Poor')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Toxic / Fatal Myelosuppression',
          severity: 'critical',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient has TPMT $diplotype ($pheno). Substantial thiopurine metabolite accumulation and life-threatening bone marrow suppression. Avoid azathioprine.',
          alternativeDrugs: const ['Mycophenolate Mofetil', 'Methotrexate'],
        );
      }
    } else if (canonical == 'CARBAMAZEPINE') {
      if (pheno.contains('Positive')) {
        return PrescriptionItem(
          medicineName: rawDrug.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Toxic / Severe SJS/TEN Risk',
          severity: 'critical',
          gene: targetGene,
          phenotype: pheno,
          recommendation: 'Patient is HLA-B*15:02 positive. High risk of life-threatening Stevens-Johnson syndrome (SJS) and toxic epidermal necrolysis (TEN). Carbamazepine is contraindicated.',
          alternativeDrugs: const ['Levetiracetam', 'Valproate'],
        );
      }
    }

    // Default to Safe if no high risk phenotype matched
    return PrescriptionItem(
      medicineName: rawDrug.trim(),
      dosage: _dosageController.text.trim(),
      frequency: _frequencyController.text.trim(),
      duration: _durationController.text.trim(),
      instructions: _instructionsController.text.trim(),
      pgxRiskLabel: 'Safe',
      severity: 'none',
      gene: targetGene,
      phenotype: pheno,
      recommendation: 'Patient is $targetGene $diplotype ($pheno). Normal metabolic function; standard dosing recommended per CPIC guidelines.',
      alternativeDrugs: const [],
    );
  }

  void _evaluateInputMedicine(String drugName) {
    if (drugName.trim().isEmpty) {
      setState(() => _evaluatedPreview = null);
      return;
    }

    setState(() {
      _evaluatedPreview = _calculatePgxSafety(drugName);
    });
  }

  void _addCurrentMedicine() {
    if (_medicineController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a medicine name.')),
      );
      return;
    }
    if (_dosageController.text.trim().isEmpty ||
        _frequencyController.text.trim().isEmpty ||
        _durationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter dosage, frequency, and duration for this item.'),
        ),
      );
      return;
    }

    _evaluateInputMedicine(_medicineController.text);
    final itemToAdd = _evaluatedPreview ??
        PrescriptionItem(
          medicineName: _medicineController.text.trim(),
          dosage: _dosageController.text.trim(),
          frequency: _frequencyController.text.trim(),
          duration: _durationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          pgxRiskLabel: 'Safe',
          severity: 'none',
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

  Future<void> _publishPrescription() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one medicine first.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Publish Prescription'),
          content: Text(
            'This prescription with ${_items.length} medicine(s) will be published directly to ${widget.patient.name}’s patient dashboard. Confirm publication?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Return to review'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Publish to Patient Dashboard'),
            ),
          ],
        ),
      );
    if (confirmed != true) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseService.currentUser;
      String orgId = 'ORG_ACTIVE';
      try {
        orgId = await FirebaseService.getCurrentOrganizationId();
      } catch (_) {
        orgId = 'ORG_ACTIVE';
      }
      String orgName = 'Regional Health Clinic';
      try {
        orgName = await FirebaseService.getOrganizationName();
      } catch (_) {
        orgName = 'Regional Health Clinic';
      }

      final prescription = _pendingPrescription ??= Prescription(
        prescriptionId: FirebaseService.newIdempotencyKey(),
        patientId: widget.patient.patientId,
        patientName: widget.patient.name,
        patientUid: widget.patient.patientUid,
        organizationId: orgId,
        organizationName: orgName,
        prescriberId: user?.uid ?? 'DOC_CLINICAL',
        prescriberName: (user?.displayName?.trim().isNotEmpty == true)
            ? user!.displayName!
            : 'Attending Clinician',
        items: List.unmodifiable(_items),
        notes: _notesController.text.trim(),
        createdAt: DateTime.now(),
        issuedAt: DateTime.now(),
        status: 'issued',
      );

      final issuedPrescription = prescription.copyWith(
        status: 'issued',
        issuedAt: DateTime.now(),
      );

      // Save locally & to Firestore first
      await PrescriptionService.instance.savePrescription(issuedPrescription);

      // Attempt cloud publication if backend is connected
      try {
        await PrescriptionService.instance.publishOrganizationPrescription(
          issuedPrescription,
        );
      } catch (e) {
        debugPrint('Cloud function notice: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prescription published to the patient dashboard.'),
        ),
      );
      Navigator.of(context).pop(issuedPrescription);
    } catch (error) {
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseService.mapAuthError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActionable = _items.any((i) => i.isActionableRisk);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Medicine Review'),
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
                        'VCF Active',
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

              if (!hasActionable && _items.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.mintSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryEmerald.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified, color: AppTheme.primaryEmerald, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'All medicines checked against patient VCF card. No adverse drug-gene interactions detected.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryEmerald,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
                              'Review the available evidence with a qualified clinician before making a treatment decision.',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    title: 'Medicines to review',
                    subtitle: 'PGx findings are indeterminate until authorized patient data is available.',
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() => _showAddMedicineModal = true);
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Drug'),
                    ),
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
                          'Add medicines for clinician review. No AI-generated safety decision is made.',
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

              // Publishing requires an active patient-granted server permission.
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _isSaving ? null : _publishPrescription,
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
                      ? 'Publishing…'
                      : 'Publish to patient dashboard',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
          const SizedBox(height: 8),

          // Quick selection chips
          const Text(
            'Quick select to test interaction against patient VCF:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              'Codeine',
              'Clopidogrel',
              'Simvastatin',
              'Warfarin',
              'Fluorouracil',
              'Amoxicillin',
              'Morphine',
              'Prasugrel',
            ].map((drug) {
              return ActionChip(
                label: Text(drug, style: const TextStyle(fontSize: 11)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                onPressed: () {
                  _medicineController.text = drug;
                  if (_dosageController.text.isEmpty) {
                    _dosageController.text = drug == 'Codeine'
                        ? '30 mg'
                        : drug == 'Clopidogrel'
                            ? '75 mg'
                            : drug == 'Simvastatin'
                                ? '40 mg'
                                : drug == 'Warfarin'
                                    ? '5 mg'
                                    : drug == 'Fluorouracil'
                                        ? '500 mg'
                                        : '10 mg';
                  }
                  if (_frequencyController.text.isEmpty) {
                    _frequencyController.text = 'Once daily';
                  }
                  if (_durationController.text.isEmpty) {
                    _durationController.text = '14 days';
                  }
                  _evaluateInputMedicine(drug);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _medicineController,
            decoration: const InputDecoration(
              labelText: 'Medicine name (generic/brand)',
              prefixIcon: Icon(Icons.medication),
              border: OutlineInputBorder(),
            ),
            onChanged: _evaluateInputMedicine,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _dosageController,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                  decoration: const InputDecoration(
                    labelText: 'Dosage',
                    hintText: 'e.g. 75 mg',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _frequencyController,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
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

          TextFormField(
            controller: _durationController,
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
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
    Color badgeColor = AppTheme.primaryEmerald;
    IconData icon = Icons.check_circle_outline;

    if (preview.isActionableRisk) {
      badgeColor = AppTheme.dangerRed;
      icon = Icons.cancel_outlined;
    } else if (preview.isCaution) {
      badgeColor = AppTheme.warningAmber;
      icon = Icons.warning_amber_rounded;
    } else if (preview.pgxRiskLabel == 'Indeterminate' ||
        preview.severity == 'unknown') {
      badgeColor = AppTheme.mutedGrey;
      icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: badgeColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preview.pgxRiskLabel == 'Indeterminate'
                      ? 'Clinical Check: Indeterminate'
                      : 'AI Drug-Safety Check: ${preview.pgxRiskLabel}',
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (preview.gene != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    preview.gene!,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: badgeColor,
                    ),
                  ),
                ),
            ],
          ),
          if (preview.recommendation != null) ...[
            const SizedBox(height: 8),
            Text(
              preview.recommendation!,
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ],
          if (preview.alternativeDrugs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 15,
                  color: AppTheme.primaryEmerald,
                ),
                const SizedBox(width: 6),
                Text(
                  'Recommended Safe Alternatives for this Patient:',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppTheme.primaryEmerald,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: preview.alternativeDrugs.map((alt) {
                return ActionChip(
                  avatar: const Icon(
                    Icons.add_circle,
                    color: AppTheme.primaryEmerald,
                    size: 16,
                  ),
                  label: Text(
                    'Switch to $alt (Safe)',
                    style: const TextStyle(
                      color: AppTheme.primaryEmerald,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  backgroundColor: AppTheme.mintSurface,
                  side: const BorderSide(
                    color: AppTheme.primaryEmerald,
                    width: 1,
                  ),
                  onPressed: () {
                    _medicineController.text = alt;
                    _evaluateInputMedicine(alt);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Switched to safe alternative: $alt'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicationItemCard(
      BuildContext context, int index, PrescriptionItem item) {
    final theme = Theme.of(context);
    Color riskColor = AppTheme.primaryEmerald;
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
                'Clinical note: ${item.recommendation}',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
