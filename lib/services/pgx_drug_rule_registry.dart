import '../rules_engine/cpic_rule_engine.dart';

class PgxDrugRule {
  final String drug;
  final String gene;
  final String guidelineSource;
  final String evidenceLevel;

  const PgxDrugRule({
    required this.drug,
    required this.gene,
    required this.guidelineSource,
    required this.evidenceLevel,
  });
}

/// Registry boundary for the validated on-device PGx catalogue.
class PgxDrugRuleRegistry {
  static List<PgxDrugRule> get rules => CpicRuleEngine.drugToGeneMap.entries
      .map(
        (entry) => PgxDrugRule(
          drug: entry.key,
          gene: entry.value,
          guidelineSource: 'Validated local CPIC rule engine',
          evidenceLevel: 'CPIC local rule',
        ),
      )
      .toList(growable: false);
}
