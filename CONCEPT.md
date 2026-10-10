# OnDeviceRx — Concept, workflows, and implementation status

## Product summary

OnDeviceRx is an offline-first pharmacogenomics (PGx) decision-support
application. It uses a patient's locally imported genetic variant data and a
versioned deterministic rules engine to identify supported gene–medicine
findings. Patients can review their own locally available results and any
information explicitly shared with their account. Authorized healthcare
organization users can search and manage records linked to their organization.

The rules engine, not an AI model, determines the structured result. Any
explanation layer may restate an existing result, but cannot create or change
clinical findings. The application supports review by a qualified clinician;
it does not make treatment decisions.

This file describes both the intended product and the implementation boundary
that exists in this repository. A listed or planned feature is not evidence
that it is implemented or clinically validated.

## The problem and intended use

Medicine response can vary between people, and genetic variation is one factor
that may affect metabolism or response. PGx results can be difficult to
interpret and may not be available in a useful form during a medication
review.

OnDeviceRx aims to make supported PGx information easier to review by
connecting on-device genetic analysis, explainable rule results, and
authorization-controlled patient and organization experiences. Genetics is
only one part of medication safety. The result must be considered alongside
the patient's current clinical context and trusted evidence.

OnDeviceRx is advisory decision support, not a replacement for clinical
judgment. It does not autonomously prescribe, finalize a prescription, change
a dose, or select a substitute.

## User types and access model

### Patient

The patient experience is intended to provide access to:

- Their own profile and relevant account details.
- On-device VCF import and analysis status.
- Available local PGx findings and medication checks.
- Their report history and PDF export where implemented.
- AI-assisted explanation or chat features where enabled.
- Organization-linked patient-record status and privacy controls.
- Approved reports or prescriptions only when a future authorized sharing
  workflow makes them available.

Authentication identifies the account; it does not authorize access to every
record. Patient data must remain scoped to the signed-in patient and applicable
grants or consents.

### Organization / healthcare team

The organization workspace is intended for authorized healthcare teams. The
current organization dashboard supports:

- Searching patients linked to the authenticated user's active organization.
- Opening the matching organization patient workspace.
- Registering a patient when no accessible match is found.
- Creating a one-time, email-bound account invitation for a registered
  patient.
- Reviewing the record's stored workflow status and available counts.

The current workspace does **not** upload or retrieve VCF data, perform cloud
analysis, publish reports, or finalize prescriptions. Those functions must not
be represented as available until a privacy-approved, clinically validated
data flow is implemented.

The app does not ask users to choose a suggested professional role. Selecting
an Organization workspace or entering an organization name does not grant
organization access. Callable operations require trusted server-provisioned
claims and active membership.

## End-to-end user journeys

### Sign up and sign in

1. A person signs up or signs in through Firebase Authentication.
2. Signup collects the minimum account details and a privacy-notice
   acknowledgment. Organization signup may save the user's organization name
   and city as self-entered display information.
3. The app loads the user's profile and workspace preference.
4. Patient and Organization choices control navigation only. Protected
   organization data operations are authorized by server-managed claims and
   active organization membership.
5. The app loads only data permitted to that authenticated account.

### Patient's own PGx workflow

1. The patient imports a VCF file from local device storage.
2. VCF parsing and supported variant extraction happen on the device.
3. The deterministic rule engine evaluates only supported, locally available
   rules and returns an explicit indeterminate or unsupported outcome when
   inputs or evidence are insufficient.
4. The app presents the result with provenance and its decision-support
   limitations.
5. An explanation component may simplify the already-decided structured result
   and falls back to a deterministic template when an explanation is
   unavailable or invalid.

Raw VCF files are not uploaded to Firebase Storage, Firestore, Cloud
Functions, or an AI provider. Derived-result synchronization is not a general
sharing pipeline and must not be assumed to exist merely because account or
report metadata is stored remotely.

### Organization patient search and registration

1. An authorized organization user searches by patient name or patient ID.
2. Search results are limited to the organization's server-maintained patient
   links. A name match alone is not enough to authorize access to an unrelated
   record.
3. The user selects the intended accessible record, or registers a new one if
   no accessible match exists.
4. Registration is callable-only, membership-checked, idempotent, and audited.
   Duplicate normalized name and birth-year matches are rejected so the user
   can search for an existing record.
5. The organization workspace displays only the status and summary fields
   currently returned by the backend. A VCF reference, analysis, report, or
   prescription must not be shown as available when it has not been
   implemented.

### Patient account invitation and record link

1. During patient registration, the organization enters the patient's email.
2. The backend creates a random one-time code, stores only its hash, binds it
   to the invited email, and sets a seven-day expiry.
3. The organization shares the code with the patient manually. No invitation
   email delivery provider is configured.
4. The patient creates or signs into their own account, verifies the email,
   and enters the code. Existing accounts can use the patient dashboard's
   **Link hospital record** action.
5. The patient reviews the organization and patient record, then accepts or
   declines the link.
6. Accepting the record link and consenting to derived-profile sharing are
   separate actions. Consent can be withdrawn from the patient dashboard.
7. The present opt-in records a consent state; it does not activate a general
   derived-profile or report synchronization pipeline. Raw VCF files remain
   on the patient's device.

Declining the invitation does not associate that patient account with the
organization-created record.

## Feature catalogue and current status

| Area | Current implementation boundary |
|---|---|
| Firebase Authentication | Email/password sign-in and signup; Google sign-in is limited to supported Web configuration. |
| Workspace routing | Patient/Organization preference controls the initial dashboard route, not permissions. |
| Organization authorization | Cloud Functions verify trusted role/org claims and active membership. No in-app professional verification or role assignment. |
| Patient profile | Account profile and local patient profile; local profile storage is namespaced by Firebase UID. |
| VCF | Local import and on-device parsing. No Firebase VCF upload, cloud VCF retrieval, or server-side analysis. |
| PGx decisions | Deterministic local rule logic is the decision source. Rule coverage and evidence must be verified against the versioned data. |
| Organization patient search | Callable-only, scoped to organization patient links, capped, and audited. |
| Patient registration | Callable-only, retry-safe, with duplicate checks and audit events. |
| Patient account linking | One-time, seven-day email-bound invitation; patient email verification; explicit accept/decline; separate sharing-consent choice. |
| Consent withdrawal | Patient-facing callable revokes the stored organization consent; Firestore access checks reject inactive or expired consent. |
| Report and prescription sync | No complete organization-to-patient publication/approval workflow is implemented. |
| Prescription creation and approval | Not implemented as an organization workflow. |
| Clinical interactions, allergy checks, and contraindication checks | Not represented as available unless a validated configured engine and its data source are connected. |
| AI explanations | Explanation-only by design; actual provider availability and grounding depend on the configured implementation. |
| PDF export, chat history, and reminders | Available only to the extent implemented in the corresponding app screens/services; verify before making deployment claims. |
| Firebase Rules | Firestore and Storage rules are separate. They must be published to the correct Firebase project and emulator-tested. |

## Data flow and responsibilities

### Flutter client

- Presents patient and organization screens, signup, account-link review, and
  on-device analysis.
- Imports and parses VCF files locally.
- Calls Firebase Authentication and narrowly scoped callable operations.
- Clears transient patient-analysis state when changing accounts.
- Must not contain Firebase Admin credentials, backend secrets, or authority
  to assign privileged roles.

### Firebase Authentication

- Authenticates the account and supplies its UID.
- Email verification is required before invitation preview or response.
- Authentication alone does not authorize organization patient access.

### Cloud Firestore

Current data paths include:

- `users/{uid}` for account profile and workspace preference.
- `organizations/{orgId}/members/{uid}` for server-maintained membership.
- `organizations/{orgId}/patientLinks/{patientId}` for the organization's
  scoped patient search index.
- `organizations/{orgId}/idempotency/{key}` for safe registration retries.
- `patients/{patientId}` for organization-created patient identity/workflow
  metadata and the server-linked owner UID after invitation acceptance.
- `patients/{patientId}/accountInvitations/{codeHash}` for a hashed,
  expiring, email-bound one-time invitation.
- `patients/{patientId}/consents/{organizationId}` for explicit derived-data
  sharing consent, when granted.
- `auditLogs/{eventId}` for backend-written organization and invitation
  events.

Raw VCF contents do not belong in Firestore documents. Use the actual
collection schema and deployed rules as the source of truth; this list is a
summary, not a replacement for [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md).

### Cloud Functions

Privileged organization search, registration, patient workspace reads, and
account invitation operations are performed by callable Functions. They
validate input, App Check, claims, active membership, and patient-link
ownership, and write audit events. The client must not bypass these callables
to query the full patient collection.

### Firebase Storage

Storage rules are separate from Firestore rules. The current app must not
create a public VCF path or upload raw genetic files. Existing PDF/profile
paths are independently restricted by Storage Rules.

### Clinical rules and explanations

- The deterministic engine consumes supported inputs and validated rules.
- Every result should preserve its rule version, evidence reference, input
  traceability, and limitations as applicable to the implemented model.
- Unsupported drugs, missing data, and uncallable input must not produce a
  reassuring or invented result.
- AI may explain an existing structured result only. It cannot determine
  risk, invent evidence, or approve a prescription.
- Clinical rule content must be ingested from maintained authoritative
  sources and reviewed; it must not be authored from memory.

## Security and privacy requirements

- Default-deny Firestore and Storage access; check authorization on the
  backend and in direct database rules.
- Use server-managed custom claims plus active organization membership for
  organization access. Profile workspace preferences and self-entered
  organization details are not authorization claims.
- Restrict patient records to the owner and appropriately consented,
  verified, actively affiliated organizations.
- Invitation codes are one-time, short-lived, email-bound, and stored only as
  hashes.
- Keep raw VCF data on-device. Do not include genetic data or other PHI in
  logs, analytics, notifications, screenshots, or unapproved external calls.
- Keep sensitive audit events server-written and append-only.
- Provide consent revocation and ensure authorization checks honor inactive
  and expired consent.
- Test positive and negative authorization paths using the Firebase Emulator
  Suite before deployment.
- Confirm retention, erasure, consent, regulatory, and clinical-validation
  obligations with qualified advisors before production use.

## Important implementation gaps

The following are future work, not current promises:

- Uploading or retrieving VCF files from Firebase Storage.
- Cloud VCF processing or cloud genetic analysis.
- Cross-dashboard synchronization of derived genomic profiles.
- Organization publication of reports and prescriptions to patient accounts.
- Prescription drafting, human approval, override acknowledgment, and
  history in the organization dashboard.
- Validated clinical interaction, allergy, and contraindication data sources.
- A complete consent center, data-export, erasure, and retention workflow.
- A general patient report-grounded AI chat with validated safeguards.

Any future cloud processing of genetic data requires a separate privacy,
security, and clinical architecture review. It must not be added by changing
the client alone.

## Definition of an end-to-end release workflow

A release candidate should demonstrate that:

1. Patient and organization accounts route to their selected workspaces
   without client preferences granting access.
2. An unprivileged account cannot search, register, or retrieve organization
   patient records.
3. Active members can access only patient records linked to their
   organization and covered by required consent.
4. Patient invitations require the matching verified email and cannot be
   reused or accepted after expiry.
5. Patients can decline invitations and separately grant or withdraw
   derived-profile sharing consent.
6. Raw VCF parsing and PGx decisions remain on-device.
7. Unknown, missing, unsupported, or ambiguous input produces an explicit
   non-reassuring result.
8. Firestore and Storage rules reject unauthorized access, including
   suspended organization members and cross-patient reads.
9. Failed requests report an actionable error and retry-safe operations do
   not create duplicate patient records.
10. No unavailable cloud upload, report, prescription, or AI behavior is
    presented as complete.

For current workflows and schema detail, see
[`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) and
[`docs/DATA_MODEL.md`](docs/DATA_MODEL.md).
