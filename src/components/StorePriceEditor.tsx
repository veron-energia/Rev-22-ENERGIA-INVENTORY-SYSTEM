import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Store } from '../types';
import { Modal } from './ui';
import { RefreshCw } from 'lucide-react';
import { listText, priceProblem, unsavedStoreNames } from '../lib/catalogue/pageRules.mjs';

const money = (n: number | null) => n == null ? '—' : `S$${Number(n).toFixed(2)}`;

type Draft = { m: string; nm: string; avail: boolean };
const BLANK: Draft = { m: '', nm: '', avail: true };

/** Per-store selling price editor for vouchers, promotions and therapy packages.
 *  Owner/Manager only (RPCs enforce it server-side). Each row is saved on its
 *  own; a price below zero, or one that is not a number, is refused before it
 *  is sent, and closing with prices typed but not saved asks first. Saving
 *  one row keeps what is typed in the others. When the saved prices cannot be
 *  read, no row is shown until Retry reads them: a row filled with defaults
 *  could switch a store back on. */
const StorePriceEditor: React.FC<{
  kind: 'voucher' | 'promotion' | 'therapy';
  targetId: string;
  targetName: string;
  stores: Store[];
  onClose: () => void;
}> = ({ kind, targetId, targetName, stores, onClose }) => {
  const table = kind === 'voucher' ? 'voucher_store_prices' : kind === 'promotion' ? 'promotion_store_prices' : 'unlimited_therapy_store_prices';
  const idCol = kind === 'voucher' ? 'voucher_id' : kind === 'promotion' ? 'promotion_id' : 'package_id';
  const rpc = kind === 'voucher' ? 'set_voucher_prices' : kind === 'promotion' ? 'set_promotion_prices' : 'set_unlimited_therapy_price';

  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyStore, setBusyStore] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loadFailed, setLoadFailed] = useState(false);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  // What is typed now, for after a save's answer (rows typed meanwhile count).
  const draftsNow = useRef(drafts);
  draftsNow.current = drafts;

  // keep: rows still being typed, by store, which a reload must not overwrite.
  const load = async (keep: Record<string, Draft> = {}) => {
    setLoading(true); setLoadFailed(false);
    const { data, error } = await supabase.from(table).select('*').eq(idCol, targetId).is('deleted_at', null);
    if (error) {
      setErr(`The saved prices could not be loaded: ${error.message}`);
      setLoadFailed(true); setLoading(false); return;
    }
    const rs = (data as any[]) ?? [];
    setRows(rs);
    const d: Record<string, Draft> = {};
    stores.forEach(s => {
      const r = rs.find(x => x.store_id === s.id);
      d[s.id] = keep[s.id] ?? {
        // Phase 19: one selling price. The former Member Price is the price.
        m: r?.selling_price != null ? String(r.selling_price) : '',
        nm: r?.selling_price != null ? String(r.selling_price) : '',
        avail: r ? r.available_at_store !== false : true,
      };
    });
    setDrafts(d);
    setLoading(false);
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [targetId]);

  // The rows typed but not saved, except one store's: what a reload keeps.
  const typedRows = (except?: string) => {
    const typed = draftsNow.current;
    const keep: Record<string, Draft> = {};
    stores.forEach(s => {
      if (s.id !== except && typed[s.id] && unsavedStoreNames([s], typed, rows).length > 0) keep[s.id] = typed[s.id];
    });
    return keep;
  };

  const save = async (storeId: string) => {
    const d = drafts[storeId];
    if (!d || loadFailed) return; // nothing read yet: nothing to save
    const storeName = stores.find(s => s.id === storeId)?.name ?? 'this store';
    // Checked here first, so the reason is plain; the server refuses it too.
    const problem = priceProblem(d.m);
    if (problem) { setErr(`The price at ${storeName} ${problem}. Enter 0 or more, or leave it blank.`); return; }
    setBusyStore(storeId); setErr(null);
    const price = d.m.trim() === '' ? null : Number(d.m);
    const args: any = kind === 'therapy'
      ? { p_package_id: targetId, p_store_id: storeId, p_member: price, p_non_member: price, p_available: d.avail }
      : { [`p_${idCol}`]: targetId, p_store_id: storeId, p_member: price, p_non_member: price, p_available: d.avail };
    const { error } = await supabase.rpc(rpc, args);
    setBusyStore(null);
    if (error) { setErr(`${storeName}: ${error.message}`); return; }
    // The other stores' rows that are typed but not saved stay as typed.
    load(typedRows(storeId));
  };

  // Done, the cross and Escape all come here: prices typed but not saved are
  // not thrown away without asking.
  const close = () => {
    const unsaved = loading ? [] : unsavedStoreNames(stores, drafts, rows);
    if (unsaved.length > 0
        && !window.confirm(`You have unsaved prices for ${listText(unsaved)}. Discard them?`)) return;
    onClose();
  };

  return (
    <Modal title={`Store Prices — ${targetName}`} maxWidth={520} onClose={close}
      footer={<button className="btn btn-secondary" onClick={close}>Done</button>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
          Set the selling price for this {kind} at each store, then press Save on that row. A blank price
          <strong> blocks</strong> the sale at that store. A price cannot be below zero.
        </div>
        {loading ? <div style={{ textAlign: 'center', padding: 12 }}><RefreshCw size={16} className="spin" style={{ opacity: 0.4 }} /></div>
          : loadFailed ? (
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <span style={{ fontSize: 12.5 }}>No price can be changed until the saved prices are read.</span>
              <button className="btn btn-secondary btn-sm" onClick={() => { setErr(null); void load(typedRows()); }}>Retry</button>
            </div>
          )
          : stores.map(s => {
            const d = drafts[s.id] ?? BLANK;
            const saved = rows.find(r => r.store_id === s.id);
            const problem = priceProblem(d.m);
            return (
              <div key={s.id} style={{ display: 'flex', gap: 8, alignItems: 'flex-end', flexWrap: 'wrap', borderBottom: '1px solid var(--border)', paddingBottom: 8 }}>
                <div style={{ flex: 1, minWidth: 120 }}>
                  <div style={{ fontSize: 12.5, fontWeight: 600 }}>{s.name}</div>
                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>
                    Saved: {money(saved?.selling_price ?? null)}{saved && saved.available_at_store === false ? ' · unavailable' : ''}
                  </div>
                </div>
                <div className="form-group" style={{ marginBottom: 0, width: 120 }}>
                  <label style={{ fontSize: 10.5 }} htmlFor={`store-price-${s.id}`}>Price</label>
                  <input id={`store-price-${s.id}`} type="number" min={0} step="0.01" value={d.m} placeholder="—"
                    aria-invalid={problem ? true : undefined}
                    onChange={e => setDrafts(x => ({ ...x, [s.id]: { ...BLANK, ...x[s.id], m: e.target.value, nm: e.target.value } }))} />
                  {problem && <div style={{ fontSize: 10.5, color: 'var(--danger)', marginTop: 2 }}>Price {problem}</div>}
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 12, cursor: 'pointer', paddingBottom: 8 }}>
                  <input type="checkbox" checked={d.avail} style={{ width: 'auto' }}
                    onChange={e => setDrafts(x => ({ ...x, [s.id]: { ...BLANK, ...x[s.id], avail: e.target.checked } }))} /> Available
                </label>
                <button className="btn btn-primary btn-sm" style={{ marginBottom: 6 }} disabled={busyStore === s.id || !!problem}
                  onClick={() => save(s.id)}>
                  {busyStore === s.id ? 'Saving…' : 'Save'}
                </button>
              </div>
            );
          })}
      </div>
    </Modal>
  );
};

export default StorePriceEditor;
