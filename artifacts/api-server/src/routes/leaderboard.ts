import { Router, type IRouter } from "express";
import { eq, and, sql } from "drizzle-orm";
import { db, eventsTable, registrationsTable, lapLogsTable, usersTable } from "@workspace/db";

const router: IRouter = Router();

// GET /events/:id/leaderboard
router.get("/events/:id/leaderboard", async (req, res): Promise<void> => {
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

  const filter = req.query.filter as string | undefined;

  // Get all confirmed registrations + user info
  let regsQuery = db
    .select({
      regId: registrationsTable.id,
      userId: registrationsTable.userId,
      preferredName: usersTable.preferredName,
      gender: usersTable.gender,
      birthdate: usersTable.birthdate,
    })
    .from(registrationsTable)
    .leftJoin(usersTable, eq(registrationsTable.userId, usersTable.id))
    .where(
      and(
        eq(registrationsTable.eventId, id),
        eq(registrationsTable.paymentStatus, "confirmed"),
      ),
    );

  const regs = await regsQuery;

  // Filter by gender if requested
  const filteredRegs =
    filter && filter !== "overall"
      ? regs.filter((r) => r.gender === filter)
      : regs;

  // Get all lap logs for this event's registrations
  const regIds = filteredRegs.map((r) => r.regId);
  if (regIds.length === 0) {
    res.json([]);
    return;
  }

  const allLaps = await db
    .select()
    .from(lapLogsTable)
    .where(sql`registration_id = ANY(${sql`ARRAY[${sql.join(regIds.map(id => sql`${id}`), sql`, `)}]::int[]`})`);

  // Build leaderboard entries
  const entries = filteredRegs.map((reg) => {
    const laps = allLaps
      .filter((l) => l.registrationId === reg.regId)
      .sort((a, b) => a.lapNumber - b.lapNumber);

    const maxLap = laps.length > 0 ? Math.max(...laps.map((l) => l.lapNumber)) : 0;
    const totalElapsedMs = laps.length > 0 ? Math.max(...laps.map((l) => l.elapsedMs)) : 0;
    const finished = maxLap >= 4 && laps.length >= 4;

    return {
      registrationId: reg.regId,
      userId: reg.userId,
      preferredName: reg.preferredName,
      gender: reg.gender,
      totalElapsedMs,
      lapCount: laps.length,
      finished,
      laps: laps.map((l) => ({
        lapNumber: l.lapNumber,
        elapsedMs: l.elapsedMs,
        splitTimeMs: l.splitTimeMs,
        pourConfirmed: l.pourConfirmed,
      })),
    };
  });

  // Sort: finishers first (by total time), then by lap count
  entries.sort((a, b) => {
    if (a.finished && !b.finished) return -1;
    if (!a.finished && b.finished) return 1;
    if (a.finished && b.finished) return a.totalElapsedMs - b.totalElapsedMs;
    return b.lapCount - a.lapCount;
  });

  res.json(entries);
});

export default router;
