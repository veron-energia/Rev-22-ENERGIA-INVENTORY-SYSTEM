// Renders the real referral page (/r/:code) against a stubbed database, so a
// registration can be pressed end to end without touching production. The
// stub answers as 392 does and holds the page on its way to cal.com, showing
// the booking address it would have opened (392).
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
