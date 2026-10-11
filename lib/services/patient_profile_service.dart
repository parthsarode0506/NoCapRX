import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/patient_profile.dart';

class PatientProfileService {
  static const _keyPrefix = 'patient_profile';
  static PatientProfile _memoryCache = const PatientProfile();

  static String? _resolveUid([String? userId]) {
    if (userId != null && userId.isNotEmpty) return userId;
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance.currentUser?.uid;
      }
    } catch (_) {}
    return null;
  }

  static bool get _hasFirebase {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<PatientProfile> load([String? userId]) async {
    final uid = _resolveUid(userId);
    final key = uid == null ? _keyPrefix : '${_keyPrefix}_$uid';
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(key);
      if (value != null) {
        final profile = PatientProfile.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
        _memoryCache = profile;
        return profile;
      }

      // If not in local storage, try Firestore
      if (_hasFirebase && uid != null && uid.isNotEmpty) {
        try {
          final doc =
              await FirebaseFirestore.instance.collection('users').doc(uid).get();
          if (doc.exists) {
            final data = doc.data();
            if (data != null) {
              final rawProfile = data['patientProfile'];
              if (rawProfile is Map) {
                final profile = PatientProfile.fromJson(
                  Map<String, dynamic>.from(rawProfile),
                );
                _memoryCache = profile;
                await prefs.setString(key, jsonEncode(profile.toJson()));
                return profile;
              } else if (data['displayName'] != null ||
                  data['fullName'] != null) {
                final profile = PatientProfile(
                  fullName:
                      (data['fullName'] ?? data['displayName'] ?? '') as String,
                  patientId: (data['patientId'] ?? '') as String,
                  email: (data['email'] ?? '') as String,
                  phoneNumber:
                      (data['phoneNumber'] ?? data['phone'] ?? '') as String,
                  dateOfBirth: (data['dateOfBirth'] ?? '') as String,
                  age: (data['age'] ?? '') as String,
                  sex: (data['sex'] ?? '') as String,
                  weight: (data['weight'] ?? '') as String,
                  height: (data['height'] ?? '') as String,
                  allergies:
                      (data['allergies'] as List?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      const [],
                  currentMedicines:
                      (data['currentMedicines'] as List?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      const [],
                  conditions:
                      (data['conditions'] as List?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      const [],
                );
                if (profile.hasData) {
                  _memoryCache = profile;
                  await prefs.setString(key, jsonEncode(profile.toJson()));
                  return profile;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('PatientProfileService Firestore fetch note: $e');
        }
      }
    } catch (e) {
      debugPrint('PatientProfileService.load error: $e');
    }
    _memoryCache = const PatientProfile();
    return _memoryCache;
  }

  static Future<void> save(PatientProfile profile, [String? userId]) async {
    _memoryCache = profile;
    final uid = _resolveUid(userId);
    final key = uid == null ? _keyPrefix : '${_keyPrefix}_$uid';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(profile.toJson()));

      // Sync non-sensitive demographic details to Firestore for cloud account persistence
      if (_hasFirebase && uid != null && uid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'patientProfile': profile.toJson(),
            if (profile.fullName.isNotEmpty) 'displayName': profile.fullName,
            if (profile.phoneNumber.isNotEmpty)
              'phoneNumber': profile.phoneNumber,
            'hasCompletedIntake': profile.hasCompletedIntake,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('PatientProfileService Firestore sync note: $e');
        }
      }
    } catch (e) {
      debugPrint('PatientProfileService.save error: $e');
    }
  }

  static Future<void> clearMemory() async {
    _memoryCache = const PatientProfile();
  }

  static Future<void> clear([String? userId]) async {
    _memoryCache = const PatientProfile();
    final uid = _resolveUid(userId);
    final key = uid == null ? _keyPrefix : '${_keyPrefix}_$uid';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}