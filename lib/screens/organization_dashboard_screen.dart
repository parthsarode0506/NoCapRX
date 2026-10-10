import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/organization_patient.dart';
import '../models/prescription.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../services/prescription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'new_patient_screen.dart';
import 'organization_access_requests_screen.dart';
import 'organization_accepted_patients_screen.dart';
import 'organization_audit_screen.dart';
import 'organization_invitations_screen.dart';
import 'organization_patient_screen.dart';
import 'sign_in_screen.dart';

class OrganizationDashboardScreen extends ConsumerStatefulWidget {
  const OrganizationDashboardScreen({
    super.key,
    this.organizationName,
    this.hasVerifiedClaim,
  });

  final Future<String>? organizationName;
  final Future<bool>? hasVerifiedClaim;

  @override
  ConsumerState<OrganizationDashboardScreen> createState() =>
      _OrganizationDashboardScreenState();
}

class _OrganizationDashboardScreenState
    extends ConsumerState<OrganizationDashboardScreen> {
  final _searchController = TextEditingController();
  late final Future<String> _organizationName =
      widget.organizationName ?? _getSafeOrganizationName();

  late final Future<bool> _hasVerifiedOrganizationClaim =
      widget.hasVerifiedClaim ?? _checkVerifiedClaim();
  List<OrganizationPatient> _searchResults = [];
  String? _searchQuery;
  bool _isSearchingPatients = false;
  String? _patientSearchError;

  Future<String> _getSafeOrganizationName() async {
    try {
      return await FirebaseService.getOrganizationName();
    } catch (_) {
      return 'Medical Genomics Institute';
    }
  }

  Future<bool> _checkVerifiedClaim() async {
    try {
      return await FirebaseService.hasOrganizationWorkspace();
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _ensurePublished();
  }

  void _ensurePublished() {
    try {
      final user = FirebaseService.currentUser;
      final profile = ref.read(userProfileProvider);
      if (user != null && profile != null) {
        FirebaseService.ensureOrganizationDirectoryPublished(
          user: user,
          name: profile.organizationName,
          city: profile.city,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchPatients() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchQuery = null;
        _searchResults = [];
        _patientSearchError = null;
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearchingPatients = true;
      _patientSearchError = null;
    });
    try {
      final patients = await FirebaseService.searchOrganizationPatients(query);
      if (!mounted) return;
      setState(() => _searchResults = patients);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _patientSearchError = FirebaseService.mapAuthError(error);
      });
    } finally {
      if (mounted) setState(() => _isSearchingPatients = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('Organization Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<bool>(
          future: _hasVerifiedOrganizationClaim,
          builder: (context, snapshot) {
            final isVerified = snapshot.data == true;

            if (!isVerified &&
                snapshot.connectionState == ConnectionState.done) {
              return _buildDirectoryOnlyWorkspace(context);
            }

            if (!isVerified &&
                snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            return _buildVerifiedWorkspace(context);
          },
        ),
      ),
    );
  }

  Widget _buildDirectoryOnlyWorkspace(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _OrganizationHero(organizationName: _organizationName),
        const SizedBox(height: 24),
        const AppCard(
          child: Text(
            'Organization signup lists this name and city in patient search without a professional verification step. Patients can send a contact request to this account. A request shares only the patient’s display name; it does not share a patient profile, genetic information, or grant record access.',
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Patient record search remains limited to provisioned organizations, but reviewing contact requests for this listing does not require professional verification.',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OrganizationAccessRequestsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.inbox_outlined),
                label: const Text('Review patient requests'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OrganizationAcceptedPatientsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('Accepted patients & VCF records'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeader(
          title: 'Clinical workflows',
          subtitle:
              'Review authorized patient genomic cards and create prescriptions.',
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
    );
  }



  Widget _buildVerifiedWorkspace(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final displayedName = profile?.organizationName.isNotEmpty == true
        ? profile!.organizationName
        : 'Medical Genomics Institute';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      children: [
        // Hero Organization Banner
        _buildOrgHero(displayedName),
        const SizedBox(height: 18),

        // Quick Actions: New Patient, Invitations, Audit Logs
        const SectionHeader(
          title: 'Clinical Operations',
          subtitle: 'Institutional workflows and patient record management.',
        ),
        const SizedBox(height: 12),
        _buildActionButtonsRow(context),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OrganizationAcceptedPatientsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.people_alt_outlined),
            label: const Text('View all accepted patients'),
          ),
        ),
        const SizedBox(height: 24),

        // Search Existing Patients (Feature 2)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionHeader(
              title: 'Patient Directory',
              subtitle: 'Authorized patient genomic records.',
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewPatientScreen()),
                );
              },
              icon: const Icon(Icons.person_add_alt, size: 16),
              label: const Text('New Patient'),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Search Bar
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _searchPatients(),
          onChanged: (val) {
            if (val.isEmpty) {
              setState(() {
                _searchQuery = null;
                _searchResults = [];
                _patientSearchError = null;
              });
            }
          },
          decoration: InputDecoration(
            hintText: 'Search by patient ID or name...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _searchPatients,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.cardBorder),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Patient List (Filtered or Full)
        _buildPatientList(context),
        const SizedBox(height: 24),

        // Recent Prescriptions Activity
        _buildRecentPrescriptionsStream(),
      ],
    );
  }

  Widget _buildOrgHero(String fallbackName) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.apartment_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, size: 14, color: AppTheme.vibrantMint),
                    SizedBox(width: 4),
                    Text(
                      'Verified Clinical Organization',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Organization workspace',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          FutureBuilder<String>(
            future: _organizationName,
            builder: (context, snapshot) {
              final name = snapshot.data ?? fallbackName;
              return Text(
                name,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            'B2B2C Pharmacogenomics Decision Support Workspace',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OrganizationInvitationsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.inbox_outlined, size: 18),
            label: const Text('Review Requests'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OrganizationAuditScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history_outlined, size: 18),
            label: const Text('Audit Trail'),
          ),
        ),
      ],
    );
  }

  Widget _buildPatientList(BuildContext context) {
    if (_isSearchingPatients) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_patientSearchError != null) {
      return AppCard(child: Text(_patientSearchError!));
    }
    if (_searchQuery == null) {
      return const AppCard(
        child: Text(
          'Search by patient name or ID. Results are returned only for records this organization is authorized to access.',
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return const AppCard(child: Text('No authorized patient records found.'));
    }

    return Column(
      children: _searchResults.map((patient) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryEmerald.withValues(alpha: 0.12),
              child: const Icon(Icons.person, color: AppTheme.primaryEmerald),
            ),
            title: Text(
              patient.name,
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Patient ID: ${patient.patientId}${patient.vcfFileName != null ? " · VCF: ${patient.vcfFileName}" : ""}',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            trailing: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PillBadge(label: 'Authorized', color: AppTheme.safeGreen),
                SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 20),
              ],
            ),
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
      }).toList(),
    );
  }

  Widget _buildRecentPrescriptionsStream() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Prescription Activity',
          subtitle: 'Prescription details stay within each patient workspace.',
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<Prescription>>(
          stream: PrescriptionService.instance.streamOrganizationPrescriptions(
            'any',
          ),
          builder: (context, snapshot) {
            final list = snapshot.data ?? [];
            if (list.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Center(
                  child: Text(
                    'Open an accepted patient workspace to view authorized prescription records.',
                  ),
                ),
              );
            }

            return Column(
              children: list.take(3).map((rx) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      rx.isIssued ? Icons.verified : Icons.edit_note,
                      color: rx.isIssued
                          ? AppTheme.safeGreen
                          : AppTheme.warningAmber,
                    ),
                    title: Text(
                      '${rx.patientName} — Prescription ${rx.prescriptionId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      '${rx.items.length} medicines · Prescriber: ${rx.prescriberName}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      rx.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: rx.isIssued
                            ? AppTheme.safeGreen
                            : AppTheme.warningAmber,
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
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
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
      trailing: const PillBadge(
        label: 'Unavailable',
        color: AppTheme.unknownSlate,
      ),
      isThreeLine: true,
    ),
  );
}

class _PrivacyBoundaryCard extends StatelessWidget {
  const _PrivacyBoundaryCard();

  @override
  Widget build(BuildContext context) => const AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.privacy_tip_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Patient privacy boundary',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'This workspace does not retrieve or upload raw VCF files, run cloud analysis, or claim that a report or prescription has been created. Counts above reflect only records actually returned by the backend.',
        ),
      ],
    ),
  );
}
