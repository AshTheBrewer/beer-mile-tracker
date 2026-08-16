import { pgTable, text, serial, timestamp, real, jsonb } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { tenantsTable } from "./tenants";

export const eventStatusEnum = ["draft", "open", "active", "completed", "cancelled"] as const;

export const eventsTable = pgTable("events", {
  id: serial("id").primaryKey(),
  tenantId: serial("tenant_id").notNull().references(() => tenantsTable.id),
  title: text("title").notNull(),
  eventCode: text("event_code").notNull().unique(),
  eventDate: text("event_date").notNull(), // YYYY-MM-DD
  locationLat: real("location_lat"),
  locationLng: real("location_lng"),
  locationName: text("location_name"),
  beerType: text("beer_type"),
  entryFee: text("entry_fee"),
  paymentInstructions: text("payment_instructions"),
  prizesJson: jsonb("prizes_json").$type<{ description: string; position: number }[]>(),
  status: text("status").notNull().default("draft"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const insertEventSchema = createInsertSchema(eventsTable).omit({ id: true, createdAt: true, updatedAt: true });
export type InsertEvent = z.infer<typeof insertEventSchema>;
export type Event = typeof eventsTable.$inferSelect;
