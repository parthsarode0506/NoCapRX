import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/organization_access.dart';
import '../models/organization_patient.dart';
import '../models/uploaded_vcf_file.dart';

class ScreenCacheService {
  static const String _keyCachedVcfName = 'nocaprx_cache_vcf_filename';
  static const String _keyCachedVcfContent = 'nocaprx_cache_vcf_content';
  static const String _keyUserVcfsPrefix = 'nocaprx_cache_user_vcfs_';
  static const String _keyCachedUserPrefix = 'nocaprx_cache_user_profile_';
  static const String _keyCachedPrivacyPrefix = 'nocaprx_cache_privacy_accepted_';
  static const String _keyCachedWorkspaceChoice = 'nocaprx_cache_workspace_choice';
  static const String _keyCachedOrganizations = 'nocaprx_cache_organizations_list';
  static const String _keyConnectedPatientsPrefix = 'nocaprx_cache_connected_patients_';
  static const String _keyCachedRequestsPrefix = 'nocaprx_cache_requests_';

  static String _vcfNameKey([String? uid]) =>
      uid != null && uid.isNotEmpty ? '${_keyCachedVcfName}_$uid' : _keyCachedVcfName;
  static String _vcfContentKey([String? uid]) =>
      uid != null && uid.isNotEmpty ? '${_keyCachedVcfContent}_$uid' : _keyCachedVcfContent;

  /// Saves list of multiple uploaded VCF files for a user
  static Future<void> saveUserVcfFiles(String uid, List<UploadedVcfFile> files) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyUserVcfsPrefix$uid';
      final raw = jsonEncode(files.map((f) => f.toJson()).toList());
      await prefs.setString(key, raw);
      if (files.isNotEmpty) {
        // Also keep latest primary cached for quick single-file lookups
        await prefs.setString(_vcfNameKey(uid), files.map((f) => f.fileName).join(', '));
        await prefs.setString(_vcfContentKey(uid), files.last.content);
      }
      debugPrint('ScreenCacheService: Saved ${files.length} VCF files for user $uid');
    } catch (e) {
      debugPrint('ScreenCacheService error saving user VCF files: $e');
    }
  }

  /// Retrieves all uploaded VCF files for a user
  static Future<List<UploadedVcfFile>> getUserVcfFiles(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyUserVcfsPrefix$uid';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((item) =>
                UploadedVcfFile.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('ScreenCacheService error getting user VCF files: $e');
    }
    return [];
  }

  /// Saves the active VCF file and derived analysis into persistent cache memory
  static Future<void> cacheVcfData({
    required String filename,
    required String content,
    String? uid,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid != null && uid.isNotEmpty) {
        await prefs.setString(_vcfNameKey(uid), filename);
        await prefs.setString(_vcfContentKey(uid), content);
      }
      await prefs.setString(_keyCachedVcfName, filename);
      await prefs.setString(_keyCachedVcfContent, content);
      debugPrint('ScreenCacheService: VCF data cached ($filename)');
    } catch (e) {
      debugPrint('ScreenCacheService error caching VCF: $e');
    }
  }

  /// Restores the cached VCF data if available
  static Future<Map<String, String>?> restoreVcfData([String? uid]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid != null && uid.isNotEmpty) {
        final name = prefs.getString(_vcfNameKey(uid));
        final content = prefs.getString(_vcfContentKey(uid));
        if (name != null && content != null && content.isNotEmpty) {
          return {'filename': name, 'content': content};
        }
        // For a specific user ID, do not leak another user's global cache
        return null;
      }
      final name = prefs.getString(_keyCachedVcfName);
      final content = prefs.getString(_keyCachedVcfContent);
      if (name != null && content != null && content.isNotEmpty) {
        return {'filename': name, 'content': content};
      }
    } catch (e) {
      debugPrint('ScreenCacheService error restoring VCF: $e');
    }
    return null;
  }

  /// Clears the cached VCF data
  static Future<void> clearVcfCache([String? uid]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid != null && uid.isNotEmpty) {
        await prefs.remove(_vcfNameKey(uid));
        await prefs.remove(_vcfContentKey(uid));
      }
      await prefs.remove(_keyCachedVcfName);
      await prefs.remove(_keyCachedVcfContent);
    } catch (_) {}
  }

  /// Saves user profile in persistent cache memory
  static Future<void> cacheUserProfile(AppUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(user.toJson());
      await prefs.setString('$_keyCachedUserPrefix${user.uid}', jsonStr);
      await prefs.setString(_keyCachedWorkspaceChoice, user.role);
    } catch (e) {
      debugPrint('ScreenCacheService error caching user: $e');
    }
  }

  /// Restores user profile from persistent cache memory
  static Future<AppUser?> restoreUserProfile(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyCachedUserPrefix$uid');
      if (raw != null && raw.isNotEmpty) {
        return AppUser.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      }
    } catch (e) {
      debugPrint('ScreenCacheService error restoring user: $e');
    }
    return null;
  }

  /// Alias for restoreUserProfile
  static Future<AppUser?> getCachedUserProfile(String uid) =>
      restoreUserProfile(uid);

  /// Records privacy notice acceptance in local persistent cache memory
  static Future<void> cachePrivacyNoticeAccepted(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_keyCachedPrivacyPrefix$uid', true);
    } catch (_) {}
  }

  /// Checks if privacy notice is acknowledged in local cache
  static Future<bool> isPrivacyNoticeAccepted(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_keyCachedPrivacyPrefix$uid') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Caches an organization directory entry so it is instantly findable
  static Future<void> cacheOrganization(OrganizationDirectoryEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getCachedOrganizations();
      final map = <String, OrganizationDirectoryEntry>{
        for (final item in existing) item.organizationId: item,
      };
      map[entry.organizationId] = entry;
      final raw = jsonEncode(map.values.map((e) => e.toJson()).toList());
      await prefs.setString(_keyCachedOrganizations, raw);
      debugPrint('ScreenCacheService: cached organization ${entry.name} | ${entry.city}');
    } catch (e) {
      debugPrint('ScreenCacheService error caching organization: $e');
    }
  }

  /// Retrieves all locally cached organization directory entries
  static Future<List<OrganizationDirectoryEntry>> getCachedOrganizations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyCachedOrganizations);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((e) => OrganizationDirectoryEntry.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('ScreenCacheService error getting cached organizations: $e');
    }
    return [];
  }

  /// Saves a connected patient under an organization
  static Future<void> saveConnectedPatient(
    String orgId,
    OrganizationPatient patient,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final patients = await getConnectedPatients(orgId);
      final map = <String, OrganizationPatient>{
        for (final p in patients) p.patientId: p,
      };
      map[patient.patientId] = patient;
      final raw = jsonEncode(map.values.map((p) => p.toJson()).toList());
      await prefs.setString('$_keyConnectedPatientsPrefix$orgId', raw);
      debugPrint('ScreenCacheService: saved connected patient ${patient.name} (${patient.patientId}) for $orgId');
    } catch (e) {
      debugPrint('ScreenCacheService error saving connected patient: $e');
    }
  }

  /// Retrieves connected patients for an organization
  static Future<List<OrganizationPatient>> getConnectedPatients(
    String orgId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyConnectedPatientsPrefix$orgId');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((e) => OrganizationPatient.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('ScreenCacheService error getting connected patients: $e');
    }
    return [];
  }

  /// Saves an access request locally
  static Future<void> cacheAccessRequest(OrganizationAccessRequest request) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cache under patient
      final patientKey = '$_keyCachedRequestsPrefix${request.patientUid}';
      final pList = await _getRequestsByKey(patientKey);
      final pMap = <String, OrganizationAccessRequest>{
        for (final r in pList) r.organizationId: r,
      };
      pMap[request.organizationId] = request;
      await prefs.setString(
        patientKey,
        jsonEncode(pMap.values.map((r) => r.toJson()).toList()),
      );

      // Cache under organization
      final orgKey = '$_keyCachedRequestsPrefix${request.organizationId}';
      final oList = await _getRequestsByKey(orgKey);
      final oMap = <String, OrganizationAccessRequest>{
        for (final r in oList) r.patientUid: r,
      };
      oMap[request.patientUid] = request;
      await prefs.setString(
        orgKey,
        jsonEncode(oMap.values.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('ScreenCacheService error caching access request: $e');
    }
  }

  /// Retrieves cached requests for a user or org ID
  static Future<List<OrganizationAccessRequest>> getCachedAccessRequests(
    String id,
  ) async {
    return _getRequestsByKey('$_keyCachedRequestsPrefix$id');
  }

  static Future<List<OrganizationAccessRequest>> _getRequestsByKey(
    String key,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((e) => OrganizationAccessRequest.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Clears connected patients and access requests for a given organization ID
  static Future<void> clearOrganizationCache(String orgId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyConnectedPatientsPrefix$orgId');
      await prefs.remove('$_keyCachedRequestsPrefix$orgId');
    } catch (_) {}
  }

  /// Completely wipes all local persistent cache for NoCapRx
  static Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('nocaprx_')).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
      debugPrint('ScreenCacheService: purged ${keys.length} cached keys');
    } catch (e) {
      debugPrint('ScreenCacheService error clearing all cache: $e');
    }
  }
}


