// Renders the Reports page against invented data, so its tabs, labels, error
// states and exports can be checked without a database or a login.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/reports/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/reports/preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/reports/preview/supabase-stub.ts') },
      // The page reads the signed-in role through useAuth; the preview is an Owner.
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/reports/preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/reports/preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5193, strictPort: true },
});
