import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import {
  StockMovement, Product, Warehouse, Store, Profile,
  MOVEMENT_LABELS, StockMovementType,
} from '../types';
import { RefreshCw, History, ArrowRight } from 'lucide-react';

const MOVEMENT_TINTS: Partial<Record<StockMovementType, string>> = {
  warehouse_stock_in: 'badge-success',
  warehouse_to_store: 'badge-primary',
  warehouse_to_warehouse: 'badge-primary',
  store_to_store: 'badge-primary',
  store_sale: 'badge-accent',
  invoice_cancel_return: 'badge-muted',
  invoice_refund_return: 'badge-muted',
  inventory_adjustment: 'badge-accent',
};

const StockMovementsPage: React.FC = () => {
  const [movements, setMovements] = useState<StockMovement[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [typeFilter, setTypeFilter] = useState<'all' | StockMovementType>('all');

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [mv, prod, wh, st, prof] = await Promise.all([
      supabase.from('stock_movements').select('*').order('created_at', { ascending: false }).limit(500),
      supabase.from('products').select('id,name,sku'),
      supabase.from('warehouses').select('id,name'),
      supabase.from('stores').select('id,name'),
      supabase.from('profiles').select('id,full_name'),
    ]);
    if (mv.error) { console.error('stock_movements read failed:', mv.error); setLoadErr(mv.error.message); }
    else setLoadErr(null);
    setMovements((mv.data as StockMovement[]) ?? []);
    setProducts((prod.data as Product[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { loadAll(); }, [loadAll]);

  const pName = (id: string) => products.find(p => p.id === id)?.name ?? 'Unknown';
  const pSku = (id: string) => products.find(p => p.id === id)?.sku ?? '';
  const uName = (id: string | null) => id ? (profiles.find(p => p.id === id)?.full_name ?? '—') : '—';
  const locName = (whId: string | null, stId: string | null) => {
    if (whId) return `🏭 ${warehouses.find(w => w.id === whId)?.name ?? '—'}`;
    if (stId) return `🏪 ${stores.find(s => s.id === stId)?.name ?? '—'}`;
    return null;
  };

  const filtered = movements.filter(m => typeFilter === 'all' || m.movement_type === typeFilter);

  const typeOptions: (StockMovementType | 'all')[] = ['all', 'warehouse_stock_in', 'warehouse_to_store', 'warehouse_to_warehouse', 'store_to_store', 'store_sale', 'inventory_adjustment'];

  return (
    <div>
      <div className="page-header">
        <div><h2>Stock Movement History</h2><p>Every stock change, newest first. Permanent and read-only.</p></div>
        <button className="btn btn-secondary" onClick={loadAll}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
        {typeOptions.map(t => (
          <button key={t} className={`btn btn-sm ${typeFilter === t ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTypeFilter(t)}>
            {t === 'all' ? 'All' : MOVEMENT_LABELS[t]}
          </button>
        ))}
      </div>

      {loadErr && <div className="alert alert-danger"><span>⚠</span><div>Couldn't read stock history: {loadErr}. If this mentions a policy, run <code>07_phase2_fix_rls.sql</code>.</div></div>}

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><History size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No movements yet</p></div>
          : (
            <table>
              <thead><tr><th>Date</th><th>Type</th><th>Product</th><th>Movement</th><th style={{ textAlign: 'right' }}>Qty</th><th>By</th><th>Notes</th></tr></thead>
              <tbody>
                {filtered.map(m => {
                  const from = locName(m.from_warehouse_id, m.from_store_id);
                  const to = locName(m.to_warehouse_id, m.to_store_id);
                  return (
                    <tr key={m.id}>
                      <td style={{ whiteSpace: 'nowrap', fontSize: 12.5 }}>{new Date(m.created_at).toLocaleDateString()}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{new Date(m.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div></td>
                      <td><span className={`badge ${MOVEMENT_TINTS[m.movement_type] ?? 'badge-muted'}`}>{MOVEMENT_LABELS[m.movement_type]}</span></td>
                      <td><strong>{pName(m.product_id)}</strong><div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{pSku(m.product_id)}</div></td>
                      <td style={{ fontSize: 12.5 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                          {from && <span>{from}</span>}
                          {from && to && <ArrowRight size={12} style={{ color: 'var(--text-muted)' }} />}
                          {to && <span>{to}</span>}
                          {!from && !to && '—'}
                        </div>
                      </td>
                      <td style={{ textAlign: 'right', fontWeight: 700 }}>{m.quantity}</td>
                      <td style={{ fontSize: 12.5 }}>{uName(m.created_by)}</td>
                      <td style={{ fontSize: 12, color: 'var(--text-muted)', maxWidth: 240 }}>{m.notes || '—'}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
};

export default StockMovementsPage;
