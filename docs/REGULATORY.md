# REGULATORY.md

CDSCO/MD/GD/MDSW/01/2026 — **confirm with a regulatory consultant**.

## Intended-use statement
NoCapRx is a pharmacogenomic **clinical decision-support** tool. It is intended to
assist licensed clinicians and to inform patients. It does not diagnose, prescribe,
or replace clinical judgment. Patient mode is informational; clinician mode is
advisory decision support with a mandatory human-in-the-loop acknowledgment.

## Required controls
- Keep the human-in-the-loop gate and the traceability matrix
  (requirement → test → release).
- Maintain lifecycle documentation: versioning, change control, risk analysis
  (ISO 14971 style), cybersecurity, post-market monitoring plan.
- Keep a clinical-reviewer sign-off on every rule-pack change.
- State limitations explicitly in-app and in reports (adult guidelines, uncallable
  genes, no replacement for clinical judgment).

## Copy discipline
Advisory language only. Banned directive phrases: "you must", "do not take",
"stop taking", "will cause", "guaranteed", "safe to take", "cure", "diagnose",
"contraindicated" (as an instruction). Enforced by `AdvisoryCopy` in
`lib/theme/severity_style.dart` and a CI banned-phrase check.
