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
    expect(
      find.textContaining('automatically lists your name and city'),
      findsOneWidget,
    );
    expect(find.text('Patient records'), findsOneWidget);
    expect(find.text('Review patient requests'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Search records'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Search records'), findsOneWidget);
    expect(find.text('Add New Patient'), findsNothing);

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

    await tester.scrollUntilVisible(
      find.text('Search records'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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
    expect(find.textContaining('lists your name and city'), findsOneWidget);
    expect(find.text('Add New Patient'), findsNothing);
    expect(
      find.text('Organization access is awaiting administrator setup.'),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.text('Search records'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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

    expect(
      find.text('Organization access is awaiting administrator setup.'),
      findsNothing,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Patient name'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Generate Drug-Safety Report'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Generate Drug-Safety Report'), findsOneWidget);
    expect(find.text('Create Prescription'), findsOneWidget);
  });
}
