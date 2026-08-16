import { pgTable, text, timestamp, pgEnum } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const userRoleEnum = pgEnum("user_role", ["super_admin", "host", "runner"]);
export const authProviderEnum = pgEnum("auth_provider", ["clerk", "google", "apple", "email"]);
export const genderEnum = pgEnum("gender", ["male", "female", "non_binary", "prefer_not_to_say"]);

export const usersTable = pgTable("users", {
  id: text("id").primaryKey(), // Clerk user ID
  email: text("email").notNull(),
  authProvider: authProviderEnum("auth_provider").notNull().default("clerk"),
  role: userRoleEnum("role").notNull().default("runner"),
  gender: genderEnum("gender"),
  birthdate: text("birthdate"), // YYYY-MM-DD
  preferredName: text("preferred_name"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const insertUserSchema = createInsertSchema(usersTable).omit({ createdAt: true, updatedAt: true });
export type InsertUser = z.infer<typeof insertUserSchema>;
export type User = typeof usersTable.$inferSelect;
