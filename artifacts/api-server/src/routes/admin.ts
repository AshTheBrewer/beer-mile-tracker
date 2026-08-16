import { Router, type IRouter } from "express";
import { eq, sql } from "drizzle-orm";
import { db, usersTable, eventsTable, registrationsTable, tenantsTable, lapLogsTable, platformSettingsTable } from "@workspace/db";
import { requireRole } from "../middlewares/requireAuth";
import { UpdatePlatformSettingsBody } from "@workspace/api-zod";

const router: IRouter = Router();

// GET /admin/analytics — super_admin only
router.get("/admin/analytics", requireRole("super_admin"), async (req, res): Promise<void> => {
  const [{ totalEvents }] = await db
    .select({ totalEvents: sql<number>`count(*)::int` })
    .from(eventsTable);

  const [{ totalRunners }] = await db
    .select({ totalRunners: sql<number>`count(*)::int` })
    .from(usersTable)
    .where(eq(usersTable.role, "runner"));

  const [{ totalTenants }] = await db
    .select({ totalTenants: sql<number>`count(*)::int` })
    .from(tenantsTable);

  // Finishers = registrations with 4 lap logs
  const finishersResult = await db.execute(sql`
    SELECT COUNT(DISTINCT registration_id)::int AS total_finishers
    FROM lap_logs
    WHERE lap_number = 4
  `);
  const totalFinishers = (finishersResult.rows[0] as any)?.total_finishers ?? 0;

  // Average lap time across all lap logs
  const avgResult = await db.execute(sql`
    SELECT AVG(split_time_ms)::bigint AS avg_lap_time_ms FROM lap_logs WHERE split_time_ms IS NOT NULL
  `);
  const avgLapTimeMs = (avgResult.rows[0] as any)?.avg_lap_time_ms ?? null;

  // Events by status
  const byStatus = await db
    .select({ status: eventsTable.status, count: sql<number>`count(*)::int` })
    .from(eventsTable)
    .groupBy(eventsTable.status);

  const eventsByStatus: Record<string, number> = {};
  for (const row of byStatus) {
    eventsByStatus[row.status] = row.count;
  }

  res.json({
    totalEvents,
    totalRunners,
    totalTenants,
    totalFinishers,
    avgLapTimeMs: avgLapTimeMs ? Number(avgLapTimeMs) : null,
    eventsByStatus,
  });
});

// GET /admin/tenants — super_admin only
router.get("/admin/tenants", requireRole("super_admin"), async (req, res): Promise<void> => {
  const tenants = await db
    .select({
      id: tenantsTable.id,
      userId: tenantsTable.userId,
      organizationName: tenantsTable.organizationName,
      createdAt: tenantsTable.createdAt,
      userEmail: usersTable.email,
    })
    .from(tenantsTable)
    .leftJoin(usersTable, eq(tenantsTable.userId, usersTable.id));

  res.json(tenants);
});

// GET /platform-settings
router.get("/platform-settings", async (_req, res): Promise<void> => {
  const [settings] = await db.select().from(platformSettingsTable);
  if (!settings) {
    // Return empty defaults
    res.json({ id: 0, appStoreIosUrl: null, playStoreAndroidUrl: null, updatedAt: new Date().toISOString() });
    return;
  }
  res.json(settings);
});

// PATCH /platform-settings — super_admin only
router.patch("/platform-settings", requireRole("super_admin"), async (req, res): Promise<void> => {
  const parsed = UpdatePlatformSettingsBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [existing] = await db.select().from(platformSettingsTable);

  let updated;
  if (existing) {
    [updated] = await db
      .update(platformSettingsTable)
      .set(parsed.data)
      .where(eq(platformSettingsTable.id, existing.id))
      .returning();
  } else {
    [updated] = await db
      .insert(platformSettingsTable)
      .values(parsed.data)
      .returning();
  }

  res.json(updated);
});

export default router;
