import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/chat/ask_nocaprx_screen.dart';
import '../models/genomic_drug_scan_report.dart';
import '../models/pgx_report.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_emblem.dart';
import 'chatbot_screen.dart';
import 'drug_input_screen.dart';
import 'genomic_scan_screen.dart';
import 'history_screen.dart';
import 'patient_profile_screen.dart';
import 'prescription_scan_screen.dart';
import 'results_screen.dart';
import 'sign_in_screen.dart';
import 'upload_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // ─── Navigation helpers ───────────────────────────────────────────────────

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await FirebaseService.signOut();
    ref.read(userProfileProvider.notifier).state = null;
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (_) => false,
      );
    }
  }

  void _openUpload(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const UploadScreen()));
  }

  void _openMedicine(BuildContext context, WidgetRef ref) {
    if (ref.read(vcfParseResultProvider) == null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            const UploadScreen(returnToMedicine: true, returnToDashboard: false),
      ));
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const DrugInputScreen()));
  }

  void _openWatchlist(
      BuildContext context, WidgetRef ref, GenomicDrugScanReport? scan) {
    if (scan == null) {
      _openUpload(context);
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GenomicScanScreen(report: scan)));
  }

  Future<void> _openPrescriptionScan(
      BuildContext context, WidgetRef ref) async {
    // If no VCF yet, go to upload first
    if (ref.read(vcfParseResultProvider) == null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            const UploadScreen(returnToMedicine: true, returnToDashboard: false),
      ));
      return;
    }

    // Navigate to PrescriptionScanScreen, then forward result to DrugInputScreen
    final result = await Navigator.of(context).push<PrescriptionScanResult>(
      MaterialPageRoute(builder: (_) => const PrescriptionScanScreen()),
    );

    if (!context.mounted || result == null) return;

    // Pre-fill the drug input screen with OCR medicines
    if (result.medicines.isNotEmpty) {
      ref.read(customDrugTextProvider.notifier).state =
          result.medicines.join(', ');
    }

    if (context.mounted) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const DrugInputScreen()));
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parseResult = ref.watch(vcfParseResultProvider);
    final scan = ref.watch(genomicScanReportProvider);
    final reportsAsync = ref.watch(userReportsStreamProvider);
    final latestReport = reportsAsync.valueOrNull?.isNotEmpty == true
        ? reportsAsync.valueOrNull!.first
        : null;
    final genes = parseResult?.geneProfiles.length ?? 0;
    final actionableGenes = parseResult?.geneProfiles.values
            .where((g) => g.phenotype != 'Unknown')
            .length ??
        0;
    final watchCount = scan?.actionableReports.length ?? 0;
    final displayName = ref.watch(userProfileProvider)?.displayName ??
        FirebaseService.currentUser?.displayName ??
        'there';
    final hasVcf = parseResult != null;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceLight,
        title: Row(
          children: [
            const NoCapRxEmblem(
              size: 32,
              borderRadius: 9,
              showShadow: false,
            ),
            const SizedBox(width: 10),
            Text(
              'NoCapRX',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.deepInk,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Check a medicine',
            icon: const Icon(Icons.medication_outlined),
            onPressed: () => _openMedicine(context, ref),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PatientProfileScreen()));
                  break;
                case 'reports':
                  Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HistoryScreen()));
                  break;
                case 'sign_out':
                  _signOut(context, ref);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('My profile')),
              PopupMenuItem(value: 'reports', child: Text('Reports')),
              PopupMenuItem(value: 'sign_out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(userReportsStreamProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            children: [
              // ── Hero card ────────────────────────────────────────────
              _buildHeroCard(displayName, hasVcf, () => _openUpload(context)),
              const SizedBox(height: 18),

              // ── VCF empty state ───────────────────────────────────────
              if (!hasVcf)
                _buildEmptyState(() => _openUpload(context))
              else ...[
                // ── Summary row ────────────────────────────────────────
                _buildSummaryRow(
                  context,
                  ref,
                  genes,
                  actionableGenes,
                  watchCount,
                  latestReport,
                  scan,
                  parseResult,
                ),
                const SizedBox(height: 18),

                // ── Quick actions ──────────────────────────────────────
                Text(
                  'Quick actions',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.deepInk,
                  ),
                ),
                const SizedBox(height: 10),

                // Scan Prescription — primary CTA
                _buildActionCard(
                  icon: Icons.document_scanner_rounded,
                  iconColor: AppTheme.primaryEmerald,
                  iconBg: AppTheme.mintSurface,
                  title: 'Scan Prescription',
                  subtitle:
                      'Photograph a prescription — AI reads the medicines then analyses your genetics.',
                  badge: 'NEW',
                  badgeColor: Colors.deepOrange,
                  onTap: () => _openPrescriptionScan(context, ref),
                ),
                const SizedBox(height: 10),

                // Check Medicine Manually
                _buildActionCard(
                  icon: Icons.medication_outlined,
                  iconColor: Colors.indigo,
                  iconBg: Colors.indigo.shade50,
                  title: 'Check Medicine',
                  subtitle:
                      'Enter a generic name, brand name, or alias for any medicine.',
                  onTap: () => _openMedicine(context, ref),
                ),
                const SizedBox(height: 10),

                // Drugs to Watch
                _buildActionCard(
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.deepOrange,
                  iconBg: Colors.deepOrange.shade50,
                  title: 'Drugs to Watch',
                  subtitle: watchCount == 0
                      ? 'Review all 16 medicines vs your genetic profile.'
                      : '$watchCount medicine(s) flagged by your genetic profile.',
                  badgeCount: watchCount,
                  onTap: () => _openWatchlist(context, ref, scan),
                ),
                const SizedBox(height: 18),

                // ── Latest report ──────────────────────────────────────
                if (latestReport != null) ...[
                  Text(
                    'Latest report',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.deepInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildLatestReportCard(context, latestReport),
                  const SizedBox(height: 18),
                ],

                // ── Insight card ───────────────────────────────────────
                _buildInsightCard(
                    actionableGenes, () => _openProfile(context, parseResult)),
              ],

              const SizedBox(height: 18),
              // ── AI chatbot card ────────────────────────────────────────
              _buildAiCard(context, latestReport),

              const SizedBox(height: 12),
              _buildAskNocapRxCard(context),

              const SizedBox(height: 18),
              // ── Privacy badge ──────────────────────────────────────────
              _buildPrivacyBadge(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Widget builders ──────────────────────────────────────────────────────

  Widget _buildHeroCard(
      String name, bool analyzed, VoidCallback onUpload) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3A2E), Color(0xFF1B5E44)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $name 👋',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Know your genes. Understand your medicines.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'v2.4',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: analyzed ? null : onUpload,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: analyzed
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: analyzed
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.amber.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    analyzed ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                    color: analyzed ? AppTheme.vibrantMint : Colors.amberAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      analyzed
                          ? 'Genetic profile loaded'
                          : 'Upload your VCF file to begin',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (!analyzed)
                    Text(
                      'Upload →',
                      style: GoogleFonts.inter(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(VoidCallback onUpload) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.biotech_outlined, size: 52, color: AppTheme.accentEmerald),
            const SizedBox(height: 14),
            Text(
              'Build your medication safety profile',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.deepInk,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Upload a VCF file to identify genetic information relevant to your medicines. '
              'Raw genetic data stays on your phone.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.secondaryInk,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Upload VCF File'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryEmerald,
                minimumSize: const Size(200, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    WidgetRef ref,
    int genes,
    int actionable,
    int watchCount,
    PgxMultiReport? latest,
    GenomicDrugScanReport? scan,
    dynamic parseResult,
  ) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            icon: Icons.biotech_outlined,
            color: AppTheme.accentEmerald,
            label: 'Genes',
            value: '$genes analysed',
            onTap: () => _openProfile(context, parseResult),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            icon: Icons.warning_amber_rounded,
            color: Colors.deepOrange,
            label: 'Flagged',
            value: '$watchCount medicines',
            onTap: () => _openWatchlist(context, ref, scan),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            icon: Icons.assignment_outlined,
            color: Colors.indigo,
            label: 'Reports',
            value: latest != null ? '${latest.drugReports.length} last' : 'None yet',
            onTap: latest == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ResultsScreen(report: latest)),
                    ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    String? badge,
    Color? badgeColor,
    int? badgeCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.deepInk,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor ?? Colors.deepOrange,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (badgeCount != null && badgeCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$badgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.secondaryInk,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppTheme.mutedGrey),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestReportCard(BuildContext context, PgxMultiReport report) {
    final drugs = report.drugReports.map((d) => d.drug).join(', ');
    final date = report.timestamp.split('T').first;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultsScreen(report: report)),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment_turned_in_outlined,
                  color: Colors.indigo, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drugs,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.deepInk,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$date · ${report.drugReports.length} medicine(s)',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: AppTheme.secondaryInk),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 13, color: AppTheme.mutedGrey),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard(int actionable, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.mintSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppTheme.accentEmerald.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lightbulb_outline, color: AppTheme.primaryEmerald),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                actionable == 0
                    ? 'No major actionable pharmacogenomic findings in your current profile.'
                    : '$actionable gene(s) may affect how some medicines work for you. '
                        'Tap to see your full genetic profile.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: AppTheme.primaryDarkEmerald,
                  height: 1.35,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.accentEmerald),
          ],
        ),
      ),
    );
  }

  Widget _buildAiCard(BuildContext context, PgxMultiReport? latest) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatbotScreen(report: latest)),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.purple, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NoCapRX AI',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.deepInk,
                    ),
                  ),
                  Text(
                    'Ask about your verified medication results.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppTheme.secondaryInk),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 13, color: AppTheme.mutedGrey),
          ],
        ),
      ),
    );
  }

  Widget _buildAskNocapRxCard(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AskNocapRxScreen())),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.primaryEmerald, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ask NOCAPRx', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            Text('Simple answers from your local medicine facts.', style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: .85))),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.white),
        ]),
      ),
    );
  }

  Widget _buildPrivacyBadge() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.mintSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.accentEmerald.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
            Row(
            children: [
              const Icon(Icons.lock_rounded,
                  size: 16, color: AppTheme.primaryEmerald),
              const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Genomic Privacy: AI explains; the rule engine decides.',
                    softWrap: true,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryDarkEmerald,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _privacyRow('VCF processing', '✓ On Device'),
          _privacyRow('Raw VCF uploaded', '0 KB'),
          _privacyRow('Raw genetic data', 'Never uploaded'),
        ],
      ),
    );
  }

  Widget _privacyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 24),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label: ',
              softWrap: true,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppTheme.secondaryInk),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryEmerald,
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, dynamic parseResult) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _GeneticProfileScreen(parseResult: parseResult)));
  }
}

// ─── Metric tile ──────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _MetricTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.deepInk,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppTheme.secondaryInk),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Genetic Profile sub-screen ────────────────────────────────────────────

class _GeneticProfileScreen extends StatelessWidget {
  final dynamic parseResult;
  const _GeneticProfileScreen({required this.parseResult});

  @override
  Widget build(BuildContext context) {
    final profiles = parseResult.geneProfiles.values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Genetic Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${profiles.length} genes analysed',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...profiles.map(
            (gene) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading: Icon(
                  gene.phenotype == 'Unknown'
                      ? Icons.help_outline
                      : Icons.biotech_outlined,
                  color: gene.phenotype == 'Unknown'
                      ? Colors.grey
                      : AppTheme.primaryEmerald,
                ),
                title: Text(
                  gene.gene,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  gene.phenotype == 'Unknown'
                      ? 'No actionable finding'
                      : 'Phenotype: ${gene.phenotype}',
                  style: TextStyle(
                    color: gene.phenotype == 'Unknown'
                        ? Colors.grey
                        : AppTheme.primaryEmerald,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Diplotype', gene.diplotype),
                        _row('Phenotype', gene.phenotype),
                        _row(
                          'Variants',
                          gene.variants.isEmpty
                              ? 'Not detected in VCF'
                              : gene.variants
                                  .map((v) => v.rsid)
                                  .join(', '),
                        ),
                        if (gene.isInferred)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: const Text(
                              '⚠ Diplotype inferred — no direct VCF annotation for this gene.',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
