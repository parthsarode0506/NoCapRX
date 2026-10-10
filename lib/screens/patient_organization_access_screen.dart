import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/organization_access.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';

class PatientOrganizationAccessScreen extends ConsumerStatefulWidget {
  const PatientOrganizationAccessScreen({super.key});

  @override
  ConsumerState<PatientOrganizationAccessScreen> createState() =>
      _PatientOrganizationAccessScreenState();
}

class _PatientOrganizationAccessScreenState
    extends ConsumerState<PatientOrganizationAccessScreen> {
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
    _loadOrganizations();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizations([String query = '']) async {
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

  Future<void> _searchOrganizations() async {
    await _loadOrganizations(_searchController.text.trim());
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loadingRequests = true;
      _requestError = null;
    });
    try {
      final directoryRequests =
          await FirebaseService.listPatientDirectoryContactRequests();
      var organizationRequests = <OrganizationAccessRequest>[];
      try {
        organizationRequests =
            await FirebaseService.listPatientOrganizationRequests();
      } catch (error) {
        debugPrint('Enterprise organization requests callable skipped: $error');
      }
      final requestsByOrganization = <String, OrganizationAccessRequest>{
        for (final request in organizationRequests)
          request.organizationId: request,
        for (final request in directoryRequests)
          request.organizationId: request,
      };
      if (mounted) {
        setState(() {
          _requests = requestsByOrganization.values.toList(growable: false);
          _requestError = null;
        });
      }
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
    final sharing = accepted ? await _chooseSharingSettings() : null;
    if (accepted && sharing == null) return;
    setState(() => _busyOrganizationId = request.organizationId);
    try {
      await FirebaseService.respondToPatientOrganizationRequest(
        invitation: request,
        accepted: accepted,
        shareGenomicProfile: sharing?.shareGenomicProfile ?? false,
        allowPrescriptions: sharing?.allowPrescriptions ?? false,
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

  Future<void> _updateSharing(OrganizationAccessRequest request) async {
    final sharing = await _chooseSharingSettings(
      initialShareGenomicProfile: request.shareGenomicProfile,
      initialAllowPrescriptions: request.allowPrescriptions,
    );
    if (sharing == null) return;
    setState(() => _busyOrganizationId = request.organizationId);
    try {
      await FirebaseService.updatePatientOrganizationSharing(
        organizationId: request.organizationId,
        shareGenomicProfile: sharing.shareGenomicProfile,
        allowPrescriptions: sharing.allowPrescriptions,
      );
      await _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing preferences updated.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _requestError = FirebaseService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _busyOrganizationId = null);
    }
  }

  Future<({bool shareGenomicProfile, bool allowPrescriptions})?>
      _chooseSharingSettings({
    bool initialShareGenomicProfile = false,
    bool initialAllowPrescriptions = false,
  }) async {
    var shareGenomicProfile = initialShareGenomicProfile;
    var allowPrescriptions = initialAllowPrescriptions;
    return showDialog<({bool shareGenomicProfile, bool allowPrescriptions})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choose what to share'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Basic profile sharing is required for this organization link. Saving replaces your optional sharing choices. Raw VCF files stay on your device.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: shareGenomicProfile,
                onChanged: (value) => setDialogState(
                  () => shareGenomicProfile = value ?? false,
                ),
                title: const Text('Share derived PGx findings'),
                subtitle: const Text(
                  'Shares gene, diplotype and phenotype only. These findings are not a validated clinical report.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: allowPrescriptions,
                onChanged: (value) => setDialogState(
                  () => allowPrescriptions = value ?? false,
                ),
                title: const Text('Allow prescription drafts and publication'),
                subtitle: const Text(
                  'The organization can save drafts and publish clinician-authored prescriptions to your dashboard.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                (
                  shareGenomicProfile: shareGenomicProfile,
                  allowPrescriptions: allowPrescriptions,
                ),
              ),
              child: const Text('Save choices'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDerivedProfile(OrganizationAccessRequest request) async {
    final profile = ref.read(vcfParseResultProvider);
    final patientId = ref.read(patientProfileProvider).patientId.trim();
    if (profile == null || patientId.isEmpty) {
      setState(() {
        _requestError =
            'Load a VCF and complete patient account linking before sharing derived findings.';
      });
      return;
    }
    setState(() {
      _busyOrganizationId = request.organizationId;
      _requestError = null;
    });
    try {
      final profiles = profile.geneProfiles.values
          .map(
            (gene) => <String, Object?>{
              'gene': gene.gene,
              'diplotype': gene.diplotype,
              'phenotype': gene.phenotype,
              'isInferred': gene.isInferred,
            },
          )
          .toList(growable: false);
      if (profiles.isEmpty) {
        throw StateError('The loaded VCF has no derived gene profiles to share.');
      }
      await FirebaseService.publishDerivedGenomicProfile(
        patientId: patientId,
        organizationId: request.organizationId,
        profiles: profiles,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Derived findings shared. The raw VCF remains on this device.',
            ),
          ),
        );
      }
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
          'Find an organization by name and send a request. For self-registered listings, only your display name is sent; no patient profile or genetic data is shared.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchOrganizations(),
          onChanged: (val) => _loadOrganizations(val.trim()),
          decoration: InputDecoration(
            labelText: 'Search Hospital or Organization',
            hintText: 'Type hospital name or city...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _loadOrganizations('');
                    },
                  )
                : null,
            border: const OutlineInputBorder(),
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
        if (!_searching && _organizations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No registered hospitals found. When a clinic signs up, it will appear here immediately.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
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
              'Sharing is optional and can be changed at any time. Raw VCF files always stay on your device. You may separately choose to share derived PGx findings and allow prescriptions.',
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
              ? '${organization.city} · Self-registered'
              : organization.city,
        ),
        trailing: status != null
            ? Text(_statusLabel(status))
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
            if (request.isDirectoryContactRequest) ...[
              const SizedBox(height: 6),
              const Text(
                'This is a contact request only. No patient record, medical profile, or genetic data was shared.',
              ),
            ],
            if (request.status == 'awaiting_patient_confirmation') ...[
              const SizedBox(height: 8),
              const Text(
                'The organization reviewed your request. You choose whether to share derived PGx findings or allow prescriptions.',
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
            if (request.status == 'accepted') ...[
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => _updateSharing(request),
                    child: const Text('Sharing settings'),
                  ),
                  if (ref.watch(vcfParseResultProvider) != null)
                    TextButton(
                      onPressed: busy ? null : () => _shareDerivedProfile(request),
                      child: const Text('Share derived PGx findings'),
                    ),
                  TextButton(
                    onPressed: busy ? null : () => _revoke(request),
                    child: const Text('Revoke access'),
                  ),
                ],
              ),
            ],
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
    'directory_request_pending' => 'Request sent — awaiting organization',
    'directory_request_acknowledged' => 'Organization acknowledged request',
    'directory_request_declined' => 'Organization declined request',
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
