export const CHANGED_WHILE_EXPORTING: string;
/** Every customer a search matches, every page read; refuses (throws) on a
 *  failed page, a customer met twice, or a list that changed while read. */
export function fetchAllCustomerRows<T extends { id: string; total_count?: number | string | null }>(
  fetchPage: (limit: number, offset: number) => PromiseLike<{ data: T[] | null; error: { message?: string } | null }>,
  pageSize?: number,
): Promise<T[]>;
