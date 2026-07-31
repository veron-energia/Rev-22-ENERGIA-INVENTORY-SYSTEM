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

/**
 * Fetch customers by id, in chunks.
 *
 * Pages that load the whole customer table only receive Supabase's first 1000
 * rows, so any record belonging to a customer outside that set displays with no
 * name. Rather than pulling a table that may hold a million rows into the
 * browser, look up exactly the ids being displayed.
 */
export async function fetchCustomersByIds(ids: (string | null | undefined)[]): Promise<any[]> {
  const wanted = Array.from(new Set(ids.filter(Boolean) as string[]));
  if (wanted.length === 0) return [];
  const out: any[] = [];
  for (let i = 0; i < wanted.length; i += 200) {
    const { data } = await supabase.from('customers')
      .select('id, full_name, phone, email, referred_by')
      .in('id', wanted.slice(i, i + 200));
    out.push(...((data as any[]) ?? []));
  }
  return out;
}

/** Merge freshly-fetched customers into an existing list without duplicates. */
export function mergeCustomers<T extends { id: string }>(existing: T[], extra: any[]): T[] {
  if (extra.length === 0) return existing;
  const seen = new Set(existing.map(c => c.id));
  const add = extra.filter(c => !seen.has(c.id));
  return add.length === 0 ? existing : [...existing, ...add] as T[];
}
