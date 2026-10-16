// Renders the Health Surveys page against an in-memory stub, so 433's
// "To match" tab (QR forms held for staff) can be looked at without a
// database or a login. Invented data only.
//   npx vite --config vite.survey-preview.config.mts
//   http://localhost:5212/?role=staff            (any staff: attach, new customer)
//   http://localhost:5212/?role=owner            (also Close without attaching)
//   http://localhost:5212/?role=owner&holds=none (nothing waiting)
//   http://localhost:5212/?role=owner&holds=old  (server without 433: no tab)
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/survey/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/survey/preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/survey/preview/supabase-stub.ts') },
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/survey/preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/survey/preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5212, strictPort: true },
});
