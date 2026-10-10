import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prescription.dart';
import 'audit_service.dart';
import 'firebase_service.dart';

class PrescriptionService {
  PrescriptionService._();
  static final PrescriptionService instance = PrescriptionService._();

  static const String _localPrescriptionsKey = 'nocaprx_local_prescriptions';
  final Map<String, Prescription> _inMemoryCache = {};

  Future<void> _initDefaultsIfEmpty() async {
    if (_inMemoryCache.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localPrescriptionsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final p = Prescription.fromJson(Map<String, dynamic>.from(item as Map));
          _inMemoryCache[p.prescriptionId] = p;
        }
      }
    } catch (e) {
      debugPrint('Error loading cached prescriptions: $e');
    }

    if (_inMemoryCache.isEmpty) {
      // Seed demonstration sample prescription for PATIENT_001
      final sample = Prescription(
        prescriptionId: 'RX-98241',
        patientId: 'PATIENT_001',
        patientName: 'Alex Mercer',
        organizationId: 'ORG-APOLLO-01',
        organizationName: 'Apollo Clinical Genomics Center',
        prescriberId: 'DOC-5501',
        prescriberName: 'Dr. Sarah Jenkins, MD (Cardiology)',
        status: 'issued',
        notes: 'Patient post-PCI stenting. Pharmacogenomic profile reviewed prior to clopidogrel prescription.',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        issuedAt: DateTime.now().subtract(const Duration(days: 3)),
        items: const [
          PrescriptionItem(
            medicineName: 'Prasugrel',
            dosage: '10 mg',
            frequency: 'Once daily',
            duration: '30 days',
            instructions: 'Take with or without food at the same time daily.',
            pgxRiskLabel: 'Safe',
            severity: 'none',
            gene: 'CYP2C19',
            phenotype: 'CYP2C19 Intermediate Metabolizer',
            recommendation: 'Selected as safer guideline-supported alternative to Clopidogrel for CYP2C19 *1/*2.',
            alternativeDrugs: ['Ticagrelor'],
          ),
          PrescriptionItem(
            medicineName: 'Rosuvastatin',
            dosage: '20 mg',
            frequency: 'Once daily at bedtime',
            duration: '90 days',
            instructions: 'Avoid high consumption of grapefruit juice.',
            pgxRiskLabel: 'Safe',
            severity: 'none',
            gene: 'SLCO1B1',
            phenotype: 'SLCO1B1 Normal Function',
            recommendation: 'Standard dosing appropriate. Normal myopathy risk.',
          ),
        ],
      );
      _inMemoryCache[sample.prescriptionId] = sample;
      await _persistLocal();
    }
  }

  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _inMemoryCache.values.map((p) => p.toJson()).toList();
      await prefs.setString(_localPrescriptionsKey, jsonEncode(list));
    } catch (e) {
      debugPrint('Failed to persist prescriptions locally: $e');
    }
  }

  Stream<List<Prescription>> streamPatientPrescriptions(
    String patientId, {
    String? patientUid,
  }) async* {
    await _initDefaultsIfEmpty();

    // Yield local / in-memory first for instant UI response
    final localMatches = _inMemoryCache.values
        .where((p) =>
            p.patientId.toUpperCase() == patientId.toUpperCase() ||
            (patientUid != null && p.patientUid == patientUid))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield localMatches;

    if (!FirebaseService.isCloudAvailable) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final query = firestore
          .collection('prescriptions')
          .where('patientId', isEqualTo: patientId);

      await for (final snapshot in query.snapshots()) {
        final cloudItems = <Prescription>[];
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final item = Prescription.fromJson({
            ...data,
            'prescriptionId': doc.id,
          });
          cloudItems.add(item);
          _inMemoryCache[item.prescriptionId] = item;
        }

        final combined = _inMemoryCache.values
            .where((p) =>
                p.patientId.toUpperCase() == patientId.toUpperCase() ||
                (patientUid != null && p.patientUid == patientUid))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        await _persistLocal();
        yield combined;
      }
    } catch (e) {
      debugPrint('Cloud prescription stream notice: $e');
      yield localMatches;
    }
  }

  Stream<List<Prescription>> streamOrganizationPrescriptions(
    String organizationId,
  ) async* {
    await _initDefaultsIfEmpty();

    final localMatches = _inMemoryCache.values
        .where((p) =>
            p.organizationId.isEmpty ||
            p.organizationId == organizationId ||
            organizationId == 'any')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield localMatches;

    if (!FirebaseService.isCloudAvailable) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final query = organizationId == 'any'
          ? firestore.collection('prescriptions')
          : firestore
              .collection('prescriptions')
              .where('organizationId', isEqualTo: organizationId);

      await for (final snapshot in query.snapshots()) {
        for (final doc in snapshot.docs) {
          final item = Prescription.fromJson({
            ...doc.data(),
            'prescriptionId': doc.id,
          });
          _inMemoryCache[item.prescriptionId] = item;
        }

        final combined = _inMemoryCache.values
            .where((p) =>
                p.organizationId.isEmpty ||
                p.organizationId == organizationId ||
                organizationId == 'any')
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        await _persistLocal();
        yield combined;
      }
    } catch (e) {
      debugPrint('Cloud org prescription stream notice: $e');
      yield localMatches;
    }
  }

  Future<void> savePrescription(Prescription prescription) async {
    await _initDefaultsIfEmpty();
    _inMemoryCache[prescription.prescriptionId] = prescription;
    await _persistLocal();

    // Log to Audit Log
    await AuditService.instance.recordLog(
      action: prescription.status == 'issued'
          ? 'prescription_issued'
          : 'prescription_draft_saved',
      actorUid: FirebaseService.currentUser?.uid ?? prescription.prescriberId,
      actorRole: 'doctor',
      organizationId: prescription.organizationId,
      targetId: prescription.patientId,
      description:
          'Prescription ${prescription.prescriptionId} (${prescription.status}) with ${prescription.items.length} medicines created for ${prescription.patientName}.',
      metadata: {
        'prescriptionId': prescription.prescriptionId,
        'medicines': prescription.items.map((i) => i.medicineName).toList(),
        'hasActionableRisks': prescription.hasActionableRisks,
      },
    );

    if (FirebaseService.isCloudAvailable) {
      try {
        await FirebaseFirestore.instance
            .collection('prescriptions')
            .doc(prescription.prescriptionId)
            .set(prescription.toJson(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('Prescription cloud sync notice: $e');
      }
    }
  }

  Future<void> issuePrescription(String prescriptionId) async {
    await _initDefaultsIfEmpty();
    final existing = _inMemoryCache[prescriptionId];
    if (existing == null) return;

    final updated = existing.copyWith(
      status: 'issued',
      issuedAt: DateTime.now(),
    );
    await savePrescription(updated);
  }

  Future<void> cancelPrescription(String prescriptionId, {String reason = ''}) async {
    await _initDefaultsIfEmpty();
    final existing = _inMemoryCache[prescriptionId];
    if (existing == null) return;

    final updated = existing.copyWith(
      status: 'cancelled',
      notes: reason.isNotEmpty ? '${existing.notes}\nCancelled: $reason' : existing.notes,
    );
    await savePrescription(updated);
  }
}
