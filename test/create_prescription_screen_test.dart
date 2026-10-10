import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/models/organization_patient.dart';
import 'package:ondevicerx/screens/create_prescription_screen.dart';

void main() {
  testWidgets('medicine review is indeterminate without shared patient genetics',
      (tester) async {
    const patient = OrganizationPatient(
      patientId: 'SYNTHETIC_PATIENT_1',
      name: 'Synthetic Patient',
    );
    await tester.pumpWidget(
      const MaterialApp(home: CreatePrescriptionScreen(patient: patient)),
    );

    await tester.tap(find.text('Add Drug'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Clopidogrel',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Indeterminate'), findsOneWidget);
    expect(
      find.textContaining('No approved, consent-authorized clinical rule assessment'),
      findsOneWidget,
    );
    expect(find.textContaining('safe'), findsNothing);
  });

  testWidgets('prescription requires a medicine before it can be published',
      (tester) async {
    const patient = OrganizationPatient(
      patientId: 'SYNTHETIC_PATIENT_2',
      name: 'Synthetic Patient',
    );
    await tester.pumpWidget(
      const MaterialApp(home: CreatePrescriptionScreen(patient: patient)),
    );

    final issueButton = find.text('Publish to patient dashboard');
    await tester.dragUntilVisible(
      issueButton,
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.tap(issueButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Add at least one medicine first'),
      findsOneWidget,
    );
  });
}
