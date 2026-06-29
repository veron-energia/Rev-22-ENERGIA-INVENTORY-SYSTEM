import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, InvoiceItem, InvoicePayment, Store, Product, Customer, Affiliate,
  PaymentMethod, StoreProductPrice, InvoiceStatus, INVOICE_STATUS_LABELS,
} from '../types';
import { Modal } from '../components/ui';
import {
  Plus, RefreshCw, FileText, Trash2, X, CreditCard, Eye, Search, CheckCircle2,
} from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

const StatusBadge: React.FC<{ s: InvoiceStatus }> = ({ s }) => {
  const cls = s === 'paid' ? 'badge-success' : s === 'partially_paid' ? 'badge-primary'
    : s === 'unpaid' || s === 'draft' ? 'badge-accent'
    : s === 'cancelled' || s === 'refunded' ? 'badge-muted' : 'badge-danger';
  return <span className={`badge ${cls}`}>{INVOICE_STATUS_LABELS[s]}</span>;
};

interface LineDraft { product_id: string; quantity: number; }

const InvoicesPage: React.FC = () => {
  const { profile } = useAuth();
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [affiliates, setAffiliates] = useState<Affiliate[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [prices, setPrices] = useState<StoreProductPrice[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<'all' | InvoiceStatus>('all');

  // Create modal
  const [createOpen, setCreateOpen] = useState(false);
  const [cStore, setCStore] = useState('');
  const [cCustomer, setCCustomer] = useState('');
  const [cAffiliate, setCAffiliate] = useState('');
  const [cLines, setCLines] = useState<LineDraft[]>([{ product_id: '', quantity: 1 }]);
  const [cDiscount, setCDiscount] = useState(0);
  const [cErr, setCErr] = useState<string | null>(null);
  const [cSaving, setCSaving] = useState(false);

  // Detail / payment modal
  const [detail, setDetail] = useState<Invoice | null>(null);
  const [detailItems, setDetailItems] = useState<InvoiceItem[]>([]);
  const [detailPayments, setDetailPayments] = useState<InvoicePayment[]>([]);
  const [payLines, setPayLines] = useState<{ payment_method_id: string; amount: number }[]>([]);
  const [payErr, setPayErr] = useState<string | null>(null);
  const [payBusy, setPayBusy] = useState(false);

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [inv, st, pr, cu, af, pm, pp] = await Promise.all([
      supabase.from('invoices').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('*').is('deleted_at', null).order('full_name'),
      supabase.from('affiliates').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('store_product_prices').select('*').is('deleted_at', null),
    ]);
    setInvoices((inv.data as Invoice[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setAffiliates((af.data as Affiliate[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    setPrices((pp.data as StoreProductPrice[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { loadAll(); }, [loadAll]);

  const storeName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const custName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const prodName = (id: string) => products.find(p => p.id === id)?.name ?? '—';
  const methodName = (id: string) => methods.find(m => m.id === id)?.name ?? '—';
  const priceFor = (storeId: string, productId: string) =>
    prices.find(p => p.store_id === storeId && p.product_id === productId)?.selling_price ?? null;

  // Products available at the chosen store (those with a price).
  const storeProducts = useMemo(() =>
    cStore ? products.filter(p => priceFor(cStore, p.id) !== null) : [],
    [cStore, products, prices]);

  const createSubtotal = useMemo(() =>
    cLines.reduce((sum, l) => {
      const price = cStore && l.product_id ? priceFor(cStore, l.product_id) : null;
      return sum + (price ? price * l.quantity : 0);
    }, 0), [cLines, cStore, prices]);

  const resetCreate = () => {
    setCStore(''); setCCustomer(''); setCAffiliate('');
    setCLines([{ product_id: '', quantity: 1 }]); setCDiscount(0); setCErr(null);
  };

  const handleCreate = async () => {
    if (!cStore) { setCErr('Select a store.'); return; }
    if (!cCustomer) { setCErr('Select a customer.'); return; }
    const validLines = cLines.filter(l => l.product_id && l.quantity > 0);
    if (validLines.length === 0) { setCErr('Add at least one product.'); return; }
    setCSaving(true); setCErr(null);
    const { error } = await supabase.rpc('create_invoice', {
      p_store_id: cStore, p_customer_id: cCustomer, p_affiliate_id: cAffiliate || null,
      p_items: validLines, p_discount_total: cDiscount || 0, p_notes: null,
    });
    setCSaving(false);
    if (error) { setCErr(error.message); return; }
    setCreateOpen(false); resetCreate(); loadAll();
  };

  const openDetail = async (inv: Invoice) => {
    setDetail(inv);
    const [items, pays] = await Promise.all([
      supabase.from('invoice_items').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_payments').select('*').eq('invoice_id', inv.id),
    ]);
    setDetailItems((items.data as InvoiceItem[]) ?? []);
    setDetailPayments((pays.data as InvoicePayment[]) ?? []);
    const remaining = inv.total_amount - inv.paid_amount;
    setPayLines([{ payment_method_id: methods[0]?.id ?? '', amount: remaining > 0 ? remaining : 0 }]);
    setPayErr(null);
  };

  const payTotal = useMemo(() => payLines.reduce((s, p) => s + (p.amount || 0), 0), [payLines]);

  const handlePay = async () => {
    if (!detail) return;
    const valid = payLines.filter(p => p.payment_method_id && p.amount > 0);
    if (valid.length === 0) { setPayErr('Add at least one payment.'); return; }
    setPayBusy(true); setPayErr(null);
    const { error } = await supabase.rpc('pay_invoice', { p_invoice_id: detail.id, p_payments: valid });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    setDetail(null); loadAll();
  };

  const handleDelete = async (inv: Invoice) => {
    if (inv.status === 'paid') { alert('Paid invoices cannot be deleted.'); return; }
    if (!confirm(`Delete invoice ${inv.invoice_no}?`)) return;
    const { error } = await supabase.rpc('delete_invoice', { p_invoice_id: inv.id });
    if (error) { alert(error.message); return; }
    loadAll();
  };

  // Phase 4: request refund or cancellation
  const [actionType, setActionType] = useState<'invoice_refund' | 'invoice_cancel' | null>(null);
  const [actionReturnStock, setActionReturnStock] = useState(true);
  const [actionReason, setActionReason] = useState('');
  const [actionBusy, setActionBusy] = useState(false);
  const [actionErr, setActionErr] = useState<string | null>(null);

  const submitAction = async () => {
    if (!detail || !actionType) return;
    if (!actionReason.trim()) { setActionErr('A reason is required.'); return; }
    setActionBusy(true); setActionErr(null);
    const { error } = await supabase.rpc('request_invoice_action', {
      p_invoice_id: detail.id, p_type: actionType,
      p_return_stock: actionReturnStock, p_reason: actionReason.trim(),
    });
    setActionBusy(false);
    if (error) { setActionErr(error.message); return; }
    setActionType(null); setActionReason(''); setDetail(null); loadAll();
  };

  const filtered = invoices.filter(i => statusFilter === 'all' || i.status === statusFilter);
  const statusOptions: ('all' | InvoiceStatus)[] = ['all', 'unpaid', 'partially_paid', 'paid', 'cancelled', 'refunded'];

  return (
    <div>
      <div className="page-header">
        <div><h2>Invoices</h2><p>Create invoices for a store. Stock is deducted only when an invoice is fully paid.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={loadAll}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={() => { resetCreate(); setCreateOpen(true); }}><Plus size={16} /> New Invoice</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
        {statusOptions.map(s => (
          <button key={s} className={`btn btn-sm ${statusFilter === s ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setStatusFilter(s)}>
            {s === 'all' ? 'All' : INVOICE_STATUS_LABELS[s]}
          </button>
        ))}
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><FileText size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No invoices yet</p></div>
          : (
            <table>
              <thead><tr><th>Invoice</th><th>Date</th><th>Store</th><th>Customer</th><th style={{ textAlign: 'right' }}>Total</th><th style={{ textAlign: 'right' }}>Paid</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(inv => (
                  <tr key={inv.id}>
                    <td><strong style={{ fontFamily: 'var(--font-display)' }}>{inv.invoice_no}</strong></td>
                    <td style={{ fontSize: 12.5, whiteSpace: 'nowrap' }}>{new Date(inv.created_at).toLocaleDateString()}</td>
                    <td style={{ fontSize: 12.5 }}>{storeName(inv.store_id)}</td>
                    <td style={{ fontSize: 13 }}>{custName(inv.customer_id)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(inv.total_amount)}</td>
                    <td style={{ textAlign: 'right', color: inv.paid_amount >= inv.total_amount ? 'var(--success)' : 'var(--text-muted)' }}>{money(inv.paid_amount)}</td>
                    <td><StatusBadge s={inv.status} /></td>
                    <td>
                      <div style={{ display: 'flex', gap: 4 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openDetail(inv)}><Eye size={13} /> View</button>
                        {inv.status !== 'paid' && inv.status !== 'cancelled' && inv.status !== 'refunded' && (
                          <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(inv)}><Trash2 size={13} /></button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Create invoice modal */}
      {createOpen && (
        <Modal title="New Invoice" maxWidth={640} onClose={() => setCreateOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setCreateOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleCreate} disabled={cSaving}>{cSaving ? 'Creating…' : 'Create Invoice'}</button></>}>
          <div className="form-grid">
            {cErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{cErr}</div></div>}
            <div className="form-grid-2">
              <div className="form-group">
                <label>Store *</label>
                <select value={cStore} onChange={e => { setCStore(e.target.value); setCLines([{ product_id: '', quantity: 1 }]); }}>
                  <option value="">— Select store —</option>
                  {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label>Customer *</label>
                <select value={cCustomer} onChange={e => setCCustomer(e.target.value)}>
                  <option value="">— Select customer —</option>
                  {customers.map(c => <option key={c.id} value={c.id}>{c.full_name} ({c.phone})</option>)}
                </select>
              </div>
            </div>
            <div className="form-group">
              <label>Affiliate (optional — earns commission when paid)</label>
              <select value={cAffiliate} onChange={e => setCAffiliate(e.target.value)}>
                <option value="">— None —</option>
                {affiliates.map(a => <option key={a.id} value={a.id}>{a.name} ({a.commission_value}%)</option>)}
              </select>
            </div>

            {cStore && (
              <div>
                <label>Products <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— only products priced at this store appear</span></label>
                {storeProducts.length === 0 ? (
                  <div className="alert alert-warning" style={{ marginTop: 6 }}><span>⚠</span><div>This store has no priced products. Set prices in the Price List first.</div></div>
                ) : (
                  <>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }}>
                      {cLines.map((line, i) => {
                        const price = line.product_id ? priceFor(cStore, line.product_id) : null;
                        return (
                          <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                            <select value={line.product_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, product_id: e.target.value } : l))} style={{ flex: 1 }}>
                              <option value="">— Product —</option>
                              {storeProducts.map(p => <option key={p.id} value={p.id}>{p.name} — {money(priceFor(cStore, p.id)!)}</option>)}
                            </select>
                            <input type="number" min={1} value={line.quantity || ''} placeholder="Qty" style={{ width: 80 }}
                              onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, quantity: +e.target.value } : l))} />
                            <span style={{ width: 80, textAlign: 'right', fontSize: 13, fontWeight: 600 }}>{price ? money(price * line.quantity) : '—'}</span>
                            <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setCLines(ls => ls.filter((_, j) => j !== i))} disabled={cLines.length === 1}><X size={13} /></button>
                          </div>
                        );
                      })}
                    </div>
                    <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setCLines(ls => [...ls, { product_id: '', quantity: 1 }])}><Plus size={13} /> Add Product</button>
                  </>
                )}
              </div>
            )}

            <div className="form-grid-2">
              <div className="form-group"><label>Discount (S$)</label><input type="number" min={0} step={0.01} value={cDiscount || ''} onChange={e => setCDiscount(+e.target.value)} placeholder="0.00" /></div>
              <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
                <div style={{ textAlign: 'right', fontSize: 13, color: 'var(--text-secondary)' }}>Subtotal: <strong>{money(createSubtotal)}</strong></div>
                <div style={{ textAlign: 'right', fontSize: 16, fontWeight: 700, marginTop: 2 }}>Total: {money(Math.max(0, createSubtotal - cDiscount))}</div>
              </div>
            </div>
          </div>
        </Modal>
      )}

      {/* Invoice detail + payment modal */}
      {detail && (
        <Modal title={`Invoice ${detail.invoice_no}`} maxWidth={560} onClose={() => setDetail(null)}
          footer={
            detail.status === 'paid'
              ? <><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button><button className="btn btn-danger" onClick={() => { setActionType('invoice_refund'); setActionReturnStock(true); setActionReason(''); setActionErr(null); }}>Request Refund</button></>
              : detail.status === 'cancelled' || detail.status === 'refunded' || detail.status === 'cancellation_requested' || detail.status === 'refund_requested'
              ? <button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
              : <><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button><button className="btn btn-primary" onClick={handlePay} disabled={payBusy}><CreditCard size={15} /> {payBusy ? 'Processing…' : 'Record Payment'}</button></>
          }>
          <div className="form-grid">
            {/* Summary */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{storeName(detail.store_id)} · {custName(detail.customer_id)}</div>
                <div style={{ marginTop: 4 }}><StatusBadge s={detail.status} /></div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 20, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(detail.total_amount)}</div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Paid {money(detail.paid_amount)}</div>
              </div>
            </div>

            {/* Items */}
            <div>
              <label>Items</label>
              <table style={{ marginTop: 4 }}>
                <thead><tr><th>Product</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Price</th><th style={{ textAlign: 'right' }}>Total</th></tr></thead>
                <tbody>
                  {detailItems.map(it => (
                    <tr key={it.id}>
                      <td>{prodName(it.product_id)}</td>
                      <td style={{ textAlign: 'right' }}>{it.quantity}</td>
                      <td style={{ textAlign: 'right' }}>{money(it.unit_price)}</td>
                      <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(it.line_total)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Existing payments */}
            {detailPayments.length > 0 && (
              <div>
                <label>Payments Recorded</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                  {detailPayments.map(p => (
                    <div key={p.id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                      <span>{methodName(p.payment_method_id)}</span>
                      <span style={{ fontWeight: 600 }}>{money(p.amount)}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Payment entry (only if not fully paid) */}
            {detail.status !== 'paid' && detail.status !== 'cancelled' && detail.status !== 'refunded' && (
              <div>
                {payErr && <div className="alert alert-danger"><span>⚠</span><div>{payErr}</div></div>}
                <label>Record Payment <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— split across methods if needed</span></label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }}>
                  {payLines.map((pl, i) => (
                    <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                      <select value={pl.payment_method_id} onChange={e => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, payment_method_id: e.target.value } : l))} style={{ flex: 1 }}>
                        <option value="">— Method —</option>
                        {methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                      </select>
                      <input type="number" min={0} step={0.01} value={pl.amount || ''} placeholder="Amount" style={{ width: 110 }}
                        onChange={e => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, amount: +e.target.value } : l))} />
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setPayLines(ls => ls.filter((_, j) => j !== i))} disabled={payLines.length === 1}><X size={13} /></button>
                    </div>
                  ))}
                </div>
                <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setPayLines(ls => [...ls, { payment_method_id: methods[0]?.id ?? '', amount: 0 }])}><Plus size={13} /> Split Payment</button>

                <div style={{ marginTop: 12, padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', fontSize: 13 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Remaining balance</span><strong>{money(detail.total_amount - detail.paid_amount)}</strong></div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4 }}><span>This payment</span><strong>{money(payTotal)}</strong></div>
                  {payTotal >= (detail.total_amount - detail.paid_amount) - 0.001 && payTotal > 0 && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8, color: 'var(--success)', fontWeight: 600 }}>
                      <CheckCircle2 size={15} /> This completes the invoice — stock will be deducted.
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        </Modal>
      )}

      {/* Refund / cancel request modal */}
      {actionType && detail && (
        <Modal title={actionType === 'invoice_refund' ? 'Request Refund' : 'Request Cancellation'} maxWidth={440} onClose={() => setActionType(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setActionType(null)}>Back</button><button className="btn btn-danger" onClick={submitAction} disabled={actionBusy}>{actionBusy ? 'Submitting…' : 'Submit Request'}</button></>}>
          <div className="form-grid">
            {actionErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{actionErr}</div></div>}
            <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
              This sends a request for Owner/Manager approval. {actionType === 'invoice_refund' ? 'Refunds' : 'Cancellations'} reverse any affiliate commission.
            </p>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', padding: '10px 12px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
              <input type="checkbox" checked={actionReturnStock} onChange={e => setActionReturnStock(e.target.checked)} style={{ width: 'auto' }} />
              <div>
                <div style={{ fontSize: 13, fontWeight: 600 }}>Return stock to store</div>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Tick if items are resellable. Untick if damaged/lost.</div>
              </div>
            </label>
            <div className="form-group"><label>Reason *</label><textarea rows={2} value={actionReason} onChange={e => setActionReason(e.target.value)} placeholder="Why is this being requested?" autoFocus /></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default InvoicesPage;
