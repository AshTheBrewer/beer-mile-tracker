import { Router, type IRouter } from "express";
import { eq, and } from "drizzle-orm";
import { db, eventsTable, tenantsTable, registrationsTable, usersTable } from "@workspace/db";
import { requireAuth } from "../middlewares/requireAuth";
import {
  CreateEventBody,
  UpdateEventBody,
  JoinEventByCodeBody,
} from "@workspace/api-zod";
import { randomBytes } from "crypto";

const router: IRouter = Router();

function generateEventCode(): string {
  return randomBytes(3).toString("hex").toUpperCase();
}

// GET /events
router.get("/events", async (req, res): Promise<void> => {
  const events = await db.select().from(eventsTable);
  res.json(events);
});

// POST /events
router.post("/events", requireAuth, async (req, res): Promise<void> => {
  if (req.userRole !== "host" && req.userRole !== "super_admin") {
    res.status(403).json({ error: "Only hosts can create events" });
    return;
  }

  const parsed = CreateEventBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  if (req.userRole === "super_admin") {
    res.status(400).json({ error: "Super admins must specify tenantId" });
    return;
  }

  const [tenant] = await db
    .select()
    .from(tenantsTable)
    .where(eq(tenantsTable.userId, req.userId!));

  if (!tenant) {
    res.status(400).json({ error: "Host has no tenant. Create a tenant first." });
    return;
  }

  let eventCode = generateEventCode();
  for (let i = 0; i < 5; i++) {
    const [existing] = await db
      .select({ id: eventsTable.id })
      .from(eventsTable)
      .where(eq(eventsTable.eventCode, eventCode));
    if (!existing) break;
    eventCode = generateEventCode();
  }

  const [event] = await db
    .insert(eventsTable)
    .values({ ...parsed.data, tenantId: tenant.id, eventCode })
    .returning();

  res.status(201).json(event);
});

// POST /events/join
router.post("/events/join", async (req, res): Promise<void> => {
  const parsed = JoinEventByCodeBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [event] = await db
    .select()
    .from(eventsTable)
    .where(eq(eventsTable.eventCode, parsed.data.eventCode));

  if (!event) {
    res.status(404).json({ error: "Event not found" });
    return;
  }
  res.json(event);
});

// GET /events/:id
router.get("/events/:id", async (req, res): Promise<void> => {
  const raw = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const id = parseInt(raw, 10);
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid event ID" });
    return;
  }

  const [event] = await db.select().from(eventsTable).where(eq(eventsTable.id, id));
  if (!event) {
    res.status(404).json({ error: "Event not found" });
    return;
  }
  res.json(event);
});

// PATCH /events/:id
router.patch("/events/:id", requireAuth, async (req, res): Promise<void> => {
  const raw = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const id = parseInt(raw, 10);
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid event ID" });
    return;
  }

  const [event] = await db.select().from(eventsTable).where(eq(eventsTable.id, id));
  if (!event) {
    res.status(404).json({ error: "Event not found" });
    return;
  }

  if (req.userRole !== "super_admin") {
    const [tenant] = await db
      .select()
      .from(tenantsTable)
      .where(eq(tenantsTable.userId, req.userId!));
    if (!tenant || tenant.id !== event.tenantId) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
  }

  const parsed = UpdateEventBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [updated] = await db
    .update(eventsTable)
    .set(parsed.data)
    .where(eq(eventsTable.id, id))
    .returning();

  res.json(updated);
});

// DELETE /events/:id
router.delete("/events/:id", requireAuth, async (req, res): Promise<void> => {
  const raw = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const id = parseInt(raw, 10);
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid event ID" });
    return;
  }

  const [event] = await db.select().from(eventsTable).where(eq(eventsTable.id, id));
  if (!event) {
    res.status(404).json({ error: "Event not found" });
    return;
  }

  if (req.userRole !== "super_admin") {
    const [tenant] = await db
      .select()
      .from(tenantsTable)
      .where(eq(tenantsTable.userId, req.userId!));
    if (!tenant || tenant.id !== event.tenantId) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
  }

  await db.delete(eventsTable).where(eq(eventsTable.id, id));
  res.sendStatus(204);
});

// GET /events/:id/registrations
router.get("/events/:id/registrations", requireAuth, async (req, res): Promise<void> => {
  const raw = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const id = parseInt(raw, 10);
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid event ID" });
    return;
  }

  if (req.userRole !== "super_admin") {
    const [tenant] = await db
      .select()
      .from(tenantsTable)
      .where(eq(tenantsTable.userId, req.userId!));
    const [event] = await db.select().from(eventsTable).where(eq(eventsTable.id, id));
    if (!event || !tenant || tenant.id !== event.tenantId) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }
  }

  const regs = await db
    .select({
      id: registrationsTable.id,
      eventId: registrationsTable.eventId,
      userId: registrationsTable.userId,
      paymentStatus: registrationsTable.paymentStatus,
      tagUid: registrationsTable.tagUid,
      runnerToken: registrationsTable.runnerToken,
      registeredAt: registrationsTable.registeredAt,
      updatedAt: registrationsTable.updatedAt,
      userEmail: usersTable.email,
      preferredName: usersTable.preferredName,
      gender: usersTable.gender,
      birthdate: usersTable.birthdate,
    })
    .from(registrationsTable)
    .leftJoin(usersTable, eq(registrationsTable.userId, usersTable.id))
    .where(eq(registrationsTable.eventId, id));

  res.json(regs);
});

// POST /events/:id/registrations
router.post("/events/:id/registrations", requireAuth, async (req, res): Promise<void> => {
  const raw = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const id = parseInt(raw, 10);
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid event ID" });
    return;
  }

  const [event] = await db.select().from(eventsTable).where(eq(eventsTable.id, id));
  if (!event) {
    res.status(404).json({ error: "Event not found" });
    return;
  }

  // Use INSERT ... ON CONFLICT DO NOTHING to avoid race conditions on the
  // (event_id, user_id) unique DB constraint. The RETURNING clause tells us
  // whether a row was actually inserted or already existed.
  const [reg] = await db
    .insert(registrationsTable)
    .values({ eventId: id, userId: req.userId! })
    .onConflictDoNothing({ target: [registrationsTable.eventId, registrationsTable.userId] })
    .returning();

  if (!reg) {
    res.status(409).json({ error: "Already registered for this event" });
    return;
  }

  res.status(201).json(reg);
});

export default router;
