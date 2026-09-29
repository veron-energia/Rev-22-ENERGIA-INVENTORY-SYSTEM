// Renders the Events page against an in-memory stub, so its list, guest list,
// door screen and editor can be checked at real widths without a database or
// a login. Add ?role=staff|manager|owner to see each person's view, and
// ?fail=<rpc name> to see that call's error state.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/events/preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/events/preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/events/preview/supabase-stub.ts') },
      // The page reads the signed-in role through useAuth; ?role= picks it.
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/events/preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/events/preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5192, strictPort: true },
});
