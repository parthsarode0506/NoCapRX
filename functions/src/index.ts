import { initializeApp } from "firebase-admin/app";
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
    const { orgId } = await requireOrganizationAccess(auth.uid, auth.token);
    const organization = await database.collection("organizations").doc(orgId).get();
    if (!organization.exists) {
      throw new HttpsError("not-found", "Organization profile is unavailable.");
    }
    return {
      organizationId: orgId,
      name: organization.data()?.name ?? "Organization",
    };
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
