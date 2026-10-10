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
4. A patient can search the registered-organization directory and send an
   access request. An authorized organization member may review or decline it.
5. Organization approval only advances the request. The patient must separately
   consent to sharing the basic profile (`read_profile`) before organization
   search or profile access is enabled.
6. The patient can revoke organization consent; subsequent callable reads are
   denied. Raw VCF and derived genomic profiles remain on-device.
7. Prescription authoring, clinician acknowledgment, clinical notes and
   patient-authorized report synchronization are not implemented.

### Current organization workspace implementation boundary

- The sign-in screen offers separate Patient and Organization dashboard
  choices. The choice is a navigation preference only; it does not grant
  permissions. Organization entry requires server-provisioned doctor/pharmacist
  claims with an organization ID, and every callable checks active membership.
- Choosing Sign Up while Organization is selected carries that workspace
  intent through signup, stores `accountType: organization` as a workspace
  preference, and opens the organization dashboard shell. Existing organization
  preferences also open that dashboard by default after sign-in or app restart.
  The preference never grants access: patient search is available in the UI,
  but callable Functions enforce trusted organization claims, active
  membership, and patient consent before returning profile data.
- Public signup never assigns organization roles. There is no
  professional-verification workflow in the app.
- Organization signup stores organization name and city only as self-entered
  profile details; they do not create an organization or grant member claims.
- The patient-facing organization directory exposes only active organization
  names and locations. Organization signup automatically publishes the
  self-entered name and city as a self-registered, unverified listing.
- Patients can discover these self-registered listings, but cannot request
  patient-data access through a listing that has no provisioned organization.
- Privacy notice v1.1 explains that organization name and city become publicly
  discoverable to signed-in patients. Acknowledgment is recorded at signup.
- Patient access requests and mirrored request status for provisioned
  organizations are written by callable Functions and audited server-side.
- Organization members can review patient requests. Their approval does not
  grant access; the patient must separately approve basic-profile sharing.
- Patient links and organization search are callable-only. Search and profile
  reads check active membership and unexpired patient consent; report and
  prescription workflows are not implemented. Raw VCF files are never uploaded.
- Patient accounts open the patient dashboard. The organization dashboard is
  not hidden behind a client-side membership check; each patient-data callable
  still denies unauthorized access server-side and returns no patient data.
- Patient search is paged/capped and callable-only; it returns records from
  that organization's patient links only when organization consent is active.
  Search results do not silently select one of multiple matching patients.
- The organization landing screen provides patient search and a patient-request
  review pathway. It labels report generation and prescription authoring as
  unavailable.
- The Patient Details workspace returns the shared basic profile only. VCF,
  genomic findings, reports and prescriptions are explicitly shown as not
  shared or not synchronized; missing records are not represented as zero
  counts. Cloud analysis, report publication and prescription approval remain
  unavailable until the approved processing and clinical-rule workflows exist.

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
- Access requests, organization search and workspace reads use callable
  Functions with App Check, active membership and audit logging. Deploy them on
  a supported Firebase plan before using these workflows.
- Patients can search the organization directory. Self-registered entries are
  labeled unverified and are directory-only. Provisioned organizations can
  receive access requests; organization review and patient consent are separate
  steps before `read_profile` access is granted. Requests, links, consent and
  revocation are managed by trusted Functions, not direct client writes.
- **Consent doc** per grantee: `scope[]`, `active`, `expiresAt` (max 365 days).
  The current organization share grants only `read_profile`; it does not share
  genetic data or clinical reports.
- Revoke by setting `active=false` through the patient-facing callable; the
  grantee's next consent-checked read fails immediately.
