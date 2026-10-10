import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
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
  await assertSucceeds(updateDoc(profile, { accountType: 'patient' }));
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
});

test('a user can record required privacy-notice acknowledgment', async () => {
  const userDb = testEnvironment.authenticatedContext('consent-user').firestore();
  await assertSucceeds(setDoc(doc(userDb, 'users/consent-user/consents/privacy_notice'), {
    accepted: true,
    noticeVersion: '1.0',
    createdAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(
    doc(userDb, 'users/consent-user/consents/privacy_notice'),
    { accepted: false },
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
