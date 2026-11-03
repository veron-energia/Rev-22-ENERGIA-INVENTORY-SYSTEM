// Renders the real AffiliateLayout against a stubbed auth context, so the
// portal's navigation can be checked at real laptop and phone widths without a
// database or a login. Used to diagnose a report of "no sidebar, no hamburger".
// The email warning above the page (3 Nov 2026) answers from
// scripts/affiliate/preview/supabase-stub.ts; ?verified=1, ?send=fail and
// ?send=verified show its other states. ?page=rules shows the Rules page
// (490) in the portal, ?page=rules&signed=0 as the public page.
//   npx vite --config vite.affiliate-preview.config.mts
//   http://localhost:5196/?send=fail
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
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/affiliate/preview/supabase-stub.ts') },
      // Also './supabase', from the other files in src/lib.
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/affiliate/preview/supabase-stub.ts') },
    ],
  },
  server: { port: 5196, strictPort: true },
});
