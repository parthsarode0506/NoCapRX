import { initializeApp } from "firebase-admin/app";
import { createHash, randomBytes, randomInt } from "node:crypto";
import {
  FieldValue,
  getFirestore,
} from "firebase-admin/firestore";
import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";
import { z } from "zod";

initializeApp();

const region = "asia-south1";
const database = getFirestore();

const organizationSearchSchema = z.object({
  query: z.string().trim().min(2).max(80),
}).strict();

const registerPatientSchema = z.object({
  idempotencyKey: z.string().uuid(),
  name: z.string().trim().min(2).max(120),
  birthYear: z.number().int().min(1900).max(new Date().getUTCFullYear()).optional(),
}).strict();

const createInvitationSchema = z.object({
  patientId: z.string().min(1).max(128),
  email: z.string().trim().email().max(254),
}).strict();

const invitationCodeSchema = z.object({
  code: z.string().trim().min(20).max(100),
}).strict();

const invitationResponseSchema = invitationCodeSchema.extend({
  accepted: z.boolean(),
  shareDerivedProfile: z.boolean(),
}).strict();

const organizationAccessRequestSchema = z.object({
  organizationCode: z.string().regex(/^\d{8}$/),
}).strict();

const organizationAccessResponseSchema = z.object({
  patientUid: z.string().min(1).max(128),
  accepted: z.boolean(),
}).strict();

const patientOrganizationResponseSchema = z.object({
  organizationId: z.string().trim().min(1).max(128),
  accepted: z.boolean(),
  shareProfile: z.boolean(),
}).strict();

const revokeOrganizationConsentSchema = z.object({
  organizationId: z.string().trim().min(1).max(128),
}).strict();

function hashInvitationCode(code: string): string {
  return createHash("sha256").update(code).digest("hex");
}

function invitationReference(code: string) {
  const separator = code.indexOf(".");
  if (separator < 1) {
    throw new HttpsError("invalid-argument", "Patient invitation code is invalid.");
  }
  const patientId = code.slice(0, separator);
  const secret = code.slice(separator + 1);
  if (!/^[A-Za-z0-9_-]{10,128}$/.test(patientId) || !/^[A-Za-z0-9_-]{32}$/.test(secret)) {
    throw new HttpsError("invalid-argument", "Patient invitation code is invalid.");
  }
  return database
    .collection("patients")
    .doc(patientId)
    .collection("accountInvitations")
    .doc(hashInvitationCode(secret));
}

function requireVerifiedPatient(request: CallableRequest<unknown>) {
  const auth = authRequired(request);
  if (auth.token.email_verified !== true || typeof auth.token.email !== "string") {
    throw new HttpsError(
      "failed-precondition",
      "Verify the invited email address before accepting this patient invitation.",
    );
  }
  return auth;
}

function normalizePatientName(name: string): string {
  return name
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("en")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

async function requireOrganizationAccess(
  uid: string,
  token: Record<string, unknown>,
): Promise<{ orgId: string; role: string }> {
  const role = token.role;
  const orgId = token.orgId;
  if (
    (role !== "doctor" && role !== "pharmacist") ||
    typeof orgId !== "string" ||
    orgId.length === 0
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active verified organization membership is required.",
    );
  }
  const membership = await database
    .collection("organizations")
    .doc(orgId)
    .collection("members")
    .doc(uid)
    .get();
  if (
    !membership.exists ||
    membership.data()?.status !== "active" ||
    membership.data()?.role !== role
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active verified organization membership is required.",
    );
  }
  return { orgId, role };
}

function authRequired(request: CallableRequest<unknown>) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  return request.auth;
}

async function ensureOrganizationAccessCode(
  orgId: string,
  actorUid: string,
  actorRole: string,
): Promise<{ code: string; name: string }> {
  const organizationRef = database.collection("organizations").doc(orgId);
  const auditRef = database.collection("auditLogs").doc();
  return database.runTransaction(async (transaction) => {
    const organization = await transaction.get(organizationRef);
    if (!organization.exists) {
      throw new HttpsError("not-found", "Organization profile is unavailable.");
    }
    const organizationData = organization.data()!;
    let code = organizationData.patientAccessCode;
    let needsOrganizationUpdate = false;
    if (typeof code !== "string" || !/^\d{8}$/.test(code)) {
      code = "";
      needsOrganizationUpdate = true;
    }

    if (code) {
      const codeRef = database.collection("organizationAccessCodes").doc(code);
      const codeSnapshot = await transaction.get(codeRef);
      if (
        !codeSnapshot.exists ||
        codeSnapshot.data()?.organizationId === orgId
      ) {
        if (!codeSnapshot.exists) {
          transaction.create(codeRef, {
            organizationId: orgId,
            createdAt: FieldValue.serverTimestamp(),
          });
          transaction.create(auditRef, {
            actorUid,
            actorRole,
            orgId,
            action: "organization_patient_access_code_registered",
            at: FieldValue.serverTimestamp(),
            meta: {},
          });
        }
        if (needsOrganizationUpdate) {
          transaction.update(organizationRef, {
            patientAccessCode: code,
          });
        }
        return {
          code,
          name: String(organizationData.name ?? "Organization"),
        };
      }
      needsOrganizationUpdate = true;
    }

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const candidate = String(randomInt(10_000_000, 100_000_000));
      const codeRef = database.collection("organizationAccessCodes")
        .doc(candidate);
      const codeSnapshot = await transaction.get(codeRef);
      if (codeSnapshot.exists) continue;
      transaction.create(codeRef, {
        organizationId: orgId,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.update(organizationRef, {
        patientAccessCode: candidate,
      });
      transaction.create(auditRef, {
        actorUid,
        actorRole,
        orgId,
        action: "organization_patient_access_code_created",
        at: FieldValue.serverTimestamp(),
        meta: {},
      });
      return {
        code: candidate,
        name: String(organizationData.name ?? "Organization"),
      };
    }
    throw new HttpsError(
      "resource-exhausted",
      "A unique organization code could not be created. Retry shortly.",
    );
  });
}

export const searchOrganizationPatients = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const parsed = organizationSearchSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError(
        "invalid-argument",
        "Enter at least two characters to search.",
      );
    }
    const { orgId, role } = await requireOrganizationAccess(
      auth.uid,
      auth.token,
    );
    const searchText = parsed.data.query.trim();
    const normalized = normalizePatientName(searchText);
    if (normalized.length < 2) {
      throw new HttpsError(
        "invalid-argument",
        "Search by at least two letters or a complete patient ID.",
      );
    }
    const links = database
      .collection("organizations")
      .doc(orgId)
      .collection("patientLinks");
    const linkQuery = links
      .orderBy("normalizedName")
      .startAt(normalized)
      .endAt(`${normalized}\uf8ff`)
      .limit(20);
    const idLink = links.doc(searchText);
    const memberRef = database
      .collection("organizations")
      .doc(orgId)
      .collection("members")
      .doc(auth.uid);
    const auditRef = database.collection("auditLogs").doc();
    const patients = await database.runTransaction(async (transaction) => {
      const member = await transaction.get(memberRef);
      if (
        !member.exists ||
        member.data()?.status !== "active" ||
        member.data()?.role !== role
      ) {
        throw new HttpsError(
          "permission-denied",
          "Organization membership is no longer active.",
        );
      }
      const matches = await transaction.get(linkQuery);
      const exactId = await transaction.get(idLink);
      const patientIds = new Set(matches.docs.map((doc) => doc.id));
      if (exactId.exists) patientIds.add(exactId.id);
      const found = [];
      for (const patientId of patientIds) {
        const patientSnapshot = await transaction.get(
          database.collection("patients").doc(patientId),
        );
        if (!patientSnapshot.exists) continue;
        const patient = patientSnapshot.data()!;
        if (typeof patient.ownerUid === "string") {
          const consent = await transaction.get(
            database.collection("patients")
              .doc(patientId)
              .collection("consents")
              .doc(orgId),
          );
          const expiresAt = consent.data()?.expiresAt?.toDate?.();
          if (
            consent.data()?.active !== true ||
            !(expiresAt instanceof Date) ||
            expiresAt.getTime() <= Date.now()
          ) {
            continue;
          }
        }
        found.push({
          patientId,
          name: patient.name,
          birthYear: patient.birthYear ?? null,
          vcfStatus: patient.vcfStatus ?? "not_uploaded",
          analysisStatus: patient.analysisStatus ?? "not_started",
          latestReportAt: patient.latestReportAt?.toDate?.().toISOString() ?? null,
        });
      }
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: role,
        orgId,
        action: "organization_patient_search",
        at: FieldValue.serverTimestamp(),
        meta: { resultCount: found.length },
      });
      return found;
    });
    return { patients, limit: 20 };
  },
);

export const getOrganizationSummary = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const { orgId, role } = await requireOrganizationAccess(auth.uid, auth.token);
    const organization = await ensureOrganizationAccessCode(
      orgId,
      auth.uid,
      role,
    );
    return {
      organizationId: orgId,
      organizationCode: organization.code,
      name: organization.name,
    };
  },
);

export const requestOrganizationPatientAccess = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = requireVerifiedPatient(request);
    const parsed = organizationAccessRequestSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError(
        "invalid-argument",
        "Enter the 8-digit organization code shared by the clinic or hospital.",
      );
    }
    const organizationCode = parsed.data.organizationCode;
    const resolvedOrganizationId = (await database
      .collection("organizationAccessCodes")
      .doc(organizationCode)
      .get()).data()?.organizationId;
    if (
      typeof resolvedOrganizationId !== "string" ||
      resolvedOrganizationId.length === 0
    ) {
      throw new HttpsError("not-found", "This organization code was not found.");
    }
    const organizationId = resolvedOrganizationId;
    const userRef = database.collection("users").doc(auth.uid);
    const organizationRef = database.collection("organizations")
      .doc(organizationId);
    const codeRef = database.collection("organizationAccessCodes")
      .doc(organizationCode);
    const organizationInvitationRef = organizationRef
      .collection("patientInvitations")
      .doc(auth.uid);
    const userInvitationRef = userRef
      .collection("organizationInvitations")
      .doc(organizationId);
    const auditRef = database.collection("auditLogs").doc();

    const result = await database.runTransaction(async (transaction) => {
      const [user, organization, organizationInvitation, accessCode] =
        await Promise.all([
          transaction.get(userRef),
          transaction.get(organizationRef),
          transaction.get(organizationInvitationRef),
          transaction.get(codeRef),
        ]);
      if (
        !user.exists ||
        !organization.exists ||
        accessCode.data()?.organizationId !== organizationId
      ) {
        throw new HttpsError("not-found", "The account or organization was not found.");
      }
      const userData = user.data()!;
      const patientId = typeof userData.linkedPatientId === "string"
        ? userData.linkedPatientId
        : auth.uid;
      const patientRef = database.collection("patients").doc(patientId);
      const patient = await transaction.get(patientRef);
      const patientData = patient.data();
      if (
        patient.exists &&
        typeof patientData?.ownerUid === "string" &&
        patientData.ownerUid !== auth.uid
      ) {
        throw new HttpsError(
          "permission-denied",
          "This patient record is linked to another account.",
        );
      }
      const currentInvitation = organizationInvitation.data();
      if (
        organizationInvitation.exists &&
        ["pending_org_review", "awaiting_patient_confirmation"]
          .includes(String(currentInvitation?.status))
      ) {
        const existingPatientInvitation = await transaction.get(userInvitationRef);
        if (
          !existingPatientInvitation.exists ||
          existingPatientInvitation.data()?.status !== currentInvitation?.status
        ) {
          throw new HttpsError(
            "internal",
            "The organization invitation records are out of sync. Contact support.",
          );
        }
        return {
          status: currentInvitation?.status as string,
          organizationName: organization.data()?.name ?? "Organization",
        };
      }
      if (currentInvitation?.status === "accepted") {
        const consent = await transaction.get(
          patientRef.collection("consents").doc(organizationId),
        );
        const expiry = consent.data()?.expiresAt?.toDate?.();
        if (
          consent.data()?.active === true &&
          expiry instanceof Date &&
          expiry.getTime() > Date.now()
        ) {
          return {
            status: "accepted",
            organizationName: organization.data()?.name ?? "Organization",
          };
        }
      }
      const patientName =
        (typeof patientData?.name === "string" && patientData.name.trim()) ||
        (typeof userData.displayName === "string" && userData.displayName.trim()) ||
        "";
      if (patientName.length < 2) {
        throw new HttpsError(
          "failed-precondition",
          "Complete your account profile before sending an organization invitation.",
        );
      }
      const normalizedName = normalizePatientName(patientName);
      if (!patient.exists) {
        transaction.create(patientRef, {
          ownerUid: auth.uid,
          name: patientName,
          normalizedName,
          birthYear: null,
          createdBy: auth.uid,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          version: 1,
          vcfStatus: "not_uploaded",
          analysisStatus: "not_started",
        });
      }
      const invitation = {
        organizationId,
        organizationName: organization.data()?.name ?? "Organization",
        patientUid: auth.uid,
        patientId,
        patientName,
        patientEmail: String(auth.token.email).trim().toLowerCase(),
        status: "pending_org_review",
        requestedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(organizationInvitationRef, invitation);
      transaction.set(userInvitationRef, invitation);
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: "patient",
        orgId: organizationId,
        action: "patient_organization_access_requested",
        targetPath: `patients/${patientId}`,
        at: FieldValue.serverTimestamp(),
        meta: {},
      });
      return {
        status: "pending_org_review",
        organizationName: invitation.organizationName,
      };
    });
    return result;
  },
);

export const listPatientOrganizationInvitations = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const snapshot = await database.collection("users")
      .doc(auth.uid)
      .collection("organizationInvitations")
      .orderBy("requestedAt", "desc")
      .limit(100)
      .get();
    const userSnapshot = await database.collection("users").doc(auth.uid).get();
    const patientId = typeof userSnapshot.data()?.linkedPatientId === "string"
      ? userSnapshot.data()!.linkedPatientId as string
      : auth.uid;
    const consents = await database.collection("patients")
      .doc(patientId)
      .collection("consents")
      .limit(100)
      .get();
    const invitationData = new Map(
      snapshot.docs.map((doc) => [doc.id, doc.data()]),
    );
    const consentData = new Map(
      consents.docs.map((doc) => [doc.id, doc.data()]),
    );
    const organizationIds = new Set([
      ...invitationData.keys(),
      ...consentData.keys(),
    ]);
    const invitations = await Promise.all(
      [...organizationIds].map(async (organizationId) => {
        const invitation = invitationData.get(organizationId);
        const consent = consentData.get(organizationId);
        const expiresAt = consent?.expiresAt?.toDate?.();
        const consentActive =
          consent?.active === true &&
          expiresAt instanceof Date &&
          expiresAt.getTime() > Date.now();
        const organizationName =
          invitation?.organizationName ??
          (await database.collection("organizations").doc(organizationId).get())
            .data()?.name ??
          "Organization";
        return {
          organizationId,
          organizationName,
          patientUid: auth.uid,
          patientId,
          patientName: invitation?.patientName ??
            userSnapshot.data()?.displayName ??
            "Patient",
          patientEmail: String(auth.token.email ?? ""),
          status: consentActive ? "accepted" : invitation?.status ?? "revoked_by_patient",
          consentActive,
          requestedAt: invitation?.requestedAt?.toDate?.().toISOString() ?? null,
        };
      }),
    );
    return {
      invitations: invitations.filter((invitation) =>
        invitation.consentActive ||
        ["pending_org_review", "awaiting_patient_confirmation"]
          .includes(String(invitation.status))
      ),
    };
  },
);

export const listOrganizationPatientInvitations = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const { orgId, role } = await requireOrganizationAccess(auth.uid, auth.token);
    const organizationRef = database.collection("organizations").doc(orgId);
    const memberRef = organizationRef.collection("members").doc(auth.uid);
    const invitationsRef = organizationRef.collection("patientInvitations");
    const invitations = await database.runTransaction(async (transaction) => {
      const [member, snapshot] = await Promise.all([
        transaction.get(memberRef),
        transaction.get(invitationsRef.orderBy("requestedAt", "desc").limit(50)),
      ]);
      if (
        !member.exists ||
        member.data()?.status !== "active" ||
        member.data()?.role !== role
      ) {
        throw new HttpsError("permission-denied", "Organization membership is no longer active.");
      }
      return snapshot.docs
        .map((doc) => doc.data())
        .filter((data) => [
          "pending_org_review",
          "awaiting_patient_confirmation",
        ].includes(String(data.status)))
        .map((data) => ({
          patientUid: data.patientUid,
          patientId: data.patientId,
          patientName: data.patientName,
          patientEmail: data.patientEmail,
          status: data.status,
          requestedAt: data.requestedAt?.toDate?.().toISOString() ?? null,
        }));
    });
    return { invitations };
  },
);

export const respondToOrganizationPatientInvitation = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const parsed = organizationAccessResponseSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Patient invitation response is invalid.");
    }
    const { orgId, role } = await requireOrganizationAccess(auth.uid, auth.token);
    const organizationRef = database.collection("organizations").doc(orgId);
    const memberRef = organizationRef.collection("members").doc(auth.uid);
    const organizationInvitationRef = organizationRef
      .collection("patientInvitations")
      .doc(parsed.data.patientUid);
    const userInvitationRef = database.collection("users")
      .doc(parsed.data.patientUid)
      .collection("organizationInvitations")
      .doc(orgId);
    const auditRef = database.collection("auditLogs").doc();

    return database.runTransaction(async (transaction) => {
      const [member, organizationInvitation, userInvitation] =
        await Promise.all([
          transaction.get(memberRef),
          transaction.get(organizationInvitationRef),
          transaction.get(userInvitationRef),
        ]);
      if (
        !member.exists ||
        member.data()?.status !== "active" ||
        member.data()?.role !== role
      ) {
        throw new HttpsError("permission-denied", "Organization membership is no longer active.");
      }
      const invite = organizationInvitation.data();
      if (
        !organizationInvitation.exists ||
        !userInvitation.exists ||
        invite?.status !== "pending_org_review" ||
        userInvitation.data()?.status !== "pending_org_review"
      ) {
        throw new HttpsError("failed-precondition", "This patient invitation is no longer awaiting review.");
      }
      const status = parsed.data.accepted
        ? "awaiting_patient_confirmation"
        : "declined_by_organization";
      const response = {
        status,
        organizationRespondedAt: FieldValue.serverTimestamp(),
        organizationRespondedBy: auth.uid,
      };
      transaction.update(organizationInvitationRef, response);
      transaction.update(userInvitationRef, response);
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: role,
        orgId,
        action: parsed.data.accepted
          ? "organization_patient_access_accepted"
          : "organization_patient_access_declined",
        targetPath: `patients/${invite.patientId}`,
        at: FieldValue.serverTimestamp(),
        meta: {},
      });
      return { status };
    });
  },
);

export const respondToPatientOrganizationInvitation = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = requireVerifiedPatient(request);
    const parsed = patientOrganizationResponseSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Patient confirmation is invalid.");
    }
    if (parsed.data.accepted && !parsed.data.shareProfile) {
      throw new HttpsError(
        "failed-precondition",
        "Confirm profile sharing to grant this organization access, or decline the invitation.",
      );
    }
    const userRef = database.collection("users").doc(auth.uid);
    const userInvitationRef = userRef.collection("organizationInvitations")
      .doc(parsed.data.organizationId);
    const organizationRef = database.collection("organizations")
      .doc(parsed.data.organizationId);
    const organizationInvitationRef = organizationRef
      .collection("patientInvitations")
      .doc(auth.uid);
    const auditRef = database.collection("auditLogs").doc();

    return database.runTransaction(async (transaction) => {
      const [user, userInvitation, organizationInvitation, organization] =
        await Promise.all([
          transaction.get(userRef),
          transaction.get(userInvitationRef),
          transaction.get(organizationInvitationRef),
          transaction.get(organizationRef),
        ]);
      const invite = userInvitation.data();
      if (
        !user.exists ||
        !userInvitation.exists ||
        !organizationInvitation.exists ||
        !organization.exists ||
        invite?.status !== "awaiting_patient_confirmation" ||
        organizationInvitation.data()?.status !== "awaiting_patient_confirmation" ||
        invite.patientUid !== auth.uid
      ) {
        throw new HttpsError("failed-precondition", "This organization has not accepted the invitation or it is no longer available.");
      }
      const memberUid = invite.organizationRespondedBy;
      if (typeof memberUid !== "string") {
        throw new HttpsError("failed-precondition", "Organization approval is unavailable.");
      }
      const membershipRef = organizationRef.collection("members").doc(memberUid);
      const membership = await transaction.get(membershipRef);
      if (
        !membership.exists ||
        membership.data()?.status !== "active" ||
        !["doctor", "pharmacist"].includes(String(membership.data()?.role))
      ) {
        throw new HttpsError("failed-precondition", "Organization approval is no longer active.");
      }
      const patientRef = database.collection("patients").doc(invite.patientId);
      const consentRef = patientRef.collection("consents").doc(parsed.data.organizationId);
      const patientLinkRef = organizationRef.collection("patientLinks")
        .doc(invite.patientId);
      const patient = await transaction.get(patientRef);
      if (!patient.exists || patient.data()?.ownerUid !== auth.uid) {
        throw new HttpsError("permission-denied", "The linked patient record is unavailable.");
      }

      if (!parsed.data.accepted) {
        transaction.update(userInvitationRef, {
          status: "declined_by_patient",
          patientRespondedAt: FieldValue.serverTimestamp(),
        });
        transaction.update(organizationInvitationRef, {
          status: "declined_by_patient",
          patientRespondedAt: FieldValue.serverTimestamp(),
        });
        transaction.create(auditRef, {
          actorUid: auth.uid,
          actorRole: "patient",
          orgId: parsed.data.organizationId,
          action: "patient_organization_access_declined",
          targetPath: patientRef.path,
          at: FieldValue.serverTimestamp(),
          meta: {},
        });
        return { status: "declined_by_patient" };
      }

      const patientData = patient.data()!;
      const patientName = String(patientData.name ?? user.data()?.displayName ?? "Patient");
      const normalizedName = normalizePatientName(patientName);
      const birthYear = patientData.birthYear ?? null;
      const now = new Date();
      transaction.update(patientRef, {
        normalizedName,
        updatedAt: FieldValue.serverTimestamp(),
        version: (patientData.version ?? 1) + 1,
      });
      transaction.update(userRef, {
        displayName: patientName,
        linkedPatientId: patientRef.id,
        linkedPatientBirthYear: birthYear,
      });
      transaction.set(consentRef, {
        grantee: parsed.data.organizationId,
        grantedBy: auth.uid,
        scope: ["read_profile"],
        active: true,
        expiresAt: new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000),
        grantedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(patientLinkRef, {
        patientId: patientRef.id,
        normalizedName,
        birthYear,
        linkedBy: auth.uid,
        linkedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      const accepted = {
        status: "accepted",
        patientRespondedAt: FieldValue.serverTimestamp(),
        sharingConsent: "read_profile",
      };
      transaction.update(userInvitationRef, accepted);
      transaction.update(organizationInvitationRef, accepted);
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: "patient",
        orgId: parsed.data.organizationId,
        action: "patient_organization_access_confirmed",
        targetPath: patientRef.path,
        at: FieldValue.serverTimestamp(),
        meta: { sharingConsent: "read_profile" },
      });
      return { status: "accepted", patientId: patientRef.id };
    });
  },
);

export const createPatientAccountInvitation = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const parsed = createInvitationSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Patient invitation details are invalid.");
    }
    const { orgId, role } = await requireOrganizationAccess(auth.uid, auth.token);
    const patientId = parsed.data.patientId;
    const email = parsed.data.email.trim().toLowerCase();
    const organizationRef = database.collection("organizations").doc(orgId);
    const memberRef = organizationRef.collection("members").doc(auth.uid);
    const patientLinkRef = organizationRef.collection("patientLinks").doc(patientId);
    const patientRef = database.collection("patients").doc(patientId);
    const organization = await organizationRef.get();
    if (!organization.exists) {
      throw new HttpsError("not-found", "Organization profile is unavailable.");
    }
    const secret = randomBytes(24).toString("base64url");
    const code = `${patientId}.${secret}`;
    const invitationRef = patientRef
      .collection("accountInvitations")
      .doc(hashInvitationCode(secret));
    const auditRef = database.collection("auditLogs").doc();

    await database.runTransaction(async (transaction) => {
      const [member, link, patient] = await Promise.all([
        transaction.get(memberRef),
        transaction.get(patientLinkRef),
        transaction.get(patientRef),
      ]);
      if (
        !member.exists ||
        member.data()?.status !== "active" ||
        member.data()?.role !== role
      ) {
        throw new HttpsError("permission-denied", "Organization membership is no longer active.");
      }
      if (!link.exists || !patient.exists) {
        throw new HttpsError("permission-denied", "This patient is not accessible to your organization.");
      }
      if (
        typeof patient.data()?.ownerUid === "string" &&
        patient.data()?.ownerUid.length > 0
      ) {
        throw new HttpsError("already-exists", "This patient already has an account linked.");
      }
      transaction.create(invitationRef, {
        patientId,
        orgId,
        email,
        status: "pending",
        createdBy: auth.uid,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      });
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: role,
        orgId,
        action: "patient_account_invitation_created",
        targetPath: `patients/${patientId}`,
        at: FieldValue.serverTimestamp(),
        meta: {},
      });
    });

    return { code };
  },
);

export const previewPatientAccountInvitation = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = requireVerifiedPatient(request);
    const parsed = invitationCodeSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Patient invitation code is invalid.");
    }
    const invitationRef = invitationReference(parsed.data.code);
    const invitationSnapshot = await invitationRef.get();
    if (!invitationSnapshot.exists) {
      throw new HttpsError("not-found", "This invitation code is invalid or expired.");
    }
    const data = invitationSnapshot.data()!;
    if (
      data.status !== "pending" ||
      !(data.expiresAt?.toDate?.() instanceof Date) ||
      data.expiresAt.toDate().getTime() <= Date.now() ||
      data.email !== String(auth.token.email).trim().toLowerCase()
    ) {
      throw new HttpsError("permission-denied", "This invitation is expired or belongs to a different email.");
    }
    const [patient, organization] = await Promise.all([
      database.collection("patients").doc(data.patientId).get(),
      database.collection("organizations").doc(data.orgId).get(),
    ]);
    if (!patient.exists || !organization.exists) {
      throw new HttpsError("not-found", "The invited patient or organization is unavailable.");
    }
    return {
      patientId: data.patientId,
      patientName: patient.data()?.name ?? "Patient",
      organizationName: organization.data()?.name ?? "Organization",
      organizationCity: organization.data()?.city ?? "",
    };
  },
);

export const respondToPatientAccountInvitation = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = requireVerifiedPatient(request);
    const parsed = invitationResponseSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Patient invitation response is invalid.");
    }
    const invitationRef = invitationReference(parsed.data.code);
    const invitationSnapshot = await invitationRef.get();
    if (!invitationSnapshot.exists) {
      throw new HttpsError("not-found", "This invitation code is invalid or expired.");
    }
    const patientRef = invitationRef.parent.parent;
    if (!patientRef) {
      throw new HttpsError("internal", "Patient invitation record is invalid.");
    }
    const userRef = database.collection("users").doc(auth.uid);
    const organizationRef = database.collection("organizations").doc(
      invitationSnapshot.data()!.orgId,
    );
    const auditRef = database.collection("auditLogs").doc();
    const result = await database.runTransaction(async (transaction) => {
      const [invitation, patient, user, organization] = await Promise.all([
        transaction.get(invitationRef),
        transaction.get(patientRef),
        transaction.get(userRef),
        transaction.get(organizationRef),
      ]);
      const data = invitation.data();
      if (
        !invitation.exists ||
        data?.status !== "pending" ||
        !(data.expiresAt?.toDate?.() instanceof Date) ||
        data.expiresAt.toDate().getTime() <= Date.now() ||
        data.email !== String(auth.token.email).trim().toLowerCase()
      ) {
        throw new HttpsError("permission-denied", "This invitation is expired or belongs to a different email.");
      }
      if (!patient.exists || !user.exists || !organization.exists) {
        throw new HttpsError("failed-precondition", "Complete patient account setup before responding.");
      }
      const patientData = patient.data()!;
      if (
        typeof patientData.ownerUid === "string" &&
        patientData.ownerUid !== auth.uid
      ) {
        throw new HttpsError("already-exists", "This patient record is already linked to another account.");
      }
      transaction.update(invitationRef, {
        status: parsed.data.accepted ? "accepted" : "declined",
        respondedAt: FieldValue.serverTimestamp(),
        respondedBy: auth.uid,
      });
      if (parsed.data.accepted) {
        transaction.update(patientRef, {
          ownerUid: auth.uid,
          updatedAt: FieldValue.serverTimestamp(),
          version: (patientData.version ?? 1) + 1,
        });
        transaction.update(userRef, {
          displayName: patientData.name,
          linkedPatientId: patientRef.id,
          linkedPatientBirthYear: patientData.birthYear ?? null,
          linkedOrganizationId: data.orgId,
          linkedOrganizationName: organization.data()?.name ?? "Organization",
          linkedOrganizationCity: organization.data()?.city ?? "",
        });
        if (parsed.data.shareDerivedProfile) {
          transaction.set(patientRef.collection("consents").doc(data.orgId), {
            grantee: data.orgId,
            grantedBy: auth.uid,
            scope: ["read_profile"],
            active: true,
            expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000),
            grantedAt: FieldValue.serverTimestamp(),
          });
        }
      }
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: "patient",
        orgId: data.orgId,
        action: parsed.data.accepted
          ? "patient_account_invitation_accepted"
          : "patient_account_invitation_declined",
        targetPath: patientRef.path,
        at: FieldValue.serverTimestamp(),
        meta: { derivedProfileSharing: parsed.data.accepted && parsed.data.shareDerivedProfile },
      });
      return { accepted: parsed.data.accepted, patientId: parsed.data.accepted ? patientRef.id : null };
    });
    return result;
  },
);

export const revokePatientOrganizationConsent = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const parsed = revokeOrganizationConsentSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Organization reference is invalid.");
    }
    const userRef = database.collection("users").doc(auth.uid);
    const auditRef = database.collection("auditLogs").doc();
    const result = await database.runTransaction(async (transaction) => {
      const user = await transaction.get(userRef);
      const userData = user.data();
      const patientId = typeof userData?.linkedPatientId === "string"
        ? userData.linkedPatientId
        : auth.uid;
      const orgId = parsed.data.organizationId;
      if (!user.exists) {
        throw new HttpsError("failed-precondition", "No linked patient record is available.");
      }
      const patientRef = database.collection("patients").doc(patientId);
      const consentRef = patientRef.collection("consents").doc(orgId);
      const invitationRef = userRef.collection("organizationInvitations").doc(orgId);
      const organizationInvitationRef = database.collection("organizations")
        .doc(orgId)
        .collection("patientInvitations")
        .doc(auth.uid);
      const patientLinkRef = database.collection("organizations")
        .doc(orgId)
        .collection("patientLinks")
        .doc(patientId);
      const [patient, consent, invitation, organizationInvitation] = await Promise.all([
        transaction.get(patientRef),
        transaction.get(consentRef),
        transaction.get(invitationRef),
        transaction.get(organizationInvitationRef),
      ]);
      if (!patient.exists || patient.data()?.ownerUid !== auth.uid) {
        throw new HttpsError("permission-denied", "You cannot change this patient record's consent.");
      }
      if (!consent.exists || consent.data()?.active !== true) {
        return { revoked: false };
      }
      transaction.update(consentRef, {
        active: false,
        revokedAt: FieldValue.serverTimestamp(),
      });
      transaction.delete(patientLinkRef);
      if (invitation.exists) {
        transaction.update(invitationRef, {
          status: "revoked_by_patient",
          patientRespondedAt: FieldValue.serverTimestamp(),
        });
      }
      if (organizationInvitation.exists) {
        transaction.update(organizationInvitationRef, {
          status: "revoked_by_patient",
          patientRespondedAt: FieldValue.serverTimestamp(),
        });
      }
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: "patient",
        orgId,
        action: "patient_organization_consent_revoked",
        targetPath: consentRef.path,
        at: FieldValue.serverTimestamp(),
        meta: {},
      });
      return { revoked: true };
    });
    return result;
  },
);

export const registerOrganizationPatient = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const parsed = registerPatientSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Patient details are invalid.");
    }
    const { orgId, role } = await requireOrganizationAccess(
      auth.uid,
      auth.token,
    );
    const normalizedName = normalizePatientName(parsed.data.name);
    if (normalizedName.length < 2) {
      throw new HttpsError(
        "invalid-argument",
        "Enter a patient name containing at least two letters or digits.",
      );
    }
    const organizationRef = database.collection("organizations").doc(orgId);
    const memberRef = organizationRef.collection("members").doc(auth.uid);
    const idempotencyRef = organizationRef
      .collection("idempotency")
      .doc(parsed.data.idempotencyKey);
    const patientId = database.collection("patients").doc().id;
    const patientRef = database.collection("patients").doc(patientId);
    const patientLinkRef = organizationRef
      .collection("patientLinks")
      .doc(patientId);
    const auditRef = database.collection("auditLogs").doc();

    const result = await database.runTransaction(async (transaction) => {
      const [member, idempotency, duplicate] = await Promise.all([
        transaction.get(memberRef),
        transaction.get(idempotencyRef),
        transaction.get(
          organizationRef
            .collection("patientLinks")
            .where("normalizedName", "==", normalizedName)
            .where("birthYear", "==", parsed.data.birthYear ?? null)
            .limit(1),
        ),
      ]);
      if (
        !member.exists ||
        member.data()?.status !== "active" ||
        member.data()?.role !== role
      ) {
        throw new HttpsError(
          "permission-denied",
          "Organization membership is no longer active.",
        );
      }
      if (idempotency.exists) {
        const previous = idempotency.data()!;
        if (
          previous.normalizedName !== normalizedName ||
          previous.birthYear !== (parsed.data.birthYear ?? null)
        ) {
          throw new HttpsError(
            "already-exists",
            "This request key was already used for different patient details.",
          );
        }
        return {
          patientId: previous.patientId as string,
          created: false,
        };
      }
      if (!duplicate.empty) {
        throw new HttpsError(
          "already-exists",
          "A patient with this normalized name is already accessible. Search and select the existing record.",
        );
      }
      transaction.create(patientRef, {
        name: parsed.data.name,
        normalizedName,
        birthYear: parsed.data.birthYear ?? null,
        createdBy: auth.uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        version: 1,
        vcfStatus: "not_uploaded",
        analysisStatus: "not_started",
      });
      transaction.create(patientLinkRef, {
        patientId,
        normalizedName,
        birthYear: parsed.data.birthYear ?? null,
        linkedBy: auth.uid,
        linkedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(idempotencyRef, {
        patientId,
        normalizedName,
        birthYear: parsed.data.birthYear ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: role,
        orgId,
        action: "organization_patient_registered",
        targetPath: `patients/${patientId}`,
        at: FieldValue.serverTimestamp(),
        meta: {},
      });
      return { patientId, created: true };
    });
    return result;
  },
);

export const getOrganizationPatientWorkspace = onCall(
  { enforceAppCheck: true, region },
  async (request) => {
    const auth = authRequired(request);
    const parsed = z.object({ patientId: z.string().min(1).max(128) })
      .strict()
      .safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Patient reference is invalid.");
    }
    const { orgId, role } = await requireOrganizationAccess(
      auth.uid,
      auth.token,
    );
    const linkRef = database
      .collection("organizations")
      .doc(orgId)
      .collection("patientLinks")
      .doc(parsed.data.patientId);
    const memberRef = database
      .collection("organizations")
      .doc(orgId)
      .collection("members")
      .doc(auth.uid);
    const auditRef = database.collection("auditLogs").doc();
    const patient = await database.runTransaction(async (transaction) => {
      const [member, link, patientSnapshot] = await Promise.all([
        transaction.get(memberRef),
        transaction.get(linkRef),
        transaction.get(
          database.collection("patients").doc(parsed.data.patientId),
        ),
      ]);
      if (
        !member.exists ||
        member.data()?.status !== "active" ||
        member.data()?.role !== role
      ) {
        throw new HttpsError(
          "permission-denied",
          "Organization membership is no longer active.",
        );
      }
      if (!link.exists) {
        throw new HttpsError(
          "permission-denied",
          "This patient is not accessible to your organization.",
        );
      }
      if (!patientSnapshot.exists) {
        throw new HttpsError("not-found", "Patient record is unavailable.");
      }
      const patientData = patientSnapshot.data()!;
      if (typeof patientData.ownerUid === "string") {
        const consent = await transaction.get(
          database.collection("patients")
            .doc(parsed.data.patientId)
            .collection("consents")
            .doc(orgId),
        );
        const expiresAt = consent.data()?.expiresAt?.toDate?.();
        if (
          consent.data()?.active !== true ||
          !(expiresAt instanceof Date) ||
          expiresAt.getTime() <= Date.now()
        ) {
          throw new HttpsError(
            "permission-denied",
            "Patient profile sharing consent is not active.",
          );
        }
      }
      transaction.create(auditRef, {
        actorUid: auth.uid,
        actorRole: role,
        orgId,
        action: "organization_patient_record_viewed",
        targetPath: `patients/${parsed.data.patientId}`,
        at: FieldValue.serverTimestamp(),
        meta: {},
      });
      return patientSnapshot.data()!;
    });
    return {
      patientId: parsed.data.patientId,
      name: patient.name,
      birthYear: patient.birthYear ?? null,
      vcfStatus: patient.vcfStatus ?? "not_uploaded",
      analysisStatus: patient.analysisStatus ?? "not_started",
      latestReportAt: patient.latestReportAt?.toDate?.().toISOString() ?? null,
      reportCount: patient.reportCount ?? 0,
      prescriptionCount: patient.prescriptionCount ?? 0,
      limitations:
        "Raw VCF data stays on the patient's device. Cloud analysis is unavailable until a clinically validated, privacy-approved processing pipeline is configured.",
    };
  },
);
