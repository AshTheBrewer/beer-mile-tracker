---
name: Static asset serving
description: Filesystem path normalization and SPA fallback behavior for production static servers
---

Normalize the resolved public directory before comparing requested asset paths against it. For missing asset URLs, return a non-cacheable 404 instead of the SPA document; serve the SPA document only for route-like paths.

**Why:** A trailing separator on the public root can make a correct containment check reject every child path. If the request then falls through to the SPA fallback, the browser receives HTML for a JavaScript or CSS URL and reports a misleading MIME-type error.

**How to apply:** Resolve both the configured public root and each requested file to canonical filesystem paths. Test a real emitted JS/CSS asset, a missing hashed asset, and a client-side route separately.