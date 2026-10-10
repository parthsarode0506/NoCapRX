import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/services/firebase_service.dart';

void main() {
  test(
    'explains Firestore setup failure without assuming App Check is broken',
    () {
      final message = FirebaseService.mapAccountSetupError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        authAccountExists: true,
      );

      expect(message, contains('Firebase sign-in succeeded'));
      expect(message, contains('publish Firestore Rules'));
      expect(message, contains('Retry account setup'));
      expect(message, isNot(contains('Android logs also show')));
      expect(message, contains('App Check'));
    },
  );

  test('explains the stale privacy-notice rule that blocks signup', () {
    final message = FirebaseService.mapAccountSetupError(
      AccountSetupFailure(
        step: 'privacy acknowledgment (users/{uid}/consents/privacy_notice)',
        cause: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      ),
      authAccountExists: true,
    );

    expect(message, contains('rules are outdated'));
    expect(message, contains('version 1.0'));
    expect(message, contains('version 1.1'));
    expect(message, contains('Retry account setup'));
  });

  test('explains when organization directory rules block signup', () {
    final message = FirebaseService.mapAccountSetupError(
      AccountSetupFailure(
        step: 'public organization directory listing',
        cause: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      ),
      authAccountExists: true,
    );

    expect(message, contains('organization directory listing'));
    expect(message, contains('Retry account setup'));
  });

  test(
    'does not suggest account recovery when Auth account was not created',
    () {
      final message = FirebaseService.mapAccountSetupError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        authAccountExists: false,
      );

      expect(message, isNot(contains('Authentication account was created')));
    },
  );

  test(
    'explains an internal Functions error without showing the bare code',
    () {
      final message = FirebaseService.mapAuthError(
        FirebaseFunctionsException(code: 'internal', message: '[0]'),
      );

      expect(message, contains('Deploy the latest Cloud Functions'));
      expect(message, contains('Firebase Functions logs'));
      expect(message, isNot('[0]'));
    },
  );
}
