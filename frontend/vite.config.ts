import { mkdirSync, renameSync } from "node:fs";
import { resolve } from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import type { Plugin } from "vite";
import { defineConfig } from "vitest/config";

const rails = "http://localhost:3000";
const assetsDir = resolve(import.meta.dirname, "../public/spa");
const shellDir = resolve(import.meta.dirname, "dist");

/**
 * Moves the built index.html out of public/, so the only way to get the shell
 * is through SpaController, which adds the CSP. Hashed assets stay in public/.
 */
function shellOutsidePublic(): Plugin {
  return {
    name: "shell-outside-public",
    apply: "build",
    closeBundle() {
      mkdirSync(shellDir, { recursive: true });
      renameSync(resolve(assetsDir, "index.html"), resolve(shellDir, "index.html"));
    },
  };
}

export default defineConfig(({ command }) => ({
  base: command === "build" ? "/spa/" : "/",
  plugins: [react(), tailwindcss(), shellOutsidePublic()],
  build: {
    outDir: assetsDir,
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": rails,
      "/up": rails,
      "/theme-init.js": rails,
    },
  },
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.{ts,tsx}"],
    setupFiles: ["./src/test/setup.ts"],
  },
}));
