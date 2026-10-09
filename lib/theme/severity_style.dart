import 'package:flutter/material.dart';

/// NoCapRx canonical severity model — single source of truth.
///
/// Matches the build pack (`.github/copilot-instructions.md` §5):
/// `info | consider | caution | high_risk | testing_recommended | indeterminate`.
///
/// Everything user-facing about a risk flag (label, guidance, colour, icon)
/// is derived from this enum, so the whole UI stays consistent and the
/// advisory-only copy deck is enforced in one place.
enum SeverityLevel {
  info,
  consider,
  caution,
  highRisk,
  testingRecommended,
  indeterminate,
}

/// Allowed advisory verbs for any copy shown to a patient or clinician.
/// Directive verbs ("stop", "do not take", "you must") are banned by the pack.
abstract class AdvisoryCopy {
  AdvisoryCopy._();

  static const String decisionSupportOnly =
      'Decision support only — confirm with your prescriber/pharmacist.';

  /// Verbs allowed in generated or static copy.
  static const List<String> allowedVerbs = <String>[
    'consider',
    'may',
    'suggests',
    'flag',
    'review',
    'discuss',
    'confirm',
  ];

  /// Phrases banned from any generated or static copy (CI enforces this).
  static const List<String> bannedPhrases = <String>[
    'you must',
    'do not take',
    'stop taking',
    'will cause',
    'guaranteed',
    'safe to take',
    'cure',
    'diagnose',
  ];

  /// Returns the banned phrases found in [text] (case-insensitive).
  static List<String> findings(String text) {
    final lower = text.toLowerCase();
    return bannedPhrases.where(lower.contains).toList(growable: false);
  }

  static bool isClean(String text) => findings(text).isEmpty;
}

/// Visual + copy tokens for a [SeverityLevel].
class SeverityStyle {
  final SeverityLevel level;
  final String label;
  final String guidance;
  final Color color;
  final Color background;
  final IconData icon;

  const SeverityStyle({
    required this.level,
    required this.label,
    required this.guidance,
    required this.color,
    required this.background,
    required this.icon,
  });

  static const Map<SeverityLevel, SeverityStyle>
  _styles = <SeverityLevel, SeverityStyle>{
    SeverityLevel.info: SeverityStyle(
      level: SeverityLevel.info,
      label: 'No action suggested',
      guidance:
          'No actionable pharmacogenomic finding was identified. Continue standard care.',
      color: Color(0xFF059669),
      background: Color(0xFFD1FAE5),
      icon: Icons.check_circle,
    ),
    SeverityLevel.consider: SeverityStyle(
      level: SeverityLevel.consider,
      label: 'Consider adjustment',
      guidance:
          'The guideline suggests reviewing the dose or the choice of medicine with the prescriber.',
      color: Color(0xFFD97706),
      background: Color(0xFFFEF3C7),
      icon: Icons.tune,
    ),
    SeverityLevel.caution: SeverityStyle(
      level: SeverityLevel.caution,
      label: 'Use with caution',
      guidance:
          'Extra monitoring may be appropriate. Discuss this result with the prescriber or pharmacist.',
      color: Color(0xFFEA580C),
      background: Color(0xFFFFEDD5),
      icon: Icons.warning_amber_rounded,
    ),
    SeverityLevel.highRisk: SeverityStyle(
      level: SeverityLevel.highRisk,
      label: 'High-risk finding',
      guidance:
          'A factor associated with increased medicine risk was identified. Review this with a qualified clinician before changing anything.',
      color: Color(0xFFDC2626),
      background: Color(0xFFFEE2E2),
      icon: Icons.dangerous,
    ),
    SeverityLevel.testingRecommended: SeverityStyle(
      level: SeverityLevel.testingRecommended,
      label: 'Testing suggested',
      guidance:
          'The guideline suggests confirmatory testing or a lab-confirmed genotype before acting on this result.',
      color: Color(0xFF2563EB),
      background: Color(0xFFDBEAFE),
      icon: Icons.science_outlined,
    ),
    SeverityLevel.indeterminate: SeverityStyle(
      level: SeverityLevel.indeterminate,
      label: 'Unknown — not enough information',
      guidance:
          'There is not enough verified information to classify this medicine. Confirm with your prescriber or pharmacist.',
      color: Color(0xFF4B5563),
      background: Color(0xFFF3F4F6),
      icon: Icons.help_outline,
    ),
  };

  static SeverityStyle of(SeverityLevel level) => _styles[level]!;

  /// Maps the legacy risk labels still produced by the on-device engine to the
  /// canonical severity model. Keeps the engine untouched while the UI speaks
  /// the pack's severity language.
  static SeverityLevel levelFromRiskLabel(String riskLabel) {
    switch (riskLabel.trim()) {
      case 'Safe':
      case 'No major risk identified':
      case 'NO_MAJOR_RISK_IDENTIFIED':
        return SeverityLevel.info;
      case 'Adjust Dosage':
      case 'Use with caution':
        return SeverityLevel.consider;
      case 'Additional medical review required':
        return SeverityLevel.caution;
      case 'Toxic':
      case 'Ineffective':
      case 'High-risk finding':
      case 'CONTRAINDICATED':
      case 'Contraindication identified':
      case 'DRUG_INTERACTION_DETECTED':
        return SeverityLevel.highRisk;
      case 'Testing recommended':
      case 'testing_recommended':
        return SeverityLevel.testingRecommended;
      default:
        return SeverityLevel.indeterminate;
    }
  }

  static SeverityStyle fromRiskLabel(String riskLabel) =>
      of(levelFromRiskLabel(riskLabel));
}
