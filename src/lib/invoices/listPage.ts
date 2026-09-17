import { supabase } from '../supabase';
import type { Invoice } from '../../types';
import type { InvoiceSortField, SortDirection } from './business';

export type InvoiceListQuery = {
  search: string;
  status: string;          // 'all' or an invoice_status
  dateMode: 'all' | 'confirmed' | 'pending';
  dateFrom: string;
  dateTo: string;
  storeId: string;
  sortField: InvoiceSortField;
  sortDir: SortDirection;
  pageSize: number;
  page: number;            // 1-based
};

export type InvoiceListResult = {
  rows: Invoice[];
  total: number;
  pages: number;
  summary: { matching: number; total_amount: number; outstanding: number; paid: number };
};

/**
 * One page of the invoice list.
 *
 * The filter, the search, the sort, the count and the summary all happen in the
 * database, over every invoice the user may see — not over whatever happened to
 * be downloaded. The browser used to fetch the whole table plus every payment
 * row and every customer to do the same job, which is what made opening the
 * list slow and got slower as the table grew.
 */
export async function fetchInvoicePage(q: InvoiceListQuery): Promise<InvoiceListResult> {
  const { data, error } = await supabase.rpc('invoice_list_page', {
    p_search: q.search.trim() || null,
    p_status: q.status === 'all' ? null : q.status,
    p_date_mode: q.dateMode,
    p_date_from: q.dateFrom || null,
    p_date_to: q.dateTo || null,
    p_store_id: q.storeId || null,
    p_sort_field: q.sortField,
    p_sort_dir: q.sortDir,
    p_limit: q.pageSize,
    p_offset: Math.max(0, (q.page - 1) * q.pageSize),
  });
  if (error) throw new Error(error.message);
  const d = data as any;
  return {
    rows: (d?.rows ?? []) as Invoice[],
    total: Number(d?.total ?? 0),
    pages: Number(d?.pages ?? 0),
    summary: {
      matching: Number(d?.summary?.matching ?? 0),
      total_amount: Number(d?.summary?.total_amount ?? 0),
      outstanding: Number(d?.summary?.outstanding ?? 0),
      paid: Number(d?.summary?.paid ?? 0),
    },
  };
}

/**
 * Every matching invoice, for an export, in controlled batches.
 *
 * Deliberately not one big request: the row limit would truncate it silently,
 * which is the failure XERO_ROW_LIMIT_FIX.md records. onProgress reports rows
 * fetched so a large export can show it is still working.
 */
export async function fetchAllMatchingInvoices(
  q: Omit<InvoiceListQuery, 'page' | 'pageSize'>,
  onProgress?: (fetched: number, total: number) => void,
): Promise<Invoice[]> {
  const batch = 500;
  const rows: Invoice[] = [];
  let page = 1;
  let total = Infinity;
  for (;;) {
    const res = await fetchInvoicePage({ ...q, pageSize: batch, page });
    rows.push(...res.rows);
    total = res.total;
    onProgress?.(rows.length, total);
    if (rows.length >= total || res.rows.length === 0) return rows;
    page += 1;
  }
}
