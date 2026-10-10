import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'organization_dashboard_screen.dart';
import 'sign_in_screen.dart';

class OrganizationVerificationScreen extends ConsumerStatefulWidget {
  const OrganizationVerificationScreen({
    super.key,
    this.organizationName = 'Medical Organization',
    this.city = '',
  });

  final String organizationName;
  final String city;

  @override
  ConsumerState<OrganizationVerificationScreen> createState() =>
      _OrganizationVerificationScreenState();
}

class _OrganizationVerificationScreenState
    extends ConsumerState<OrganizationVerificationScreen> {
  bool _isChecking = false;

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    final hasWorkspace = await FirebaseService.hasOrganizationWorkspace(
      forceRefresh: true,
    );
    if (!mounted) return;
    setState(() => _isChecking = false);

    if (hasWorkspace) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OrganizationDashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your organization registration is currently pending review by clinical administrators.',
          ),
        ),
      );
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Organization Verification'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            // Status Icon & Header
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppTheme.warningAmber.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.warningAmber.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  color: AppTheme.warningAmber,
                  size: 46,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Verification Under Review',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.deepInk,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your organization account has been submitted and is currently awaiting clinical compliance validation.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),

            // Organization Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.apartment_rounded,
                        color: AppTheme.primaryEmerald,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.organizationName,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.city.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Location: ${widget.city}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const Divider(height: 24),
                  _buildStatusRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Status',
                    value: 'Pending Institutional Review',
                    color: AppTheme.warningAmber,
                  ),
                  const SizedBox(height: 10),
                  _buildStatusRow(
                    icon: Icons.shield_outlined,
                    label: 'Data Access Scope',
                    value: 'Restricted (Awaiting Consent Engine)',
                    color: AppTheme.unknownSlate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Requirements Explanatory Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.mintSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.vibrantMint.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppTheme.primaryEmerald,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'What happens during verification?',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryEmerald,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Verification of clinical license & institution registration.\n'
                    '2. Enrollment into HIPAA/DPDP end-to-end audit logging.\n'
                    '3. Activation of prescription issuance & CPIC pharmacogenomic safety engine.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: AppTheme.deepInk.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            FilledButton.icon(
              onPressed: _isChecking ? null : _checkVerification,
              icon: _isChecking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _isChecking ? 'Checking…' : 'Check Verification Status',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
