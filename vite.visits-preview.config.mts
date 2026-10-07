// Renders the screens of 398 against an in-memory stub, so they can be looked
// at without a database or a login: the Customers page (Visited, the first
// visit range and column, Downline), the Affiliates page's Referral promotion
// tab (provisional or final, Mark reward given, Undo) and the affiliate
// portal's My Network with its progress card. Invented data only.
//   npx vite --config vite.visits-preview.config.mts
//   http://localhost:5190/?view=customers&role=owner
//   http://localhost:5190/?view=promotion&role=owner&status=final
//   http://localhost:5190/?view=network
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/referrals/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/referrals/preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/referrals/preview/supabase-stub.ts') },
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/referrals/preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/referrals/preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5190, strictPort: true },
});
