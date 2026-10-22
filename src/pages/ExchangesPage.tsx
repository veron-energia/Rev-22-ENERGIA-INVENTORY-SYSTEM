import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react';
import { supabase, fetchCustomersByIds, mergeCustomers} from '../lib/supabase';
import { singaporeToday } from '../lib/invoices/business';
import { exchangePaymentMethods, bundleLineBlock, componentsExchanged, exchangePaymentProblem,
         exchangePaymentRowProblem, bundleQuoteFromRpc, affiliateHint, type BundleQuote,
         creditPreviewFromRpc, previewLine, componentCredit, creditBasisText,
         exchangeDay, displayDay, instalmentLabelFrom, type CreditPreview, type CreditFigures,
         saleDay, exchangeDateFloor, exchangeDateProblem, exchangeDateHint,
         itemsCredit, itemPicksProblem, itemsProductType, type ItemPick, exchangeServerWords } from '../lib/exchanges/rules.mjs';
import { printA5Document, esc as printEsc, type PrintTotal } from '../lib/printDoc';
import { promotionOnSale } from '../lib/promotions/status.mjs';
import { InstalmentPortionFields, INSTALMENT_METHOD, emptyPortion, portionProblem,
         type InstalmentPortion } from '../components/invoices/InstalmentPortionFields';
import { useAuth } from '../context/AuthContext';
import { Invoice, InvoiceItem, Product, Store, Customer, PaymentMethod, ProductExchange, ProductExchangeItem, Promotion } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Plus, ArrowLeftRight, Trash2, Eye, Printer, FileText } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';
import { SearchSelect } from '../components/SearchSelect';

const money = (n: number) => `S$${Number(n).toFixed(2)}`;

const ExchangesPage: React.FC = () => {
  const { profile } = useAuth();
  const [exchanges, setExchanges] = useState<ProductExchange[]>([]);
  const [exchangeInvoiceNos, setExchangeInvoiceNos] = useState<Record<string, string>>({});
  /** Each exchange's replacement invoice id, for its Open invoice button (455). */
  const [exchangeInvoiceIds, setExchangeInvoiceIds] = useState<Record<string, string>>({});
  /** The instalment label each replacement invoice records (424). */
  const [exchangeInstalments, setExchangeInstalments] = useState<Record<string, { method_id: string; months: number }>>({});
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
    const [ex, exinv, pr, st, pm, spp, si, mine, myStoreList, promo] = await Promise.all([
      supabase.from('product_exchanges').select('*').order('created_at', { ascending: false }),
      supabase.from('invoices').select('id, invoice_no, exchange_id, instalment_method_id, instalment_months').eq('is_exchange', true),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      // The customers table is deliberately absent. It was read whole here, a
      // thousand rows of every column on each page open, to supply names that
      // the by-id lookup below already supplies — and that the thousand-row cap
      // could not have guaranteed in any case.
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('store_product_prices').select('store_id,product_id,selling_price,is_active').eq('is_active', true),
      supabase.from('store_inventory').select('store_id,product_id,current_qty'),
      supabase.rpc('my_assigned_store_id'),
      supabase.rpc('my_assigned_stores'),
      supabase.from('promotions').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setExchanges((ex.data as ProductExchange[]) ?? []);
    const exMap: Record<string, string> = {};
    const idMap: Record<string, string> = {};
    const instMap: Record<string, { method_id: string; months: number }> = {};
    for (const r of ((exinv.data as any[]) ?? [])) {
      if (!r.exchange_id) continue;
      exMap[r.exchange_id] = r.invoice_no;
      idMap[r.exchange_id] = r.id;
      if (r.instalment_method_id && r.instalment_months) {
        instMap[r.exchange_id] = { method_id: r.instalment_method_id, months: Number(r.instalment_months) };
      }
    }
    setExchangeInvoiceNos(exMap);
    setExchangeInvoiceIds(idMap);
    setExchangeInstalments(instMap);
    setProducts((pr.data as Product[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    // Exactly the customers these exchanges name, by id, which is correct at
    // any table size and reaches historical records the live list excludes.
    // Awaited rather than left running: the rows are rendered once, with their
    // names, instead of appearing as dashes that fill in a moment later.
    const named = await fetchCustomersByIds(((ex.data as any[]) ?? []).map(x => x.customer_id));
    setCustomers(cur => mergeCustomers(cur, named));
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
  // 455 (the Owner, 22 Oct 2026, "Both kinds, any mix"): Items returns plain
  // product lines and items of bundles together, in one exchange; the whole
  // bundle stays its own mode.
  const [mode, setMode] = useState<'items' | 'bundle'>('items');
  const [bundleLineId, setBundleLineId] = useState('');      // whole bundle: the bundle invoice_item id
  const [newPromoId, setNewPromoId] = useState('');          // replacement bundle B
  /** The items of bundles ticked to return, each with how many of it. */
  const [picks, setPicks] = useState<ItemPick[]>([]);
  /** What each bundle line of the invoice holds (bundle_line_components). */
  const [lineComps, setLineComps] = useState<Record<string, { product_id: string; quantity: number }[]>>({});
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

  // An exchange's additional payment is never wallet credit: the exchange
  // copies its payments into the replacement invoice and takes no credit, so a
  // wallet "payment" would mark it paid with nothing taken (408 refuses it too).
  const payMethods = useMemo(() => exchangePaymentMethods(methods), [methods]);

  // ---- Whole-bundle preview (408): the server's own figures, before Confirm ----
  // exchange_bundle_preview is the same check the exchange itself makes, so a
  // swap it refuses is shown as refused here, with the reason.
  const [bundleQuote, setBundleQuote] = useState<BundleQuote | null>(null);
  const [bundleQuoteState, setBundleQuoteState] = useState<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  const quoteSeq = useRef(0);
  useEffect(() => {
    const seq = ++quoteSeq.current;
    if (mode !== 'bundle' || !invoice || !effectiveStore || !bundleLineId || !newPromoId) {
      setBundleQuote(null); setBundleQuoteState('idle'); return;
    }
    setBundleQuote(null); setBundleQuoteState('loading');
    supabase.rpc('exchange_bundle_preview', {
      p_original_invoice_id: invoice.id, p_processing_store_id: effectiveStore,
      p_original_invoice_item_id: bundleLineId, p_new_promotion_id: newPromoId,
    }).then(({ data, error }) => {
      if (seq !== quoteSeq.current) return;   // a later choice has been made
      const q = error ? null : bundleQuoteFromRpc(data);
      setBundleQuote(q); setBundleQuoteState(q ? 'ready' : 'failed');
    });
  }, [mode, invoice, effectiveStore, bundleLineId, newPromoId]);

  // ---- What the returned items count for (424): the server's own figures ----
  // exchange_credit_preview works out, for each line, today's price, what the
  // customer paid and the lower of the two, which is the credit the exchange
  // itself gives. Without it nothing can be valued, so Confirm is refused.
  const [creditPreview, setCreditPreview] = useState<CreditPreview | null>(null);
  const [creditPreviewState, setCreditPreviewState] = useState<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  const creditSeq = useRef(0);
  useEffect(() => {
    const seq = ++creditSeq.current;
    if (!invoice || !effectiveStore || eligMsg) {
      setCreditPreview(null); setCreditPreviewState('idle'); return;
    }
    setCreditPreview(null); setCreditPreviewState('loading');
    supabase.rpc('exchange_credit_preview', {
      p_original_invoice_id: invoice.id, p_processing_store_id: effectiveStore,
    }).then(({ data, error }) => {
      if (seq !== creditSeq.current) return;   // another invoice or store since
      const p = error ? null : creditPreviewFromRpc(data);
      setCreditPreview(p); setCreditPreviewState(p ? 'ready' : 'failed');
    });
  }, [invoice, effectiveStore, eligMsg]);

  // Everything one exchange typed is cleared before the next: a second
  // exchange in the same session must not carry the last one's staff,
  // affiliate, issuer, date or customer.
  const resetWizard = () => {
    setStore(isStaff && myStores.length === 1
      ? (myStores[0]?.store_id ?? assignedStoreId ?? '') : ''); setInvSearch(''); setInvoice(null); setInvItems([]);
    setEligMsg(null); setReturnIds([]); setRepl([{ product_id: '', quantity: 1 }]); setPays([]); setReason(''); setNotes(''); setErr(null);
    setMode('items'); setBundleLineId(''); setNewPromoId(''); setPicks([]); setLineComps({});
    setExStaff([]); setExAffiliate(''); setExRaisedBy(''); setExDate(singaporeToday());
    setOriginalContext(null); setInvoiceCustomer(null); setCustomerUnavailable(false);
    setConfirming(false); setAttestName('');
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
    setBundleLineId(''); setPicks([]); setLineComps({});
    setExStaff([]); setExAffiliate(''); setExRaisedBy(''); setPays([]);
    setExDate(singaporeToday());
    const q = invSearch.trim();
    if (!q) return;
    const { data: inv } = await supabase.from('invoices').select('*').eq('invoice_no', q).maybeSingle();
    if (!inv) { setErr('No invoice found with that number.'); return; }
    const { data: reasonData } = await supabase.rpc('exchange_ineligibility_reason', { p_invoice_id: (inv as Invoice).id });
    const rd = (reasonData as string | null) ?? '';
    if (rd !== '') { setEligMsg(rd); }
    const { data: items } = await supabase.from('invoice_items').select('*').eq('invoice_id', (inv as Invoice).id);
    // What each bundle line holds, so its items can be ticked under Items.
    const bundles = ((items as InvoiceItem[]) ?? []).filter(i => i.line_kind === 'promotion');
    const held = await Promise.all(bundles.map(b => supabase.rpc('bundle_line_components', { p_invoice_item_id: b.id })
      .then(({ data }) => [b.id, ((data as any[]) ?? []).map(r => ({ product_id: String(r.product_id), quantity: Number(r.quantity) }))] as const)));
    setLineComps(Object.fromEntries(held));
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
  const ticked = returnIds.length + picks.length;
  const pickOf = (lineId: string, productId: string) =>
    picks.find(p => p.invoice_item_id === lineId && p.product_id === productId) ?? null;
  const togglePick = (lineId: string, productId: string, held: number) =>
    setPicks(prev => prev.some(p => p.invoice_item_id === lineId && p.product_id === productId)
      ? prev.filter(p => !(p.invoice_item_id === lineId && p.product_id === productId))
      : [...prev, { invoice_item_id: lineId, product_id: productId, quantity: held }]);

  // bundle valuation (uses promotion regular totals — computed server-side; show best-effort here)
  const promoName = (id: string) => promotions.find(p => p.id === id)?.name ?? '—';
  // 455: one product type for everything ticked, plain lines and bundle items.
  const returnedType = useMemo(() => itemsProductType(
    [...returnedItems.map(i => i.product_id ?? ''), ...picks.map(p => p.product_id)],
    id => products.find(p => p.id === id)?.product_type), [returnedItems, picks, products]);

  // 424 (the Owner, Q17): each returned item counts for the lower of today's
  // price and what was paid for it (for a bundle item, its share of what the
  // bundle was paid; the server's preview). 455: pooled across every item.
  const itemsFig = useMemo(() => itemsCredit(creditPreview, returnIds, picks), [creditPreview, returnIds, picks]);
  const creditTotal = itemsFig.credit ?? 0;

  const replLines = repl.filter(r => r.product_id && r.quantity > 0);
  const replTotal = useMemo(() => replLines.reduce((s, r) => {
    const pr = priceAt(effectiveStore, r.product_id); return s + (pr ?? 0) * r.quantity;
  }, 0), [replLines, effectiveStore, prices]);

  const paySum = pays.reduce((s, p) => s + (Number(p.amount) || 0), 0);
  const modeFig: CreditFigures = { todays: itemsFig.todays, paid: itemsFig.paid, credit: itemsFig.credit };
  const modeCredit = creditTotal;
  // Only items of bundles ticked: what was paid is their share of the bundle's price.
  const shareOnly = picks.length > 0 && returnIds.length === 0;
  const compTopup = mode === 'bundle' ? 0 : Math.max(0, +(replTotal - modeCredit).toFixed(2));
  // An instalment is a label on money that has arrived, so its amount is
  // received money like any other and needs no separate coverage figure.
  const receivedNow = pays.reduce((a, p) => a + (Number(p.amount) || 0), 0);
  const compNonref = mode === 'bundle' ? 0 : Math.max(0, +(modeCredit - replTotal).toFixed(2));
  // What this exchange charges now: the whole bundle's top-up comes from the
  // server's preview; an Items exchange is priced here.
  const due = mode === 'bundle'
    ? (bundleQuote && !bundleQuote.problem ? bundleQuote.topup : 0)
    : compTopup;
  const selectedBundleLine = bundleLines.find(b => b.id === bundleLineId) ?? null;

  // replacement products must match returned type (own/third)
  const replCandidates = products.filter(p => returnedType && returnedType !== 'MIXED' ? p.product_type === returnedType : true);

  /** Why the returned items cannot be valued yet, or null. */
  const creditProblem = (): string | null => {
    if (creditPreviewState === 'loading') return 'Still working out what the returned items count for. Try again in a moment.';
    if (creditPreviewState !== 'ready' || !creditPreview) return 'What the returned items count for could not be worked out. Refresh the page and try again.';
    return null;
  };

  const validate = (): string | null => {
    if (!effectiveStore) return 'Select a processing store.';
    if (!invoice) return 'Find the original invoice first.';
    if (eligMsg) return eligMsg;
    if (!reason.trim()) return 'A reason is required for the exchange.';
    // 424: the day the sale counts on: from the 1st of this month, not before
    // the original sale, not in the future (the server checks the same).
    { const dp = exchangeDateProblem(exDate, singaporeToday(), saleDay(invoice));
      if (dp) return dp; }
    if (mode === 'items') {
      if (ticked === 0) return 'Select at least one item to return.';
      // 455: each bundle item once, up to what its bundle holds, not exchanged before.
      { const pick = itemPicksProblem(picks, bundleLines as any, lineComps, pName);
        if (pick) return pick; }
      if (returnedType === 'MIXED') return 'All returned items must be the same product type (own or third-party).';
      if (replLines.length === 0) return 'Add at least one replacement product.';
      if (returnedType && replLines.some(r => products.find(p => p.id === r.product_id)?.product_type !== returnedType)) {
        return `The replacement products must be ${returnedType === 'own' ? 'own' : 'third-party'} products, as the returned items are.`;
      }
      const valued = creditProblem();
      if (valued) return valued;
      if (itemsFig.missing) return 'A returned item has no price at this store, so it cannot be valued here.';
    } else if (mode === 'bundle') {
      if (!bundleLineId) return 'Select the bundle being returned.';
      { const block = bundleLineBlock(selectedBundleLine as any, 'bundle');
        if (block) return `This bundle cannot be exchanged whole: ${block}.`; }
      if (!newPromoId) return 'Select the replacement bundle.';
      if (bundleQuoteState === 'loading') return 'Still working out the bundle exchange — try again in a moment.';
      if (bundleQuoteState !== 'ready' || !bundleQuote) return 'The bundle exchange could not be priced. Refresh the page and try again.';
      if (bundleQuote.problem) return bundleQuote.problem;
      if (due > 0 && pays.some(p => p.payment_method_id === INSTALMENT_METHOD)) {
        return 'A whole-bundle exchange is paid in full now: choose a payment method, not an instalment.';
      }
    }
    // Only what is due is sent (nothing when nothing is due): every amount
    // with a method (a row left on "— Method —" would count here but never be
    // sent), never a wallet method, never more than is due, and for a whole
    // bundle exactly the top-up.
    if (due > 0) {
      const row = exchangePaymentRowProblem(pays, payMethods.map(m => m.id), INSTALMENT_METHOD);
      if (row) return row;
      const paid = exchangePaymentProblem({ due, received: receivedNow, exact: mode === 'bundle' });
      if (paid) return paid;
      const bad = pays.map(p => p.payment_method_id === INSTALMENT_METHOD ? portionProblem(p.instalment, p.amount || 0) : null).find(Boolean);
      if (bad) return bad;
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
    // Nothing is sent when nothing is due (the server refuses a payment then).
    const active = due > 0 ? pays : [];
    const payPayload = active
      .filter(p => Number(p.amount) > 0 && (p.payment_method_id === INSTALMENT_METHOD
        ? !!p.instalment?.method_id : !!p.payment_method_id))
      .map(p => ({
        payment_method_id: p.payment_method_id === INSTALMENT_METHOD ? p.instalment!.method_id : p.payment_method_id,
        amount: p.amount, reference: p.reference,
      }));
    // An instalment is recorded as the payment it is, under the real method,
    // so there is no arrangement to write alongside it. Its method and months
    // are the replacement invoice's instalment label (424), as on any invoice.
    const instalment = mode === 'bundle' ? null : instalmentLabelFrom(active, INSTALMENT_METHOD);
    // One call: the exchange and who handled it are written together, so an
    // exchange can never exist without its own attribution. The creators are
    // called underneath (455: create_items_exchange for Items).
    const common = {
      original_invoice_id: invoice.id, processing_store_id: effectiveStore,
      payments: payPayload,
      arrangements: [],
      instalment,
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
    // 455: plain lines whole, and each bundle item with its bundle line, the
    // product and how many, in one list.
    const payload = mode === 'items'
      ? { ...common,
          returned: [
            ...returnedItems.map(i => ({ invoice_item_id: i.id, quantity: i.quantity })),
            ...picks.map(p => ({ invoice_item_id: p.invoice_item_id, product_id: p.product_id, quantity: p.quantity })),
          ],
          replacement: replLines }
      : { ...common, original_invoice_item_id: bundleLineId, new_promotion_id: newPromoId };
    const { data, error } = await supabase.rpc('create_exchange_with_details', {
      p_kind: mode === 'items' ? 'items' : 'bundle',
      p_payload: payload,
    });
    setBusy(false);
    if (error) { setErr(exchangeServerWords(error.message)); setConfirming(false); return; }
    setConfirming(false); setWizard(false); load();
    alert(`Exchange ${(data as any)?.exchange_no ?? ''} completed.`);
  };

  // ---- Detail view ----
  const [detail, setDetail] = useState<ProductExchange | null>(null);
  const [detailItems, setDetailItems] = useState<ProductExchangeItem[]>([]);
  // 455: what the printed exchange says besides its rows: the original
  // invoice's number, the payments taken, and who raised and saved it.
  const [detailOrigNo, setDetailOrigNo] = useState<string | null>(null);
  const [detailPays, setDetailPays] = useState<any[]>([]);
  const [detailNames, setDetailNames] = useState<Record<string, string>>({});
  // Print waits for these reads: printed before them, both copies would say
  // "None" returned, no payments and no signature, and still be logged. A
  // failed read of the rows or the payments keeps Print off.
  const [detailState, setDetailState] = useState<'loading' | 'ready' | 'failed'>('loading');
  const detailSeq = useRef(0);
  const openDetail = async (e: ProductExchange) => {
    const seq = ++detailSeq.current;
    setDetail(e); setDetailItems([]); setDetailPosition(null);
    setDetailOrigNo(null); setDetailPays([]); setDetailNames({}); setDetailState('loading');
    const people = [(e as any).raised_by, e.created_by].filter(Boolean) as string[];
    try {
      const [items, orig, paid, names, position] = await Promise.all([
        supabase.from('product_exchange_items').select('*').eq('exchange_id', e.id),
        supabase.from('invoices').select('id, invoice_no').eq('id', e.original_invoice_id).maybeSingle(),
        supabase.from('product_exchange_payments').select('*').eq('exchange_id', e.id),
        people.length > 0 ? supabase.from('profiles').select('id, full_name').in('id', people) : Promise.resolve({ data: [] as any[] }),
        // What is charged, what arrived and what is still owed — read from the
        // server rather than inferred from the charge alone.
        supabase.rpc('exchange_payment_position', { p_exchange_id: e.id }),
      ]);
      if (seq !== detailSeq.current) return;   // another exchange opened since
      setDetailItems((items.data as ProductExchangeItem[]) ?? []);
      setDetailOrigNo((orig.data as any)?.invoice_no ?? null);
      setDetailPays((paid.data as any[]) ?? []);
      setDetailNames(Object.fromEntries(((names.data as any[]) ?? []).map(p => [p.id, p.full_name])));
      setDetailPosition(position.data ?? null);
      setDetailState(items.error || paid.error ? 'failed' : 'ready');
    } catch {
      if (seq === detailSeq.current) setDetailState('failed');
    }
  };

  // 455 (the Owner, 22 Oct 2026, item 4): the exchange document prints as
  // invoices do, a customer copy and an office copy on one A4 sheet
  // (printA5Document), the returned items above the replacement, the note on
  // both copies, and the person who raised it on the staff signature line.
  const printExchange = () => {
    if (!detail || detailState !== 'ready') return;
    const d: any = detail;
    const st: any = stores.find(x => x.id === detail.processing_store_id) ?? {};
    const cust: any = customers.find(c => c.id === detail.customer_id);
    const replNo = exchangeInvoiceNos[detail.id];
    const returnedRows = detailItems.filter(i => i.direction === 'returned')
      .map(i => `<tr><td>${printEsc(pName(i.product_id))}</td><td class="r">${printEsc(i.quantity)}</td><td class="r">${printEsc(money(i.line_total))}</td></tr>`).join('');
    const returnedTable = `<h2>Returned Items</h2><table><thead><tr><th>Returned Item</th><th class="r">Qty</th><th class="r">Credit</th></tr></thead>
      <tbody>${returnedRows || '<tr><td colspan="3" class="mut">None</td></tr>'}</tbody></table>`;
    const totals: PrintTotal[] = [
      { label: 'Returned value (credit)', value: money(detail.returned_credit_total) },
      { label: 'Replacement total', value: money(detail.replacement_total) },
      ...(Number(d.foc_amount ?? 0) > 0 ? [{ label: 'FOC waived', value: `−${money(d.foc_amount)}` }] : []),
      Number(detail.topup_amount) > 0 ? { label: 'Additional charge', value: money(detail.topup_amount), grand: true }
        : Number(detail.nonrefundable_amount) > 0 ? { label: 'Unused value (non-refundable)', value: money(detail.nonrefundable_amount), grand: true }
        : { label: 'Even exchange', value: money(0), grand: true },
    ];
    const payments: [string, string][] = detailPays.map(p => [
      `${methods.find(m => m.id === p.payment_method_id)?.name ?? 'Payment'}${p.reference ? ` · ${p.reference}` : ''}`, money(p.amount)]);
    if (Number(detail.topup_amount) > 0 && detailPosition && Number(detailPosition.outstanding) > 0) {
      payments.push(['Received', money(detailPosition.received)], ['Outstanding', money(detailPosition.outstanding)]);
    }
    // FOC reasons are internal (the Owner, Q7): the copies say FOC and its value.
    const extraBlocks = [
      ...(detail.reason ? [`<h2>Reason</h2><div class="mut">${printEsc(detail.reason)}</div>`] : []),
      ...(d.is_foc ? [`<div class="mut"><b>FREE OF CHARGE EXCHANGE</b> — FOC value ${printEsc(money(d.foc_amount ?? 0))}</div>`] : []),
      ...(detail.notes ? [`<h2>Notes</h2><div class="mut">${printEsc(detail.notes).replace(/\n/g, '<br/>')}</div>`] : []),
    ];
    const printed = printA5Document({
      docNo: detail.exchange_no,
      docTitle: 'Exchange',
      branding: st,
      headerLines: [
        ...(replNo ? [`Replacement invoice: ${printEsc(replNo)}`] : []),
        ...(detailOrigNo ? [`Original invoice: ${printEsc(detailOrigNo)}`] : []),
        `Exchange date: ${printEsc(displayDay(exchangeDay(detail)))}`,
        `Processed at: ${printEsc(sName(detail.processing_store_id))}`,
      ],
      billToName: cName(detail.customer_id),
      billToLines: [cust?.phone ?? ''].filter(Boolean),
      beforeItems: [returnedTable],
      itemHeading: 'Replacement Item',
      lines: detailItems.filter(i => i.direction === 'replacement')
        .map(i => ({ name: pName(i.product_id), qty: i.quantity, unit: Number(i.unit_price), total: Number(i.line_total) })),
      totals, payments, extraBlocks,
      // Who raised the exchange, else whoever saved it, as invoices print who raised them.
      signedByName: detailNames[d.raised_by ?? ''] ?? detailNames[detail.created_by ?? ''] ?? '',
      policyText: st.policy_text ?? null,
      termsText: 'Exchanged goods have been checked and collected. No further exchange is allowed on the returned items.',
    });
    if (!printed) return;
    // Audit: record that this exchange was printed. The server writes the row
    // for an exchange the person can see (406); the print never waits on it.
    supabase.rpc('record_document_printed', { p_kind: 'exchange', p_record_id: detail.id })
      .then(() => {}, () => {});
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Exchanges</h2><p>Product-to-product exchanges within 5 days of purchase. Returned stock comes back to the processing store; replacements are deducted from it.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={exchanges} filename="exchanges" sheetName="Exchanges"
            dateOf={(r: any) => exchangeDay(r)} dateLabel="Exchange date"
            columns={[
              { header: 'Date', value: (e: any) => exchangeDay(e).split('-').reverse().join('/') },
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
                    <td style={{ fontSize: 12.5 }}>{displayDay(exchangeDay(e))}</td>
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
        <Modal title="New Exchange" maxWidth={640} confirmClose onClose={() => setWizard(false)}
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
                  {([['items', 'Items'], ['bundle', 'Whole bundle']] as const).map(([v, lbl]) => (
                    <button key={v} type="button" className={`btn btn-sm ${mode === v ? 'btn-primary' : 'btn-secondary'}`}
                      onClick={() => { setMode(v); setReturnIds([]); setPicks([]); setBundleLineId(''); setNewPromoId(''); setPays([]); }}>{lbl}</button>
                  ))}
                </div>

                {mode === 'items' && (
                <div className="form-group">
                  <label>Items to return (select the ones physically brought back &amp; unused)</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                    {productLines.length === 0 && bundleLines.length === 0 && <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No products or bundles on this invoice.</span>}
                    {productLines.map(i => {
                      const already = (i as any).exchanged_at;
                      const on = returnIds.includes(i.id);
                      return (
                        <label key={i.id} style={{ display: 'flex', alignItems: 'center', gap: 8, opacity: already ? 0.5 : 1, fontSize: 13 }}>
                          <input type="checkbox" disabled={!!already} checked={on} style={{ width: 'auto' }}
                            onChange={() => setReturnIds(prev => on ? prev.filter(x => x !== i.id) : [...prev, i.id])} />
                          <span>{pName(i.product_id ?? '')} × {i.quantity} {already ? '(already exchanged)' : ''}
                            {!already && previewLine(creditPreview, i.id) && (() => {
                              const f = previewLine(creditPreview, i.id)!;
                              return <span className="muted" style={{ marginLeft: 6, fontSize: 12 }}>
                                paid {f.paid === null ? '—' : money(f.paid)} · today {f.todays === null ? 'no price here' : money(f.todays)}
                              </span>;
                            })()}
                          </span>
                        </label>
                      );
                    })}
                    {/* 455: each bundle's items, ticked beside the plain lines, each up
                        to what the bundle holds; an item exchanged before stays off. */}
                    {bundleLines.map(b => {
                      const block = bundleLineBlock(b as any, 'items');
                      const done = componentsExchanged(b as any);
                      return (
                        <div key={b.id} className="exchange-bundle-items" data-line={b.id} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                          <span style={{ fontSize: 12.5, color: 'var(--text-secondary)', opacity: block ? 0.5 : 1 }}>
                            {promoName(b.promotion_id ?? '')} × {b.quantity}{block ? ` (${block})` : ''}</span>
                          {!block && (lineComps[b.id] ?? []).map(c => {
                            const already = done.includes(c.product_id);
                            const pick = pickOf(b.id, c.product_id);
                            const f = already ? null : componentCredit(creditPreview, b.id, c.product_id, pick?.quantity ?? c.quantity);
                            return (
                              <div key={c.product_id} style={{ display: 'flex', alignItems: 'center', gap: 8, paddingLeft: 18, opacity: already ? 0.5 : 1, fontSize: 13 }}>
                                <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                                  <input type="checkbox" disabled={already} checked={!!pick} style={{ width: 'auto' }}
                                    onChange={() => togglePick(b.id, c.product_id, c.quantity)} />
                                  <span>{pName(c.product_id)} (×{c.quantity} in bundle){already ? ' (already exchanged)' : ''}
                                    {f && <span className="muted" style={{ marginLeft: 6, fontSize: 12 }}>
                                      {pick && pick.quantity !== c.quantity ? `×${pick.quantity}: ` : ''}its share paid {f.paid === null ? '—' : money(f.paid)} · today {f.todays === null ? 'no price here' : money(f.todays)}
                                    </span>}
                                  </span>
                                </label>
                                {pick && c.quantity > 1 && (
                                  <input type="number" min={1} max={c.quantity} value={pick.quantity} style={{ width: 64 }}
                                    aria-label={`How many ${pName(c.product_id)} come back`}
                                    onChange={e => setPicks(prev => prev.map(p => p.invoice_item_id === b.id && p.product_id === c.product_id
                                      ? { ...p, quantity: +e.target.value } : p))} />
                                )}
                              </div>
                            );
                          })}
                        </div>
                      );
                    })}
                  </div>
                  {returnedType === 'MIXED' && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>Returned items must all be the same product type (own or third-party).</div>}
                </div>
                )}

                {mode === 'bundle' && (
                  <div className="form-group">
                    <label>Bundle on this invoice</label>
                    <select value={bundleLineId} onChange={e => setBundleLineId(e.target.value)}>
                      <option value="">— Select bundle —</option>
                      {bundleLines.map(i => {
                        // Whole bundle: one bundle whose items were not exchanged on
                        // their own (408); the others are returned item by item under Items.
                        const block = bundleLineBlock(i as any, 'bundle');
                        return <option key={i.id} value={i.id} disabled={!!block}>{promoName(i.promotion_id ?? '')} × {i.quantity}{block ? ` (${block})` : ''}</option>;
                      })}
                    </select>
                    {bundleLines.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No bundles on this invoice.</span>}
                  </div>
                )}

                {mode === 'bundle' && bundleLineId && (
                  <>
                    <div className="form-group">
                      <label>Replacement bundle</label>
                      {/* Every active bundle is a candidate here, and the catalogue runs to
                          names that differ by one word — "Bundle B with Therapy" against
                          "Bundle B with Vouchers". Scrolling a plain <select> for those is
                          how the wrong bundle gets picked, so this searches name, code and
                          price, the same way the invoice form's promotion picker does. */}
                      <SearchSelect placeholder="Search bundle name, code or price…"
                        value={newPromoId} onChange={v => setNewPromoId(v)}
                        emptyLabel="No bundle matches that name, code or price"
                        options={promotions.filter(p => promotionOnSale(p, singaporeToday())).map(p => ({
                          value: p.id,
                          label: `${p.name} — ${money(Number(p.fixed_price))}`,
                          sublabel: p.code,
                          search: `${p.name} ${p.code ?? ''}`,
                          searchPrices: [p.fixed_price],
                        }))} />
                    </div>
                    <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Whole-bundle swap: every item of the old bundle goes back to stock and every item of the new bundle is taken out. Only one bundle of products is swapped whole: a bundle with choices, vouchers or therapy, a line of several bundles, or one with an item already exchanged is returned item by item under Items.</div></div>
                  </>
                )}

                {mode === 'bundle' && bundleLineId && newPromoId && (
                  bundleQuoteState === 'loading'
                    ? <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>Working out the exchange…</div>
                    : bundleQuoteState === 'failed' || !bundleQuote
                      ? <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>The bundle exchange could not be priced. Refresh the page and try again.</div></div>
                      : bundleQuote.problem
                        ? <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{bundleQuote.problem}</div></div>
                        : (
                          <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 12, fontSize: 13 }}>
                            {bundleQuote.todays_value !== null && bundleQuote.paid !== null && (<>
                              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Returned bundle, today's value</span><span>{money(bundleQuote.todays_value)}</span></div>
                              <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Returned bundle, what was paid</span><span>{money(bundleQuote.paid)}</span></div>
                            </>)}
                            <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Exchange credit (the lower of the two)</span><strong>{money(bundleQuote.credit)}</strong></div>
                            {bundleQuote.todays_value !== null && bundleQuote.paid !== null && (
                              <div className="muted" style={{ fontSize: 12 }}>{creditBasisText({ todays: bundleQuote.todays_value, paid: bundleQuote.paid, credit: bundleQuote.credit })}</div>)}
                            <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Replacement bundle</span><strong>{money(bundleQuote.replacement)}</strong></div>
                            <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px solid var(--border)', marginTop: 6, paddingTop: 6 }}>
                              {bundleQuote.topup > 0 ? <><span>Additional charge (paid in full now)</span><strong style={{ color: 'var(--primary)' }}>{money(bundleQuote.topup)}</strong></>
                                : bundleQuote.nonrefundable > 0 ? <><span>Unused value (non-refundable)</span><strong style={{ color: 'var(--danger)' }}>{money(bundleQuote.nonrefundable)}</strong></>
                                : <><span>Even exchange</span><strong>{money(0)}</strong></>}
                            </div>
                            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 6, lineHeight: 1.6 }}>
                              <div>Back to stock: {bundleQuote.returned.map(x => `${x.name} ×${x.quantity}`).join(', ') || '—'}</div>
                              <div>Out of stock: {bundleQuote.replacement_items.map(x => `${x.name} ×${x.quantity}`).join(', ') || '—'}</div>
                            </div>
                          </div>
                        )
                )}

                {mode === 'items' && (
                <div className="form-group">
                  <label>Replacement products {returnedType && returnedType !== 'MIXED' ? `(${returnedType === 'own' ? 'own' : 'third-party'} only)` : ''}</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    {repl.map((r, i) => (
                      <div key={i} style={{ display: 'flex', gap: 6 }}>
                        <SearchSelect style={{ flex: 1 }} placeholder="Search product name or SKU…"
                          value={r.product_id}
                          onChange={v => setRepl(rs => rs.map((x, j) => j === i ? { ...x, product_id: v } : x))}
                          options={replCandidates
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

                {/* Valuation: the credit comes from the server's preview (424); the
                    replacement is priced here, as the server prices it. */}
                {mode !== 'bundle' && (
                <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 12, fontSize: 13 }}>
                  {creditPreviewState === 'loading' && <div className="muted">Working out what the returned items count for…</div>}
                  {creditPreviewState === 'failed' && <div style={{ color: 'var(--danger)' }}>What the returned items count for could not be worked out. Refresh the page and try again.</div>}
                  {creditPreviewState === 'ready' && modeFig.credit !== null && ticked > 0 && (<>
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Returned, today's price</span><span>{money(modeFig.todays ?? 0)}</span></div>
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>{shareOnly ? 'Returned, its share of what the bundle was paid'
                      : picks.length > 0 ? 'Returned, what was paid (a bundle item: its share)' : 'Returned, what was paid'}</span><span>{money(modeFig.paid ?? 0)}</span></div>
                  </>)}
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Exchange credit (the lower of the two)</span><strong>{money(modeCredit)}</strong></div>
                  {creditPreviewState === 'ready' && ticked > 0 && (
                    <div className="muted" style={{ fontSize: 12 }}>{creditBasisText(modeFig, shareOnly)}</div>)}
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Replacement total</span><strong>{money(replTotal)}</strong></div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px solid var(--border)', marginTop: 6, paddingTop: 6 }}>
                    {compTopup > 0 ? <><span>Additional charge</span><strong style={{ color: 'var(--primary)' }}>{money(compTopup)}</strong></>
                      : compNonref > 0 ? <><span>Unused value (non-refundable)</span><strong style={{ color: 'var(--danger)' }}>{money(compNonref)}</strong></>
                      : <><span>Even exchange</span><strong>{money(0)}</strong></>}
                  </div>
                </div>
                )}
                {due > 0 && (
                  <div className="form-group">
                    <label>Additional payment ({money(due)} due) — {mode === 'bundle'
                      ? 'exactly this amount, now, by one or more methods'
                      : 'all of it now, by one or more methods (Instalment records how it is paid)'}</label>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {pays.map((p, i) => (
                        <div key={i} style={{ display: 'flex', gap: 6 }}>
                          <select value={p.payment_method_id} style={{ flex: 1 }} onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, payment_method_id: e.target.value } : x))}>
                            <option value="">— Method —</option>
                            {/* A label on money taken now (the duration is recorded on the replacement invoice). */}
                            {mode !== 'bundle' && <option value={INSTALMENT_METHOD}>Instalment</option>}
                            {/* Never wallet credit: an exchange takes no credit from the wallet. */}
                            {payMethods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                          </select>
                          <input type="number" min={0} step="0.01" value={p.amount} style={{ width: 90 }}
                            placeholder={p.payment_method_id === INSTALMENT_METHOD ? 'Now' : 'Amount'}
                            onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, amount: +e.target.value } : x))} />
                          <input value={p.reference} placeholder="Ref" style={{ width: 80 }} onChange={e => setPays(ps => ps.map((x, j) => j === i ? { ...x, reference: e.target.value } : x))} />
                          <button className="btn btn-secondary btn-sm btn-icon" type="button" onClick={() => setPays(ps => ps.filter((_, j) => j !== i))}><Trash2 size={13} /></button>
                        </div>
                      ))}
                      {pays.map((p, i) => p.payment_method_id === INSTALMENT_METHOD && mode !== 'bundle' ? (
                        <InstalmentPortionFields key={`inst-${i}`}
                          value={p.instalment ?? emptyPortion}
                          onChange={v => setPays(ps => ps.map((x, j) => j === i ? { ...x, instalment: v } : x))}
                          methods={payMethods}
                          receivedNow={p.amount || 0}
                          onReceivedNow={n => setPays(ps => ps.map((x, j) => j === i ? { ...x, amount: n } : x))}
                          error={portionProblem(p.instalment, p.amount || 0)} />
                      ) : null)}
                      <button className="btn btn-secondary btn-sm" type="button" style={{ alignSelf: 'flex-start' }} onClick={() => setPays(ps => [...ps, { payment_method_id: payMethods[0]?.id ?? '', amount: +(due - paySum).toFixed(2) > 0 ? +(due - paySum).toFixed(2) : 0, reference: '' }])}><Plus size={13} /> Add payment</button>
                      {mode === 'bundle' && (
                        <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.7 }}>
                          <div>Additional charge: <strong>{money(due)}</strong></div>
                          <div>Received now: <strong style={{ color: Math.abs(receivedNow - due) < 0.005 ? 'var(--success)' : 'var(--accent)' }}>{money(receivedNow)}</strong></div>
                        </div>
                      )}
                      {mode !== 'bundle' && (
                        <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.7 }}>
                          <div>Additional charge: <strong>{money(compTopup)}</strong></div>
                          <div>Received now: <strong style={{ color: Math.abs(receivedNow - compTopup) < 0.005 ? 'var(--success)' : 'var(--accent)' }}>{money(receivedNow)}</strong></div>
                        </div>
                      )}
                    </div>
                  </div>
                )}

                <div className="form-grid-2">
                  <div className="form-group"><label>Reason *</label><input value={reason} onChange={e => setReason(e.target.value)} placeholder="Required" /></div>
                  <div className="form-group"><label>Notes</label>
                    <textarea value={notes} rows={3} onChange={e => setNotes(e.target.value)} placeholder="Optional" />
                    {/* 455 (the Owner, 22 Oct 2026, item 6): the note prints. */}
                    <small>Prints on both copies of the exchange (the customer's and the office's) and on its replacement invoice, so the customer sees it. It cannot be changed once the exchange is saved.</small>
                  </div>

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
                      placeholder={originalContext?.affiliate_inherited_id
                        ? `Same as the original sale (${originalContext.affiliate})` : 'Search affiliate…'}
                      options={[
                        { value: 'none', label: 'None — no affiliate for this exchange' },
                        ...affiliateOptions,
                      ]} />
                    <small>
                      {/* 408: left empty, an exchange carries the original sale's
                          affiliate while they are still eligible. */}
                      {affiliateHint(originalContext)}
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
                      min={exchangeDateFloor(singaporeToday(), saleDay(invoice))}
                      onChange={e => setExDate(e.target.value)} />
                    {/* 424 (the Owner, 9 Oct 2026): the sale counts on this date,
                        never before the 1st of this month. */}
                    <small>
                      Defaults to today in Singapore. {exchangeDateHint(exDate, singaporeToday())}{' '}
                      The earliest is the 1st of this month, so a month already sent to Xero never changes. It cannot be before the original sale. The original invoice’s date is not changed.
                    </small>
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
                {mode === 'items' && returnedItems.map(i => (
                  <div key={i.id} style={{ fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <strong>{pName(i.product_id ?? '')}</strong> × {i.quantity}
                    <span style={{ color: 'var(--text-muted)', marginLeft: 6 }}>SKU: {pSku(i.product_id ?? '') || '—'}</span>
                  </div>
                ))}
                {mode === 'items' && picks.map(p => (
                  <div key={`${p.invoice_item_id}/${p.product_id}`} style={{ fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <strong>{pName(p.product_id)}</strong> × {p.quantity}
                    <span style={{ color: 'var(--text-muted)', marginLeft: 6 }}>SKU: {pSku(p.product_id) || '—'}</span>
                    <div style={{ color: 'var(--text-muted)', marginTop: 2 }}>(item of {promoName(bundleLines.find(b => b.id === p.invoice_item_id)?.promotion_id ?? '')})</div>
                  </div>
                ))}
                {mode === 'bundle' && (
                  <div style={{ fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <strong>Whole bundle: {promoName(bundleLines.find(b => b.id === bundleLineId)?.promotion_id ?? '')}</strong>
                    <div style={{ color: 'var(--text-muted)', marginTop: 2 }}>{(lineComps[bundleLineId] ?? []).map(cp => `${pName(cp.product_id)} ×${cp.quantity}`).join(', ')}</div>
                    <div style={{ marginTop: 2 }}>→ replacing with: <strong>{promoName(newPromoId)}</strong></div>
                    {bundleQuote && !bundleQuote.problem && (
                      <div style={{ marginTop: 4 }}>
                        Credit {money(bundleQuote.credit)} · Replacement {money(bundleQuote.replacement)} ·{' '}
                        <strong>{bundleQuote.topup > 0 ? `${money(bundleQuote.topup)} paid now`
                          : bundleQuote.nonrefundable > 0 ? `${money(bundleQuote.nonrefundable)} unused (non-refundable)`
                          : 'even exchange'}</strong>
                      </div>
                    )}
                  </div>
                )}
                {exDate && exDate < singaporeToday() && (
                  <div style={{ fontSize: 13 }}>{exchangeDateHint(exDate, singaporeToday())}</div>
                )}
                {mode !== 'bundle' && (
                  <div style={{ fontSize: 13 }}>
                    Credit {money(modeCredit)} · Replacement {money(replTotal)} ·{' '}
                    <strong>{compTopup > 0 ? `${money(compTopup)} paid now`
                      : compNonref > 0 ? `${money(compNonref)} unused (non-refundable)` : 'even exchange'}</strong>
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
          footer={
            // Three buttons wrap on a phone rather than run off the dialog's left edge.
            <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'flex-end', gap: 10, rowGap: 8, flex: 1, minWidth: 0 }}>
            {/* 455 (the Owner, 22 Oct 2026, item 4): the replacement invoice, to
                print or send from the Invoices page. */}
            {exchangeInvoiceIds[detail.id] && (
              <a className="btn btn-secondary" href={`/invoices?review=${encodeURIComponent(exchangeInvoiceIds[detail.id])}`}><FileText size={14} /> Open invoice</a>)}
            <button className="btn btn-secondary" onClick={printExchange} disabled={detailState !== 'ready'}>
              <Printer size={14} /> {detailState === 'loading' ? 'Loading…' : 'Print'}</button>
            <button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></div>}>
          <div className="form-grid">
            <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{cName(detail.customer_id)} · {sName(detail.processing_store_id)} · {displayDay(exchangeDay(detail))}
              {detailOrigNo ? ` · Original invoice ${detailOrigNo}` : ''}</div>
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
                  {exchangeInstalments[detail.id] && (
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: 'var(--text-secondary)' }}>
                      <span>Paid by instalment</span>
                      <span>{exchangeInstalments[detail.id].months} months · {methods.find(m => m.id === exchangeInstalments[detail.id].method_id)?.name ?? 'payment method'}</span>
                    </div>)}
                  {(detailPosition.arrangements ?? []).map((a: any) => (
                    <div key={a.arrangement_id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: 'var(--text-secondary)' }}>
                      <span>{a.category === 'in_house' ? 'In-house' : 'Provider-funded'} instalment · {a.months} months · {a.method}</span>
                      <span>{money(a.covered_amount)} covered · {money(a.remaining)} left</span>
                    </div>))}
                </>)}
              </>)}
              {detail.nonrefundable_amount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--danger)' }}><span>Unused value (non-refundable)</span><strong>{money(detail.nonrefundable_amount)}</strong></div>}
            </div>
            {detail.notes && (
              <div>
                <label>Notes</label>
                <div style={{ fontSize: 13, whiteSpace: 'pre-wrap' }}>{detail.notes}</div>
              </div>)}
            {detailState === 'failed' && (
              <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>This exchange could not be read in full, so it cannot be printed. Close it and open it again.</div></div>)}
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>This exchange is locked. No further exchange is allowed on the returned items.</div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default ExchangesPage;
