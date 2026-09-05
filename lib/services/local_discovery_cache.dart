import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drug_evidence.dart';

/// Caches online-discovered drug evidence locally on-device.
/// This preserves offline functionality for previously searched medicines.
class LocalDiscoveryCache {
  static const String _storagePrefix = 'pgx_discovered_drug_';
  static final Map<String, DrugEvidence> _memoryCache = {};
  static bool _initialized = false;

  /// Initializes the local discovery cache from persistent storage.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_storagePrefix));
      for (final key in keys) {
        final jsonStr = prefs.getString(key);
        if (jsonStr != null) {
          final map = json.decode(jsonStr) as Map<String, dynamic>;
          final evidence = DrugEvidence.fromJson(map);
          _memoryCache[evidence.genericName.toUpperCase()] = evidence;
          for (final alias in evidence.aliases) {
            _memoryCache[alias.toUpperCase()] = evidence;
          }
        }
      }
      _initialized = true;
      debugPrint('LocalDiscoveryCache loaded ${_memoryCache.length} cached drug mappings.');
    } catch (e) {
      debugPrint('LocalDiscoveryCache init error: $e');
    }
  }

  /// Retrieves cached DrugEvidence for a drug name or alias if available.
  static DrugEvidence? get(String drugName) {
    final key = drugName.trim().toUpperCase();
    return _memoryCache[key];
  }

  /// Caches a newly validated DrugEvidence locally and asynchronously persists it.
  static Future<void> put(DrugEvidence evidence) async {
    final key = evidence.genericName.toUpperCase();
    _memoryCache[key] = evidence;
    for (final alias in evidence.aliases) {
      _memoryCache[alias.toUpperCase()] = evidence;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(evidence.toJson());
      await prefs.setString('$_storagePrefix$key', jsonStr);
    } catch (e) {
      debugPrint('LocalDiscoveryCache persist error: $e');
    }
  }

  /// Lists all cached drug evidences.
  static List<DrugEvidence> getAllCached() {
    final unique = <String, DrugEvidence>{};
    for (final evidence in _memoryCache.values) {
      unique[evidence.genericName] = evidence;
    }
    return unique.values.toList();
  }

  /// Clears the discovery cache (useful for testing).
  static Future<void> clear() async {
    _memoryCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_storagePrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
