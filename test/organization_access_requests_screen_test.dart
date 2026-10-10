import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/screens/organization_access_requests_screen.dart';

void main() {
  testWidgets('explains directory-only access instead of showing a raw error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OrganizationAccessRequestsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Sign in to continue.'), findsOneWidget);
    expect(
      find.textContaining('active verified organization membership'),
      findsNothing,
    );
    expect(find.text('Retry'), findsOneWidget);
  });
}
