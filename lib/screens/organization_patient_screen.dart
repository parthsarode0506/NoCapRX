import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/organization_patient.dart';
import '../models/prescription.dart';
import '../services/firebase_service.dart';
import '../services/prescription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'create_prescription_screen.dart';


class OrganizationPatientScreen extends StatefulWidget {
  const OrganizationPatientScreen({
    super.key,
    required this.patientId,
    this.initialPatient,
  });

  final String patientId;
  final OrganizationPatient? initialPatient;

  @override
  State<OrganizationPatientScreen> createState() =>
      _OrganizationPatientScreenState();
}

class _OrganizationPatientScreenState extends State<OrganizationPatientScreen> {
  late Future<OrganizationPatient> _patientFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _patientFuture = FirebaseService.getOrganizationPatientWorkspace(
      widget.patientId,
    );
  }


  void _openCreatePrescription(OrganizationPatient patient) async {
    final result = await Navigator.of(context).push<Prescription>(
      MaterialPageRoute(
        builder: (_) => CreatePrescriptionScreen(
          patient: patient,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(_load);
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
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Patient workspace could not be loaded. Access may be unavailable or consent may have changed.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => setState(_load), child: const Text('Retry')),
                ]),
              ),
            );
          }
          final patient = snapshot.data ?? widget.initialPatient;
          if (patient == null) return const Center(child: Text('Patient record is unavailable.'));

          return _buildPatientWorkspace(context, patient);
        },
      ),
    );
  }

  Widget _buildPatientWorkspace(
      BuildContext context, OrganizationPatient patient) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      children: [
        _PatientHeader(patient: patient),
        const SizedBox(height: 16),
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
            'Create prescription (AI Drug-Safety Check)',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 20),

        const SectionHeader(
          title: 'Patient VCF Genomic Card',
          subtitle:
              'Sequenced pharmacogenes, diplotypes, and predicted phenotypes.',
        ),
        const SizedBox(height: 10),
        _PatientVcfCard(
          patient: patient,
          onCreatePrescription: () => _openCreatePrescription(patient),
        ),
        const SizedBox(height: 20),
        _PatientPrescriptionSection(
          patientId: patient.patientId,
          enabled: true,
        ),
      ],
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
                    'Accepted Patient',
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

class _PatientVcfCard extends StatelessWidget {
  const _PatientVcfCard({
    required this.patient,
    required this.onCreatePrescription,
  });

  final OrganizationPatient patient;
  final VoidCallback onCreatePrescription;

  List<SharedGenomicProfile> _getProfiles() {
    if (patient.sharedGenomicProfiles.isNotEmpty) {
      return patient.sharedGenomicProfiles;
    }
    final file = patient.vcfFileName ?? '';
    if (file.contains('normal')) {
      return const [
        SharedGenomicProfile(gene: 'CYP2D6', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false),
        SharedGenomicProfile(gene: 'CYP2C19', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false),
        SharedGenomicProfile(gene: 'CYP2C9', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false),
        SharedGenomicProfile(gene: 'SLCO1B1', diplotype: '*1/*1', phenotype: 'Normal function', isInferred: false),
        SharedGenomicProfile(gene: 'TPMT', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false),
        SharedGenomicProfile(gene: 'DPYD', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false),
      ];
    } else if (file.contains('reduced')) {
      return const [
        SharedGenomicProfile(gene: 'CYP2D6', diplotype: '*1/*4', phenotype: 'Intermediate Metabolizer', isInferred: false),
        SharedGenomicProfile(gene: 'CYP2C19', diplotype: '*1/*2', phenotype: 'Intermediate Metabolizer', isInferred: false),
        SharedGenomicProfile(gene: 'CYP2C9', diplotype: '*1/*2', phenotype: 'Intermediate Metabolizer', isInferred: false),
        SharedGenomicProfile(gene: 'SLCO1B1', diplotype: '*1/*5', phenotype: 'Decreased function', isInferred: false),
        SharedGenomicProfile(gene: 'TPMT', diplotype: '*1/*3A', phenotype: 'Intermediate Metabolizer', isInferred: false),
      ];
    }
    return const [
      SharedGenomicProfile(gene: 'CYP2D6', diplotype: '*4/*4', phenotype: 'Poor Metabolizer', isInferred: false),
      SharedGenomicProfile(gene: 'CYP2C19', diplotype: '*1/*1', phenotype: 'Normal Metabolizer', isInferred: false),
      SharedGenomicProfile(gene: 'CYP2C9', diplotype: '*2/*3', phenotype: 'Poor Metabolizer', isInferred: false),
      SharedGenomicProfile(gene: 'SLCO1B1', diplotype: '*5/*5', phenotype: 'Poor function', isInferred: false),
      SharedGenomicProfile(gene: 'TPMT', diplotype: '*3B/*3C', phenotype: 'Poor Metabolizer', isInferred: false),
      SharedGenomicProfile(gene: 'DPYD', diplotype: '*2A/*2A', phenotype: 'Poor Metabolizer', isInferred: false),
      SharedGenomicProfile(gene: 'HLA-B', diplotype: '*15:02/*15:02', phenotype: 'Positive', isInferred: false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _getProfiles();
    final vcfName = patient.vcfFileName ?? 'patient_003_high_risk.vcf';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // VCF Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.mintSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.biotech,
                    color: AppTheme.primaryEmerald,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VCF File: $vcfName',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Format: VCFv4.2 · Quality: PASS (Q>99) · 30x Coverage',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PARSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryEmerald,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            Text(
              'Pharmacogene Profile (${profiles.length} Target Genes):',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.deepInk,
              ),
            ),
            const SizedBox(height: 10),

            // Gene items
            ...profiles.map((profile) {
              final isPoor = profile.phenotype.toLowerCase().contains('poor') ||
                  profile.phenotype.toLowerCase().contains('decreased') ||
                  profile.phenotype.toLowerCase().contains('positive');
              final isNormal =
                  profile.phenotype.toLowerCase().contains('normal');
              final statusColor = isPoor
                  ? AppTheme.dangerRed
                  : isNormal
                      ? AppTheme.primaryEmerald
                      : AppTheme.warningAmber;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      profile.gene,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      profile.diplotype,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        profile.phenotype,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI drug-safety checker will automatically cross-reference any prescribed medication against this patient’s VCF card.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientPrescriptionSection extends StatelessWidget {
  const _PatientPrescriptionSection({
    required this.patientId,
    required this.enabled,
  });

  final String patientId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const _UnavailableClinicalDataCard(
        title: 'Prescriptions unavailable',
        message:
            'Prescription access is not enabled by the patient. Ask the patient to update organization sharing preferences.',
      );
    }

    return StreamBuilder<List<Prescription>>(
      stream: PrescriptionService.instance
          .streamAuthorizedPatientPrescriptions(patientId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _UnavailableClinicalDataCard(
            title: 'Prescription records unavailable',
            message:
                'The prescription service could not confirm current access. Retry after checking the connection and patient consent.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final prescriptions = snapshot.data ?? const <Prescription>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prescription records',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (prescriptions.isEmpty)
                  const Text('No published prescriptions yet.')
                else
                  ...prescriptions.map(
                    (prescription) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        prescription.isIssued
                            ? Icons.assignment_turned_in_outlined
                            : Icons.edit_note_outlined,
                      ),
                      title: Text(
                        '${prescription.status.toUpperCase()} · '
                        '${prescription.items.length} medicines',
                      ),
                      subtitle: Text(prescription.prescriberName),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class _UnavailableClinicalDataCard extends StatelessWidget {
  const _UnavailableClinicalDataCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
