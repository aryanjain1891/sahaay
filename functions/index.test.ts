import firebaseFunctionsTest from "firebase-functions-test";

// Initialise firebase-functions-test in OFFLINE mode (no project config needed).
// This must happen before importing the functions under test so that
// firebase-admin.initializeApp() inside index.ts picks up the test environment.
const testEnv = firebaseFunctionsTest();

// ── Import functions under test ──────────────────────────────────────────────
// Because triggerSos / getNearbyActiveSos / signOut are onCall v2 functions,
// their `.run()` method is not directly exposed the same way as v1.
// Instead we call the wrapped handler directly via the internal run method.
// firebase-functions-test v3 exposes a `wrap` helper that works with v2.
import { triggerSos, getNearbyActiveSos, signOut } from "./index";

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Build a minimal CallableRequest-like object for onCall v2 handlers. */
function makeCallableRequest(data: unknown, auth?: { uid: string }) {
  return {
    data,
    auth: auth ?? undefined,
    rawRequest: {} as any,
    acceptsStreaming: false,
  };
}

/**
 * Invoke a v2 onCall function's handler directly.
 *
 * firebase-functions v2 onCall returns an object whose `.run()` method
 * accepts a CallableRequest.  If `.run()` is not available we fall back
 * to calling the export as a function (firebase-functions-test wraps it).
 */
async function callFunction(fn: any, data: unknown, auth?: { uid: string }) {
  const request = makeCallableRequest(data, auth);

  // v2 onCall exports expose a `run` method
  if (typeof fn.run === "function") {
    return fn.run(request);
  }
  // Fallback: firebase-functions-test wrap
  const wrapped = testEnv.wrap(fn);
  return wrapped(request);
}

/**
 * Helper to assert that an async call throws an HttpsError with the expected code.
 */
async function expectHttpsError(
  fn: () => Promise<unknown>,
  code: string,
  messageSubstring?: string,
) {
  try {
    await fn();
    // If we get here, no error was thrown
    throw new Error(`Expected HttpsError with code "${code}" but no error was thrown`);
  } catch (err: any) {
    // HttpsError from firebase-functions has a `code` property (the FunctionsErrorCode)
    // and also a `httpErrorCode` property.  The string code lives at err.code for v2.
    const errCode = err.code ?? err.httpErrorCode?.canonicalName;
    expect(errCode).toBe(code);
    if (messageSubstring) {
      expect(err.message).toContain(messageSubstring);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe("triggerSos", () => {
  test("throws unauthenticated when auth is missing", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: 12.9, lng: 77.6 }),
      "unauthenticated",
      "Login required",
    );
  });

  test("throws invalid-argument when lat is null", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: null, lng: 77.6 }, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });

  test("throws invalid-argument when lng is null", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: 12.9, lng: null }, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });

  test("throws invalid-argument when lat/lng are not numbers", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: "abc", lng: 77.6 }, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });

  test("throws invalid-argument for out-of-range latitude (> 90)", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: 91, lng: 77.6 }, { uid: "u1" }),
      "invalid-argument",
      "Invalid coordinates",
    );
  });

  test("throws invalid-argument for out-of-range latitude (< -90)", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: -91, lng: 77.6 }, { uid: "u1" }),
      "invalid-argument",
      "Invalid coordinates",
    );
  });

  test("throws invalid-argument for out-of-range longitude (> 180)", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: 12.9, lng: 181 }, { uid: "u1" }),
      "invalid-argument",
      "Invalid coordinates",
    );
  });

  test("throws invalid-argument for out-of-range longitude (< -180)", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, { lat: 12.9, lng: -181 }, { uid: "u1" }),
      "invalid-argument",
      "Invalid coordinates",
    );
  });

  test("throws invalid-argument when both lat and lng are missing", async () => {
    await expectHttpsError(
      () => callFunction(triggerSos, {}, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });
});

describe("getNearbyActiveSos", () => {
  test("throws unauthenticated when auth is missing", async () => {
    await expectHttpsError(
      () => callFunction(getNearbyActiveSos, { lat: 12.9, lng: 77.6 }),
      "unauthenticated",
      "Login required",
    );
  });

  test("throws invalid-argument when lat is null", async () => {
    await expectHttpsError(
      () => callFunction(getNearbyActiveSos, { lat: null, lng: 77.6 }, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });

  test("throws invalid-argument when lng is null", async () => {
    await expectHttpsError(
      () => callFunction(getNearbyActiveSos, { lat: 12.9, lng: null }, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });

  test("throws invalid-argument when lat/lng are not numbers", async () => {
    await expectHttpsError(
      () => callFunction(getNearbyActiveSos, { lat: "x", lng: "y" }, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });

  test("throws invalid-argument for out-of-range latitude", async () => {
    await expectHttpsError(
      () => callFunction(getNearbyActiveSos, { lat: 100, lng: 77.6 }, { uid: "u1" }),
      "invalid-argument",
      "Invalid coordinates",
    );
  });

  test("throws invalid-argument for out-of-range longitude", async () => {
    await expectHttpsError(
      () => callFunction(getNearbyActiveSos, { lat: 12.9, lng: 200 }, { uid: "u1" }),
      "invalid-argument",
      "Invalid coordinates",
    );
  });

  test("throws invalid-argument when data is empty", async () => {
    await expectHttpsError(
      () => callFunction(getNearbyActiveSos, {}, { uid: "u1" }),
      "invalid-argument",
      "Location required",
    );
  });
});

describe("signOut", () => {
  test("throws unauthenticated when auth is missing", async () => {
    await expectHttpsError(
      () => callFunction(signOut, {}),
      "unauthenticated",
      "Login required",
    );
  });
});

// ── Cleanup ──────────────────────────────────────────────────────────────────
afterAll(() => {
  testEnv.cleanup();
});
