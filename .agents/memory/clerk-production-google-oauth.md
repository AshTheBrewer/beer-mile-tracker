---
name: Clerk production Google OAuth
description: Google social sign-in setup requirements for the external Clerk Production instance.
---

Clerk Production requires a Google OAuth client ID and secret configured as custom credentials for its Google social connection. Development's shared Google credentials do not carry over to Production. A Google error stating that `client_id` is missing points to the Production connection's missing or unsaved client ID, rather than an app-code or CNAME problem.

**Why:** Clerk keeps Development and Production provider configuration separate, and production OAuth credentials are supplied by the application owner.

**How to apply:** In Clerk's external Production instance, configure Google under SSO connections with custom credentials. Create a Google Web OAuth client if needed, use the exact Authorized Redirect URI Clerk displays, then save the client ID and secret directly in Clerk. Never request or store those credentials in chat or project memory.