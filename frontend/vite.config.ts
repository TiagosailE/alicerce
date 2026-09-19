import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

const rails = "http://localhost:3000";

export default defineConfig(({ command }) => ({
  base: command === "build" ? "/spa/" : "/",
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "../public/spa",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": rails,
      "/up": rails,
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
  },
}));
