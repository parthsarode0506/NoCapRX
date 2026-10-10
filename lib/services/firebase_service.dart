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
import 'local_report_service.dart';

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
    try {
      await saveUserProfile(
        AppUser(
          uid: user.uid,
          displayName: displayName.trim(),
          email: user.email ?? '',
          role: accountType,
          locale: locale,
          createdAt: DateTime.now(),
          organizationName: organizationName.trim(),
          city: city.trim(),
        ),
      );
    } catch (error) {
      throw AccountSetupFailure(
        step: 'user profile (users/{uid})',
        cause: error,
      );
    }
    try {
      await _savePrivacyNoticeAcknowledgment(user.uid);
    } catch (error) {
      throw AccountSetupFailure(
        step: 'privacy acknowledgment (users/{uid}/consents/privacy_notice)',
        cause: error,
      );
    }
    if (accountType == 'organization') {
      try {
        await _publishSelfRegisteredOrganization(
          user: user,
          name: organizationName.trim(),
          city: city.trim(),
        );
      } catch (error) {
        throw AccountSetupFailure(
          step: 'public organization directory listing',
          cause: error,
        );
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
    try {
      final firestore = FirebaseFirestore.instance;
      final profileRef = firestore.collection('users').doc(user.uid);
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(profileRef);
        if (snapshot.exists) {
          transaction.update(profileRef, {
            'displayName': user.displayName.trim(),
            'accountType': user.role,
            'locale': user.locale,
            'organizationName': user.organizationName,
            'city': user.city,
          });
          return;
        }
        transaction.set(profileRef, {
          'displayName': user.displayName.trim(),
          'accountType': user.role,
          'locale': user.locale,
          'organizationName': user.organizationName,
          'city': user.city,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      debugPrint('User profile sync unavailable: ${error.code}');
      rethrow;
    }
  }

  static Future<AppUser?> getUserProfile(String uid) async {
    if (!_initialized) return null;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snapshot.data();
      if (data == null) return null;
      final profile = <String, dynamic>{...data, 'uid': uid};
      profile['role'] = profile['accountType'] ?? 'patient';
      profile['linkedPatientId'] = data['linkedPatientId'];
      final authUser = _auth.currentUser;
      if (authUser?.uid == uid) {
        profile['email'] = authUser?.email ?? '';
      }
      return AppUser.fromJson(profile);
    } on FirebaseException catch (error) {
      debugPrint('User profile unavailable: ${error.code}');
      return null;
    }
  }

  static Future<bool> hasOrganizationWorkspace({
    bool forceRefresh = false,
  }) async {
    final user = currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(forceRefresh);
    return {'doctor', 'pharmacist'}.contains(token.claims?['role']) &&
        token.claims?['orgId'] is String &&
        (token.claims?['orgId'] as String).isNotEmpty;
  }

  static Future<List<OrganizationPatient>> searchOrganizationPatients(
    String query,
  ) async {
    final normalized = _normalizeOrganizationSearch(query);
    if (normalized.length < 2) {
      throw ArgumentError('Enter at least two characters to search.');
    }
    final result = await _organizationFunctions
        .httpsCallable('searchOrganizationPatients')
        .call(<String, Object?>{'query': normalized});
    final data = Map<String, dynamic>.from(result.data as Map);
    final patients = data['patients'];
    if (patients is! List) {
      throw const FormatException(
        'Organization patient search returned an invalid response.',
      );
    }
    return patients
        .map(
          (patient) => OrganizationPatient.fromCallable(
            Map<String, dynamic>.from(patient as Map),
          ),
        )
        .toList(growable: false);
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

  static Future<void> _publishSelfRegisteredOrganization({
    required User user,
    required String name,
    required String city,
  }) async {
    if (name.length < 2 || city.isEmpty) {
      throw ArgumentError(
        'Enter an organization name and city to appear in patient search.',
      );
    }
    final normalizedName = _normalizeOrganizationSearch(name);
    await FirebaseFirestore.instance
        .collection('organizationDirectory')
        .doc(user.uid)
        .set({
          'organizationId': user.uid,
          'name': name,
          'city': city,
          'normalizedName': normalizedName,
          'active': true,
          'selfRegistered': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<List<OrganizationDirectoryEntry>> findOrganizations(
    String query,
  ) async {
    final normalized = _normalizeOrganizationSearch(query);
    if (normalized.length < 2) {
      throw ArgumentError('Enter at least two characters to search.');
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('organizationDirectory')
        .where('active', isEqualTo: true)
        .orderBy('normalizedName')
        .startAt([normalized])
        .endAt(['$normalized\uf8ff'])
        .limit(20)
        .get();
    return snapshot.docs
        .map(
          (document) => OrganizationDirectoryEntry.fromJson({
            ...document.data(),
            'organizationId': document.id,
          }),
        )
        .toList(growable: false);
  }

  static Future<void> sendOrganizationAccessRequest(
    OrganizationDirectoryEntry organization,
  ) async {
    await _organizationFunctions
        .httpsCallable('requestOrganizationAccessById')
        .call(<String, Object?>{'organizationId': organization.organizationId});
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
          }),
        )
        .toList(growable: false);
  }

  static Future<List<OrganizationAccessRequest>>
  listOrganizationPatientRequests() async {
    final orgId = await _currentOrganizationId();
    final invitations = await listOrganizationPatientInvitations();
    return invitations
        .map(
          (invitation) => OrganizationAccessRequest.fromJson({
            'organizationId': orgId,
            'organizationName': invitation.organizationName,
            'patientUid': invitation.patientUid,
            'patientId': invitation.patientId,
            'patientName': invitation.patientName,
            'status': invitation.status,
            'requestedAt': invitation.requestedAt?.toIso8601String(),
          }),
        )
        .toList(growable: false);
  }

  static Future<void> respondToOrganizationAccessRequest({
    required OrganizationAccessRequest invitation,
    required bool accepted,
  }) async {
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
    if (user == null) throw StateError('Sign in to continue.');
    final token = await user.getIdTokenResult();
    final claims = token.claims ?? const {};
    final orgId = claims['orgId'];
    if (claims['verified'] != true ||
        !{'doctor', 'pharmacist'}.contains(claims['role']) ||
        orgId is! String ||
        orgId.isEmpty) {
      throw StateError(
        'An active verified organization membership is required.',
      );
    }
    return orgId;
  }

  static String _normalizeOrganizationSearch(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

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
  }) async {
    final result = await _organizationFunctions
        .httpsCallable('respondToPatientOrganizationInvitation')
        .call(<String, Object?>{
          'organizationId': organizationId,
          'accepted': accepted,
          'shareProfile': accepted && shareProfile,
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
    });
  }

  static FirebaseFunctions get _organizationFunctions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  static Future<void> _savePrivacyNoticeAcknowledgment(String uid) async {
    final acknowledgment = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('consents')
        .doc('privacy_notice');
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(acknowledgment);
      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data['accepted'] != true) {
          throw StateError('The existing privacy acknowledgment is invalid.');
        }
        if (data['noticeVersion'] == '1.1') return;
        if (data['noticeVersion'] == '1.0') {
          transaction.update(acknowledgment, {
            'noticeVersion': '1.1',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        throw StateError('The existing privacy acknowledgment is invalid.');
      }
      transaction.set(acknowledgment, {
        'accepted': true,
        'noticeVersion': '1.1',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
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

  static void _requireAuth() {
    if (!_initialized) {
      throw StateError(
        'Firebase Auth is unavailable. Check google-services.json, internet connection, and Firebase configuration.',
      );
    }
  }
}
