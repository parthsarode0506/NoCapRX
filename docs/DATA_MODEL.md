# DATA_MODEL.md — Firestore collections

Region: create the Firestore database in **asia-south1 (Mumbai)** or
**asia-south2 (Delhi)**. Native mode. The location cannot be changed later.

```
users/{uid}                        self profile (displayName, locale, fcmTokens, requestedRole, createdAt). NO role/verified here.
providers/{uid}                    public provider card, written by Functions only: displayName, role, verified, orgId, specialty, verifiedAt, verificationExpiresAt
verifications/{uid}                type, registrationNumber, issuingBody, state, documentPaths[], status(pending|approved|rejected|expired), submittedAt, reviewedBy, reviewedAt, reason
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
patients/{pid}/consents/{id}          purpose, granted, textVersion, createdAt, revokedAt
patients/{pid}/accessLog/{id}         actorUid, actorRole, orgId, action, at   (append-only; patient can read)
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
