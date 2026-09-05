import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/pgx_report.dart';
import 'local_report_service.dart';

/// Firebase Auth service handling real cloud authentication.
/// VCF parsing and genomic analysis remain on-device and private.
class FirebaseService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static bool _initialized = false;

  static bool get isCloudAvailable => _initialized;
  static User? get currentUser => _initialized ? _auth.currentUser : null;
  static Stream<User?> get authStateChanges => _initialized
      ? _auth.authStateChanges()
      : Stream<User?>.value(null);

  static Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } catch (e) {
          debugPrint('Firebase.initializeApp with options failed: $e; trying default binding...');
          await Firebase.initializeApp();
        }
      }
      _initialized = true;
      debugPrint('Firebase Auth initialized successfully for project on-devicerx.');
    } catch (error) {
      _initialized = false;
      debugPrint('Firebase initialization failed: $error');
    }
  }

  static String mapAuthError(Object error) {
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
    return error.toString();
  }

  static Future<UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    if (!_initialized) {
      await init();
    }
    _requireAuth();
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    String role = 'User',
  }) async {
    if (!_initialized) {
      await init();
    }
    _requireAuth();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    await user?.updateDisplayName(displayName.trim());
    if (user != null) {
      await saveUserProfile(AppUser(
        uid: user.uid,
        displayName: displayName.trim(),
        email: user.email ?? email.trim(),
        role: role,
        createdAt: DateTime.now(),
      ));
    }
    return credential;
  }

  /// Google Sign-In requires an SHA-1 fingerprint registered in Firebase Console
  static Future<UserCredential?> signInWithGoogle() async {
    throw StateError(
      'Google Sign-In requires SHA-1 fingerprint in Firebase Console. Please use Email/Password sign-in or Sign Up.',
    );
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

  // Cloud sync stores account metadata and derived reports only. Raw VCF data remains on-device.
  static Future<void> saveUserProfile(AppUser user) async {
    if (!_initialized) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(user.toJson(), SetOptions(merge: true));
    } on FirebaseException catch (error) {
      debugPrint('User profile sync unavailable: ${error.code}');
    }
  }

  static Future<AppUser?> getUserProfile(String uid) async {
    if (!_initialized) return null;
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snapshot.data();
      return data == null ? null : AppUser.fromJson(data);
    } on FirebaseException catch (error) {
      debugPrint('User profile unavailable: ${error.code}');
      return null;
    }
  }
  static Future<void> saveReport(PgxMultiReport report) async {
    await LocalReportService.save(report);
    final user = currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reports')
          .doc(report.reportId)
          .set(report.toJson());
    } on FirebaseException catch (error) {
      debugPrint('Cloud report backup failed; local copy retained: ${error.code}');
    }
  }

  static Stream<List<PgxMultiReport>> streamUserReports() async* {
    final localReports = await LocalReportService.load();
    yield localReports;

    final user = currentUser;
    if (user == null) return;

    try {
      await for (final snapshot in FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reports')
          .orderBy('timestamp', descending: true)
          .snapshots()) {
        final cloudReports = snapshot.docs
            .map((doc) => PgxMultiReport.fromJson(doc.data()))
            .toList();
        final merged = _mergeReports(cloudReports, await LocalReportService.load());
        yield merged;
      }
    } on FirebaseException catch (error) {
      debugPrint('Cloud report history unavailable; local history retained: ${error.code}');
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
  static Future<void> saveChatMessage(String reportId, ChatMessage message) async {}
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
