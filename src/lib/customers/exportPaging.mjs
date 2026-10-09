/**
 * Every customer a search matches, for the Customers page's Excel exports
 * (409).
 *
 * search_customers pages by OFFSET in one fixed order (newest first, then by
 * id, since 409), so consecutive pages are consecutive slices of one list.
 * Before 409 it ordered by created_at alone, and most customers share an
 * import timestamp: every export silently left out 126 customers and listed
 * 126 others twice, while the total looked right.
 *
 * This reads every page and refuses rather than hand back a wrong sheet: a
 * page that fails, a customer met twice, or a list that changed while it was
 * read (a customer added or removed between pages) is an error the export
 * shows, never a short or doubled file.
 *
 * fetchPage(limit, offset) returns { data, error } as supabase.rpc does; each
 * row carries its id and total_count (the number of customers matched).
 */
export const CHANGED_WHILE_EXPORTING =
  'The customer list changed while it was being exported, so the file would not match it. Export again.';

export async function fetchAllCustomerRows(fetchPage, pageSize = 1000) {
  const rows = [];
  const seen = new Set();
  let expected = null;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await fetchPage(pageSize, offset);
    if (error) throw new Error(`The customer list could not be read (${error.message ?? error}). Nothing was exported.`);
    const batch = data ?? [];
    for (const row of batch) {
      const total = row.total_count == null ? null : Number(row.total_count);
      if (expected == null) expected = total;
      else if (total != null && total !== expected) throw new Error(CHANGED_WHILE_EXPORTING);
      if (seen.has(row.id)) throw new Error(CHANGED_WHILE_EXPORTING);
      seen.add(row.id);
      rows.push(row);
    }
    if (batch.length < pageSize) break;
  }
  if (expected != null && rows.length !== expected) throw new Error(CHANGED_WHILE_EXPORTING);
  return rows;
}
