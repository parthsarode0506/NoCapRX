import admin from 'firebase-admin';

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'on-devicerx',
  });
}

const auth = admin.auth();
const db = admin.firestore();

async function deleteAllUsers() {
  console.log('Fetching users from Firebase Auth...');
  let nextPageToken;
  let totalDeleted = 0;
  do {
    const listUsersResult = await auth.listUsers(1000, nextPageToken);
    const uids = listUsersResult.users.map((user) => user.uid);
    if (uids.length > 0) {
      const deleteResult = await auth.deleteUsers(uids);
      totalDeleted += deleteResult.successCount;
      console.log(`Deleted ${deleteResult.successCount} users.`);
    }
    nextPageToken = listUsersResult.pageToken;
  } while (nextPageToken);
  console.log(`Finished deleting users. Total deleted: ${totalDeleted}`);
}

async function deleteAllCollections() {
  console.log('Fetching root collections in Firestore...');
  const collections = await db.listCollections();
  for (const col of collections) {
    console.log(`Deleting collection: ${col.id}...`);
    await db.recursiveDelete(col);
    console.log(`Deleted collection: ${col.id}.`);
  }
  console.log('All Firestore collections deleted.');
}

async function main() {
  try {
    console.log('Starting Firebase wipe for project: ' + (process.env.FIREBASE_PROJECT_ID || 'on-devicerx'));
    await deleteAllUsers();
    await deleteAllCollections();
    console.log('Successfully removed all data and users from Firebase!');
  } catch (err) {
    console.error('Error during Firebase wipe:', err.message);
    console.log('\nAlternative ways to clear Firebase:');
    console.log('1. Firebase Console:');
    console.log('   - Authentication tab -> Select all users -> Delete accounts');
    console.log('   - Cloud Firestore tab -> Delete collections (or delete database)');
    console.log('2. Firebase CLI:');
    console.log('   - npx firebase-tools firestore:delete --all-collections -y --project on-devicerx');
  }
}

main();
