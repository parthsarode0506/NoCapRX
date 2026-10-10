import 'package:flutter/material.dart';

import '../models/organization_access.dart';
import '../services/firebase_service.dart';

class PatientOrganizationAccessScreen extends StatefulWidget {
  const PatientOrganizationAccessScreen({super.key});

  @override
  State<PatientOrganizationAccessScreen> createState() =>
      _PatientOrganizationAccessScreenState();
}

class _PatientOrganizationAccessScreenState
    extends State<PatientOrganizationAccessScreen> {
  final _searchController = TextEditingController();
  List<OrganizationDirectoryEntry> _organizations = const [];
  List<OrganizationAccessRequest> _requests = const [];
  String? _searchError;
  String? _requestError;
  bool _searching = false;
  bool _loadingRequests = true;
  String? _busyOrganizationId;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchOrganizations() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _organizations = const [];
        _searchError = 'Enter at least two characters to search.';
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await FirebaseService.findOrganizations(query);
      if (mounted) setState(() => _organizations = results);
    } catch (error) {
      if (mounted) {
        setState(() => _searchError = FirebaseService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loadingRequests = true;
      _requestError = null;
    });
    try {
      final requests = await FirebaseService.listPatientOrganizationRequests();
      if (mounted) setState(() => _requests = requests);
    } catch (error) {
      if (mounted) {
        setState(() => _requestError = FirebaseService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _requestAccess(OrganizationDirectoryEntry organization) async {
    setState(() => _busyOrganizationId = organization.organizationId);
    try {
      await FirebaseService.sendOrganizationAccessRequest(organization);
      await _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access request sent to the organization.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _searchError = FirebaseService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _busyOrganizationId = null);
    }
  }

  Future<void> _respond(
    OrganizationAccessRequest request, {
    required bool accepted,
  }) async {
    setState(() => _busyOrganizationId = request.organizationId);
    try {
      await FirebaseService.respondToPatientOrganizationRequest(
        invitation: request,
        accepted: accepted,
      );
      await _loadRequests();
    } catch (error) {
      if (mounted) {
        setState(() => _requestError = FirebaseService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _busyOrganizationId = null);
    }
  }

  Future<void> _revoke(OrganizationAccessRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke organization access?'),
        content: Text(
          'This will remove ${request.organizationName}’s access to your shared profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyOrganizationId = request.organizationId);
    try {
      await FirebaseService.revokePatientOrganizationAccess(request);
      await _loadRequests();
    } catch (error) {
      if (mounted) {
        setState(() => _requestError = FirebaseService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _busyOrganizationId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Organization access')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Find an organization by name. It must review your request before you decide whether to share your basic profile.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchOrganizations(),
          decoration: const InputDecoration(
            labelText: 'Organization name',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _searching ? null : _searchOrganizations,
          icon: _searching
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(_searching ? 'Searching…' : 'Search organizations'),
        ),
        if (_searchError != null) _ErrorText(_searchError!),
        ..._organizations.map(_organizationTile),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your requests',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Refresh requests',
              onPressed: _loadingRequests ? null : _loadRequests,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_requestError != null) _ErrorText(_requestError!),
        if (_loadingRequests)
          const Center(child: CircularProgressIndicator())
        else if (_requests.isEmpty)
          const Text('You have not requested organization access.')
        else
          ..._requests.map(_requestTile),
        const SizedBox(height: 20),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Sharing is optional. If you approve a request, only your basic patient profile is shared for up to one year. Genetic files stay on your device. You can revoke access here at any time.',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _organizationTile(OrganizationDirectoryEntry organization) {
    final existingRequest = _requests
        .where(
          (request) => request.organizationId == organization.organizationId,
        )
        .firstOrNull;
    final status = existingRequest?.status;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.apartment_outlined),
        title: Text(organization.name),
        subtitle: Text(
          organization.selfRegistered
              ? '${organization.city} · Self-registered, not verified'
              : organization.city,
        ),
        trailing:
            status == 'pending_org_review' ||
                status == 'awaiting_patient_confirmation' ||
                status == 'accepted'
            ? Text(_statusLabel(status!))
            : !organization.canRequestAccess
            ? const Text('Listing only')
            : FilledButton(
                onPressed: _busyOrganizationId == organization.organizationId
                    ? null
                    : () => _requestAccess(organization),
                child: const Text('Request'),
              ),
      ),
    );
  }

  Widget _requestTile(OrganizationAccessRequest request) {
    final busy = _busyOrganizationId == request.organizationId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.organizationName),
            const SizedBox(height: 4),
            Text(_statusLabel(request.status)),
            if (request.status == 'awaiting_patient_confirmation') ...[
              const SizedBox(height: 8),
              const Text(
                'The organization reviewed your request. Approving shares your basic patient profile only.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => _respond(request, accepted: true),
                    child: const Text('Share profile'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _respond(request, accepted: false),
                    child: const Text('Decline'),
                  ),
                ],
              ),
            ],
            if (request.status == 'accepted')
              TextButton(
                onPressed: busy ? null : () => _revoke(request),
                child: const Text('Revoke access'),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'pending_org_review' => 'Waiting for organization review',
    'awaiting_patient_confirmation' => 'Your approval is needed',
    'accepted' => 'Profile shared',
    'declined' => 'Declined',
    'revoked' => 'Access revoked',
    _ => status.replaceAll('_', ' '),
  };
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
