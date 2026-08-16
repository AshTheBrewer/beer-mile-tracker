import { Router, type IRouter } from "express";
import { eq, and, sql } from "drizzle-orm";
import { createClerkClient, getAuth } from "@clerk/express";
import { db, usersTable, tenantsTable, registrationsTable, eventsTable, lapLogsTable } from "@workspace/db";
import { requireAuth } from "../middlewares/requireAuth";
import {
  ProvisionUserBody,
  UpdateMeBody,
  CreateTenantBody,
} from "@workspace/api-zod";

const router: IRouter = Router();

function getClerk() {
  return createClerkClient({ secretKey: process.env.CLERK_SECRET_KEY });
}

// POST /users/me/provision — create or fetch user; email comes from Clerk, role always defaults to runner
router.post("/users/me/provision", requireAuth, async (req, res): Promise<void> => {
  const parsed = ProvisionUserBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const userId = req.userId!;

  const [existing] = await db
    .select()
    .from(usersTable)
    .where(eq(usersTable.id, userId));

  if (existing) {
    res.json(existing);
    return;
  }

  // Fetch authoritative identity data from Clerk — never trust caller-supplied email/role
  const clerkUser = await getClerk().users.getUser(userId);
  const email =
    clerkUser.emailAddresses.find((e) => e.id === clerkUser.primaryEmailAddressId)
      ?.emailAddress ?? clerkUser.emailAddresses[0]?.emailAddress ?? "";

  const [created] = await db
    .insert(usersTable)
    .values({
      id: userId,
      email,
      preferredName: parsed.data.preferredName ?? clerkUser.firstName ?? null,
      role: "runner", // always start as runner; privileged roles granted by admin only
    })
    .returning();

  res.status(201).json(created);
});

// GET /users/me
router.get("/users/me", requireAuth, async (req, res): Promise<void> => {
  const [user] = await db
    .select()
    .from(usersTable)
    .where(eq(usersTable.id, req.userId!));

  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(user);
});

// PATCH /users/me — only profile fields; role is not changeable by the user themselves
router.patch("/users/me", requireAuth, async (req, res): Promise<void> => {
  const parsed = UpdateMeBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [updated] = await db
    .update(usersTable)
    .set(parsed.data)
    .where(eq(usersTable.id, req.userId!))
    .returning();

  if (!updated) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(updated);
});

// GET /users/me/race-history — all completed races for the current runner in one call
router.get("/users/me/race-history", requireAuth, async (req, res): Promise<void> => {
  const userId = req.userId!;

  // 1. Get all confirmed registrations for this user, joined with event data
  const userRegs = await db
    .select({
      regId: registrationsTable.id,
      eventId: registrationsTable.eventId,
      registeredAt: registrationsTable.registeredAt,
      tenantId: eventsTable.tenantId,
      eventTitle: eventsTable.title,
      eventCode: eventsTable.eventCode,
      eventDate: eventsTable.eventDate,
      eventStatus: eventsTable.status,
      eventCreatedAt: eventsTable.createdAt,
      locationName: eventsTable.locationName,
    })
    .from(registrationsTable)
    .innerJoin(eventsTable, eq(registrationsTable.eventId, eventsTable.id))
    .where(
      and(
        eq(registrationsTable.userId, userId),
        eq(registrationsTable.paymentStatus, "confirmed"),
      ),
    );

  if (userRegs.length === 0) {
    res.json([]);
    return;
  }

  // 2. Get all confirmed registrations across those events (needed to compute finish positions)
  const eventIds = [...new Set(userRegs.map((r) => r.eventId))];
  const allEventRegs = await db
    .select({
      regId: registrationsTable.id,
      eventId: registrationsTable.eventId,
      userId: registrationsTable.userId,
    })
    .from(registrationsTable)
    .where(
      and(
        sql`${registrationsTable.eventId} = ANY(ARRAY[${sql.join(eventIds.map((id) => sql`${id}`), sql`, `)}]::int[])`,
        eq(registrationsTable.paymentStatus, "confirmed"),
      ),
    );

  // 3. Fetch all lap logs for all registrations in those events in a single query
  const allRegIds = allEventRegs.map((r) => r.regId);
  const allLaps = allRegIds.length > 0
    ? await db
        .select()
        .from(lapLogsTable)
        .where(
          sql`${lapLogsTable.registrationId} = ANY(ARRAY[${sql.join(allRegIds.map((id) => sql`${id}`), sql`, `)}]::int[])`,
        )
    : [];

  // 4. Build a result for each of the user's registrations
  const results: object[] = [];

  for (const reg of userRegs) {
    const userLaps = allLaps
      .filter((l) => l.registrationId === reg.regId)
      .sort((a, b) => a.lapNumber - b.lapNumber);

    const maxLap = userLaps.length > 0 ? Math.max(...userLaps.map((l) => l.lapNumber)) : 0;
    const totalElapsedMs = userLaps.length > 0 ? Math.max(...userLaps.map((l) => l.elapsedMs)) : 0;
    const finished = maxLap >= 4 && userLaps.length >= 4;

    if (!finished) continue; // Only include completed races

    // Compute finish position using all finishers in this event
    const eventRegs = allEventRegs.filter((r) => r.eventId === reg.eventId);
    const finishers = eventRegs
      .map((r) => {
        const laps = allLaps.filter((l) => l.registrationId === r.regId);
        const mxLap = laps.length > 0 ? Math.max(...laps.map((l) => l.lapNumber)) : 0;
        const totalMs = laps.length > 0 ? Math.max(...laps.map((l) => l.elapsedMs)) : 0;
        return { regId: r.regId, totalMs, finished: mxLap >= 4 && laps.length >= 4 };
      })
      .filter((f) => f.finished)
      .sort((a, b) => a.totalMs - b.totalMs);

    const totalFinishers = finishers.length;
    const posIdx = finishers.findIndex((f) => f.regId === reg.regId);
    const finishPosition = posIdx >= 0 ? posIdx + 1 : null;

    results.push({
      eventId: reg.eventId,
      tenantId: reg.tenantId,
      eventTitle: reg.eventTitle,
      eventCode: reg.eventCode,
      eventDate: reg.eventDate,
      eventStatus: reg.eventStatus,
      eventCreatedAt: reg.eventCreatedAt,
      locationName: reg.locationName,
      registrationId: reg.regId,
      registeredAt: reg.registeredAt,
      totalElapsedMs,
      finished,
      finishPosition,
      totalFinishers,
      laps: userLaps.map((l) => ({
        lapNumber: l.lapNumber,
        elapsedMs: l.elapsedMs,
        splitTimeMs: l.splitTimeMs,
        pourConfirmed: l.pourConfirmed,
      })),
    });
  }

  // Sort newest-first by registeredAt
  (results as Array<{ registeredAt: Date }>).sort(
    (a, b) => b.registeredAt.getTime() - a.registeredAt.getTime(),
  );

  res.json(results);
});

// GET /tenants/me
router.get("/tenants/me", requireAuth, async (req, res): Promise<void> => {
  const [tenant] = await db
    .select()
    .from(tenantsTable)
    .where(eq(tenantsTable.userId, req.userId!));

  if (!tenant) {
    res.status(404).json({ error: "Tenant not found" });
    return;
  }
  res.json(tenant);
});

// POST /tenants/me — promotes the user to host role and creates their tenant
router.post("/tenants/me", requireAuth, async (req, res): Promise<void> => {
  const parsed = CreateTenantBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [existing] = await db
    .select()
    .from(tenantsTable)
    .where(eq(tenantsTable.userId, req.userId!));

  if (existing) {
    res.status(409).json({ error: "Tenant already exists" });
    return;
  }

  // Promote to host
  await db
    .update(usersTable)
    .set({ role: "host" })
    .where(eq(usersTable.id, req.userId!));

  const [created] = await db
    .insert(tenantsTable)
    .values({ userId: req.userId!, organizationName: parsed.data.organizationName })
    .returning();

  res.status(201).json(created);
});

export default router;
