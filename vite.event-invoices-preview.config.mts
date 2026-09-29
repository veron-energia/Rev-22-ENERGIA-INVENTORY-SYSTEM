// Renders the Invoices page against an in-memory stub holding one event, so
// selling an event ticket (days, a name for every person, the early-bird
// price) and correcting it can be checked without a database or a login.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/events/invoice-preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/events/invoice-preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/events/invoice-preview/supabase-stub.ts') },
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/events/invoice-preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/events/invoice-preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5191, strictPort: true },
});
