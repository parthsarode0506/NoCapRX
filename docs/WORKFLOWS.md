# PharmaGuard (NoCapRX) — Production Workflows

## 2.1 Core Check Pipeline (all roles, offline)

1. **Input**: Prescription photo or typed drug name.
2. **On-device OCR** → drug resolver (brand → generic, fuzzy match, confidence). Low confidence: user picks from a shortlist.
3. **Load genetic profile**: VCF import (local) or stored derived calls.
4. **Star-allele caller** → diplotype → phenotype mapper.
5. **Rule evaluator** looks up `(gene, drug, phenotype)` in the active signed ruleset → tier, advisory, alternatives, dosing.
6. **Explainer**: bundled template text first; on-device Gemma rewrite if available; validated against the structured result, template fallback on mismatch.
7. **Result card** (gene, diplotype, phenotype, drug, source, evidence level, rule version, disclaimer) → "Save" → local record + audit event + sync outbox entry.
8. **Optional "Evidence discovery"** for drugs outside the ruleset: user toggle, sends drug name only, results labeled "unvalidated, not a guideline".

---

## 2.2 Patient (B2C) Workflow

1. Sign up (email/Google/phone) → create self + family profiles.
2. Import VCF or order a partner-lab test.
3. Scan prescription ("check before you take").
4. Plain-language result with "talk to your doctor" CTA.
5. Chatbot scoped to the saved result only.
6. PDF export.
7. Share with a verified clinician via consent (scope + expiry).
8. Consent center (view, revoke).
9. History (delete my data).
10. Medication reminders.

---

## 2.3 Doctor Workflow

1. Sign up → NMC/state council registration number + ID upload.
2. Tier: `pending` (sandbox patients only).
3. Cloud Function verification (register lookup where permitted, else manual review queue).
4. Claims set to `verified/full`.
5. Roster (search, create, link via consent QR/OTP).
6. Draft prescription → real-time risk flag → alternatives + genotype-adjusted dosing.
7. Auto clinical note → clinician confirms.
8. Export e-prescription PDF / FHIR payload with PGx rationale.
9. Optional time-limited second-opinion share.
10. Audit trail view.

---

## 2.4 Pharmacy Workflow

1. Org onboarding (business + drug license).
2. `org_admin` invites pharmacists (seats).
3. Pharmacist scans prescription.
4. Patient lookup by consent QR/OTP.
5. Flag check → substitution suggestions filtered by pharmacy stock (CSV upload / POS API).
6. Override requires reason code + text.
7. Audit → dispense log.

---

## 2.5 Diagnostic Lab Workflow

1. Org onboarding.
2. `lab_tech` creates order (consented patient).
3. Upload VCF (single or batch).
4. On-device or isolated batch parser.
5. Standardized PGx PDF (patient + clinician versions).
6. Publish to patient account, optional webhook to partner EMR.
7. Dashboard (turnaround, QC failures).

---

## 2.6 Admin

- Org approvals, seat management, role assignment (Function-only).
- Aggregated no-PII analytics.
- Ruleset release console: draft → clinical sign-off → sign → stage (5% via Remote Config) → full rollout → instant rollback.

---

## 2.7 Sync

- Writes go to local DB + outbox.
- `workmanager` flushes when online with exponential backoff and idempotency keys.
- Audit events: append-only.
- Patient records: last-writer-wins with server timestamp + version counter.
- Clinical-note edits: create new revisions.

---

## 2.8 Verification and Consent

- **Tiers**: `pending` (sandbox only) → `basic` → `full`. Re-verify periodically.
- **Consent doc** per grantee: `scope[]`, `active`, `expiresAt` (max 365 days).
- Revoke by setting `active=false`; the grantee's next read fails immediately.
