import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/app_user.dart';
import '../models/pgx_report.dart';
import '../models/chat_message.dart';

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _initialized = false;

  static bool get isCloudAvailable => _initialized;
  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Initializes online Firebase Core & services.
  static Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          final projectId = dotenv.env['FIREBASE_PROJECT_ID'];
          final appId = dotenv.env['FIREBASE_APP_ID'];
          final apiKey = dotenv.env['FIREBASE_API_KEY'];
          final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'];
          final projectNumber = dotenv.env['FIREBASE_PROJECT_NUMBER'];

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
        } else {
          // On Android / iOS, native configuration is automatically loaded from google-services.json
          await Firebase.initializeApp();
        }
      }
      _initialized = true;
      debugPrint('Firebase online services initialized successfully.');
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
      rethrow;
    }
  }

  /// Maps Firebase Auth exceptions to friendly error messages.
  static String mapAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email address.';
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

  /// Sign In with Email & Password online.
  static Future<UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return cred;
  }

  /// Sign Up with Email & Password online, writing user profile doc to Firestore.
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
      await saveUserProfile(
        AppUser(
          uid: user.uid,
          displayName: displayName,
          email: email.trim(),
          role: role,
          createdAt: DateTime.now(),
        ),
      );
    }

    return cred;
  }

  /// Online Google Sign-In Flow.
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return null; // Canceled by user

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final cred = await _auth.signInWithCredential(credential);
      final user = cred.user;

      if (user != null) {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (!userDoc.exists) {
          await saveUserProfile(
            AppUser(
              uid: user.uid,
              displayName: user.displayName ?? 'Google User',
              email: user.email ?? '',
              role: 'Patient',
              createdAt: DateTime.now(),
            ),
          );
        }
      }

      return cred;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      rethrow;
    }
  }

  /// Send Password Reset Email.
  static Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Sign Out online.
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
      rethrow;
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
    } catch (e) {
      debugPrint('Firestore saveReport error: $e');
    }
  }

  /// Fetches history of reports for current user from Firestore.
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
      return snapshot.docs
          .map((doc) => PgxMultiReport.fromJson(doc.data()))
          .toList();
    });
  }

  /// Saves a chat message under `users/{uid}/reports/{reportId}/chat/{messageId}`.
  static Future<void> saveChatMessage(
    String reportId,
    ChatMessage message,
  ) async {
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
    } catch (e) {
      debugPrint('Firestore saveChatMessage error: $e');
    }
  }

  /// Streams chat history for a report from Firestore.
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
      return snapshot.docs
          .map((doc) => ChatMessage.fromJson(doc.data()))
          .toList();
    });
  }
}
