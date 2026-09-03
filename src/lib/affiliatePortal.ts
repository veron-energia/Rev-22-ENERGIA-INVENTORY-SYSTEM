import { supabase } from './supabase';

export const money = (n: any) => `S$${Number(n ?? 0).toFixed(2)}`;
export const dateStr = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

// Maps the raw commission_status enum to affiliate-friendly wording.
export const statusLabel = (s?: string): { label: string; cls: string } => {
  switch (s) {
    case 'paid': return { label: 'Paid', cls: 'badge-success' };
    case 'earned': return { label: 'Unpaid', cls: 'badge-warning' };
    case 'reversed': return { label: 'Reversed', cls: 'badge-muted' };
    case 'cancelled': return { label: 'Blocked', cls: 'badge-danger' };
    default: return { label: s ?? '—', cls: 'badge-muted' };
  }
};

// All portal reads go through SECURITY DEFINER RPCs that derive identity from
// auth.uid(); the browser never supplies an affiliate id.
export async function portalRpc<T = any>(fn: string): Promise<T> {
  const { data, error } = await supabase.rpc(fn);
  if (error) throw new Error(error.message);
  return data as T;
}
