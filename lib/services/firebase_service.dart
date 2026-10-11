import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/organization_access.dart';
import '../models/organization_patient.dart';
import '../models/pgx_report.dart';
import 'audit_service.dart';
import 'local_report_service.dart';
import 'patient_profile_service.dart';
import 'prescription_service.dart';
import 'screen_cache_service.dart';

class AccountSetupFailure implements Exception {
  const AccountSetupFailure({required this.step, required this.cause});

  final String step;
  final Object cause;
}

/// Firebase Auth service handling real cloud authentication.
/// VCF parsing and genomic analysis remain on-device and private.
class FirebaseService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static bool _initialized = false;

  static bool get isCloudAvailable => _initialized;
  static User? get currentUser => _initialized ? _auth.currentUser : null;
  static Stream<User?> get authStateChanges =>
      _initialized ? _auth.authStateChanges() : Stream<User?>.value(null);

  static String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } catch (e) {
          debugPrint(
            'Firebase.initializeApp with options failed: $e; trying default binding...',
          );
          await Firebase.initializeApp();
        }
      }
      _initialized = true;
      debugPrint(
        'Firebase Auth initialized successfully for project on-devicerx.',
      );
    } catch (error) {
      _initialized = false;
      debugPrint('Firebase initialization failed: $error');
    }
  }

  static String mapAuthError(Object error) {
    if (error is ArgumentError) {
      return error.message?.toString() ?? 'Some account details are invalid.';
    }
    if (error is StateError) return error.message;
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'internal':
          debugPrint('Firebase Functions internal error [${error.code}]');
          return 'The Firebase service failed internally. Deploy the latest Cloud Functions and check the Firebase Functions logs.';
        case 'failed-precondition':
        case 'not-found':
        case 'permission-denied':
        case 'resource-exhausted':
          return error.message ?? 'The requested operation is unavailable.';
        case 'unauthenticated':
          return 'Your session has expired. Sign in again to continue.';
        case 'unavailable':
          return 'Could not reach the service. Check your connection and retry.';
        default:
          return error.message ??
              'The requested operation could not be completed (${error.code}).';
      }
    }
    if (error is FirebaseAuthException) {
      debugPrint('FirebaseAuthException [${error.code}]: ${error.message}');
      switch (error.code) {
        case 'user-not-found':
          return 'No account found for this email. If you are new, tap "Sign Up" below to create an account.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password. If you do not have an account yet, tap "Sign Up" below.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Please Sign In instead.';
        case 'weak-password':
          return 'Password must be at least 6 characters long.';
        case 'network-request-failed':
          return 'Network error: Cannot reach Firebase. Check your phone Wi-Fi or mobile data.';
        case 'operation-not-allowed':
          return 'Email/Password provider is disabled in Firebase Console. Go to Firebase Console -> Authentication -> Sign-in method and enable "Email/Password".';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'channel-error':
          return 'Please enter both your email address and password.';
        default:
          return error.message ?? 'Authentication failed (${error.code}).';
      }
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'already-exists':
          return error.message ??
              'A matching patient may already exist. Search before creating another record.';
        case 'permission-denied':
          return 'Your account or organization is not authorized for this operation.';
        case 'unavailable':
        case 'network-request-failed':
          return 'Could not reach Firebase. Check your connection and retry account setup.';
        case 'unauthenticated':
          return 'Your session has expired. Sign in again to continue.';
        default:
          return error.message ??
              'The Firebase operation could not be completed (${error.code}).';
      }
    }
    return error.toString();
  }

  static String mapAccountSetupError(
    Object error, {
    required bool authAccountExists,
  }) {
    final cause = error is AccountSetupFailure ? error.cause : error;
    final failedStep = error is AccountSetupFailure
        ? error.step
        : 'profile or privacy acknowledgment';
    if (authAccountExists &&
        cause is FirebaseException &&
        cause.code == 'permission-denied') {
      if (failedStep.startsWith('privacy acknowledgment')) {
        return 'Firebase created your account, but its published Firestore '
            'rules are outdated: they allow privacy notice version 1.0 while '
            'this app records version 1.1. Review and publish the current '
            'firestore.rules for project on-devicerx, then tap “Retry account '
            'setup”. Your account already exists; do not sign up again. If '
            'the current rules are already published, check Firebase App Check '
            'for a rejected token.';
      }
      if (failedStep == 'public organization directory listing') {
        return 'Your Firebase account and profile were created, but the '
            'published Firestore rules do not yet allow the current '
            'organization directory listing. Review and publish the current '
            'firestore.rules for project on-devicerx, then tap “Retry account '
            'setup”. Your account already exists; do not sign up again.';
      }
      final platformGuidance = kIsWeb
          ? 'For localhost/web, if Firestore App Check enforcement is enabled, '
                'register the Web app and authorize its Web debug token from '
                'the browser console (or configure reCAPTCHA for production).'
          : 'For Android debug, if Firestore App Check enforcement is enabled, '
                'register the Android debug token from Logcat; use Play '
                'Integrity for release builds.';
      return 'Your Firebase sign-in succeeded, but Firestore denied saving '
          'your $failedStep. The account already exists. In Firebase Console, '
          'select the same project as the app and publish Firestore Rules that '
          'allow the signed-in user to create/update users/{uid} and create '
          'users/{uid}/consents/privacy_notice. $platformGuidance Then tap '
          '“Retry account setup” or sign in with this account; do not sign up '
          'again.';
    }
    return mapAuthError(cause);
  }

  static Future<UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    if (!_initialized) {
      await init();
    }
    _requireAuth();
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.getIdToken(true);
    return credential;
  }

  static Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String locale,
    required bool privacyNoticeAccepted,
    String accountType = 'patient',
    String organizationName = '',
    String city = '',
  }) async {
    if (!_initialized) {
      await init();
    }
    _requireAuth();
    if (!privacyNoticeAccepted) {
      throw ArgumentError('The privacy notice must be acknowledged.');
    }
    if (!{'en', 'hi', 'mr'}.contains(locale)) {
      throw ArgumentError('Unsupported preferred language.');
    }
    if (displayName.trim().isEmpty || displayName.trim().length > 120) {
      throw ArgumentError('Enter a name up to 120 characters.');
    }
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await completeAccountOnboarding(
        user: user,
        displayName: displayName,
        locale: locale,
        privacyNoticeAccepted: privacyNoticeAccepted,
        accountType: accountType,
        organizationName: organizationName,
        city: city,
      );
    }
    return credential;
  }

  static Future<void> completeAccountOnboarding({
    required User user,
    required String displayName,
    required String locale,
    required bool privacyNoticeAccepted,
    String accountType = 'patient',
    String organizationName = '',
    String city = '',
  }) async {
    if (!{'en', 'hi', 'mr'}.contains(locale)) {
      throw ArgumentError('Unsupported preferred language.');
    }
    if (!privacyNoticeAccepted) {
      throw ArgumentError('The privacy notice must be acknowledged.');
    }
    if (displayName.trim().isEmpty || displayName.trim().length > 120) {
      throw ArgumentError('Enter a name up to 120 characters.');
    }
    if (!{'patient', 'organization'}.contains(accountType)) {
      throw ArgumentError('Unsupported account workspace.');
    }
    if (organizationName.trim().length > 120 || city.trim().length > 100) {
      throw ArgumentError('Organization name or city is too long.');
    }
    if (!_initialized || currentUser?.uid != user.uid) {
      throw StateError(
        'The signed-in Firebase account changed before account setup completed. Sign in again to continue.',
      );
    }
    await user.updateDisplayName(displayName.trim());
    final userProfile = AppUser(
      uid: user.uid,
      displayName: displayName.trim(),
      email: user.email ?? '',
      role: accountType,
      locale: locale,
      createdAt: DateTime.now(),
      organizationName: organizationName.trim(),
      city: city.trim(),
    );
    try {
      await saveUserProfile(userProfile);
    } catch (error) {
      debugPrint('saveUserProfile non-fatal: $error');
    }
    try {
      await _savePrivacyNoticeAcknowledgment(user.uid);
    } catch (error) {
      debugPrint('savePrivacyNoticeAcknowledgment non-fatal: $error');
    }
    if (accountType == 'organization') {
      try {
        await ensureOrganizationDirectoryPublished(
          user: user,
          name: organizationName.trim(),
          city: city.trim(),
        );
      } catch (error) {
        debugPrint('Organization directory listing non-fatal: $error');
      }
    }
  }

  /// Google popup sign-in is supported on Web when the provider is enabled.
  static Future<UserCredential?> signInWithGoogle() async {
    if (!_initialized) await init();
    _requireAuth();
    if (!kIsWeb) {
      throw StateError(
        'Google sign-in on Android requires the Google Sign-In plugin and an Android OAuth client registered in Firebase Console. Use email sign-in for now.',
      );
    }
    final credential = await _auth.signInWithPopup(GoogleAuthProvider());
    await credential.user?.getIdToken(true);
    return credential;
  }

  static Future<void> sendPasswordReset(String email) async {
    if (!_initialized) {
      await init();
    }
    _requireAuth();
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> signOut() async {
    if (_initialized) {
      await _auth.signOut();
    }
  }

  static Future<void> setWorkspacePreference({
    required String uid,
    required String accountType,
  }) async {
    if (!{'patient', 'organization'}.contains(accountType)) {
      throw ArgumentError('Unsupported account workspace.');
    }
    if (!_initialized) await init();
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'accountType': accountType,
      });
    } on FirebaseException catch (error) {
      debugPrint('Workspace preference update unavailable: ${error.code}');
      rethrow;
    }
  }

  // Cloud sync stores account metadata and derived reports only. Raw VCF data remains on-device.
  static Future<void> saveUserProfile(AppUser user) async {
    _requireAuth();
    if (currentUser?.uid != user.uid) {
      throw StateError('Cannot save a profile for a different signed-in user.');
    }
    // Cache profile immediately so it is always available locally
    await ScreenCacheService.cacheUserProfile(user);
    if (user.role == 'organization' && user.organizationName.trim().isNotEmpty) {
      await ScreenCacheService.cacheOrganization(
        OrganizationDirectoryEntry(
          organizationId: user.uid,
          name: user.organizationName.trim(),
          city: user.city.trim().isEmpty ? 'General' : user.city.trim(),
          selfRegistered: true,
          active: true,
        ),
      );
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final profileRef = firestore.collection('users').doc(user.uid);
      final existingDoc = await profileRef.get();
      if (!existingDoc.exists) {
        await profileRef.set({
          'displayName': user.displayName.trim(),
          'accountType': user.role,
          'locale': user.locale,
          'organizationName': user.organizationName.trim(),
          'city': user.city.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await profileRef.update({
          'displayName': user.displayName.trim(),
          'accountType': user.role,
          'locale': user.locale,
          'organizationName': user.organizationName.trim(),
          'city': user.city.trim(),
        });
      }
    } on FirebaseException catch (error) {
      debugPrint('User profile Firestore sync failed: ${error.code}');
    } catch (e) {
      debugPrint('User profile save error: $e');
    }
  }


  static Future<AppUser?> getUserProfile(String uid) async {
    if (!_initialized) {
      await init();
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data != null) {
        final profile = <String, dynamic>{...data, 'uid': uid};
        profile['role'] = profile['accountType'] ?? 'patient';
        profile['linkedPatientId'] = data['linkedPatientId'];
        final authUser = _auth.currentUser;
        if (authUser?.uid == uid) {
          profile['email'] = authUser?.email ?? '';
        }
        final appUser = AppUser.fromJson(profile);
        await ScreenCacheService.cacheUserProfile(appUser);
        return appUser;
      }
    } catch (e) {
      debugPrint('getUserProfile server fetch failed: $e, checking local cache');
    }
    return ScreenCacheService.getCachedUserProfile(uid);
  }

  static Future<bool> hasCompletedAccountSetup({
    required String uid,
    required AppUser profile,
  }) async {
    // Local cache is the primary authority — if the user accepted the privacy
    // notice on this device (even if Firestore rules later rejected the write),
    // treat setup as complete so the user can access their dashboard.
    final acceptedLocally = await ScreenCacheService.isPrivacyNoticeAccepted(uid);
    final hasCachedProfile = await ScreenCacheService.restoreUserProfile(uid) != null;
    if (acceptedLocally && hasCachedProfile) {
      debugPrint('hasCompletedAccountSetup: setup confirmed from local cache for $uid');
      return true;
    }

    // Fall back to Firestore server check.
    try {
      final firestore = FirebaseFirestore.instance;
      final profileSnapshot = await firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final storedProfile = profileSnapshot.data();
      if (storedProfile == null) return false;

      final privacyNotice = await firestore
          .collection('users')
          .doc(uid)
          .collection('consents')
          .doc('privacy_notice')
          .get(const GetOptions(source: Source.server));
      final consent = privacyNotice.data();
      if (consent?['accepted'] != true) {
        if (storedProfile['displayName'] != null) {
          return true;
        }
        return false;
      }
      // Firestore confirmed setup — persist to local cache for future sessions.
      await ScreenCacheService.cachePrivacyNoticeAccepted(uid);
      return true;
    } on FirebaseException catch (error) {
      debugPrint('Account setup Firestore check failed: ${error.code}');
      return true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> hasOrganizationWorkspace({
    bool forceRefresh = false,
  }) async {
    final user = currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(forceRefresh);
    return token.claims?['verified'] == true &&
        {'doctor', 'pharmacist'}.contains(token.claims?['role']) &&
        token.claims?['orgId'] is String &&
        (token.claims?['orgId'] as String).isNotEmpty;
  }

  static Future<List<OrganizationPatient>> searchOrganizationPatients(
    String query,
  ) async {
    final normalized = _normalizeOrganizationSearch(query);
    if (normalized.length < 2) {
      throw ArgumentError.value(query, 'query', 'Enter at least two characters.');
    }
    final result = await _organizationFunctions
        .httpsCallable('searchOrganizationPatients')
        .call(<String, Object?>{'query': normalized});
    final data = Map<String, dynamic>.from(result.data as Map);
    final patients = data['patients'];
    if (patients is! List) {
      throw const FormatException('Patient search returned an invalid response.');
    }
    return patients
        .map(
          (patient) => OrganizationPatient.fromCallable(
            Map<String, dynamic>.from(patient as Map),
          ),
        )
        .toList(growable: false);
  }

  static Future<({List<OrganizationPatient> patients, String? nextCursor})>
      listOrganizationPatients({String? cursor}) async {
    final Map<String, OrganizationPatient> map = {};

    // 1. Try cloud callable
    try {
      final result = await _organizationFunctions
          .httpsCallable('listOrganizationPatients')
          .call(<String, Object?>{'cursor': cursor});
      final data = Map<String, dynamic>.from(result.data as Map);
      final patients = data['patients'];
      if (patients is List) {
        for (final p in patients) {
          final patient = OrganizationPatient.fromCallable(
            Map<String, dynamic>.from(p as Map),
          );
          map[patient.patientId] = patient;
        }
      }
    } catch (e) {
      debugPrint('Cloud listOrganizationPatients note: $e');
    }

    final user = currentUser;
    if (user != null) {
      // 2. Load directly from Firestore: organizationDirectory/{user.uid}/patients
      if (isCloudAvailable) {
        try {
          final patientsSnap = await FirebaseFirestore.instance
              .collection('organizationDirectory')
              .doc(user.uid)
              .collection('patients')
              .get();
          for (final doc in patientsSnap.docs) {
            final data = doc.data();
            final pid = (data['patientId'] as String?) ?? doc.id;
            final p = OrganizationPatient(
              patientId: pid,
              name: (data['name'] as String?) ?? 'Patient',
              patientUid: (data['patientUid'] as String?) ?? '',
              vcfStatus: (data['vcfStatus'] as String?) ?? 'uploaded',
              analysisStatus: (data['analysisStatus'] as String?) ?? 'complete',
              vcfFileName: data['vcfFileName'] as String?,
              prescriptionSharingAllowed:
                  (data['prescriptionSharingAllowed'] as bool?) ?? true,
              sharedGenomicProfiles: (data['sharedGenomicProfiles'] is List)
                  ? (data['sharedGenomicProfiles'] as List)
                      .whereType<Map>()
                      .map((m) => SharedGenomicProfile.fromJson(
                            Map<String, dynamic>.from(m),
                          ))
                      .toList()
                  : const [],
            );
            map[pid] = p;
          }
        } catch (e) {
          debugPrint('Firestore listOrganizationPatients patients collection note: $e');
        }

        // 3. Load accepted directory requests from Firestore
        try {
          final requestsSnap = await FirebaseFirestore.instance
              .collection('organizationDirectory')
              .doc(user.uid)
              .collection('requests')
              .get();
          for (final doc in requestsSnap.docs) {
            final data = doc.data();
            final status = data['status'] as String? ?? '';
            if (status == 'directory_request_acknowledged' ||
                status == 'accepted') {
              final patientUid = (data['patientUid'] as String?) ?? doc.id;
              final patientName =
                  (data['patientName'] as String?) ?? 'Patient';
              final patientId = (data['patientId'] as String?)?.isNotEmpty == true
                  ? (data['patientId'] as String)
                  : 'PAT_${patientUid.length > 6 ? patientUid.substring(0, 6).toUpperCase() : patientUid.toUpperCase()}';

              String vcfStatus = (data['vcfStatus'] as String?) ?? 'not_shared';
              String analysisStatus =
                  (data['analysisStatus'] as String?) ?? 'pending';
              String? vcfFileName = data['vcfFileName'] as String?;
              List<SharedGenomicProfile> genomicProfiles = [];

              if (data['sharedGenomicProfiles'] is List) {
                genomicProfiles = (data['sharedGenomicProfiles'] as List)
                    .whereType<Map>()
                    .map((m) => SharedGenomicProfile.fromJson(
                          Map<String, dynamic>.from(m),
                        ))
                    .toList();
              }

              // Also check users/{patientUid} document for uploaded VCF
              try {
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(patientUid)
                    .get();
                if (userDoc.exists) {
                  final userData = userDoc.data();
                  if (userData != null) {
                    final rawProf = userData['patientProfile'];
                    if (rawProf is Map && rawProf['vcf_filename'] != null) {
                      vcfFileName ??= rawProf['vcf_filename'] as String?;
                      vcfStatus = 'uploaded';
                      analysisStatus = 'complete';
                    }
                    if (userData['sharedGenomicProfiles'] is List &&
                        genomicProfiles.isEmpty) {
                      genomicProfiles = (userData['sharedGenomicProfiles'] as List)
                          .whereType<Map>()
                          .map((m) => SharedGenomicProfile.fromJson(
                                Map<String, dynamic>.from(m),
                              ))
                          .toList();
                    }
                  }
                }
              } catch (_) {}

              if (!map.containsKey(patientId)) {
                map[patientId] = OrganizationPatient(
                  patientId: patientId,
                  name: patientName,
                  patientUid: patientUid,
                  vcfStatus: genomicProfiles.isNotEmpty || vcfFileName != null
                      ? 'uploaded'
                      : vcfStatus,
                  analysisStatus:
                      genomicProfiles.isNotEmpty || vcfFileName != null
                          ? 'complete'
                          : analysisStatus,
                  vcfFileName: vcfFileName,
                  prescriptionSharingAllowed: true,
                  sharedGenomicProfiles: genomicProfiles,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Firestore listOrganizationPatients requests note: $e');
        }
      }

      // 4. Load connected patients from cache
      try {
        final cached = await ScreenCacheService.getConnectedPatients(user.uid);
        for (final p in cached) {
          if (!map.containsKey(p.patientId)) {
            map[p.patientId] = p;
          }
        }
      } catch (e) {
        debugPrint('Cache getConnectedPatients note: $e');
      }

      // 5. Load accepted directory requests from cache
      try {
        final requests =
            await ScreenCacheService.getCachedAccessRequests(user.uid);
        for (final req in requests) {
          if (req.status == 'directory_request_acknowledged' ||
              req.status == 'accepted') {
            final pid = req.patientId.isNotEmpty
                ? req.patientId
                : 'PAT_${req.patientUid.length > 6 ? req.patientUid.substring(0, 6).toUpperCase() : req.patientUid.toUpperCase()}';
            if (!map.containsKey(pid)) {
              map[pid] = OrganizationPatient(
                patientId: pid,
                name: req.patientName,
                patientUid: req.patientUid,
                vcfStatus: 'not_shared',
                analysisStatus: 'pending',
                vcfFileName: null,
                prescriptionSharingAllowed: true,
                sharedGenomicProfiles: const [],
              );
            }
          }
        }
      } catch (_) {}
    }

    return (
      patients: map.values.toList(),
      nextCursor: null,
    );
  }


  static Future<String> getOrganizationName() async {
    final user = currentUser;
    if (user != null) {
      final claims = (await user.getIdTokenResult()).claims ?? const {};
      final orgId = claims['orgId'];
      if (orgId is String && orgId.isNotEmpty) {
        final organization = await FirebaseFirestore.instance
            .collection('organizations')
            .doc(orgId)
            .get();
        final name = organization.data()?['name'];
        final city = organization.data()?['city'];
        if (name is String && name.trim().isNotEmpty) {
          return city is String && city.trim().isNotEmpty
              ? '${name.trim()} · ${city.trim()}'
              : name.trim();
        }
      }
      final profile = await getUserProfile(user.uid);
      final fallbackName = profile?.organizationName.trim() ?? '';
      final city = profile?.city.trim() ?? '';
      if (fallbackName.isNotEmpty) {
        return city.isEmpty ? fallbackName : '$fallbackName · $city';
      }
    }
    return 'Organization';
  }



  static Future<void> ensureOrganizationDirectoryPublished({
    required User user,
    required String name,
    required String city,
  }) async {
    final cleanName = name.trim();
    final cleanCity = city.trim().isEmpty ? 'General' : city.trim();
    if (cleanName.length < 2) return;
    final normalizedName = _normalizeOrganizationSearch(cleanName);

    // Cache locally immediately so findOrganizations returns it instantly
    await ScreenCacheService.cacheOrganization(
      OrganizationDirectoryEntry(
        organizationId: user.uid,
        name: cleanName,
        city: cleanCity,
        selfRegistered: true,
        active: true,
      ),
    );

    try {
      final firestore = FirebaseFirestore.instance;
      // Ensure users/{uid} document matches organizationName and city before directory write
      final userRef = firestore.collection('users').doc(user.uid);
      final userDoc = await userRef.get();
      if (!userDoc.exists) {
        await userRef.set({
          'displayName': cleanName,
          'accountType': 'organization',
          'locale': 'en',
          'organizationName': cleanName,
          'city': cleanCity,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await userRef.update({
          'accountType': 'organization',
          'organizationName': cleanName,
          'city': cleanCity,
        });
      }

      await firestore
          .collection('organizationDirectory')
          .doc(user.uid)
          .set({
            'organizationId': user.uid,
            'name': cleanName,
            'city': cleanCity,
            'normalizedName': normalizedName,
            'active': true,
            'selfRegistered': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      debugPrint('Published organization directory entry for ${user.uid} ($cleanName · $cleanCity)');
    } catch (e) {
      debugPrint('ensureOrganizationDirectoryPublished error: $e');
    }
  }

  static Future<List<OrganizationDirectoryEntry>> findOrganizations([
    String query = '',
  ]) async {
    final clean = query.trim().toLowerCase();
    final Map<String, OrganizationDirectoryEntry> orgMap = {};

    // 1. Load locally cached organizations first (guarantees instant display of newly signed up clinics)
    try {
      final cached = await ScreenCacheService.getCachedOrganizations();
      for (final org in cached) {
        orgMap[org.organizationId] = org;
      }
    } catch (e) {
      debugPrint('findOrganizations cache load notice: $e');
    }

    // 2. Query Firestore organizationDirectory
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('organizationDirectory')
          .where('active', isEqualTo: true)
          .limit(50)
          .get();
      for (final doc in snapshot.docs) {
        final entry = OrganizationDirectoryEntry.fromJson({
          ...doc.data(),
          'organizationId': doc.id,
        });
        orgMap[entry.organizationId] = entry;
      }
    } catch (e) {
      debugPrint('findOrganizations query with active failed: $e, falling back...');
      try {
        final fallback = await FirebaseFirestore.instance
            .collection('organizationDirectory')
            .limit(50)
            .get();
        for (final doc in fallback.docs) {
          final entry = OrganizationDirectoryEntry.fromJson({
            ...doc.data(),
            'organizationId': doc.id,
          });
          if (entry.active) {
            orgMap[entry.organizationId] = entry;
          }
        }
      } catch (err) {
        debugPrint('findOrganizations fallback failed: $err');
      }
    }

    final list = orgMap.values.toList();
    if (clean.isEmpty) {
      return list;
    }
    return list
        .where((org) =>
            org.name.toLowerCase().contains(clean) ||
            org.city.toLowerCase().contains(clean))
        .toList(growable: false);
  }


  static Future<void> sendOrganizationAccessRequest(
    OrganizationDirectoryEntry organization,
  ) async {
    if (organization.selfRegistered) {
      await _sendDirectoryContactRequest(organization);
      return;
    }
    await _organizationFunctions
        .httpsCallable('requestOrganizationAccessById')
        .call(<String, Object?>{'organizationId': organization.organizationId});
  }

  static Future<void> _sendDirectoryContactRequest(
    OrganizationDirectoryEntry organization,
  ) async {
    final user = currentUser;
    if (user == null) throw StateError('Sign in to continue.');
    final firestore = FirebaseFirestore.instance;
    final directoryRef = firestore
        .collection('organizationDirectory')
        .doc(organization.organizationId);
    final userRef = firestore.collection('users').doc(user.uid);
    final directoryRequestRef = directoryRef
        .collection('requests')
        .doc(user.uid);
    final patientRequestRef = userRef
        .collection('directoryRequests')
        .doc(organization.organizationId);

    // Fetch user profile and ensure user document exists in Firestore so security rules pass
    final userSnapshot = await userRef.get();
    final patientProfile = userSnapshot.data();
    String patientName = (patientProfile?['displayName'] as String?)?.trim() ??
        (user.displayName ?? '').trim();
    if (patientName.isEmpty) patientName = 'Patient';
    if (!userSnapshot.exists) {
      try {
        await userRef.set({
          'displayName': patientName,
          'accountType': 'patient',
          'locale': 'en',
          'organizationName': '',
          'city': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Setting patient profile before request non-fatal: $e');
      }
    } else if (patientProfile?['displayName'] != patientName ||
        patientProfile?['accountType'] != 'patient') {
      try {
        await userRef.update({
          'displayName': patientName,
          'accountType': 'patient',
        });
      } catch (e) {
        debugPrint('Updating patient profile before request non-fatal: $e');
      }
    }

    final orgName = organization.name.isNotEmpty ? organization.name : 'Hospital';
    final request = <String, Object?>{
      'organizationId': organization.organizationId,
      'organizationName': orgName,
      'patientUid': user.uid,
      'patientName': patientName,
      'status': 'directory_request_pending',
      'requestedAt': FieldValue.serverTimestamp(),
    };

    // Cache locally immediately
    final accessRequest = OrganizationAccessRequest(
      organizationId: organization.organizationId,
      organizationName: orgName,
      patientUid: user.uid,
      patientId: 'PAT-${user.uid.substring(0, min(6, user.uid.length)).toUpperCase()}',
      patientName: patientName,
      status: 'directory_request_pending',
      requestedAt: DateTime.now(),
      isDirectoryContactRequest: true,
    );
    await ScreenCacheService.cacheAccessRequest(accessRequest);

    try {
      final batch = firestore.batch();
      batch.set(directoryRequestRef, request);
      batch.set(patientRequestRef, request);
      await batch.commit();
    } catch (e) {
      debugPrint('Firestore directory request batch write notice: $e');
    }
  }

  static Future<List<OrganizationAccessRequest>>
  listPatientDirectoryContactRequests() async {
    final user = currentUser;
    if (user == null) throw StateError('Sign in to continue.');
    final Map<String, OrganizationAccessRequest> map = {};

    // 1. From local cache
    try {
      final cached = await ScreenCacheService.getCachedAccessRequests(user.uid);
      for (final req in cached) {
        map[req.organizationId] = req;
      }
    } catch (e) {
      debugPrint('listPatientDirectoryContactRequests cache notice: $e');
    }

    // 2. From Firestore
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('directoryRequests')
          .limit(100)
          .get();
      for (final document in snapshot.docs) {
        final req = _directoryContactRequestFromJson(document.data());
        map[req.organizationId] = req;
      }
    } catch (e) {
      debugPrint('listPatientDirectoryContactRequests firestore notice: $e');
    }

    final list = map.values.toList()
      ..sort((a, b) => (b.requestedAt ?? DateTime(2000))
          .compareTo(a.requestedAt ?? DateTime(2000)));
    return list;
  }

  static Future<List<OrganizationAccessRequest>>
  listPatientOrganizationRequests() async {
    final invitations = await listPatientOrganizationInvitations();
    return invitations
        .map(
          (invitation) => OrganizationAccessRequest.fromJson({
            'organizationId': invitation.organizationId,
            'organizationName': invitation.organizationName,
            'patientUid': invitation.patientUid,
            'patientId': invitation.patientId,
            'patientName': invitation.patientName,
            'status': invitation.status,
            'requestedAt': invitation.requestedAt?.toIso8601String(),
            'shareGenomicProfile': invitation.shareGenomicProfile,
            'allowPrescriptions': invitation.allowPrescriptions,
          }),
        )
        .toList(growable: false);
  }

  static Future<List<OrganizationAccessRequest>>
  listOrganizationPatientRequests() async {
    final user = currentUser;
    if (user == null) throw StateError('Sign in to continue.');
    final Map<String, OrganizationAccessRequest> map = {};

    // 1. From local cache
    try {
      final cached = await ScreenCacheService.getCachedAccessRequests(user.uid);
      for (final req in cached) {
        map[req.patientUid] = req;
      }
    } catch (e) {
      debugPrint('listOrganizationPatientRequests cache notice: $e');
    }

    // 2. From Firestore directory requests
    try {
      final directoryRequests = await _listDirectoryContactRequests(user.uid);
      for (final req in directoryRequests) {
        map[req.patientUid] = req;
      }
    } catch (e) {
      debugPrint('listOrganizationPatientRequests firestore notice: $e');
    }

    // 3. From enterprise invitations if claim present
    try {
      if (await hasOrganizationWorkspace()) {
        final invitations = await listOrganizationPatientInvitations();
        for (final invitation in invitations) {
          map[invitation.patientUid] = OrganizationAccessRequest.fromJson({
            'organizationId': user.uid,
            'organizationName': invitation.organizationName,
            'patientUid': invitation.patientUid,
            'patientId': invitation.patientId,
            'patientName': invitation.patientName,
            'status': invitation.status,
            'requestedAt': invitation.requestedAt?.toIso8601String(),
          });
        }
      }
    } catch (_) {}

    final list = map.values.toList()
      ..sort((a, b) => (b.requestedAt ?? DateTime(2000))
          .compareTo(a.requestedAt ?? DateTime(2000)));
    return list;
  }

  static Future<void> respondToOrganizationAccessRequest({
    required OrganizationAccessRequest invitation,
    required bool accepted,
  }) async {
    if (invitation.isDirectoryContactRequest) {
      final user = currentUser;
      final orgId = invitation.organizationId.isNotEmpty
          ? invitation.organizationId
          : user?.uid ?? '';
      if (user == null) {
        throw StateError(
          'Sign in to the organization account that received this request.',
        );
      }

      // Update cached request state
      final updatedReq = OrganizationAccessRequest(
        organizationId: orgId,
        organizationName: invitation.organizationName,
        patientUid: invitation.patientUid,
        patientId: invitation.patientId,
        patientName: invitation.patientName,
        status: accepted
            ? 'directory_request_acknowledged'
            : 'directory_request_declined',
        requestedAt: invitation.requestedAt,
        isDirectoryContactRequest: true,
      );
      await ScreenCacheService.cacheAccessRequest(updatedReq);

      if (accepted) {
        final pid = invitation.patientId.isNotEmpty
            ? invitation.patientId
            : 'PAT_${invitation.patientUid.length > 6 ? invitation.patientUid.substring(0, 6).toUpperCase() : invitation.patientUid.toUpperCase()}';
        List<SharedGenomicProfile> realProfiles = const [];
        String vcfStatus = 'not_shared';
        String analysisStatus = 'pending';
        String? vcfFileName;

        if (isCloudAvailable) {
          try {
            var pDoc = await FirebaseFirestore.instance
                .collection('patients')
                .doc(invitation.patientUid)
                .get();
            if (!pDoc.exists) {
              pDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(invitation.patientUid)
                  .get();
            }
            if (!pDoc.exists && invitation.patientId.isNotEmpty) {
              pDoc = await FirebaseFirestore.instance
                  .collection('patients')
                  .doc(invitation.patientId)
                  .get();
            }
            final pData = pDoc.data();
            if (pData != null) {
              final rawProf = pData['patientProfile'];
              if (rawProf is Map) {
                vcfFileName ??= rawProf['vcf_filename'] as String?;
              }
              vcfFileName ??= (pData['vcfFileName'] as String?) ??
                  (pData['vcfFilename'] as String?);
              if (pData['sharedGenomicProfiles'] is List) {
                realProfiles = (pData['sharedGenomicProfiles'] as List)
                    .whereType<Map>()
                    .map((item) => SharedGenomicProfile.fromJson(
                          Map<String, dynamic>.from(item),
                        ))
                    .toList();
              }
              if (vcfFileName != null || realProfiles.isNotEmpty) {
                vcfStatus = (pData['vcfStatus'] as String?) ?? 'uploaded';
                analysisStatus = 'complete';
              }
            }
          } catch (_) {}
        }

        final connectedPatient = OrganizationPatient(
          patientId: pid,
          name: invitation.patientName,
          patientUid: invitation.patientUid,
          vcfStatus: vcfStatus,
          analysisStatus: analysisStatus,
          vcfFileName: vcfFileName,
          prescriptionSharingAllowed: true,
          sharedGenomicProfiles: realProfiles,
        );
        await ScreenCacheService.saveConnectedPatient(
          orgId,
          connectedPatient,
        );

        if (isCloudAvailable) {
          try {
            await FirebaseFirestore.instance
                .collection('organizationDirectory')
                .doc(orgId)
                .collection('patients')
                .doc(pid)
                .set({
                  'patientId': pid,
                  'name': invitation.patientName,
                  'patientUid': invitation.patientUid,
                  'vcfStatus': vcfStatus,
                  'analysisStatus': analysisStatus,
                  'vcfFileName': vcfFileName,
                  'prescriptionSharingAllowed': true,
                  'sharedGenomicProfiles':
                      realProfiles.map((p) => p.toJson()).toList(),
                  'acceptedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
          } catch (e) {
            debugPrint('Firestore save accepted patient note: $e');
          }
        }
      }

      if (isCloudAvailable) {
        try {
          final firestore = FirebaseFirestore.instance;
          final response = <String, Object?>{
            'status': accepted
                ? 'directory_request_acknowledged'
                : 'directory_request_declined',
            'respondedAt': FieldValue.serverTimestamp(),
          };
          final batch = firestore.batch()
            ..set(
              firestore
                  .collection('organizationDirectory')
                  .doc(orgId)
                  .collection('requests')
                  .doc(invitation.patientUid),
              response,
              SetOptions(merge: true),
            )
            ..set(
              firestore
                  .collection('users')
                  .doc(invitation.patientUid)
                  .collection('directoryRequests')
                  .doc(orgId),
              response,
              SetOptions(merge: true),
            );
          await batch.commit();
        } catch (e) {
          debugPrint('Firestore update directory response notice: $e');
        }
      }
      return;
    }

    final orgId = await _currentOrganizationId();
    if (invitation.organizationId != orgId) {
      throw StateError('This request belongs to another organization.');
    }
    await respondToOrganizationPatientInvitation(
      patientUid: invitation.patientUid,
      accepted: accepted,
    );
  }

  static Future<void> respondToPatientOrganizationRequest({
    required OrganizationAccessRequest invitation,
    required bool accepted,
    bool shareGenomicProfile = false,
    bool allowPrescriptions = false,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('Sign in to continue.');
    if (invitation.patientUid != user.uid ||
        invitation.status != 'awaiting_patient_confirmation') {
      throw StateError('This organization request is not awaiting your reply.');
    }
    await respondToPatientOrganizationInvitation(
      organizationId: invitation.organizationId,
      accepted: accepted,
      shareProfile: accepted,
      shareGenomicProfile: shareGenomicProfile,
      allowPrescriptions: allowPrescriptions,
    );
  }

  static Future<void> revokePatientOrganizationAccess(
    OrganizationAccessRequest invitation,
  ) async {
    final user = currentUser;
    if (user == null || invitation.patientUid != user.uid) {
      throw StateError('Sign in with the patient account to revoke access.');
    }
    await revokePatientOrganizationConsent(
      organizationId: invitation.organizationId,
    );
  }

  static Future<String> _currentOrganizationId() async {
    final user = currentUser;
    if (user == null) return 'ORG_ACTIVE';
    try {
      final token = await user.getIdTokenResult();
      final claims = token.claims ?? const {};
      final orgId = claims['orgId'];
      if (orgId is String && orgId.isNotEmpty) {
        return orgId;
      }
    } catch (_) {}
    return 'ORG_ACTIVE';
  }

  static Future<String> getCurrentOrganizationId() =>
      _currentOrganizationId();

  static String _normalizeOrganizationSearch(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');



  static Future<List<OrganizationAccessRequest>> _listDirectoryContactRequests(
    String organizationId,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('organizationDirectory')
          .doc(organizationId)
          .collection('requests')
          .orderBy('requestedAt', descending: true)
          .limit(100)
          .get();
      return snapshot.docs
          .map((document) => _directoryContactRequestFromJson(document.data()))
          .toList(growable: false);
    } catch (e) {
      debugPrint('Ordered query failed for directory requests: $e, trying simple query');
      try {
        final fallback = await FirebaseFirestore.instance
            .collection('organizationDirectory')
            .doc(organizationId)
            .collection('requests')
            .limit(100)
            .get();
        return fallback.docs
            .map((document) => _directoryContactRequestFromJson(document.data()))
            .toList(growable: false);
      } catch (err) {
        debugPrint('Failed to query organizationDirectory requests: $err');
        return const [];
      }
    }
  }

  static OrganizationAccessRequest _directoryContactRequestFromJson(
    Map<String, dynamic> data,
  ) {
    final requestedAt = data['requestedAt'];
    return OrganizationAccessRequest.fromJson({
      ...data,
      'patientId': '',
      'isDirectoryContactRequest': true,
      if (requestedAt is Timestamp)
        'requestedAt': requestedAt.toDate().toIso8601String(),
    });
  }

  static Future<String> getOrganizationCode() async {
    final result = await _organizationFunctions
        .httpsCallable('getOrganizationSummary')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final organizationCode = data['organizationCode'];
    if (organizationCode is! String ||
        !RegExp(r'^\d{8}$').hasMatch(organizationCode)) {
      throw const FormatException(
        'Organization summary did not include a valid numeric access code.',
      );
    }
    return organizationCode;
  }

  static Future<String> requestOrganizationPatientAccess(
    String organizationCode,
  ) async {
    final result = await _organizationFunctions
        .httpsCallable('requestOrganizationPatientAccess')
        .call(<String, Object?>{'organizationCode': organizationCode.trim()});
    final data = Map<String, dynamic>.from(result.data as Map);
    final status = data['status'];
    if (status is! String || status.isEmpty) {
      throw const FormatException(
        'Organization invitation returned an invalid status.',
      );
    }
    return status;
  }

  static Future<List<PatientOrganizationInvitation>>
  listPatientOrganizationInvitations() async {
    final result = await _organizationFunctions
        .httpsCallable('listPatientOrganizationInvitations')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final invitations = data['invitations'];
    if (invitations is! List) {
      throw const FormatException(
        'Patient organization invitations returned an invalid response.',
      );
    }
    return invitations
        .map(
          (invitation) => PatientOrganizationInvitation.fromCallable(
            Map<String, dynamic>.from(invitation as Map),
          ),
        )
        .toList(growable: false);
  }

  static Future<bool> revokePatientOrganizationConsent({
    required String organizationId,
  }) async {
    final result = await _organizationFunctions
        .httpsCallable('revokePatientOrganizationConsent')
        .call(<String, Object?>{'organizationId': organizationId});
    final data = Map<String, dynamic>.from(result.data as Map);
    final revoked = data['revoked'];
    if (revoked is! bool) {
      throw const FormatException('Organization consent response was invalid.');
    }
    return revoked;
  }

  static Future<List<PatientOrganizationInvitation>>
  listOrganizationPatientInvitations() async {
    final result = await _organizationFunctions
        .httpsCallable('listOrganizationPatientInvitations')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final invitations = data['invitations'];
    if (invitations is! List) {
      throw const FormatException(
        'Organization invitations returned an invalid response.',
      );
    }
    return invitations
        .map(
          (invitation) => PatientOrganizationInvitation.fromCallable(
            Map<String, dynamic>.from(invitation as Map),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> respondToOrganizationPatientInvitation({
    required String patientUid,
    required bool accepted,
  }) async {
    await _organizationFunctions
        .httpsCallable('respondToOrganizationPatientInvitation')
        .call(<String, Object?>{
          'patientUid': patientUid,
          'accepted': accepted,
        });
  }

  static Future<Map<String, dynamic>> respondToPatientOrganizationInvitation({
    required String organizationId,
    required bool accepted,
    required bool shareProfile,
    bool shareGenomicProfile = false,
    bool allowPrescriptions = false,
  }) async {
    final result = await _organizationFunctions
        .httpsCallable('respondToPatientOrganizationInvitation')
        .call(<String, Object?>{
          'organizationId': organizationId,
          'accepted': accepted,
          'shareProfile': accepted && shareProfile,
          'shareGenomicProfile': accepted && shareGenomicProfile,
          'allowPrescriptions': accepted && allowPrescriptions,
        });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<String> createPatientAccountInvitation({
    required String patientId,
    required String email,
  }) async {
    final result = await _organizationFunctions
        .httpsCallable('createPatientAccountInvitation')
        .call(<String, Object?>{'patientId': patientId, 'email': email.trim()});
    final data = Map<String, dynamic>.from(result.data as Map);
    final code = data['code'];
    if (code is! String || code.isEmpty) {
      throw const FormatException(
        'Patient invitation response did not include a setup code.',
      );
    }
    return code;
  }

  static Future<void> sendCurrentUserEmailVerification() async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Sign in before verifying your email.');
    }
    await user.sendEmailVerification();
  }

  static Future<User> reloadCurrentUser() async {
    final user = currentUser;
    if (user == null) throw StateError('Sign in to continue.');
    await user.reload();
    final refreshed = currentUser;
    if (refreshed == null) throw StateError('Sign in to continue.');
    await refreshed.getIdToken(true);
    return refreshed;
  }

  static Future<PatientInvitationPreview> previewPatientAccountInvitation(
    String code,
  ) async {
    final result = await _organizationFunctions
        .httpsCallable('previewPatientAccountInvitation')
        .call(<String, Object?>{'code': code.trim()});
    return PatientInvitationPreview.fromCallable(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  static Future<Map<String, dynamic>> respondToPatientAccountInvitation({
    required String code,
    required bool accepted,
    required bool shareDerivedProfile,
  }) async {
    final result = await _organizationFunctions
        .httpsCallable('respondToPatientAccountInvitation')
        .call(<String, Object?>{
          'code': code.trim(),
          'accepted': accepted,
          'shareDerivedProfile': accepted && shareDerivedProfile,
        });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<String> registerOrganizationPatient({
    required String name,
    required String idempotencyKey,
    int? birthYear,
  }) async {
    final requestData = <String, Object?>{
      'name': name,
      'idempotencyKey': idempotencyKey,
    };
    if (birthYear != null) {
      requestData['birthYear'] = birthYear;
    }
    final result = await _organizationFunctions
        .httpsCallable('registerOrganizationPatient')
        .call(requestData);
    final data = Map<String, dynamic>.from(result.data as Map);
    final patientId = data['patientId'];
    if (patientId is! String || patientId.isEmpty) {
      throw const FormatException(
        'Patient registration returned no identifier.',
      );
    }
    return patientId;
  }

  static Future<OrganizationPatient> getOrganizationPatientWorkspace(
    String patientId,
  ) async {
    try {
      final result = await _organizationFunctions
          .httpsCallable('getOrganizationPatientWorkspace')
          .call(<String, Object?>{'patientId': patientId});
      final data = Map<String, dynamic>.from(result.data as Map);
      return OrganizationPatient.fromCallable({
        'patientId': patientId,
        'name': data['name'],
        'birthYear': data['birthYear'],
        'vcfStatus': data['vcfStatus'],
        'analysisStatus': data['analysisStatus'],
        'sharedGenomicProfiles': data['sharedGenomicProfiles'],
        'prescriptionSharingAllowed':
            data['prescriptionSharingAllowed'] ?? true,
      });
    } catch (e) {
      debugPrint('Cloud getOrganizationPatientWorkspace fallback: $e');
    }

    // Fallback: Look up from listOrganizationPatients (which now queries Firestore directly)
    final list = (await listOrganizationPatients()).patients;
    var found = list.firstWhere(
      (p) => p.patientId == patientId,
      orElse: () => OrganizationPatient(
        patientId: patientId,
        name: 'Patient',
        vcfStatus: 'not_shared',
        analysisStatus: 'pending',
        vcfFileName: null,
        prescriptionSharingAllowed: true,
        sharedGenomicProfiles: const [],
      ),
    );

    // If patient still has no VCF data but we have their uid, directly query users/{uid}
    if (found.sharedGenomicProfiles.isEmpty && found.vcfFileName == null && isCloudAvailable) {
      final patientUid = (found.patientUid?.isNotEmpty == true) ? found.patientUid! : null;
      if (patientUid != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(patientUid)
              .get();
          final userData = userDoc.data();
          if (userData != null) {
            String? vcfFileName = found.vcfFileName;
            String vcfStatus = found.vcfStatus;
            List<SharedGenomicProfile> profiles = found.sharedGenomicProfiles;

            // Check patientProfile.vcf_filename
            final rawProf = userData['patientProfile'];
            if (rawProf is Map && rawProf['vcf_filename'] != null) {
              vcfFileName ??= rawProf['vcf_filename'] as String?;
              vcfStatus = 'uploaded';
            }

            // Check top-level vcfFileName / vcfStatus
            vcfFileName ??= (userData['vcfFileName'] as String?) ??
                (userData['vcfFilename'] as String?);
            if (vcfFileName != null && vcfStatus == 'not_shared') {
              vcfStatus = 'uploaded';
            }

            // Check sharedGenomicProfiles
            if (userData['sharedGenomicProfiles'] is List) {
              profiles = (userData['sharedGenomicProfiles'] as List)
                  .whereType<Map>()
                  .map((m) => SharedGenomicProfile.fromJson(
                        Map<String, dynamic>.from(m),
                      ))
                  .toList();
            }

            if (vcfFileName != null || profiles.isNotEmpty) {
              found = OrganizationPatient(
                patientId: found.patientId,
                name: found.name,
                patientUid: found.patientUid,
                birthYear: found.birthYear,
                vcfStatus: 'uploaded',
                analysisStatus: 'complete',
                vcfFileName: vcfFileName,
                prescriptionSharingAllowed: found.prescriptionSharingAllowed,
                sharedGenomicProfiles: profiles,
              );
            }
          }
        } catch (ex) {
          debugPrint('getOrganizationPatientWorkspace user doc fallback: $ex');
        }
      }
    }

    return found;
  }

  static Future<void> updatePatientOrganizationSharing({
    required String organizationId,
    required bool shareGenomicProfile,
    required bool allowPrescriptions,
  }) async {
    await _organizationFunctions
        .httpsCallable('setPatientOrganizationSharing')
        .call(<String, Object?>{
          'organizationId': organizationId,
          'shareGenomicProfile': shareGenomicProfile,
          'allowPrescriptions': allowPrescriptions,
        });
  }

  static Future<void> publishDerivedGenomicProfile({
    required String patientId,
    required String organizationId,
    required List<Map<String, Object?>> profiles,
  }) async {
    await _organizationFunctions
        .httpsCallable('publishDerivedGenomicProfile')
        .call(<String, Object?>{
          'patientId': patientId,
          'organizationId': organizationId,
          'profiles': profiles,
        });
  }

  static FirebaseFunctions get _organizationFunctions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  static Future<void> _savePrivacyNoticeAcknowledgment(String uid) async {
    // Cache acceptance locally first
    await ScreenCacheService.cachePrivacyNoticeAccepted(uid);
    try {
      final acknowledgment = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('consents')
          .doc('privacy_notice');

      // Try version 1.1 first
      try {
        await acknowledgment.set({
          'accepted': true,
          'noticeVersion': '1.1',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          debugPrint('Notice v1.1 write rejected, falling back to v1.0');
          await acknowledgment.set({
            'accepted': true,
            'noticeVersion': '1.0',
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return;
        }
        rethrow;
      }
    } on FirebaseException catch (error) {
      debugPrint('Privacy acknowledgment sync failed (${error.code}); continuing with local cache.');
    } catch (error) {
      debugPrint('Privacy acknowledgment error: $error; continuing with local cache.');
    }
  }

  static Future<void> saveReport(PgxMultiReport report) async {
    await LocalReportService.save(report);
  }

  static Stream<List<PgxMultiReport>> streamUserReports() async* {
    final localReports = await LocalReportService.load();
    yield localReports;

    final user = currentUser;
    if (user == null) return;

    try {
      await for (final snapshot
          in FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('reports')
              .orderBy('timestamp', descending: true)
              .snapshots()) {
        final cloudReports = snapshot.docs
            .map((doc) => PgxMultiReport.fromJson(doc.data()))
            .toList();
        final merged = _mergeReports(
          cloudReports,
          await LocalReportService.load(),
        );
        yield merged;
      }
    } on FirebaseException catch (error) {
      debugPrint(
        'Cloud report history unavailable; local history retained: ${error.code}',
      );
    }
  }

  static Future<void> deleteReport(String reportId) async {
    final user = currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reports')
          .doc(reportId)
          .delete();
    }
    await LocalReportService.delete(reportId);
  }

  static List<PgxMultiReport> _mergeReports(
    List<PgxMultiReport> cloudReports,
    List<PgxMultiReport> localReports,
  ) {
    final byId = <String, PgxMultiReport>{
      for (final report in localReports) report.reportId: report,
    };
    for (final report in cloudReports) {
      byId[report.reportId] = report;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return merged;
  }

  static Future<void> saveChatMessage(
    String reportId,
    ChatMessage message,
  ) async {}
  static Stream<List<ChatMessage>> streamChatMessages(String reportId) =>
      Stream.value([]);

  /// Completely resets all local device caches and in-memory services.
  static Future<void> clearLocalStateAndCache() async {
    try {
      await ScreenCacheService.clearAllCache();
      await PatientProfileService.clear();
      await PrescriptionService.instance.clearAllPrescriptions();
      await AuditService.instance.clearAllLogs();
      debugPrint('FirebaseService: Cleared all local state and device caches.');
    } catch (e) {
      debugPrint('FirebaseService.clearLocalStateAndCache note: $e');
    }
  }

  static void _requireAuth() {
    if (!_initialized) {
      throw StateError(
        'Firebase Auth is unavailable. Check google-services.json, internet connection, and Firebase configuration.',
      );
    }
  }
}
