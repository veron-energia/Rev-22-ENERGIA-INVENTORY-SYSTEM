// Renders the therapy components against a stub, so their real markup can be
// checked at real phone widths without a database or a login.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/therapy/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      // Every component reaches supabase through this one module.
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/therapy/preview/supabase-stub.ts') },
      { find: /^.*\/lib\/supabase$/, replacement: abs('./scripts/therapy/preview/supabase-stub.ts') },
    ],
  },
  server: { port: 5199, strictPort: true },
});
