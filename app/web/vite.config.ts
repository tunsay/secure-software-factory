import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // En dev, l'API tourne sur :8000 ; en prod, nginx proxifie /api → api:8000.
    proxy: { "/api": { target: "http://localhost:8000", rewrite: (p) => p.replace(/^\/api/, "") } },
  },
  build: {
    sourcemap: false,
    target: "es2022",
  },
});
