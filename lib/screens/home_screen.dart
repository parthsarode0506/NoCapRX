import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/pgx_report.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_emblem.dart';
import '../widgets/pgx_summary_dashboard.dart';
import '../widgets/security_cards.dart';
import 'upload_screen.dart';
import 'results_screen.dart';
import 'sign_in_screen.dart';
import 'history_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    await FirebaseService.signOut();
    ref.read(userProfileProvider.notifier).state = null;
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfile = ref.watch(userProfileProvider);
    final reportsAsync = ref.watch(userReportsStreamProvider);

    final displayName = userProfile?.displayName ??
        FirebaseService.currentUser?.displayName ??
        'Alex Morgan';
    final role = userProfile?.role ?? 'Patient';

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Row(
          children: [
            const NoCapRxEmblem(size: 32, borderRadius: 9, showShadow: false),
            const SizedBox(width: 10),
            Text(
              'NoCapRX',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppTheme.deepInk,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'All Past Reports',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.cardBorder),
            ),
            onSelected: (value) {
              if (value == 'sign_out') {
                _handleSignOut(context, ref);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.deepInk,
                      ),
                    ),
                    Text(
                      FirebaseService.currentUser?.email ?? 'ondevice@nocaprx.local',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.mutedGrey),
                    ),
                    const Divider(),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sign_out',
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: AppTheme.dangerRed, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.inter(
                        color: AppTheme.dangerRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryEmerald,
          onRefresh: () async {
            ref.invalidate(userReportsStreamProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Greeting Banner Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.primaryDarkEmerald,
                        AppTheme.primaryEmerald,
                        AppTheme.accentEmerald,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryDarkEmerald.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppTheme.vibrantMint,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.vibrantMint,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'PHARMACOGENOMIC PORTAL',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              role.toUpperCase(),
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Welcome, $displayName',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Deterministic pharmacogenomic risk assessment on your device.',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // On-Device Privacy Banner
                const OnDevicePrivacyMicroCard(),
                const SizedBox(height: 18),

                // Primary CTA Card: New Analysis
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UploadScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.cardBorder, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.lightEmeraldPill,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.upload_file_rounded,
                            size: 26,
                            color: AppTheme.primaryEmerald,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New Analysis',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.5,
                                  color: AppTheme.deepInk,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Select patient .VCF file & check drug risks locally',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.secondaryInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppTheme.subtleFill,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: AppTheme.primaryEmerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Split Block: Half 1 (Recent Reports) & Half 2 (Risk Overview Dashboard)
                reportsAsync.when(
                  data: (reports) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 640;

                        if (isWide) {
                          // Side-by-side row on wider screens
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _buildRecentReportsBlock(
                                  context,
                                  ref,
                                  reports,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 1,
                                child: PgxSummaryDashboard(
                                  reports: reports,
                                  onNewAnalysis: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const UploadScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        }

                        // Mobile Dual-Card Split Layout (stacked vertically with matching visual weights)
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Half 2: Risk Overview Dashboard
                            PgxSummaryDashboard(
                              reports: reports,
                              onNewAnalysis: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const UploadScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),

                            // Half 1: Recent Reports Section
                            _buildRecentReportsBlock(
                              context,
                              ref,
                              reports,
                            ),
                          ],
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: AppTheme.primaryEmerald),
                    ),
                  ),
                  error: (err, stack) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerRedBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Error loading reports history: $err',
                      style: GoogleFonts.inter(color: AppTheme.dangerRed, fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentReportsBlock(
    BuildContext context,
    WidgetRef ref,
    List<PgxMultiReport> reports,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.lightEmeraldPill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_edu_rounded,
                      size: 16,
                      color: AppTheme.primaryEmerald,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RECENT REPORTS',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.deepInk,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
                child: Text(
                  'View All ↗',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryEmerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (reports.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: AppTheme.bgLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.assignment_outlined,
                    size: 28,
                    color: AppTheme.secondaryInk,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No Reports Generated Yet',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.deepInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Analyze your first .VCF file.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.secondaryInk,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reports.take(3).length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return _buildCompactReportItemTile(context, ref, report);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactReportItemTile(
    BuildContext context,
    WidgetRef ref,
    PgxMultiReport report,
  ) {
    final drugNames = report.drugReports.map((d) => d.drug).join(', ');
    final dateStr = report.timestamp.split('T').first;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.7)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.lightEmeraldPill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.analytics_outlined,
            color: AppTheme.primaryEmerald,
            size: 18,
          ),
        ),
        title: Text(
          drugNames,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: AppTheme.deepInk,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Patient: ${report.patientId} • $dateStr',
          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.secondaryInk),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppTheme.secondaryInk,
        ),
        onTap: () {
          ref.read(currentReportProvider.notifier).state = report;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ResultsScreen(report: report),
            ),
          );
        },
      ),
    );
  }
}
