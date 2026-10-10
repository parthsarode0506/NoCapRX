import 'package:flutter/material.dart';

import '../models/organization_patient.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'organization_access_requests_screen.dart';
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
            'Organization signup automatically lists your name and city for patient search as self-registered and unverified. This public listing does not grant access to patient data; patient records remain protected by consent and server access controls.',
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const OrganizationAccessRequestsScreen(),
            ),
          ),
          icon: const Icon(Icons.inbox_outlined),
          label: const Text('Review patient requests'),
        ),
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Patient records',
          subtitle: 'Search for a patient already linked to your organization.',
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
                  labelText: 'Patient name',
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
            ],
          ),
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
          'Search patient names already linked to this organization and open their profile.',
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
            'Search by patient name. Only profiles already linked to this organization can appear here.',
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
          const Text(
            'No matching patient profile is linked to this organization.',
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onTryAnotherSearch,
            child: const Text('Try Another Search'),
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
