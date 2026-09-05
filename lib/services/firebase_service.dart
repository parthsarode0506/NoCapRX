import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/app_user.dart';
import '../models/pgx_report.dart';
import '../models/chat_message.dart';

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static FirebaseAnalytics? _analytics;
  static bool _initialized = false;

  /// Initializes Firebase Core, Crashlytics, Analytics, and App Check safely.
  /// On web, uses FirebaseOptions from .env since google-services.json is Android-only.
  static Future<void> init() async {
    try {
      // On web, Firebase needs explicit options. On Android, google-services.json is auto-detected.
      if (identical(0, 0.0)) {
        // This is always true in dart2js (web), false in VM (mobile)
        // Use a more reliable check:
      }
      
      final projectId = dotenv.env['FIREBASE_PROJECT_ID'];
      final appId = dotenv.env['FIREBASE_APP_ID'];
      final apiKey = dotenv.env['FIREBASE_API_KEY'];
      final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'];
      final projectNumber = dotenv.env['FIREBASE_PROJECT_NUMBER'];

      if (Firebase.apps.isEmpty) {
        if (projectId != null && appId != null && apiKey != null) {
          await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: apiKey,
              appId: appId,
              messagingSenderId: projectNumber ?? '',
              projectId: projectId,
              storageBucket: storageBucket,
            ),
          );
        } else {
          await Firebase.initializeApp();
        }
      }
      _initialized = true;

      // Crashlytics setup (not available on web)
      try {
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      } catch (_) {}

      // Analytics
      try {
        _analytics = FirebaseAnalytics.instance;
      } catch (_) {}

      // App Check (Play Integrity on Android, not available on web)
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.deviceCheck,
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Firebase init warning (proceeding in local/mock mode if unconfigured): $e');
    }
  }

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Logs Firebase Analytics event safely.
  static Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    try {
      if (_initialized && _analytics != null) {
        await _analytics!.logEvent(name: name, parameters: parameters);
      }
    } catch (e) {
      debugPrint('Analytics log error: $e');
    }
  }

  /// Maps Firebase Auth Error Codes to User-Friendly strings.
  static String mapAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No user account found with this email address.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password. Please try again.';
        case 'invalid-email':
          return 'The email address format is invalid.';
        case 'email-already-in-use':
          return 'An account with this email address already exists.';
        case 'weak-password':
          return 'Password must be at least 6 characters long.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'user-disabled':
          return 'This user account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        default:
          return error.message ?? 'Authentication failed (${error.code}).';
      }
    }
    return error.toString();
  }

  /// Sign In with Email & Password.
  static Future<UserCredential> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await logEvent('sign_in', {'method': 'email'});
    return cred;
  }

  /// Sign Up with Email & Password, writing user profile doc to Firestore.
  static Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = cred.user;
    if (user != null) {
      await user.updateDisplayName(displayName);
      await saveUserProfile(AppUser(
        uid: user.uid,
        displayName: displayName,
        email: email,
        role: role,
        createdAt: DateTime.now(),
      ));
    }

    await logEvent('sign_up', {'method': 'email', 'role': role});
    return cred;
  }

  /// Google Sign-In Flow.
  static Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

    if (googleUser == null) return null; // Canceled by user

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user;

    if (user != null) {
      // Check if user profile doc exists in Firestore, create if absent
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await saveUserProfile(AppUser(
          uid: user.uid,
          displayName: user.displayName ?? 'Google User',
          email: user.email ?? '',
          role: 'Patient',
          createdAt: DateTime.now(),
        ));
      }
    }

    await logEvent('sign_in', {'method': 'google'});
    return cred;
  }

  /// Send Password Reset Email.
  static Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Sign Out.
  static Future<void> signOut() async {
    await GoogleSignIn().signOut().catchError((_) => null);
    await _auth.signOut();
  }

  /// Writes user profile to Firestore (`users/{uid}`).
  static Future<void> saveUserProfile(AppUser user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'displayName': user.displayName,
          'email': user.email,
          'role': user.role,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Firestore saveUserProfile error: $e');
    }
  }

  /// Reads user profile from Firestore (`users/{uid}`).
  static Future<AppUser?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return AppUser.fromJson(doc.data()!);
      }
    } catch (e) {
      debugPrint('Firestore getUserProfile error: $e');
    }
    return null;
  }

  /// Saves derived report JSON to Firestore (`users/{uid}/reports/{reportId}`).
  /// NOTE: Raw VCF file content is NEVER written to Firestore!
  static Future<void> saveReport(PgxMultiReport report) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('reports')
          .doc(report.reportId)
          .set(report.toJson());

      await logEvent('report_generated', {
        'report_id': report.reportId,
        'drug_count': report.drugReports.length,
      });
    } catch (e) {
      debugPrint('Firestore saveReport error: $e');
    }
  }

  /// Fetches history of reports for current user.
  static Stream<List<PgxMultiReport>> streamUserReports() {
    final uid = currentUser?.uid;
    if (uid == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('reports')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => PgxMultiReport.fromJson(doc.data())).toList();
    });
  }

  /// Saves a chat message under `users/{uid}/reports/{reportId}/chat/{messageId}`.
  static Future<void> saveChatMessage(String reportId, ChatMessage message) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('reports')
          .doc(reportId)
          .collection('chat')
          .doc(message.id)
          .set(message.toJson());

      await logEvent('chatbot_query', {'report_id': reportId, 'role': message.role});
    } catch (e) {
      debugPrint('Firestore saveChatMessage error: $e');
    }
  }

  /// Streams chat history for a report.
  static Stream<List<ChatMessage>> streamChatMessages(String reportId) {
    final uid = currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('reports')
        .doc(reportId)
        .collection('chat')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ChatMessage.fromJson(doc.data())).toList();
    });
  }
}
