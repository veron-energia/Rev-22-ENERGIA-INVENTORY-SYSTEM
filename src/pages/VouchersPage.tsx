import React, { useEffect, useState, useCallback } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Voucher, VoucherKind, VoucherStoreStock, Store, VOUCHER_KIND_LABELS, VOUCHER_CATEGORY_LABELS, BIRTHDAY_RULE_LABELS,
  VoucherDiscountCategory, BirthdayRule, isOwnerOrManager } from '../types';
import StorePriceEditor from '../components/StorePriceEditor';
import { Modal, NoAccess } from '../components/ui';
import { VoucherEditModal, type VoucherRow as VoucherRowT } from '../components/VoucherEditModal';
import { Plus, Pencil, Trash2, Search, Ticket, RefreshCw, Boxes } from 'lucide-react';
import { dayNumbers, dayText, isPastValidUntil, sgToday, voucherDependents, type VoucherDeleteAnswer } from '../lib/catalogue/pageRules.mjs';

const money = (n: number) => `S$${n.toFixed(2)}`;

type VoucherRow = VoucherRowT;

/** "Birthday · in the birth month", for a discount voucher; null for a normal one. */
const categoryText = (v: Voucher): string | null => {
  if (v.voucher_kind === 'normal') return null;
  const c = v.discount_category ?? 'voucher';
  return c === 'birthday' && v.birthday_rule
    ? `${VOUCHER_CATEGORY_LABELS[c]} · ${BIRTHDAY_RULE_LABELS[v.birthday_rule].toLowerCase()}`
    : VOUCHER_CATEGORY_LABELS[c];
};

const VouchersPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isOwnerOrManager(profile?.role);
  const [rows, setRows] = useState<VoucherRow[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [mnmFor, setMnmFor] = useState<{ id: string; name: string } | null>(null);
  const [stock, setStock] = useState<VoucherStoreStock[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [modal, setModal] = useState<{ voucher: VoucherRow | null } | null>(null);
  const [pageErr, setPageErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  // Delete, when something still depends on the voucher: what it is, and why.
  const [delFor, setDelFor] = useState<{ voucher: VoucherRow; answer: VoucherDeleteAnswer } | null>(null);
  const [delReason, setDelReason] = useState('');
  const [delBusy, setDelBusy] = useState(false);
  const [delErr, setDelErr] = useState<string | null>(null);

  const [stockFor, setStockFor] = useState<Voucher | null>(null);
  const [stockStore, setStockStore] = useState('');
  const [stockQty, setStockQty] = useState(0);
  const [stockBusy, setStockBusy] = useState(false);
  // 514: one request id per Add stock window, so a second click, or the same
  // request sent again after its answer was lost, adds the stock once.
  const [stockRequestId, setStockRequestId] = useState(() => crypto.randomUUID());

  const load = useCallback(async () => {
    setLoading(true);
    const [v, s, vs, cls] = await Promise.all([
      supabase.from('vouchers').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('voucher_store_stock').select('*'),
      // 548 (the Owner, 27 Nov 2026): the class vouchers are on the Class page, not here. Until 548 is
      // in there is no class table, the read finds nothing, and every voucher is listed as before.
      supabase.from('class_vouchers').select('voucher_id'),
    ]);
    const classIds = new Set(((cls?.data as { voucher_id: string }[] | null) ?? []).map(r => r.voucher_id));
    setRows(((v.data as VoucherRow[]) ?? []).filter(r => !classIds.has(r.id)));
    setStores((s.data as Store[]) ?? []);
    setStock((vs.data as VoucherStoreStock[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => setModal({ voucher: null });
  const openEdit = (v: VoucherRow) => setModal({ voucher: v });

  // Delete marks the voucher deleted and switches it off (soft_delete_voucher,
  // 423). When customers still hold it, a store has it in stock, or something
  // live offers it, the server says so first and nothing changes until the
  // second step, which needs a reason.
  const handleDelete = async (v: VoucherRow) => {
    if (!window.confirm(`Delete voucher "${v.name}"?`)) return;
    setPageErr(null); setNotice(null);
    const { data, error } = await supabase.rpc('soft_delete_voucher', { p_voucher_id: v.id, p_reason: null, p_confirmed: false });
    if (error) { setPageErr(`"${v.name}" was not deleted: ${error.message}`); return; }
    const answer = (data ?? {}) as VoucherDeleteAnswer;
    if (answer.needs_confirmation) {
      setDelFor({ voucher: v, answer }); setDelReason(''); setDelErr(null);
      return;
    }
    setNotice(`"${v.name}" deleted.`);
    load();
  };

  const confirmDelete = async () => {
    if (!delFor) return;
    if (!delReason.trim()) { setDelErr('Give a short reason. It is kept in the history.'); return; }
    setDelBusy(true); setDelErr(null);
    const { data, error } = await supabase.rpc('soft_delete_voucher', {
      p_voucher_id: delFor.voucher.id, p_reason: delReason.trim(), p_confirmed: true,
    });
    setDelBusy(false);
    if (error) { setDelErr(error.message); return; }
    if (!(data as VoucherDeleteAnswer | null)?.deleted) { setDelErr('The voucher was not deleted. Refresh and try again.'); return; }
    setNotice(`"${delFor.voucher.name}" deleted. Customers keep the vouchers they hold.`);
    setDelFor(null);
    load();
  };

  const openStock = (v: VoucherRow) => { setStockFor(v); setStockStore(stores[0]?.id ?? ''); setStockQty(0); setStockRequestId(crypto.randomUUID()); };
  const addStock = async () => {
    if (!stockFor || !stockStore || stockQty <= 0) return;
    setStockBusy(true);
    const { error } = await supabase.rpc('voucher_stock_in', { p_voucher_id: stockFor.id, p_store_id: stockStore, p_quantity: stockQty, p_note: null, p_request_id: stockRequestId });
    setStockBusy(false);
    if (error) { alert(error.message); return; }
    setStockFor(null); load();
  };

  const stockFancy = (vId: string) => stock.filter(s => s.voucher_id === vId);
  // Dates are days (YYYY-MM-DD), shown as they are, with no time zone shift.
  const validityText = (v: VoucherRow) => {
    const f = v.valid_from ? dayText(v.valid_from) : null;
    const u = v.valid_until ? dayText(v.valid_until) : null;
    if (!f && !u) return 'No expiry';
    if (f && u) return `${f} → ${u}`;
    if (u) return `Until ${u}`;
    return `From ${f}`;
  };
  const today = sgToday();
  const filtered = rows.filter(v => { const q = search.toLowerCase(); return !q || v.name.toLowerCase().includes(q) || v.code.toLowerCase().includes(q); });

  const kindBadge = (k: VoucherKind) => {
    const cls = k === 'normal' ? 'badge-primary' : k === 'fixed_discount' ? 'badge-accent' : 'badge-success';
    return <span className={`badge ${cls}`}>{VOUCHER_KIND_LABELS[k]}</span>;
  };

  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage vouchers." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Vouchers</h2><p>Sellable vouchers and discount vouchers. Limited vouchers track stock per store.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={filtered} filename="vouchers" sheetName="Vouchers"
            dateOf={(r: any) => r.created_at} dateLabel="Created"
            columns={[
              { header: 'Name', value: (v: any) => v.name },
              { header: 'Code', value: (v: any) => v.code },
              { header: 'Type', value: (v: any) => v.voucher_kind },
              { header: 'Offered as', value: (v: any) => categoryText(v) ?? '' },
              { header: 'Qty type', value: (v: any) => v.qty_type },
              { header: 'Selling price', value: (v: any) => Number(v.selling_price ?? 0) },
              { header: 'Valid from', value: (v: any) => dayNumbers(v.valid_from) },
              { header: 'Valid until', value: (v: any) => v.valid_until ? dayNumbers(v.valid_until) : 'No expiry' },
              // A discount voucher is never a reward: 422's rule (THERAPY-7), live before this page.
              { header: 'Can be a reward', value: (v: any) => v.voucher_kind === 'normal' ? (v.reward_eligible === false ? 'No' : 'Yes') : 'No' },
              { header: 'Status', value: (v: any) => v.is_active ? 'Active' : 'Inactive' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Voucher</button>
        </div>
      </div>

      {pageErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{pageErr}</div></div>}
      {notice && <div className="alert alert-success" role="status"><span>✓</span><div>{notice}</div></div>}

      <div style={{ marginBottom: 14, position: 'relative', maxWidth: 360 }}>
        <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name or code…" style={{ paddingLeft: 34 }} />
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><Ticket size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No vouchers yet</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Code</th><th>Type</th><th>Value</th><th>Qty</th><th>Validity</th><th style={{ textAlign: 'right' }}>Price</th><th></th></tr></thead>
              <tbody>
                {filtered.map(v => (
                  <tr key={v.id}>
                    <td><strong>{v.name}</strong></td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{v.code}</td>
                    <td>{kindBadge(v.voucher_kind)}
                      {categoryText(v) && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>{categoryText(v)}</div>}
                      {v.voucher_kind === 'normal' && v.reward_eligible === false &&
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>Not given as a reward</div>}</td>
                    <td style={{ fontSize: 13 }}>
                      {v.voucher_kind === 'fixed_discount' ? money(v.discount_amount ?? 0)
                        : v.voucher_kind === 'percentage_discount' ? `${v.discount_percent}%${v.max_discount_cap ? ` (cap ${money(v.max_discount_cap)})` : ''}`
                        : '—'}
                    </td>
                    <td style={{ fontSize: 12.5 }}>
                      {v.qty_type === 'unlimited' ? <span className="badge badge-muted">Unlimited</span>
                        : <span>{stockFancy(v.id).reduce((s, x) => s + x.current_qty, 0)} in stock</span>}
                    </td>
                    {/* Red only after the last valid day, in Singapore. */}
                    <td style={{ fontSize: 11.5, color: isPastValidUntil(v.valid_until, today) ? 'var(--danger)' : 'var(--text-muted)' }}>{validityText(v)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(v.selling_price)}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {v.qty_type === 'limited' && <button className="btn btn-secondary btn-sm" onClick={() => openStock(v)}><Boxes size={13} /> Stock</button>}
                      <button className="btn btn-secondary btn-sm" title="Per-store selling prices" onClick={() => setMnmFor({ id: v.id, name: v.name })}>Prices</button>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(v)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" aria-label={`Delete ${v.name}`} onClick={() => handleDelete(v)}><Trash2 size={13} /></button>
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {modal && (
        <VoucherEditModal voucher={modal.voucher} onClose={() => setModal(null)} onChanged={load} />
      )}

      {stockFor && (
        <Modal title={`Voucher Stock — ${stockFor.name}`} maxWidth={420} onClose={() => setStockFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setStockFor(null)}>Close</button><button className="btn btn-primary" onClick={addStock} disabled={stockBusy || !stockStore || stockQty <= 0}>{stockBusy ? 'Adding…' : 'Add Stock'}</button></>}>
          <div className="form-grid">
            <div className="form-grid-2">
              <div className="form-group">
                <label>Store</label>
                <select value={stockStore} onChange={e => setStockStore(e.target.value)}>
                  {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
              <div className="form-group"><label>Add Quantity</label><input type="number" min={1} value={stockQty || ''} onChange={e => setStockQty(+e.target.value)} placeholder="0" /></div>
            </div>
            <div>
              <label>Current stock by store</label>
              <table style={{ marginTop: 4 }}>
                <thead><tr><th>Store</th><th style={{ textAlign: 'right' }}>Qty</th></tr></thead>
                <tbody>
                  {stockFancy(stockFor.id).length === 0 ? <tr><td colSpan={2} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 14 }}>No stock yet</td></tr>
                    : stockFancy(stockFor.id).map(s => (
                      <tr key={s.id}><td>{stores.find(st => st.id === s.store_id)?.name ?? '—'}</td><td style={{ textAlign: 'right', fontWeight: 600 }}>{s.current_qty}</td></tr>
                    ))}
                </tbody>
              </table>
            </div>
          </div>
        </Modal>
      )}
      {delFor && (
        <Modal title={`Delete ${delFor.voucher.name}?`} maxWidth={480} onClose={() => setDelFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setDelFor(null)}>Keep it</button>
            <button className="btn btn-danger" onClick={() => void confirmDelete()} disabled={delBusy || !delReason.trim()}>
              {delBusy ? 'Deleting…' : 'Delete anyway'}</button></>}>
          <div className="form-grid">
            <div className="alert alert-warning" style={{ marginBottom: 0 }}>
              <span>⚠</span>
              <div>
                <strong>This voucher is still in use.</strong>
                <ul style={{ margin: '6px 0 0 18px' }}>
                  {voucherDependents(delFor.answer).map((line, i) => <li key={i}>{line}</li>)}
                </ul>
                <div style={{ marginTop: 6 }}>
                  Deleting it stops it being sold or offered. Past invoices still show it.
                </div>
              </div>
            </div>
            {delErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{delErr}</div></div>}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label htmlFor="voucher-delete-reason">Reason *</label>
              <textarea id="voucher-delete-reason" rows={2} value={delReason} placeholder="For example: the event is over"
                onChange={e => { setDelReason(e.target.value); setDelErr(null); }} />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Kept in the history, with your name.</div>
            </div>
          </div>
        </Modal>
      )}
      {mnmFor && (
        <StorePriceEditor kind="voucher" targetId={mnmFor.id} targetName={mnmFor.name}
          stores={stores} onClose={() => setMnmFor(null)} />
      )}
    </div>
  );
};

export default VouchersPage;
