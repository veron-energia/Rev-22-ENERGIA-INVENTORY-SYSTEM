import { supabase } from './supabase';

/**
 * Read every row a query matches, not the first thousand.
 *
 * PostgREST is deployed with `PGRST_DB_MAX_ROWS=1000`. A `.select()` with no
 * `.range()` therefore stops at a thousand rows and reports no error — the
 * screen simply shows a plausible, wrong answer, and keeps doing so more
 * severely as the table grows. XERO_ROW_LIMIT_FIX.md records what that cost
 * the last time: invoices exported to Xero with lines missing.
 *
 * `build` must return a fresh query each call, because a PostgREST builder
 * cannot be re-ranged once used.
 *
 * A stable order is required for paging to be correct: without one the database
 * may return the same row on two pages and omit another entirely. `id` is the
 * default because every table here has one.
 */
export async function fetchAllRows<T = any>(
  build: () => any,
  orderBy: string[] = ['id'],
): Promise<T[]> {
  const rows: T[] = [];
  for (let offset = 0; ; offset += 1000) {
    let query = build();
    for (const column of orderBy) query = query.order(column, { ascending: true });
    const { data, error } = await query.range(offset, offset + 999);
    if (error) throw new Error(error.message);
    rows.push(...((data ?? []) as T[]));
    if ((data ?? []).length < 1000) return rows;
  }
}

/**
 * The same, for a plain table read.
 *
 *   fetchAllFrom('invoice_payments', 'invoice_id, payment_method_id')
 */
export function fetchAllFrom<T = any>(
  table: string,
  columns = '*',
  refine: (q: any) => any = q => q,
  orderBy: string[] = ['id'],
): Promise<T[]> {
  return fetchAllRows<T>(() => refine(supabase.from(table).select(columns)), orderBy);
}
