import { Router, type IRouter } from "express";
import { eq } from "drizzle-orm";
import { createClerkClient, getAuth } from "@clerk/express";
import { db, usersTable, tenantsTable } from "@workspace/db";
import { requireAuth } from "../middlewares/requireAuth";
import {
  ProvisionUserBody,
  UpdateMeBody,
  CreateTenantBody,
} from "@workspace/api-zod";

const router: IRouter = Router();

function getClerk() {
  return createClerkClient({ secretKey: process.env.CLERK_SECRET_KEY });
}

// POST /users/me/provision — create or fetch user; email comes from Clerk, role always defaults to runner
router.post("/users/me/provision", requireAuth, async (req, res): Promise<void> => {
  const parsed = ProvisionUserBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const userId = req.userId!;

  const [existing] = await db
    .select()
    .from(usersTable)
    .where(eq(usersTable.id, userId));

  if (existing) {
    res.json(existing);
    return;
  }

  // Fetch authoritative identity data from Clerk — never trust caller-supplied email/role
  const clerkUser = await getClerk().users.getUser(userId);
  const email =
    clerkUser.emailAddresses.find((e) => e.id === clerkUser.primaryEmailAddressId)
      ?.emailAddress ?? clerkUser.emailAddresses[0]?.emailAddress ?? "";

  const [created] = await db
    .insert(usersTable)
    .values({
      id: userId,
      email,
      preferredName: parsed.data.preferredName ?? clerkUser.firstName ?? null,
      role: "runner", // always start as runner; privileged roles granted by admin only
    })
    .returning();

  res.status(201).json(created);
});

// GET /users/me
router.get("/users/me", requireAuth, async (req, res): Promise<void> => {
  const [user] = await db
    .select()
    .from(usersTable)
    .where(eq(usersTable.id, req.userId!));

  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(user);
});

// PATCH /users/me — only profile fields; role is not changeable by the user themselves
router.patch("/users/me", requireAuth, async (req, res): Promise<void> => {
  const parsed = UpdateMeBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [updated] = await db
    .update(usersTable)
    .set(parsed.data)
    .where(eq(usersTable.id, req.userId!))
    .returning();

  if (!updated) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(updated);
});

// GET /tenants/me
router.get("/tenants/me", requireAuth, async (req, res): Promise<void> => {
  const [tenant] = await db
    .select()
    .from(tenantsTable)
    .where(eq(tenantsTable.userId, req.userId!));

  if (!tenant) {
    res.status(404).json({ error: "Tenant not found" });
    return;
  }
  res.json(tenant);
});

// POST /tenants/me — promotes the user to host role and creates their tenant
router.post("/tenants/me", requireAuth, async (req, res): Promise<void> => {
  const parsed = CreateTenantBody.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message });
    return;
  }

  const [existing] = await db
    .select()
    .from(tenantsTable)
    .where(eq(tenantsTable.userId, req.userId!));

  if (existing) {
    res.status(409).json({ error: "Tenant already exists" });
    return;
  }

  // Promote to host
  await db
    .update(usersTable)
    .set({ role: "host" })
    .where(eq(usersTable.id, req.userId!));

  const [created] = await db
    .insert(tenantsTable)
    .values({ userId: req.userId!, organizationName: parsed.data.organizationName })
    .returning();

  res.status(201).json(created);
});

export default router;
