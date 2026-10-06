// Renders the Invoices page against an in-memory stub with two unpaid invoices
// (one at a store with its own QR images, one at a store without), so the
// payment QR pop-up can be pressed without a database or a login. The images
// are placeholders that say they are not payment codes.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

const abs = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  root: abs('./scripts/invoices/qr-preview'),
  plugins: [react()],
  resolve: {
    alias: [
      { find: abs('./src/lib/supabase.ts'), replacement: abs('./scripts/invoices/qr-preview/supabase-stub.ts') },
      { find: /^(\.{1,2}\/)+(lib\/)?supabase$/, replacement: abs('./scripts/invoices/qr-preview/supabase-stub.ts') },
      { find: abs('./src/context/AuthContext.tsx'), replacement: abs('./scripts/invoices/qr-preview/auth-stub.tsx') },
      { find: /^(\.{1,2}\/)+context\/AuthContext$/, replacement: abs('./scripts/invoices/qr-preview/auth-stub.tsx') },
    ],
  },
  server: { port: 5187, strictPort: true },
});
