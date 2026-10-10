# Repository audit

Audit scope: current Flutter app, Firebase rules and configuration, clinical
data/engine, persistence, and available tests. This audit records what was
verified in source and local checks; it is not a clinical validation or
production-readiness claim.

## Current baseline

- Flutter 3.47.2 and Dart 3.13.2 are installed. The package declares Dart
  `^3.12.2`, Riverpod, Firebase Auth/Firestore, ML Kit OCR, Gemma, Hive,
  SharedPreferences, PDF, and printing.
- The app starts in `lib/main.dart`; Firebase and dotenv initialize before the
  app. Riverpod providers hold session/profile and selected VCF/report state.
  Screens navigate using `MaterialPageRoute`; there is no `go_router`.
- Public email/password sign-up creates patient accounts only. Organization
  accounts are provisioned separately by a trusted organization administrator;
  there is no in-app professional credential verification or reviewer flow.
- VCF upload is parsed from in-memory bytes with a 5 MB UI limit. There is no
  Firebase Storage upload in that flow. A VCF parser and deterministic
  drug/gene evaluator are present, alongside local medicine lookup and PDF
  generation.
- Local reports, patient data, and discovered medicine records use
  SharedPreferences. Hive is declared as a dependency but an encrypted Hive
  store is not wired into these flows.
- `firestore.rules` is default-deny and defines owner-scoped users, reports,
  patients, consents, checks, notes, lab orders, rule sets, and audit events.
  The client currently uses `/users/{uid}` and nested `/reports`.
- Storage rules permit user-owned PDF reports. The raw VCF upload grant was
  removed in this audit; unmatched
  Storage paths are denied.
- Five Firestore/Storage Emulator tests pass using a demo project ID, covering
  profile owner writes, protected profile fields, cross-user/anonymous writes,
  and verified lab-tech raw VCF upload denial. Profile photo reads were
  restricted to owners/platform admins; emulator coverage verifies owner access
  and denies other/anonymous readers. Broader report, consent, and clinical-note
  scenarios still need tests.
- `firebase.json` references Cloud Functions. Organization patient workflow
  callables build locally; production deployment is not verified.

## Findings

### Implemented and locally verified

- The Android app and Web app use dotenv-backed Firebase options. Local
  `android/app/google-services.json`, `.env`, and `lib/firebase_options.dart`
  are git-ignored. Android and Web options identify the same Firebase project.
- Profile writes in `FirebaseService.saveUserProfile` now write only
  `displayName` and a server timestamp for new profiles. Existing profiles are
  updated narrowly so fields such as `phone` and `locale` are preserved.
  Profile reads derive UID from the document path and email from Firebase Auth,
  matching the current `/users/{uid}` rules allowlist.
- New PGx reports are saved locally only. Automatic cloud upload is disabled
  until an explicit derived-genetic-data sync consent flow and bounded cloud
  schema are implemented; report serialization currently includes patient
  identifiers, filenames, detailed findings, and explanations.
- VCF bytes are held in memory for the active session and are not sent to
  Storage by the upload UI.
- Cloud AI/OCR paths expose opt-in flags which default to false; the local
  medicine/PGx flow exists independently.
- `flutter analyze` completes with no issues.
- `flutter build web --debug` succeeds, with WebAssembly dry-run warnings in
  Gemma MediaPipe and TTS dependencies.
- `:app:compileFlutterBuildDebug` succeeded. A full Android APK build did not
  complete reliably in this OneDrive workspace: generated build outputs are
  cloud-file/reparse entries, and Gradle later failed to find `R.jar`.

### Incomplete or unverified

- The profile sync fix has not been exercised against the deployed Firestore
  rules. The previous browser run logged `permission-denied`; Firebase CLI
  deployment preflight failed because the CLI is not authenticated.
- Firebase emulator tests cover profile access, deny raw VCF
  Storage writes, and restrict profile-photo reads. Production rule deployment
  and direct behavior against the live project remain unverified.
- Firebase Auth initialization is configured, but email/password provider
  enablement, Web API-key restrictions, account recovery, consent capture, and
  deployed Firestore behavior depend on Firebase Console settings not checked
  in this audit.
- An Android debug build was installed and launched on device
  `10BFAX1BTP0010U`. Device logs show Firebase App Check API is disabled in the
  project, so protected callable operations are not yet verified live.

### Release blockers and security gaps

1. **Clinical content provenance and correctness are not established.** The
   evaluator and VCF phenotype logic contain hardcoded calls/rules, while
   `assets/data/cpic_rules.json` also contains clinical claims. Rule-pack
   signature verification, ingestion provenance, independent clinical review,
   and complete input/engine traceability are not demonstrated. Do not use the
   current catalogue for care until qualified clinical review and source
   verification are complete.
2. **Role-based clinical workflows are incomplete.** Organization patient
   search/registration/details callables are implemented locally, but backend
   deployment and authorization tests for the callables are outstanding.
   Patient-authorized sharing, doctor review notes, and report sync remain
   incomplete. UI selections must not be treated as authorization.
3. **Privileged backend is incomplete.** Grant lifecycle, deletion/erasure,
   notifications, and broader trusted audit workflows are not implemented.
4. **Raw VCF upload was allowed by Storage rules.** The grant has been removed
   locally and an emulator test denies it, preserving the device-only genome
   boundary. Production Storage rules are not verified.
5. **Local persistence is not encrypted.** SharedPreferences stores reports,
   patient profile data, and medicine-discovery records. No secure key or
   encrypted local database migration is present.
6. **Cloud provider credentials are client-side.** Groq and OpenRouter calls
   originate in the Flutter client when explicitly enabled; a bundled API key
   is extractable and is not a trusted backend secret. A Groq key was exposed
   in shared development text and should be revoked/rotated. Do not reuse it.
7. **Error handling and privacy need hardening.** Several services catch
   broad exceptions and return fallbacks; logs and user-facing messages need a
   systematic PHI/credential review. Profile writes previously hid permission
   failures; that behavior should be made explicit.
8. **Storage profile images** are now owner/platform-admin readable in the
   local rules; deployed rule behavior remains unverified.
9. **Consent, retention, erasure, audit visibility, App Check, and account
   suspension enforcement are incomplete or unverified.**
10. **Localization, accessibility, dark mode, and 2x text-scale coverage need
    broader verification.** Current UI contains many literal English strings.

## Architecture and files to preserve

- Keep the Flutter/Riverpod app entry and existing feature screens.
- Preserve `lib/parser/vcf_parser.dart`, the deterministic
  `lib/rules_engine/cpic_rule_engine.dart`, local drug repository, and local
  report/PDF services while clinical content and decision paths are validated.
- Preserve Firestore default-deny rules and narrow ownership checks. Resolve
  client/schema mismatches by changing the client or schema deliberately; do
  not broaden permissions to silence errors.
- Keep VCF parsing on-device and cloud AI/OCR disabled unless the user explicitly
  opts in through an informed, per-use consent flow.

## Prioritized implementation plan

1. **Stabilize and test:** fix test harness failures, add Firestore and Storage
   Emulator Suite tests, verify the profile write against deployed rules, and
   make Firebase sync errors observable without exposing PHI.
2. **Security/data boundaries:** validate the local rule set, restrict profile
   Storage reads, add consent/grant tests, encrypt local records, and remove
   direct client cloud credentials in favor of a consent-gated trusted proxy.
3. **Clinical provenance:** define and validate a rule-pack schema, create a
   reproducible CPIC ingestion pipeline, verify signatures/version retention,
   and obtain clinical review before activating rule data.
4. **Patient workflow:** complete consent, report lifecycle, local/offline
   history, deletion/export, and authorized sharing.
5. **Organization workflow:** securely provision organization memberships,
   implement authorized patient/report queries, immutable review notes, and
   patient-visible access logs. Professional credential verification is
   intentionally outside the app scope.
6. **Release verification:** run Flutter tests/analyze, Firebase Emulator Suite
   tests, Android and Web builds, accessibility/localization checks, and a
   security/regulatory review. Do not call the app production-ready before
   clinical validation and regulatory review.

## Current disposition

This is an early functional prototype, not a production-ready clinical system.
The local profile-write mismatch was corrected and the Storage VCF upload grant
was removed. Rules deployment remains blocked until an authorized Firebase CLI
session is available; clinical interpretation, security, privacy, and regulatory
gaps above remain release blockers.

## Follow-up verification

This section supersedes the earlier baseline test counts and Storage-test notes.

- Full Flutter suite: **61 passed** after removing professional-verification
  screens and signup options.
- Firebase Emulator Suite: **9 rules tests passed**, including no raw VCF or
  professional registration document uploads. Run them with:
  `firebase emulators:exec --only firestore,storage --project demo-nocaprx "npm.cmd --prefix test/rules test"`.
- `npm audit --prefix test/rules`: **0 vulnerabilities** after pinning a
  compatible patched `@grpc/grpc-js` override.
- `flutter analyze`: no issues.
- `flutter build web --debug`: succeeds; third-party Gemma/TTS WebAssembly
  dry-run warnings remain.
- `npm --prefix functions run build` succeeds and `npm audit --prefix functions`
  reports **0 vulnerabilities**.
- Android device `10BFAX1BTP0010U` is connected and the debug build launched.
  Device logs report that the Firebase App Check API is disabled for the project.
- Firebase CLI production deployment remains blocked by missing CLI
  authentication. No production rules were deployed.

## Organization workspace follow-up

- Organization users with active server-provisioned membership are
  routed to an organization workspace. Search, registration, organization-name
  lookup, and patient details are App-Check-protected callable Functions.
- Search and detail access re-check active membership in the same Firestore
  transaction as their server-side audit record. Registration is retry-safe via
  an idempotency key, rejects exact normalized-name/birth-year duplicates, and
  writes its patient, organization link, idempotency record, and audit entry in
  one transaction.
- Added `firestore.indexes.json` for the compound duplicate lookup. Deploying
  Functions and indexes remains a project-owner action; neither was deployed.
- The current local `firestore.rules` schema still uses `/orgs` and
  `/auditEvents`, while these callables use `/organizations` and `/auditLogs`.
  Admin SDK calls bypass Firestore client rules, but client access should remain
  denied until the project owner manually publishes a reviewed ruleset. A
  proposed ruleset is supplied in the work-session response; this change set
  did not edit or deploy Firestore Rules.
- No organization provisioning flow currently assigns the `orgId` custom claim
  and active `organizations/{orgId}/members/{uid}` record. A trusted
  organization administrator must provision both before a user can use
  these organization callables.
- The organization workspace shows actual persisted status values and clearly
  states that cloud VCF upload/analysis/reporting are unavailable. Raw VCFs
  remain on-device. Patient-authorized consent/linking, report sharing, clinical
  notes, and prescription review are not implemented.
- Latest checks: Flutter tests **61 passed**, rules emulator tests **9 passed**,
  `flutter analyze` clean, Functions TypeScript build succeeded, and Web debug
  build succeeded with dependency WebAssembly dry-run warnings. The Android
  debug build installed/launched on `10BFAX1BTP0010U`; runtime logs indicate
  Firebase App Check API is disabled in the Firebase project, preventing a
  verified live callable test.

## Current follow-up implementation

- Signup stores a Patient or Organization workspace preference. Selecting
  Organization routes to its dashboard, but does not grant patient-data access.
- Organization access requires server-provisioned doctor/pharmacist role and
  organization ID claims plus an active organization membership. The backend
  checks membership on every organization callable. The app has no professional
  credential collection, verification request, or reviewer queue.
- Organization patient callables compile locally but are not deployed. Firebase
  CLI authentication is unavailable in this environment.
- Google popup onboarding is implemented for Web; Android Google OAuth still
  needs native sign-in integration and a Firebase Android OAuth client.
- The local Firestore Rules now allow a self-owned `accountType` workspace
  preference of `patient` or `organization`; it is not used for authorization.
  Publish the updated user-profile rules manually in Firebase Console. Legacy
  `/verifications` and `/providers` blocks remain in the local rules file.
- Integrated report grants/revocation, cloud report synchronization, doctor
  patient dashboard, clinical notes/amendments, and patient-visible access logs
  are still not implemented. Report content remains local and is not made
  available to organization users simply by selecting that workspace at login.
