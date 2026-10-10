import 'package:flutter/material.dart';

import '../models/organization_patient.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class OrganizationPatientScreen extends StatefulWidget {
  const OrganizationPatientScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<OrganizationPatientScreen> createState() =>
      _OrganizationPatientScreenState();
}

class _OrganizationPatientScreenState extends State<OrganizationPatientScreen> {
  late Future<OrganizationPatient> _patient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _patient = FirebaseService.getOrganizationPatientWorkspace(
      widget.patientId,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Patient details')),
    body: FutureBuilder<OrganizationPatient>(
      future: _patient,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not load this patient record.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    FirebaseService.mapAuthError(snapshot.error!),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => setState(_load),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final patient = snapshot.data!;
        return _Workspace(patient: patient);
      },
    ),
  );
}

class _Workspace extends StatelessWidget {
  const _Workspace({required this.patient});

  final OrganizationPatient patient;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _PatientHeader(patient: patient),
      const SizedBox(height: 20),
      const SectionHeader(
        title: 'Record status',
        subtitle: 'Values returned by the authorized organization workspace.',
      ),
      _StatusCard(
        title: 'VCF file sharing',
        value: _label(patient.vcfStatus),
        icon: Icons.biotech_outlined,
      ),
      _StatusCard(
        title: 'Analysis',
        value: _label(patient.analysisStatus),
        icon: Icons.analytics_outlined,
      ),
      _StatusCard(
        title: 'Reports',
        value: patient.reportCount == null
            ? 'Not shared'
            : '${patient.reportCount} available',
        icon: Icons.description_outlined,
      ),
      _StatusCard(
        title: 'Prescriptions',
        value: patient.prescriptionCount == null
            ? 'Not synchronized'
            : '${patient.prescriptionCount} available',
        icon: Icons.medication_outlined,
      ),
      const SizedBox(height: 20),
      const SectionHeader(
        title: 'Patient actions',
        subtitle: 'Clinical workflows are not connected in this build.',
      ),
      const _UnavailableAction(
        icon: Icons.analytics_outlined,
        title: 'Generate Drug-Safety Report',
        description:
            'Not available until a validated rules engine and report-saving workflow are configured.',
      ),
      const _UnavailableAction(
        icon: Icons.medication_outlined,
        title: 'Create Prescription',
        description:
            'Prescription checks, clinician approval, and patient sharing are not available.',
      ),
      const SizedBox(height: 16),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.privacy_tip_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Genetic data remains on-device',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This workspace does not retrieve or upload raw VCF files, run cloud analysis, or claim that a report or prescription has been created. Counts above reflect only records actually returned by the backend.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ],
  );

  String _label(String status) => switch (status) {
    'not_shared' => 'Not shared',
    'not_available' => 'Not available',
    'not_uploaded' => 'Not available',
    'uploaded' => 'Uploaded',
    'processing' => 'Processing',
    'complete' => 'Complete',
    'failed' => 'Failed',
    'requires_review' => 'Requires review',
    'not_started' => 'Not started',
    _ => status.replaceAll('_', ' '),
  };
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
        const Icon(Icons.person_outline, color: Colors.white, size: 28),
        const SizedBox(height: 12),
        Text(
          patient.name,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Patient ID: ${patient.patientId}',
          style: const TextStyle(color: Colors.white),
        ),
        if (patient.birthYear != null)
          Text(
            'Birth year: ${patient.birthYear}',
            style: const TextStyle(color: Colors.white),
          ),
      ],
    ),
  );
}

class _UnavailableAction extends StatelessWidget {
  const _UnavailableAction({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(description),
      trailing: const PillBadge(
        label: 'Unavailable',
        color: AppTheme.unknownSlate,
      ),
      isThreeLine: true,
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(value),
    ),
  );
}
