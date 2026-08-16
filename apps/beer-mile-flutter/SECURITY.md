# Security & Data Boundary

## Overview

The Beer Mile app has two data stores:

| Store | Technology | Encrypted |
|-------|-----------|-----------|
| Server | PostgreSQL (Replit-managed) | Yes — TLS in transit, disk encryption at rest |
| On-device | SQLite via SQLCipher | Yes — AES-256 at rest, key in FlutterSecureStorage |

---

## On-Device SQLite — Sync Boundary

The table below lists **every column** in the local SQLite database and whether
it is allowed to be stored on the device.

### `events`

| Column | On-device? | Notes |
|--------|-----------|-------|
| `id` | ✅ | Opaque integer PK |
| `tenant_id` | ✅ | Opaque integer FK |
| `title` | ✅ | Public event name |
| `event_code` | ✅ | Public join code |
| `event_date` | ✅ | Public date string |
| `location_name` | ✅ | Public venue name |
| `location_lat` | ✅ | Public GPS lat |
| `location_lng` | ✅ | Public GPS lng |
| `beer_type` | ✅ | Public info |
| `entry_fee` | ✅ | Public info |
| `payment_instructions` | ✅ | Public info |
| `prizes_json` | ✅ | Public info |
| `status` | ✅ | Public event state |
| `created_at` / `updated_at` | ✅ | Timestamps |

### `registrations`

| Column | On-device? | Notes |
|--------|-----------|-------|
| `id` | ✅ | Opaque integer PK |
| `event_id` | ✅ | Opaque integer FK |
| `user_id` | ✅ | Opaque Clerk user ID string |
| `payment_status` | ✅ | `pending` or `confirmed` — no PII |
| `tag_uid` | ✅ | NFC hardware UID — no PII |
| `runner_token` | ✅ | Opaque HMAC token |
| `registered_at` / `updated_at` | ✅ | Timestamps |
| `preferred_name` | ❌ **SERVER-ONLY** | PII — never cached locally |
| `email` | ❌ **SERVER-ONLY** | PII — never cached locally |
| `gender` | ❌ **SERVER-ONLY** | PII — never cached locally |
| `birthdate` | ❌ **SERVER-ONLY** | PII — never cached locally |

### `lap_logs`

| Column | On-device? | Notes |
|--------|-----------|-------|
| `id` | ✅ | Autoincrement local PK |
| `client_event_log_id` | ✅ | UUID for idempotent upload |
| `registration_id` | ✅ | Opaque integer FK |
| `lap_number` | ✅ | 1–4 |
| `elapsed_ms` | ✅ | Race telemetry — no PII |
| `split_time_ms` | ✅ | Race telemetry — no PII |
| `pour_confirmed` | ✅ | Boolean flag |
| `is_synced` | ✅ | Upload state flag |
| `device_monotonic_timestamp` | ✅ | Device clock — no PII |
| `logged_at` | ✅ | Wall-clock timestamp |

### `runner_tokens`

| Column | On-device? | Notes |
|--------|-----------|-------|
| `runner_token` | ✅ | Opaque HMAC token — PK |
| `registration_id` | ✅ | Opaque integer FK |
| `event_id` | ✅ | Opaque integer FK |
| `user_id` | ✅ | Opaque Clerk user ID string |
| `display_name` | ❌ **SERVER-ONLY** | PII — removed in schema v2 |

> **Rule**: If you are adding a column to any of the above tables, ask "does
> this column identify or describe a natural person?"  If yes, it is
> **server-only** — do not add it to the local schema or write it in a DAO.

---

## Encryption Key Management

1. On first launch, `AppDatabase._getOrCreateKey()` generates a random 32-byte
   key using `Random.secure()`.
2. The key is stored as a hex string in `FlutterSecureStorage`:
   - **Android**: `EncryptedSharedPreferences` backed by the Android Keystore.
   - **iOS**: iOS Keychain with `kSecAttrAccessibleAfterFirstUnlock`.
3. The key is read from secure storage every time the database is opened; it is
   never stored in plaintext or in `SharedPreferences`.
4. The database file itself is encrypted at rest with SQLCipher (AES-256-CBC).

---

## Session Token (Clerk JWT)

- Stored **only** in `FlutterSecureStorage` (key: `clerk_session_token`).
- Never written to SQLite or `SharedPreferences`.
- The WorkManager background-sync isolate reads it from `FlutterSecureStorage`
  after calling `WidgetsFlutterBinding.ensureInitialized()`.
- Cleared on sign-out via `AuthRepository.signOut()`.
- A one-time migration (`AuthMigrations.v1`) removes any legacy
  `bg_sync_token` entry that may have been written by an older build.

---

## In-Memory PII (Runner Names)

During a scanner session, the app holds a `Map<int, String>` of
`registrationId → displayName` in the `_ScannerModeScreenState` widget tree.
This map is:
- Populated from the API response during **Pre-Race Sync** (names are returned
  by the server but never written to SQLite).
- Discarded when the scanner screen is closed (widget dispose).
- Not accessible to background isolates.

When the scanner is operating **offline** (no network), the fallback label
`"Runner #<id>"` is shown.  The name is resolved from the in-memory map if the
pre-race sync succeeded, or from the server if a network call was feasible.

---

## NFC Tag Security

NFC runner tokens are HMAC-SHA256 payloads compiled with a shared secret
(`--dart-define=NFC_HMAC_SECRET`).  The tokens protect against casual tag
forgery but are **not a strong security boundary** because the secret is in the
app binary.  See the NFC section of `README.md` for the full threat model and
guidance on upgrading to server-signed tokens.
