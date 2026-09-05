import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/pgx_report.dart';

/// Firebase Auth is optional cloud functionality. VCF parsing and PGx analysis
/// remain local and no raw genomic content is sent to Firebase.
class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static bool _initialized = false;

  static bool get isCloudAvailable => _initialized;
  static User? get currentUser => _initialized ? _auth.currentUser : null;
  static Stream<User?> get authStateChanges => _initialized
      ? _auth.authStateChanges()
      : Stream<User?>.value(null);

  static Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          final apiKey = dotenv.env['FIREBASE_API_KEY'] ?? 'AIzaSyDgs2zWU4ZLAMc0th-8IezaEnQBTAm1IjQ';
          final appId = dotenv.env['FIREBASE_APP_ID'] ?? '1:525855030557:android:9eb65b4222ae899309f5f4';
          final projectId = dotenv.env['FIREBASE_PROJECT_ID'] ?? 'on-devicerx';
          final messagingSenderId = dotenv.env['FIREBASE_PROJECT_NUMBER'] ?? '525855030557';
          final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? 'on-devicerx.firebasestorage.app';

          await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: apiKey,
              appId: appId,
              messagingSenderId: messagingSenderId,
              projectId: projectId,
              storageBucket: storageBucket,
            ),
          );
        } else {
          await Firebase.initializeApp();
        }
      }
      _initialized = true;
      debugPrint('Firebase Auth initialized successfully.');
    } catch (error) {
      _initialized = false;
      debugPrint('Firebase unavailable; continuing in local mode: $error');
    }
  }

  static String mapAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found for this email address.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'email-already-in-use':
          return 'An account with this email already exists.';
        case 'weak-password':
          return 'Password must be at least 6 characters long.';
        case 'network-request-failed':
          return 'Network error. Check your internet connection.';
        case 'operation-not-allowed':
          return 'Email/password sign-in is disabled in Firebase Console.';
        case 'too-many-requests':
          return 'Too many attempts. Try again later.';
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
    _requireAuth();
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String role,
  }) async {
    _requireAuth();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName(displayName.trim());
    return credential;
  }

  /// Google provider is intentionally unavailable until an OAuth client is
  /// configured for this Android package. Email/password remains supported.
  static Future<UserCredential?> signInWithGoogle() async {
    throw StateError(
      'Google Sign-In requires an Android OAuth client configuration. Use email/password sign-in.',
    );
  }

  static Future<void> sendPasswordReset(String email) async {
    _requireAuth();
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> signOut() async {
    if (_initialized) await _auth.signOut();
  }

  // Cloud profile/report sync is disabled so raw VCF and derived health data
  // are not uploaded without an explicit backend privacy configuration.
  static Future<void> saveUserProfile(AppUser user) async {}
  static Future<AppUser?> getUserProfile(String uid) async => null;
  static Future<void> saveReport(PgxMultiReport report) async {}
  static Stream<List<PgxMultiReport>> streamUserReports() => Stream.value([]);
  static Future<void> saveChatMessage(String reportId, ChatMessage message) async {}
  static Stream<List<ChatMessage>> streamChatMessages(String reportId) =>
      Stream.value([]);

  static void _requireAuth() {
    if (!_initialized) {
      throw StateError(
        'Firebase Auth is unavailable. Check google-services.json and Firebase configuration.',
      );
    }
  }
}
