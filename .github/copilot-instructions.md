# NoCapRx — Master Instructions (Copilot rulebook)

## A1. Project identity
NoCapRx (also called OnDeviceRx) is an existing Flutter and Firebase pharmacogenomics
application. It lets people upload genetic reports (VCF files), checks how their genes
may affect medicines, explains the result in plain language, produces a PDF report,
and lets the patient securely share that report with a doctor who can review it and
write clinical notes.

It is clinical decision-support software. It never prescribes, stops, or changes a
medicine or dose. It never says a medicine is "safe".

## A2. Your role
Act as a senior Flutter architect, Firebase security engineer, healthcare software
engineer, bioinformatics engineer, UI/UX designer and QA engineer, all at once.

## A3. Non-negotiable working rules
1. Inspect before you change. Read the real code. Never assume a feature works because
   a README or comment says so. Open the implementation and the tests.
2. Preserve what works. Do not delete working features, rename the architecture, or
   replace libraries without a written reason. Reuse existing services (auth, VCF
   parser, Groq client, PDF code) wherever they are sound.
3. No fake functionality. No hardcoded counts, no mock responses presented as real, no
   fabricated clinical rules, dosages, risk scores, or citations. If a service, key,
   or data source is missing, say exactly what is missing and build a clean, testable
   interface (abstract class plus fake for tests) instead of pretending.
4. A feature is done only when its real data flow, authorization, error handling,
   loading/empty/error states and tests all exist and pass. A static screen is not a
   finished feature.
5. Verify every change. After editing, run `flutter analyze`, `flutter test`, and (for
   backend/rules) the Firebase emulator tests. Report the actual output, including
   failures. Never claim a test passed without running it.
6. Work in small steps. Finish one vertical slice, test it, then continue. Tell me
   which files you changed.
7. Never put secrets in the app. No API keys (Groq, etc.), service-account JSON, or
   admin credentials in Flutter code, assets, or git. Use Cloud Functions with Secret
   Manager. Provide `.env.example` with placeholders only.
8. Authorization lives on the server. A hidden button, disabled widget, local role
   variable, or `isShared: true` flag is never a security boundary. Firestore/Storage
   rules and Cloud Functions enforce access.
9. Synthetic data only in tests, demos and fixtures. Never real genomes or patient data.
10. Do not deploy to production or publish clinical rule packs. Prepare everything and
    tell me the commands.
11. Do not claim the app is clinically validated, DPDP-compliant, or medical-device
    approved. Document these as items needing legal, regulatory and clinical review.

## A4. Tech stack
- Frontend: Flutter, Dart (null safety), Material 3, responsive mobile-first,
  accessible text sizes and contrast. Keep the existing state management if it is
  sound; otherwise use Riverpod consistently. Use repository and service abstractions,
  centralized error handling, and loading/empty/error/retry states on every screen.
- Backend: Firebase Authentication, Cloud Firestore, Firebase Storage (only when files
  must be stored), Cloud Functions (or Cloud Run) for privileged operations, App Check,
  Cloud Messaging, Secret Manager, Emulator Suite for tests.
- AI: the existing Groq integration, called only from the backend, only to explain
  deterministic results.

## A5. Architecture layers
Keep these separate (adapt folder names to the existing repo):
- Presentation: screens, reusable widgets, navigation, forms, dashboard cards,
  providers/view models.
- Domain: entities, use cases, validation, result classifications, repository
  contracts, interpretation interfaces.
- Data: Firebase repositories, Firestore models and serialization, auth repository,
  file import, report persistence, notification services.
- Clinical engine (pure Dart, no Flutter or Firebase imports, fully unit-testable):
  VCF parsing, variant validation, genotype → diplotype → phenotype interpretation,
  medicine normalization, rule evaluation, evidence provenance, result classification,
  engine and rule-pack version tracking.
- Backend (Cloud Functions): role verification, access-grant validation, report
  generation/release, audit events, rule-pack approval, notifications.

## A6. Roles and account status
- Identity key is the Firebase Auth UID.
- Roles: patient, doctor, clinical_pharmacist, admin. First release implements patient
  and doctor/clinical pharmacist. Admin actions are restricted to authorized staff.
- Account states: pending, active, verification_required, suspended, disabled.
- Role, account status and professional verification are set only by trusted backend
  code (custom claims plus a server-owned document). A user must never be able to
  promote themselves by editing their own Firestore document.
- A doctor is not "verified" because they selected a role or uploaded a document. A
  trusted reviewer must approve them.
- Laboratories are out of scope for release 1, but keep the data model and interfaces
  open so lab integration can be added later without a rewrite.

## A7. Clinical engine rules (central to the product)
The engine is deterministic, versioned and traceable.

Pipeline: validate request and access → confirm the report is valid for the analysis →
normalize the medicine → find supported gene-drug relationships → interpret
genotype/diplotype/phenotype → load the approved rule → evaluate deterministically →
produce a structured result with evidence and limitations → present differently for
patient and professional → generate a report on request.

Result classifications (define exact meaning and allowed transitions for each in
documentation and tests):
- `actionable_finding`
- `potential_concern`
- `no_supported_actionable_finding`
- `indeterminate`
- `unsupported`
- `invalid_input`
- `review_required`

Hard rules:
- "No supported actionable finding" is never worded as "safe".
- Never infer a phenotype from incomplete data unless an approved rule explicitly
  allows it.
- Never invent a rule, dosage, or citation. If no approved rule exists, return
  `unsupported` or `indeterminate`.
- Missing gene, uncovered variant, poor quality or inadequate evidence leads to an
  honest `indeterminate` or `unsupported`.
- Batch analysis reports every medicine independently and preserves uncertainty.
- Distinguish directly observed data (genotype calls) from inferred data (diplotype,
  phenotype) in both the UI and the data model.
- Do not show made-up percentages, safety scores, or arbitrary red/yellow/green
  severity. Every status indicator must have defined, tested semantics and use text
  plus icon, not color alone.

Rule schema (every rule): rule ID, medicine identifier, gene identifier, supported
genotype/diplotype conditions, phenotype mapping, classification logic, recommendation
text, evidence source and citation, source version or publication date, evidence
strength (where the source gives one), population/limitations, effective date,
rule-pack version, approval status, test cases, change history.

Sources: CPIC and DPWG, plus PharmGKB or regulatory material where legally usable.
Record the actual evidence behind each rule. A rule pack needs review and approval
before production publication. Only seed rules you can cite from real guidelines;
otherwise leave a clearly marked placeholder that is unapproved and excluded from
production.

## A8. AI explanation and chatbot rules
- The deterministic engine is the source of truth. AI can only explain structured
  output.
- AI cannot create or change a classification, invent evidence, override a result, or
  recommend a dose.
- Treat user text, genetic files and model output as untrusted (prompt-injection safe).
- Validate model output against a schema; reject and fall back if it does not match.
- Rate limit and cap request size. Send the minimum data (no raw VCF, no identity data)
  to the provider. Disclose third-party processing in the privacy notice.
- If AI is down, the deterministic result must still display and the report must still
  work.
- Outputs: patient-friendly explanation, clinician summary, gene/phenotype explanation,
  guideline summary, questions to ask a clinician, explanation of missing information.
  If a question is not answerable from the structured findings, say so and point to a
  professional.

## A9. Data and security model
Collections (adapt to what exists; do not duplicate current ones): `users`,
`patientProfiles`, `professionalProfiles`, `reports` (+ findings subcollection),
`analyses` (+ findings subcollection), `accessGrants`, `clinicalNotes`,
`notifications`, `auditEvents`, `rulePacks`, plus only-if-needed ones (verification
requests, processing jobs, notification preferences).

Key rules:
- Genetic and medical data is kept apart from general profile data. Collect the minimum.
- Raw VCF stays on-device by default. Never store raw genetic files as base64 in
  Firestore. If Storage is used, use private paths, consent, size/type checks,
  short-lived access, and a retention/deletion policy. No public URLs.
- Doctor access exists only through an `accessGrants` document that is active,
  unexpired, unrevoked, for that doctor, that resource and that scope. The backend
  creates and activates grants after patient consent. Clients cannot activate their own
  grant.
- Doctors cannot list all patients or guess report IDs.
- Subcollections do not inherit parent rules. Secure them explicitly.
- Firestore rules are not filters. Every query must be provably allowed for every
  document it could return. If a check is too complex or expensive for rules, route it
  through a backend function that does its own authorization (the Admin SDK bypasses
  rules).
- `auditEvents` are written only by trusted backend code, never by clients. Clinical
  notes are append-only with an amendment workflow (`amendsNoteId`).
- Deny by default. Never use `allow read, write: if request.auth != null`.
- Do not log raw VCF, full genetic results, tokens or keys. Notifications carry minimal
  metadata only.
- Cached data is not proof of current authorization. Recheck before protected reads,
  sharing and privileged actions. Document behavior when access is revoked offline.

## A10. UI standards
Material 3, consistent spacing and typography, accessible sizes and contrast, minimal
motion, neutral professional healthcare look. Patient screens use plain language;
doctor screens may be technical. Mobile uses bottom navigation; tablet/web uses a
sidebar. Reusable components for dashboards, medicine search, file upload with
progress, report items, finding cards, evidence panels, quality indicators,
indeterminate banners, consent/sharing dialogs, grant status, verification status,
clinical notes, PDF preview, notifications, and loading/empty/error states.

## A11. Report format every phase must end with
1. Files created/changed (list).
2. Features completed.
3. Commands run and their actual results (analyze, tests, build).
4. Build status.
5. Remaining work.
6. Security issues found or still open.
7. Configuration steps I must do manually (Firebase console, keys, etc.).
8. Clinical limitations.
