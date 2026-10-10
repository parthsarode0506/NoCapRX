import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/screens/sign_up_screen.dart';

void main() {
  testWidgets('signup offers patient and organization workspace options', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignUpScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Choose which workspace to open after signup.'),
      findsOneWidget,
    );
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Organization'), findsOneWidget);
    expect(find.text('Organization name'), findsNothing);
    expect(find.text('City'), findsNothing);
    expect(find.text('Hospital invitation code (optional)'), findsOneWidget);
    expect(find.text('Professional registration number'), findsNothing);
    expect(find.text('Clinical pharmacist'), findsNothing);
  });

  testWidgets('organization workspace intent is retained on signup', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SignUpScreen(organizationWorkspaceRequested: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Choose which workspace to open after signup.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('This opens the organization dashboard.'),
      findsOneWidget,
    );
    expect(find.text('Organization name'), findsOneWidget);
    expect(find.text('City'), findsOneWidget);
    expect(find.text('Hospital invitation code (optional)'), findsNothing);
    expect(find.text('Clinical pharmacist'), findsNothing);
  });

  testWidgets('selecting Organization shows the access boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignUpScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Organization'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This opens the organization dashboard.'),
      findsOneWidget,
    );
  });
}
