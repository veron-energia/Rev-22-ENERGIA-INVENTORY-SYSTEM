// Renders the Therapy Services page against a stub, so its real markup can be
// checked at real phone widths without a database or a login.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/therapy-services/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/therapy-services/preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/therapy-services/preview/supabase-stub.ts') },
      // The page reads the signed-in role through useAuth; the preview is a Manager.
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/therapy-services/preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/therapy-services/preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5197, strictPort: true },
});
