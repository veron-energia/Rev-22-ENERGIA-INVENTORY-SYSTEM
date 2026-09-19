import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { createChangeCollector, invoiceIdsFromChange } from '../lib/invoices/listRefresh';

/**
 * Tells the invoice list when something it shows may have changed.
 *
 * Four sources, all of them only signals — the list answers each by asking
 * the server for its page again, through the same access-checked query it
 * always uses. Nothing here reads row data out of an event, so a signal can
 * never show a viewer more than the query would.
 *
 *  - realtime: Postgres changes on invoices and invoice_payments, delivered
 *    through the user's own session, so row-level security decides which
 *    events reach them. Bursts are collected into one signal.
 *  - other tabs of this browser: a BroadcastChannel message posted by the
 *    tab that made a change (works even when realtime is down).
 *  - coming back: the tab becoming visible again, the browser coming back
 *    online, and the realtime channel re-subscribing after a drop.
 *  - polling: only while realtime is not subscribed AND the tab is visible,
 *    once a minute. A hidden tab makes no requests.
 */
export type LiveSource = 'realtime' | 'tab' | 'reconnect' | 'visible' | 'online' | 'poll';
/** rows: the invoice row each realtime event announced (invoices table only), by id — compared, never shown. */
export type LiveChange = { source: LiveSource; ids: string[]; at: number; rows?: Record<string, any> };
export type LiveState = 'off' | 'connecting' | 'live' | 'unavailable';

const TAB_CHANNEL = 'energia:invoices';
const BURST_MS = 400;
const POLL_MS = 60_000;

export function useInvoiceLiveUpdates(opts: {
  /** The signed-in user; the subscription is torn down when it changes or goes. */
  userId: string | null | undefined;
  onChange: (change: LiveChange) => void;
}) {
  const { userId } = opts;
  const onChangeRef = useRef(opts.onChange);
  onChangeRef.current = opts.onChange;
  const [state, setState] = useState<LiveState>('off');
  const stateRef = useRef<LiveState>('off');
  const tabRef = useRef<BroadcastChannel | null>(null);
  const tabIdRef = useRef<string>('');

  const emit = useCallback((source: LiveSource, ids: string[], at: number, rows?: Record<string, any>) => {
    onChangeRef.current({ source, ids, at, rows });
  }, []);

  /** Tell the other tabs of this browser that these invoices changed here. */
  const announce = useCallback((ids: string[]) => {
    try { tabRef.current?.postMessage({ type: 'invoices-changed', ids, from: tabIdRef.current }); } catch { /* no channel */ }
  }, []);

  useEffect(() => {
    if (!userId) { stateRef.current = 'off'; setState('off'); return; }
    let disposed = false;
    const setLive = (s: LiveState) => { if (!disposed) { stateRef.current = s; setState(s); } };

    // --- realtime ------------------------------------------------------
    const collector = createChangeCollector(BURST_MS, b => emit('realtime', b.ids, b.firstAt, b.rows));
    let subscribedBefore = false;
    let channel: any = null;
    const client: any = supabase;
    if (typeof client.channel === 'function') {
      setLive('connecting');
      channel = client.channel(`invoices-live-${userId}`);
      for (const table of ['invoices', 'invoice_payments']) {
        channel.on('postgres_changes', { event: '*', schema: 'public', table }, (payload: any) => {
          const ids = invoiceIdsFromChange(table, payload);
          const row = table === 'invoices' && payload?.new && typeof payload.new.id === 'string' ? { [payload.new.id]: payload.new } : {};
          collector.push(ids, row);
        });
      }
      channel.subscribe((status: string) => {
        if (disposed) return;
        if (status === 'SUBSCRIBED') {
          // A re-subscription after a drop may have missed events; ask once.
          if (subscribedBefore) emit('reconnect', [], Date.now());
          subscribedBefore = true;
          setLive('live');
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          setLive('unavailable');
        }
      });
    } else {
      setLive('unavailable');
    }

    // --- other tabs -----------------------------------------------------
    tabIdRef.current = (globalThis.crypto?.randomUUID?.() ?? String(Math.random()));
    let tab: BroadcastChannel | null = null;
    if (typeof BroadcastChannel !== 'undefined') {
      tab = new BroadcastChannel(TAB_CHANNEL);
      tab.onmessage = (ev: MessageEvent) => {
        const m = ev.data;
        if (!m || m.type !== 'invoices-changed' || m.from === tabIdRef.current) return;
        emit('tab', Array.isArray(m.ids) ? m.ids.filter((x: unknown) => typeof x === 'string') : [], Date.now());
      };
      tabRef.current = tab;
    }

    // --- coming back ----------------------------------------------------
    const onVisibility = () => { if (document.visibilityState === 'visible') emit('visible', [], Date.now()); };
    const onOnline = () => emit('online', [], Date.now());
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('online', onOnline);

    // --- bounded polling, only when realtime is not there and the tab is seen
    const poll = setInterval(() => {
      if (document.visibilityState !== 'visible') return;
      if (stateRef.current === 'live') return;
      emit('poll', [], Date.now());
    }, POLL_MS);

    return () => {
      disposed = true;
      collector.cancel();
      clearInterval(poll);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('online', onOnline);
      if (tab) { try { tab.close(); } catch { /* already closed */ } }
      if (tabRef.current === tab) tabRef.current = null;
      if (channel) { try { client.removeChannel(channel); } catch { /* already gone */ } }
      stateRef.current = 'off'; setState('off');
    };
  }, [userId, emit]);

  return { state, announce };
}
