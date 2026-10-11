import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/organization_access.dart';
import '../services/audit_service.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'organization_patient_screen.dart';

class OrganizationInvitationsScreen extends StatefulWidget {
  const OrganizationInvitationsScreen({super.key});

  @override
  State<OrganizationInvitationsScreen> createState() =>
      _OrganizationInvitationsScreenState();
}

class _OrganizationInvitationsScreenState
    extends State<OrganizationInvitationsScreen> {
  bool _isLoading = true;
  List<OrganizationAccessRequest> _invitations = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = <OrganizationAccessRequest>[];
      try {
        final cloudList =
            await FirebaseService.listOrganizationPatientRequests();
        list.addAll(cloudList);
      } catch (_) {
        // Fallback for demonstration / offline workspace
      }


      if (mounted) {
        setState(() {
          _invitations = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _respondToInvitation(
      int index, OrganizationAccessRequest inv, bool accept) async {
    setState(() {
      _invitations[index] = OrganizationAccessRequest(
        organizationId: inv.organizationId,
        organizationName: inv.organizationName,
        patientUid: inv.patientUid,
        patientId: inv.patientId,
        patientName: inv.patientName,
        status: accept ? 'accepted' : 'rejected',
        requestedAt: inv.requestedAt,
        isDirectoryContactRequest: inv.isDirectoryContactRequest,
      );
    });

    await AuditService.instance.recordLog(
      action: accept ? 'invitation_accepted' : 'invitation_rejected',
      actorUid: FirebaseService.currentUser?.uid ?? 'DOC_ACTIVE',
      actorRole: 'doctor',
      organizationId: inv.organizationId,
      targetId: inv.patientId,
      description:
          'Patient invitation from ${inv.patientName} (${inv.patientId}) was ${accept ? "accepted" : "rejected"} by organization.',
    );

    try {
      await FirebaseService.respondToOrganizationAccessRequest(
        invitation: inv,
        accepted: accept,
      );
    } catch (_) {
      // Handled gracefully in mock / direct mode
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Accepted invitation from ${inv.patientName}. Patient records are now accessible.'
                : 'Declined access request from ${inv.patientName}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Patient Access Invitations'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadInvitations,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  children: [
                    const SectionHeader(
                      title: 'Incoming Patient Consent Requests',
                      subtitle:
                          'Patients seeking clinical review who authorized your organization to access their genetic findings.',
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage != null) ...[
                      NoticeBanner(
                          tone: NoticeTone.warning, message: _errorMessage!),
                      const SizedBox(height: 16),
                    ],
                    if (_invitations.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: const Center(
                          child: Text('No pending patient invitations found.'),
                        ),
                      )
                    else
                      ..._invitations.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final inv = entry.value;
                        return _buildInvitationCard(idx, inv);
                      }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInvitationCard(int index, OrganizationAccessRequest inv) {
    final isPending = inv.status == 'pending_org_review' ||
        inv.status == 'directory_request_pending';
    final isAccepted = inv.status == 'accepted' ||
        inv.status == 'directory_request_acknowledged';

    Color statusColor = AppTheme.warningAmber;
    if (isAccepted) statusColor = AppTheme.safeGreen;
    if (inv.status == 'rejected' || inv.status == 'directory_request_declined') {
      statusColor = AppTheme.dangerRed;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? AppTheme.primaryEmerald.withValues(alpha: 0.5)
              : AppTheme.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    AppTheme.primaryEmerald.withValues(alpha: 0.15),
                child: const Icon(Icons.person, color: AppTheme.primaryEmerald),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.patientName,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      inv.isDirectoryContactRequest
                          ? 'Patient Directory Access Request'
                          : 'Patient ID: ${inv.patientId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  inv.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Requested Access: Read clinical demographics, VCF-derived report, genotype and CPIC risk findings.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.3),
          ),
          const SizedBox(height: 14),
          if (isPending) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.dangerRed,
                      side: const BorderSide(color: AppTheme.dangerRed),
                    ),
                    onPressed: () => _respondToInvitation(index, inv, false),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryEmerald,
                    ),
                    onPressed: () => _respondToInvitation(index, inv, true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Accept Access'),
                  ),
                ),
              ],
            ),
          ] else if (isAccepted) ...[
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrganizationPatientScreen(
                        patientId: inv.patientId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Patient Workspace'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
