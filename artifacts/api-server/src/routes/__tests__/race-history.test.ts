/**
 * Unit tests for GET /users/me/race-history
 *
 * Covers three scenarios:
 *   1. Runner with no confirmed registrations → returns []
 *   2. Runner with registrations but no finished races (<4 laps) → returns []
 *   3. Runner with multiple finished races → returns correct finish positions
 *
 * All database I/O is avoided: the @workspace/db module is fully mocked so
 * no DATABASE_URL is required and no real Postgres connection is made.
 * The requireAuth middleware is replaced by a stub that injects a fixed userId.
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import express from "express";
import request from "supertest";

// ── Module mocks ──────────────────────────────────────────────────────────────
// vi.mock calls are hoisted by Vitest so they execute before any import,
// preventing @workspace/db from throwing on a missing DATABASE_URL.

vi.mock("@workspace/db", () => ({
  db: { select: vi.fn() },
  usersTable: Symbol("usersTable"),
  tenantsTable: Symbol("tenantsTable"),
  registrationsTable: Symbol("registrationsTable"),
  eventsTable: Symbol("eventsTable"),
  lapLogsTable: Symbol("lapLogsTable"),
}));

vi.mock("../../middlewares/requireAuth", () => ({
  requireAuth: (req: express.Request, _res: express.Response, next: express.NextFunction) => {
    req.userId = TEST_USER_ID;
    next();
  },
}));

// Clerk is imported at the top of users.ts; stub it so no real client is created.
vi.mock("@clerk/express", () => ({
  createClerkClient: vi.fn(),
  getAuth: vi.fn(),
}));

// ── Imports (after mocks are registered) ─────────────────────────────────────

import { db } from "@workspace/db";
import usersRouter from "../users";

// ── Constants & helpers ───────────────────────────────────────────────────────

const TEST_USER_ID = "user-test-1";

/** Build a chainable Drizzle-style select mock that resolves to `rows`. */
function makeChain(rows: unknown[]) {
  const chain = {
    from: vi.fn().mockReturnThis(),
    innerJoin: vi.fn().mockReturnThis(),
    where: vi.fn().mockResolvedValue(rows),
  };
  return chain;
}

/** Convenience: stage multiple sequential db.select() return values. */
function stageCalls(...rowSets: unknown[][]) {
  const mockSelect = vi.mocked(db.select as (...args: unknown[]) => unknown);
  for (const rows of rowSets) {
    mockSelect.mockReturnValueOnce(makeChain(rows) as unknown as ReturnType<typeof db.select>);
  }
}

/** Create a minimal Express app with just the users router mounted at root. */
function buildApp() {
  const app = express();
  app.use(express.json());
  app.use(usersRouter);
  return app;
}

/** One lap row per lapNumber given an array of cumulative elapsedMs values. */
function makeLaps(registrationId: number, elapsedMsArr: number[]) {
  return elapsedMsArr.map((elapsedMs, idx) => ({
    id: registrationId * 100 + idx,
    registrationId,
    lapNumber: idx + 1,
    elapsedMs,
    splitTimeMs: idx === 0 ? elapsedMs : elapsedMs - elapsedMsArr[idx - 1],
    pourConfirmed: true,
    scannedAt: new Date(),
  }));
}

// ── Shared fixtures ───────────────────────────────────────────────────────────

/** Older event — registered September 2025 */
const REG_EVENT_1 = {
  regId: 1,
  eventId: 1,
  registeredAt: new Date("2025-09-14T10:00:00Z"),
  tenantId: 10,
  eventTitle: "Autumn Beer Mile",
  eventCode: "ABM25",
  eventDate: "2025-09-14",
  eventStatus: "completed",
  eventCreatedAt: new Date("2025-09-01T00:00:00Z"),
  locationName: "City Park",
};

/** Newer event — registered December 2025 */
const REG_EVENT_2 = {
  regId: 2,
  eventId: 2,
  registeredAt: new Date("2025-12-06T10:00:00Z"),
  tenantId: 10,
  eventTitle: "Winter Beer Mile",
  eventCode: "WBM25",
  eventDate: "2025-12-06",
  eventStatus: "completed",
  eventCreatedAt: new Date("2025-11-20T00:00:00Z"),
  locationName: "Riverside Track",
};

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("GET /users/me/race-history", () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    vi.clearAllMocks();
  });

  // ── Scenario 1: no registrations ─────────────────────────────────────────

  it("returns an empty array when the runner has no confirmed registrations", async () => {
    // Only one DB call is made; early-return skips the rest.
    stageCalls(
      [], // userRegs → empty
    );

    const res = await request(app)
      .get("/users/me/race-history")
      .set("Authorization", "Bearer fake-token");

    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  // ── Scenario 2: registrations exist but no race is finished ─────────────

  it("excludes races where the runner completed fewer than 4 laps", async () => {
    // User is registered for event 1 but has only 3 laps → unfinished.
    stageCalls(
      [REG_EVENT_1],       // userRegs
      // allEventRegs — only user's reg in that event
      [{ regId: 1, eventId: 1, userId: TEST_USER_ID }],
      // allLaps — only 3 laps, so finished = false
      makeLaps(1, [150_000, 300_000, 450_000]),
    );

    const res = await request(app)
      .get("/users/me/race-history")
      .set("Authorization", "Bearer fake-token");

    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  it("excludes races where the runner has fewer than 4 distinct lap records even with high elapsedMs", async () => {
    // Only 2 laps recorded (scanner error mid-race) — must be excluded.
    stageCalls(
      [REG_EVENT_1],
      [{ regId: 1, eventId: 1, userId: TEST_USER_ID }],
      makeLaps(1, [300_000, 600_000]), // only 2 laps
    );

    const res = await request(app)
      .get("/users/me/race-history")
      .set("Authorization", "Bearer fake-token");

    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  // ── Scenario 3: multiple finished races with correct finish positions ─────

  it("returns finished races with correct finish positions and totalFinishers", async () => {
    /**
     * Setup
     * ─────
     * Event 1 (older, Sep 2025): user (regId=1) vs competitor (regId=3)
     *   - user: 600 000 ms (10 min) → 2nd place
     *   - competitor: 500 000 ms (8.3 min) → 1st place (faster)
     *
     * Event 2 (newer, Dec 2025): user (regId=2) alone
     *   - user: 700 000 ms → 1st place (sole finisher)
     *
     * Response must be sorted newest-first → event 2 first.
     */

    // DB call 1: user's confirmed registrations + event join
    const userRegs = [REG_EVENT_1, REG_EVENT_2];

    // DB call 2: ALL confirmed registrations for eventIds [1, 2]
    const allEventRegs = [
      { regId: 1, eventId: 1, userId: TEST_USER_ID },   // user in event 1
      { regId: 3, eventId: 1, userId: "other-runner" }, // competitor in event 1
      { regId: 2, eventId: 2, userId: TEST_USER_ID },   // user in event 2
    ];

    // DB call 3: all laps for regIds [1, 3, 2]
    const allLaps = [
      // User's laps for event 1 — 600 000 ms total
      ...makeLaps(1, [150_000, 300_000, 450_000, 600_000]),
      // Competitor's laps for event 1 — 500 000 ms total (faster)
      ...makeLaps(3, [125_000, 250_000, 375_000, 500_000]),
      // User's laps for event 2 — 700 000 ms total
      ...makeLaps(2, [175_000, 350_000, 525_000, 700_000]),
    ];

    stageCalls(userRegs, allEventRegs, allLaps);

    const res = await request(app)
      .get("/users/me/race-history")
      .set("Authorization", "Bearer fake-token");

    expect(res.status).toBe(200);

    const body: {
      eventId: number;
      finishPosition: number;
      totalFinishers: number;
      totalElapsedMs: number;
      finished: boolean;
      laps: unknown[];
    }[] = res.body;

    expect(body).toHaveLength(2);

    // Newest first: event 2 (December) must be the first result.
    expect(body[0].eventId).toBe(2);
    expect(body[0].finishPosition).toBe(1);
    expect(body[0].totalFinishers).toBe(1);
    expect(body[0].totalElapsedMs).toBe(700_000);
    expect(body[0].finished).toBe(true);
    expect(body[0].laps).toHaveLength(4);

    // Older race: event 1 (September) — user finished 2nd out of 2.
    expect(body[1].eventId).toBe(1);
    expect(body[1].finishPosition).toBe(2);
    expect(body[1].totalFinishers).toBe(2);
    expect(body[1].totalElapsedMs).toBe(600_000);
    expect(body[1].finished).toBe(true);
    expect(body[1].laps).toHaveLength(4);
  });

  it("returns finishPosition=1 and totalFinishers=1 for a sole finisher", async () => {
    stageCalls(
      [REG_EVENT_2],
      [{ regId: 2, eventId: 2, userId: TEST_USER_ID }],
      makeLaps(2, [175_000, 350_000, 525_000, 700_000]),
    );

    const res = await request(app)
      .get("/users/me/race-history")
      .set("Authorization", "Bearer fake-token");

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
    expect(res.body[0].finishPosition).toBe(1);
    expect(res.body[0].totalFinishers).toBe(1);
  });

  it("sorts multiple results newest-first by registeredAt", async () => {
    // Both events are returned; newest (Dec) must come first.
    const allEventRegs = [
      { regId: 1, eventId: 1, userId: TEST_USER_ID },
      { regId: 2, eventId: 2, userId: TEST_USER_ID },
    ];
    const allLaps = [
      ...makeLaps(1, [150_000, 300_000, 450_000, 600_000]),
      ...makeLaps(2, [175_000, 350_000, 525_000, 700_000]),
    ];

    stageCalls([REG_EVENT_1, REG_EVENT_2], allEventRegs, allLaps);

    const res = await request(app)
      .get("/users/me/race-history")
      .set("Authorization", "Bearer fake-token");

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(2);
    // Dec 2025 registration must appear before Sep 2025
    expect(res.body[0].eventId).toBe(2);
    expect(res.body[1].eventId).toBe(1);
  });
});
