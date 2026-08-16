import { db, usersTable, tenantsTable, eventsTable, platformSettingsTable } from "@workspace/db";
import { eq } from "drizzle-orm";
import { logger } from "../lib/logger";

async function seed() {
  logger.info("Starting seed...");

  // Create super admin user (placeholder — Clerk user IDs come from auth)
  const superAdminId = "seed_super_admin_001";
  const [existingAdmin] = await db
    .select()
    .from(usersTable)
    .where(eq(usersTable.id, superAdminId));

  if (!existingAdmin) {
    await db.insert(usersTable).values({
      id: superAdminId,
      email: "admin@beermile.dev",
      role: "super_admin",
      preferredName: "Admin",
    });
    logger.info("Created super admin user");
  }

  // Create host user
  const hostId = "seed_host_001";
  const [existingHost] = await db
    .select()
    .from(usersTable)
    .where(eq(usersTable.id, hostId));

  if (!existingHost) {
    await db.insert(usersTable).values({
      id: hostId,
      email: "host@beermile.dev",
      role: "host",
      preferredName: "Demo Host",
    });
    logger.info("Created host user");
  }

  // Create tenant
  const [existingTenant] = await db
    .select()
    .from(tenantsTable)
    .where(eq(tenantsTable.userId, hostId));

  let tenantId: number;
  if (!existingTenant) {
    const [tenant] = await db
      .insert(tenantsTable)
      .values({ userId: hostId, organizationName: "Demo Beer Mile Club" })
      .returning();
    tenantId = tenant.id;
    logger.info({ tenantId }, "Created tenant");
  } else {
    tenantId = existingTenant.id;
  }

  // Create sample event
  const sampleEventCode = "DEMO01";
  const [existingEvent] = await db
    .select()
    .from(eventsTable)
    .where(eq(eventsTable.eventCode, sampleEventCode));

  if (!existingEvent) {
    const eventDate = new Date();
    eventDate.setDate(eventDate.getDate() + 14);
    const eventDateStr = eventDate.toISOString().split("T")[0];

    await db.insert(eventsTable).values({
      tenantId,
      title: "Summer Beer Mile Classic",
      eventCode: sampleEventCode,
      eventDate: eventDateStr,
      locationName: "Central Park Track",
      locationLat: 40.7851,
      locationLng: -73.9683,
      beerType: "Lager (4 oz per lap)",
      entryFee: "$10",
      paymentInstructions: "Venmo @DemoBeerMile or pay cash at check-in",
      prizesJson: [
        { position: 1, description: "Gold medal + $50 gift card" },
        { position: 2, description: "Silver medal + $25 gift card" },
        { position: 3, description: "Bronze medal" },
      ],
      status: "open",
    });
    logger.info("Created sample event");
  }

  // Initialize platform settings if not present
  const [existingSettings] = await db.select().from(platformSettingsTable);
  if (!existingSettings) {
    await db.insert(platformSettingsTable).values({
      appStoreIosUrl: null,
      playStoreAndroidUrl: null,
    });
    logger.info("Initialized platform settings");
  }

  logger.info("Seed complete");
}

seed().catch((err) => {
  logger.error(err, "Seed failed");
  process.exit(1);
});
