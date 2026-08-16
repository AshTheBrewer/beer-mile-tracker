import { pgTable, text, serial, timestamp, integer, boolean, bigint, unique } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { registrationsTable } from "./registrations";

export const lapLogsTable = pgTable("lap_logs", {
  id: serial("id").primaryKey(),
  // clientEventLogId is stored for audit/idempotency tracking but is NOT unique —
  // the uniqueness key is (registration_id, lap_number). An atomic upsert keeps
  // the fastest (lowest elapsed_ms) record per runner per lap.
  clientEventLogId: text("client_event_log_id").notNull(),
  registrationId: serial("registration_id").notNull().references(() => registrationsTable.id),
  lapNumber: integer("lap_number").notNull(), // 1-4
  splitTimeMs: bigint("split_time_ms", { mode: "number" }), // lap split in ms
  elapsedMs: bigint("elapsed_ms", { mode: "number" }).notNull(), // total elapsed from T0
  pourConfirmed: boolean("pour_confirmed").notNull().default(false),
  isSynced: boolean("is_synced").notNull().default(true),
  deviceMonotonicTimestamp: bigint("device_monotonic_timestamp", { mode: "number" }),
  loggedAt: timestamp("logged_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  // Enforce "one lap record per runner per lap" at the DB level.
  // The route uses INSERT ON CONFLICT DO UPDATE with a WHERE clause to atomically
  // keep the earliest (lowest elapsedMs) scan — "Earliest Scan Wins".
  unique("lap_logs_registration_lap_unique").on(t.registrationId, t.lapNumber),
]);

export const insertLapLogSchema = createInsertSchema(lapLogsTable).omit({ id: true, loggedAt: true });
export type InsertLapLog = z.infer<typeof insertLapLogSchema>;
export type LapLog = typeof lapLogsTable.$inferSelect;
