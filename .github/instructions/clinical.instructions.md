---
applyTo: "lib/rules_engine/**,lib/services/medicine_analysis_service.dart,lib/services/universal_medicine_safety_engine.dart,lib/services/personalized_side_effect_engine.dart"
---
- This code is the clinical decision engine. It must be deterministic, pure, side-effect free.
- NO LLM calls, NO network, NO randomness, NO DateTime.now() inside decision logic (inject a Clock).
- All clinical content comes from a rule pack (JSON) validated against the schema in docs/RULEPACK_SCHEMA.md. Never hardcode gene/drug/phenotype/recommendation text.
- Every result carries: ruleSetVersion, cpicGuidelineRef, evidenceLevel, inputHash, and a human-readable provenance trace.
- Unknown or uncallable input returns Severity.indeterminate with a reason. Never guess.
- 100% branch coverage target for phenotype assignment and recommendation lookup.
