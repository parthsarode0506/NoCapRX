# DATA_MODEL.md — Firestore collections

Region: create the Firestore database in **asia-south1 (Mumbai)** or
**asia-south2 (Delhi)**. Native mode. The location cannot be changed later.

```
users/{uid}                        self profile (displayName, phone, locale, accountType, organizationName, city, linkedPatientId, linkedPatientBirthYear, linked organization display fields, createdAt). UID is the document ID; email comes from Firebase Auth. `accountType`, organizationName and city are display preferences only, never authorization claims.
organizations/{orgId}/patientLinks/{patientId} organization-scoped patient search index; patient-originated invitation links are disabled in free Firebase mode.
users/{uid}/consents/privacy_notice immutable acknowledgment (accepted, noticeVersion, createdAt); optional processing consents must use separately versioned, revocable records.
users/{uid}/reports/{id}           legacy cloud report history; new reports remain local until an explicit derived-data sync consent flow is implemented.
orgs/{orgId}                       displayName, type(pharmacy|lab|hospital|clinic), plan, status, logoUrl, contactEmail, kybStatus
orgs/{orgId}/members/{uid}         role, status, invitedBy, joinedAt                 (Functions write)
orgs/{orgId}/invites/{inviteId}    email, role, expiresAt, status                    (Functions write)
orgs/{orgId}/inventory/{drugId}    drugId(generic), name, inStock, updatedAt, updatedBy
orgs/{orgId}/usage/{yyyymm}        counters only, no PHI                              (Functions write)
patients/{pid}                     ownerUid, managedByOrgId, alias, yearOfBirth, sex, relation, isMinor, guardianConsent, createdAt, updatedAt
patients/{pid}/genomicProfiles/{id}   gene, diplotype, phenotype, activityScore, source(vcf|lab_report|manual), confidence, ruleSetVersion, createdBy, createdAt   (append-only)
patients/{pid}/prescriptions/{id}     drugs[{generic, brand, strength, frequency}], source(ocr|manual|voice), authorId, status, createdAt, updatedAt
patients/{pid}/screenings/{id}        prescriptionId, drug, gene[], phenotype[], severity, recommendationRef, cpicGuidelineRef, evidenceLevel, ruleSetVersion, inputHash, appVersion, createdBy, createdAt  (append-only)
patients/{pid}/screenings/{id}/acknowledgments/{ackId}   actorUid, actorRole, action(accepted|alternative_chosen|overridden|deferred), reasonCode, reasonText, createdAt  (immutable)
patients/{pid}/grants/{granteeUid}    scopes[], expiresAt, revokedAt, createdAt, grantedBy, granteeOrgId, label, breakGlass(bool, Functions only)
patients/{pid}/consents/{id}          purpose, granted, textVersion, createdAt, revokedAt; organization sharing consent is keyed by organization ID and revocable via a callable.
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
- Signup lets users choose Patient or Organization as a dashboard preference.
  Organization name/city are self-entered profile details and do not create an
  organization or grant access. Trusted organization claims are provisioned
  separately; professional credential verification is not implemented.
- In free Firebase mode, the UI disables numeric hospital access codes and
  patient account invitations. Add Patient creates an organization-only record
  without collecting an email, creating an Auth account, or issuing a setup
  code; it does not link to patient sign-in. Raw VCF files remain on-device.
- Organization patient search and registration are callable-only operations.
  `organizations/{orgId}/patientLinks/{patientId}` is the scoped search index;
  it points to the single canonical `patients/{patientId}` record. The
  `idempotency` subcollection stores request-key results to make registration
  retry-safe. Clients must not read the full patient collection.
- The current organization workspace returns only identity and workflow
  status. It does not upload raw VCFs, run a server analysis, or publish a
  report. Those fields must not be represented as complete without a trusted,
  privacy-approved, clinically validated pipeline.
