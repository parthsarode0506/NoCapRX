# SECURITY.md

## Device
- SQLCipher DB, key in Keystore/Keychain; biometric lock; auto-lock; FLAG_SECURE on
  PHI screens; no PHI in clipboard, notifications, logs, screenshots, or crash reports.
- Root/jailbreak warning; Play Integrity via App Check; release builds only accept
  signed rule packs.
- Redacting logger strips PHI patterns before any log line is written
  (`lib/services/redacting_logger.dart`).

## Backend
- Default-deny rules, claim-based roles, append-only clinical data, Functions-only
  audit logs, App Check enforced everywhere, zod validation, rate limiting on
  callables (per uid), idempotency keys, secrets in Secret Manager, least-privilege
  service accounts.

## Privacy (DPDP Act 2023 mindset — confirm specifics with counsel)
- Notice and granular, revocable consent; purpose limitation; data minimization
  (alias, birth year); guardian consent for minors; patient access log; export and
  erasure; breach-response runbook; named grievance contact; data residency in India
  (Mumbai/Delhi); retention policy per collection.

## Known gaps (from docs/AUDIT.md, P0)
1. Remove committed secrets; move any cloud AI pipeline behind a secure backend proxy.
2. Disable cloud AI/OCR by default; require explicit per-use consent, de-identified payloads only.
3. Encrypt local Hive storage and add a versioned migration.
4. Replace the Groq/OpenRouter client path with a local-first fallback and a consent sheet.
5. Redacting logger on every log site.

## OWASP MASVS L1 checklist
Track coverage per release; the reference matrix lives with the release artifact.
