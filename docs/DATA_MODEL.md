# DATA_MODEL.md — Firestore collections

Region: create the Firestore database in **asia-south1 (Mumbai)** or
**asia-south2 (Delhi)**. Native mode. The location cannot be changed later.

```
users/{uid}                        self profile (displayName, phone, locale, accountType, organizationName, city, linkedPatientId, linkedPatientBirthYear, linked organization display fields, createdAt). UID is the document ID; email comes from Firebase Auth. `accountType`, organizationName and city are display preferences only, never authorization claims.
organizations/{orgId}/patientLinks/{patientId} organization-scoped patient search index; Functions write only after patient consent.
organizations/{orgId}/patientInvitations/{patientUid} server-managed patient access request and review state.
users/{uid}/organizationInvitations/{orgId} mirrored server-managed patient access request state.
organizationDirectory/{uid} public-safe organization name and city; signup creates a selfRegistered listing that is explicitly unverified.
organizationDirectory/{orgUid}/requests/{patientUid} patient display-name-only contact request for a self-registered listing; the owner may acknowledge or decline without gaining patient-record access.
users/{patientUid}/directoryRequests/{orgUid} patient-readable mirror of the directory contact request and its status.
users/{uid}/consents/privacy_notice privacy-notice acknowledgment (accepted, noticeVersion, createdAt); v1.1 includes public self-registered directory listings.
users/{uid}/reports/{id}           legacy cloud report history; new reports remain local until an explicit derived-data sync consent flow is implemented.
orgs/{orgId}                       displayName, type(pharmacy|lab|hospital|clinic), plan, status, logoUrl, contactEmail, kybStatus
orgs/{orgId}/members/{uid}         role, status, invitedBy, joinedAt                 (Functions write)
orgs/{orgId}/invites/{inviteId}    email, role, expiresAt, status                    (Functions write)
orgs/{orgId}/inventory/{drugId}    drugId(generic), name, inStock, updatedAt, updatedBy
orgs/{orgId}/usage/{yyyymm}        counters only, no PHI                              (Functions write)
patients/{pid}                     ownerUid, managedByOrgId, alias, yearOfBirth, sex, relation, isMinor, guardianConsent, createdAt, updatedAt
patients/{pid}/genomicProfiles/{id}   profiles[{gene, diplotype, phenotype, isInferred}], source(on_device_vcf_parse), clinicalStatus(not_clinically_validated), createdAt   (append-only; patient callable write, consent-scoped clinician read)
patients/{pid}/prescriptionDrafts/{id} prescriptionId, patientId, organizationId, prescriberUid, prescriberName, items[{medicineName, dosage, frequency, duration, instructions, pgxRiskLabel, severity, recommendation}], notes, status(draft), createdAt   (append-only; callable-only write, clinician-only read)
patients/{pid}/prescriptions/{id}     same prescription content, status(issued), createdAt, issuedAt   (append-only published copy; patient reads issued records)
patients/{pid}/screenings/{id}        prescriptionId, drug, gene[], phenotype[], severity, recommendationRef, cpicGuidelineRef, evidenceLevel, ruleSetVersion, inputHash, appVersion, createdBy, createdAt  (append-only)
patients/{pid}/screenings/{id}/acknowledgments/{ackId}   actorUid, actorRole, action(accepted|alternative_chosen|overridden|deferred), reasonCode, reasonText, createdAt  (immutable)
patients/{pid}/grants/{granteeUid}    scopes[], expiresAt, revokedAt, createdAt, grantedBy, granteeOrgId, label, breakGlass(bool, Functions only)
patients/{pid}/consents/{orgId}       scopes, active, expiresAt, grantedAt, revokedAt; organization access is limited to explicit scopes and changed through callables.
patients/{pid}/accessLog/{id}         actorUid, actorRole, orgId, action, at   (append-only; patient can read)
patients/{pid}/accountInvitations/{sha256(code)} legacy email-bound one-time account link; not available in free Firebase mode.
orders/{orderId}                      patientId, labOrgId, panel, status, createdAt
ruleSets/{version}                    sha256, signature, storagePath, cpicSnapshot, changelog, signoff{reviewerUid, at}, status, createdAt
ruleChannels/{channel}                currentVersion, canaryOrgIds[], canaryPercent, pinnedVersion
config/app                            minAppVersion, killSwitchGenePairs[], maintenanceMessage
auditLogs/{id}                        actorUid, actorRole, orgId, action, targetPath, meta (no PHI), at     (Functions write only)
users/{uid}/notifications/{id}        type, title, body(no PHI), read, createdAt
```

## Rules of thumb
- Never store raw VCF or full names/phone in `patients/*`. Use alias.
- Timestamps always `FieldValue.serverTimestamp()` on the client (rules check `== request.time`).
- Clinical collections are append-only. Corrections create a new doc that supersedes (`supersedes: <id>`).
- No document exceeds 100 KB. Arrays that grow unbounded become subcollections.
- Rules allow at most 10 document-access calls per request. Denormalize `ownerUid`
  onto subcollection docs if the limit is hit.
- List queries must include the same filter the rule checks, else Firestore rejects the query.
- Signup lets users choose Patient or Organization as a dashboard choice.
  Organization sign-up automatically publishes the self-entered name and city
  to the patient-search directory with `selfRegistered: true`; no professional
  verification is required for listing or receiving contact requests. This
  listing is not a clinical organization identity or patient-data access claim.
  Only the owner can create/update their own matching listing; patient profiles
  remain protected by server authorization and explicit consent.
- Organization membership, access requests, patient links, consent and audit
  records are managed by callable Functions. They require a supported Firebase
  plan, deployed Functions and App Check configuration.
- Patients may search the public-safe organization directory and send a
  display-name-only contact request to a self-registered listing. The
  organization can acknowledge or decline; these actions never reveal patient
  records or genomic information. Requests for patient-record access remain
  available only for provisioned organizations, and the patient must separately
  consent to `read_profile`.
- Organization patient search is callable-only and returns only linked records
  after active-membership and organization-consent checks.
  `organizations/{orgId}/patientLinks/{patientId}` is the scoped search index;
  it points to the canonical `patients/{patientId}` record. Clients cannot
  read or write patient-link and invitation documents directly.
- The organization workspace returns only identity data shared under
  `read_profile`. `read_genomic_profiles` is a separate patient-controlled
  scope for derived gene/diplotype/phenotype data; it never grants raw VCF
  access. The app marks these parser-derived fields as not clinically
  validated. `manage_prescriptions` separately permits a clinician to save
  drafts and publish clinician-authored prescriptions. All writes are
  callable-only, membership- and consent-checked, and audited server-side.
  Drafts and published copies are append-only; publication creates a distinct
  issued record.
