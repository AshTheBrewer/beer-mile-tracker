---
name: Railway service boundaries
description: Why a root start script is not the right fix for unrelated Railway services
---

Do not add a root start script that launches the API merely to satisfy Railway start-command detection for every service.

**Why:** This repository contains multiple workspaces. An unrelated service configured at the repository root could then run a duplicate API process rather than its intended application. The missing start-command failure is separate from the API's pnpm install failure.

**How to apply:** Identify which Railway service is failing and configure or disable that service explicitly. Keep the API build/install fix separate from service-specific launch configuration.