const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Admin SDK once
try {
  admin.initializeApp();
} catch (_) {}

// Sends FCM when a per-user notification doc is created
exports.sendUserNotificationPush = functions.firestore
  .document('users/{userId}/notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const userId = context.params.userId;

    // Fetch user's FCM tokens
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const tokens = (userDoc.get('fcmTokens') || []).filter(Boolean);
    if (!tokens.length) {
      return null;
    }

    const title = data.title || 'Notification';
    const body = data.body || '';

    const message = {
      tokens,
      notification: { title, body },
      data: {
        type: (data.type || 'general').toString(),
        groupId: (data.groupId || '').toString(),
        notificationId: snap.id,
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    // Remove invalid tokens
    const invalidTokens = [];
    response.responses.forEach((res, idx) => {
      if (!res.success) {
        const code = res.error && res.error.code;
        if (code && (
          code.includes('registration-token-not-registered') ||
          code.includes('invalid-argument') ||
          code.includes('mismatch')
        )) {
          invalidTokens.push(tokens[idx]);
        }
      }
    });
    if (invalidTokens.length) {
      await admin.firestore().collection('users').doc(userId).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      });
    }
    return null;
  });


