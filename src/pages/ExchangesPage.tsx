import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase, fetchCustomersByIds, mergeCustomers} from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Invoice, InvoiceItem, Product, Store, Customer, PaymentMethod, ProductExchange, ProductExchangeItem, Promotion, isManagerOrAbove } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Plus, ArrowLeftRight, Trash2, Eye, Printer } from 'lucide-react';

const money = (n: number) => `S$${Number(n).toFixed(2)}`;

const ExchangesPage: React.FC = () => {
  const { profile } = useAuth();
  const [exchanges, setExchanges] = useState<ProductExchange[]>([]);
  const [exchangeInvoiceNos, setExchangeInvoiceNos] = useState<Record<string, string>>({});
  const [products, setProducts] = useState<Product[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [prices, setPrices] = useState<{ store_id: string; product_id: string; selling_price: number; is_active: boolean }[]>([]);
  const [storeInv, setStoreInv] = useState<{ store_id: string; product_id: string; current_qty: number }[]>([]);
  const [loading, setLoading] = useState(true);
  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  const [promotions, setPromotions] = useState<Promotion[]>([]);

  const isStaff = profile?.role === 'staff';

  const load = useCallback(async () => {
    setLoading(true);
    const [ex, exinv, pr, st, cu, pm, spp, si, mine, promo] = await Promise.all([
      supabase.from('product_exchanges').select('*').order('created_at', { ascending: false }),
      supabase.from('invoices').select('id, invoice_no, exchange_id').eq('is_exchange', true),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('*').is('deleted_at', null),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('store_product_prices').select('store_id,product_id,selling_price,is_active').eq('is_active', true),
      supabase.from('store_inventory').select('store_id,product_id,current_qty'),
      supabase.rpc('my_assigned_store_id'),
      supabase.from('promotions').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setExchanges((ex.data as ProductExchange[]) ?? []);
    const exMap: Record<string, string> = {};
    for (const r of ((exinv.data as any[]) ?? [])) if (r.exchange_id) exMap[r.exchange_id] = r.invoice_no;
    setExchangeInvoiceNos(exMap);
    setProducts((pr.data as Product[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    const baseCustomers = (cu.data as Customer[]) ?? [];
    setCustomers(baseCustomers);
    // The customer table is capped at 1000 rows per request, so records
    // belonging to customers outside that set would show no name. Fetch the
    // ones actually referenced here.
    void (async () => {
      const extra = await fetchCustomersByIds(((ex.data as any[]) ?? []).map(x => x.customer_id));
      setCustomers(cur => mergeCustomers(cur, extra));
    })();
    setMethods((pm.data as PaymentMethod[]) ?? []);
    setPrices((spp.data as any[]) ?? []);
    setStoreInv((si.data as any[]) ?? []);
    setAssignedStoreId((mine.data as string | null) ?? null);
    setPromotions((promo.data as Promotion[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const pName = (id: string) => products.find(p => p.id === id)?.name ?? '—';
  const pSku = (id: string) => products.find(p => p.id === id)?.sku ?? '';
  const cName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const sName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const priceAt = (storeId: string, productId: string) => prices.find(p => p.store_id === storeId && p.product_id === productId)?.selling_price ?? null;
  const stockAt = (storeId: string, productId: string) => storeInv.find(s => s.store_id === storeId && s.product_id === productId)?.current_qty ?? 0;

  // ---- New exchange wizard ----
  const [wizard, setWizard] = useState(false);
  const [mode, setMode] = useState<'product' | 'bundle' | 'component'>('product');
  const [bundleLineId, setBundleLineId] = useState('');      // chosen bundle invoice_item id
  const [newPromoId, setNewPromoId] = useState('');          // replacement bundle B
  const [componentPid, setComponentPid] = useState('');      // component product to exchange
  const [componentQty, setComponentQty] = useState(1);
  const [bundleComps, setBundleComps] = useState<{ product_id: string; quantity: number }[]>([]);
  const [store, setStore] = useState('');
  const [invSearch, setInvSearch] = useState('');
  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [invItems, setInvItems] = useState<InvoiceItem[]>([]);
  const [eligMsg, setEligMsg] = useState<string | null>(null);
  const [returnIds, setReturnIds] = useState<string[]>([]);
  const [repl, setRepl] = useState<{ product_id: string; quantity: number }[]>([{ product_id: '', quantity: 1 }]);
  const [pays, setPays] = useState<{ payment_method_id: string; amount: number; reference: string }[]>([]);
  const [reason, setReason] = useState('');
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [attestName, setAttestName] = useState('');

  const effectiveStore = isStaff ? (assignedStoreId ?? '') : store;

  const resetWizard = () => {
    setStore(isStaff ? (assignedStoreId ?? '') : ''); setInvSearch(''); setInvoice(null); setInvItems([]);
    setEligMsg(null); setReturnIds([]); setRepl([{ product_id: '', quantity: 1 }]); setPays([]); setReason(''); setNotes(''); setErr(null);
    setMode('product'); setBundleLineId(''); setNewPromoId(''); setComponentPid(''); setComponentQty(1); setBundleComps([]);
  };
  const openWizard = () => { resetWizard(); setWizard(true); };

  const findInvoice = async () => {
    setErr(null); setInvoice(null); setInvItems([]); setEligMsg(null); setReturnIds([]);
    const q = invSearch.trim();
    if (!q) return;
    const { data: inv } = await supabase.from('invoices').select('*').eq('invoice_no', q).maybeSingle();
    if (!inv) { setErr('No invoice found with that number.'); return; }
    const { data: reasonData } = await supabase.rpc('exchange_ineligibility_reason', { p_invoice_id: (inv as Invoice).id });
    const rd = (reasonData as string | null) ?? '';
    if (rd !== '') { setEligMsg(rd); }
    const { data: items } = await supabase.from('invoice_items').select('*').eq('invoice_id', (inv as Invoice).id);
    setInvoice(inv as Invoice);
    setInvItems((items as InvoiceItem[]) ?? []);
  };

  const productLines = invItems.filter(i => i.line_kind === 'product');
  const bundleLines = invItems.filter(i => i.line_kind === 'promotion');
  const returnedItems = productLines.filter(i => returnIds.includes(i.id));

  // load components of the chosen bundle line
  const loadBundleComps = async (lineId: string) => {
    setBundleLineId(lineId); setComponentPid(''); setComponentQty(1);
    if (!lineId) { setBundleComps([]); return; }
    const { data } = await supabase.rpc('bundle_line_components', { p_invoice_item_id: lineId });
    setBundleComps(((data as any[]) ?? []).map(r => ({ product_id: r.product_id, quantity: Number(r.quantity) })));
  };

  // bundle valuation (uses promotion regular totals — computed server-side; show best-effort here)
  const promoName = (id: string) => promotions.find(p => p.id === id)?.name ?? '—';
  const returnedType = useMemo(() => {
    if (returnedItems.length === 0) return null;
    const types = new Set(returnedItems.map(i => products.find(p => p.id === (i.product_id ?? ''))?.product_type));
    return types.size === 1 ? [...types][0] : 'MIXED';
  }, [returnedItems, products]);

  const creditTotal = useMemo(() => returnedItems.reduce((s, i) => {
    const pr = priceAt(effectiveStore, i.product_id ?? ''); return s + (pr ?? 0) * i.quantity;
  }, 0), [returnedItems, effectiveStore, prices]);

  const replLines = repl.filter(r => r.product_id && r.quantity > 0);
  const replTotal = useMemo(() => replLines.reduce((s, r) => {
    const pr = priceAt(effectiveStore, r.product_id); return s + (pr ?? 0) * r.quantity;
  }, 0), [replLines, effectiveStore, prices]);

  const topup = Math.max(0, +(replTotal - creditTotal).toFixed(2));
  const nonref = Math.max(0, +(creditTotal - replTotal).toFixed(2));
  const paySum = pays.reduce((s, p) => s + (Number(p.amount) || 0), 0);
  // Mode-aware credit (component mode uses the selected component's store price).
  const modeCredit = mode === 'component' ? (priceAt(effectiveStore, componentPid) ?? 0) * componentQty : creditTotal;
  const compTopup = mode === 'bundle' ? 0 : Math.max(0, +(replTotal - modeCredit).toFixed(2));
  const compNonref = mode === 'bundle' ? 0 : Math.max(0, +(modeCredit - replTotal).toFixed(2));

  // replacement products must match returned type (own/third)
  const replCandidates = products.filter(p => returnedType && returnedType !== 'MIXED' ? p.product_type === returnedType : true);

  const validate = (): string | null => {
    if (!effectiveStore) return 'Select a processing store.';
    if (!invoice) return 'Find the original invoice first.';
    if (eligMsg) return eligMsg;
    if (!reason.trim()) return 'A reason is required for the exchange.';
    if (mode === 'product') {
      if (returnIds.length === 0) return 'Select at least one item to return.';
      if (returnedType === 'MIXED') return 'All returned items must be the same product type.';
      if (replLines.length === 0) return 'Add at least one replacement product.';
      if (compTopup > 0 && Math.abs(paySum - compTopup) > 0.001) return `Top-up payment must total ${money(compTopup)}.`;
    } else if (mode === 'bundle') {
      if (!bundleLineId) return 'Select the bundle being returned.';
      if (!newPromoId) return 'Select the replacement bundle.';
    } else if (mode === 'component') {
      if (!bundleLineId) return 'Select the bundle.';
      if (!componentPid) return 'Select the component to exchange.';
      if (componentQty <= 0) return 'Component quantity must be greater than zero.';
      if (replLines.length === 0) return 'Add at least one replacement product.';
      if (compTopup > 0 && Math.abs(paySum - compTopup) > 0.001) return `Top-up payment must total ${money(compTopup)}.`;
    }
    return null;
  };

  const openConfirm = () => {
    const v = validate();
    if (v) { setErr(v); return; }
    setErr(null); setAttestName(''); setConfirming(true);
  };

  const submit = async () => {
    setErr(null);
    const v = validate();
    if (v) { setErr(v); setConfirming(false); return; }
    if (!invoice) return;
    setBusy(true);
    const payPayload = (compTopup > 0 || mode === 'bundle') ? pays.filter(p => p.payment_method_id && Number(p.amount) > 0).map(p => ({ payment_method_id: p.payment_method_id, amount: p.amount, reference: p.reference })) : [];
    let data: any, error: any;
    if (mode === 'product') {
      ({ data, error } = await supabase.rpc('create_product_exchange', {
        p_original_invoice_id: invoice.id, p_processing_store_id: effectiveStore,
        p_returned: returnedItems.map(i => ({ invoice_item_id: i.id, quantity: i.quantity })),
        p_replacement: replLines, p_payments: payPayload,
        p_reason: reason.trim() || null, p_notes: notes.trim() || null,
      }));
    } else if (mode === 'bundle') {
      ({ data, error } = await supabase.rpc('create_bundle_exchange', {
        p_original_invoice_id: invoice.id, p_processing_store_id: effectiveStore,
        p_original_invoice_item_id: bundleLineId, p_new_promotion_id: newPromoId,
        p_payments: payPayload, p_reason: reason.trim() || null, p_notes: notes.trim() || null,
      }));
    } else {
      ({ data, error } = await supabase.rpc('create_bundle_component_exchange', {
        p_original_invoice_id: invoice.id, p_processing_store_id: effectiveStore,
        p_original_invoice_item_id: bundleLineId, p_component_product_id: componentPid, p_component_qty: componentQty,
        p_replacement: replLines, p_payments: payPayload, p_reason: reason.trim() || null, p_notes: notes.trim() || null,
      }));
    }
    setBusy(false);
    if (error) { setErr(error.message); setConfirming(false); return; }
    setConfirming(false); setWizard(false); load();
    alert(`Exchange ${(data as any)?.exchange_no ?? ''} completed.`);
  };

  // ---- Detail view ----
  const [detail, setDetail] = useState<ProductExchange | null>(null);
  const [detailItems, setDetailItems] = useState<ProductExchangeItem[]>([]);
  const openDetail = async (e: ProductExchange) => {
    setDetail(e); setDetailItems([]);
    const { data } = await supabase.from('product_exchange_items').select('*').eq('exchange_id', e.id);
    setDetailItems((data as ProductExchangeItem[]) ?? []);
  };

  // Print an exchange document in the same style as invoice printing.
  const printExchange = () => {
    if (!detail) return;
    const esc = (x: any) => String(x ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;');
    const st: any = stores.find(x => x.id === detail.processing_store_id) ?? {};
    const cust = customers.find(c => c.id === detail.customer_id);
    const inv = exchangeInvoiceNos[detail.id];
    const rowsFor = (dir: 'returned' | 'replacement') => detailItems.filter(i => i.direction === dir)
      .map(i => `<tr><td>${esc(pName(i.product_id))}</td><td class="r">${i.quantity}</td><td class="r">S$${Number(i.unit_price).toFixed(2)}</td><td class="r">S$${Number(i.line_total).toFixed(2)}</td></tr>`).join('');
    const headBlock = (st.company_logo_url || st.store_logo_url)
      ? `<div style="display:flex;gap:16px;align-items:center;margin-bottom:10px">
          ${st.company_logo_url ? `<img src="${esc(st.company_logo_url)}" style="max-height:48px;max-width:180px;object-fit:contain" />` : ''}
          ${st.store_logo_url ? `<img src="${esc(st.store_logo_url)}" style="max-height:48px;max-width:180px;object-fit:contain" />` : ''}
        </div>` : '';
    const focStamp = (detail as any).is_foc
      ? `<div class="mut"><b>FREE OF CHARGE EXCHANGE</b> — FOC value S$${Number((detail as any).foc_amount ?? 0).toFixed(2)}${(detail as any).foc_reason ? ` · ${esc((detail as any).foc_reason)}` : ''}</div>` : '';
    const html = `<!doctype html><html><head><title>${esc(detail.exchange_no)}</title><style>
      @page { size: A4; margin: 10mm; }
      body{font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#111;margin:0;}
      h1{font-size:18px;margin:0;} h2{font-size:12px;margin:12px 0 4px;text-transform:uppercase;letter-spacing:0.04em;color:#333;}
      .mut{color:#666;font-size:10.5px;} .r{text-align:right;}
      table{width:100%;border-collapse:collapse;margin-top:4px;}
      th{font-size:10px;text-transform:uppercase;color:#666;text-align:left;border-bottom:1px solid #999;padding:4px 6px;}
      th.r{text-align:right;} td{padding:4px 6px;border-bottom:1px solid #eee;vertical-align:top;}
      .totals{margin-top:8px;width:280px;margin-left:auto;} .totals td{border:none;padding:2px 6px;}
      .grand{font-size:15px;font-weight:bold;border-top:1px solid #999;}
      .head{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #111;padding-bottom:10px;}
      .signrow{display:flex;gap:40px;margin-top:36px;} .sign{flex:1;text-align:center;font-size:11px;color:#444;}
      .signline{border-bottom:1px solid #999;height:34px;margin-bottom:4px;}
      .terms{margin-top:18px;font-size:10px;color:#666;border-top:1px solid #ddd;padding-top:6px;}
      </style><script>window.onload=function(){window.print();}</script></head><body>
      <div>
        ${headBlock}
        <div class="head">
          <div>
            <h1>${esc(st.company_name ?? st.name ?? 'Energia')}</h1>
            <div class="mut">${esc(st.address ?? '')}${st.phone ? ` · ${esc(st.phone)}` : ''}</div>
          </div>
          <div style="text-align:right">
            <h1>EXCHANGE</h1>
            <div><b>${esc(detail.exchange_no)}</b></div>
            ${inv ? `<div class="mut">Invoice ${esc(inv)}</div>` : ''}
            <div class="mut">${new Date(detail.created_at).toLocaleString()}</div>
          </div>
        </div>
        <h2>Customer</h2>
        <div>${esc(cName(detail.customer_id))}${(cust as any)?.phone ? ` · ${esc((cust as any).phone)}` : ''}</div>
        <div class="mut">Processed at ${esc(sName(detail.processing_store_id))}${detail.reason ? ` · Reason: ${esc(detail.reason)}` : ''}</div>
        ${focStamp}
        <h2>Returned Items</h2>
        <table><thead><tr><th>Item</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Total</th></tr></thead>
        <tbody>${rowsFor('returned') || '<tr><td colspan="4" class="mut">None</td></tr>'}</tbody></table>
        <h2>Replacement Items</h2>
        <table><thead><tr><th>Item</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Total</th></tr></thead>
        <tbody>${rowsFor('replacement') || '<tr><td colspan="4" class="mut">None</td></tr>'}</tbody></table>
        <table class="totals"><tbody>
          <tr><td>Returned value (credit)</td><td class="r">S$${Number(detail.returned_credit_total).toFixed(2)}</td></tr>
          <tr><td>Replacement total</td><td class="r">S$${Number(detail.replacement_total).toFixed(2)}</td></tr>
          ${Number(detail.topup_amount) > 0 ? `<tr class="grand"><td>Top-up paid</td><td class="r">S$${Number(detail.topup_amount).toFixed(2)}</td></tr>` : ''}
          ${Number(detail.nonrefundable_amount) > 0 ? `<tr class="grand"><td>Unused value (non-refundable)</td><td class="r">S$${Number(detail.nonrefundable_amount).toFixed(2)}</td></tr>` : ''}
        </tbody></table>
        <div class="signrow">
          <div class="sign"><div class="signline"></div>Customer Signature</div>
          <div class="sign"><div class="signline"></div>Staff Signature</div>
        </div>
        <div class="terms">Exchanged goods have been checked and collected. No further exchange is allowed on the returned items.</div>
      </div>
      </body></html>`;
    const w = window.open('', '_blank');
    if (!w) { alert('Please allow pop-ups to print.'); return; }
    w.document.write(html); w.document.close();
    // Audit: record that this exchange was printed.
    supabase.rpc('write_audit', {
      p_table: 'product_exchanges', p_record: detail.id, p_action: 'exchange_printed',
      p_old: null, p_new: { exchange_no: detail.exchange_no },
    }).then(() => {}, () => {});
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Exchanges</h2><p>Product-to-product exchanges within 5 days of purchase. Returned stock comes back to the processing store; replacements are deducted from it.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openWizard}><Plus size={16} /> New Exchange</button>
        </div>
      </div>

      <div className="card"><div className="table-wrap">
        {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : exchanges.length === 0 ? <div className="empty-state"><ArrowLeftRight size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No exchanges yet</p></div>
          : (
            <table>
              <thead><tr><th>Exchange</th><th>Date</th><th>Customer</th><th>Store</th><th style={{ textAlign: 'right' }}>Credit</th><th style={{ textAlign: 'right' }}>Replacement</th><th style={{ textAlign: 'right' }}>Top-up</th><th style={{ textAlign: 'right' }}>Non-ref.</th><th></th></tr></thead>
              <tbody>
                {exchanges.map(e => (
                  <tr key={e.id}>
                    <td><strong>{e.exchange_no}</strong>
                      {exchangeInvoiceNos[e.id] && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Invoice {exchangeInvoiceNos[e.id]}</div>}
                    </td>
                    <td style={{ fontSize: 12.5 }}>{new Date(e.created_at).toLocaleDateString()}</td>
                    <td>{cName(e.customer_id)}</td>
                    <td style={{ fontSize: 12.5 }}>{sName(e.processing_store_id)}</td>
                    <td style={{ textAlign: 'right' }}>{money(e.returned_credit_total)}</td>
                    <td style={{ textAlign: 'right' }}>{money(e.replacement_total)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{e.topup_amount > 0 ? money(e.topup_amount) : '—'}</td>
                    <td style={{ textAlign: 'right', color: e.nonrefundable_amount > 0 ? 'var(--danger)' : 'inherit' }}>{e.nonrefundable_amount > 0 ? money(e.nonrefundable_amount) : '—'}</td>
                    <td><button className="btn btn-secondary btn-sm" onClick={() => openDetail(e)}><Eye size={13} /></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
      </div></div>

      {/* New exchange wizard */}
      {wizard && (
        <Modal title="New Exchange" maxWidth={640} onClose={() => setWizard(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setWizard(false)}>Cancel</button><button className="btn btn-primary" onClick={openConfirm} disabled={busy}>{busy ? 'Processing…' : 'Complete Exchange'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}

            <div className="form-group">
              <label>Processing Store *</label>
              {isStaff ? <input value={sName(assignedStoreId ?? '') } disabled style={{ background: 'var(--surface-2)' }} />
                : <select value={store} onChange={e => setStore(e.target.value)}><option value="">— Select —</option>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}</select>}
            </div>

            <div className="form-group">
              <label>Original Invoice No. *</label>
              <div style={{ display: 'flex', gap: 8 }}>
                <input value={invSearch} onChange={e => setInvSearch(e.target.value)} placeholder="Enter invoice number" onKeyDown={e => e.key === 'Enter' && findInvoice()} />
                <button className="btn btn-secondary" onClick={findInvoice} type="button">Find</button>
              </div>
            </div>

            {eligMsg && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{eligMsg}</div></div>}

            {invoice && !eligMsg && (
              <>
                <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>Customer: <strong>{cName(invoice.customer_id)}</strong> · Paid {invoice.paid_at ? new Date(invoice.paid_at).toLocaleDateString() : '—'}</div>

                <div style={{ display: 'flex', gap: 6 }}>
                  {([['product', 'Product'], ['bundle', 'Whole bundle'], ['component', 'Bundle component']] as const).map(([v, lbl]) => (
                    <button key={v} type="button" className={`btn btn-sm ${mode === v ? 'btn-primary' : 'btn-secondary'}`}
                      onClick={() => { setMode(v); setReturnIds([]); setBundleLineId(''); setNewPromoId(''); setComponentPid(''); setBundleComps([]); }}>{lbl}</button>
                  ))}
                </div>

                {mode === 'product' && (
                <div className="form-group">
                  <label>Items to return (select the ones physically brought back &amp; unused)</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                    {productLines.length === 0 && <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No plain product lines on this invoice.</span>}
                    {productLines.map(i => {
                      const already = (i as any).exchanged_at;
                      const on = returnIds.includes(i.id);
                      return (
                        <label key={i.id} style={{ display: 'flex', alignItems: 'center', gap: 8, opacity: already ? 0.5 : 1, fontSize: 13 }}>
                          <input type="checkbox" disabled={!!already} checked={on} style={{ width: 'auto' }}
                            onChange={() => setReturnIds(prev => on ? prev.filter(x => x !== i.id) : [...prev, i.id])} />
                          <span>{pName(i.product_id ?? '')} × {i.quantity} {already ? '(already exchanged)' : ''}</span>
                        </label>
                      );
                    })}
                  </div>
                  {returnedType === 'MIXED' && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>Returned items must all be the same product type (own or third-party).</div>}
                </div>
                )}

                {(mode === 'bundle' || mode === 'component') && (
                  <div className="form-group">
                    <label>Bundle on this invoice</label>
                    <select value={bundleLineId} onChange={e => loadBundleComps(e.target.value)}>
                      <option value="">— Select bundle —</option>
                      {bundleLines.map(i => {
                        const already = (i as any).exchanged_at;
                        return <option key={i.id} value={i.id} disabled={!!already}>{promoName(i.promotion_id ?? '')} × {i.quantity}{already ? ' (already exchanged)' : ''}</option>;
                      })}
                    </select>
                    {bundleLines.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No bundles on this invoice.</span>}
                  </div>
                )}

                {mode === 'bundle' && bundleLineId && (
                  <>
                    <div className="form-group">
                      <label>Replacement bundle</label>
                      <select value={newPromoId} onChange={e => setNewPromoId(e.target.value)}>
                        <option value="">— Select replacement bundle —</option>
                        {promotions.map(p => <option key={p.id} value={p.id}>{p.name} — {money(Number(p.fixed_price))}</option>)}
                      </select>
                    </div>
                    <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Whole-bundle swap: every component of the old bundle returns to stock and every component of the new bundle is deducted. The exact credit, replacement total, and any top-up or non-refundable balance are computed and shown on the completed exchange.</div></div>
                  </>
                )}

                {mode === 'component' && bundleLineId && (
                  <div className="form-group">
                    <label>Component to exchange</label>
                    <div style={{ display: 'flex', gap: 6 }}>
                      <select value={componentPid} style={{ flex: 1 }} onChange={e => { setComponentPid(e.target.value); const comp = bundleComps.find(x => x.product_id === e.target.value); setComponentQty(comp?.quantity ?? 1); }}>
                        <option value="">— Select component —</option>
                        {bundleComps.map(comp => <option key={comp.product_id} value={comp.product_id}>{pName(comp.product_id)} (×{comp.quantity} in bundle)</option>)}
                      </select>
                      <input type="number" min={1} value={componentQty} style={{ width: 70 }} onChange={e => setComponentQty(+e.target.value)} />
                    </div>
                  </div>
                )}

                {(mode === 'product' || mode === 'component') && (
                <div className="form-group">
                  <label>Replacement products {mode === 'component' && componentPid ? '' : returnedType && returnedType !== 'MIXED' ? `(${returnedType === 'own' ? 'own' : 'third-party'} only)` : ''}</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    {repl.map((r, i) => (
                      <div key={i} style={{ display: 'flex', gap: 6 }}>
                        <select value={r.product_id} style={{ flex: 1 }}
                          onChange={e => setRepl(rs => rs.map((x, j) => j === i ? { ...x, product_id: e.target.value } : x))}>
                          <option value="">— Product —</option>
                          {(mode === 'component' ? products : replCandidates).filter(p => priceAt(effectiveStore, p.id) != null).map(p => (
                            <option key={p.id} value={p.id}>{p.name} — {money(priceAt(effectiveStore, p.id) ?? 0)} (stock {stockAt(effectiveStore, p.id)})</option>
                          ))}
                        </select>
                        <input type="number" min={1} value={r.quantity} style={{ width: 70 }}
                          onChange={e => setRepl(rs => rs.map((x, j) => j === i ? { ...x, quantity: +e.target.value } : x))} />
                        <button className="btn btn-secondary btn-sm btn-icon" type="button" onClick={() => setRepl(rs => rs.filter((_, j) => j !== i))}><Trash2 size={13} /></button>
                      </div>
                    ))}
                    <button className="btn btn-secondary btn-sm" type="button" style={{ alignSelf: 'flex-start' }} onClick={() => setRepl(rs => [...rs, { product_id: '', quantity: 1 }])}><Plus size={13} /> Add replacement</button>
                  </div>
                </div>
                )}

                {/* Valuation (product & component modes compute client-side; bundle is server-side) */}
                {mode !== 'bundle' && (
                <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 12, fontSize: 13 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Exchange credit (returned)</span><strong>{money(mode === 'component' ? (priceAt(effectiveStore, componentPid) ?? 0) * componentQty : creditTotal)}</strong></div>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Replacement total</span><strong>{money(replTotal)}</strong></div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px solid var(--border)', marginTop: 6, paddingTop: 6 }}>
                    {compTopup > 0 ? <><span>Top-up to collect</span><strong style={{ color: 'var(--primary)' }}>{money(compTopup)}</strong></>
                      : compNonref > 0 ? <><span>Unused value (non-refundable)</span><strong style={{ color: 'var(--danger)' }}>{money(compNonref)}</strong></>
                      : <><span>Even exchange</span><strong>{money(0)}</strong></>}
                  </div>
                </div>
                )}
                {mode === 'bundle' && (
                  <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>If the new bundle costs more, add the top-up payment below; the exact amount is validated on completion.</div>
                )}

                {(compTopup > 0 || mode === 'bundle') && (
                  <div className="form-group">
                    <label>Top-up payment {mode !== 'bundle' ? `(${money(compTopup)})` : ''} — add one or more methods</label>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {pays.map((p, i) => (
                        <div key={i} style={{ display: 'flex', gap: 6 }}>
                          <select value={p.payment_method_id} style={{ flex: 1 }} onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, payment_method_id: e.target.value } : x))}>
                            <option value="">— Method —</option>{methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                          </select>
                          <input type="number" min={0} step="0.01" value={p.amount} style={{ width: 90 }} onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, amount: +e.target.value } : x))} />
                          <input value={p.reference} placeholder="Ref" style={{ width: 80 }} onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, reference: e.target.value } : x))} />
                          <button className="btn btn-secondary btn-sm btn-icon" type="button" onClick={() => setPays(ps => ps.filter((_, j) => j !== i))}><Trash2 size={13} /></button>
                        </div>
                      ))}
                      <button className="btn btn-secondary btn-sm" type="button" style={{ alignSelf: 'flex-start' }} onClick={() => setPays(ps => [...ps, { payment_method_id: methods[0]?.id ?? '', amount: mode !== 'bundle' && +(compTopup - paySum).toFixed(2) > 0 ? +(compTopup - paySum).toFixed(2) : 0, reference: '' }])}><Plus size={13} /> Add payment</button>
                      {mode !== 'bundle' && <div style={{ fontSize: 12, color: Math.abs(paySum - compTopup) < 0.001 ? 'var(--success)' : 'var(--text-muted)' }}>Entered: {money(paySum)} / {money(compTopup)}</div>}
                    </div>
                  </div>
                )}

                <div className="form-grid-2">
                  <div className="form-group"><label>Reason *</label><input value={reason} onChange={e => setReason(e.target.value)} placeholder="Required" /></div>
                  <div className="form-group"><label>Notes</label><input value={notes} onChange={e => setNotes(e.target.value)} placeholder="Optional" /></div>
                </div>
              </>
            )}
          </div>
        </Modal>
      )}

      {/* Confirmation: product name + SKU, and staff attests the item is unused */}
      {confirming && (
        <Modal title="Confirm Exchange" maxWidth={460} onClose={() => setConfirming(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setConfirming(false)}>Back</button>
            <button className="btn btn-primary" onClick={submit}
              disabled={busy || attestName.trim().toLowerCase() !== (profile?.full_name ?? '').trim().toLowerCase()}>
              {busy ? 'Processing…' : 'Confirm & Complete'}
            </button>
          </>}>
          <div className="form-grid">
            <div>
              <label>Returning — confirm physically received and unused:</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 6 }}>
                {mode === 'product' && returnedItems.map(i => (
                  <div key={i.id} style={{ fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <strong>{pName(i.product_id ?? '')}</strong> × {i.quantity}
                    <span style={{ color: 'var(--text-muted)', marginLeft: 6 }}>SKU: {pSku(i.product_id ?? '') || '—'}</span>
                  </div>
                ))}
                {mode === 'bundle' && (
                  <div style={{ fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <strong>Whole bundle: {promoName(bundleLines.find(b => b.id === bundleLineId)?.promotion_id ?? '')}</strong>
                    <div style={{ color: 'var(--text-muted)', marginTop: 2 }}>{bundleComps.map(cp => `${pName(cp.product_id)} ×${cp.quantity}`).join(', ')}</div>
                    <div style={{ marginTop: 2 }}>→ replacing with: <strong>{promoName(newPromoId)}</strong></div>
                  </div>
                )}
                {mode === 'component' && componentPid && (
                  <div style={{ fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <strong>{pName(componentPid)}</strong> × {componentQty}
                    <span style={{ color: 'var(--text-muted)', marginLeft: 6 }}>SKU: {pSku(componentPid) || '—'}</span>
                    <div style={{ color: 'var(--text-muted)', marginTop: 2 }}>(component of {promoName(bundleLines.find(b => b.id === bundleLineId)?.promotion_id ?? '')})</div>
                  </div>
                )}
              </div>
            </div>
            <div className="form-group">
              <label>Type your name to confirm you are handling this and the product is unused</label>
              <input value={attestName} onChange={e => setAttestName(e.target.value)} placeholder={profile?.full_name ?? 'Your name'} autoFocus />
              {attestName && attestName.trim().toLowerCase() !== (profile?.full_name ?? '').trim().toLowerCase() &&
                <span style={{ fontSize: 11.5, color: 'var(--danger)', marginTop: 4, display: 'block' }}>Name must match your account name ({profile?.full_name}).</span>}
            </div>
          </div>
        </Modal>
      )}

      {/* Detail */}
      {detail && (
        <Modal title={`Exchange ${detail.exchange_no}${exchangeInvoiceNos[detail.id] ? ` — Invoice ${exchangeInvoiceNos[detail.id]}` : ''}`} maxWidth={520} onClose={() => setDetail(null)}
          footer={<><button className="btn btn-secondary" onClick={printExchange}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{cName(detail.customer_id)} · {sName(detail.processing_store_id)} · {new Date(detail.created_at).toLocaleString()}</div>
            <div>
              <label>Returned</label>
              {detailItems.filter(i => i.direction === 'returned').map(i => <div key={i.id} style={{ fontSize: 13 }}>{pName(i.product_id)} × {i.quantity} @ {money(i.unit_price)} = {money(i.line_total)}</div>)}
            </div>
            <div>
              <label>Replacement</label>
              {detailItems.filter(i => i.direction === 'replacement').map(i => <div key={i.id} style={{ fontSize: 13 }}>{pName(i.product_id)} × {i.quantity} @ {money(i.unit_price)} = {money(i.line_total)}</div>)}
            </div>
            <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 12, fontSize: 13 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Credit</span><span>{money(detail.returned_credit_total)}</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Replacement</span><span>{money(detail.replacement_total)}</span></div>
              {detail.topup_amount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Top-up paid</span><strong>{money(detail.topup_amount)}</strong></div>}
              {detail.nonrefundable_amount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--danger)' }}><span>Unused value (non-refundable)</span><strong>{money(detail.nonrefundable_amount)}</strong></div>}
            </div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>This exchange is locked. No further exchange is allowed on the returned items.</div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default ExchangesPage;
