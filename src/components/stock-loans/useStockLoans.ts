import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { LocationType, StockLoan, outByProduct } from '../../lib/stock-loans/stockLoans';

type Loaded = {
  /** The location these loans belong to ("store:<id>"). */
  key: string;
  open: StockLoan[];
  closed: StockLoan[];
  today: string;
  /** stock_loans_at's can_act: may this person lend, take back and Record use here. */
  canAct: boolean | null;
};

/**
 * The "On loan" list of one store or warehouse (stock_loans_at, 401): its
 * open loans, and its last closed ones when asked. `outBy` is each product's
 * "Out on loan" figure for the stock table.
 *
 * Only the answer to the latest request is kept: switching from Store A to
 * Store B while A's answer is on its way never shows A's loans or figures
 * under B. Until B's answer arrives, B shows none (rather than A's).
 *
 * `canAct` is null until the database has answered (and after a failed
 * read); the pages then leave Lend and Record use to the database's own
 * check, as before, and offer Take back only when it is true.
 */
export function useStockLoans(locationType: LocationType, locationId: string, includeClosed: boolean) {
  const key = `${locationType}:${locationId}`;
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const latest = useRef(0);

  const reload = useCallback(async () => {
    const ask = ++latest.current;
    if (!locationId) { setLoaded(null); setError(null); setLoading(false); return; }
    setLoading(true);
    const { data, error: e } = await supabase.rpc('stock_loans_at', {
      p_location_type: locationType, p_location_id: locationId, p_include_closed: includeClosed,
    });
    // A newer request (another location, or the closed toggle) has been made since.
    if (ask !== latest.current) return;
    setLoading(false);
    if (e) { setError(e.message); setLoaded(null); return; }
    setError(null);
    setLoaded({
      key: `${locationType}:${locationId}`,
      open: (data?.open as StockLoan[]) ?? [],
      closed: (data?.closed as StockLoan[]) ?? [],
      today: data?.today ?? '',
      canAct: typeof data?.can_act === 'boolean' ? data.can_act : null,
    });
  }, [locationType, locationId, includeClosed]);

  useEffect(() => { reload(); }, [reload]);
  // An answer arriving after the page has gone is ignored too.
  useEffect(() => () => { latest.current++; }, []);

  const current = loaded && loaded.key === key ? loaded : null;
  const open = useMemo(() => current?.open ?? [], [current]);
  const closed = current?.closed ?? [];
  const outBy = useMemo(() => outByProduct(open), [open]);
  const overdue = open.filter(l => l.overdue).length;
  return {
    open, closed, today: current?.today ?? '', canAct: current?.canAct ?? null,
    loading, error, reload, outBy, overdue,
  };
}
