import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/screens/sign_in_screen.dart';

void main() {
  testWidgets('sign-in lets users choose a patient or organization dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignInScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to your dashboard'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Organization'), findsOneWidget);

    await tester.tap(find.text('Organization'));
    await tester.pumpAndSettle();

    expect(find.text('Organization'), findsOneWidget);
  });

  testWidgets('signup keeps the selected organization workspace intent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignInScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Organization').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign Up ↗'));
    await tester.tap(find.text('Sign Up ↗'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Choose which workspace to open after signup.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'lists the organization name and city in patient search',
      ),
      findsOneWidget,
    );
  });
}
