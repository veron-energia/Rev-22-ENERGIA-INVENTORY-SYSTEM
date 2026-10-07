// Renders the Store and Warehouse stock pages and a customer's loans against
// an in-memory stub (scripts/stock-loans/preview), so Record Use, Lend, the On
// loan list and Take back can be pressed without a database or a login.
// ?role=staff|manager|admin|owner picks who is signed in (default owner).
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/stock-loans/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/stock-loans/preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/stock-loans/preview/supabase-stub.ts') },
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/stock-loans/preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/stock-loans/preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5211, strictPort: true },
});
