// Renders the real referral page (/r/:code) against a stubbed database, so a
// registration can be pressed end to end without touching production. The
// stub answers as 392 does and holds the page on its way to cal.com, showing
// the booking address it would have opened (392).
// 484 (push #2): the notice above each card's button. ?name=none: no inviter
// name (the notice says "the person who invited you"); ?notice=missing: a
// database without 484 (PGRST202), so the page signs up the old way.
//   npx vite --config vite.referral-preview.config.mts
//   http://localhost:5188/?name=none&notice=missing
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/affiliate-signup/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/affiliate-signup/preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+lib\/supabase$/, replacement: abs('./scripts/affiliate-signup/preview/supabase-stub.ts') },
    ],
  },
  server: { port: 5188, strictPort: true },
});
