import 'package:flutter/material.dart';

import '../models/organization_patient.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'organization_patient_screen.dart';
import 'sign_in_screen.dart';

class OrganizationDashboardScreen extends StatefulWidget {
  const OrganizationDashboardScreen({super.key, this.organizationName});

  final Future<String>? organizationName;

  @override
  State<OrganizationDashboardScreen> createState() =>
      _OrganizationDashboardScreenState();
}

class _OrganizationDashboardScreenState
    extends State<OrganizationDashboardScreen> {
  final _searchController = TextEditingController();
  late final Future<String> _organizationName =
      widget.organizationName ?? FirebaseService.getOrganizationName();
  Future<List<OrganizationPatient>>? _search;
  String? _searchError;
  bool _isSearching = false;
  String? _pendingRegistrationFingerprint;
  String? _pendingRegistrationKey;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchPatients() async {
    final query = _searchController.text.trim();
    if (_isSearching) return;
    if (query.length < 2) {
      setState(() {
        _search = null;
        _searchError = 'Enter at least two characters to search.';
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
      _search = FirebaseService.searchOrganizationPatients(query);
    });
    try {
      await _search;
    } catch (error) {
      if (mounted) setState(() => _searchError = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  String _messageFor(Object error) {
    final message = FirebaseService.mapAuthError(error);
    if (message == error.toString()) {
      return 'Patient search is unavailable. Check organization access and connection.';
    }
    return message;
  }

  Future<void> _addPatient() async {
    final result = await showDialog<_NewPatientInput>(
      context: context,
      builder: (_) => const _NewPatientDialog(),
    );
    if (result == null || !mounted) return;
    final fingerprint =
        '${result.name.toLowerCase().trim()}|${result.birthYear ?? ''}';
    if (_pendingRegistrationFingerprint != fingerprint) {
      _pendingRegistrationFingerprint = fingerprint;
      _pendingRegistrationKey = FirebaseService.newIdempotencyKey();
    }
    try {
      final patientId = await FirebaseService.registerOrganizationPatient(
        name: result.name,
        birthYear: result.birthYear,
        idempotencyKey: _pendingRegistrationKey!,
      );
      _pendingRegistrationFingerprint = null;
      _pendingRegistrationKey = null;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrganizationPatientScreen(patientId: patientId),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Organization Dashboard'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: () async {
            await FirebaseService.signOut();
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const SignInScreen()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: _buildWorkspace(context),
  );

  Widget _buildWorkspace(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _OrganizationHero(organizationName: _organizationName),
        const SizedBox(height: 24),
        const AppCard(
          child: Text(
            'Hospital access codes and patient-account invitations are unavailable in free Firebase mode. Patient records created here are organization-only and will not appear in a patient login.',
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Patient records',
          subtitle: 'Find an existing patient or create a new record.',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchPatients(),
                decoration: const InputDecoration(
                  labelText: 'Patient name or patient ID',
                  hintText: 'Enter at least 2 characters',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSearching ? null : _searchPatients,
                icon: _isSearching
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isSearching ? 'Searching…' : 'Search records'),
              ),
              const SizedBox(height: 8),
              Text(
                'Results are limited to records linked to your active organization.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'This creates a patient record only. The patient creates their own account and password from Patient Sign Up; organization staff should not collect or set the patient password.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addPatient,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add New Patient'),
        ),
        if (_searchError != null) ...[
          const SizedBox(height: 16),
          _InlineError(message: _searchError!, onRetry: _searchPatients),
        ],
        if (_search == null && _searchError == null) ...[
          const SizedBox(height: 12),
          const _SearchPrompt(),
        ],
        if (_search != null) ...[
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Search results',
            subtitle: 'Select the matching patient to open their workspace.',
          ),
          FutureBuilder<List<OrganizationPatient>>(
            future: _search,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) return const SizedBox.shrink();
              final patients = snapshot.data ?? const [];
              if (patients.isEmpty) {
                return _NoResults(
                  onTryAnotherSearch: () {
                    _searchController.clear();
                    setState(() {
                      _search = null;
                      _searchError = null;
                    });
                  },
                );
              }
              return Column(
                children: patients
                    .map((patient) => _PatientTile(patient: patient))
                    .toList(growable: false),
              );
            },
          ),
        ],
        const SizedBox(height: 24),
        const SectionHeader(
          title: 'Clinical workflows',
          subtitle:
              'These actions are shown for clarity, but are not enabled yet.',
        ),
        const _UnavailableWorkflowCard(
          icon: Icons.analytics_outlined,
          title: 'Generate Drug-Safety Report',
          detail:
              'Requires a validated clinical rules workflow and an authorized patient record.',
        ),
        const _UnavailableWorkflowCard(
          icon: Icons.medication_outlined,
          title: 'Create Prescription',
          detail:
              'Prescription review, approval, and patient-record sync are not connected.',
        ),
        const SizedBox(height: 12),
        const _PrivacyBoundaryCard(),
      ],
    ),
  );
}

class _OrganizationHero extends StatelessWidget {
  const _OrganizationHero({required this.organizationName});

  final Future<String> organizationName;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: AppTheme.heroGradient,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.apartment_outlined, color: Colors.white, size: 30),
        const SizedBox(height: 16),
        Text(
          'Organization workspace',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        FutureBuilder<String>(
          future: organizationName,
          builder: (context, snapshot) => Text(
            snapshot.hasError
                ? 'Organization details could not be loaded.'
                : snapshot.data ?? 'Loading organization…',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Search authorized patient records, review available status, and register a patient when no matching record exists.',
          style: TextStyle(color: Colors.white),
        ),
      ],
    ),
  );
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context) => AppCard(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Row(
      children: [
        Icon(Icons.manage_search_outlined),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Start with a patient search. Existing matches appear here; add a new record only when the patient is not already registered.',
          ),
        ),
      ],
    ),
  );
}

class _UnavailableWorkflowCard extends StatelessWidget {
  const _UnavailableWorkflowCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(detail),
      trailing: const PillBadge(
        label: 'Not enabled',
        color: AppTheme.unknownSlate,
      ),
      isThreeLine: true,
    ),
  );
}

class _PrivacyBoundaryCard extends StatelessWidget {
  const _PrivacyBoundaryCard();

  @override
  Widget build(BuildContext context) => AppCard(
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.privacy_tip_outlined),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Genetic files stay on-device. This workspace does not retrieve or upload raw VCF files, run cloud genetic analysis, or publish reports. Only server-authorized patient records are searchable.',
          ),
        ),
      ],
    ),
  );
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({required this.patient});

  final OrganizationPatient patient;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(patient.name),
      subtitle: Text(
        '${patient.patientId} • Birth year: ${patient.birthYear ?? 'Not recorded'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OrganizationPatientScreen(patientId: patient.patientId),
        ),
      ),
    ),
  );
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onTryAnotherSearch});

  final VoidCallback onTryAnotherSearch;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No matching patient record found.'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: onTryAnotherSearch,
                child: const Text('Try Another Search'),
              ),
              const Text(
                'Use Add New Patient only if this person is not already registered.',
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _NewPatientInput {
  const _NewPatientInput({required this.name, this.birthYear});

  final String name;
  final int? birthYear;
}

class _NewPatientDialog extends StatefulWidget {
  const _NewPatientDialog();

  @override
  State<_NewPatientDialog> createState() => _NewPatientDialogState();
}

class _NewPatientDialogState extends State<_NewPatientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _birthYear = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add patient record'),
    scrollable: true,
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (value) {
              if ((value?.trim().length ?? 0) < 2) {
                return 'Enter at least two characters.';
              }
              return null;
            },
          ),
          TextFormField(
            controller: _birthYear,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'Birth year (optional)',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final year = int.tryParse(value);
              if (year == null || year < 1900 || year > DateTime.now().year) {
                return 'Enter a valid year.';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'This creates an organization-only record. Hospital access codes and patient account linking are disabled in free Firebase mode, so this record will not appear in a patient login.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _NewPatientInput(
              name: _name.text.trim(),
              birthYear: int.tryParse(_birthYear.text.trim()),
            ),
          );
        },
        child: const Text('Create record'),
      ),
    ],
  );
}
