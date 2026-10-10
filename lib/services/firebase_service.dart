import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/organization_patient.dart';
import '../models/pgx_report.dart';
import 'local_report_service.dart';

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
    if (authAccountExists &&
        error is FirebaseException &&
        error.code == 'permission-denied') {
      return 'Your Firebase Authentication account was created, but Firestore '
          'blocked profile setup. Android logs also show App Check token '
          'verification failing. Enable the Firebase App Check API, register '
          'a new Android debug token (or configure Play Integrity), and confirm '
          'Firestore rules allow the signed-in user to create their own profile '
          'and privacy acknowledgment. Then tap “Retry account setup”; do not '
          'create another account.';
    }
    return mapAuthError(error);
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
    await user.updateDisplayName(displayName.trim());
    await saveUserProfile(
      AppUser(
        uid: user.uid,
        displayName: displayName.trim(),
        email: user.email ?? '',
        role: accountType,
        locale: locale,
        createdAt: DateTime.now(),
      ),
    );
    await _savePrivacyNoticeAcknowledgment(user.uid);
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
    if (!_initialized) return;
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
          });
          return;
        }
        transaction.set(profileRef, {
          'displayName': user.displayName.trim(),
          'accountType': user.role,
          'locale': user.locale,
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
    final result = await _organizationFunctions
        .httpsCallable('searchOrganizationPatients')
        .call(<String, Object?>{'query': query});
    final data = Map<String, dynamic>.from(result.data as Map);
    final patients = data['patients'];
    if (patients is! List) {
      throw const FormatException(
        'Patient search returned an invalid response.',
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
    final result = await _organizationFunctions
        .httpsCallable('getOrganizationSummary')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['name'] as String? ?? 'Organization';
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
    return OrganizationPatient.fromCallable(
      Map<String, dynamic>.from(result.data as Map),
    );
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
        if (data['accepted'] == true && data['noticeVersion'] == '1.0') return;
        throw StateError('The existing privacy acknowledgment is invalid.');
      }
      transaction.set(acknowledgment, {
        'accepted': true,
        'noticeVersion': '1.0',
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
