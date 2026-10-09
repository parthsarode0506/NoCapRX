# Audit report

## Summary

This repository contains several privacy and safety issues that are incompatible with the required offline-first guidance. The highest-risk items are direct cloud AI calls from the client, committed secrets, and cloud OCR being enabled by default.

## A. Data leaving the device

### Client-side cloud AI and OCR
- [lib/features/chat/chat_service.dart](../lib/features/chat/chat_service.dart): direct fallback to Groq from the client when the local medicine record is missing or when a cloud response is available.
- [lib/features/chat/cloud_fallback_service.dart](../lib/features/chat/cloud_fallback_service.dart): sends questions and patient context to Groq over the public internet using a bearer token embedded in the app environment.
- [lib/services/groq_ai_service.dart](../lib/services/groq_ai_service.dart): performs cloud medical explanation and online drug lookup calls using a direct Groq API key.
- [lib/services/prescription_ocr_service.dart](../lib/services/prescription_ocr_service.dart): sends prescription images to OpenRouter by default when a key is present.
- [lib/services/online_evidence_service.dart](../lib/services/online_evidence_service.dart): enriches medicine lookups with external AI and online service data; the AI branch is not gated behind explicit consent.
- [lib/services/firebase_service.dart](../lib/services/firebase_service.dart): Firestore writes are network-bound and should be treated as cloud data egress. Only derived calls should be synced with consent.

### What is sent
- Question text, drug name, and local safety facts.
- OCR image bytes or prescription text.
- Derived clinical results, medicine name, gene, phenotype, and risk summaries.
- If the app is not corrected, these may include patient-linked data and de-identified care context without a clear consent gate.

## B. Hardcoded API keys or secrets

The repository contained committed secrets in the local development environment and the app bundle:
- [.env](../.env): Groq and OpenRouter keys were committed.
- Firebase Web API key and app settings are loaded from the ignored local `.env` at runtime. Client-side Firebase API keys are public identifiers, not secrets; restrict their API and application usage in Google Cloud/Firebase settings.
- [build/**](../build): generated assets also contained the same environment secrets.

These are not acceptable for production or even a shared developer workspace.

## C. Clinical rules hardcoded in Dart

The deterministic domain logic is still embedded in Dart and is not yet fully controlled by a signed ruleset file:
- [lib/rules_engine/cpic_rule_engine.dart](../lib/rules_engine/cpic_rule_engine.dart)
- [lib/services/personalized_side_effect_engine.dart](../lib/services/personalized_side_effect_engine.dart)
- [lib/services/universal_medicine_safety_engine.dart](../lib/services/universal_medicine_safety_engine.dart)
- [lib/services/medicine_analysis_service.dart](../lib/services/medicine_analysis_service.dart)

These should be migrated behind a signed ruleset schema and versioned registry.

## D. Unencrypted Hive storage

There is no evidence of a Keystore-backed encrypted Hive layer yet. The project still uses Hive as a local persistence layer and requires a one-time migration to encrypted storage.
- [pubspec.yaml](../pubspec.yaml): `hive` and `hive_flutter` are enabled.
- The app must move to `HiveAesCipher` with a key from `flutter_secure_storage` before persisting patient-derived records.

## E. Directive or prescriptive wording in UI or AI prompts

The app contains wording that is too direct for a CDS-style clinical advisory tool:
- [lib/features/chat/chat_service.dart](../lib/features/chat/chat_service.dart): default Groq failure message explicitly tells the user to inspect environment configuration instead of staying local-first.
- [lib/services/groq_ai_service.dart](../lib/services/groq_ai_service.dart): direct answer prompts are not strictly bounded to local evidence and may drift into medical advice without a deterministic result branch.
- Jurisdictional or advisory wording should be checked and replaced with the required language set in the pack: “Consider…”, “Guideline suggests…”, and “Discuss with your clinician.”

## F. Missing tests

The repo does not yet include the required privacy and rules coverage for the pack:
- no consent-gated cloud AI test;
- no Firestore rules unit test suite for patient and verification paths;
- no golden tests per gene-drug phenotype;
- no offline sync conflict test;
- no recovery test for ruleset rollback.

## Prioritized fix list

### P0 (must fix first)
1. Remove committed secrets and move any cloud AI pipeline behind a secure backend proxy with App Check and rate limits.
2. Disable cloud AI/OCR by default; require explicit per-use consent and de-identified payloads only.
3. Encrypt Hive and add a versioned migration.
4. Replace the Groq/OpenRouter client path with a local-first fallback and a consent sheet.
5. Add the redacting logger and stop sending raw patient details to logs.

### P1
1. Introduce a signed, versioned ruleset loader with rollback support.
2. Add the deterministic engine split into pure Dart modules under lib/engine.
3. Add consent and audit event structures for patient data sharing.

### P2
1. Add Firestore rules tests and role verification flow.
2. Add offline sync and workmanager backoff coverage.
3. Add golden tests and rule-version badges.

## Current status

The repository has been updated to the local-first pattern for the immediate security fix: cloud AI is gated behind explicit consent, the default path stays on-device, and the committed secret values have been removed from the project root local environment file.
