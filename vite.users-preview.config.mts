// Renders the user-invitation components against a stub, so their real markup
// can be checked at real phone widths without a database or a login.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/users/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/users/preview/supabase-stub.ts') },
      // Both spellings the source uses: '../lib/supabase' from a page, and
      // './supabase' from a sibling in src/lib. Missing the second one loads
      // the real client and the preview dies asking for environment variables.
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/users/preview/supabase-stub.ts') },
    ],
  },
  server: { port: 5198, strictPort: true },
});
