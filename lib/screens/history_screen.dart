import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'results_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(userReportsStreamProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: Text(
          'Past Analysis Reports',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: AppTheme.deepInk,
          ),
        ),
      ),
      body: SafeArea(
        child: reportsAsync.when(
          data: (reports) {
            if (reports.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.lightEmeraldPill,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.history_toggle_off_rounded,
                          size: 48,
                          color: AppTheme.primaryEmerald,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'No Analysis History Found',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.deepInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Derived reports generated on your device will appear here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: AppTheme.secondaryInk,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                final drugNames = report.drugReports.map((d) => d.drug).join(', ');
                final dateStr = report.timestamp.split('T').first;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.lightEmeraldPill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.analytics_outlined,
                        color: AppTheme.primaryEmerald,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      drugNames,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppTheme.deepInk,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        Text(
                          'Patient: ${report.patientId} • File: ${report.vcfFilename}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.secondaryInk,
                          ),
                        ),
                        Text(
                          'Date: $dateStr • ${report.drugReports.length} Drug(s)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.mutedGrey,
                          ),
                        ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
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
              },
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryEmerald),
          ),
          error: (err, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading history: $err',
                style: GoogleFonts.inter(color: AppTheme.dangerRed),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
