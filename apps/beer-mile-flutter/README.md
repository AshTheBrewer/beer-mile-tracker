# Beer Mile Flutter App

Multi-tenant Beer Mile race timing app for iOS and Android.

## Architecture

| Layer | Technology |
|-------|-----------|
| UI | Flutter 3.x, Material 3 |
| State Management | Riverpod |
| Local Database | SQLCipher via sqflite_sqlcipher (AES-256 encrypted at rest) |
| Auth | Clerk — WebView-based OAuth hosted sign-in |
| API Client | Typed Dart HTTP client (matches `lib/api-spec/openapi.yaml`) |
| Navigation | go_router |
| Background Sync | WorkManager (Android) / BGTaskScheduler via workmanager plugin |
| NFC | nfc_manager |
| QR Scanner | mobile_scanner |
| QR Generator | qr_flutter |

## Prerequisites

```
Flutter SDK >= 3.19 (Dart >= 3.3)
Xcode >= 15 (for iOS builds)
Android Studio with Android SDK 34 (for Android builds)
```

Verify your installation:

```bash
flutter doctor -v
```

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Configure build-time variables

The app uses `--dart-define` to inject environment variables at compile time.
Create a `dart-defines.env` file (never commit this) with:

```
API_BASE_URL=https://your-api.replit.dev/api
CLERK_FRONTEND_API_DOMAIN=your-app.clerk.accounts.dev
NFC_HMAC_SECRET=your-shared-hmac-secret
```

### 3. Analyse the codebase

```bash
flutter analyze
```

All issues should be zero warnings, zero errors.

## Building

### iOS

```bash
flutter build ios \
  --dart-define=API_BASE_URL=https://your-api.replit.dev/api \
  --dart-define=CLERK_FRONTEND_API_DOMAIN=your-app.clerk.accounts.dev \
  --dart-define=NFC_HMAC_SECRET=your-secret
```

Then open `ios/Runner.xcworkspace` in Xcode, select a real device or simulator,
and run.

**iOS NFC requirement**: NFC tag reading and writing requires a physical iPhone
(XS or later). You must add the NFC entitlement in Xcode:

1. Target → Signing & Capabilities → + Capability → Near Field Communication Tag Reading

### Android

```bash
flutter build appbundle \
  --dart-define=API_BASE_URL=https://your-api.replit.dev/api \
  --dart-define=CLERK_FRONTEND_API_DOMAIN=your-app.clerk.accounts.dev \
  --dart-define=NFC_HMAC_SECRET=your-secret
```

Upload the `.aab` from `build/app/outputs/bundle/release/` to Google Play.

## Running locally (development)

```bash
flutter run \
  --dart-define=API_BASE_URL=https://your-api.replit.dev/api \
  --dart-define=CLERK_FRONTEND_API_DOMAIN=your-app.clerk.accounts.dev \
  --dart-define=NFC_HMAC_SECRET=dev-secret
```

## Local Database

The app uses **SQLCipher** (via `sqflite_sqlcipher`) for the local offline
database.  The database file is encrypted at rest with AES-256.  Tables are
created and migrated in `lib/database/app_database.dart`.  No code generation
step is required — `flutter pub get` is sufficient.

### Encryption key

A random 32-byte key is generated on first launch and stored in
`FlutterSecureStorage` (Android Keystore / iOS Keychain).  The key is never
stored in plaintext or `SharedPreferences`.

### PII policy

Display names, email addresses, and other personal data are **never written to
SQLite**.  The local database stores only opaque IDs (integer registration IDs,
Clerk user ID strings).  Names are held in memory during a scanner session only
and are discarded when the screen closes.  See `SECURITY.md` for the full
on-device / server-only data boundary.

### Inspecting the database during development

The database is encrypted, so standard SQLite tools cannot read it directly.
Use the `sqlcipher` CLI with the key from FlutterSecureStorage:

```bash
# Android emulator — find the database file
adb shell "run-as com.beermile.app ls /data/data/com.beermile.app/databases/"
```

## Clerk Auth

The sign-in flow uses Clerk's **hosted sign-in page** loaded inside a WebView.
After the user authenticates, a JavaScript poller detects the established Clerk
session and forwards the JWT to the Flutter layer via a JavaScript channel.

Configure your Clerk dashboard:

1. Set the **Redirect URL** allow-list to include `beermile://auth-callback`
2. Enable the OAuth providers you want (Google, Apple, Email/Password)
3. For Google OAuth on iOS, add your reversed client ID to `CFBundleURLSchemes`

## NFC Tag Payload Format

Tags are written by the Host Console during the **Tag Provisioning** flow:

```
<registrationId>:<eventId>:<nonce>:<hmac>
```

- `registrationId` — numeric ID of the runner's registration
- `eventId` — numeric ID of the event
- `nonce` — UUID v4 (no dashes, 32 hex chars)
- `hmac` — first 16 chars of HMAC-SHA256(`registrationId:eventId:nonce`, `NFC_HMAC_SECRET`)

The Scanner Mode screen looks up the runner from the local sqflite token cache
(populated during Pre-Race Sync) for a fast offline read.

> **Security note**: The `NFC_HMAC_SECRET` is compiled into the app binary via
> `--dart-define`. This provides **tag integrity against casual forgery** (a
> random NFC tag without the payload format won't match), but it is **not a
> strong security boundary** — the secret can be extracted from the binary by a
> motivated attacker. The Scanner does not re-validate the HMAC at scan time;
> it trusts that the tag token matches an entry in the local runner-token cache
> which was populated from the server during Pre-Race Sync. For higher-assurance
> deployments, move HMAC signing to the backend (`POST /events/:id/tags`) and
> have the scanner verify the payload with a public key or server round-trip.

## Offline-First Sync

```
Scan → Local sqflite write (is_synced=0) → Immediate ACK
     ↓
Connectivity restored → SyncEngine.syncPendingLogs()
     ↓
POST /api/lap-logs (50 records/batch, idempotent by clientEventLogId)
     ↓
Server returns processedIds → Local records marked is_synced=1
```

Pre-Race Sync (`SyncEngine.preRaceSync`) downloads the event profile, confirmed
registrations, and runner tokens into sqflite before race start so the app works
fully offline.

## Screen Map

| Route | Who sees it | Description |
|-------|------------|-------------|
| `/sign-in` | Anyone | Clerk WebView auth |
| `/runner/events` | Runner | Browse public events |
| `/runner/events/:id` | Runner | Event detail + registration |
| `/runner/events/:id/leaderboard` | Anyone | Live leaderboard |
| `/runner/profile` | Authenticated | Profile + sign-out |
| `/host` | Host | Host console + event list |
| `/host/events/new` | Host | Create event |
| `/host/events/:id/edit` | Host | Edit event |
| `/host/events/:id/registrations` | Host | Registrations + payment confirm |
| `/host/events/:id/tags` | Host | NFC/QR tag provisioning |
| `/host/events/:id/scanner` | Host | Scanner Mode (race day) |
| `/admin` | Super Admin | Analytics dashboard |
| `/admin/platform-settings` | Super Admin | App Store / Play Store URLs |

## Project Structure

```
lib/
├── main.dart                 # Entry point, WorkManager init
├── app.dart                  # MaterialApp.router, go_router
├── core/
│   ├── config.dart           # API URL, Clerk domain (--dart-define)
│   └── theme.dart            # Material 3 light/dark + Scanner Mode theme
├── auth/
│   ├── auth_repository.dart  # JWT storage, provision, restore session
│   └── models/user_model.dart
├── api/
│   ├── api_client.dart       # Typed HTTP client for all API endpoints
│   └── models/               # Dart models matching OpenAPI schemas
├── database/
│   ├── app_database.dart     # sqflite schema + migrations
│   └── daos/                 # Type-safe DAOs (events, registrations, lap_logs)
├── providers/                # Riverpod providers
├── sync/
│   └── sync_engine.dart      # Pre-race sync, batch upload, connectivity listener
├── screens/
│   ├── auth/                 # Sign-in (Clerk WebView)
│   ├── runner/               # Event browse, detail, leaderboard, profile
│   ├── host/                 # Host console, event form, registrations, tags
│   ├── scanner/              # Scanner Mode (race day full-screen)
│   └── admin/                # Analytics dashboard, platform settings
└── widgets/                  # SyncStatusBanner, EmptyState, LoadingIndicator
```
