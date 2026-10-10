import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/audit_log.dart';
import '../models/prescription.dart';
import '../services/audit_service.dart';
import '../services/firebase_service.dart';
import '../services/prescription_service.dart';
import '../theme/app_theme.dart';

class OrganizationAuditScreen extends StatefulWidget {
  const OrganizationAuditScreen({super.key});

  @override
  State<OrganizationAuditScreen> createState() =>
      _OrganizationAuditScreenState();
}

class _OrganizationAuditScreenState extends State<OrganizationAuditScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orgId = FirebaseService.currentUser?.uid ?? 'ORG_ACTIVE';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical History & Audit Logs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history_edu), text: 'Prescription Records'),
            Tab(icon: Icon(Icons.security), text: 'Audit Trail'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPrescriptionHistoryTab(orgId),
          _buildAuditTrailTab(orgId),
        ],
      ),
    );
  }

  Widget _buildPrescriptionHistoryTab(String orgId) {
    return StreamBuilder<List<Prescription>>(
      stream: PrescriptionService.instance.streamOrganizationPrescriptions(orgId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final prescriptions = snapshot.data ?? [];

        if (prescriptions.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.medication_outlined,
                    size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'Prescription records are available in each consent-authorized patient workspace.',
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: prescriptions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final p = prescriptions[index];
            final dateStr = DateFormat('dd MMM yyyy, hh:mm a')
                .format(p.issuedAt ?? p.createdAt);

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.isIssued
                              ? AppTheme.safeGreen.withValues(alpha: 0.12)
                              : AppTheme.warningAmber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.status.toUpperCase(),
                          style: TextStyle(
                            color: p.isIssued
                                ? AppTheme.safeGreen
                                : AppTheme.warningAmber,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'ID: ${p.prescriptionId}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Patient: ${p.patientName} (${p.patientId})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Prescriber: ${p.prescriberName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: p.items.map((i) {
                      Color riskColor = AppTheme.safeGreen;
                      if (i.isActionableRisk) riskColor = AppTheme.dangerRed;
                      if (i.isCaution) riskColor = AppTheme.warningAmber;

                      return Chip(
                        label: Text(
                          '${i.medicineName} (${i.dosage})',
                          style: TextStyle(fontSize: 11, color: riskColor),
                        ),
                        backgroundColor: riskColor.withValues(alpha: 0.08),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAuditTrailTab(String orgId) {
    return StreamBuilder<List<AuditLogEntry>>(
      stream: AuditService.instance.streamAuditLogs(organizationId: 'any'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data ?? [];

        return ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: logs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final entry = logs[index];
            final dateStr = DateFormat('dd MMM yyyy, hh:mm:ss a')
                .format(entry.timestamp);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryEmerald.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined,
                        size: 20, color: AppTheme.primaryEmerald),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              entry.action.replaceAll('_', ' ').toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryEmerald,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.description,
                          style: const TextStyle(fontSize: 13, height: 1.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Actor: ${entry.actorRole} (${entry.actorUid}) · Target: ${entry.targetId}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
