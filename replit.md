# Beer Mile Tracker

A multi-tenant Beer Mile event tracking platform. Hosts create and manage race events; runners register, get tagged with NFC/QR, and are timed lap-by-lap. The Flutter frontend compiles natively for iOS and Android. This repo contains the backend API and shared TypeScript libraries.

## Run & Operate

- `pnpm --filter @workspace/api-server run dev` — run the API server (port from env)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- `pnpm --filter @workspace/api-server run seed` — seed demo data (requires built dist/)

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- API: Express 5 + Clerk auth (`@clerk/express`)
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (ESM bundle)
- Frontend: Flutter/Dart (compile locally with `flutter build ios` / `flutter build appbundle`)

## Where things live

- `lib/api-spec/openapi.yaml` — single source of truth for all API contracts
- `lib/db/src/schema/` — Drizzle ORM table definitions (one file per entity)
- `artifacts/api-server/src/routes/` — Express route handlers (one file per domain)
- `artifacts/api-server/src/middlewares/requireAuth.ts` — Clerk JWT auth + role guard
- `artifacts/api-server/src/scripts/seed.ts` — demo data seeder
- `apps/beer-mile-flutter/` — Flutter app (Task #2, not yet built)

## API Routes

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/healthz | — | Health check |
| POST | /api/users/me/provision | auth | Create-or-fetch user from Clerk JWT |
| GET | /api/users/me | auth | Get current user |
| PATCH | /api/users/me | auth | Update profile |
| GET | /api/tenants/me | auth | Get host's tenant |
| POST | /api/tenants/me | auth | Create tenant (promotes user to host) |
| GET | /api/events | — | List all events |
| POST | /api/events | host | Create event |
| POST | /api/events/join | — | Find event by private code |
| GET | /api/events/:id | — | Get event detail |
| PATCH | /api/events/:id | host/admin | Update event |
| DELETE | /api/events/:id | host/admin | Delete event |
| GET | /api/events/:id/registrations | host/admin | List registrations + runner info |
| POST | /api/events/:id/registrations | auth | Register current user |
| PATCH | /api/registrations/:id | host/runner/admin | Update payment status, tag UID |
| POST | /api/lap-logs | auth | Bulk ingest lap logs (idempotent) |
| GET | /api/events/:id/leaderboard | — | Race leaderboard with splits |
| GET | /api/admin/analytics | super_admin | Platform-wide analytics |
| GET | /api/admin/tenants | super_admin | List all tenants |
| GET | /api/platform-settings | — | App Store / Play Store URLs |
| PATCH | /api/platform-settings | super_admin | Update platform settings |

## Architecture decisions

- **Multi-tenancy via tenant table**: hosts own a tenant row; events FK to tenant; all host routes verify ownership before mutation.
- **Earliest Scan Wins deduplication**: lap log ingest compares `elapsed_ms` per `(registration_id, lap_number)` and keeps the lowest value, replacing any slower existing record. Idempotency is ensured by `client_event_log_id` UUID.
- **Clerk auth is role-aware**: on every authenticated request, `requireAuth` middleware reads the user's role from the DB (not the JWT claim) so role changes are reflected immediately without re-issuing tokens.
- **OpenAPI spec is the contract**: `lib/api-spec/openapi.yaml` gates all codegen. Query params are intentionally omitted from the spec (the Flutter client calls the API directly; the React Query hooks are for future web frontend use).
- **Integer fields are `type: number` in OpenAPI**: Orval 8.x generates `zod.int()` for `type: integer`, which is Zod v4 API not available in the workspace's Zod v3. Using `type: number` generates `zod.number()` which works in both.

## Product

Multi-tenant race timing platform for Beer Mile events. Three roles:
- **Super Admin**: platform analytics, tenant management, app store link settings
- **Host/Tenant**: create events, manage registrations, provision NFC/QR tags, run Scanner Mode during races
- **Runner**: browse/join events, register, view personal history and live leaderboards

Offline-first design: all lap scans write locally first with <50ms response; background sync pushes to server in batches when connectivity is restored.

## User preferences

_Populate as you build._

## Gotchas

- Run `pnpm --filter @workspace/api-spec run codegen` after any OpenAPI spec change before touching route files — the Zod validators are generated.
- The seed script requires a built dist (`pnpm --filter @workspace/api-server run build` first).
- `type: integer` in the OpenAPI spec generates `zod.int()` (Zod v4) which fails typecheck. Always use `type: number` instead.
- Orval generates `<OperationId>Params` in both `generated/api.ts` (Zod) and `generated/types/` (TS type), causing TS2308 collisions for any endpoint with query parameters. Keep query params out of the OpenAPI spec.
- Flutter app lives in `apps/beer-mile-flutter/` (Task #2). Compile locally with `flutter build ios` or `flutter build appbundle`.

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
- See `lib/api-spec/openapi.yaml` for the full API contract
