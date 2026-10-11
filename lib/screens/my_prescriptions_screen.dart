import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/prescription.dart';
import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../services/prescription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class MyPrescriptionsScreen extends ConsumerStatefulWidget {
  const MyPrescriptionsScreen({super.key});

  @override
  ConsumerState<MyPrescriptionsScreen> createState() =>
      _MyPrescriptionsScreenState();
}

class _MyPrescriptionsScreenState extends ConsumerState<MyPrescriptionsScreen> {
  String _filter = 'all'; // 'all', 'issued', 'draft'

  @override
  Widget build(BuildContext context) {
    final patientProfile = ref.watch(patientProfileProvider);
    final user = FirebaseService.currentUser;
    final patientId = patientProfile.patientId.trim().isNotEmpty
        ? patientProfile.patientId.trim()
        : (user?.uid ?? '');

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('My Prescriptions'),
      ),
      body: SafeArea(
        child: patientId.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Please sign in to view your prescriptions.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : StreamBuilder<List<Prescription>>(
          stream: PrescriptionService.instance.streamPatientPrescriptions(
            patientId,
            patientUid: user?.uid,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Published prescriptions could not be loaded. Current access could not be confirmed.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final allPrescriptions = snapshot.data ?? [];
            final prescriptions = allPrescriptions.where((p) {
              if (_filter == 'issued') return p.isIssued;
              if (_filter == 'draft') return p.isDraft;
              return true;
            }).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                // Header Hero
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.medication_rounded,
                              color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'Prescription Records',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Prescriptions published by your healthcare providers. Any PGx status shown is advisory and may be indeterminate.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Filters
                Row(
                  children: [
                    _buildFilterChip('All (${allPrescriptions.length})', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Issued (${allPrescriptions.where((p) => p.isIssued).length})',
                      'issued',
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Drafts (${allPrescriptions.where((p) => p.isDraft).length})',
                      'draft',
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Prescriptions List
                if (prescriptions.isEmpty)
                  _buildEmptyState()
                else
                  ...prescriptions.map((p) => _buildPrescriptionCard(context, p)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppTheme.primaryEmerald.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? AppTheme.primaryEmerald : AppTheme.deepInk,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.infoBlueBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_outlined,
                  size: 40, color: AppTheme.infoBlue),
            ),
            const SizedBox(height: 16),
            Text(
              'No Prescriptions Found',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.deepInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Prescriptions published by an authorized clinic or hospital will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrescriptionCard(BuildContext context, Prescription prescription) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a')
        .format(prescription.issuedAt ?? prescription.createdAt);

    final statusColor = prescription.isIssued
        ? AppTheme.safeGreen
        : (prescription.isDraft ? AppTheme.warningAmber : AppTheme.dangerRed);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            prescription.isIssued
                ? Icons.verified_outlined
                : Icons.pending_actions_outlined,
            color: statusColor,
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                prescription.organizationName,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.deepInk,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                prescription.status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${prescription.prescriberName} · $dateStr',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Prescription ID: ${prescription.prescriptionId}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              if (prescription.hasActionableRisks)
                PillBadge(
                  label: 'CPIC Risk Monitored',
                  color: AppTheme.warningAmber,
                  icon: Icons.shield,
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Medicines List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: prescription.items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final med = prescription.items[idx];
              Color riskColor = AppTheme.unknownSlate;
              if (med.isActionableRisk) {
                riskColor = AppTheme.dangerRed;
              } else if (med.isCaution) {
                riskColor = AppTheme.warningAmber;
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: AppTheme.primaryEmerald),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            med.medicineName,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: riskColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            med.pgxRiskLabel,
                            style: TextStyle(
                              color: riskColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        '${med.dosage} · ${med.frequency} · ${med.duration}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (med.instructions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          'Instructions: ${med.instructions}',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                    if (med.recommendation != null &&
                        med.recommendation!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          'Clinical Note: ${med.recommendation}',
                          style: TextStyle(
                            fontSize: 11,
                            color: riskColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          if (prescription.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Clinician Directions: ${prescription.notes}',
                style: const TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
