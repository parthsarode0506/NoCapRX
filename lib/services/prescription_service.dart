import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
          if (p.prescriptionId == 'RX-98241') continue;
          _inMemoryCache[p.prescriptionId] = p;
        }
      }
    } catch (e) {
      debugPrint('Error loading cached prescriptions: $e');
    }
  }

  Future<void> clearAllPrescriptions() async {
    _inMemoryCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localPrescriptionsKey);
    } catch (_) {}
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

    List<Prescription> getLocalMatches() {
      final pid = patientId.trim().toUpperCase();
      final puid = patientUid?.trim() ?? '';
      final curUid = FirebaseService.currentUser?.uid ?? '';
      final matches = _inMemoryCache.values
          .where((p) =>
              pid == 'ALL' ||
              (pid.isNotEmpty && pid != 'PATIENT_001' && p.patientId.toUpperCase() == pid) ||
              (puid.isNotEmpty && p.patientUid == puid) ||
              (puid.isNotEmpty && p.patientId == puid) ||
              (curUid.isNotEmpty && p.patientUid == curUid) ||
              (curUid.isNotEmpty && p.patientId == curUid))
          .toList()
        ..sort((a, b) =>
            (b.issuedAt ?? b.createdAt).compareTo(a.issuedAt ?? a.createdAt));
      return matches;
    }

    yield getLocalMatches();

    if (FirebaseService.isCloudAvailable) {
      final targetIds = <String>{};
      if (patientId.trim().isNotEmpty &&
          patientId.trim().toUpperCase() != 'PATIENT_001') {
        targetIds.add(patientId.trim());
      }
      if (patientUid?.trim().isNotEmpty == true) {
        targetIds.add(patientUid!.trim());
      }
      final curUid = FirebaseService.currentUser?.uid;
      if (curUid != null && curUid.trim().isNotEmpty) {
        targetIds.add(curUid.trim());
      }

      if (targetIds.isNotEmpty) {
        final controller = StreamController<List<Prescription>>();
        final cloudPrescriptions = <String, Prescription>{};
        final subscriptions = <StreamSubscription>[];

        void emitMerged() {
          if (controller.isClosed) return;
          final localList = getLocalMatches();
          final map = <String, Prescription>{};
          for (final p in localList) {
            map[p.prescriptionId] = p;
          }
          for (final p in cloudPrescriptions.values) {
            map[p.prescriptionId] = p;
          }
          final list = map.values.toList()
            ..sort((a, b) =>
                (b.issuedAt ?? b.createdAt).compareTo(a.issuedAt ?? a.createdAt));
          controller.add(list);
        }

        for (final id in targetIds) {
          for (final col in ['patients', 'users']) {
            try {
              final sub = FirebaseFirestore.instance
                  .collection(col)
                  .doc(id)
                  .collection('prescriptions')
                  .snapshots()
                  .listen(
                (snapshot) {
                  for (final doc in snapshot.docs) {
                    try {
                      final p = _fromCloudDocument(doc.id, doc.data());
                      cloudPrescriptions[p.prescriptionId] = p;
                      _inMemoryCache[p.prescriptionId] = p;
                    } catch (_) {}
                  }
                  _persistLocal();
                  emitMerged();
                },
                onError: (e) {
                  debugPrint('Prescription listen error on $col/$id: $e');
                },
              );
              subscriptions.add(sub);
            } catch (_) {}
          }
        }

        controller.onCancel = () {
          for (final sub in subscriptions) {
            sub.cancel();
          }
          controller.close();
        };

        yield* controller.stream;
      }
    }
  }

  Stream<List<Prescription>> streamAuthorizedPatientPrescriptions(
    String patientId,
  ) async* {
    await _initDefaultsIfEmpty();
    final localMatches = _inMemoryCache.values
        .where((p) => p.patientId.toUpperCase() == patientId.toUpperCase())
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    yield localMatches;

    if (FirebaseService.isCloudAvailable && patientId.trim().isNotEmpty) {
      try {
        final query = FirebaseFirestore.instance
            .collection('patients')
            .doc(patientId.trim())
            .collection('prescriptions');
        await for (final snapshot in query.snapshots()) {
          final cloudList = snapshot.docs
              .map((doc) => _fromCloudDocument(doc.id, doc.data()))
              .toList(growable: false);
          final map = <String, Prescription>{};
          for (final p in localMatches) {
            map[p.prescriptionId] = p;
          }
          for (final p in cloudList) {
            map[p.prescriptionId] = p;
            _inMemoryCache[p.prescriptionId] = p;
          }
          final list = map.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          yield list;
        }
      } catch (_) {
        yield localMatches;
      }
    }
  }


  Stream<List<Prescription>> streamOrganizationPrescriptions(
    String organizationId,
  ) async* {
    if (organizationId.trim().isEmpty) {
      throw ArgumentError.value(organizationId, 'organizationId');
    }
    await _initDefaultsIfEmpty();
    yield _inMemoryCache.values
        .where((p) => p.organizationId == organizationId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> savePrescription(Prescription prescription) async {
    await _initDefaultsIfEmpty();
    _inMemoryCache[prescription.prescriptionId] = prescription;
    await _persistLocal();

    if (FirebaseService.isCloudAvailable) {
      try {
        final firestore = FirebaseFirestore.instance;
        final data = prescription.toJson();
        if (prescription.patientId.isNotEmpty) {
          await firestore
              .collection('patients')
              .doc(prescription.patientId)
              .collection('prescriptions')
              .doc(prescription.prescriptionId)
              .set(data, SetOptions(merge: true));
        }

        if (prescription.patientUid != null &&
            prescription.patientUid!.isNotEmpty) {
          await firestore
              .collection('users')
              .doc(prescription.patientUid!)
              .collection('prescriptions')
              .doc(prescription.prescriptionId)
              .set(data, SetOptions(merge: true));

          await firestore
              .collection('patients')
              .doc(prescription.patientUid!)
              .collection('prescriptions')
              .doc(prescription.prescriptionId)
              .set(data, SetOptions(merge: true));
        }

        if (prescription.patientId.isNotEmpty &&
            prescription.patientId != prescription.patientUid) {
          await firestore
              .collection('users')
              .doc(prescription.patientId)
              .collection('prescriptions')
              .doc(prescription.prescriptionId)
              .set(data, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('Firestore save prescription notice: $e');
      }
    }

    // Log to Audit Log
    try {
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
    } catch (_) {}
  }

  Future<void> saveOrganizationPrescription(Prescription prescription) async {
    await savePrescription(prescription);
    if (FirebaseService.isCloudAvailable) {
      try {
        await FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('saveOrganizationPrescription')
            .call(<String, Object?>{
              'patientId': prescription.patientId,
              'prescriptionId': prescription.prescriptionId,
              'items': prescription.items
                  .map(
                    (item) => <String, Object?>{
                      'medicineName': item.medicineName,
                      'dosage': item.dosage,
                      'frequency': item.frequency,
                      'duration': item.duration,
                      'instructions': item.instructions,
                    },
                  )
                  .toList(growable: false),
              'notes': prescription.notes,
            });
      } catch (e) {
        debugPrint('Cloud function saveOrganizationPrescription notice: $e');
      }
    }
  }

  Future<void> publishOrganizationPrescription(
    Prescription prescription,
  ) async {
    final issuedPrescription = prescription.copyWith(
      status: 'issued',
      issuedAt: DateTime.now(),
    );
    await savePrescription(issuedPrescription);

    if (FirebaseService.isCloudAvailable) {
      try {
        await FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('publishOrganizationPrescription')
            .call(<String, Object?>{
              'patientId': issuedPrescription.patientId,
              'prescriptionId': issuedPrescription.prescriptionId,
            });
      } catch (e) {
        debugPrint('Cloud function publishOrganizationPrescription notice: $e');
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

  Prescription _fromCloudDocument(
    String id,
    Map<String, dynamic> data,
  ) =>
      Prescription.fromJson({
        ...data,
        'prescriptionId': id,
        'createdAt': _dateString(data['createdAt']),
        'issuedAt': _dateString(data['issuedAt']),
      });

  String? _dateString(Object? value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is String) return value;
    return null;
  }
}
