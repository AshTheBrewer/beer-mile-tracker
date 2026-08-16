import { pgTable, text, serial, timestamp } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const platformSettingsTable = pgTable("platform_settings", {
  id: serial("id").primaryKey(),
  appStoreIosUrl: text("app_store_ios_url"),
  playStoreAndroidUrl: text("play_store_android_url"),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const insertPlatformSettingsSchema = createInsertSchema(platformSettingsTable).omit({ id: true, updatedAt: true });
export type InsertPlatformSettings = z.infer<typeof insertPlatformSettingsSchema>;
export type PlatformSettings = typeof platformSettingsTable.$inferSelect;
