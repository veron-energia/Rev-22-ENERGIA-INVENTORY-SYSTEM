import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase, fetchCustomersByIds, mergeCustomers} from '../lib/supabase';
import { singaporeToday } from '../lib/invoices/business';
import { InstalmentPortionFields, INSTALMENT_METHOD, emptyPortion, portionProblem,
         type InstalmentPortion } from '../components/invoices/InstalmentPortionFields';
import { useAuth } from '../context/AuthContext';
import { Invoice, InvoiceItem, Product, Store, Customer, PaymentMethod, ProductExchange, ProductExchangeItem, Promotion, isManagerOrAbove } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Plus, ArrowLeftRight, Trash2, Eye, Printer } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';
import { SearchSelect } from '../components/SearchSelect';

const money = (n: number) => `S$${Number(n).toFixed(2)}`;

const ExchangesPage: React.FC = () => {
  const { profile } = useAuth();
  const [exchanges, setExchanges] = useState<ProductExchange[]>([]);
  const [exchangeInvoiceNos, setExchangeInvoiceNos] = useState<Record<string, string>>({});
  const [products, setProducts] = useState<Product[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  /** The customer on the invoice being exchanged, read by id rather than
   *  hoped for in the page's bounded customer list. */
  const [invoiceCustomer, setInvoiceCustomer] = useState<any | null>(null);
  const [customerUnavailable, setCustomerUnavailable] = useState(false);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [prices, setPrices] = useState<{ store_id: string; product_id: string; selling_price: number; is_active: boolean }[]>([]);
  const [storeInv, setStoreInv] = useState<{ store_id: string; product_id: string; current_qty: number }[]>([]);
  const [loading, setLoading] = useState(true);
  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  // Staff may be assigned to several stores and choose among them.
  const [myStores, setMyStores] = useState<{ store_id: string; store_name: string; is_default: boolean }[]>([]);
  const [promotions, setPromotions] = useState<Promotion[]>([]);

  const isStaff = profile?.role === 'staff';

  const load = useCallback(async () => {
    setLoading(true);
    const [ex, exinv, pr, st, cu, pm, spp, si, mine, myStoreList, promo] = await Promise.all([
      supabase.from('product_exchanges').select('*').order('created_at', { ascending: false }),
      supabase.from('invoices').select('id, invoice_no, exchange_id').eq('is_exchange', true),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('*').is('deleted_at', null),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('store_product_prices').select('store_id,product_id,selling_price,is_active').eq('is_active', true),
      supabase.from('store_inventory').select('store_id,product_id,current_qty'),
      supabase.rpc('my_assigned_store_id'),
      supabase.rpc('my_assigned_stores'),
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
    setMyStores((myStoreList.data as any[]) ?? []);
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
  const [pays, setPays] = useState<{ payment_method_id: string; amount: number; reference: string; instalment?: InstalmentPortion }[]>([]);
  const [reason, setReason] = useState('');
  const [notes, setNotes] = useState('');
  // ---- who handled THIS exchange, kept apart from who served the original ----
  const [exStaff, setExStaff] = useState<string[]>([]);
  const [exAffiliate, setExAffiliate] = useState<'' | 'none' | string>('');
  const [exRaisedBy, setExRaisedBy] = useState('');
  const [exDate, setExDate] = useState('');
  /** The original sale's own attribution, shown beside the exchange as
   *  reference. Never used as a default for the exchange's own fields. */
  const [originalContext, setOriginalContext] = useState<any | null>(null);
  /** Additional charge / received / outstanding / terms for the open exchange. */
  const [detailPosition, setDetailPosition] = useState<any | null>(null);
  const [profilesList, setProfilesList] = useState<any[]>([]);
  const [affiliateOptions, setAffiliateOptions] = useState<{ value: string; label: string }[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [attestName, setAttestName] = useState('');

  // With several assigned stores nothing is preselected — the store decides
  // which stock the replacement comes out of.
  const staffMustChooseStore = isStaff && myStores.length > 1;
  const effectiveStore = isStaff
    ? (staffMustChooseStore ? store : (store || assignedStoreId || myStores[0]?.store_id || ''))
    : store;

  const resetWizard = () => {
    setStore(isStaff && myStores.length === 1
      ? (myStores[0]?.store_id ?? assignedStoreId ?? '') : ''); setInvSearch(''); setInvoice(null); setInvItems([]);
    setEligMsg(null); setReturnIds([]); setRepl([{ product_id: '', quantity: 1 }]); setPays([]); setReason(''); setNotes(''); setErr(null);
    setMode('product'); setBundleLineId(''); setNewPromoId(''); setComponentPid(''); setComponentQty(1); setBundleComps([]);
  };
  const openWizard = () => { resetWizard(); setWizard(true); };

  // Everyone who could serve or raise an exchange, and every eligible
  // affiliate. Loaded once; the server checks both again on save.
  useEffect(() => {
    supabase.from('profiles').select('id, full_name, role, is_active')
      .is('deleted_at', null).eq('is_active', true).order('full_name')
      .then(({ data }) => setProfilesList((data as any[]) ?? []));
    supabase.from('customer_affiliates')
      .select('id, customer_id, status, manually_suspended')
      .is('deleted_at', null)
      .then(async ({ data }) => {
        const rows = ((data as any[]) ?? []).filter(r => !r.manually_suspended);
        const people = await fetchCustomersByIds(rows.map(r => r.customer_id));
        const byId = new Map(people.map((c: any) => [c.id, c]));
        setAffiliateOptions(rows.map(r => ({
          value: r.id,
          label: byId.get(r.customer_id)?.full_name ?? 'Affiliate',
          search: `${byId.get(r.customer_id)?.full_name ?? ''} ${byId.get(r.customer_id)?.phone ?? ''}`,
        }) as any));
      });
  }, []);

  // Staff eligible for the store processing this exchange. Owners and managers
  // reach every store; staff must be assigned to it.
  const [storeStaff, setStoreStaff] = useState<any[]>([]);
  useEffect(() => {
    if (!effectiveStore) { setStoreStaff([]); return; }
    supabase.rpc('store_commission_staff', { p_store_id: effectiveStore })
      .then(({ data }) => setStoreStaff((data as any[]) ?? []));
  }, [effectiveStore]);
  const eligibleExchangeStaff = useMemo(() => {
    const assigned = storeStaff.map(s2 => ({ id: s2.staff_id, full_name: s2.staff_name }));
    const seniors = profilesList
      .filter(p => ['owner', 'manager'].includes(p.role))
      .map(p => ({ id: p.id, full_name: `${p.full_name} (${p.role})` }));
    return [...assigned, ...seniors];
  }, [storeStaff, profilesList]);
  const raisedByOptions = useMemo(() => profilesList
    .filter(p => ['owner', 'admin', 'manager', 'staff'].includes(p.role))
    .map(p => ({ value: p.id, label: p.full_name })), [profilesList]);

  const findInvoice = async () => {
    // Looking up a different invoice must not leave anything from the last one
    // on screen: its items, its returns, its staff, its affiliate or its
    // customer.
    setErr(null); setInvoice(null); setInvItems([]); setEligMsg(null); setReturnIds([]);
    setInvoiceCustomer(null); setCustomerUnavailable(false); setOriginalContext(null);
    setBundleLineId(''); setBundleComps([]); setComponentPid(''); setComponentQty(1);
    setExStaff([]); setExAffiliate(''); setPays([]);
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

    // The page's customer list is one page of rows and excludes deleted ones,
    // so an invoice belonging to any customer outside it showed "Customer: —"
    // even though the invoice named them perfectly well. Fetch this invoice's
    // own customer by id, which also reaches historical records.
    const cid = (inv as Invoice).customer_id;
    if (!cid) { setCustomerUnavailable(true); return; }
    supabase.rpc('exchange_original_context', { p_invoice_id: (inv as Invoice).id })
      .then(({ data }) => setOriginalContext(data ?? null));
    setExDate(singaporeToday());
    const found = await fetchCustomersByIds([cid]);
    if (found.length > 0) {
      setInvoiceCustomer(found[0]);
      setCustomers(cur => mergeCustomers(cur, found));
    } else {
      // Never guess from a similar name or number: say it plainly instead.
      setCustomerUnavailable(true);
    }
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
  // Money actually received now, kept apart from what an arrangement merely
  // covers. An in-house promise is not a receipt.
  const receivedNow = pays.reduce((a, p) => a + (Number(p.amount) || 0), 0);
  const instalmentCovered = pays.reduce((a, p) =>
    a + (p.payment_method_id === INSTALMENT_METHOD ? (Number(p.instalment?.covered_amount) || 0) : 0), 0);
  const outstandingNow = Math.max(0, +(compTopup - receivedNow).toFixed(2));
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
      if (compTopup > 0 && receivedNow - compTopup > 0.001) return `Payments (${money(receivedNow)}) exceed the additional charge of ${money(compTopup)}.`;
      if (compTopup > 0 && receivedNow + instalmentCovered - compTopup < -0.001) {
        return `${money(compTopup - receivedNow - instalmentCovered)} of the additional charge is unaccounted for — take it now or cover it with an instalment.`;
      }
      { const bad = pays.map(p => p.payment_method_id === INSTALMENT_METHOD ? portionProblem(p.instalment, p.amount || 0) : null).find(Boolean);
        if (bad) return bad; }
    } else if (mode === 'bundle') {
      if (!bundleLineId) return 'Select the bundle being returned.';
      if (!newPromoId) return 'Select the replacement bundle.';
    } else if (mode === 'component') {
      if (!bundleLineId) return 'Select the bundle.';
      if (!componentPid) return 'Select the component to exchange.';
      if (componentQty <= 0) return 'Component quantity must be greater than zero.';
      if (replLines.length === 0) return 'Add at least one replacement product.';
      if (compTopup > 0 && receivedNow - compTopup > 0.001) return `Payments (${money(receivedNow)}) exceed the additional charge of ${money(compTopup)}.`;
      if (compTopup > 0 && receivedNow + instalmentCovered - compTopup < -0.001) {
        return `${money(compTopup - receivedNow - instalmentCovered)} of the additional charge is unaccounted for — take it now or cover it with an instalment.`;
      }
      { const bad = pays.map(p => p.payment_method_id === INSTALMENT_METHOD ? portionProblem(p.instalment, p.amount || 0) : null).find(Boolean);
        if (bad) return bad; }
    }
    return null;
  };

  const openConfirm = () => {
    if (exStaff.length === 0) {
      setErr('Choose the staff who handled this exchange. The original sale\u2019s staff are not carried over.');
      return;
    }
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
    // An instalment line carries the arrangement; any money taken under it goes
    // in as a receipt through the REAL method, never as "Instalment".
    const active = (compTopup > 0 || mode === 'bundle') ? pays : [];
    const payPayload = active
      .filter(p => Number(p.amount) > 0 && (p.payment_method_id === INSTALMENT_METHOD
        ? !!p.instalment?.method_id : !!p.payment_method_id))
      .map(p => ({
        payment_method_id: p.payment_method_id === INSTALMENT_METHOD ? p.instalment!.method_id : p.payment_method_id,
        amount: p.amount, reference: p.reference,
      }));
    const arrangementPayload = active
      .filter(p => p.payment_method_id === INSTALMENT_METHOD && p.instalment)
      .map((p, i) => ({
        key: `exchange-plan-${i}`,
        category: p.instalment!.category, method_id: p.instalment!.method_id,
        months: Number(p.instalment!.months), covered_amount: p.instalment!.covered_amount,
      }));
    // One call: the exchange and who handled it are written together, so an
    // exchange can never exist without its own attribution. The three original
    // creators are called unchanged underneath.
    const common = {
      original_invoice_id: invoice.id, processing_store_id: effectiveStore,
      payments: payPayload,
      arrangements: arrangementPayload,
      reason: reason.trim() || null, notes: notes.trim() || null,
      served_by: exStaff,
      // "None" is a decision, not an absence: it is sent explicitly so the
      // server cannot fall back to the customer's referrer.
      affiliate: exAffiliate === 'none' ? { mode: 'none' }
               : exAffiliate ? { mode: 'set', id: exAffiliate }
               : { mode: 'inherit' },
      raised_by: exRaisedBy || null,
      exchange_date: exDate || null,
    };
    const payload = mode === 'product'
      ? { ...common,
          returned: returnedItems.map(i => ({ invoice_item_id: i.id, quantity: i.quantity })),
          replacement: replLines }
      : mode === 'bundle'
      ? { ...common, original_invoice_item_id: bundleLineId, new_promotion_id: newPromoId }
      : { ...common, original_invoice_item_id: bundleLineId,
          component_product_id: componentPid, component_qty: componentQty,
          replacement: replLines };
    const { data, error } = await supabase.rpc('create_exchange_with_details', {
      p_kind: mode === 'product' ? 'product' : mode === 'bundle' ? 'bundle' : 'bundle_component',
      p_payload: payload,
    });
    setBusy(false);
    if (error) { setErr(error.message); setConfirming(false); return; }
    setConfirming(false); setWizard(false); load();
    alert(`Exchange ${(data as any)?.exchange_no ?? ''} completed.`);
  };

  // ---- Detail view ----
  const [detail, setDetail] = useState<ProductExchange | null>(null);
  const [detailItems, setDetailItems] = useState<ProductExchangeItem[]>([]);
  const openDetail = async (e: ProductExchange) => {
    setDetail(e); setDetailItems([]); setDetailPosition(null);
    // What is charged, what arrived and what is still owed — read from the
    // server rather than inferred from the charge alone.
    supabase.rpc('exchange_payment_position', { p_exchange_id: e.id })
      .then(({ data }) => setDetailPosition(data ?? null));
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
          ${Number(detail.topup_amount) > 0 ? `<tr class="grand"><td>Additional charge</td><td class="r">S$${Number(detail.topup_amount).toFixed(2)}</td></tr>` : ''}
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
          <ExcelExportButton
            rows={exchanges} filename="exchanges" sheetName="Exchanges"
            dateOf={(r: any) => r.created_at} dateLabel="Exchange date"
            columns={[
              { header: 'Date', value: (e: any) => new Date(e.created_at).toLocaleDateString('en-GB') },
              { header: 'Exchange No', value: (e: any) => e.exchange_no ?? '' },
              { header: 'Customer', value: (e: any) => cName(e.customer_id) },
              { header: 'Status', value: (e: any) => e.status ?? '' },
              { header: 'Returned credit', value: (e: any) => Number(e.returned_credit_total ?? 0) },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openWizard}><Plus size={16} /> New Exchange</button>
        </div>
      </div>

      <div className="card"><div className="table-wrap">
        {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : exchanges.length === 0 ? <div className="empty-state"><ArrowLeftRight size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No exchanges yet</p></div>
          : (
            <table>
              <thead><tr><th>Exchange</th><th>Date</th><th>Customer</th><th>Store</th><th style={{ textAlign: 'right' }}>Credit</th><th style={{ textAlign: 'right' }}>Replacement</th><th style={{ textAlign: 'right' }}>Additional</th><th style={{ textAlign: 'right' }}>Non-ref.</th><th></th></tr></thead>
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
              {isStaff && myStores.length <= 1 ? <input value={sName(assignedStoreId ?? myStores[0]?.store_id ?? '')} disabled style={{ background: 'var(--surface-2)' }} />
                : <select value={effectiveStore} onChange={e => setStore(e.target.value)}>
                    {(!isStaff || staffMustChooseStore) && <option value="">— Select —</option>}
                    {(isStaff ? myStores.map(m => ({ id: m.store_id, name: m.store_name })) : stores)
                      .map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>}
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
                <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>Customer:{' '}
                  {invoiceCustomer
                    ? <strong>{invoiceCustomer.full_name}{invoiceCustomer.phone ? ` · ${invoiceCustomer.phone}` : ''}</strong>
                    : customerUnavailable
                      ? <em title="The invoice keeps its link to this customer; only the customer record could not be read.">
                          Customer record unavailable
                        </em>
                      : <span>Loading…</span>}
                  {' '}· Paid {invoice.paid_at ? new Date(invoice.paid_at).toLocaleDateString() : '—'}</div>

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
                        <SearchSelect style={{ flex: 1 }} placeholder="Search product name or SKU…"
                          value={r.product_id}
                          onChange={v => setRepl(rs => rs.map((x, j) => j === i ? { ...x, product_id: v } : x))}
                          options={(mode === 'component' ? products : replCandidates)
                            .filter(p => priceAt(effectiveStore, p.id) != null)
                            .map((p: any) => ({
                              value: p.id,
                              label: `${p.name} — ${money(priceAt(effectiveStore, p.id) ?? 0)} (stock ${stockAt(effectiveStore, p.id)})`,
                              sublabel: p.sku,
                              search: `${p.name} ${p.sku ?? ''}`,
                            }))} />
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
                    {compTopup > 0 ? <><span>Additional charge</span><strong style={{ color: 'var(--primary)' }}>{money(compTopup)}</strong></>
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
                    <label>Additional payment {mode !== 'bundle' ? `(${money(compTopup)} due)` : ''} — one or more methods, or an instalment</label>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {pays.map((p, i) => (
                        <div key={i} style={{ display: 'flex', gap: 6 }}>
                          <select value={p.payment_method_id} style={{ flex: 1 }} onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, payment_method_id: e.target.value } : x))}>
                            <option value="">— Method —</option>
                            <option value={INSTALMENT_METHOD}>Instalment — pay over time</option>
                            {methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                          </select>
                          <input type="number" min={0} step="0.01" value={p.amount} style={{ width: 90 }}
                            placeholder={p.payment_method_id === INSTALMENT_METHOD ? 'Now' : 'Amount'}
                            onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, amount: +e.target.value } : x))} />
                          <input value={p.reference} placeholder="Ref" style={{ width: 80 }} onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, reference: e.target.value } : x))} />
                          <button className="btn btn-secondary btn-sm btn-icon" type="button" onClick={() => setPays(ps => ps.filter((_, j) => j !== i))}><Trash2 size={13} /></button>
                        </div>
                      ))}
                      {pays.map((p, i) => p.payment_method_id === INSTALMENT_METHOD ? (
                        <InstalmentPortionFields key={`inst-${i}`}
                          value={p.instalment ?? emptyPortion}
                          onChange={v => setPays(ps => ps.map((x, j) => j === i ? { ...x, instalment: v } : x))}
                          methods={methods}
                          receivedNow={p.amount || 0}
                          onReceivedNow={n => setPays(ps => ps.map((x, j) => j === i ? { ...x, amount: n } : x))}
                          error={portionProblem(p.instalment, p.amount || 0)} />
                      ) : null)}
                      <button className="btn btn-secondary btn-sm" type="button" style={{ alignSelf: 'flex-start' }} onClick={() => setPays(ps => [...ps, { payment_method_id: methods[0]?.id ?? '', amount: mode !== 'bundle' && +(compTopup - paySum).toFixed(2) > 0 ? +(compTopup - paySum).toFixed(2) : 0, reference: '' }])}><Plus size={13} /> Add payment</button>
                      {mode !== 'bundle' && (
                        <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.7 }}>
                          <div>Additional charge: <strong>{money(compTopup)}</strong></div>
                          <div>Received now: <strong>{money(receivedNow)}</strong></div>
                          <div>Covered by instalment: <strong>{money(instalmentCovered)}</strong></div>
                          <div>Outstanding: <strong style={{ color: outstandingNow > 0 ? 'var(--accent)' : 'var(--success)' }}>{money(outstandingNow)}</strong></div>
                          {outstandingNow > 0 && instalmentCovered === 0 && (
                            <div className="muted">The balance stays owed on the replacement invoice.</div>)}
                        </div>
                      )}
                    </div>
                  </div>
                )}

                <div className="form-grid-2">
                  <div className="form-group"><label>Reason *</label><input value={reason} onChange={e => setReason(e.target.value)} placeholder="Required" /></div>
                  <div className="form-group"><label>Notes</label><input value={notes} onChange={e => setNotes(e.target.value)} placeholder="Optional" /></div>

                  {/* ---- who handled THIS exchange -----------------------------
                      Deliberately empty to begin with. The original sale's staff
                      are shown below as context and are never copied in: an
                      exchange done today by different people must say so. */}
                  <div className="form-group exchange-attribution">
                    <label id="ex-staff-label">Served by *</label>
                    <div className="exchange-staff" role="group" aria-labelledby="ex-staff-label">
                      {eligibleExchangeStaff.length === 0 && (
                        <span className="muted">No staff are assigned to this store.</span>)}
                      {eligibleExchangeStaff.map(p => (
                        <label key={p.id} className={exStaff.includes(p.id) ? 'chosen' : ''}>
                          <input type="checkbox" checked={exStaff.includes(p.id)}
                            onChange={e => setExStaff(cur => e.target.checked
                              ? [...cur, p.id] : cur.filter(x => x !== p.id))} />
                          {p.full_name}
                        </label>
                      ))}
                    </div>
                    <small>Who served this exchange, not the original sale.</small>
                  </div>

                  <div className="form-group">
                    <label>Referrer / affiliate</label>
                    <SearchSelect value={exAffiliate}
                      onChange={v => setExAffiliate(v as any)}
                      placeholder="Search affiliate…"
                      options={[
                        { value: 'none', label: 'None — no affiliate for this exchange' },
                        ...affiliateOptions,
                      ]} />
                    <small>
                      {originalContext?.affiliate
                        ? `Original sale: ${originalContext.affiliate}${originalContext.affiliate_still_eligible === false ? ' (no longer eligible)' : ''}.`
                        : 'The original sale had no affiliate.'}
                      {' '}Choosing None records None; it does not fall back to the customer’s referrer.
                    </small>
                  </div>

                  <div className="form-group">
                    <label>Raised by</label>
                    <SearchSelect value={exRaisedBy} onChange={v => setExRaisedBy(v)}
                      placeholder="Who is issuing this exchange"
                      options={raisedByOptions} />
                    <small>Who issues the document. Kept separate from Served by — it earns no commission.</small>
                  </div>

                  <div className="form-group">
                    <label>Exchange date</label>
                    <input type="date" value={exDate} max={singaporeToday()}
                      onChange={e => setExDate(e.target.value)} />
                    <small>Defaults to today in Singapore. The original invoice’s date is not changed.</small>
                  </div>

                  {originalContext && (
                    <div className="form-group exchange-original">
                      <label>Original sale</label>
                      <div>
                        <strong>{originalContext.invoice_no}</strong> · {originalContext.invoice_date}
                        <div>Customer: {originalContext.customer ?? 'Customer record unavailable'}</div>
                        <div>Served by: {(originalContext.served_by ?? []).length > 0
                          ? (originalContext.served_by as any[]).map((x: any) => x.name).join(', ')
                          : '—'}</div>
                        <div>Affiliate: {originalContext.affiliate ?? '—'}</div>
                      </div>
                      <small>Shown for reference. This exchange keeps its own attribution.</small>
                    </div>
                  )}
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
              {detail.topup_amount > 0 && (<>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>Additional charge</span><strong>{money(detail.topup_amount)}</strong></div>
                {detailPosition && (<>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span>Received</span><strong>{money(detailPosition.received)}</strong></div>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span>Outstanding</span>
                    <strong style={{ color: Number(detailPosition.outstanding) > 0 ? 'var(--accent)' : 'var(--success)' }}>
                      {money(detailPosition.outstanding)}</strong></div>
                  {(detailPosition.arrangements ?? []).map((a: any) => (
                    <div key={a.arrangement_id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: 'var(--text-secondary)' }}>
                      <span>{a.category === 'in_house' ? 'In-house' : 'Provider-funded'} instalment · {a.months} months · {a.method}</span>
                      <span>{money(a.covered_amount)} covered · {money(a.remaining)} left</span>
                    </div>))}
                </>)}
              </>)}
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
