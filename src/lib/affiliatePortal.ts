import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase';

export const money = (n: any) => `S$${Number(n ?? 0).toFixed(2)}`;
export const dateStr = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

// The wording and figures the portal shows (410: blocked, partly paid, and a
// deduction rather than a negative Unpaid).
export { statusLabel, earningsFigures, settledFigure, DEDUCTION_NOTE } from './affiliatePortalFigures';

// All portal reads go through SECURITY DEFINER RPCs that derive identity from
// auth.uid(); the browser never supplies an affiliate id.
export async function portalRpc<T = any>(fn: string): Promise<T> {
  const { data, error } = await supabase.rpc(fn);
  if (error) throw new Error(error.message);
  return data as T;
}

/** One portal read for a page: its data (null until it arrives), its error,
 *  and retry(), which reads it again. An answer to an earlier read is
 *  dropped (AFFILIATES-7). */
export function usePortalRpc<T = any>(fn: string): { data: T | null; err: string | null; retry: () => void } {
  const [data, setData] = useState<T | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const ticket = useRef(0);
  useEffect(() => {
    const mine = ++ticket.current;
    setErr(null);
    portalRpc<T>(fn)
      .then(d => { if (mine === ticket.current) setData(d); })
      .catch((e: unknown) => { if (mine === ticket.current) setErr(e instanceof Error ? e.message : String(e)); });
  }, [fn, tick]);
  const retry = useCallback(() => setTick(t => t + 1), []);
  return { data, err, retry };
}
