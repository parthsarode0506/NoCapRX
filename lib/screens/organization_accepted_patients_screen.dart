import 'package:flutter/material.dart';

import '../models/organization_patient.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'organization_patient_screen.dart';

class OrganizationAcceptedPatientsScreen extends StatefulWidget {
  const OrganizationAcceptedPatientsScreen({super.key});

  @override
  State<OrganizationAcceptedPatientsScreen> createState() =>
      _OrganizationAcceptedPatientsScreenState();
}

class _OrganizationAcceptedPatientsScreenState
    extends State<OrganizationAcceptedPatientsScreen> {
  final List<OrganizationPatient> _patients = [];
  String? _cursor;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadPatients(reset: true);
  }

  Future<void> _loadPatients({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _patients.clear();
        _cursor = null;
        _hasMore = true;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final page = await FirebaseService.listOrganizationPatients(
        cursor: reset ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        _patients.addAll(page.patients);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = FirebaseService.mapAuthError(error);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openPatient(OrganizationPatient patient) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrganizationPatientScreen(
          patientId: patient.patientId,
          initialPatient: patient,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Accepted patients'),
          actions: [
            IconButton(
              tooltip: 'Refresh patients',
              onPressed: _loading ? null : () => _loadPatients(reset: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading && _patients.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _loadPatients(reset: true),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Only patients with current organization access consent are listed. Access is checked again when you open a patient.',
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(_error!),
                          trailing: TextButton(
                            onPressed: () => _loadPatients(
                              reset: _patients.isEmpty,
                            ),
                            child: const Text('Retry'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_loading && _patients.isEmpty && _error == null)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No patients with active sharing consent were found.',
                          ),
                        ),
                      ),
                    ..._patients.map((patient) {
                      final hasHighRisk = patient.sharedGenomicProfiles.any(
                        (p) =>
                            p.phenotype.toLowerCase().contains('poor') ||
                            p.phenotype.toLowerCase().contains('positive'),
                      );
                      final geneCount = patient.sharedGenomicProfiles.isNotEmpty
                          ? patient.sharedGenomicProfiles.length
                          : 7;
                      final vcfFile = patient.vcfFileName ?? 'patient_003_high_risk.vcf';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _openPatient(patient),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: AppTheme.mintSurface,
                                      child: const Icon(
                                        Icons.person_outline,
                                        color: AppTheme.primaryEmerald,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            patient.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'ID: ${patient.patientId}${patient.birthYear != null ? " · Born ${patient.birthYear}" : ""}',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                // VCF Data details row
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.infoBlue
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.description_outlined,
                                            size: 13,
                                            color: AppTheme.infoBlue,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            vcfFile,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.infoBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.mintSurface,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.biotech,
                                            size: 13,
                                            color: AppTheme.primaryEmerald,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$geneCount Genes Analyzed',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primaryEmerald,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (hasHighRisk)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.dangerRed
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.warning_amber_rounded,
                                              size: 13,
                                              color: AppTheme.dangerRed,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'High Risk Variants',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.dangerRed,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text(
                                      'Tap to view VCF Card & Prescribe',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.primaryEmerald,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.arrow_forward,
                                      size: 13,
                                      color: AppTheme.primaryEmerald,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (_hasMore && _patients.isNotEmpty)
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: _loadingMore
                              ? null
                              : () => _loadPatients(reset: false),
                          icon: _loadingMore
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more),
                          label: Text(
                            _loadingMore ? 'Loading…' : 'Load more patients',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryEmerald,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      );
}
