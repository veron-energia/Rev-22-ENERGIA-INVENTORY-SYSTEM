import { supabase } from './supabase';

export const money = (n: any) => `S$${Number(n ?? 0).toFixed(2)}`;
export const dateStr = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

// The wording and figures the portal shows (410: blocked, partly paid, and a
// deduction rather than a negative Unpaid).
export { statusLabel, earningsFigures, DEDUCTION_NOTE } from './affiliatePortalFigures';

// All portal reads go through SECURITY DEFINER RPCs that derive identity from
// auth.uid(); the browser never supplies an affiliate id.
export async function portalRpc<T = any>(fn: string): Promise<T> {
  const { data, error } = await supabase.rpc(fn);
  if (error) throw new Error(error.message);
  return data as T;
}
