import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/patient_profile.dart';

class PatientProfileService {
  static const _key = 'patient_profile';
  static PatientProfile _memoryCache = const PatientProfile();

  static Future<PatientProfile> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      if (value != null) {
        final profile = PatientProfile.fromJson(jsonDecode(value) as Map<String, dynamic>);
        _memoryCache = profile;
        return profile;
      }
    } catch (e) {
      debugPrint('PatientProfileService.load error: $e');
    }
    return _memoryCache;
  }

  static Future<void> save(PatientProfile profile) async {
    _memoryCache = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(profile.toJson()));
    } catch (e) {
      debugPrint('PatientProfileService.save error: $e');
    }
  }

  static Future<void> clear() async {
    _memoryCache = const PatientProfile();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}