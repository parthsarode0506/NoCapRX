# NoCapRx — Master Instructions for GitHub Copilot

## 1. What we are building
NoCapRx is an offline-first pharmacogenomics (PGx) decision-support platform. It turns a patient's genetic profile (VCF file or lab-reported diplotypes) plus a prescription (typed, or photographed and read by OCR) into a clear, guideline-cited, advisory risk check against CPIC gene–drug guidelines — fully on-device, even with no internet.

Three audiences, one core engine:
1. B2C — patients and families: scan a prescription, get a plain-language explanation in English/Hindi/Marathi, keep a "PGx passport", share it with their doctor via a time-limited QR grant.
2. B2B — pharmacies, diagnostic labs, hospitals: dispensing-time safety checks, substitution suggestions aware of stock, bulk lab report generation, org admin console.
3. Clinicians — doctors: check a drug against the patient's genotype before prescribing, see guideline-based alternatives, document the decision (accept / override with reason), export a clinical note.

Origin: this evolves our iQOO Hackathon 2026 app (OnDeviceRx: Flutter, OCR, VCF parsing, Snapdragon NPU, on-device Gemma). Reuse that work where possible.

## 2. Non-negotiable principles
1. **The LLM never makes clinical decisions.** The deterministic rule engine (`lib/rules_engine`, `lib/services/*engine*`) decides. Gemma only rewrites an already-decided structured result into plain language, under schema + banned-phrase validation, with a template fallback.
2. **Advisory, never directive.** The product is clinical decision SUPPORT. Copy uses "consider", "may", "guideline suggests", "review with the prescriber". Never "stop", "do not take", "you must", "contraindicated" as an instruction to patients. Final decision always belongs to a licensed clinician. Aligned to CDSCO's Medical Device Software guidance CDSCO/MD/GD/MDSW/01/2026; confirm with a regulatory consultant.
3. **Human-in-the-loop gate.** For doctor and pharmacist flows a flag does not become part of the record until a verified clinician explicitly acknowledges it (accepted / overridden-with-reason / alternative-chosen / deferred). Stored as an immutable acknowledgment.
4. **Raw genomes never leave the device.** VCF files are parsed on-device. Only derived results (gene, diplotype, phenotype) may sync, and only with explicit consent. No VCF upload path exists in Storage rules.
5. **Never invent clinical content.** Alleles, diplotype→phenotype tables, activity scores, recommendations, and evidence levels are ingested by script from CPIC (api.cpicpgx.org and published tables) into a versioned, signed rule pack. If asked to write clinical text from memory, refuse and generate the ingestion script instead.
6. **Fail safe.** Missing data, uncallable star alleles (e.g., CYP2D6 copy-number variation from a plain VCF), or unsupported drugs return `Severity.indeterminate` with a reason and a "get lab-confirmed genotype" suggestion. Never silently return "safe".
7. **Traceability.** Every screening stores: ruleSetVersion, cpicGuidelineRef, evidenceLevel, inputHash (SHA-256 of normalized input), appVersion, createdBy, createdAt.
8. **Privacy by design (DPDP Act 2023 mindset).** Data minimization, purpose limitation, explicit granular consent, revocable access grants, patient-visible access log, erasure on request, guardian consent for minors. No PHI in logs, analytics, crash reports, notifications, or screenshots of PHI screens.
9. **Least privilege.** Firestore/Storage rules are default-deny. Roles come from verified custom claims, never from client-writable fields.
10. **Production quality.** Typed, tested, linted, documented, observable, accessible, localized. No TODO-driven demos, no hardcoded secrets, no mock data outside `tools/synth_*` and demo mode.

## 3. Tech stack (do not substitute without asking)
- Client: Flutter (stable), Dart 3. Mobile app (Android first, iOS compatible) and Flutter Web console.
- State/DI: Riverpod. Navigation: go_router with role guards. Models: freezed + json_serializable (this repo currently uses hand-written `fromJson`/`toJson`; keep them consistent and immutable).
- Local data: encrypted local store (target: Drift on SQLCipher; key in flutter_secure_storage, biometric app lock via local_auth). Current repo uses Hive — migrate behind the same repository interfaces.
- OCR: `google_mlkit_text_recognition` (on-device) + a prescription parser with drug-name fuzzy matching against a local brand→generic dictionary.
- On-device LLM: Gemma via MediaPipe LLM Inference / `flutter_gemma` behind an `ExplanationEngine` interface; NPU/GPU delegates with automatic CPU fallback. Must degrade gracefully to templates.
- Backend: Firebase — Auth (email/phone + custom claims), Firestore (asia-south1/2), Storage, Cloud Functions v2 (TypeScript), App Check, FCM, Remote Config, Crashlytics (PHI-scrubbed), Analytics (no PHI, consented).
- Crypto: `cryptography` package for Ed25519 signature verification of rule packs and SHA-256 hashing.
- PDF: `pdf` + `printing`. Interop: FHIR R4 export.
- i18n: flutter_localizations + ARB (en, hi, mr).
- Testing: flutter_test, mocktail, integration_test, golden tests, Firebase Emulator Suite, rules-unit-testing.
- CI: GitHub Actions — analyze, test, rules tests, functions tests, build, secret scan, banned-phrase check.

## 4. Architecture rules
- Layers per feature: `presentation` → `domain` → `data`.
- Pure clinical engine should depend on nothing but `meta`, `collection`, `crypto` (no Flutter, no Firebase, no network). Target package: `packages/nocaprx_core`; in this repo the equivalent lives under `lib/rules_engine` + pure services.
- Offline-first: the local DB is the source of truth for the UI. A `SyncEngine` pushes an outbox to Firestore when online (exponential backoff, idempotency keys).
- Rule packs are data, hot-updatable (OTA) only after SHA-256 + Ed25519 verification. Keep the last 3 verified packs. Every screening records which pack produced it.
- Roles: patient, doctor, pharmacist, lab_tech, org_admin, clinical_reviewer, platform_admin. Role + verified + orgId come from Firebase custom claims. UI hides what the role cannot do, but Firestore rules are the real enforcement.
- Error handling: sealed `Result<T, Failure>`; no swallowed exceptions; user-facing messages localized and non-technical; technical detail only in PHI-scrubbed logs.

## 5. Severity model (single source of truth)
`info` | `consider` | `caution` | `high_risk` | `testing_recommended` | `indeterminate`.

Implemented in `lib/theme/severity_style.dart` (`SeverityLevel`, `SeverityStyle`, `AdvisoryCopy`). The legacy labels produced by the engine map onto this model — do not invent new labels in widgets.

Copy deck rules:
- Allowed verbs: consider, may, suggests, flag, review, discuss, confirm.
- Banned phrases in any generated or static copy: "you must", "do not take", "stop taking", "will cause", "guaranteed", "safe to take", "cure", "diagnose", "contraindicated" (as an instruction).
- Every screen showing a result also shows: CPIC reference, rule-set version, "Decision support only — confirm with your prescriber/pharmacist", and the date of the rule snapshot (see `lib/widgets/compliance_footer.dart`).
- A test greps ARB files and templates for banned phrases and fails the build on a match.

## 6. Definition of Done (every task)
- `dart format`, `flutter analyze` (zero warnings), unit/widget tests added, rules tests updated if data access changed.
- No PHI in logs. No hardcoded strings. Works offline. Works at text scale 2.0. Works in dark mode.
- Docs updated (`docs/*.md`) and, for clinical logic changes, a CHANGELOG entry referencing the CPIC source.

## 7. How to work
- Plan first: before coding any task, output a short plan listing files you will create/change; then implement.
- Work in small vertical slices. After each slice run analyze + tests and report results.
- If a requirement is ambiguous or touches clinical content or security, ask instead of guessing.
- Prefer the simplest design that satisfies the Definition of Done.
