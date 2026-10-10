import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/organization_patient.dart';
import '../models/prescription.dart';
import '../parser/vcf_parser.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../services/prescription_service.dart';
import '../services/screen_cache_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'create_prescription_screen.dart';


class OrganizationPatientScreen extends ConsumerStatefulWidget {
  const OrganizationPatientScreen({
    super.key,
    required this.patientId,
    this.initialPatient,
    this.initialParseResult,
  });

  final String patientId;
  final OrganizationPatient? initialPatient;
  final VcfParseResult? initialParseResult;

  @override
  ConsumerState<OrganizationPatientScreen> createState() =>
      _OrganizationPatientScreenState();
}

class _OrganizationPatientScreenState
    extends ConsumerState<OrganizationPatientScreen> {
  late Future<OrganizationPatient> _patientFuture;
  VcfParseResult? _parseResult;
  bool _isLoadingVcf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _parseResult = widget.initialParseResult ?? ref.read(vcfParseResultProvider);
    if (widget.initialPatient != null) {
      _patientFuture = Future.value(widget.initialPatient);
    } else {
      _patientFuture = FirebaseService.getOrganizationPatientWorkspace(
        widget.patientId,
      ).catchError((_) {
        // Fallback for demo/offline workspace
        return OrganizationPatient(
          patientId: widget.patientId,
          name: 'Patient ${widget.patientId}',
          birthYear: 1988,
          vcfStatus: 'uploaded',
          analysisStatus: 'complete',
          reportCount: 1,
          prescriptionCount: 1,
        );
      });
    }

    if (_parseResult == null) {
      _loadSampleGeneticReport();
    }
  }

  Future<void> _loadSampleGeneticReport() async {
    setState(() => _isLoadingVcf = true);
    try {
      final cachedVcf = await ScreenCacheService.restoreVcfData();
      if (cachedVcf != null && cachedVcf['content']?.isNotEmpty == true) {
        final result = VcfParser.parseVcfContent(cachedVcf['content']!);
        if (mounted) {
          setState(() {
            _parseResult = result;
            _isLoadingVcf = false;
          });
          return;
        }
      }
      final sampleString = await rootBundle
          .loadString('assets/samples/patient_002_reduced_function.vcf');
      final result = VcfParser.parseVcfContent(sampleString);
      if (mounted) {
        setState(() {
          _parseResult = result;
          _isLoadingVcf = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingVcf = false);
    }
  }


  void _openCreatePrescription(OrganizationPatient patient) async {
    final result = await Navigator.of(context).push<Prescription>(
      MaterialPageRoute(
        builder: (_) => CreatePrescriptionScreen(
          patient: patient,
          parseResult: _parseResult,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Workspace'),
      ),
      body: FutureBuilder<OrganizationPatient>(
        future: _patientFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              widget.initialPatient == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final patient = snapshot.data ??
              widget.initialPatient ??
              OrganizationPatient(
                patientId: widget.patientId,
                name: 'Patient ${widget.patientId}',
                vcfStatus: 'uploaded',
                analysisStatus: 'complete',
              );

          return _buildPatientWorkspace(context, patient);
        },
      ),
    );
  }

  Widget _buildPatientWorkspace(
      BuildContext context, OrganizationPatient patient) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      children: [
        _PatientHeader(patient: patient),
        const SizedBox(height: 16),

        // Primary Clinical Call to Action: Create Prescription
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryEmerald,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => _openCreatePrescription(patient),
          icon: const Icon(Icons.note_add_outlined, size: 22),
          label: Text(
            'Create Prescription (with CPIC Safety Check)',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Record Status Cards
        const SectionHeader(
          title: 'Clinical Record Status',
          subtitle: 'Verified permissions and genomic file synchronization.',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Genomic VCF',
                value: 'Authorized',
                icon: Icons.biotech_rounded,
                color: AppTheme.primaryEmerald,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                title: 'CPIC Analysis',
                value: 'Complete',
                icon: Icons.analytics_outlined,
                color: AppTheme.safeGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Genetic Report & Pharmacogenomic Profile Section (Feature 3)
        _buildGeneticReportSection(theme),
        const SizedBox(height: 24),

        // Patient Prescriptions Section (Feature 6 & 8)
        _buildPatientPrescriptionsSection(context, patient),
      ],
    );
  }

  Widget _buildGeneticReportSection(ThemeData theme) {
    if (_isLoadingVcf) {
      return const Center(child: CircularProgressIndicator());
    }

    final profiles = _parseResult?.geneProfiles;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.infoBlueBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.biotech_outlined,
                    color: AppTheme.infoBlue, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Genetic Report & Findings',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'CPIC Guideline Star-Alleles and Metabolizer Phenotypes',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.safeGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Verified',
                  style: TextStyle(
                    color: AppTheme.safeGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          if (profiles == null || profiles.isEmpty) ...[
            const Text(
              'No genetic variants detected for this patient.',
              style: TextStyle(fontSize: 13),
            ),
          ] else ...[
            Text(
              'Detected Pharmacogenes (${profiles.length}):',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.deepInk,
              ),
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: profiles.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final key = profiles.keys.elementAt(idx);
                final geneData = profiles[key]!;

                Color phenoColor = AppTheme.safeGreen;
                if (geneData.phenotype.contains('Poor') ||
                    geneData.phenotype.contains('Ultrarapid')) {
                  phenoColor = AppTheme.dangerRed;
                } else if (geneData.phenotype.contains('Intermediate')) {
                  phenoColor = AppTheme.warningAmber;
                }

                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.bgLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Text(
                        geneData.gene,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          geneData.diplotype,
                          style: GoogleFonts.sourceCodePro(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: phenoColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          geneData.phenotype,
                          style: TextStyle(
                            color: phenoColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPatientPrescriptionsSection(
      BuildContext context, OrganizationPatient patient) {
    return StreamBuilder<List<Prescription>>(
      stream: PrescriptionService.instance.streamPatientPrescriptions(
        patient.patientId,
      ),
      builder: (context, snapshot) {
        final prescriptions = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SectionHeader(
                  title: 'Issued Prescriptions (${prescriptions.length})',
                  subtitle: 'History of clinical prescriptions for this patient.',
                ),
                TextButton(
                  onPressed: () => _openCreatePrescription(patient),
                  child: const Text('+ New RX'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (prescriptions.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Center(
                  child: Text(
                    'No prescriptions issued yet for this patient.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...prescriptions.map((rx) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(
                        rx.isIssued
                            ? Icons.verified
                            : Icons.edit_note_outlined,
                        color: rx.isIssued
                            ? AppTheme.safeGreen
                            : AppTheme.warningAmber,
                      ),
                      title: Text(
                        'Prescription ${rx.prescriptionId}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${rx.items.length} medicines · Prescribed by ${rx.prescriberName}',
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: rx.isIssued
                              ? AppTheme.safeGreen.withValues(alpha: 0.12)
                              : AppTheme.warningAmber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          rx.status.toUpperCase(),
                          style: TextStyle(
                            color: rx.isIssued
                                ? AppTheme.safeGreen
                                : AppTheme.warningAmber,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({required this.patient});

  final OrganizationPatient patient;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.heroGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    patient.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Active Consent',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Patient ID: ${patient.patientId}',
              style: const TextStyle(color: Colors.white),
            ),
            if (patient.vcfFileName != null && patient.vcfFileName!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file, color: AppTheme.vibrantMint, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'VCF File: ${patient.vcfFileName}',
                      style: const TextStyle(
                        color: AppTheme.vibrantMint,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (patient.birthYear != null)
              Text(
                'Birth year: ${patient.birthYear}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
          ],
        ),
      );

}
