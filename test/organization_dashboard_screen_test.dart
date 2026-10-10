import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/screens/organization_dashboard_screen.dart';

void main() {
  testWidgets('shows directory-only state for an unprovisioned signup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationDashboardScreen(
          organizationName: Future.value('Sample Hospital'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Organization workspace'), findsOneWidget);
    expect(find.text('Sample Hospital'), findsWidgets);
    expect(
      find.textContaining('Organization signup lists this name and city'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'reviewing contact requests for this listing does not require professional verification',
      ),
      findsOneWidget,
    );
    expect(find.text('Patient records'), findsNothing);
    expect(find.text('Review patient requests'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Clinical workflows'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Generate Drug-Safety Report'), findsOneWidget);
    expect(find.text('Create Prescription'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('does not retrieve or upload raw VCF files'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not retrieve or upload raw VCF files'),
      findsOneWidget,
    );
  });
}
