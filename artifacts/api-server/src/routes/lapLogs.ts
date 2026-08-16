import { Router, type IRouter } from "express";
import { eq, inArray, sql } from "drizzle-orm";
import { db, lapLogsTable, registrationsTable, eventsTable, tenantsTable } from "@workspace/db";
import { requireAuth } from "../middlewares/requireAuth";
import { IngestLapLogsBody } from "@workspace/api-zod";
import { z } from "zod";

const router: IRouter = Router();

// Domain-level validation on top of the OpenAPI schema:
// - lapNumber must be 1–4 (a standard Beer Mile is exactly 4 laps)
// - elapsedMs must be a finite positive integer (milliseconds from race start)
// - splitTimeMs, if provided, must be non-negative
const lapLogRecordValidator = z.object({
  clientEventLogId: z.string().min(1),
  registrationId: z.number().int().positive(),
  lapNumber: z.number().int().min(1).max(4),
  elapsedMs: z.number().int().positive(),
  splitTimeMs: z.number().int().nonnegative().optional().nullable(),
  pourConfirmed: z.boolean(),
  deviceMonotonicTimestamp: z.number().int().optional().nullable(),
});

// POST /lap-logs — bulk ingest with idempotency + atomic "Earliest Scan Wins"
// Authorization: runners may only submit logs for their own registrations;
//                hosts may only submit logs for registrations in their tenant's events;
//                super_admin may submit any.
router.post("/lap-logs", requireAuth, async (req, res): Promise<void> => {
  const parsed = IngestLapLogsBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const { records } = parsed.data;
  const processedIds: string[] = [];

  // Pre-build authorization context once for the whole batch
  let authorizedRegistrationIds: Set<number> | "all" = "all";

  if (req.userRole === "super_admin") {
    authorizedRegistrationIds = "all";
  } else if (req.userRole === "host") {
    const [tenant] = await db
      .select({ id: tenantsTable.id })
      .from(tenantsTable)
      .where(eq(tenantsTable.userId, req.userId!));

    if (!tenant) {
      res.status(403).json({ error: "No tenant found for this host" });
      return;
    }

    const tenantEvents = await db
      .select({ id: eventsTable.id })
      .from(eventsTable)
      .where(eq(eventsTable.tenantId, tenant.id));

    const eventIds = tenantEvents.map((e) => e.id);
    if (eventIds.length === 0) {
      authorizedRegistrationIds = new Set();
    } else {
      const regs = await db
        .select({ id: registrationsTable.id })
        .from(registrationsTable)
        .where(inArray(registrationsTable.eventId, eventIds));
      authorizedRegistrationIds = new Set(regs.map((r) => r.id));
    }
  } else {
    // Runner: only their own confirmed registrations
    const ownRegs = await db
      .select({ id: registrationsTable.id })
      .from(registrationsTable)
      .where(eq(registrationsTable.userId, req.userId!));
    authorizedRegistrationIds = new Set(ownRegs.map((r) => r.id));
  }

  for (const record of records) {
    // Domain validation (lapNumber range, timing sanity)
    const validated = lapLogRecordValidator.safeParse(record);
    if (!validated.success) {
      req.log.warn({ clientEventLogId: record.clientEventLogId, errors: validated.error.message }, "Skipping invalid lap log record");
      continue; // skip invalid records without failing the whole batch
    }

    const {
      clientEventLogId,
      registrationId,
      lapNumber,
      splitTimeMs,
      elapsedMs,
      pourConfirmed,
      deviceMonotonicTimestamp,
    } = validated.data;

    // Authorization check per record
    if (
      authorizedRegistrationIds !== "all" &&
      !authorizedRegistrationIds.has(registrationId)
    ) {
      req.log.warn({ clientEventLogId, registrationId }, "Skipping unauthorized lap log record");
      continue;
    }

    // Atomic upsert: INSERT with ON CONFLICT (registration_id, lap_number) DO UPDATE
    // only when the incoming elapsed_ms is strictly lower than the stored value.
    // This is the DB-level "Earliest Scan Wins" guarantee and is concurrency-safe.
    await db.execute(sql`
      INSERT INTO lap_logs
        (client_event_log_id, registration_id, lap_number, split_time_ms, elapsed_ms,
         pour_confirmed, is_synced, device_monotonic_timestamp)
      VALUES
        (${clientEventLogId}, ${registrationId}, ${lapNumber}, ${splitTimeMs ?? null},
         ${elapsedMs}, ${pourConfirmed}, true, ${deviceMonotonicTimestamp ?? null})
      ON CONFLICT (registration_id, lap_number)
      DO UPDATE SET
        client_event_log_id     = EXCLUDED.client_event_log_id,
        split_time_ms           = EXCLUDED.split_time_ms,
        elapsed_ms              = EXCLUDED.elapsed_ms,
        pour_confirmed          = EXCLUDED.pour_confirmed,
        device_monotonic_timestamp = EXCLUDED.device_monotonic_timestamp,
        is_synced               = true
      WHERE EXCLUDED.elapsed_ms < lap_logs.elapsed_ms
    `);

    // Always acknowledge the client_event_log_id so the client can clear its sync queue
    processedIds.push(clientEventLogId);
  }

  res.json({ processedIds });
});

export default router;
