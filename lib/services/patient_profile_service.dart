import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/patient_profile.dart';
import 'firebase_service.dart';

class PatientProfileService {
  static const _legacyKey = 'patient_profile';
  static final Map<String, PatientProfile> _memoryCache = {};

  static String get _key {
    final uid = FirebaseService.currentUser?.uid;
    return uid == null ? _legacyKey : '$_legacyKey:$uid';
  }

  static Future<PatientProfile> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      if (value != null) {
        final profile = PatientProfile.fromJson(jsonDecode(value) as Map<String, dynamic>);
        _memoryCache[_key] = profile;
        return profile;
      }
    } catch (e) {
      debugPrint('PatientProfileService.load error: $e');
    }
    return _memoryCache[_key] ?? const PatientProfile();
  }

  static Future<void> save(PatientProfile profile) async {
    _memoryCache[_key] = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(profile.toJson()));
    } catch (e) {
      debugPrint('PatientProfileService.save error: $e');
    }
  }

  static Future<void> clear() async {
    _memoryCache.remove(_key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}