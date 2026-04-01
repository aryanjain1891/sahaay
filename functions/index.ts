import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as geofire from "geofire-common";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ─── Constants ────────────────────────────────────────────────────────────────

const RADIUS_KM = 0.5;           // 500m
const ACTIVE_THRESHOLD_MIN = 5;  // users active within last 5 minutes
const SOS_COOLDOWN_SEC = 30;     // minimum seconds between SOS triggers per user

// ─── triggerSos ──────────────────────────────────────────────────────────────
// Called by Flutter client on SOS confirm.
// Creates SOS_EVENT, geo-queries nearby users, dispatches FCM.

export const triggerSos = onCall(
  { region: "asia-south1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const uid = request.auth.uid;
    const data = request.data;
    const lat: number = data.lat;
    const lng: number = data.lng;
    const accuracyFlag: string = data.accuracy_flag ?? "current";

    // ── Validate coordinates ────────────────────────────────────────────────
    if (lat == null || lng == null || typeof lat !== "number" || typeof lng !== "number") {
      throw new HttpsError("invalid-argument", "Location required");
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw new HttpsError("invalid-argument", "Invalid coordinates");
    }

    // ── Server-side rate limiting ───────────────────────────────────────────
    const recentSos = await db.collection("sos_events")
      .where("triggered_by", "==", uid)
      .where("status", "==", "ACTIVE")
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();

    if (!recentSos.empty) {
      const lastTimestamp = recentSos.docs[0].data().timestamp?.toDate();
      if (lastTimestamp && (Date.now() - lastTimestamp.getTime()) < SOS_COOLDOWN_SEC * 1000) {
        throw new HttpsError("resource-exhausted", "Please wait before triggering another SOS");
      }
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

    logger.info(`SOS created: ${sosRef.id} by ${uid}`);

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
        if (doc.id === uid) continue;

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

    logger.info(`Found ${nearbyUsers.length} nearby users for SOS ${sosRef.id}`);

    // ── 3. Dispatch FCM ──────────────────────────────────────────────────────
    if (nearbyUsers.length > 0) {
      const tokenDocs = await Promise.all(
        nearbyUsers.map((u) => db.collection("users").doc(u.id).get())
      );

      const tokens = tokenDocs
        .map((d) => d.data()?.fcm_token)
        .filter(Boolean) as string[];

      if (tokens.length > 0) {
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
        logger.info(`FCM sent: ${response.successCount} success, ${response.failureCount} failures`);
        await _cleanStaleFcmTokens(tokens, response, nearbyUsers.map((u) => u.id));
      }
    } else {
      logger.warn(`No nearby users for SOS ${sosRef.id} — triggering fallback`);
    }

    return { sos_id: sosRef.id };
  }
);

// ─── autoExpireSos ───────────────────────────────────────────────────────────
// Runs every 5 minutes. Marks SOS events older than 30 minutes as EXPIRED.

export const autoExpireSos = onSchedule(
  { schedule: "every 5 minutes", region: "asia-south1" },
  async () => {
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
    logger.info(`Expired ${stale.size} stale SOS events`);
  }
);

// ─── getNearbyActiveSos ─────────────────────────────────────────────────────
// Returns active SOS events within RADIUS_KM of the caller's location.
// This replaces direct Firestore reads so victims' locations aren't globally visible.

export const getNearbyActiveSos = onCall(
  { region: "asia-south1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const { lat, lng } = request.data;

    if (lat == null || lng == null || typeof lat !== "number" || typeof lng !== "number") {
      throw new HttpsError("invalid-argument", "Location required");
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw new HttpsError("invalid-argument", "Invalid coordinates");
    }

    const center = [lat, lng] as [number, number];
    const bounds = geofire.geohashQueryBounds(center, RADIUS_KM * 1000);

    const queries = bounds.map((b) =>
      db.collection("sos_events")
        .where("status", "==", "ACTIVE")
        .orderBy("geohash")
        .startAt(b[0])
        .endAt(b[1])
        .get()
    );

    const snapshots = await Promise.all(queries);
    const events: Record<string, unknown>[] = [];
    const seen = new Set<string>();

    for (const snap of snapshots) {
      for (const doc of snap.docs) {
        if (seen.has(doc.id)) continue;
        seen.add(doc.id);

        const data = doc.data();
        const loc = data.location as admin.firestore.GeoPoint;
        const distanceKm = geofire.distanceBetween(
          [loc.latitude, loc.longitude],
          center,
        );

        if (distanceKm <= RADIUS_KM) {
          events.push({
            sos_id: doc.id,
            triggered_by: data.triggered_by,
            location: { lat: loc.latitude, lng: loc.longitude },
            geohash: data.geohash,
            timestamp: data.timestamp?.toDate()?.toISOString(),
            status: data.status,
            responders: data.responders ?? [],
            distance_m: Math.round(distanceKm * 1000),
          });
        }
      }
    }

    // Sort by nearest first
    events.sort((a, b) => (a.distance_m as number) - (b.distance_m as number));
    return { events: events.slice(0, 10) };
  }
);

// ─── signOut ────────────────────────────────────────────────────────────────
// Cleans up FCM token on logout to prevent stale notifications.

export const signOut = onCall(
  { region: "asia-south1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    await db.collection("users").doc(request.auth.uid).update({
      fcm_token: admin.firestore.FieldValue.delete(),
    });

    return { success: true };
  }
);

// ─── onSosAccepted ───────────────────────────────────────────────────────────
// Firestore trigger: when a responder is added, notify the victim.

export const onSosAccepted = onDocumentUpdated(
  { document: "sos_events/{sosId}", region: "asia-south1" },
  async (event) => {
    if (!event.data) return;

    const before = event.data.before.data();
    const after = event.data.after.data();

    const newResponders: string[] = after.responders ?? [];
    const oldResponders: string[] = before.responders ?? [];

    if (newResponders.length <= oldResponders.length) return;

    const newResponderId = newResponders.find((r) => !oldResponders.includes(r));
    if (!newResponderId) return;

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
        sos_id: event.params.sosId,
        responder_name: responderName,
        responder_count: String(newResponders.length),
      },
      android: {
        priority: "high",
        notification: {
          title: "Help is coming",
          body: `${responderName} accepted and is on the way`,
          channelId: "sos_updates",
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: "Help is coming",
              body: `${responderName} accepted and is on the way`,
            },
            sound: "default",
          },
        },
      },
    });
  }
);

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
