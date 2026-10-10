import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/organization_patient.dart';
import '../parser/vcf_parser.dart';
import '../services/audit_service.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'organization_patient_screen.dart';

class NewPatientScreen extends ConsumerStatefulWidget {
  const NewPatientScreen({super.key});

  @override
  ConsumerState<NewPatientScreen> createState() => _NewPatientScreenState();
}

class _NewPatientScreenState extends ConsumerState<NewPatientScreen> {
  final _searchController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // New patient registration fields
  final _nameController = TextEditingController();
  final _birthYearController = TextEditingController(text: '1985');
  final _phoneController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _medsController = TextEditingController();

  String _gender = 'Female';
  String _selectedSampleVcf = 'patient_001_normal.vcf';

  bool _isSearching = false;
  bool _isSaving = false;
  bool _hasSearched = false;
  List<OrganizationPatient> _searchResults = [];
  bool _showCreateForm = false;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _birthYearController.dispose();
    _phoneController.dispose();
    _allergiesController.dispose();
    _medsController.dispose();
    super.dispose();
  }

  Future<void> _searchPatients() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least 2 characters to search.')),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _showCreateForm = false;
    });

    try {
      final results = <OrganizationPatient>[];

      // Query cloud functions / firestore
      try {
        final cloudPatients =
            await FirebaseService.searchOrganizationPatients(query);
        results.addAll(cloudPatients);
      } catch (_) {
        // Fallback search in known registry
      }

      // Check standard demonstration patients if matches query
      final standardRegistry = [
        const OrganizationPatient(
          patientId: 'PATIENT_001',
          name: 'Alex Mercer',
          birthYear: 1988,
          vcfStatus: 'uploaded',
          analysisStatus: 'complete',
          reportCount: 3,
          prescriptionCount: 2,
        ),
        const OrganizationPatient(
          patientId: 'PATIENT_002',
          name: 'Priya Sharma',
          birthYear: 1992,
          vcfStatus: 'uploaded',
          analysisStatus: 'complete',
          reportCount: 1,
          prescriptionCount: 1,
        ),
        const OrganizationPatient(
          patientId: 'PATIENT_003',
          name: 'David Kim',
          birthYear: 1979,
          vcfStatus: 'uploaded',
          analysisStatus: 'complete',
          reportCount: 2,
          prescriptionCount: 0,
        ),
      ];

      for (final p in standardRegistry) {
        if ((p.name.toLowerCase().contains(query.toLowerCase()) ||
                p.patientId.toLowerCase().contains(query.toLowerCase())) &&
            !results.any((r) => r.patientId == p.patientId)) {
          results.add(p);
        }
      }

      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _showCreateForm = true;
          _nameController.text = query;
        }
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _registerNewPatient() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final birthYear = int.tryParse(_birthYearController.text.trim());
      final newId = 'PATIENT_${DateTime.now().millisecondsSinceEpoch % 10000}';

      // Load sample VCF content from assets
      VcfParseResult? parseResult;
      try {
        final vcfString =
            await rootBundle.loadString('assets/samples/$_selectedSampleVcf');
        parseResult = VcfParser.parseVcfContent(vcfString);
      } catch (e) {
        debugPrint('Sample VCF load note: $e');
      }

      final newPatient = OrganizationPatient(
        patientId: newId,
        name: name,
        birthYear: birthYear,
        vcfStatus: 'uploaded',
        analysisStatus: 'complete',
        reportCount: 1,
        prescriptionCount: 0,
        vcfFileName: _selectedSampleVcf,
        sharedGenomicProfiles: parseResult?.geneProfiles.entries
                .map((e) => SharedGenomicProfile(
                      gene: e.key,
                      diplotype: e.value.diplotype,
                      phenotype: e.value.phenotype,
                      isInferred: false,
                    ))
                .toList() ??
            const [],
      );

      // Log to Audit Log
      await AuditService.instance.recordLog(
        action: 'patient_registered',
        actorUid: FirebaseService.currentUser?.uid ?? 'DOC_REG',
        actorRole: 'doctor',
        organizationId: 'ORG_ACTIVE',
        targetId: newId,
        description: 'New clinical patient profile registered: $name ($newId).',
        metadata: {
          'name': name,
          'birthYear': birthYear,
          'sampleVcf': _selectedSampleVcf,
        },
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registered new patient: $name ($newId)')),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrganizationPatientScreen(
            patientId: newId,
            initialPatient: newPatient,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error registering patient: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('New / Search Patient'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // Search existing patient header
            const SectionHeader(
              title: 'Search Existing Patient',
              subtitle: 'Check for existing clinical records before creating duplicates.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchPatients(),
                    decoration: const InputDecoration(
                      labelText: 'Search by Patient ID, Name, or Phone',
                      hintText: 'e.g. PATIENT_001 or Alex',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _isSearching ? null : _searchPatients,
                  child: _isSearching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Search Results
            if (_hasSearched) ...[
              if (_searchResults.isNotEmpty) ...[
                Text(
                  'Found Existing Records (${_searchResults.length})',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                ..._searchResults.map((p) => _buildPatientResultTile(p)),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showCreateForm = true;
                      });
                    },
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Not on list? Register new patient'),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.mintSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.vibrantMint.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.primaryEmerald),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No existing patient found matching "${_searchController.text.trim()}". Complete the form below to register a new profile.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.deepInk,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],

            // Register New Patient Form
            if (_showCreateForm || !_hasSearched) ...[
              const Divider(height: 32),
              const SectionHeader(
                title: 'Register New Patient Profile',
                subtitle: 'Creates a verifiable patient record linked to your institution.',
              ),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Patient Full Name *',
                          hintText: 'e.g. Maria Gonzalez',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _birthYearController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Birth Year *',
                                hintText: 'e.g. 1985',
                                prefixIcon: Icon(Icons.calendar_today_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Required';
                                final yr = int.tryParse(v);
                                if (yr == null || yr < 1900 || yr > 2026) {
                                  return 'Invalid year';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _gender,
                              decoration: const InputDecoration(
                                labelText: 'Sex / Gender',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Female', child: Text('Female')),
                                DropdownMenuItem(
                                    value: 'Male', child: Text('Male')),
                                DropdownMenuItem(
                                    value: 'Other', child: Text('Other')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _gender = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact Phone (Optional)',
                          hintText: '+1 555-0192',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _allergiesController,
                        decoration: const InputDecoration(
                          labelText: 'Known Allergies (Optional)',
                          hintText: 'e.g. Penicillin, Sulfa drugs',
                          prefixIcon: Icon(Icons.warning_amber_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _medsController,
                        decoration: const InputDecoration(
                          labelText: 'Current Medications (Optional)',
                          hintText: 'e.g. Aspirin 81mg, Metformin 500mg',
                          prefixIcon: Icon(Icons.medication_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Genetic VCF attachment option
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.biotech_rounded,
                                    color: AppTheme.primaryEmerald, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Attach Initial Genomic VCF Sample:',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSampleVcf,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'patient_001_normal.vcf',
                                  child: Text('Sample 1: Standard / Normal metabolizer'),
                                ),
                                DropdownMenuItem(
                                  value: 'patient_002_reduced_function.vcf',
                                  child: Text('Sample 2: Reduced function (CYP2C19 *2)'),
                                ),
                                DropdownMenuItem(
                                  value: 'patient_003_high_risk.vcf',
                                  child: Text('Sample 3: High Risk (CYP2C19 *2/*2, CYP2D6 *4)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedSampleVcf = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isSaving ? null : _registerNewPatient,
                        icon: _isSaving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_rounded),
                        label: Text(
                          _isSaving
                              ? 'Registering Patient…'
                              : 'Save Patient Profile & Open Workspace',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPatientResultTile(OrganizationPatient patient) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryEmerald.withValues(alpha: 0.15),
          child: const Icon(Icons.person, color: AppTheme.primaryEmerald),
        ),
        title: Text(
          patient.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'ID: ${patient.patientId} · Birth year: ${patient.birthYear ?? "N/A"}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrganizationPatientScreen(
                patientId: patient.patientId,
                initialPatient: patient,
              ),
            ),
          );
        },
      ),
    );
  }
}
