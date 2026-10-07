// Renders the Invoices page against an in-memory stub (399): a part-paid
// invoice with a pillow already handed over and a set whose contents are still
// to collect, and an unpaid one with goods out, so Record Payment's "Did the
// customer take any goods now?", Hand over items, Record items returned, the
// "Goods out" badge and the copies' Collected / To collect can be pressed
// without a database or a login. ?role=staff hides Record items returned.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/invoices/handover-preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/invoices/handover-preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/invoices/handover-preview/supabase-stub.ts') },
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/invoices/handover-preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/invoices/handover-preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5183, strictPort: true },
});
