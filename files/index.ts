import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { GeoFirestore } from "geofirestore";
import * as geofire from "geofire-common";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ─── Constants ────────────────────────────────────────────────────────────────

const RADIUS_KM = 0.5;           // 500m
const ACTIVE_THRESHOLD_MIN = 5;  // users active within last 5 minutes

// ─── triggerSos ──────────────────────────────────────────────────────────────
// Called by Flutter client on SOS confirm.
// Creates SOS_EVENT, geo-queries nearby users, dispatches FCM.

export const triggerSos = functions
  .region("asia-south1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required");
    }

    const uid = context.auth.uid;
    const lat: number = data.lat;
    const lng: number = data.lng;
    const accuracyFlag: string = data.accuracy_flag ?? "current";

    if (!lat || !lng) {
      throw new functions.https.HttpsError("invalid-argument", "Location required");
    }

    // ── 1. Create SOS_EVENT ──────────────────────────────────────────────────
    const sosRef = db.collection("sos_events").doc();
    const geohash = geofire.geohashForLocation([lat, lng]);

    await sosRef.set({
      triggered_by: uid,
      location: new admin.firestore.GeoPoint(lat, lng),
      geohash,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "ACTIVE",
      responders: [],
      accuracy_flag: accuracyFlag,
    });

    functions.logger.info(`SOS created: ${sosRef.id} by ${uid}`);

    // ── 2. Geo-query nearby available users ──────────────────────────────────
    const center = [lat, lng] as [number, number];
    const bounds = geofire.geohashQueryBounds(center, RADIUS_KM * 1000);
    const activeThreshold = new Date(Date.now() - ACTIVE_THRESHOLD_MIN * 60 * 1000);

    const queries = bounds.map((b) =>
      db.collection("users")
        .orderBy("geohash")
        .startAt(b[0])
        .endAt(b[1])
        .where("is_available_for_help", "==", true)
        .where("last_active", ">=", admin.firestore.Timestamp.fromDate(activeThreshold))
        .get()
    );

    const snapshots = await Promise.all(queries);

    // Second-pass Haversine filter (geohash cells aren't perfect circles)
    const nearbyUsers: admin.firestore.DocumentData[] = [];
    for (const snap of snapshots) {
      for (const doc of snap.docs) {
        if (doc.id === uid) continue; // skip the person triggering SOS

        const userLoc = doc.data().location as admin.firestore.GeoPoint;
        const distanceKm = geofire.distanceBetween(
          [userLoc.latitude, userLoc.longitude],
          center,
        );

        if (distanceKm <= RADIUS_KM) {
          nearbyUsers.push({ id: doc.id, ...doc.data(), distance_km: distanceKm });
        }
      }
    }

    functions.logger.info(`Found ${nearbyUsers.length} nearby users for SOS ${sosRef.id}`);

    // ── 3. Dispatch FCM ──────────────────────────────────────────────────────
    if (nearbyUsers.length > 0) {
      // Get FCM tokens for nearby users
      const tokenDocs = await Promise.all(
        nearbyUsers.map((u) => db.collection("users").doc(u.id).get())
      );

      const tokens = tokenDocs
        .map((d) => d.data()?.fcm_token)
        .filter(Boolean) as string[];

      if (tokens.length > 0) {
        // Fetch triggering user's name
        const triggerUserDoc = await db.collection("users").doc(uid).get();
        const triggerUserName = triggerUserDoc.data()?.name ?? "Someone";

        const message: admin.messaging.MulticastMessage = {
          tokens,
          data: {
            type: "SOS_ALERT",
            sos_id: sosRef.id,
            user_name: triggerUserName,
            lat: String(lat),
            lng: String(lng),
            distance: `${(nearbyUsers[0].distance_km * 1000).toFixed(0)}m`,
          },
          android: {
            priority: "high",
            notification: {
              title: "🚨 SOS Alert Nearby",
              body: `${triggerUserName} needs help nearby`,
              channelId: "sos_alerts",
            },
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: "🚨 SOS Alert Nearby",
                  body: `${triggerUserName} needs help nearby`,
                },
                sound: "default",
                contentAvailable: true,
              },
            },
          },
        };

        const response = await messaging.sendEachForMulticast(message);
        functions.logger.info(
          `FCM sent: ${response.successCount} success, ${response.failureCount} failures`
        );

        // Clean up stale tokens
        await _cleanStaleFcmTokens(tokens, response, nearbyUsers.map((u) => u.id));
      }
    } else {
      // Fallback: no nearby users — notify emergency contacts via function
      functions.logger.warn(`No nearby users for SOS ${sosRef.id} — triggering fallback`);
      // Emergency contact SMS handled client-side via url_launcher + SMS intent
    }

    return { sos_id: sosRef.id };
  });

// ─── autoExpireSos ───────────────────────────────────────────────────────────
// Runs every 5 minutes. Marks SOS events older than 30 minutes as EXPIRED.

export const autoExpireSos = functions
  .region("asia-south1")
  .pubsub.schedule("every 5 minutes")
  .onRun(async () => {
    const expireThreshold = new Date(Date.now() - 30 * 60 * 1000);

    const stale = await db.collection("sos_events")
      .where("status", "==", "ACTIVE")
      .where("timestamp", "<=", admin.firestore.Timestamp.fromDate(expireThreshold))
      .get();

    const batch = db.batch();
    stale.docs.forEach((doc) => {
      batch.update(doc.ref, { status: "EXPIRED" });
    });

    await batch.commit();
    functions.logger.info(`Expired ${stale.size} stale SOS events`);
  });

// ─── onSosAccepted ───────────────────────────────────────────────────────────
// Firestore trigger: when a responder is added, notify the victim.

export const onSosAccepted = functions
  .region("asia-south1")
  .firestore.document("sos_events/{sosId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    const newResponders: string[] = after.responders ?? [];
    const oldResponders: string[] = before.responders ?? [];

    if (newResponders.length <= oldResponders.length) return; // no new responder

    const newResponderId = newResponders.find((r) => !oldResponders.includes(r));
    if (!newResponderId) return;

    // Notify the person who triggered the SOS
    const victimId = after.triggered_by as string;
    const victimDoc = await db.collection("users").doc(victimId).get();
    const victimToken = victimDoc.data()?.fcm_token;
    if (!victimToken) return;

    const responderDoc = await db.collection("users").doc(newResponderId).get();
    const responderName = responderDoc.data()?.name ?? "Someone";

    await messaging.send({
      token: victimToken,
      data: {
        type: "RESPONDER_ACCEPTED",
        sos_id: context.params.sosId,
        responder_name: responderName,
        responder_count: String(newResponders.length),
      },
      android: {
        priority: "high",
        notification: {
          title: "✅ Help is coming",
          body: `${responderName} accepted and is on the way`,
          channelId: "sos_updates",
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: "✅ Help is coming",
              body: `${responderName} accepted and is on the way`,
            },
            sound: "default",
          },
        },
      },
    });
  });

// ─── Helper: clean stale FCM tokens ─────────────────────────────────────────

async function _cleanStaleFcmTokens(
  tokens: string[],
  response: admin.messaging.BatchResponse,
  userIds: string[]
): Promise<void> {
  const batch = db.batch();
  let hasStaleBatch = false;

  response.responses.forEach((r, i) => {
    if (!r.success && r.error?.code === "messaging/registration-token-not-registered") {
      const ref = db.collection("users").doc(userIds[i]);
      batch.update(ref, { fcm_token: admin.firestore.FieldValue.delete() });
      hasStaleBatch = true;
    }
  });

  if (hasStaleBatch) await batch.commit();
}
