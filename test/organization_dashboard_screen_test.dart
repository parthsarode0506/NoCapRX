import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/screens/organization_dashboard_screen.dart';

void main() {
  testWidgets('shows the organization workspace and available pathways', (
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
    expect(find.text('Patient records'), findsOneWidget);
    expect(find.text('Search records'), findsOneWidget);
    expect(find.text('Add New Patient'), findsOneWidget);

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

  testWidgets('requires a meaningful patient search query', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationDashboardScreen(
          organizationName: Future.value('Sample Hospital'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Search records'));
    await tester.tap(find.text('Search records'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter at least two characters to search.'),
      findsOneWidget,
    );
  });

  testWidgets('does not gate organization actions on a client access check', (
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

    expect(find.text('Organization Dashboard'), findsOneWidget);
    expect(find.text('Organization workspace'), findsOneWidget);
    expect(
      find.text('Organization access is awaiting administrator setup.'),
      findsNothing,
    );
    await tester.ensureVisible(find.text('Search records'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).enabled,
      isNot(false),
    );
    await tester.tap(find.text('Search records'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter at least two characters to search.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Add New Patient'));
    await tester.tap(find.text('Add New Patient'));
    await tester.pumpAndSettle();
    expect(find.text('Register patient'), findsOneWidget);
    expect(
      find.text('Organization access is awaiting administrator setup.'),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Generate Drug-Safety Report'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Generate Drug-Safety Report'), findsOneWidget);
    expect(find.text('Create Prescription'), findsOneWidget);
  });
}
