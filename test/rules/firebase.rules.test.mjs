import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  getDocs,
  collection,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

const projectId = 'demo-nocaprx';
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
    },
    storage: {
      rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await testEnvironment?.cleanup();
});

test('a user can save a workspace preference without gaining authorization', async () => {
  const userDb = testEnvironment.authenticatedContext('patient-1').firestore();
  const profile = doc(userDb, 'users/patient-1');

  await assertSucceeds(setDoc(profile, {
    displayName: 'Patient',
    accountType: 'patient',
    locale: 'en',
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(profile, { displayName: 'Updated patient' }));
  await assertSucceeds(updateDoc(profile, { accountType: 'organization' }));
  await assertSucceeds(updateDoc(profile, {
    organizationName: 'Sample Hospital',
    city: 'Pune',
  }));
  await assertSucceeds(updateDoc(profile, { accountType: 'patient' }));
});

test('organization signup profile and privacy acknowledgment can both be stored', async () => {
  const userDb = testEnvironment.authenticatedContext('organization-signup').firestore();
  await assertSucceeds(setDoc(doc(userDb, 'users/organization-signup'), {
    displayName: 'Org User',
    accountType: 'organization',
    organizationName: 'Sample Hospital',
    city: 'Pune',
    locale: 'en',
    createdAt: serverTimestamp(),
  }));
  const privacyNotice = doc(
    userDb,
    'users/organization-signup/consents/privacy_notice',
  );
  await assertSucceeds(runTransaction(userDb, async (transaction) => {
    const existingNotice = await transaction.get(privacyNotice);
    assert.equal(existingNotice.exists(), false);
    transaction.set(privacyNotice, {
      accepted: true,
      noticeVersion: '1.1',
      createdAt: serverTimestamp(),
    });
  }));
  await assertSucceeds(setDoc(
    doc(userDb, 'organizationDirectory/organization-signup'),
    {
      organizationId: 'organization-signup',
      name: 'Sample Hospital',
      city: 'Pune',
      normalizedName: 'sample hospital',
      active: true,
      selfRegistered: true,
      updatedAt: serverTimestamp(),
    },
  ));

  const patientDb = testEnvironment.authenticatedContext('directory-patient').firestore();
  const listing = await getDoc(
    doc(patientDb, 'organizationDirectory/organization-signup'),
  );
  assert.equal(listing.data()?.name, 'Sample Hospital');
  assert.equal(listing.data()?.selfRegistered, true);
  const searchResults = await getDocs(query(
    collection(patientDb, 'organizationDirectory'),
    where('active', '==', true),
    orderBy('normalizedName'),
  ));
  assert.equal(searchResults.docs.length, 1);
  assert.equal(searchResults.docs[0].data().selfRegistered, true);
});

test('a user cannot assign a privileged or unsupported account type', async () => {
  const userDb = testEnvironment.authenticatedContext('patient-2').firestore();
  const profile = doc(userDb, 'users/patient-2');

  await assertSucceeds(setDoc(profile, {
    displayName: 'Patient',
    accountType: 'patient',
    createdAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(profile, { accountType: 'doctor' }));
  await assertFails(updateDoc(profile, { accountType: 'platform_admin' }));
  await assertFails(updateDoc(profile, { linkedPatientId: 'forged-link' }));
  await assertFails(updateDoc(profile, { linkedPatientBirthYear: 1990 }));
});

test('a user can record required privacy-notice acknowledgment', async () => {
  const userDb = testEnvironment.authenticatedContext('consent-user').firestore();
  await assertSucceeds(setDoc(doc(userDb, 'users/consent-user/consents/privacy_notice'), {
    accepted: true,
    noticeVersion: '1.1',
    createdAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(
    doc(userDb, 'users/consent-user/consents/privacy_notice'),
    { accepted: false },
  ));
});

test('an existing privacy acknowledgment can be upgraded to the public-directory notice', async () => {
  const noticeUpgradeRef = doc(
    testEnvironment.authenticatedContext('notice-upgrade').firestore(),
    'users/notice-upgrade/consents/privacy_notice',
  );
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(
      context.firestore(),
      'users/notice-upgrade/consents/privacy_notice',
    ), {
      accepted: true,
      noticeVersion: '1.0',
      createdAt: new Date(),
    });
  });
  await assertSucceeds(updateDoc(noticeUpgradeRef, {
    noticeVersion: '1.1',
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(noticeUpgradeRef, {
    accepted: false,
  }));
});

test('a patient cannot publish an organization directory entry', async () => {
  const patientDb = testEnvironment.authenticatedContext('directory-forger').firestore();
  await assertFails(setDoc(
    doc(patientDb, 'organizationDirectory/directory-forger'),
    {
      organizationId: 'directory-forger',
      name: 'Fake Hospital',
      city: 'Pune',
      normalizedName: 'fake hospital',
      active: true,
      selfRegistered: true,
      updatedAt: serverTimestamp(),
    },
  ));
});

test('a user cannot create a profile with client-assigned role or email', async () => {
  const userDb = testEnvironment.authenticatedContext('patient-2').firestore();

  await assertFails(setDoc(doc(userDb, 'users/patient-2'), {
    displayName: 'Patient',
    email: 'patient@example.invalid',
    role: 'platform_admin',
    createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(userDb, 'users/patient-2'), {
    displayName: 'Patient',
    accountType: 'platform_admin',
    createdAt: serverTimestamp(),
  }));
});

test('professional credential verification has no client-write path', async () => {
  const userDb = testEnvironment.authenticatedContext('no-verification').firestore();
  await assertFails(setDoc(doc(userDb, 'verifications/no-verification'), {
    type: 'doctor',
    registrationNumber: 'TEST-12345',
    council: 'Example',
    institution: 'Example Clinic',
    docPaths: [],
    submittedAt: serverTimestamp(),
    status: 'pending',
  }));
});

test('a user cannot read another user profile', async () => {
  const otherUserDb = testEnvironment.authenticatedContext('patient-2').firestore();

  await assertFails(setDoc(
    doc(otherUserDb, 'users/patient-1'),
    { displayName: 'Unauthorized', createdAt: serverTimestamp() },
  ));
});

test('unauthenticated access to user profiles is denied', async () => {
  const anonymousDb = testEnvironment.unauthenticatedContext().firestore();

  await assertFails(setDoc(
    doc(anonymousDb, 'users/anonymous'),
    { displayName: 'Anonymous', createdAt: serverTimestamp() },
  ));
});

test('even a verified lab technician cannot upload a raw VCF file', async () => {
  const labStorage = testEnvironment
    .authenticatedContext('lab-tech', {
      role: 'lab_tech',
      verified: true,
      orgId: 'org-1',
    })
    .storage();

  await assertFails(uploadBytes(
    ref(labStorage, 'labUploads/org-1/order-1/patient.vcf'),
    new Uint8Array([35, 35, 102, 105, 108, 101, 102, 111, 114, 109, 97, 116]),
    { contentType: 'text/vcf' },
  ));
});

test('professional registration documents have no upload path', async () => {
  const userStorage = testEnvironment.authenticatedContext('app-user').storage();
  await assertFails(uploadBytes(
    ref(userStorage, 'verifications/app-user/registration.pdf'),
    new Uint8Array([37, 80, 68, 70]),
    { contentType: 'application/pdf' },
  ));
});

test('report updates remain restricted to bounded PDF files', async () => {
  const userStorage = testEnvironment.authenticatedContext('report-owner').storage();
  const reportRef = ref(userStorage, 'reports/report-owner/report-1/report.pdf');
  await assertSucceeds(uploadBytes(reportRef, new Uint8Array([37, 80, 68, 70]), {
    contentType: 'application/pdf',
  }));
  await assertFails(uploadBytes(reportRef, new Uint8Array([1, 2, 3]), {
    contentType: 'application/octet-stream',
  }));
});

test('profile photos can only be read by the owner or platform admins', async () => {
  const ownerStorage = testEnvironment.authenticatedContext('patient-photo').storage();
  const photoRef = ref(ownerStorage, 'profiles/patient-photo/avatar.png');
  await assertSucceeds(uploadBytes(photoRef, new Uint8Array([137, 80, 78, 71]), {
    contentType: 'image/png',
  }));
  await assertSucceeds(getBytes(photoRef));

  const otherUserStorage = testEnvironment.authenticatedContext('another-user').storage();
  await assertFails(getBytes(ref(otherUserStorage, 'profiles/patient-photo/avatar.png')));

  const anonymousStorage = testEnvironment.unauthenticatedContext().storage();
  await assertFails(getBytes(ref(anonymousStorage, 'profiles/patient-photo/avatar.png')));
});

test('organization patient data and audit logs are callable-only', async () => {
  const organizationDb = testEnvironment.authenticatedContext('doctor-1', {
    role: 'doctor',
    verified: true,
    orgId: 'org-1',
  }).firestore();

  await assertFails(getDoc(doc(
    organizationDb,
    'organizations/org-1/patientLinks/patient-1',
  )));
  await assertFails(setDoc(doc(
    organizationDb,
    'organizations/org-1/patientLinks/patient-1',
  ), { patientId: 'patient-1' }));
  await assertFails(getDoc(doc(organizationDb, 'patients/patient-1')));
  await assertFails(setDoc(doc(organizationDb, 'auditLogs/fake-event'), {
    actorUid: 'doctor-1',
    action: 'forged',
  }));
});

test('organization links, invitations, and consent cannot be changed by clients', async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'patients/patient-owner'), {
      ownerUid: 'patient-owner',
      name: 'Sample Patient',
    });
  });

  const patientDb = testEnvironment
    .authenticatedContext('patient-owner')
    .firestore();
  const invitation = {
    organizationId: 'org-1',
    organizationName: 'Sample Hospital',
    patientUid: 'patient-owner',
    patientId: 'patient-owner',
    patientName: 'Sample Patient',
    status: 'pending_org_review',
    requestedAt: serverTimestamp(),
  };

  await assertFails(setDoc(
    doc(patientDb, 'users/patient-owner/organizationInvitations/org-1'),
    invitation,
  ));
  await assertFails(setDoc(
    doc(patientDb, 'organizations/org-1/patientInvitations/patient-owner'),
    invitation,
  ));
  await assertFails(setDoc(
    doc(patientDb, 'organizations/org-1/patientLinks/patient-owner'),
    {
      patientId: 'patient-owner',
      name: 'Sample Patient',
      normalizedName: 'sample patient',
      linkedAt: serverTimestamp(),
    },
  ));
  await assertFails(setDoc(
    doc(patientDb, 'patients/patient-owner/consents/org-1'),
    {
      grantee: 'org-1',
      scope: ['read_profile'],
      active: true,
      expiresAt: new Date(Date.now() + 60_000),
      grantedAt: serverTimestamp(),
    },
  ));
});

test('organization patient-profile reads are callable-only even with active consent', async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();
    await setDoc(doc(adminDb, 'patients/patient-consent'), {
      ownerUid: 'patient-owner',
      name: 'Patient',
      version: 1,
    });
    await setDoc(doc(adminDb, 'patients/patient-consent/consents/org-1'), {
      grantee: 'org-1',
      scope: ['read_profile'],
      active: true,
      expiresAt: new Date(Date.now() + 60_000),
    });
    await setDoc(doc(adminDb, 'organizations/org-1/members/doctor-consent'), {
      role: 'doctor',
      status: 'active',
    });
  });

  const organizationDb = testEnvironment.authenticatedContext('doctor-consent', {
    role: 'doctor',
    verified: true,
    orgId: 'org-1',
  }).firestore();
  const patientRef = doc(organizationDb, 'patients/patient-consent');
  await assertFails(getDoc(patientRef));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(
      doc(context.firestore(), 'patients/patient-consent/consents/org-1'),
      { active: false },
    );
  });
  await assertFails(getDoc(patientRef));
});

test('a verified organization claim without active membership grants no patient access', async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();
    await setDoc(doc(adminDb, 'patients/patient-no-membership'), {
      ownerUid: 'patient-owner',
      name: 'Patient',
    });
    await setDoc(doc(adminDb, 'patients/patient-no-membership/consents/org-2'), {
      grantee: 'org-2',
      scope: ['read_profile'],
      active: true,
      expiresAt: new Date(Date.now() + 60_000),
    });
    await setDoc(doc(adminDb, 'organizations/org-2/members/doctor-no-membership'), {
      role: 'doctor',
      status: 'suspended',
    });
  });

  const organizationDb = testEnvironment.authenticatedContext('doctor-no-membership', {
    role: 'doctor',
    verified: true,
    orgId: 'org-2',
  }).firestore();
  await assertFails(getDoc(doc(organizationDb, 'patients/patient-no-membership')));
});
