import { supabase } from '../supabase';
import type { Invoice } from '../../types';
import { byInvoiceNoDesc } from './business';

/** Page through the accessible invoices so historical/pending dates are not
 * hidden by PostgREST's per-request row limit. RLS remains authoritative.
 *
 * Paging is ordered by invoice_no, which is NOT NULL and UNIQUE: a total order
 * with no ties, so no row can be repeated or skipped across .range() calls.
 * The previous order — business_date, id — sorted equal-dated invoices by a
 * random uuid, which is why a list of one day's invoices came out 0168, 0169,
 * 0172, 0171.
 *
 * The rows are then sorted again here rather than trusted from the server,
 * because PostgREST can only order by the column as text and that misplaces a
 * sequence once it outgrows its padding. See compareInvoiceNo. Every page has
 * been fetched by this point, so sorting the whole set is complete.
 */
export async function loadInvoiceList() {
  const rows: Invoice[] = [];
  const size = 500;
  for (let start = 0; ; start += size) {
    const result = await supabase.from('invoices').select('*').is('deleted_at', null)
      .order('invoice_no', { ascending: false })
      .range(start, start + size - 1);
    if (result.error) return { data: null, error: result.error };
    rows.push(...(result.data as Invoice[]));
    if (result.data.length < size) return { data: rows.sort(byInvoiceNoDesc), error: null };
  }
}
