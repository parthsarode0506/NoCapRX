import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/pgx_report.dart';
import '../theme/app_theme.dart';

class PgxSummaryDashboard extends StatelessWidget {
  final List<PgxMultiReport> reports;
  final VoidCallback? onNewAnalysis;

  const PgxSummaryDashboard({
    super.key,
    required this.reports,
    this.onNewAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    // Compute dynamic stats if reports exist, otherwise use standard baseline
    int safeCount = 0;
    int adjustCount = 0;
    int highRiskCount = 0;
    int unknownCount = 0;
    final Set<String> uniqueGenes = {};
    final Set<String> uniqueDrugs = {};

    if (reports.isNotEmpty) {
      for (final report in reports) {
        for (final drugReport in report.drugReports) {
          uniqueDrugs.add(drugReport.drug.toUpperCase());
          final gene = drugReport.pharmacogenomicProfile.primaryGene;
          if (gene != 'UNMAPPED' && gene != 'NON-PGX') {
            uniqueGenes.add(gene);
          }

          final label = drugReport.riskAssessment.riskLabel.trim();
          if (label == 'Safe') {
            safeCount++;
          } else if (label == 'Adjust Dosage') {
            adjustCount++;
          } else if (label == 'Toxic' || label == 'Ineffective') {
            highRiskCount++;
          } else {
            unknownCount++;
          }
        }
      }
    }

    // Default baseline if no reports have been generated yet
    final genesAnalyzedCount = uniqueGenes.isEmpty ? 6 : uniqueGenes.length;
    final displaySafe = reports.isEmpty ? 3 : safeCount;
    final displayAdjust = reports.isEmpty ? 1 : adjustCount;
    final displayHighRisk = reports.isEmpty ? 1 : highRiskCount;
    final displayUnknown = reports.isEmpty ? 1 : unknownCount;
    final medicinesCheckedCount = uniqueDrugs.isEmpty ? 8 : uniqueDrugs.length;

    final totalRisks = displaySafe + displayAdjust + displayHighRisk + displayUnknown;

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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header Section
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          Icons.bar_chart_rounded,
                          size: 16,
                          color: AppTheme.primaryEmerald,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'YOUR PGx SUMMARY',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.deepInk,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.mintSurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Live Profile',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryDarkEmerald,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$genesAnalyzedCount Genes analyzed',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryInk,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Visual Segmented Risk Ratio Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (displaySafe > 0)
                    Expanded(
                      flex: displaySafe,
                      child: Container(color: AppTheme.safeGreen),
                    ),
                  if (displayAdjust > 0)
                    Expanded(
                      flex: displayAdjust,
                      child: Container(color: AppTheme.warningAmber),
                    ),
                  if (displayHighRisk > 0)
                    Expanded(
                      flex: displayHighRisk,
                      child: Container(color: AppTheme.dangerRed),
                    ),
                  if (displayUnknown > 0)
                    Expanded(
                      flex: displayUnknown,
                      child: Container(color: AppTheme.unknownSlate),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 4-category breakdown grid / list
          Column(
            children: [
              _buildRiskRow(
                dotColor: AppTheme.safeGreen,
                label: 'Normal',
                count: displaySafe,
                total: totalRisks,
              ),
              const SizedBox(height: 6),
              _buildRiskRow(
                dotColor: AppTheme.warningAmber,
                label: 'Dose Adjustment',
                count: displayAdjust,
                total: totalRisks,
              ),
              const SizedBox(height: 6),
              _buildRiskRow(
                dotColor: AppTheme.dangerRed,
                label: 'High Risk',
                count: displayHighRisk,
                total: totalRisks,
              ),
              const SizedBox(height: 6),
              _buildRiskRow(
                dotColor: AppTheme.unknownSlate,
                label: 'Unknown',
                count: displayUnknown,
                total: totalRisks,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Medicines checked footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.lightEmeraldPill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.accentEmerald.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.medication_outlined,
                      size: 15,
                      color: AppTheme.primaryEmerald,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Medicines checked:',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryDarkEmerald,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$medicinesCheckedCount',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryEmerald,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskRow({
    required Color dotColor,
    required String label,
    required int count,
    required int total,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.deepInk,
                ),
              ),
            ],
          ),
          Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }
}
