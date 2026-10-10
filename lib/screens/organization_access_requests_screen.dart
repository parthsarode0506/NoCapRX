import 'package:flutter/material.dart';

import '../models/organization_access.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';


class OrganizationAccessRequestsScreen extends StatefulWidget {
  const OrganizationAccessRequestsScreen({super.key});

  @override
  State<OrganizationAccessRequestsScreen> createState() =>
      _OrganizationAccessRequestsScreenState();
}

class _OrganizationAccessRequestsScreenState
    extends State<OrganizationAccessRequestsScreen> {
  late Future<List<OrganizationAccessRequest>> _requests;
  String? _error;
  String? _busyPatientUid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requests = _loadAuthorizedRequests();
  }

  Future<List<OrganizationAccessRequest>> _loadAuthorizedRequests() async {
    return FirebaseService.listOrganizationPatientRequests();
  }

  Future<void> _respond(
    OrganizationAccessRequest request, {
    required bool accepted,
  }) async {
    setState(() {
      _busyPatientUid = request.patientUid;
      _error = null;
    });
    try {
      await FirebaseService.respondToOrganizationAccessRequest(
        invitation: request,
        accepted: accepted,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            request.isDirectoryContactRequest
                ? accepted
                      ? 'Contact request acknowledged. No patient data was shared.'
                      : 'Contact request declined.'
                : accepted
                ? 'Request reviewed. The patient must approve profile sharing.'
                : 'Access request declined.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = FirebaseService.mapAuthError(error);
          _load();
        });
      }
    } finally {
      if (mounted) setState(() => _busyPatientUid = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Patient requests')),
    body: FutureBuilder<List<OrganizationAccessRequest>>(
      future: _requests,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _RequestMessage(
            message: _error ?? FirebaseService.mapAuthError(snapshot.error!),
            action: FilledButton(
              onPressed: () => setState(() {
                _error = null;
                _load();
              }),
              child: const Text('Retry'),
            ),
          );
        }
        final requests = snapshot.data ?? const [];
        if (requests.isEmpty) {
          return const _RequestMessage(
            message: 'There are no patient requests awaiting review.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() {
            _error = null;
            _load();
          }),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                requests.any((request) => request.isDirectoryContactRequest)
                    ? 'Directory contact requests contain only the patient’s display name. Acknowledging a request does not share medical data or grant patient-record access.'
                    : 'Reviewing an access request does not share patient data. The patient must separately consent before their basic profile becomes visible.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              ...requests.map(
                (request) => _AccessRequestCard(
                  request: request,
                  busy: _busyPatientUid == request.patientUid,
                  onAccept: () => _respond(request, accepted: true),
                  onDecline: () => _respond(request, accepted: false),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _AccessRequestCard extends StatelessWidget {
  const _AccessRequestCard({
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final OrganizationAccessRequest request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.patientName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!request.isDirectoryContactRequest) ...[
            const SizedBox(height: 4),
            Text('Patient ID: ${request.patientId}'),
          ],
          if (request.isDirectoryContactRequest) ...[
            const SizedBox(height: 4),
            const Text(
              'Directory contact request · no patient record attached',
            ),
          ],
          const SizedBox(height: 12),
          if (request.status == 'directory_request_pending')
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Acknowledge request'),
                ),
                TextButton(
                  onPressed: busy ? null : onDecline,
                  child: const Text('Decline'),
                ),
              ],
            )
          else if (request.isDirectoryContactRequest)
            Row(
              children: [
                Text(
                  request.status == 'directory_request_acknowledged'
                      ? 'Request accepted'
                      : 'Request declined',
                  style: TextStyle(
                    color: request.status == 'directory_request_acknowledged'
                        ? AppTheme.safeGreen
                        : AppTheme.dangerRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (request.status == 'directory_request_acknowledged') ...[
                  const Spacer(),
                  const Flexible(
                    child: Text('Acknowledgment does not grant patient-record or genomic access.'),
                  ),
                ],
              ],
            )

          else
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve for patient review'),
                ),
                TextButton(
                  onPressed: busy ? null : onDecline,
                  child: const Text('Decline'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _RequestMessage extends StatelessWidget {
  const _RequestMessage({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}
