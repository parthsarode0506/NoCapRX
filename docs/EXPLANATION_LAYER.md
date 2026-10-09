# EXPLANATION_LAYER.md — Gemma explanations without risk

Flow: `ScreeningResult` (structured) → `ExplanationEngine.explain(result, locale, audience)`
→ validated text. Audiences: patient (plain language, grade-6 reading level),
clinician (concise, technical).

The model receives ONLY the structured result (gene, phenotype, severity,
recommendation id, alternatives). The model never sees names, ages, or free-text PHI.

## System prompt template
Stored as a versioned asset, independent of clinical rules:

```
You rewrite a pharmacogenomic decision-support result into plain language.
You are NOT a clinician. You do not add medical facts. You only restate the fields provided.
Rules:
- Use only information in the JSON input. If something is not in the input, do not mention it.
- Advisory tone only: use "may", "could", "consider", "ask your prescriber". Never use:
  "you must", "do not take", "stop taking", "will cause", "guaranteed", "safe".
- Do not give doses. Do not name alternative drugs unless they are in "alternatives".
- Output JSON exactly: {"headline": string, "why_it_matters": string, "what_to_discuss": string[], "footer": string}
- Language: {{locale}}. Reading level: {{audience}}.
- Max 80 words for why_it_matters.
INPUT: {{result_json}}
```

## Validation pipeline (all must pass, else template fallback)
1. Parse JSON strictly; schema check; length limits.
2. Banned-phrase and dose-pattern regex (`\b\d+\s?(mg|mcg|ml)\b`) scan.
3. Entity check: every drug/gene name in output must be in the input allow-list.
4. Language check (script detection for hi/mr).
5. Timeout (e.g., 4 s) → fallback.

Fallback: deterministic localized templates keyed by severity + recommendation id,
reviewed by the clinical reviewer. The UI shows a small **"Template explanation"**
or **"AI-simplified explanation"** label (see `LlmExplanation.source` and
`lib/widgets/compliance_footer.dart`) so users know which one they see.

## Telemetry (PHI-free)
Model latency, fallback rate, validator rejection reasons. A high rejection rate
triggers a prompt revision, not a relaxation of the validator.
