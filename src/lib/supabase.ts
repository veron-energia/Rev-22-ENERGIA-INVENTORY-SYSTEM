import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

if (!supabaseUrl || !supabaseAnonKey) {
  // Surfaced clearly in the console and the login screen handles the null gracefully.
  console.error(
    'Missing Supabase environment variables. Create .env.local with ' +
    'VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY (see .env.local.example).'
  );
}

export const supabase = createClient(supabaseUrl ?? '', supabaseAnonKey ?? '');
