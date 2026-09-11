import { supabase } from '../supabase';
import type { Invoice } from '../../types';

/** Page through the accessible invoices so historical/pending dates are not
 * hidden by PostgREST's per-request row limit. RLS remains authoritative. */
export async function loadInvoiceList() {
  const rows: Invoice[] = [];
  const size = 500;
  for (let start = 0; ; start += size) {
    const result = await supabase.from('invoices').select('*').is('deleted_at', null)
      .order('business_date', { ascending: false, nullsFirst: false }).order('id')
      .range(start, start + size - 1);
    if (result.error) return { data: null, error: result.error };
    rows.push(...(result.data as Invoice[]));
    if (result.data.length < size) return { data: rows, error: null };
  }
}
