// Renders the real AffiliateLayout against a stubbed auth context, so the
// portal's navigation can be checked at real laptop and phone widths without a
// database or a login. Used to diagnose a report of "no sidebar, no hamburger".
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/affiliate/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/affiliate/preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/affiliate/preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5196, strictPort: true },
});
