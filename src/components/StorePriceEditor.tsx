import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Store } from '../types';
import { Modal } from './ui';
import { RefreshCw } from 'lucide-react';

const money = (n: number | null) => n == null ? '—' : `S$${Number(n).toFixed(2)}`;

/** Per-store Member / Non-Member price editor for vouchers and promotions.
 *  Owner/Manager only (RPCs enforce it server-side). */
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
  const [drafts, setDrafts] = useState<Record<string, { m: string; nm: string; avail: boolean }>>({});

  const load = async () => {
    setLoading(true);
    const { data } = await supabase.from(table).select('*').eq(idCol, targetId).is('deleted_at', null);
    const rs = (data as any[]) ?? [];
    setRows(rs);
    const d: Record<string, { m: string; nm: string; avail: boolean }> = {};
    stores.forEach(s => {
      const r = rs.find(x => x.store_id === s.id);
      d[s.id] = {
        m: r?.member_price != null ? String(r.member_price) : '',
        nm: r?.non_member_price != null ? String(r.non_member_price) : '',
        avail: r ? r.available_at_store !== false : true,
      };
    });
    setDrafts(d);
    setLoading(false);
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [targetId]);

  const save = async (storeId: string) => {
    const d = drafts[storeId];
    setBusyStore(storeId); setErr(null);
    const args: any = kind === 'therapy'
      ? { p_package_id: targetId, p_store_id: storeId, p_member: d.m === '' ? null : Number(d.m), p_non_member: d.nm === '' ? null : Number(d.nm), p_available: d.avail }
      : { [`p_${idCol}`]: targetId, p_store_id: storeId, p_member: d.m === '' ? null : Number(d.m), p_non_member: d.nm === '' ? null : Number(d.nm), p_available: d.avail };
    const { error } = await supabase.rpc(rpc, args);
    setBusyStore(null);
    if (error) { setErr(error.message); return; }
    load();
  };

  return (
    <Modal title={`Member / Non-Member Prices — ${targetName}`} maxWidth={560} onClose={onClose}
      footer={<button className="btn btn-secondary" onClick={onClose}>Done</button>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
          Invoices price this {kind} per store: members pay the Member price, non-members the Non-Member price.
          A blank price <strong>blocks</strong> that sale type at that store.
        </div>
        {loading ? <div style={{ textAlign: 'center', padding: 12 }}><RefreshCw size={16} className="spin" style={{ opacity: 0.4 }} /></div>
          : stores.map(s => {
            const d = drafts[s.id] ?? { m: '', nm: '', avail: true };
            const saved = rows.find(r => r.store_id === s.id);
            return (
              <div key={s.id} style={{ display: 'flex', gap: 8, alignItems: 'flex-end', flexWrap: 'wrap', borderBottom: '1px solid var(--border)', paddingBottom: 8 }}>
                <div style={{ flex: 1, minWidth: 120 }}>
                  <div style={{ fontSize: 12.5, fontWeight: 600 }}>{s.name}</div>
                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>
                    Saved: M {money(saved?.member_price ?? null)} · NM {money(saved?.non_member_price ?? null)}{saved && saved.available_at_store === false ? ' · unavailable' : ''}
                  </div>
                </div>
                <div className="form-group" style={{ marginBottom: 0, width: 96 }}>
                  <label style={{ fontSize: 10.5 }}>Member</label>
                  <input type="number" min={0} step="0.01" value={d.m} placeholder="—"
                    onChange={e => setDrafts(x => ({ ...x, [s.id]: { ...x[s.id], m: e.target.value } }))} />
                </div>
                <div className="form-group" style={{ marginBottom: 0, width: 96 }}>
                  <label style={{ fontSize: 10.5 }}>Non-Member</label>
                  <input type="number" min={0} step="0.01" value={d.nm} placeholder="—"
                    onChange={e => setDrafts(x => ({ ...x, [s.id]: { ...x[s.id], nm: e.target.value } }))} />
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 12, cursor: 'pointer', paddingBottom: 8 }}>
                  <input type="checkbox" checked={d.avail} style={{ width: 'auto' }}
                    onChange={e => setDrafts(x => ({ ...x, [s.id]: { ...x[s.id], avail: e.target.checked } }))} /> Available
                </label>
                <button className="btn btn-primary btn-sm" style={{ marginBottom: 6 }} disabled={busyStore === s.id} onClick={() => save(s.id)}>
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
