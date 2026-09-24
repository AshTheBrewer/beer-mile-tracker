---
name: Clerk proxy 403 responses
description: Diagnosing Clerk Frontend API proxy asset requests rejected with Cloudflare error code 1000.
---

When `/api/__clerk/npm/...` returns `403` with the plain-text body `error code: 1000`, the request can be reaching Clerk's Frontend API and being rejected because of the `Clerk-Secret-Key` proxy credential. A direct asset request without proxy headers may still return 200; an invalid proxy secret can reproduce the same 403 response.

**Why:** A production asset request returning HTML or plain text instead of JavaScript makes the browser report a MIME/failed-script error, which can look like a static-file problem even though the proxy is forwarding Clerk's rejection.

**How to apply:** Verify Railway's API service uses the live secret key paired with the production publishable key embedded in the web build. If that pair is correct, verify the production Clerk instance permits the configured proxy origin. Do not change asset serving or the canonical proxy middleware based only on this symptom.