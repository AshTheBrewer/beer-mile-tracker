import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    // Vitest handles TypeScript via esbuild — no separate tsconfig needed.
    // Workspace packages are resolved via pnpm's node_modules symlinks.
  },
});
