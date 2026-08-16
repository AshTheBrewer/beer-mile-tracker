import { pgTable, text, serial, timestamp, unique } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { eventsTable } from "./events";
import { usersTable } from "./users";

export const registrationsTable = pgTable("registrations", {
  id: serial("id").primaryKey(),
  eventId: serial("event_id").notNull().references(() => eventsTable.id),
  userId: text("user_id").notNull().references(() => usersTable.id),
  paymentStatus: text("payment_status").notNull().default("pending"), // pending | confirmed
  tagUid: text("tag_uid"),
  runnerToken: text("runner_token"),
  registeredAt: timestamp("registered_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
}, (t) => [
  // Enforce at the DB level: one registration per user per event
  unique("registrations_event_user_unique").on(t.eventId, t.userId),
]);

export const insertRegistrationSchema = createInsertSchema(registrationsTable).omit({ id: true, registeredAt: true, updatedAt: true });
export type InsertRegistration = z.infer<typeof insertRegistrationSchema>;
export type Registration = typeof registrationsTable.$inferSelect;
