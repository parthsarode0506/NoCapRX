import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevicerx/theme/severity_style.dart';

void main() {
  group('AdvisoryCopy', () {
    test('accepts advisory wording', () {
      expect(
        AdvisoryCopy.isClean(
          'Consider discussing this with your prescriber or pharmacist.',
        ),
        isTrue,
      );
    });

    test('flags banned directive phrases', () {
      expect(AdvisoryCopy.findings('You must stop taking it'), isNotEmpty);
      expect(
        AdvisoryCopy.findings('Do not take this medicine'),
        contains('do not take'),
      );
      expect(AdvisoryCopy.isClean('This will cause harm'), isFalse);
    });
  });

  group('SeverityStyle mapping', () {
    test('maps legacy engine labels to the canonical severity model', () {
      expect(SeverityStyle.levelFromRiskLabel('Safe'), SeverityLevel.info);
      expect(
        SeverityStyle.levelFromRiskLabel('No major risk identified'),
        SeverityLevel.info,
      );
      expect(
        SeverityStyle.levelFromRiskLabel('Adjust Dosage'),
        SeverityLevel.consider,
      );
      expect(
        SeverityStyle.levelFromRiskLabel('Additional medical review required'),
        SeverityLevel.caution,
      );
      expect(
        SeverityStyle.levelFromRiskLabel('High-risk finding'),
        SeverityLevel.highRisk,
      );
      expect(SeverityStyle.levelFromRiskLabel('Toxic'), SeverityLevel.highRisk);
      expect(
        SeverityStyle.levelFromRiskLabel('Unknown'),
        SeverityLevel.indeterminate,
      );
    });

    test('every severity level has a style', () {
      for (final level in SeverityLevel.values) {
        expect(SeverityStyle.of(level).label, isNotEmpty);
      }
    });
  });

  test('result screens contain no banned directive copy', () {
    const files = <String>[
      'lib/screens/results_screen.dart',
      'lib/widgets/compliance_footer.dart',
    ];
    for (final path in files) {
      final content = File(path).readAsStringSync().toLowerCase();
      for (final phrase in AdvisoryCopy.bannedPhrases) {
        expect(
          content.contains(phrase),
          isFalse,
          reason: '$path contains banned phrase "$phrase"',
        );
      }
    }
  });
}
