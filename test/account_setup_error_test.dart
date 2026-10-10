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

  test('identifies which Firestore onboarding write was denied', () {
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

    expect(
      message,
      contains('privacy acknowledgment (users/{uid}/consents/privacy_notice)'),
    );
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
