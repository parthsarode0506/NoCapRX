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

1. Sign up as Patient (email, or Google on Web) → choose a preferred language and acknowledge the privacy notice. Raw VCF uploads remain on-device.
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

## 2.3 Organization Workflow

1. A patient creates an account through public signup. Organization accounts
   are provisioned separately by a trusted organization administrator.
2. An organization administrator assigns server-managed role/org claims and an
   active organization membership. There is no in-app professional credential
   verification or reviewer queue.
3. The user selects Organization at login. That selection is navigation only;
   the backend still checks the trusted role, organization ID, and active
   membership on every patient operation.
4. The organization dashboard searches only records linked to that
   organization and supports explicit registration when no matching patient
   exists.
5. Prescription authoring, clinician acknowledgment, clinical notes and
   patient-authorized report sharing are not implemented yet.

### Current organization workspace implementation boundary

- The sign-in screen offers separate Patient and Organization dashboard
  choices. The choice is a navigation preference only; it does not grant
  permissions. Organization entry requires server-provisioned doctor/pharmacist
  claims with an organization ID, and every callable checks active membership.
- Choosing Sign Up while Organization is selected carries that workspace
  intent through signup, stores `accountType: organization` as a workspace
  preference, and opens the organization dashboard shell. Existing organization
  preferences also open that dashboard by default after sign-in or app restart.
  The preference never grants access: patient search and registration are
  available in the UI, but callable Functions continue to enforce trusted
  organization claims and active membership before returning or creating data.
- Public signup never assigns organization roles. There is no
  professional-verification workflow in the app.
- Organization signup stores organization name and city only as self-entered
  profile details; they do not create an organization or grant member claims.
- In free Firebase Spark mode, Add Patient creates an organization-only record:
  it does not collect an email, create a Firebase Auth account, or issue a
  setup code. The record does not appear in a patient's login.
- Hospital access codes and patient-account invitations are disabled in the
  UI. Derived-profile sharing and patient-side organization access are also
  unavailable through this workflow; raw VCF files are never uploaded.
- Patient accounts open the patient dashboard. The organization dashboard is
  not hidden behind a client-side membership check; each patient-data callable
  still denies unauthorized access server-side and returns no patient data.
- Patient search is paged/capped and callable-only; it returns records from that
  organization's patient links. Search results do not silently select one of
  multiple matching patients.
- New patient registration is explicit, server-authorized, idempotent, and
  audited. An exact normalized name plus birth-year match is rejected so the
  user can search and select the existing record.
- The organization landing screen presents patient search/registration and
  visibly labels report generation and prescription authoring as unavailable.
- The Patient Details workspace reports actual stored statuses and returned
  report/prescription counts. It presents the same unavailable clinical actions
  instead of suggesting that they work. The client does not upload or retrieve
  raw VCFs because genome data remains on-device. Cloud analysis, report
  publication, prescription approval, and cross-dashboard report sync remain
  unavailable until an approved processing and consent architecture is
  implemented.

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

## 2.8 Organization Access and Consent

- Organization membership and custom claims are provisioned by trusted
  organization administration. The app does not collect credentials or provide
  professional-review screens.
- Free Firebase Spark mode does not deploy Cloud Functions. Hospital access
  codes and patient-account invitations are therefore disabled in the UI.
- Add Patient creates an organization-only record and does not collect an
  email, create a Firebase Auth account, or issue a setup code. These records
  do not appear in a patient's login.
- Organization search, registration, and workspace actions still use callable
  Functions when available. They may fail until Functions are deployed on a
  supported Firebase plan; the UI keeps these pathways visible by design.
- **Consent doc** per grantee: `scope[]`, `active`, `expiresAt` (max 365 days).
  Consent-based organization sharing remains separate from disabled
  account-invitation flows.
- Revoke by setting `active=false` through the patient-facing callable; the
  grantee's next consent-checked read fails immediately.
