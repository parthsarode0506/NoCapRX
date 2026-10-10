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

1. Sign up as Patient (email, or Google on Web) → choose a preferred language and acknowledge the privacy notice. If Authentication creates the account but Firestore setup is incomplete, signing in resumes profile/consent setup for that same account instead of creating a duplicate. Raw VCF uploads remain on-device.
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

1. A patient or organization creates an account through public signup.
   Organization signup immediately publishes the entered name and city in the
   patient-search directory; no professional verification is required to be
   listed or receive contact requests.
2. A patient can search the directory and send a request to a self-registered
   organization. The organization account receives the patient's display name
   and may acknowledge or decline. The request does not reveal a patient record,
   genomic data, email, or grant profile access.
3. Organizations that need patient-record search still require trusted
   server-managed role/org claims and active membership. These backend
   credentials authorize clinical record operations only; they are not a
   prerequisite for listing or receiving a directory contact request.
4. For provisioned organizations, a patient can request profile access. An
   authorized organization member may review it, then the patient must
   separately consent to `read_profile`. Patients may also separately allow
   sharing of derived PGx profile fields (`read_genomic_profiles`) and clinician
   prescription management (`manage_prescriptions`).
5. Raw VCF content remains on-device. With explicit genomic-profile consent,
   the patient may share only gene, diplotype, phenotype and inferred/observed
   status through an App Check-protected callable. These parser-derived fields
   are marked unvalidated and are not a clinical report or a safety decision.
6. Provisioned clinicians can open the server-authorized accepted-patient list.
   Each patient workspace rechecks membership and consent. It displays shared
   derived fields only when `read_genomic_profiles` remains active.
7. When `manage_prescriptions` is active, a clinician can enter and save a
   draft, then explicitly publish it. Drafts are clinician-only; published
   prescriptions appear in the patient's dashboard. Server callables verify
   active membership and patient consent and write an audit event atomically.
   Patients can read only published prescriptions. Medicine-level PGx
   assessment remains indeterminate; AI safety decisions and alternative-drug
   suggestions are not provided.
8. Patients can revoke organization consent; subsequent callable and Firestore
   reads are denied. Revocation also removes the organization patient-link index.

### Current organization workspace implementation boundary

- The sign-in screen offers separate Patient and Organization dashboard
  choices. The choice is a navigation preference only; it does not grant
  permissions. Any organization account can enter its directory-request
  workspace; patient-record search requires server-provisioned doctor or
  pharmacist claims with an organization ID, and every callable checks active
  membership.
- Choosing Sign Up while Organization is selected carries that workspace
  intent through signup, stores `accountType: organization`, publishes the
  directory listing, and opens the organization dashboard. Existing
  organization accounts return to that dashboard after sign-in or app restart.
  The account type does not grant patient-record access; callable Functions
  enforce trusted organization claims, active membership, and patient consent.
- Public signup never assigns organization roles. There is no
  professional-verification workflow in the app.
- Organization signup stores organization name and city as self-entered
  profile details and immediately creates a patient-discoverable listing. It
  does not create a clinical organization or grant member claims.
- The patient-facing organization directory exposes only active organization
  names and locations. Organization signup automatically publishes the
  self-entered name and city as a self-registered listing.
- Patients can send contact requests to self-registered listings. These requests
  contain the patient's display name only and do not share patient data.
- Privacy notice v1.1 explains that organization name and city become publicly
  discoverable to signed-in patients. Acknowledgment is recorded at signup.
- Self-registered directory contact requests are stored in a patient-and-
  organization-readable Firestore request record, with rules restricting each
  side to the minimum request fields. Provisioned patient access requests and
  their mirrored status are written by callable Functions and audited
  server-side.
- Organization members can review patient requests. Their approval does not
  grant access; the patient must separately approve basic-profile sharing.
- Patient links, patient search, and accepted-patient listing are callable-only.
  Reads check active membership and unexpired patient consent. Raw VCF files
  are never uploaded. Derived profile writes and prescription writes are also
  callable-only and audited.
- Patient accounts open the patient dashboard. The organization dashboard
  shell remains visible to self-registered accounts, but patient search and
  request-review controls are shown only when trusted organization claims are
  present. Every patient-data callable independently denies unauthorized access
  server-side and returns no patient data.
- Patient search is paged/capped and callable-only; it returns records from
  that organization's patient links only when organization consent is active.
  Search results do not silently select one of multiple matching patients.
- The organization landing screen lets a self-registered account review
  directory contact requests without professional verification. Patient-record
  search remains limited to trusted, provisioned accounts and queries real
  server results; no sample patient profiles or clinical counts are displayed.
  Server Functions enforce active membership and patient consent; report
  generation and prescription authoring remain unavailable.
- The Patient Details workspace returns the shared basic profile and, only
  with separate consent, patient-shared derived gene/diplotype/phenotype fields.
  It never retrieves raw VCF content. Prescription authoring and publication
  require separate patient consent. Missing genomic data is indeterminate;
  no approved clinical rule pack is currently wired to this organization
  workflow, so the app does not classify medicines as safe or suggest
  alternatives.

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
