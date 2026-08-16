import { Router, type IRouter } from "express";
import { eq } from "drizzle-orm";
import { db, registrationsTable, eventsTable, tenantsTable } from "@workspace/db";
import { requireAuth } from "../middlewares/requireAuth";
import { UpdateRegistrationBody } from "@workspace/api-zod";

const router: IRouter = Router();

// PATCH /registrations/:id
// Authorization matrix:
//   - super_admin: any field on any registration
//   - host (owning tenant): paymentStatus, tagUid, runnerToken (operational fields)
//   - runner: nothing — runners do not self-update registration operational fields
router.patch("/registrations/:id", requireAuth, async (req, res): Promise<void> => {
  const raw = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const id = parseInt(raw, 10);
  if (isNaN(id)) {
    res.status(400).json({ error: "Invalid registration ID" });
    return;
  }

  const [reg] = await db
    .select()
    .from(registrationsTable)
    .where(eq(registrationsTable.id, id));

  if (!reg) {
    res.status(404).json({ error: "Registration not found" });
    return;
  }

  if (req.userRole === "runner") {
    // Runners cannot update registration operational fields
    res.status(403).json({ error: "Forbidden: runners cannot update registration records" });
    return;
  }

  if (req.userRole === "host") {
    // Host must own the event this registration belongs to
    const [event] = await db
      .select()
      .from(eventsTable)
      .where(eq(eventsTable.id, reg.eventId));
    const [tenant] = await db
      .select()
      .from(tenantsTable)
      .where(eq(tenantsTable.userId, req.userId!));

    if (!event || !tenant || tenant.id !== event.tenantId) {
      res.status(403).json({ error: "Forbidden: event belongs to a different tenant" });
      return;
    }
  }
  // super_admin falls through with no additional check

  const parsed = UpdateRegistrationBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [updated] = await db
    .update(registrationsTable)
    .set(parsed.data)
    .where(eq(registrationsTable.id, id))
    .returning();

  res.json(updated);
});

export default router;
