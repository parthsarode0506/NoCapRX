import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/services/firebase_service.dart';

void main() {
  test(
    'explains Android Firestore setup failure after Auth account creation',
    () {
      final message = FirebaseService.mapAccountSetupError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        authAccountExists: true,
      );

      expect(message, contains('Authentication account was created'));
      expect(message, contains('App Check'));
      expect(message, contains('Retry account setup'));
    },
  );

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
}
