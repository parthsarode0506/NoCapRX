import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audit_log.dart';
import 'firebase_service.dart';

class AuditService {
  AuditService._();
  static final AuditService instance = AuditService._();

  static const String _localAuditLogsKey = 'nocaprx_local_audit_logs';
  final List<AuditLogEntry> _inMemoryLogs = [];

  Future<void> _initDefaultsIfEmpty() async {
    if (_inMemoryLogs.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localAuditLogsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          _inMemoryLogs.add(AuditLogEntry.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      }
    } catch (e) {
      debugPrint('Error loading audit logs: $e');
    }

  }

  Future<void> clearAllLogs() async {
    _inMemoryLogs.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localAuditLogsKey);
    } catch (_) {}
  }

  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _inMemoryLogs.map((l) => l.toJson()).toList();
      await prefs.setString(_localAuditLogsKey, jsonEncode(list));
    } catch (e) {
      debugPrint('Failed to persist audit logs: $e');
    }
  }

  Stream<List<AuditLogEntry>> streamAuditLogs({String? organizationId}) async* {
    await _initDefaultsIfEmpty();

    final localMatches = _inMemoryLogs
        .where((l) =>
            organizationId == null ||
            organizationId.isEmpty ||
            organizationId == 'any' ||
            l.organizationId == organizationId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    yield localMatches;

    if (!FirebaseService.isCloudAvailable) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final query = (organizationId == null ||
              organizationId.isEmpty ||
              organizationId == 'any')
          ? firestore
              .collection('auditLogs')
              .orderBy('timestamp', descending: true)
              .limit(50)
          : firestore
              .collection('auditLogs')
              .where('organizationId', isEqualTo: organizationId)
              .limit(50);

      await for (final snapshot in query.snapshots()) {
        for (final doc in snapshot.docs) {
          final entry = AuditLogEntry.fromJson({
            ...doc.data(),
            'id': doc.id,
          });
          if (!_inMemoryLogs.any((l) => l.id == entry.id)) {
            _inMemoryLogs.insert(0, entry);
          }
        }

        final combined = _inMemoryLogs
            .where((l) =>
                organizationId == null ||
                organizationId.isEmpty ||
                organizationId == 'any' ||
                l.organizationId == organizationId)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        await _persistLocal();
        yield combined;
      }
    } catch (e) {
      debugPrint('Cloud audit log stream notice: $e');
      yield localMatches;
    }
  }

  Future<void> recordLog({
    required String action,
    required String actorUid,
    required String actorRole,
    required String organizationId,
    required String targetId,
    required String description,
    Map<String, dynamic> metadata = const {},
  }) async {
    await _initDefaultsIfEmpty();

    final entry = AuditLogEntry(
      id: 'AUDIT-${DateTime.now().millisecondsSinceEpoch}',
      action: action,
      actorUid: actorUid,
      actorRole: actorRole,
      organizationId: organizationId,
      targetId: targetId,
      description: description,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    _inMemoryLogs.insert(0, entry);
    await _persistLocal();

    if (FirebaseService.isCloudAvailable) {
      try {
        await FirebaseFirestore.instance
            .collection('auditLogs')
            .doc(entry.id)
            .set(entry.toJson());
      } catch (e) {
        debugPrint('Cloud audit log write notice: $e');
      }
    }
  }
}
