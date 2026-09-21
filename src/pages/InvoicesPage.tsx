import { useSearchParams } from 'react-router-dom';
import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react';
import { PRINT_CSS } from '../lib/printDoc';
import { sendViaWhatsAppLink, sendViaEmailAttachment, saveDocumentFile, whatsappNumber, emailAddress, DocFormat } from '../lib/sendDoc';
import { PdfDoc } from '../lib/invoicePdf';
import { ExcelExportButton } from '../components/ExcelExport';
import { PaymentSummaryExport } from '../components/PaymentSummaryExport';
import { XeroExportButton } from '../components/XeroExport';
import { supabase } from '../lib/supabase';
import { fetchAllFrom } from '../lib/supabasePaging';
import { PaymentPriceReview, PriceReviewResult } from '../components/PricingControls';
import type { FocReason, InvoiceRevision } from '../types';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, InvoiceItem, InvoicePayment, Store, Product,
  PaymentMethod, StoreProductPrice, InvoiceStatus, INVOICE_STATUS_LABELS, Voucher, Promotion, PromotionChoiceGroup, PromotionChoiceOption, isOwnerOrManager, isOwner, Profile, SERVICE_STAFF_ROLES, TherapyPackageRule } from '../types';
import { SearchSelect, CustomerSearchSelect } from '../components/SearchSelect';
import { QuickCustomerModal } from '../components/customers/QuickCustomerModal';
import { CreditPackageSplitPanel } from '../components/CreditPackageSplitPanel';
import { PremiumBundleSplitPanel } from '../components/PremiumBundleSplitPanel';
import { Modal } from '../components/ui';
import {
  Plus, RefreshCw, FileText, Trash2, X, CreditCard, Eye, Search, CheckCircle2, Download, Printer, Sparkles, MessageCircle, Mail, AlertTriangle } from 'lucide-react';

import { InvoiceFinancePanel } from '../components/invoices/InvoiceFinancePanel';
import { InvoiceRefundCancelChooser } from '../components/invoices/InvoiceRefundCancelChooser';
import { InvoiceGuidedAction } from '../components/invoices/InvoiceGuidedAction';
import { CorrectionPreview } from '../components/invoices/CorrectionPreview';
import { InvoiceStockEvidenceReview } from '../components/invoices/InvoiceStockEvidenceReview';
import { InstalmentFields } from '../components/invoices/InstalmentFields';
import { InstalmentPortionFields, INSTALMENT_METHOD, emptyPortion, portionProblem,
         type InstalmentPortion } from '../components/invoices/InstalmentPortionFields';
import { singaporeToday, displayInvoiceDate, invoiceDateSearch, instalmentText, validateInstalment, type InstalmentDetails, INVOICE_SORT_FIELDS, isInvoiceSortField,
  type InvoiceSortField, type SortDirection } from '../lib/invoices/business';
import { InvoiceSearchSelect } from '../components/invoices/InvoiceSearchSelect';
import '../components/invoices/invoice-controls.css';

import { fetchInvoicePage, fetchAllMatchingInvoices } from '../lib/invoices/listPage';
import { createRefreshQueue, createStampedWriter, refreshCovers, pageAfterRefresh, announcedMatchesShown } from '../lib/invoices/listRefresh';
import { useInvoiceLiveUpdates, type LiveChange } from '../hooks/useInvoiceLiveUpdates';
import { calendarDate, calendarDateInRange } from '../lib/calendarDates';

const money = (n: number) => `S$${n.toFixed(2)}`;

type PayPart = { amount: string; date: string; payment_method_id: string };
/** One recorded payment as the operator wants it to read: one part is a plain
 *  correction (or nothing), two or more are a split across methods. */
type PayEdit = { parts: PayPart[]; remove: boolean };
/** Receipts and replacements still standing. A reversed entry, and the
 *  payment it superseded, are history rather than something to correct again. */
const currentPaymentsOf = (pays: InvoicePayment[]) => pays.filter(p =>
  (p as any).entry_kind !== 'correction_reversal'
  && !pays.some(r => (r as any).corrects_payment_id === p.id && (r as any).entry_kind === 'correction_reversal'));
/** The calendar day the money was received, in the business's time zone. */
const sgDateOf = (p: InvoicePayment) => calendarDate((p as any).effective_at || p.created_at, 'Asia/Singapore');

const StatusBadge: React.FC<{ s: InvoiceStatus }> = ({ s }) => {
  const cls = s === 'completed_foc' ? 'badge-success' : s === 'paid' ? 'badge-success' : s === 'partially_paid' ? 'badge-primary'
    : s === 'unpaid' || s === 'draft' ? 'badge-accent'
    : s === 'cancelled' || s === 'refunded' ? 'badge-muted' : 'badge-danger';
  return <span className={`badge ${cls}`}>{INVOICE_STATUS_LABELS[s]}</span>;
};

interface LineDraft { invoice_item_id?: string; unit_price?: number; saved_topup?: number; kind: 'product' | 'voucher' | 'promotion' | 'therapy' | 'special_product' | 'rental' | 'credit_package' | 'premium_bundle';
  special_product_id?: string; rental_rate_type?: 'day' | 'week' | 'month' | 'year';
  rental_periods?: number; rental_start_date?: string; rental_return_date?: string; product_id: string; voucher_id: string; promotion_id: string; therapy_package_id?: string; therapy_service_id?: string; therapy_service_name?: string; therapy_benefit_intent?: '' | 'unlimited' | 'voucher';
  // Credit purchases bought directly on the invoice (Phase 31). The price and
  // every credit/reward snapshot come from the backend; these only carry the
  // chosen package/bundle and, for a bundle, the reward-voucher mix.
  credit_package_id?: string; premium_bundle_id?: string; bundle_voucher_selection?: Record<string, number>;
  quantity: number; line_voucher_id: string; selections: Record<string, Record<string, number>>; foc_quantity?: number; foc_reason_id?: string; foc_reason?: string; }

const InvoicesPage: React.FC = () => {
  const { profile, session } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [promotions, setPromotions] = useState<Promotion[]>([]);
  const [choiceGroups, setChoiceGroups] = useState<PromotionChoiceGroup[]>([]);
  const [promoItems, setPromoItems] = useState<any[]>([]);
  // Whole customer records — name, phone, email, referrer — for the few
  // customers a screen actually needs one for: the invoice being viewed, the
  // one chosen in the form, their referrer. Fetched by id, so this is correct
  // and cheap at any table size.
  const [customerById, setCustomerById] = useState<Record<string, any>>({});
  // Each list row arrives with its customer's name attached, from the same
  // query that produced the row, so labelling a page of invoices costs no
  // request at all. Kept apart from customerById, which holds whole records —
  // a name here must never be mistaken for a customer whose phone is missing.
  const [nameById, setNameById] = useState<Record<string, string>>({});
  const rememberNames = useCallback((rows: { customer_id?: string | null; customer_name?: string | null }[]) => {
    setNameById(prev => {
      const next = { ...prev };
      let changed = false;
      for (const r of rows) {
        const id = r.customer_id, name = r.customer_name;
        if (id && name && next[id] !== name) { next[id] = name; changed = true; }
      }
      return changed ? next : prev;
    });
  }, []);
  // Ids already fetched or in flight. Without this an effect that re-runs while
  // a request is still out — which is what following a referral chain does —
  // asks for the same customer twice.
  const customerAskedRef = useRef<Set<string>>(new Set());
  const ensureCustomers = useCallback(async (ids: (string | null | undefined)[]) => {
    const wanted = Array.from(new Set(ids.filter(Boolean) as string[]))
      .filter(id => !customerAskedRef.current.has(id));
    if (wanted.length === 0) return;
    for (const id of wanted) customerAskedRef.current.add(id);
    const found: Record<string, any> = {};
    for (let i = 0; i < wanted.length; i += 200) {
      const slice = wanted.slice(i, i + 200);
      const { data, error } = await supabase.from('customers')
        .select('id, full_name, phone, email, referred_by')
        .in('id', slice);
      // A failed request must not mark those ids as settled, or the names
      // would stay missing until the page is reloaded.
      if (error) { for (const id of slice) customerAskedRef.current.delete(id); continue; }
      for (const c of (data as any[]) ?? []) found[c.id] = c;
    }
    if (Object.keys(found).length > 0) setCustomerById(cur => ({ ...cur, ...found }));
  }, []);
  const [choiceOptions, setChoiceOptions] = useState<PromotionChoiceOption[]>([]);
  const [storeInv, setStoreInv] = useState<any[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  // A staff member may be assigned to several stores; they choose among those.
  const [myStores, setMyStores] = useState<{ store_id: string; store_name: string; is_default: boolean }[]>([]);
  const [therapyRules, setTherapyRules] = useState<TherapyPackageRule[]>([]);
  const [therapyPackages, setTherapyPackages] = useState<any[]>([]);
  const [therapyServices, setTherapyServices] = useState<any[]>([]);
  const [therapyServiceStores, setTherapyServiceStores] = useState<any[]>([]);
  const [cServiceStaff, setCServiceStaff] = useState<string[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [prices, setPrices] = useState<StoreProductPrice[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<'all' | InvoiceStatus>('all');
  const [dateFilter, setDateFilter] = useState<'all' | 'confirmed' | 'pending'>('all');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  // A background refresh keeps the rows on screen and reports failure beside
  // them; only the first load, which has nothing to keep, shows an empty state.
  const [refreshing, setRefreshing] = useState(false);
  const [refreshError, setRefreshError] = useState<{ message: string; afterSave?: string } | null>(null);
  // Free-text search includes the confirmed invoice business date.
  const [invSearch, setInvSearch] = useState('');

  // Create modal
  const [createOpen, setCreateOpen] = useState(false);
  const [cStore, setCStore] = useState('');
  const [cBusinessDate, setCBusinessDate] = useState(singaporeToday);
  const [cNotes, setCNotes] = useState('');
  const [cInstalment, setCInstalment] = useState<InstalmentDetails>({ instalment_category: '', instalment_method_id: '', instalment_months: '' });
  const [expectedEditCount, setExpectedEditCount] = useState(0);
  const [editRequestId, setEditRequestId] = useState(() => crypto.randomUUID());
  const [cCustomer, setCCustomer] = useState('');
  const [issuedRecipientsConfirmed, setIssuedRecipientsConfirmed] = useState(false);
  // Two different corrections, named. A checkbox that said recipients would stay
  // put was what permitted the move, so there was no way to ask for either one
  // deliberately. Blank until chosen — the server refuses without it.
  const [benefitAction, setBenefitAction] = useState<'' | 'transfer' | 'keep'>('');
  // Which selector opened the customer form, so the new customer lands in the
  // row that asked for it and nothing else moves.
  const [quickCustomerFor, setQuickCustomerFor] = useState<null | { target: 'invoice' }>(null);
  const [issuedHeaderBefore, setIssuedHeaderBefore] = useState<{ customer: string; store: string } | null>(null);
  useEffect(() => { setIssuedRecipientsConfirmed(false); }, [cCustomer, cStore]);
  useEffect(() => { if (cCustomer) void ensureCustomers([cCustomer]); }, [cCustomer, ensureCustomers]);
  // The commission note names the referrer, so the chain is followed one
  // link up by id. ensureCustomers ignores ids it already holds, so this
  // settles after a single request.
  useEffect(() => {
    const referrerId = cCustomer ? customerById[cCustomer]?.referred_by : null;
    if (referrerId) void ensureCustomers([referrerId]);
  }, [cCustomer, customerById, ensureCustomers]);
  // Declared HERE, above lineUnit(), which reads it. A `const` is not hoisted:
  // declaring this further down put it in the temporal dead zone, so the first
  // render threw "Cannot access 'specialProducts' before initialization" and
  // the whole page went blank.
  const [specialProducts, setSpecialProducts] = useState<any[]>([]);
  const [cLines, setCLines] = useState<LineDraft[]>([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]);
  const [originalDrafts, setOriginalDrafts] = useState<LineDraft[]>([]);
  const unchangedDraft = (l: LineDraft) => !!l.invoice_item_id && JSON.stringify(l) === JSON.stringify(originalDrafts.find(o => o.invoice_item_id === l.invoice_item_id));
  const unchangedBenefitDefinition = (l: LineDraft) => {
    const original = originalDrafts.find(o => o.invoice_item_id === l.invoice_item_id);
    return !!original && JSON.stringify({ ...l, unit_price: undefined }) === JSON.stringify({ ...original, unit_price: undefined });
  };
  const [cDiscountVoucher, setCDiscountVoucher] = useState('');
  const [cDiscount, setCDiscount] = useState(0);
  // Internal reason for a manual discount. Its own field: not the customer
  // notes and not the correction reason. Required on the server whenever a
  // positive discount is set or changed; the form asks first so the refusal
  // arrives with the field focused rather than as a message from the save.
  const [cDiscountReason, setCDiscountReason] = useState('');
  const [discountReasonErr, setDiscountReasonErr] = useState<string | null>(null);
  const [discountBeforeEdit, setDiscountBeforeEdit] = useState(0);
  const discountReasonRef = useRef<HTMLInputElement>(null);
  // Focus is moved by an effect, not a frame callback: it then happens on the
  // commit that shows the error, and cannot be lost to a throttled frame.
  const [reasonFocusTick, setReasonFocusTick] = useState(0);
  useEffect(() => { if (reasonFocusTick) discountReasonRef.current?.focus(); }, [reasonFocusTick]);
  const [cErr, setCErr] = useState<string | null>(null);
  const [cSaving, setCSaving] = useState(false);
  const [splitMode, setSplitMode] = useState(false);
  const [splitSummary, setSplitSummary] = useState<{ package_name: string; invoices: any[] } | null>(null);

  // Detail / payment modal
  const [detailFinancial, setDetailFinancial] = useState<any>(null);
  const [chooserOpen, setChooserOpen] = useState(false);
  // Newest first by creation time, which is what the list has always shown.
  // Server-side paging. The list asks the database for one page; it no longer
  // downloads the table and slices it here.
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const [pageRows, setPageRows] = useState<Invoice[]>([]);
  const [pageTotal, setPageTotal] = useState(0);
  const [pageCount, setPageCount] = useState(0);
  const [pageSummary, setPageSummary] = useState({ matching: 0, total_amount: 0, outstanding: 0, paid: 0 });
  const [pageLoading, setPageLoading] = useState(false);
  const [pageError, setPageError] = useState<string | null>(null);
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [exportProgress, setExportProgress] = useState<{ got: number; all: number } | null>(null);
  // Only the newest request may write to the screen. Without this a slow early
  // keystroke can land after a fast later one and show the wrong results.
  const pageRequestRef = useRef(0);
  // The latest page, query, rows and dialog state, for handlers that run long
  // after the render that created them (a realtime event, a queued refresh).
  const pageRef = useRef(1);
  const rangeInvalidRef = useRef(false);
  const pageRowsRef = useRef<Invoice[]>([]);
  const createOpenRef = useRef(false);
  const editingIdRef = useRef<string | null>(null);
  const dialogsOpenRef = useRef(false);
  const financeActiveRef = useRef(false);
  // Whether the payment entry under the open invoice has been touched since it
  // was opened. An untouched entry can be reset by a background reload; a
  // touched one is never reset without being asked.
  const payTouchedRef = useRef(false);
  const programmaticPayRef = useRef(true);
  // Set on mount as well as cleared on unmount: React's development double
  // mount runs the cleanup once and mounts again with the same refs.
  const mountedRef = useRef(true);
  useEffect(() => { mountedRef.current = true; return () => { mountedRef.current = false; }; }, []);
  // When the page last started reading the list, and the last change it was
  // told about (its own save, another tab's, a realtime event): the same
  // change arriving again by another route needs no second refresh.
  const lastRefreshStartedRef = useRef(0);
  const recentChangeRef = useRef<{ at: number; ids: Set<string>; source: string }>({ at: 0, ids: new Set(), source: '' });
  const labelStamps = useRef(createStampedWriter());
  const announceRef = useRef<(ids: string[]) => void>(() => {});
  const noteLocalChangeRef = useRef<(ids: string[]) => void>(() => {});
  // The open invoice, or the one being edited, was changed elsewhere.
  const [detailStale, setDetailStale] = useState(false);
  const [detailUpdatedNote, setDetailUpdatedNote] = useState<string | null>(null);
  const [detailReloadError, setDetailReloadError] = useState<string | null>(null);
  const [editConflict, setEditConflict] = useState<{ reviewed: boolean; fresh: Invoice | null; loading: boolean } | null>(null);
  const editBaseRef = useRef<Invoice | null>(null);
  // Whether a list read was requested since a change was first seen: a request
  // made at T runs at or after T, so it covers every change seen before T.
  const lastRefreshRequestedRef = useRef(0);
  // Foreground loads (first open, filter/page change) own the "loading…"
  // indicator; a background refresh that lands first must not leave it on.
  const foregroundTicketRef = useRef(0);
  const [sortField, setSortField] = useState<InvoiceSortField>('created_at');
  const [sortDir, setSortDir] = useState<SortDirection>('desc');
  // The guided flow replaces the old two-step chooser: it derives the whole
  // effect set itself, so staff never pick ledger rows.
  const [guidedOpen, setGuidedOpen] = useState(false);
  const [financeRequest, setFinanceRequest] = useState<{ mode: 'refund' | 'cancel' | 'payment'; paymentId?: string } | null>(null);
  const [detail, setDetail] = useState<Invoice | null>(null);
  const [detailItems, setDetailItems] = useState<InvoiceItem[]>([]);
  const [detailPromoItems, setDetailPromoItems] = useState<any[]>([]);      // fixed contents of promotions on this invoice
  const [detailSelections, setDetailSelections] = useState<any[]>([]);      // chosen items for this invoice
  const [detailPayments, setDetailPayments] = useState<InvoicePayment[]>([]);
  // Payment methods per invoice for the whole list, so the table can show them
  // and the search can match on them. Keyed by invoice for a direct lookup.
  const [payMethodsByInvoice, setPayMethodsByInvoice] = useState<Record<string, string[]>>({});
  const [detailTherapy, setDetailTherapy] = useState<any>(null);
  const [detailServiceStaff, setDetailServiceStaff] = useState<string[]>([]);
  const [payLines, setPayLines] = useState<{ payment_method_id: string; amount: number; instalment?: InstalmentPortion }[]>([]);
  /** Per-line instalment problems, shown beside the line they belong to. */
  const [payLineErrors, setPayLineErrors] = useState<Record<number, string>>({});
  // The instalment arrangement is chosen where the money is taken now, not at
  // the top of the creation form. It is still invoice-level metadata.
  const [payInstalment, setPayInstalment] = useState<InstalmentDetails>({ instalment_category: '', instalment_method_id: '', instalment_months: '' });
  const [payOutcome, setPayOutcome] = useState<string | null>(null);
  // The day the money actually arrived. Defaults to today in Singapore; a past
  // date is allowed because payment often follows the invoice by days.
  const [payDate, setPayDate] = useState<string>(singaporeToday);
  // A created invoice whose detail view could not be opened. Held so the id is
  // never lost and the operator is never told to create it again.
  const [createdPending, setCreatedPending] = useState<{ id: string; message: string } | null>(null);
  // Set when a correction is refused because the invoice predates stock
  // snapshots. The review replaces the bare error with the actual evidence.
  const [stockReviewFor, setStockReviewFor] = useState<string | null>(null);
  const [payErr, setPayErr] = useState<string | null>(null);
  const [payBusy, setPayBusy] = useState(false);
  const [paymentRequestId, setPaymentRequestId] = useState(() => crypto.randomUUID());
  const [priceReview, setPriceReview] = useState<PriceReviewResult | null>(null);
  const [focReasons, setFocReasons] = useState<FocReason[]>([]);
  const [focBusy, setFocBusy] = useState(false);
  // Phase 13 — edit mode + exchange detail + revision history
  const [editingInvoiceId, setEditingInvoiceId] = useState<string | null>(null);
  // Correcting a SETTLED invoice is a different, Owner/Manager-only operation:
  // it unwinds stock and commission, writes a revision, and needs a reason.
  const [editingPaid, setEditingPaid] = useState(false);
  const [editReason, setEditReason] = useState('');
  // Correcting the affiliate and the payment methods on a settled invoice.
  const [cAffiliate, setCAffiliate] = useState('');
  const [affTouched, setAffTouched] = useState(false);
  // A correction states its effects before it is applied. The case this exists
  // for is the quiet one: a field the operator believes they changed which is
  // not in the payload, which the preview reports as "unchanged".
  const [correctionPreview, setCorrectionPreview] = useState<any | null>(null);
  const [previewing, setPreviewing] = useState(false);
  // Per recorded payment on a correction: what the operator wants it to say.
  // Amount or date changes run through the per-payment rule (reversal +
  // replacement); a method-only change stays in place; "remove" reverses a
  // receipt recorded by mistake. Wallet-credit payments never get an entry.
  const [payEdits, setPayEdits] = useState<Record<string, PayEdit>>({});
  const [statusBeforeEdit, setStatusBeforeEdit] = useState('');
  // Who the invoice is attributed to. Owner only — it changes what a printed
  // document says about who served the customer.
  const [cCreatedBy, setCCreatedBy] = useState('');
  // Snapshots taken when the correction opens: `detail` is cleared at that
  // point, so without these there is nothing to diff against on save.
  const [createdByBeforeEdit, setCreatedByBeforeEdit] = useState('');
  const [paymentsBeforeEdit, setPaymentsBeforeEdit] = useState<InvoicePayment[]>([]);
  const [detailExchange, setDetailExchange] = useState<any>(null);
  const [detailRevisions, setDetailRevisions] = useState<InvoiceRevision[]>([]);
  const [affiliateOptions, setAffiliateOptions] = useState<{ affiliate_id: string; full_name: string; phone: string }[]>([]);
  const [affiliateBusy, setAffiliateBusy] = useState(false);
  const [affiliateErr, setAffiliateErr] = useState<string | null>(null);
  const [effAffiliate, setEffAffiliate] = useState<any>(null);
  const [invLegacy, setInvLegacy] = useState<any[]>([]);
  // Credit Packages and Premium Bundles are now bought inside New Invoice as
  // ordinary line kinds (Phase 31). These hold what is available at the chosen
  // New Invoice store; the reward-voucher options for a selected bundle are
  // loaded lazily and cached by bundle id.
  const [creditPkgs, setCreditPkgs] = useState<any[]>([]);
  const [creditBundles, setCreditBundles] = useState<any[]>([]);
  const [bundleVoucherOpts, setBundleVoucherOpts] = useState<Record<string, any[]>>({});
  const [legacyDiag, setLegacyDiag] = useState<any>(null);
  const [payWallet, setPayWallet] = useState<any>(null);
  const [warehouses, setWarehouses] = useState<any[]>([]);
  const [fulfilBusy, setFulfilBusy] = useState(false);
  const [fulfilErr, setFulfilErr] = useState<string | null>(null);
  const setFulfilment = async (warehouseId: string | null) => {
    if (!detail) return;
    setFulfilBusy(true); setFulfilErr(null);
    const { error } = await supabase.rpc('set_invoice_fulfilment_warehouse',
      { p_invoice_id: detail.id, p_warehouse_id: warehouseId });
    setFulfilBusy(false);
    if (error) { setFulfilErr(error.message); return; }
    noteLocalChangeRef.current([detail.id]);
    const { data: inv } = await supabase.from('invoices').select('*').eq('id', detail.id).single();
    if (inv) await openDetail(inv as Invoice);
    void refreshList({ afterSave: 'The fulfilment warehouse was saved', changed: [detail.id] });
  };
  const [focLine, setFocLine] = useState<InvoiceItem | null>(null);
  const [focQty, setFocQty] = useState(1);
  const [focReasonId, setFocReasonId] = useState('');
  const [focNote, setFocNote] = useState('');
  const [focErr, setFocErr] = useState<string | null>(null);
  const [voucherStorePrices, setVoucherStorePrices] = useState<any[]>([]);
  const [promoStorePrices, setPromoStorePrices] = useState<any[]>([]);

  /**
   * The reference data the forms and labels need: stores, products, prices,
   * payment methods, promotions, staff, the therapy catalogue. Loaded once,
   * when the page opens.
   *
   * It does NOT load invoices. The list is one page of a server-side query,
   * refreshed by refreshList() below. This used to be called loadAll() and was
   * what every save called afterwards — which reloaded the catalogue and left
   * the list exactly as it was (INVOICE_LIST_REFRESH.md). A save must call
   * refreshList(), never this.
   */
  const loadReferenceData = useCallback(async () => {
    setLoading(true);
    const [st, pr, pm, pp, vc, pm2, cg, pit, co, si, prof, myStore, myStoreList, specialRes, trules, utpk, utsp, aset, vsp, psp, focr, services, serviceStores] = await Promise.all([
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      // The customers table is deliberately absent. It was read whole here —
      // one request per thousand rows, every time the page opened — to label
      // list rows the database already labels, and to feed a selector that
      // searches the server itself.
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      fetchAllFrom<any>('store_product_prices', '*', q => q.is('deleted_at', null)),
      supabase.from('vouchers').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotions').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotion_choice_groups').select('*'),
      supabase.from('promotion_items').select('*'),
      supabase.from('promotion_choice_options').select('*'),
      supabase.from('store_inventory').select('store_id,product_id,current_qty'),
      supabase.from('profiles').select('id,full_name,role,work_phone,is_active').is('deleted_at', null).eq('is_active', true),
      supabase.rpc('my_assigned_store_id'),
      supabase.rpc('my_assigned_stores'),
      supabase.from('special_products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('therapy_package_rules').select('*').is('deleted_at', null).eq('is_active', true),
      supabase.from('unlimited_therapy_packages').select('*').is('deleted_at', null).eq('is_active', true).order('duration_months'),
      supabase.from('unlimited_therapy_store_prices').select('*').is('deleted_at', null),
      // Save Earth defaults used to be read here; the feature is withdrawn (330).
      Promise.resolve({ data: null as any }),
      supabase.from('voucher_store_prices').select('*').is('deleted_at', null),
      supabase.from('promotion_store_prices').select('*').is('deleted_at', null),
      supabase.rpc('active_foc_reasons'),
      supabase.from('therapy_services').select('*').eq('is_active', true).order('name'),
      supabase.from('therapy_service_stores').select('*'),
    ]);
    if (!mountedRef.current) return;
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    setPrices(pp as StoreProductPrice[]);
    setVouchers((vc.data as Voucher[]) ?? []);
    setPromotions((pm2.data as Promotion[]) ?? []);
    setChoiceGroups((cg.data as PromotionChoiceGroup[]) ?? []);
    setPromoItems((pit.data as any[]) ?? []);
    setChoiceOptions((co.data as PromotionChoiceOption[]) ?? []);
    setStoreInv((si.data as any[]) ?? []);
    const allProfiles = (prof.data as Profile[]) ?? [];
    setProfiles(allProfiles);
    setAssignedStoreId((myStore.data as string | null) ?? null);
    setMyStores((myStoreList.data as any[]) ?? []);
    setSpecialProducts((specialRes.data as any[]) ?? []);
    setTherapyRules((trules.data as TherapyPackageRule[]) ?? []);
    setTherapyPackages((utpk?.data as any[]) ?? []);
    setTherapyServices((services.data as any[]) ?? []);
    setTherapyServiceStores((serviceStores.data as any[]) ?? []);
    setTherapyPrices((utsp?.data as any[]) ?? []);
    setVoucherStorePrices((vsp.data as any[]) ?? []);
    setPromoStorePrices((psp.data as any[]) ?? []);
    setFocReasons((focr?.data as FocReason[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { void loadReferenceData(); }, [loadReferenceData]);

  const storeName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const customerOf = (id: string | null | undefined) =>
    (id ? customerById[id] : null) ?? null;
  // A whole record if one has been fetched, otherwise the name the list row
  // carried. Either way the row is never left showing a dash for a customer
  // the database just named.
  const custName = (id: string) => customerOf(id)?.full_name ?? nameById[id] ?? '—';
  const prodName = (id: string) => products.find(p => p.id === id)?.name ?? '—';
  const methodName = (id: string) => methods.find(m => m.id === id)?.name ?? '—';
  // Credit Package / Premium Bundle lines carry their name in plan_name_snapshot
  // so a historical invoice keeps its name even if the package is later renamed.
  const creditLineName = (it: any): string | null =>
    it?.line_kind === 'credit_package' ? (it.plan_name_snapshot || 'Credit Package')
    : it?.line_kind === 'premium_bundle' ? (it.plan_name_snapshot || 'Premium Bundle')
    : null;
  const isStaff = profile?.role === 'staff';
  // Staff choose among their assigned stores; with only one, it behaves as
  // before. Owners and Managers use the full store list.
  // With more than one assigned store nothing is preselected: the staff member
  // must choose deliberately, because the store decides the prices, the stock
  // the sale comes out of, and where the invoice is reported.
  const staffMustChooseStore = isStaff && myStores.length > 1;
  const storeOptions = isStaff
    ? myStores.map(m => ({ id: m.store_id, name: m.store_name }))
    : stores.map(s2 => ({ id: s2.id, name: s2.name }));
  const activeStore = isStaff
    ? (staffMustChooseStore ? cStore : (cStore || assignedStoreId || myStores[0]?.store_id || ''))
    : cStore;

  // Credit Packages and Premium Bundles available at the chosen New Invoice
  // store. Reloaded whenever the store changes; the backend RPCs are the single
  // source of truth for availability and price. Changing the store also resets
  // the item lines (see the Store selector), so a package from the previous
  // store can never be silently retained.
  useEffect(() => {
    if (!createOpen || !activeStore) { setCreditPkgs([]); setCreditBundles([]); return; }
    let cancelled = false;
    setCreditPkgs([]); setCreditBundles([]);
    (async () => {
      const [{ data: cp }, { data: pb }] = await Promise.all([
        supabase.rpc('credit_packages_for_store', { p_store_id: activeStore, p_day: null }),
        supabase.rpc('premium_bundles_for_store', { p_store_id: activeStore, p_day: null }),
      ]);
      if (cancelled) return;
      setCreditPkgs((cp as any[]) ?? []);
      setCreditBundles((pb as any[]) ?? []);
    })();
    return () => { cancelled = true; };
  }, [createOpen, activeStore]);

  // Reward-voucher choices for any Premium Bundle line currently selected.
  // Loaded once per bundle and cached; mirrors the old Buy Credit chooser:
  // only vouchers eligible for that bundle AND stocked at this store appear.
  useEffect(() => {
    if (!createOpen || !activeStore) return;
    const need = cLines
      .filter(l => l.kind === 'premium_bundle' && l.premium_bundle_id && !(l.premium_bundle_id in bundleVoucherOpts))
      .map(l => l.premium_bundle_id as string);
    const uniq = Array.from(new Set(need));
    if (uniq.length === 0) return;
    let cancelled = false;
    (async () => {
      const { data: vs } = await supabase.rpc('legacy_reward_voucher_options', { p_store_id: activeStore });
      const opts = (vs as any[]) ?? [];
      const updates: Record<string, any[]> = {};
      for (const bid of uniq) {
        const { data } = await supabase.from('premium_bundle_vouchers').select('voucher_id').eq('bundle_id', bid);
        const ids = ((data as any[]) ?? []).map(x => x.voucher_id);
        updates[bid] = opts.filter(v => ids.includes(v.voucher_id));
      }
      if (!cancelled) setBundleVoucherOpts(prev => ({ ...prev, ...updates }));
    })();
    return () => { cancelled = true; };
  }, [createOpen, activeStore, cLines, bundleVoucherOpts]);

  // A Premium Bundle grants reward vouchers only when it is flagged to and has a
  // non-zero quantity — the same rule validate_bundle_voucher_selection() uses.
  const bundleGrants = (bundleId?: string): number => {
    const b: any = creditBundles.find(x => x.id === bundleId);
    return (b && b.grants_reward) ? (b.free_voucher_qty ?? 0) : 0;
  };
  // Phase 19: one selling price. The former Member Price is the single price.
  const effMember = true;
  // Strict mode-aware pricing (Phase 4): NO fallback to legacy selling_price.
  const priceRowFor = (storeId: string, productId: string) =>
    prices.find(p => p.store_id === storeId && p.product_id === productId);
  const priceFor = (storeId: string, productId: string, _member: boolean = effMember) => {
    const r = priceRowFor(storeId, productId);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };

  // Products available at the chosen store (those with a price).
  const stockQty = (storeId: string, productId: string): number =>
    storeInv.find(s => s.store_id === storeId && s.product_id === productId)?.current_qty ?? 0;

  // D: a product is offered if it has a usable price in SOME mode (auto or via
  // override) and has stock. We classify rather than hide, so an override
  // candidate (e.g. member-only product for a non-member) stays selectable
  // with a clear label. Only truly unpriced/inactive items are dropped.
  const productAvail = (pid: string): { ok: boolean; label: string; needsOverride: boolean } => {
    const r = prices.find(x => x.store_id === activeStore && x.product_id === pid);
    if (!r) return { ok: false, label: 'no price', needsOverride: false };
    const val = r.selling_price ?? r.member_price;
    if (val != null) return { ok: true, label: `${money(val)}`, needsOverride: false };
    return { ok: false, label: 'missing price', needsOverride: false };
  };
  const storeProducts = useMemo(() =>
    activeStore ? products.filter(p => productAvail(p.id).ok && stockQty(activeStore, p.id) > 0) : [],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [activeStore, products, prices, storeInv]);

  const [therapyPrices, setTherapyPrices] = useState<any[]>([]);
  const therapyPrice = (pkgId: string, _member: boolean = effMember): number | null => {
    const r = therapyPrices.find(x => x.package_id === pkgId && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };
  const voucherPrice = (id: string, _member: boolean = effMember) => {
    const r = voucherStorePrices.find(x => x.voucher_id === id && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };

  const promoPrice = (id: string, _member: boolean = effMember) => {
    const r = promoStorePrices.find(x => x.promotion_id === id && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };

  const sessionPrice = (id: string) => {
    const service = therapyServices.find(s => s.id === id);
    const store = therapyServiceStores.find(s => s.service_id === id && s.store_id === activeStore);
    return service && store?.is_available ? Number(store.price_override ?? service.standard_price) : null;
  };
  const lineMember = (_l: LineDraft): boolean => effMember;
  const lineUnit = (l: LineDraft): number | null =>
    l.unit_price !== undefined ? l.unit_price : l.kind === 'special_product' ? (() => {
      const sp = specialProducts.find((x: any) => x.id === l.special_product_id);
      return sp ? Number(sp.sale_price) : null;
    })()
    : l.kind === 'rental' ? (() => {
      const sp = specialProducts.find((x: any) => x.id === l.special_product_id);
      if (!sp) return null;
      const rate = Number(sp[`rate_${l.rental_rate_type ?? 'day'}`] ?? 0);
      return rate > 0 ? rate * Math.max(1, l.rental_periods ?? 1) : null;
    })()
    : l.kind === 'therapy' ? (l.therapy_service_id ? sessionPrice(l.therapy_service_id) : l.therapy_package_id ? therapyPrice(l.therapy_package_id, lineMember(l)) : null)
    : l.kind === 'credit_package' ? (() => {
      const p: any = creditPkgs.find(x => x.id === l.credit_package_id);
      return p ? Number(p.customer_price) : null;
    })()
    : l.kind === 'premium_bundle' ? (() => {
      const b: any = creditBundles.find(x => x.id === l.premium_bundle_id);
      return b ? Number(b.customer_payment_amount) : null;
    })()
    : l.kind === 'voucher' ? (l.voucher_id ? voucherPrice(l.voucher_id, lineMember(l)) : null)
    : l.kind === 'promotion' ? (l.promotion_id ? promoPrice(l.promotion_id, lineMember(l)) : null)
    : (activeStore && l.product_id ? priceFor(activeStore, l.product_id, lineMember(l)) : null);

  // Phase 12 — the charged quantity is what the customer actually pays for.
  const paidQty = (l: LineDraft) => Math.max(0, l.quantity - (l.foc_quantity ?? 0));
  const focValuePreview = useMemo(() =>
    cLines.reduce((sum, l) => {
      const price = lineUnit(l);
      return sum + (price ? price * (l.foc_quantity ?? 0) : 0);
    }, 0),
    [cLines, activeStore, prices, vouchers, promotions, voucherStorePrices, promoStorePrices, therapyPrices, therapyPackages, creditPkgs, creditBundles]);
  const createSubtotal = useMemo(() =>
    cLines.reduce((sum, l) => {
      const price = lineUnit(l);
      return sum + (price ? price * paidQty(l) : 0);
    }, 0),
    // B: every input that can change a line's applied price must be here,
    // or totals go stale when the pricing mode flips.
    [cLines, activeStore, prices, vouchers, promotions, voucherStorePrices, promoStorePrices, therapyPrices, therapyPackages, creditPkgs, creditBundles]);

  // Discount vouchers selectable for redemption (fixed/percentage kinds).
  // Discount slots only show vouchers valid TODAY (not-yet-valid and expired are hidden).
  // They can still be SOLD as line items (the buyer redeems later, once valid).
  const isDateValid = (v: Voucher) => {
    const d = new Date();
    const today = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    return (!v.valid_from || v.valid_from <= today) && (!v.valid_until || v.valid_until >= today);
  };
  const discountVouchers = useMemo(() => vouchers.filter(v => v.voucher_kind !== 'normal' && isDateValid(v)), [vouchers]);

  const groupsFor = (promoId: string) => choiceGroups.filter(g => g.promotion_id === promoId);
  // The promotion's fixed contents. These are always part of the bundle and are
  // not chosen by the cashier, so they were never rendered — which made the
  // invoice look as though half the bundle was missing.
  const includedFor = (promoId: string) => promoItems
    .filter(i => i.promotion_id === promoId)
    .map(i => {
      const label =
        i.item_type === 'product' ? (products.find(p => p.id === i.product_id)?.name ?? 'Product')
        : i.item_type === 'voucher' ? (vouchers.find(v => v.id === i.voucher_id)?.name ?? 'Voucher')
        : i.item_type === 'promotion' ? (promotions.find(p => p.id === i.child_promotion_id)?.name ?? 'Promotion')
        : i.item_type === 'therapy' ? (therapyPackages.find((t: any) => t.id === i.therapy_package_id)?.name ?? 'Therapy')
        : i.item_type === 'credit_package' ? 'Credit package'
        : (i.treatment_name ?? 'Item');
      return { id: i.id, label, qty: i.quantity, kind: i.item_type };
    });
  const optionsFor = (groupId: string) => choiceOptions.filter(o => o.group_id === groupId);
  const selSum = (l: LineDraft, gId: string) => Object.values(l.selections[gId] ?? {}).reduce((s, n) => s + (n || 0), 0);

  // Baseline of a product group, following the group's OWN base_mode.
  //
  // This previously always took the cheapest option, ignoring base_mode — so a
  // group set to "highest" showed one top-up on screen and the database
  // computed another when the invoice was saved. promotion_selections_topup()
  // has always honoured base_mode; only this preview did not.
  //
  // G: baseline follows the applied pricing mode — a top-up computed under the
  // previous mode is never reused (the memo recomputes on mode change).
  // C: baseline resolves in the promotion LINE's applied mode, not the
  // invoice-wide automatic mode.
  const groupBaseline = (gId: string, member: boolean = effMember): number | null => {
    if (!activeStore) return null;
    const opts = optionsFor(gId)
      .map(o => (o.product_id ? priceFor(activeStore, o.product_id, member) : null))
      .filter((p): p is number => p != null);
    if (!opts.length) return null;
    const highest = (choiceGroups.find(g => g.id === gId) as any)?.base_mode === 'highest';
    return highest ? Math.max(...opts) : Math.min(...opts);
  };

  // 3rd-party product lines cannot be discounted by VOUCHERS. Since migration 99
  // a manual discount does apply to them, so this sum is the voucher base only.
  const isThirdParty = (productId: string) => products.find(p => p.id === productId)?.product_type === 'third_party';
  const thirdPartySum = useMemo(() =>
    cLines.reduce((s, l) => {
      if (l.kind !== 'product' || !l.product_id || !isThirdParty(l.product_id)) return s;
      const u = lineUnit(l);
      return s + (u ? u * paidQty(l) : 0);
    }, 0), [cLines, activeStore, prices, products]);

  // Total top-up across all promotion lines (mirrors promotion_selections_topup).
  const topupPreview = useMemo(() => {
    if (!activeStore) return 0;
    let sum = 0;
    for (const l of cLines) {
      if (l.kind !== 'promotion' || !l.promotion_id) continue;
      if (unchangedDraft(l)) { sum += l.saved_topup || 0; continue; }
      const lm = effMember;
      for (const g of groupsFor(l.promotion_id)) {
        if (g.item_kind !== 'product') continue;
        const baseline = groupBaseline(g.id, lm);
        if (baseline == null) continue;
        // Listed options never pay a top-up — only picks outside the options do.
        const listed = new Set(optionsFor(g.id).map(o => o.product_id).filter(Boolean));
        for (const [pid, q] of Object.entries(l.selections[g.id] ?? {})) {
          if (!q || listed.has(pid)) continue;
          const pr = priceFor(activeStore, pid, lm);
          if (pr != null && pr > baseline) sum += (pr - baseline) * q;
        }
      }
    }
    return sum;
  }, [cLines, activeStore, prices, choiceGroups, choiceOptions]);

  // Mirror of SQL voucher_discount_amount for previews.
  const voucherDiscAmount = (v: Voucher | undefined, base: number): number => {
    if (!v) return 0;
    let disc = 0;
    if (v.voucher_kind === 'fixed_discount') {
      disc = v.discount_amount ?? 0;
      if (base <= disc) return 0;   // fixed vouchers need the base STRICTLY above
    }
    else if (v.voucher_kind === 'percentage_discount') {
      disc = Math.round(base * (v.discount_percent ?? 0)) / 100;
      if (v.max_discount_cap != null && disc > v.max_discount_cap) disc = v.max_discount_cap;
    }
    if (disc > base) disc = base;
    return disc < 0 ? 0 : disc;
  };

  // Per-line voucher discounts (product lines only).
  const lineVoucherDiscountPreview = useMemo(() =>
    cLines.reduce((sum, l) => {
      if (l.kind !== 'product' || !l.line_voucher_id) return sum;
      const unit = lineUnit(l);
      if (!unit) return sum;
      // Discounts apply to the PAID value only.
      return sum + voucherDiscAmount(vouchers.find(v => v.id === l.line_voucher_id), unit * paidQty(l));
    }, 0), [cLines, vouchers, activeStore, prices, voucherStorePrices, promoStorePrices]);

  // Whole-invoice voucher: base = subtotal − manual − line-voucher discounts (matches SQL).
  const voucherDiscountPreview = useMemo(() => {
    if (!cDiscountVoucher) return 0;
    // A discount voucher still cannot reach third-party value; the manual
    // discount is taken off first.
    const base = Math.max(0, createSubtotal + topupPreview - thirdPartySum - (cDiscount || 0) - lineVoucherDiscountPreview);
    return voucherDiscAmount(vouchers.find(x => x.id === cDiscountVoucher), base);
  }, [cDiscountVoucher, vouchers, createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview]);

  const hasPromoLine = useMemo(() => cLines.some(l => l.kind === 'promotion' && l.promotion_id), [cLines]);

  // Whole-invoice voucher eligibility: fixed vouchers need the discountable
  // base (excl. 3rd-party lines) to be STRICTLY above their amount.
  const wholeVoucherBase = useMemo(() =>
    Math.max(0, createSubtotal + topupPreview - thirdPartySum - (cDiscount || 0) - lineVoucherDiscountPreview),
    [createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview]);
  const eligibleWholeVouchers = useMemo(() =>
    discountVouchers.filter(v => v.voucher_kind !== 'fixed_discount' || (v.discount_amount ?? 0) < wholeVoucherBase),
    [discountVouchers, wholeVoucherBase]);
  useEffect(() => {
    if (!editingInvoiceId && cDiscountVoucher && !eligibleWholeVouchers.some(v => v.id === cDiscountVoucher)) setCDiscountVoucher('');
  }, [cDiscountVoucher, eligibleWholeVouchers]);
  useEffect(() => { if (!editingInvoiceId && hasPromoLine && cDiscountVoucher) setCDiscountVoucher(''); }, [hasPromoLine, cDiscountVoucher]);

  const previewTotal = useMemo(() => {
    // Mirrors migration 99: a MANUAL discount applies to the whole invoice,
    // third-party included; a VOUCHER discount keeps the narrower base.
    const gross = createSubtotal + topupPreview - lineVoucherDiscountPreview;
    const manual = Math.min(cDiscount || 0, Math.max(0, gross));
    const voucherBase = Math.max(0, createSubtotal + topupPreview - thirdPartySum - lineVoucherDiscountPreview - manual);
    const invLevel = manual + Math.min(voucherDiscountPreview, voucherBase);
    return Math.max(0, gross - invLevel);
  }, [createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview, voucherDiscountPreview]);


  // All vouchers can be sold as a line item (a discount voucher sold now is
  // redeemed by the buyer on a future invoice). Only discount vouchers can be
  // used in the Discount Voucher slot (Normal vouchers have no discount value).
  const sellableVouchers = useMemo(() => vouchers, [vouchers]);

  const resetCreate = () => {
    // Blank when there is a real choice to make.
    setCStore(isStaff && myStores.length === 1
      ? (myStores[0]?.store_id ?? assignedStoreId ?? '') : '');
    setCCustomer(''); setCBusinessDate(singaporeToday()); setCNotes('');
    setIssuedRecipientsConfirmed(false); setIssuedHeaderBefore(null);
    setCInstalment({ instalment_category: '', instalment_method_id: '', instalment_months: '' });
    setEditRequestId(crypto.randomUUID());
    setOriginalDrafts([]); setAffTouched(false); setCAffiliate(''); setCorrectionPreview(null); setBenefitAction(''); setPayEdits({}); setPaymentsBeforeEdit([]); setStatusBeforeEdit(''); setCCreatedBy(''); setCreatedByBeforeEdit('');
    setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); setCDiscount(0);
    setCDiscountVoucher(''); setCServiceStaff([]); setCErr(null);
    setCDiscountReason(''); setDiscountReasonErr(null); setDiscountBeforeEdit(0);
    setEditConflict(null); editBaseRef.current = null;
  };

  // What the correction sends about money. Amount or date changes go through
  // the per-payment rule (the original receipt stays; a reversal and a
  // replacement are recorded); a method-only change stays in place as before;
  // a removal is a reversal with no replacement and no refund.
  const paymentChanges = () => {
    const payment_methods: { payment_id: string; payment_method_id: string }[] = [];
    const payment_corrections: ({ payment_id: string; amount: number; date: string; payment_method_id: string }
      | { payment_id: string; parts: { amount: number; date: string; payment_method_id: string }[] })[] = [];
    const payment_removals: string[] = [];
    for (const p of paymentsBeforeEdit) {
      const e = payEdits[p.id];
      if (!e) continue;
      if (e.remove) { payment_removals.push(p.id); continue; }
      if (e.parts.length > 1) {
        // A split: every part is a replacement of this payment.
        payment_corrections.push({ payment_id: p.id, parts: e.parts.map(x => ({ amount: Number(x.amount), date: x.date, payment_method_id: x.payment_method_id })) });
        continue;
      }
      const one = e.parts[0];
      const amountChanged = Math.abs(Number(one.amount) - Number(p.amount)) > 0.004;
      const dateChanged = one.date !== sgDateOf(p);
      if (amountChanged || dateChanged) {
        payment_corrections.push({ payment_id: p.id, amount: Number(one.amount), date: one.date, payment_method_id: one.payment_method_id });
      } else if (one.payment_method_id !== p.payment_method_id) {
        payment_methods.push({ payment_id: p.id, payment_method_id: one.payment_method_id });
      }
    }
    return { payment_methods, payment_corrections, payment_removals };
  };

  const handleCreate = async () => {
    // A second click while the first is in flight would create a second invoice.
    if (cSaving) return;
    if (!editingInvoiceId && !cBusinessDate) { setCErr('Choose the invoice business date.'); return; }
    const instalmentError = validateInstalment(cInstalment);
    if (instalmentError) { setCErr(instalmentError); return; }
    if (isStaff && myStores.length === 0) { setCErr('You are not assigned to a store, so you cannot create invoices. Ask an Owner or Manager to assign you.'); return; }
    const effectiveStore = isStaff
      ? (staffMustChooseStore ? cStore : (cStore || assignedStoreId || myStores[0]?.store_id || ''))
      : cStore;
    if (!effectiveStore) { setCErr('Choose which store this invoice belongs to.'); return; }
    if (!effectiveStore) { setCErr('Select a store.'); return; }
    if (!cCustomer) { setCErr('Select a customer.'); return; }
    const activeLines = cLines.filter(l => l.quantity > 0 && (
      l.kind === 'product' ? l.product_id
      : l.kind === 'voucher' ? l.voucher_id
      : l.kind === 'therapy' ? (l.therapy_service_id || l.therapy_package_id)
      : (l.kind === 'special_product' || l.kind === 'rental') ? l.special_product_id
      : l.kind === 'credit_package' ? l.credit_package_id
      : l.kind === 'premium_bundle' ? l.premium_bundle_id
      : l.promotion_id));
    if (activeLines.length === 0) { setCErr('Add at least one product, voucher, promotion, therapy, credit package or premium bundle line.'); return; }
    // Choice-group completeness check (client-side; server re-validates).
    for (const l of activeLines) {
      if (l.kind !== 'promotion' || unchangedDraft(l)) continue;
      for (const g of groupsFor(l.promotion_id)) {
        const need = g.choose_qty * l.quantity;
        const got = selSum(l, g.id);
        if (got !== need) {
          setCErr(`"${promotions.find(p => p.id === l.promotion_id)?.name}" — ${g.label}: choose exactly ${need} (currently ${got}).`);
          return;
        }
      }
    }
    // Reward-voucher completeness for Premium Bundles (server re-validates via
    // validate_bundle_voucher_selection). Only bundles that grant vouchers.
    for (const l of activeLines) {
      if (l.kind !== 'premium_bundle' || unchangedBenefitDefinition(l)) continue;
      const need = bundleGrants(l.premium_bundle_id);
      if (need <= 0) continue;
      const got = Object.values(l.bundle_voucher_selection ?? {}).reduce((a, c) => a + (c || 0), 0);
      if (got !== need) {
        const b: any = creditBundles.find(x => x.id === l.premium_bundle_id);
        setCErr(`"${b?.name ?? 'Premium bundle'}" — choose exactly ${need} reward voucher(s) (currently ${got}).`);
        return;
      }
    }
    const ovr = (l: LineDraft) => ({ invoice_item_id: l.invoice_item_id || null, ...(l.unit_price !== undefined ? { unit_price: l.unit_price } : {}) });
    // Phase 12 — FOC travels with the line. `quantity` stays the full quantity;
    // the server derives the charged value from (quantity - foc_quantity).
    const foc = (l: LineDraft) => (l.foc_quantity ?? 0) > 0
      ? { foc_quantity: l.foc_quantity, foc_reason_id: l.foc_reason_id || null, foc_reason: l.foc_reason || null }
      : {};
    const validLines = activeLines.map(l => l.kind === 'voucher'
      ? { kind: 'voucher', voucher_id: l.voucher_id, quantity: l.quantity, ...ovr(l), ...foc(l) }
      : l.kind === 'promotion'
      ? {
          kind: 'promotion', promotion_id: l.promotion_id, quantity: l.quantity,
          selections: Object.keys(l.selections).map(groupId => {
            const g = groupsFor(l.promotion_id).find(g => g.id === groupId);
            const saved = detailSelections.find(s => s.invoice_item_id === l.invoice_item_id && s.group_id === groupId);
            return ({
            group_id: groupId,
            options: Object.entries(l.selections[groupId] ?? {})
              .filter(([, q]) => (q || 0) > 0)
              .map(([itemId, q]) => {
                // Which column the picked id belongs in is decided by the
                // group's kind. It used to be product-or-voucher only, so a
                // therapy, credit-package or promotion pick was sent as a
                // voucher and refused by the server.
                const kind = g?.item_kind ?? (saved?.product_id ? 'product' : 'voucher');
                const blank = {
                  product_id: null as string | null, voucher_id: null as string | null,
                  therapy_package_id: null as string | null, credit_package_id: null as string | null,
                  child_promotion_id: null as string | null,
                };
                switch (kind) {
                  case 'voucher':        return { ...blank, voucher_id: itemId, quantity: q };
                  case 'therapy':        return { ...blank, therapy_package_id: itemId, quantity: q };
                  case 'credit_package': return { ...blank, credit_package_id: itemId, quantity: q };
                  case 'promotion':      return { ...blank, child_promotion_id: itemId, quantity: q };
                  default:               return { ...blank, product_id: itemId, quantity: q };
                }
              }),
          }); }),
          ...ovr(l), ...foc(l),
        }
      : l.kind === 'therapy'
      ? { kind: 'therapy', therapy_package_id: l.therapy_service_id ? null : l.therapy_package_id, therapy_service_id: l.therapy_service_id || null, quantity: l.therapy_service_id ? l.quantity : 1,
          // Absent means "choose later" — the server treats a missing intent
          // as no choice rather than as a default.
          therapy_benefit_intent: l.therapy_benefit_intent || null, ...ovr(l), ...foc(l) }
      : l.kind === 'credit_package'
      ? { kind: 'credit_package', credit_package_id: l.credit_package_id, quantity: 1, ...ovr(l), ...foc(l) }
      : l.kind === 'premium_bundle'
      ? { kind: 'premium_bundle', premium_bundle_id: l.premium_bundle_id, quantity: 1, ...ovr(l), ...foc(l),
          // Saved selections remain evidence even if the current bundle's
          // voucher quantity changed or the catalogue entry was retired.
          voucher_selection: Object.entries(l.bundle_voucher_selection ?? {})
                .filter(([, q]) => (q || 0) > 0)
                .map(([voucher_id, quantity]) => ({ voucher_id, quantity }))
        }
      : l.kind === 'special_product'
      ? { kind: 'special_product', special_product_id: l.special_product_id, quantity: l.quantity, ...ovr(l), ...foc(l) }
      : l.kind === 'rental'
      ? { kind: 'rental', special_product_id: l.special_product_id, quantity: l.quantity,
          rental_rate_type: l.rental_rate_type ?? 'day',
          rental_periods: Math.max(1, l.rental_periods ?? 1),
          rental_start_date: l.rental_start_date || null,
          rental_return_date: l.rental_return_date || null,
          ...ovr(l), ...foc(l) }
      : { kind: 'product', product_id: l.product_id, quantity: l.quantity, line_voucher_id: (l.line_voucher_id && !isThirdParty(l.product_id)) ? l.line_voucher_id : null, ...ovr(l), ...foc(l) });
    const focMissing = activeLines.find(l => (l.foc_quantity ?? 0) > 0 && !l.foc_reason_id && !(l.foc_reason ?? '').trim());
    if (focMissing) { setCErr('A FOC reason is required on every FOC line.'); return; }
    const allItems: any[] = validLines.filter(Boolean);
    // create_invoice requires at least one product/voucher/promotion line
    // to open the invoice. Therapy is added right after. For a therapy-ONLY sale,
    // create the invoice, then it gets the therapy line — but we need a seed, so
    // require another line, OR fall back to creating an empty
    // invoice shell is not supported. Guide the user in that rare case.

    setCSaving(true); setCErr(null);
    // Phase 13: the same payload edits an existing unpaid invoice in place —
    // update_invoice revalidates every rule exactly as create_invoice does.
    if (editingPaid && !editReason.trim()) {
      setCErr('Give a reason for the invoice correction — it is kept in the revision history.');
      setCSaving(false); return;
    }
    // The same rule the server enforces: a positive discount that is new, or
    // changed, needs a reason. An unchanged historical one does not.
    const needsDiscountReason = (cDiscount || 0) > 0
      && (!editingInvoiceId || Number(cDiscount) !== Number(discountBeforeEdit));
    if (needsDiscountReason && !cDiscountReason.trim()) {
      setDiscountReasonErr('Give the internal reason for this manual discount.');
      setCErr('A manual discount needs a reason before the invoice can be saved.');
      setCSaving(false);
      setReasonFocusTick(t => t + 1);
      return;
    }

    // Each payment kept needs a positive amount and the date it was received;
    // the server refuses anything else, so say it here first.
    if (editingInvoiceId && paymentsBeforeEdit.some(p => {
      const e = payEdits[p.id];
      return e && !e.remove && (e.parts.length === 0 || e.parts.some(x => !(Number(x.amount) > 0) || !x.date));
    })) {
      setCErr('Each payment kept — and each part of a split — needs a positive amount and the date it was received. To take a payment out, mark it as recorded by mistake.');
      setCSaving(false); return;
    }
    // Another user or tab changed this invoice while it was being edited. The
    // server refuses a stale save anyway; asking for the review here first
    // keeps the entries and makes the refusal not the first anyone hears of it.
    if (editingInvoiceId && editConflict && !editConflict.reviewed) {
      setCErr('This invoice was changed by another user or tab. Review the current invoice (above) before saving.');
      setCSaving(false); return;
    }

    const header = {
      customer_id: cCustomer, store_id: effectiveStore, notes: cNotes || null,
      preserve_issued_recipients: issuedRecipientsConfirmed,
      ...(benefitAction ? { benefit_action: benefitAction } : {}),
      manual_discount: cDiscount || 0, discount_voucher_id: cDiscountVoucher || null,
      service_staff: cServiceStaff, business_date: cBusinessDate || null,
      instalment_category: cInstalment.instalment_category || null,
      instalment_method_id: cInstalment.instalment_method_id || null,
      instalment_months: cInstalment.instalment_months || null,
      // Internal. Sent only with a positive discount; the server refuses a
      // positive discount without one and clears it when the discount goes.
      manual_discount_reason: (cDiscount || 0) > 0 ? cDiscountReason.trim() : null,
      ...(editingInvoiceId ? { expected_edit_count: expectedEditCount } : {}),
      ...(affTouched ? { affiliate_id: cAffiliate || null } : {}),
      ...(cCreatedBy && cCreatedBy !== createdByBeforeEdit ? { created_by: cCreatedBy } : {}),
      ...paymentChanges(),
    };
    // Show what the correction will do before doing it. Confirming from the
    // summary calls back in with the preview already shown.
    if (editingInvoiceId && !correctionPreview) {
      setPreviewing(true);
      const { data: pv, error: pErr } = await supabase.rpc('preview_invoice_correction',
        { p_invoice_id: editingInvoiceId, p_header: header });
      setPreviewing(false); setCSaving(false);
      if (pErr) { setCErr(pErr.message); return; }
      setCorrectionPreview(pv);
      return;
    }
    const { data, error } = editingInvoiceId
      ? await supabase.rpc('correct_invoice', { p_invoice_id: editingInvoiceId, p_items: allItems,
          p_header: header, p_reason: editReason.trim() || null, p_request_id: editRequestId })
      : await supabase.rpc('create_invoice_with_details', { p_store_id: effectiveStore, p_customer_id: cCustomer,
          p_items: allItems, p_header: header });
    setCSaving(false);
    if (error) {
      setCErr(error.message);
      setCorrectionPreview(null);
      // Someone else saved this invoice first (expected_edit_count). Say so
      // where the entries are, with the review, rather than as a bare refusal.
      if (editingInvoiceId && /changed by another user/i.test(error.message)) markEditConflict();
      // The server's refusal names the field; put the cursor in it.
      if (/MANUAL_DISCOUNT_REASON_REQUIRED/.test(error.message)) {
        setDiscountReasonErr('Give the internal reason for this manual discount.');
        setReasonFocusTick(t => t + 1);
      }
      // This particular refusal has a way forward, so offer it rather than
      // leaving a message the operator can do nothing with.
      if (editingInvoiceId && /Historical component snapshots need review/i.test(error.message)) {
        setStockReviewFor(editingInvoiceId);
      }
      return;
    }
    const newInvoiceId = editingInvoiceId ? null : (typeof data === 'string' ? data : (data as any)?.id ?? null);
    noteLocalChangeRef.current([newInvoiceId ?? editingInvoiceId].filter(Boolean) as string[]);
    setCorrectionPreview(null);
    setCreateOpen(false); resetCreate(); setEditingInvoiceId(null);
    setEditingPaid(false); setEditReason('');
    if (newInvoiceId) {
      // Creation succeeded. Continue into the invoice that was just made rather
      // than dropping back to the list, and let its own detail view say what it
      // needs — a payment, or an FOC confirmation, or nothing.
      const { data: invRow, error: openError } = await supabase.from('invoices').select('*').eq('id', newInvoiceId).single();
      if (openError || !invRow) {
        // The invoice EXISTS. Saying creation failed here, or inviting another
        // attempt, is how a duplicate gets made.
        setCreatedPending({ id: newInvoiceId, message: 'The invoice was created but could not be opened just now. It is saved — open it to continue.' });
      } else {
        await openDetail(invRow as Invoice);
      }
    }
    void refreshList({ afterSave: editingInvoiceId ? 'The correction was saved' : 'The invoice was created',
      changed: [newInvoiceId ?? editingInvoiceId].filter(Boolean) as string[] });
  };

  // Phase 13 — prefill the builder modal from an unpaid invoice and switch it
  // into edit mode. Store is shown but locked; number/date never change.
  /* Which actions this invoice actually supports.
   *
   * Derived from the recorded financial and lifecycle state, not from
   * paid_amount: a refunded invoice has its paid amount back at zero and must
   * not fall into the ordinary unpaid-edit path because of it. The server
   * enforces the same rules; this only decides what to offer. */
  const financialState = detailFinancial as any;
  const netReceived = Number(financialState?.net_received ?? 0);
  const refundedAmount = Number(financialState?.refunded ?? 0);
  const settledHistory = detailPayments.length > 0 || netReceived > 0 || refundedAmount > 0;
  const auditedStatuses = ['paid', 'partially_paid', 'cancelled', 'refunded',
    'cancellation_requested', 'refund_requested', 'completed_foc'];
  const needsAuditedCorrection = Boolean(detail) && (
    auditedStatuses.includes(String(detail?.status)) || settledHistory
    || Boolean((detail as any)?.is_topup) || Boolean((detail as any)?.is_exchange));
  const canEditOrdinary = Boolean(detail) && !needsAuditedCorrection
    && ['draft', 'unpaid'].includes(String(detail?.status));
  // Something is refundable only when money or credit is actually still held.
  const hasRefundablePayment = netReceived > 0;
  const cancellable = Boolean(detail) && !['cancelled', 'refunded'].includes(String(detail?.status));
  const canManageInvoice = isOwnerOrManager(profile?.role);
  const refundCancelButton = detail && canManageInvoice ? (
    <button className="btn invoice-refund-cancel" onClick={() => setGuidedOpen(true)}
      title="Cancel this invoice, or record a refund">
      <FileText size={14} /> Refund / Cancel</button>
  ) : null;

  const openEdit = () => {
    if (!detail) return;
    const selByItem: Record<string, Record<string, Record<string, number>>> = {};
    for (const s0 of detailSelections) {
      const it = s0.invoice_item_id as string, g = s0.group_id as string;
      // Whatever the group offered. Reading only product-or-voucher silently
      // dropped a therapy, credit-package or promotion choice when an invoice
      // was reopened or corrected, so the cashier was shown an unanswered group
      // and the original pick was lost on save.
      const key = (s0.product_id ?? s0.voucher_id ?? (s0 as any).therapy_package_id
                ?? (s0 as any).credit_package_id ?? (s0 as any).child_promotion_id) as string;
      if (!key) continue;
      selByItem[it] = selByItem[it] ?? {};
      selByItem[it][g] = selByItem[it][g] ?? {};
      selByItem[it][g][key] = (selByItem[it][g][key] ?? 0) + Number(s0.quantity ?? 0);
    }
    const lines: LineDraft[] = [];
    for (const it of detailItems) {
      const ovr = { invoice_item_id: it.id, unit_price: Number(it.unit_price), saved_topup: Number((it as any).topup_amount ?? 0) };
      const foc = Number(it.foc_quantity ?? 0) > 0
        ? { foc_quantity: Number(it.foc_quantity), foc_reason_id: (it as any).foc_reason_id ?? '', foc_reason: it.foc_reason ?? '' }
        : {};
      if (it.line_kind === 'therapy') {
        lines.push({ kind: 'therapy', product_id: '', voucher_id: '', promotion_id: '', therapy_package_id: (it as any).therapy_package_id ?? '', therapy_service_id: (it as any).therapy_service_id ?? '', therapy_service_name: (it as any).therapy_service_name_snapshot ?? '', quantity: it.quantity, line_voucher_id: '', selections: {}, ...ovr, ...foc });
      } else if (it.line_kind === 'credit_package') {
        lines.push({ kind: 'credit_package', product_id: '', voucher_id: '', promotion_id: '', credit_package_id: (it as any).credit_package_id ?? '', quantity: 1, line_voucher_id: '', selections: {}, ...ovr });
      } else if (it.line_kind === 'premium_bundle') {
        // Rebuild the reward-voucher basket from the stored selection so editing
        // shows what was chosen and re-validates against the same rule.
        const basket: Record<string, number> = {};
        const raw = (it as any).bundle_voucher_selection;
        const arr = Array.isArray(raw) ? raw : (typeof raw === 'string' ? (() => { try { return JSON.parse(raw); } catch { return []; } })() : []);
        for (const s of (arr as any[])) { if (s && s.voucher_id) basket[s.voucher_id] = (basket[s.voucher_id] ?? 0) + Number(s.quantity ?? 0); }
        lines.push({ kind: 'premium_bundle', product_id: '', voucher_id: '', promotion_id: '', premium_bundle_id: (it as any).premium_bundle_id ?? '', bundle_voucher_selection: basket, quantity: 1, line_voucher_id: '', selections: {}, ...ovr });
      } else if (it.line_kind === 'voucher') {
        lines.push({ kind: 'voucher', product_id: '', voucher_id: (it as any).voucher_id ?? '', promotion_id: '', quantity: it.quantity, line_voucher_id: '', selections: {}, ...ovr, ...foc });
      } else if (it.line_kind === 'promotion') {
        lines.push({ kind: 'promotion', product_id: '', voucher_id: '', promotion_id: (it as any).promotion_id ?? '', quantity: it.quantity, line_voucher_id: '', selections: selByItem[it.id] ?? {}, ...ovr, ...foc });
      } else if (it.line_kind === 'special_product' || it.line_kind === 'rental') {
        // Without this branch a special or rental line fell through to
        // 'product' with an empty product_id, and reopening the invoice
        // rendered a line the rest of the form could not describe.
        lines.push({ kind: it.line_kind as LineDraft['kind'], product_id: '', voucher_id: '', promotion_id: '',
          special_product_id: (it as any).special_product_id ?? '',
          rental_rate_type: (it as any).rental_rate_type ?? 'day',
          rental_periods: Number((it as any).rental_periods ?? 1),
          rental_start_date: (it as any).rental_start_date
            ? String((it as any).rental_start_date).slice(0, 10) : '',
          rental_return_date: (it as any).rental_return_date
            ? String((it as any).rental_return_date).slice(0, 10) : '',
          quantity: it.quantity, line_voucher_id: '', selections: {}, ...ovr, ...foc });
      } else {
        lines.push({ kind: 'product', product_id: it.product_id ?? '', voucher_id: '', promotion_id: '', quantity: it.quantity, line_voucher_id: (it as any).line_voucher_id ?? '', selections: {}, ...ovr, ...foc });
      }
    }
    setOriginalDrafts(lines);
    setCStore(detail.store_id);
    setCBusinessDate((detail as any).business_date ?? ''); setCNotes((detail as any).notes ?? '');
    setCInstalment({ instalment_category: (detail as any).instalment_category ?? '',
      instalment_method_id: (detail as any).instalment_method_id ?? '', instalment_months: (detail as any).instalment_months ?? '' });
    setExpectedEditCount((detail as any).edit_count ?? 0); setEditRequestId(crypto.randomUUID());
    editBaseRef.current = detail; setEditConflict(null);
    setCCustomer(detail.customer_id);
    setIssuedRecipientsConfirmed(false);
    // What counts as "this invoice issued benefits" is decided by the server
    // (322), and it means vouchers, credit and allowances — not credit alone.
    // The form used to test invoice items for credit_issued_at, which is the
    // predicate 322 replaced, so a voucher-only invoice was refused for a
    // choice it never offered. Ask the same function the refusal comes from.
    setIssuedHeaderBefore(null);
    setBenefitAction('');
    void (async () => {
      const { data } = await supabase.rpc('invoice_transferable_benefits', { p_invoice_id: detail.id });
      if (!((data as any[]) ?? []).length) return;
      setIssuedHeaderBefore({ customer: detail.customer_id, store: detail.store_id });
      // Moving them with the customer is what a reassignment almost always
      // means, so it is offered ready to save. Keeping them is still one click
      // away, because the two outcomes are not interchangeable.
      setBenefitAction('transfer');
      setIssuedRecipientsConfirmed(true);
    })();
    setCLines(lines.length ? lines : [{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]);
    setCDiscount(Number((detail as any).manual_discount ?? 0));
    setCDiscountVoucher((detail as any).discount_voucher_id ?? '');
    // Restored exactly as saved, so an unrelated edit cannot erase it. The
    // amount at open decides whether a reason is demanded on save: only a
    // changed positive amount needs one, so history is never asked to invent.
    setCDiscountReason(String((detail as any).manual_discount_reason ?? ''));
    setDiscountReasonErr(null);
    setDiscountBeforeEdit(Number((detail as any).manual_discount ?? 0));
    setCServiceStaff(detailServiceStaff);
    setEditingInvoiceId(detail.id);
    setEditingPaid(!['draft', 'unpaid'].includes(String(detail.status)) || detailPayments.length > 0);
    setEditReason('');
    setCAffiliate((detail as any).affiliate_id ?? '');
    setAffTouched(false);
    {
      // Only payments still standing are offered; a reversed entry and the
      // receipt it superseded are history.
      const current = currentPaymentsOf(detailPayments);
      setPayEdits(Object.fromEntries(current
        .filter(p2 => !(methods.find(m => m.id === p2.payment_method_id) as any)?.is_wallet_credit)
        .map(p2 => [p2.id, { parts: [{ amount: Number(p2.amount).toFixed(2), date: sgDateOf(p2), payment_method_id: p2.payment_method_id }], remove: false }])));
      setPaymentsBeforeEdit(current);
      setStatusBeforeEdit(String(detail.status));
    }
    setCCreatedBy((detail as any).created_by ?? '');
    setCreatedByBeforeEdit((detail as any).created_by ?? '');
    void loadAffiliateOptions();
    setDetail(null);
    setCErr(null);
    setCreateOpen(true);
  };

  const loadAffiliateOptions = async () => {
    const { data } = await supabase.rpc('active_affiliates_for_picker');
    setAffiliateOptions((data as any[]) ?? []);
  };

  // The affiliate that will actually be credited: the explicit choice on the
  // invoice, or the customer's own referrer (Tier 1) when nothing is chosen.
  const loadEffectiveAffiliate = async (invoiceId: string) => {
    const { data } = await supabase.rpc('invoice_effective_affiliate', { p_invoice_id: invoiceId });
    setEffAffiliate(data ?? null);
  };

  // Legacy therapy this invoice's same-day qualification earned the customer.
  const loadInvoiceLegacy = async (invoiceId: string, inv?: Invoice) => {
    const { data } = await supabase.rpc('invoice_legacy_entitlements', { p_invoice_id: invoiceId });
    setInvLegacy((data as any[]) ?? []);
    // If nothing was earned, find out why so staff aren't left guessing.
    const src = inv ?? detail;
    if ((!data || (data as any[]).length === 0) && src?.customer_id && src?.store_id) {
      const day = src.paid_at ? new Date(src.paid_at).toISOString().slice(0, 10) : null;
      const { data: dg } = await supabase.rpc('legacy_qualification_diagnose', {
        p_customer_id: src.customer_id, p_store_id: src.store_id, p_day: day,
      });
      setLegacyDiag(dg ?? null);
    } else {
      setLegacyDiag(null);
    }
  };

  const changeInvoiceAffiliate = async (affiliateId: string | null) => {
    if (!detail) return;
    setAffiliateBusy(true); setAffiliateErr(null);
    const { error } = await supabase.rpc('set_invoice_affiliate', { p_invoice_id: detail.id, p_affiliate_id: affiliateId });
    setAffiliateBusy(false);
    if (error) { setAffiliateErr(error.message); return; }
    noteLocalChangeRef.current([detail.id]);
    await loadEffectiveAffiliate(detail.id);
    const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single();
    if (invRow) await openDetail(invRow as Invoice);
    void refreshList({ afterSave: 'The affiliate was saved', changed: [detail.id] });
  };

  // Every detail load takes a ticket. A slower, older load that finishes after
  // a newer one must not write its results over the top, and must not reopen an
  // invoice the user has already navigated away from.
  const detailLoadSeq = useRef(0);
  const detailIdRef = useRef<string | null>(null);
  // Closing the invoice forgets it: a live signal about it, or a slow open
  // still in flight, must not bring it back.
  useEffect(() => {
    if (detail) return;
    detailIdRef.current = null; detailLoadSeq.current++;
    setDetailStale(false); setDetailUpdatedNote(null); setDetailReloadError(null);
  }, [detail]);
  /**
   * Reload the invoice that is open, by its own id.
   *
   * A refund or cancellation changes status, paid_amount, refunds, payments
   * and benefits. refreshList() refreshes the LIST, but `detail` still holds the
   * row as it was when the invoice was opened, so the screen went on saying
   * "Paid · net S$15 · refunded S$0" after a S$15 refund had been recorded.
   * Nothing was wrong with the money; the screen was reading a stale copy.
   *
   * Throws on failure so the caller can say the action was saved and offer a
   * read-only retry, rather than presenting stale figures as current.
   */
  const refreshDetail = useCallback(async (invoiceId: string) => {
    // Only the invoice that is open is reloaded: never one the user has since
    // closed or navigated away from.
    if (detailIdRef.current !== invoiceId) return;
    const { data, error } = await supabase.from('invoices')
      .select('*').eq('id', invoiceId).is('deleted_at', null).maybeSingle();
    if (error) throw error;
    if (!data) throw new Error('The invoice could not be read back.');
    if (detailIdRef.current !== invoiceId) return;
    await openDetail(data as Invoice);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const openDetail = async (inv: Invoice) => {
    const seq = ++detailLoadSeq.current;
    detailIdRef.current = inv.id;
    const superseded = () => seq !== detailLoadSeq.current;
    // The list row is the page's narrow shape (324): enough to show, not
    // enough to correct from — it carries no notes, manual discount, voucher
    // or instalment fields, and openEdit restores all of those from `detail`.
    // Open from the full row, so nothing the form restores is silently blank.
    const { data: fullRow } = await supabase.from('invoices').select('*').eq('id', inv.id).maybeSingle();
    if (superseded()) return;
    if (fullRow) inv = fullRow as Invoice;
    setPaymentRequestId(crypto.randomUUID());
    setDetail(inv); setDetailFinancial(null);
    setDetailStale(false); setDetailUpdatedNote(null); setDetailReloadError(null);
    setDetailTherapy(null);
    void loadAffiliateOptions();
    void loadEffectiveAffiliate(inv.id);
    setSendErr(null); setSendNote(null);
    setRevisions([]);
    supabase.rpc('invoice_revision_history', { p_invoice_id: inv.id })
      .then(({ data }) => setRevisions((data as any[]) ?? []));
    setBillToSource('-');
    supabase.rpc('invoice_bill_to_source', { p_invoice_id: inv.id })
      .then(({ data }) => setBillToSource((data as string) || '-'));
    void loadInvoiceLegacy(inv.id, inv);
    void ensureCustomers([inv.customer_id]);
    if (warehouses.length === 0) {
      supabase.from('warehouses').select('id,name').is('deleted_at', null).order('name')
        .then(({ data }) => setWarehouses((data as any[]) ?? []));
    }
    if (inv.customer_id) {
      supabase.rpc('customer_credit_balances', { p_customer_id: inv.customer_id })
        .then(({ data }) => setPayWallet(data ?? null));
    } else { setPayWallet(null); }
    const [items, pays, svc, ther, financial] = await Promise.all([
      supabase.from('invoice_items').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_payments').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_service_staff').select('staff_id').eq('invoice_id', inv.id),
      supabase.rpc('invoice_therapy_summary', { p_invoice_id: inv.id }),
      supabase.rpc('invoice_financial_position', { p_invoice_id: inv.id }),
    ]);
    if (superseded()) return;
    setDetailTherapy(ther.data ?? null);
    const its = (items.data as InvoiceItem[]) ?? [];
    setDetailItems(its);
    setDetailPayments((pays.data as InvoicePayment[]) ?? []);
    setDetailServiceStaff(((svc.data as any[]) ?? []).map(r => r.staff_id));
    // Promotion contents: fixed items of the promotions on this invoice + this invoice's chosen selections.
    const promoIds = its.filter(i => i.line_kind === 'promotion' && (i as any).promotion_id).map(i => (i as any).promotion_id);
    const itemIds = its.map(i => i.id);
    const [pi, sel] = await Promise.all([
      promoIds.length ? supabase.from('promotion_items').select('*').in('promotion_id', promoIds) : Promise.resolve({ data: [] } as any),
      itemIds.length ? supabase.from('invoice_promotion_selections').select('*').in('invoice_item_id', itemIds) : Promise.resolve({ data: [] } as any),
    ]);
    setDetailPromoItems((pi.data as any[]) ?? []);
    setDetailSelections((sel.data as any[]) ?? []);
    // Phase 13 — exchange context + revision history.
    if ((inv as any).is_exchange) {
      const { data: exd } = await supabase.rpc('exchange_invoice_details', { p_invoice_id: inv.id });
      setDetailExchange(exd ?? null);
    } else setDetailExchange(null);
    const { data: revs } = await supabase.from('invoice_revisions')
      .select('id, invoice_id, revision_no, edited_by, edit_reason, edited_at')
      .eq('invoice_id', inv.id).order('revision_no', { ascending: false });
    setDetailRevisions((revs as InvoiceRevision[]) ?? []);
    setDetailFinancial(financial.data);
    const remaining = Number(financial.data?.outstanding ?? 0);
    // No method is chosen for the operator. Defaulting to the first method, or
    // to whatever the previous customer used, is how the wrong one gets
    // recorded without anyone noticing.
    programmaticPayRef.current = true; payTouchedRef.current = false;
    setPayLines([{ payment_method_id: '', amount: remaining > 0 ? remaining : 0 }]);
    setPayInstalment({
      instalment_category: (inv as any).instalment_category ?? '',
      instalment_method_id: (inv as any).instalment_method_id ?? '',
      instalment_months: (inv as any).instalment_months ?? '',
    });
    setPayErr(null); setPayOutcome(null); setPayDate(singaporeToday());
  };

  const payTotal = useMemo(() => payLines.reduce((s, p) => s + (p.amount || 0), 0), [payLines]);

  // Phase 12 — close a fully-FOC invoice with no payment.
  useEffect(() => {
    const review = searchParams.get('review');
    if (!review) return;
    let alive = true;
    supabase.from('invoices').select('*').eq('id', review).single().then(({ data, error }) => {
      if (!alive) return;
      if (error) { setPayErr(error.message); return; }
      void openDetail(data as Invoice);
      const next = new URLSearchParams(searchParams); next.delete('review'); setSearchParams(next, { replace: true });
    });
    return () => { alive = false; };
  }, [searchParams]);

  const handleConfirmFoc = async () => {
    if (!detail) return;
    setFocBusy(true); setFocErr(null);
    const { data, error } = await supabase.rpc('confirm_foc_invoice', { p_invoice_id: detail.id, p_note: null });
    setFocBusy(false);
    if (error) { setFocErr(error.message); return; }
    noteLocalChangeRef.current([detail.id]);
    const res = data as any;
    if (res && res.review_required) {
      setFocErr('Prices changed since this invoice was created — reopen it and review before confirming.');
      void refreshList(); return;
    }
    setDetail(null); void refreshList({ afterSave: 'The FOC invoice was confirmed', changed: [detail.id] });
  };

  const handleApplyLineFoc = async () => {
    if (!focLine) return;
    if (!focReasonId && !focNote.trim()) { setFocErr('A FOC reason is required.'); return; }
    setFocBusy(true); setFocErr(null);
    const { error } = await supabase.rpc('apply_line_foc', {
      p_invoice_item_id: focLine.id, p_foc_quantity: focQty,
      p_reason_id: focReasonId || null, p_reason_text: focNote.trim() || null,
    });
    setFocBusy(false);
    if (error) { setFocErr(error.message); return; }
    if (detail) noteLocalChangeRef.current([detail.id]);
    setFocLine(null);
    if (detail) { const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single(); if (invRow) await openDetail(invRow as Invoice); }
    void refreshList({ afterSave: 'The FOC line was saved', changed: detail ? [detail.id] : [] });
  };

  const handleRemoveLineFoc = async (itemId: string) => {
    setFocBusy(true); setFocErr(null);
    const { error } = await supabase.rpc('remove_line_foc', { p_invoice_item_id: itemId, p_reason: null });
    setFocBusy(false);
    if (error) { setFocErr(error.message); return; }
    if (detail) { noteLocalChangeRef.current([detail.id]); await openDetail(detail); }
    void refreshList({ afterSave: 'The FOC was removed', changed: detail ? [detail.id] : [] });
  };

  /* Why Record Payment is or is not available. Returned as a sentence so the
   * reason can be shown rather than left to a disabled button. The server
   * checks all of this again; this only stops an avoidable round trip. */
  const paymentBlocker = (): string | null => {
    if (!detail) return 'No invoice open.';
    if (payBusy) return 'A payment is already being recorded.';
    const filled = payLines.filter(p => p.amount > 0 || p.payment_method_id);
    if (filled.length === 0) return 'Add at least one payment.';
    // A row with money in it and no method is a mistake, not a row to skip.
    if (filled.some(p => p.amount > 0 && !p.payment_method_id)) return 'Choose a payment method for every amount entered.';
    // An instalment is a label on money that has arrived, so its line needs an
    // amount exactly like every other method.
    const isInstalment = (p: typeof payLines[number]) => p.payment_method_id === INSTALMENT_METHOD;
    if (filled.some(p => p.payment_method_id && !(p.amount > 0))) {
      return 'Enter an amount for every selected payment method.';
    }
    if (filled.some(p => !Number.isFinite(p.amount) || p.amount <= 0)) {
      return 'Amounts must be positive.';
    }
    const badPortion = filled.map((p, i) => isInstalment(p)
      ? portionProblem(p.instalment, p.amount || 0) : null).find(Boolean);
    if (badPortion) return badPortion;
    const instalmentError = validateInstalment(payInstalment);
    if (instalmentError) return instalmentError;
    if (!payDate) return 'Choose the date this payment was received.';
    if (payDate > singaporeToday()) return 'A payment cannot be dated in the future.';
    return null;
  };
  const payBlockedReason = paymentBlocker();

  const handlePay = async () => {
    if (!detail) return;
    const blocked = paymentBlocker();
    if (blocked) { setPayErr(blocked); return; }
    // An instalment line is a receipt like any other, recorded under the real
    // method the money came through. The duration is a label, stamped on the
    // invoice afterwards; no arrangement to collect anything later is written.
    const lineErrors: Record<number, string> = {};
    payLines.forEach((p, i) => {
      if (p.payment_method_id !== INSTALMENT_METHOD) return;
      const problem = portionProblem(p.instalment, p.amount || 0);
      if (problem) lineErrors[i] = problem;
    });
    setPayLineErrors(lineErrors);
    if (Object.keys(lineErrors).length > 0) {
      setPayErr('Check the instalment details below.');
      return;
    }

    const receipts: any[] = [];
    // The instalment label to stamp on the invoice once the money is recorded.
    // The last instalment line wins: the invoice carries one set of terms.
    let instalmentLabel: { method_id: string; months: number } | null = null;
    // Every receipt carries a key that is stable for this request, so a retry
    // finds what it already wrote instead of writing again.
    payLines.forEach((p, i) => {
      if (!p.payment_method_id || !(p.amount > 0)) return;
      if (p.payment_method_id === INSTALMENT_METHOD) {
        const inst = p.instalment!;
        // Money goes in under the REAL method, never "Instalment".
        receipts.push({ key: `line-${i}`, payment_method_id: inst.method_id,
                        amount: p.amount, payment_date: payDate || undefined });
        instalmentLabel = { method_id: inst.method_id, months: Number(inst.months) };
        return;
      }
      receipts.push({ key: `line-${i}`, payment_method_id: p.payment_method_id,
                      amount: p.amount, payment_date: payDate || undefined });
    });
    if (receipts.length === 0) {
      setPayErr('Choose a payment method and an amount.');
      return;
    }

    setPayBusy(true); setPayErr(null); setPayOutcome(null);
    const invoiceId = detail.id;
    // The money goes in first. The instalment label is stamped afterwards, so a
    // failed payment can never leave terms behind for money that was not taken.
    const { data, error } = await supabase.rpc('record_invoice_settlement', {
      p_invoice_id: invoiceId,
      p_payload: { receipts, arrangements: [] },
      p_request_id: paymentRequestId,
    });
    setPayBusy(false);
    if (error) {
      // A confirmed failure: the entered values stay for correction, and the
      // request id stays the same so a retry cannot double-charge.
      setPayErr(error.message);
      return;
    }
    // Terms for money that has actually been recorded. If this stamp fails the
    // payment still stands — the invoice simply shows no instalment terms, which
    // an edit can put right; it is not worth failing a taken payment over.
    if (instalmentLabel) {
      const label = instalmentLabel as { method_id: string; months: number };
      const { error: labelError } = await supabase.rpc('set_invoice_instalment_label', {
        p_invoice_id: invoiceId, p_method_id: label.method_id, p_months: label.months,
      });
      if (labelError) setPayErr(`The payment was recorded. The instalment terms were not: ${labelError.message}`);
    }
    const res: any = data;
    if (res?.review_required) {
      // Prices changed; nothing was charged. Refresh the (repriced) invoice
      // and show the review so staff confirm the new total with the customer.
      const { data: invRow } = await supabase.from('invoices').select('*').eq('id', invoiceId).single();
      if (invRow) await openDetail(invRow as Invoice);
      setPriceReview(res as PriceReviewResult);
      return;
    }
    // Recorded. From here a failure is a DISPLAY failure, never a reason to pay
    // again, so it is reported as exactly that.
    noteLocalChangeRef.current([invoiceId]);
    const { data: invRow, error: refreshError } = await supabase.from('invoices').select('*').eq('id', invoiceId).single();
    if (refreshError || !invRow) {
      setPayOutcome('The payment was recorded. This invoice could not be reloaded just now — reopen it from the list to see its updated status. Do not record the payment again.');
      void refreshList({ afterSave: 'The payment was recorded', changed: [invoiceId] });
      return;
    }
    // A fresh request id: this payment is done, the next one is a new request.
    setPaymentRequestId(crypto.randomUUID());
    await openDetail(invRow as Invoice);
    void refreshList({ afterSave: 'The payment was recorded', changed: [invoiceId] });
  };

  const handleDelete = async (inv: Invoice) => {
    if (inv.status === 'paid') { alert('Paid invoices cannot be deleted.'); return; }
    if (!confirm(`Delete invoice ${inv.invoice_no}?`)) return;
    const { error } = await supabase.rpc('delete_invoice', { p_invoice_id: inv.id });
    if (error) { alert(error.message); return; }
    noteLocalChangeRef.current([inv.id]);
    void refreshList({ afterSave: 'The invoice was deleted', changed: [inv.id] });
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
    noteLocalChangeRef.current([detail.id]);
    setActionType(null); setActionReason(''); setDetail(null);
    void refreshList({ afterSave: 'The request was recorded', changed: [detail.id] });
  };

  const canExport = isOwnerOrManager(profile?.role);
  const serviceStaffOptions = useMemo(() => profiles.filter(p => SERVICE_STAFF_ROLES.includes(p.role)), [profiles]);
  const staffName = (id: string) => profiles.find(p => p.id === id)?.full_name ?? '—';
  const effectiveStore = isStaff
    ? (staffMustChooseStore ? cStore : (cStore || assignedStoreId || myStores[0]?.store_id || ''))
    : cStore;

  // Multi-customer split: offered when a Credit Package OR Premium Bundle is
  // the sole line (never in edit mode). The panel + RPC are authoritative.
  const creditPkgLineId = (cLines.find(l => l.kind === 'credit_package' && l.credit_package_id)?.credit_package_id) ?? '';
  const bundleLineId = (cLines.find(l => l.kind === 'premium_bundle' && l.premium_bundle_id)?.premium_bundle_id) ?? '';
  const splitKind: 'credit_package' | 'premium_bundle' | null = creditPkgLineId ? 'credit_package' : (bundleLineId ? 'premium_bundle' : null);
  const splitLineId = creditPkgLineId || bundleLineId;
  const splitOnly = cLines.length === 1
    && ((splitKind === 'credit_package' && !!cLines[0].credit_package_id)
        || (splitKind === 'premium_bundle' && !!cLines[0].premium_bundle_id));
  useEffect(() => { if (!splitLineId || editingInvoiceId) setSplitMode(false); }, [splitLineId, editingInvoiceId]);
  const handleSplitCreated = (result: any) => {
    setCreateOpen(false); setSplitMode(false); resetCreate();
    setEditingInvoiceId(null); setEditingPaid(false);
    const made = (result?.invoices ?? []) as any[];
    noteLocalChangeRef.current(made.map(iv => iv.id).filter(Boolean));
    setSplitSummary({ package_name: result?.package_name ?? result?.bundle_name ?? 'Split', invoices: made });
    void ensureCustomers(made.map(iv => iv.customer_id));
    void refreshList({ afterSave: 'The split invoices were created', changed: made.map(iv => iv.id).filter(Boolean) });
  };

  // A request per keystroke would be one per letter of a customer's name.
  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(invSearch), 300);
    return () => clearTimeout(t);
  }, [invSearch]);

  const listQuery = useMemo(() => ({
    search: debouncedSearch,
    status: statusFilter,
    dateMode: dateFilter,
    dateFrom, dateTo,
    storeId: '',
    sortField, sortDir,
  }), [debouncedSearch, statusFilter, dateFilter, dateFrom, dateTo, sortField, sortDir]);

  /** Pull one customer into the local cache so the selector and the invoice
   *  can show their name immediately, without refetching the whole table. */
  const refreshCustomer = useCallback(async (id: string) => {
    const { data } = await supabase.from('customers')
      .select('id, full_name, phone, email, referred_by').eq('id', id).maybeSingle();
    if (!data) return;
    setCustomerById(cur => ({ ...cur, [id]: data }));
  }, []);

  /** Payment methods for a set of invoices, in batches — one request per page
   *  of rows, never one per row. Merged rather than replaced so an export can
   *  add to what the page already resolved. Each request stamps the invoices
   *  it is about to label; a slower, older response may not write a label a
   *  newer request has since claimed. */
  const loadPaymentMethodsFor = useCallback(async (ids: string[]) => {
    const missing = ids.filter(Boolean);
    if (missing.length === 0) return;
    const token = labelStamps.current.stamp(missing);
    const out: Record<string, string[]> = {};
    for (let i = 0; i < missing.length; i += 200) {
      const slice = missing.slice(i, i + 200);
      const { data } = await supabase
        .from('invoice_payments')
        .select('invoice_id, payment_methods(name)')
        .in('invoice_id', slice);
      for (const row of ((data as any[]) ?? [])) {
        const name = row.payment_methods?.name;
        if (!name) continue;
        // Two cash payments on one invoice read as "Cash", not "Cash, Cash".
        const list = (out[row.invoice_id] ??= []);
        if (!list.includes(name)) list.push(name);
      }
    }
    if (!mountedRef.current) return;
    setPayMethodsByInvoice(prev => {
      const next = { ...prev };
      for (const id of missing) if (labelStamps.current.accepts(id, token)) next[id] = out[id] ?? [];
      return next;
    });
  }, []);

  /**
   * One page of the list, from the server, for the current query.
   *
   * A foreground load (first open, a filter or page change) shows the empty
   * state while it waits and replaces the rows when it lands. A background
   * refresh (after a save, a realtime event, the Refresh button) keeps the
   * rows it has and only swaps them for the answer; if the answer never
   * comes, the rows stay and the failure is reported beside them.
   * Returns false only when this request failed and was the latest.
   */
  const loadPage = useCallback(async (which: number, opts: { background?: boolean } = {}): Promise<boolean> => {
    const ticket = ++pageRequestRef.current;
    const startedAt = Date.now();
    if (opts.background) setRefreshing(true);
    else { foregroundTicketRef.current = ticket; setPageLoading(true); setPageError(null); }
    try {
      const res = await fetchInvoicePage({ ...listQuery, page: which, pageSize });
      if (ticket !== pageRequestRef.current || !mountedRef.current) return true;   // a newer request won
      lastRefreshStartedRef.current = startedAt;
      // Deleting or filtering can strand the viewer past the end; step back
      // to the last page that exists rather than showing an empty page that
      // looks like "no results". The rows stay until that page arrives.
      const target = pageAfterRefresh(which, res.pages, res.total);
      if (target !== which) { setPage(target); return true; }
      setPageRows(res.rows); setPageTotal(res.total);
      setPageCount(res.pages); setPageSummary(res.summary);
      setPageError(null); setRefreshError(null);
      rememberNames(res.rows as any[]);
      void loadPaymentMethodsFor(res.rows.map(r => r.id));
      return true;
    } catch (e: any) {
      if (ticket !== pageRequestRef.current || !mountedRef.current) return true;
      const message = e?.message ?? 'The invoice list could not be loaded.';
      if (opts.background && pageRowsRef.current.length > 0) setRefreshError({ message });
      else setPageError(message);
      return false;
    } finally {
      if (mountedRef.current) {
        if (opts.background) setRefreshing(false);
        // Cleared by the newest foreground load whoever answered first; a
        // background refresh that overtook it showed the same page already.
        else if (ticket === foregroundTicketRef.current) setPageLoading(false);
      }
    }
  }, [listQuery, pageSize, loadPaymentMethodsFor, rememberNames]);

  // Any change to what is being asked for goes back to page one.
  useEffect(() => { setPage(1); }, [listQuery, pageSize]);
  // A reversed range is never sent. The list keeps its last good result and
  // the inputs say what is wrong, rather than the server refusing, or worse,
  // the dates being quietly swapped.
  const rangeInvalid = Boolean(dateFrom && dateTo && dateFrom > dateTo);
  useEffect(() => { if (rangeInvalid) return; void loadPage(page); }, [loadPage, page, rangeInvalid]);

  /**
   * Refresh what the list shows: the current page for the current search,
   * filters, sort and page size, with its count, page count, totals and
   * payment labels. The server answers; nothing is patched locally.
   *
   * Every save calls this. Calls that overlap are coalesced — one in flight,
   * at most one queued behind it — and each resolves once the list has been
   * asked again after the call was made. `afterSave` is the sentence to show
   * if the save went through but the list could not be refreshed: the action
   * is done and must not be repeated, only the screen is behind.
   */
  const loadPageRef = useRef(loadPage);
  loadPageRef.current = loadPage;
  const lastRefreshOkRef = useRef(true);
  const refreshQueue = useRef(createRefreshQueue(async () => {
    if (rangeInvalidRef.current) { lastRefreshOkRef.current = true; return; }
    lastRefreshOkRef.current = await loadPageRef.current(pageRef.current, { background: true });
  })).current;
  /**
   * This tab changed these invoices. Called the moment a save succeeds — before
   * the invoice is re-read — so the realtime echo of the save, however early it
   * arrives, is recognised as this tab's own; and the other tabs of this
   * browser are told at once.
   */
  const noteLocalChangeImpl = useCallback((ids: string[]) => {
    const recent = recentChangeRef.current;
    // Noted once per change: a save path notes it at success and again when it
    // asks for the refresh, and the other tabs must hear it once.
    const already = recent.source === 'local' && Date.now() - recent.at < 3000 && ids.every(id => recent.ids.has(id));
    if (already) return;
    recentChangeRef.current = { at: Date.now(), ids: new Set(ids), source: 'local' };
    announceRef.current(ids);
  }, []);
  noteLocalChangeRef.current = noteLocalChangeImpl;
  const refreshList = useCallback(async (opts: { afterSave?: string; changed?: string[] } = {}): Promise<boolean> => {
    if (opts.afterSave) noteLocalChangeImpl(opts.changed ?? []);
    lastRefreshRequestedRef.current = Date.now();
    await refreshQueue.request();
    const ok = lastRefreshOkRef.current;
    if (!ok && opts.afterSave && mountedRef.current) {
      const sentence = opts.afterSave;
      setRefreshError(e => ({ message: e?.message ?? 'The invoice list could not be refreshed.', afterSave: sentence }));
    }
    return ok;
  }, [refreshQueue, noteLocalChangeImpl]);

  /** The invoice being edited was changed elsewhere: keep the entries, ask for a review. */
  // A conflict that has already been reviewed, and then another change arrives,
  // is a new conflict: the review is asked for again. A preview computed before
  // the change no longer describes what the save would do.
  const markEditConflict = () => {
    setEditConflict(c => (c && !c.reviewed) ? c : { reviewed: false, fresh: null, loading: false });
    setCorrectionPreview(null);
  };
  const reviewEditConflict = async () => {
    const id = editingIdRef.current; if (!id) return;
    setEditConflict(c => c && { ...c, loading: true });
    const { data } = await supabase.from('invoices').select('*').eq('id', id).maybeSingle();
    if (data) void ensureCustomers([(data as any).customer_id]);
    setEditConflict(c => c && { ...c, loading: false, fresh: (data as Invoice) ?? null });
  };
  // Reviewed: the save proceeds against the invoice as it is now, and says so.
  const continueAfterReview = () => {
    setEditConflict(c => {
      if (c?.fresh) setExpectedEditCount(Number((c.fresh as any).edit_count ?? 0));
      return c && { ...c, reviewed: true };
    });
    setCorrectionPreview(null); setCErr(null);
  };
  const discardAndReopen = async () => {
    const id = editingIdRef.current;
    setCreateOpen(false); setEditingInvoiceId(null); setEditingPaid(false); setStockReviewFor(null);
    setEditConflict(null); setCorrectionPreview(null); setCErr(null);
    if (!id) return;
    const { data } = await supabase.from('invoices').select('*').eq('id', id).is('deleted_at', null).maybeSingle();
    if (data) void openDetail(data as Invoice);
  };
  const conflictRows = (before: Invoice | null, after: Invoice) => {
    const b: any = before ?? {}; const a: any = after;
    const row = (label: string, x: string, y: string) => ({ label, before: x, after: y, changed: x !== y });
    return [
      row('Status', String(b.status ?? '—'), String(a.status ?? '—')),
      row('Total', money(Number(b.total_amount ?? 0)), money(Number(a.total_amount ?? 0))),
      row('Paid', money(Number(b.paid_amount ?? 0)), money(Number(a.paid_amount ?? 0))),
      row('Customer', b.customer_id ? custName(b.customer_id) : '—', a.customer_id ? custName(a.customer_id) : '—'),
      row('Store', b.store_id ? storeName(b.store_id) : '—', a.store_id ? storeName(a.store_id) : '—'),
      row('Invoice date', b.business_date ?? '—', a.business_date ?? '—'),
      row('Affiliate', b.affiliate_id ? 'set' : 'none', a.affiliate_id ? 'set' : 'none'),
      row('Manual discount', money(Number(b.manual_discount ?? 0)), money(Number(a.manual_discount ?? 0))),
      row('Notes', String(b.notes ?? '—'), String(a.notes ?? '—')),
      row('Edits', String(b.edit_count ?? 0), String(a.edit_count ?? 0)),
    ];
  };

  /** The open invoice was changed elsewhere: reload it if nothing is being entered, else say so. */
  const noteDetailChanged = () => {
    const id = detailIdRef.current; if (!id) return;
    const busy = payTouchedRef.current || financeActiveRef.current || dialogsOpenRef.current;
    if (busy) { setDetailStale(true); return; }
    refreshDetail(id).then(() => {
      if (mountedRef.current && detailIdRef.current === id) setDetailUpdatedNote('Updated just now — this invoice was changed by another user or tab.');
    }).catch(() => { if (mountedRef.current && detailIdRef.current === id) setDetailStale(true); });
  };
  const reloadStaleDetail = async () => {
    const id = detailIdRef.current; if (!id) return;
    setDetailStale(false); setDetailReloadError(null);
    try { await refreshDetail(id); }
    catch (e: any) { if (detailIdRef.current === id) setDetailReloadError(`This invoice could not be reloaded${e?.message ? ` (${e.message})` : ''}. Try again, or close and reopen it.`); }
  };
  // The payment entry counts as touched once it changes after the invoice was
  // opened. The first run after opening is the reset itself and is skipped.
  useEffect(() => {
    if (programmaticPayRef.current) { programmaticPayRef.current = false; return; }
    payTouchedRef.current = true;
  }, [payLines, payDate, payInstalment]);

  /**
   * Something the list shows may have changed: another user saved, another
   * tab saved, the tab came back, the realtime channel reconnected. The list
   * is asked again — through the same access-checked query — unless a refresh
   * already covers the change. The open invoice and an open edit are told
   * first, so entries are never silently overwritten.
   */
  const handleLiveChange = useCallback((change: LiveChange) => {
    const ids = change.ids;
    // One change reaches this tab more than once: this tab's own save and its
    // realtime echo; another tab's announcement and the realtime event for the
    // same rows. A signal from a different source, about the same invoices,
    // within three seconds of one this tab already knows, is that same change:
    // the open invoice and an open edit were told the first time, and the
    // refresh for it is either pending (the queue covers it) or has landed
    // (the ordinary coverage check below decides). Two signals from the SAME
    // source are two changes and both count.
    const recent = recentChangeRef.current;
    const duplicate = ids.length > 0 && change.source !== recent.source
      && change.at - recent.at < 3000 && ids.every(id => recent.ids.has(id));
    if (!duplicate && ids.length > 0) {
      recentChangeRef.current = { at: change.at, ids: new Set(ids), source: change.source };
      if (createOpenRef.current && editingIdRef.current && ids.includes(editingIdRef.current)) markEditConflict();
      if (detailIdRef.current && ids.includes(detailIdRef.current)) noteDetailChanged();
    }
    if (duplicate && lastRefreshStartedRef.current < recent.at) return;   // its refresh is still on its way
    // A signal whose every announced row equals the row the list already shows
    // is not news, whatever route it came by: the echo of a change already on
    // screen, or the second event of the same transaction. Anything not
    // comparable — a payment-row event, an invoice not on this page — is news.
    if (ids.length > 0 && change.rows && ids.every(id => announcedMatchesShown(change.rows![id], pageRowsRef.current.find(r => r.id === id)) === true)) return;
    if ((change.source === 'realtime' || change.source === 'tab')
        && (refreshCovers(lastRefreshStartedRef.current, change.at) || lastRefreshRequestedRef.current >= change.at)) return;
    if ((change.source === 'visible' || change.source === 'poll') && Date.now() - lastRefreshStartedRef.current < 5000) return;
    void refreshList();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshList]);
  const live = useInvoiceLiveUpdates({ userId: session?.user?.id ?? null, onChange: handleLiveChange });
  announceRef.current = live.announce;
  const liveLabel = live.state === 'live' ? 'Live' : live.state === 'unavailable' ? 'Updates paused' : live.state === 'connecting' ? 'Connecting…' : '';
  const liveTitle = live.state === 'live'
    ? 'Changes made by other staff or in other tabs appear here as they happen.'
    : live.state === 'unavailable'
      ? 'Live updates are not available right now. The list is checked once a minute while this tab is open, and whenever you come back to it.'
      : '';

  /* The database filters, searches, sorts, counts and totals over every
     invoice the user may see; this is the page it returned. The previous
     version downloaded the whole table — plus every payment row and every
     customer, because the search matches those — and did the work here. */
  const sorted = pageRows;

  /** Clicking a column sorts by it; clicking again flips the direction. */
  const sortBy = (field: InvoiceSortField) => {
    if (!isInvoiceSortField(field)) return;
    if (sortField === field) { setSortDir(d => (d === 'asc' ? 'desc' : 'asc')); return; }
    setSortField(field);
    // Dates and money read most usefully newest/largest first; names A-Z.
    setSortDir(field === 'created_at' || field === 'business_date'
      || field === 'total' || field === 'outstanding' ? 'desc' : 'asc');
  };
  const sortIndicator = (field: InvoiceSortField) =>
    sortField === field ? (sortDir === 'asc' ? ' \u25B2' : ' \u25BC') : '';

  // Shared by the printed document and the WhatsApp / email message.
  const lineName = (it: InvoiceItem) =>
    it.line_kind === 'voucher' ? `Voucher: ${vouchers.find(v => v.id === it.voucher_id)?.name ?? ''}`
    : it.line_kind === 'promotion' ? `Promotion: ${promotions.find(p => p.id === (it as any).promotion_id)?.name ?? ''}`
    : (it.line_kind === 'credit_package' || it.line_kind === 'premium_bundle') ? creditLineName(it)!
    : prodName(it.product_id ?? '');

  const [sendErr, setSendErr] = useState<string | null>(null);
  const [sendBusy, setSendBusy] = useState<'whatsapp' | 'email' | null>(null);

  // The customer copy as a real A5 PDF — same content as the printed customer
  // half. Built in src/lib/invoicePdf.ts.
  const buildPdfDoc = (): PdfDoc | null => {
    if (!detail) return null;
    const store: any = stores.find(s2 => s2.id === detail.store_id) ?? {};
    const cust = customerOf(detail.customer_id);
    const bal = Number(detailFinancial?.outstanding ?? 0);
    return {
      kindLabel: 'Tax Invoice',
      docNo: detail.invoice_no,
      date: displayInvoiceDate(detail),
      status: String(INVOICE_STATUS_LABELS[detail.status as InvoiceStatus] ?? detail.status).toUpperCase(),
      storeName: store.name ?? null,
      storeAddress: store.address ?? null,
      storePhone: [store.phone, store.whatsapp_phone ? `WhatsApp ${store.whatsapp_phone}` : '']
        .filter(Boolean).join(' · ') || null,
      customerName: `${cust?.full_name ?? '—'} (${billToSource || '-'})`,
      customerContact: [cust?.phone, cust?.email].filter(Boolean).join(' · ') || null,
      lines: detailItems.map(it => {
        const focQty = Number((it as any).foc_quantity ?? 0);
        const notes: string[] = [];
        if (focQty > 0) notes.push(`FOC ${focQty === it.quantity ? '(full line)' : `${focQty} of ${it.quantity} free`}`);
        if (it.price_overridden) notes.push('Manual price override');
        return {
          name: lineName(it), qty: it.quantity,
          unit: Number(it.unit_price ?? 0), total: Number(it.line_total ?? 0), notes,
        };
      }),
      totals: [
        ['Subtotal', `S$${Number(detail.subtotal ?? 0).toFixed(2)}`],
        ['Discount', `-S$${Number(detail.discount_total ?? 0).toFixed(2)}`],
        ...(Number(detail.paid_amount ?? 0) > 0
          ? [['Paid', `S$${Number(detail.paid_amount).toFixed(2)}`] as [string, string]] : []),
        ...(bal > 0 ? [['Balance', `S$${bal.toFixed(2)}`] as [string, string]] : []),
      ],
      grandTotal: ['Total', `S$${Number(detail.total_amount ?? 0).toFixed(2)}`],
      payments: detailPayments.map((pm: any) => [
        `${methods.find(m => m.id === pm.payment_method_id)?.name ?? 'Payment'} · ${new Date(pm.effective_at || pm.created_at).toLocaleDateString('en-SG')}${pm.entry_kind === 'correction_reversal' ? ' · Reversal' : pm.entry_kind === 'correction_replacement' ? ' · Replacement' : ''}`,
        `S$${(Number(pm.amount ?? 0) * (pm.entry_kind === 'correction_reversal' ? -1 : 1)).toFixed(2)}`,
      ] as [string, string]),
      payDetails: [
        instalmentText(detail as any, methods),
        store.paynow_uen ? `CIMB UEN: ${store.paynow_uen}` : '',
        store.bank_account ? `CIMB corporate account: ${store.bank_account}` : '',
      ].filter(Boolean),
      staffName: (profiles.find(u => u.id === (detail as any).created_by)?.full_name) ?? profile?.full_name ?? '',
      policyText: store.policy_text ?? null,
      footerBits: [
        store.phone ? `DID: ${store.phone}` : '',
        store.email ? `Email: ${store.email}` : '',
        store.website ? `Website: ${store.website}` : '',
        store.co_reg_no ? `Co. Reg No.: ${store.co_reg_no}` : '',
      ].filter(Boolean),
    };
  };

  // Sends the invoice itself. On a phone the native share sheet opens with the
  // file already attached; on desktop the file downloads and the chat opens for
  // it to be attached, because desktop browsers cannot share files.
  const [sendNote, setSendNote] = useState<string | null>(null);
  const [revisions, setRevisions] = useState<any[]>([]);
  // Resolved server-side so the printed Bill To is right whether or not the
  // affiliate list happens to be loaded in the browser.
  const [billToSource, setBillToSource] = useState<string>('-');
  // WhatsApp gets a link to the PDF; email gets the PDF attached, sent by the
  // send-invoice-email Edge Function. See src/lib/sendDoc.ts.
  const sendPdf = async (channel: 'whatsapp' | 'email') => {
    const pdf = buildPdfDoc();
    if (!detail || !pdf) return;
    const cust = customerOf(detail.customer_id);
    setSendBusy(channel); setSendErr(null); setSendNote(null);
    const args = {
      pdf, kindLabel: 'Invoice', docNo: detail.invoice_no, docId: detail.id,
      docKind: 'invoice' as const, storeId: detail.store_id,
      customerId: detail.customer_id, customerName: cust?.full_name,
      phone: cust?.phone, email: cust?.email,
    };
    const r = channel === 'whatsapp'
      ? await sendViaWhatsAppLink(args)
      : await sendViaEmailAttachment(args);
    setSendBusy(null);
    if (!r.ok) { setSendErr(r.reason ?? 'Could not send.'); return; }
    if (channel === 'whatsapp') {
      setSendNote('WhatsApp has opened with a link to the invoice PDF.');
      return;
    }
    // Say which of the three routes was used, rather than implying the PDF was
    // attached when only a link went out.
    const outcome = (r as any).outcome as 'attached' | 'shared' | 'link' | undefined;
    setSendNote(
      outcome === 'attached' ? `The invoice PDF has been emailed to ${cust?.email}.`
      : outcome === 'shared' ? ((r as any).reason ?? 'Choose your email app — the PDF is attached.')
      : ((r as any).reason ?? 'Your mail client has opened with a link to the PDF.'));
  };
  const savePdf = () => { const d = buildPdfDoc(); if (d && detail) void saveDocumentFile(d, 'pdf', detail.invoice_no); };
  const saveImg = () => { const d = buildPdfDoc(); if (d && detail) void saveDocumentFile(d, 'image', detail.invoice_no); };

  const printInvoice = () => {
    if (!detail) return;
    const store = stores.find(s => s.id === detail.store_id);
    const cust = customerOf(detail.customer_id);
    // "First Last (Referrer, Source)" — a missing referrer or source prints
    // as a dash so the two slots stay readable.
    // Affiliate if the invoice has one, otherwise the customer's source,
    // otherwise a dash. Matches invoice_bill_to_source() in migration 103.
    const billTo = `${cust?.full_name ?? '—'} (${billToSource || '-'})`;
    // The staff signature is printed, not signed by hand. Use whoever raised the
    // invoice; fall back to the person printing it if that is not recorded.
    const signedByName =
      (profiles.find(u => u.id === (detail as any).created_by)?.full_name)
      ?? profile?.full_name ?? '';
    const esc = (s: any) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;');
    const subFor = (it: InvoiceItem) => {
      const fixed = detailPromoItems.filter(p => p.promotion_id === (it as any).promotion_id);
      const chosen = detailSelections.filter(s => s.invoice_item_id === it.id);
      // Therapy and credit packages were missing here, so a promotion containing
      // therapy printed "— × 1 (included)" with a blank name: the row appeared
      // but the therapy itself was invisible once the invoice was created. The
      // creation form resolves these correctly; this list did not.
      const nameOf = (x: any) => x.product_id ? (products.find(p => p.id === x.product_id)?.name ?? '')
        : x.voucher_id ? (vouchers.find(v => v.id === x.voucher_id)?.name ?? '')
        : x.child_promotion_id ? (promotions.find(p => p.id === x.child_promotion_id)?.name ?? '')
        : x.therapy_service_id ? (x.therapy_service_name_snapshot || 'Therapy session')
        : x.therapy_package_id ? (therapyPackages.find((t: any) => t.id === x.therapy_package_id)?.name ?? 'Therapy')
        : x.credit_package_id ? 'Credit package'
        : (x.treatment_name ?? '');
      return [
        ...fixed.map(f => `<tr class="sub"><td colspan="3">— ${esc(nameOf(f))} × ${f.quantity * it.quantity} (included)</td><td></td></tr>`),
        ...chosen.map(s => `<tr class="sub"><td colspan="3">— ${esc(nameOf(s))} × ${s.quantity} (chosen)</td><td></td></tr>`),
      ].join('');
    };
    const itemRows = detailItems.map(it => {
      const lv = (it as any).line_voucher_id
        ? `<div class="mut">Voucher ${esc(vouchers.find(v => v.id === (it as any).line_voucher_id)?.name ?? '')} −S$${Number((it as any).line_discount ?? 0).toFixed(2)}</div>` : '';
      const tu = Number((it as any).topup_amount ?? 0) > 0 ? `<div class="mut">incl. top-up S$${Number((it as any).topup_amount).toFixed(2)}</div>` : '';
      const md = '';
      const ov = it.price_overridden ? `<div class="mut"><b>Manual Override</b>${it.override_reason ? ` — ${esc(it.override_reason)}` : ''}</div>` : '';
      const mem = '';
      const focQty = Number((it as any).foc_quantity ?? 0);
      const focAmt = Number((it as any).foc_amount ?? 0);
      const fc = focQty > 0
        ? `<div class="mut"><b>FOC</b> ${focQty === it.quantity ? '(full line)' : `${focQty} of ${it.quantity} free`} — value S$${focAmt.toFixed(2)}${(it as any).foc_reason ? ` — ${esc(String((it as any).foc_reason))}` : ''}</div>`
        : '';
      const amountCell = focQty === it.quantity && focQty > 0
        ? `<s>S$${(Number(it.line_total) + focAmt).toFixed(2)}</s> <b>FOC</b>`
        : `<b>S$${Number(it.line_total).toFixed(2)}</b>`;
      return `<tr><td>${esc(lineName(it))}${md}${ov}${mem}${lv}${tu}${fc}</td><td class="r">${it.quantity}</td><td class="r">S$${Number(it.unit_price).toFixed(2)}</td><td class="r">${amountCell}</td></tr>` +
        (it.line_kind === 'promotion' ? subFor(it) : '');
    }).join('');
    const payRows = detailPayments.map(p =>
      `<tr><td>${esc(methods.find(m => m.id === p.payment_method_id)?.name ?? '')}${p.payment_reference ? ' · ' + esc(p.payment_reference) : ''} · ${esc(new Date((p as any).effective_at || p.created_at).toLocaleDateString('en-SG'))}${(p as any).entry_kind === 'correction_reversal' ? ' · Reversal' : (p as any).entry_kind === 'correction_replacement' ? ' · Replacement' : ''}</td><td class="r">S$${(Number(p.amount) * ((p as any).entry_kind === 'correction_reversal' ? -1 : 1)).toFixed(2)}</td></tr>`).join('');

    // Service Provided By = the invoice's service staff, each with their work phone.
    const staffRows = detailServiceStaff
      .map(id => profiles.find(p => p.id === id))
      .filter((p): p is Profile => !!p);
    const authorisedBlock = staffRows.length
      ? `<h2>Service Provided By</h2><div>${staffRows.map(p =>
          `<div>${esc(p.full_name)}${p.work_phone ? ` — ${esc(p.work_phone)}` : ''}</div>`).join('')}</div>`
      : '';

    const totalPaid = detailPayments.reduce((s, p) => s + Number(p.amount), 0);
    const ex = detailExchange?.found ? detailExchange : null;
    const exchangeBlock = ex ? `
      <h2>Exchange Details</h2>
      <div class="mut">Exchange ${esc(ex.exchange_no ?? '')} · Original invoice <b>${esc(ex.original_invoice_no ?? '')}</b>${ex.reason ? ` · Reason: ${esc(ex.reason)}` : ''}</div>
      <table><thead><tr><th>Returned Item</th><th class="r">Qty</th><th class="r">Value</th></tr></thead><tbody>
        ${(ex.returned_items ?? []).map((r: any) => `<tr><td>${esc(r.product ?? '')}</td><td class="r">${r.quantity}</td><td class="r">S$${Number(r.line_total).toFixed(2)}</td></tr>`).join('')}
        <tr><td colspan="2"><b>Returned value (exchange credit)</b></td><td class="r"><b>S$${Number(ex.returned_total ?? 0).toFixed(2)}</b></td></tr>
      </tbody></table>` : '';
    const focTotal = Number((detail as any).foc_total ?? 0);
    const focStamp = focTotal > 0
      ? `<div class="mut"><b>${(detail as any).is_full_foc ? 'FREE OF CHARGE' : 'INCLUDES FOC ITEMS'}</b> — FOC value S$${focTotal.toFixed(2)}</div>`
      : '';
    const st: any = store ?? {};
    const storePhone = st.phone ?? '';
    const gstEnabled = !!st.gst_enabled;
    const gstRate = Number(st.gst_rate ?? 0);
    // GST treated as inclusive of the shown Total (common SG retail); the line
    // is informational: Total already equals what the customer pays.
    const gstAmount = gstEnabled && gstRate > 0
      ? Number(detail.total_amount) - Number(detail.total_amount) / (1 + gstRate / 100)
      : 0;

    const logosTop = (st.company_logo_url || st.store_logo_url)
      ? `<div style="display:flex;gap:16px;align-items:center;margin-bottom:10px">
          ${st.company_logo_url ? `<img src="${esc(st.company_logo_url)}" style="max-height:48px;max-width:180px;object-fit:contain" />` : ''}
          ${st.store_logo_url ? `<img src="${esc(st.store_logo_url)}" style="max-height:48px;max-width:180px;object-fit:contain" />` : ''}
        </div>` : '';

    // Payment details as text only. The QR codes were dropped so two copies fit
    // an A4 sheet, and they are printed at the foot rather than mid-document.
    const payDetailBits = [
      st.paynow_uen ? `CIMB UEN: ${esc(st.paynow_uen)}` : '',
      st.bank_account ? `CIMB corporate account: ${esc(st.bank_account)}` : '',
    ].filter(Boolean);
    const payRow = payDetailBits.length
      ? `<div class="paydetail">${payDetailBits.join(' &nbsp;·&nbsp; ')}</div>`
      : '';

    const footerBits = [
      storePhone ? `DID: ${esc(storePhone)}` : '',
      st.email ? `Email: ${esc(st.email)}` : '',
      st.website ? `Website: ${esc(st.website)}` : '',
      st.co_reg_no ? `Co. Reg No.: ${esc(st.co_reg_no)}` : '',
    ].filter(Boolean).join(' &nbsp;|&nbsp; ');

    // Therapy block for print (spec 4.12) — only when this invoice qualified one.
    //
    // TURNED OFF. The Unlimited Therapy qualification block is internal working:
    // eligible totals, qualification top-up, forfeited amounts, entitlement
    // numbers and beneficiary rows. It sits AFTER the totals and payment
    // methods, so hiding it changes no figure on the invoice — the customer's
    // copy still reconciles exactly as before.
    //
    // The markup is kept rather than deleted so it can be brought back by
    // setting this to true. The same block still shows on screen, so staff can
    // see the qualification without it going out to the customer.
    const PRINT_THERAPY_BLOCK = false;

    const th = detailTherapy;
    const therapyBlock = (PRINT_THERAPY_BLOCK && th && th.used) ? `
      <h2>Unlimited Therapy</h2>
      <div class="ther">
        <div class="mut">
          Eligible: S$${Number(th.eligible_total).toFixed(2)}${Number(th.topup_amount) > 0 ? ` &nbsp;|&nbsp; Qualification top-up: S$${Number(th.topup_amount).toFixed(2)}` : ''} &nbsp;|&nbsp; Applied: S$${Number(th.qualified_total).toFixed(2)}${Number(th.forfeited_total) > 0 ? ` &nbsp;|&nbsp; Forfeited: S$${Number(th.forfeited_total).toFixed(2)}` : ''}
        </div>
        ${(th.linked_invoices ?? []).length > 1
          ? `<div class="mut">Combined invoices: ${(th.linked_invoices ?? []).map((li: any) => `${esc(li.invoice_no)} (S$${Number(li.contributed_amount).toFixed(2)})`).join(', ')}</div>`
          : ''}
        ${(th.entitlements ?? []).map((en: any) => `
          <div class="entb">
            <div><strong>${esc(en.package_name)}</strong> — ${en.entitlement_kind === 'unlimited' ? `${en.duration_months} month(s) unlimited` : `${en.voucher_qty} voucher(s)`}</div>
            <div class="mut">${esc(en.entitlement_no)} &nbsp;|&nbsp; Created: ${new Date(en.created_at).toLocaleDateString()} &nbsp;|&nbsp; Activate by: ${new Date(en.activation_deadline).toLocaleDateString()} &nbsp;|&nbsp; Status: ${esc(String(en.status).replace(/_/g, ' '))}</div>
            ${(en.beneficiaries ?? []).length
              ? `<table class="bentbl"><thead><tr><th>Beneficiary</th><th>Portion</th><th>Activated</th><th>Ends</th><th>Status</th></tr></thead><tbody>
                  ${(en.beneficiaries ?? []).map((b: any) => `<tr>
                    <td>${esc(b.name)}</td>
                    <td>${b.portion_months ? `${b.portion_months} mo` : `${b.portion_vouchers} vouchers`}</td>
                    <td>${b.activation_date ? new Date(b.activation_date).toLocaleDateString() : '—'}</td>
                    <td>${b.ending_date ? new Date(b.ending_date).toLocaleDateString() : (b.portion_vouchers ? 'No expiry' : '—')}</td>
                    <td>${esc(String(b.status).replace(/_/g, ' '))}</td>
                  </tr>`).join('')}
                </tbody></table>`
              : `<div class="mut">No beneficiary assigned yet.</div>`}
          </div>`).join('')}
      </div>` : '';

    // One invoice copy — rendered twice (customer + store) on a single A4 page.
    const copyHtml = (copyLabel: string) => `
      <div class="copy">
        ${logosTop}
        <div class="head">
          <div><h1>Energia</h1><div class="mut">Wellness &amp; Retail</div>
            <div class="copytag">${copyLabel}</div></div>
          <div style="text-align:right"><h1>${esc(detail.invoice_no)}</h1>
            <div class="mut">${esc(store?.name ?? '')}</div>
            ${st.address ? `<div class="mut">${esc(st.address)}</div>` : ''}
            ${storePhone ? `<div class="mut">Tel: ${esc(storePhone)}</div>` : ''}
            ${st.whatsapp_phone ? `<div class="mut">Shop WhatsApp: ${esc(st.whatsapp_phone)}</div>` : ''}
            <div class="mut">Date: ${displayInvoiceDate(detail)}</div><div class="mut">${esc(instalmentText(detail as any, methods))}</div>
            <div class="mut">Status: <b class="statusword">${esc(String(detail.status).replace(/_/g, ' ').toUpperCase())}</b></div></div>
        </div>
        ${focStamp}
        ${ex ? `<div class="mut"><b>EXCHANGE INVOICE</b> — replaces items from ${esc(ex.original_invoice_no ?? '')}</div>` : ''}
        <h2>Bill To</h2>
        <div>${esc(billTo)}</div><div class="mut">${esc(cust?.phone ?? '')}</div>
        <h2>Items</h2>
        ${exchangeBlock}
        <table><thead><tr><th>${ex ? 'Replacement Item' : 'Item'}</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Total</th></tr></thead><tbody>${itemRows}</tbody></table>
        <table class="totals">
          ${focTotal > 0 ? `<tr><td>Normal value</td><td class="r">S$${(Number(detail.subtotal) + focTotal).toFixed(2)}</td></tr>
          <tr><td>FOC (free of charge)</td><td class="r">−S$${focTotal.toFixed(2)}</td></tr>` : ''}
          <tr><td>Subtotal${focTotal > 0 ? ' (chargeable)' : ''}</td><td class="r">S$${Number(detail.subtotal).toFixed(2)}</td></tr>
          <tr><td>${ex ? 'Exchange credit applied' : 'Discount'}</td><td class="r">−S$${Number(detail.discount_total).toFixed(2)}</td></tr>
          ${ex && Number(ex.foc_waived ?? 0) > 0 ? `<tr><td>incl. FOC waived top-up</td><td class="r">−S$${Number(ex.foc_waived).toFixed(2)}</td></tr>` : ''}
          ${gstEnabled && gstRate > 0 ? `<tr><td>GST (${gstRate}%, incl.)</td><td class="r">S$${gstAmount.toFixed(2)}</td></tr>` : ''}
          <tr class="grand"><td>${ex ? 'Net Top-Up' : 'Total'}</td><td class="r">S$${Number(detail.total_amount).toFixed(2)}</td></tr>
        </table>
        ${payRows ? `<h2>Payment Methods</h2><table class="paytbl"><tbody>${payRows}<tr><td><strong>Total Paid</strong></td><td class="r"><strong>S$${totalPaid.toFixed(2)}</strong></td></tr></tbody></table>` : ''}
        ${therapyBlock}
        ${authorisedBlock}
        <div class="signrow">
          <div class="sign">
            <div class="signline signed">${esc(signedByName)}</div>Staff Signature
          </div>
          <div class="sign"><div class="signline"></div>Customer Signature</div>
        </div>
        <div class="terms"><b>GOODS AND SERVICES SOLD ARE NEITHER REFUNDABLE NOR EXCHANGEABLE.
          GOODS AND SERVICES HAVE BEEN CHECKED AND COLLECTED.</b></div>
        ${st.policy_text ? `<div class="policy"><b>CANCELLATION / EXCHANGE / REFUND POLICY</b><br/>${esc(st.policy_text).replace(/\n/g, '<br/>')}</div>` : ''}
        ${payRow ? `<div class="payfoot"><strong>How to pay</strong> &nbsp; ${payRow}</div>` : ''}
        ${footerBits ? `<div class="footer">${footerBits}</div>` : ''}
      </div>`;

    const html = `<!doctype html><html><head><title>${esc(detail.invoice_no)}</title><style>
      /* Shared with the Special Products / Rentals receipts so the two cannot
         drift apart — see src/lib/printDoc.ts */
      ${PRINT_CSS}
    </style></head><body>
      <div class="sheet">
        ${copyHtml('CUSTOMER COPY')}
        <div class="cut"><span>✂  CUT HERE</span></div>
        ${copyHtml('OFFICE COPY')}
      </div>
      <script>window.onload=function(){window.print();}</script>
    </body></html>`;
    const w = window.open('', '_blank');
    if (!w) { alert('Please allow pop-ups to print.'); return; }
    w.document.write(html); w.document.close();
    // Audit: record that this invoice was printed.
    supabase.rpc('write_audit', {
      p_table: 'invoices', p_record: detail.id, p_action: 'invoice_printed',
      p_old: null, p_new: { invoice_no: detail.invoice_no },
    }).then(() => {}, () => {});
  };

  const statusOptions: ('all' | InvoiceStatus)[] = ['all', 'unpaid', 'partially_paid', 'paid', 'cancelled', 'refunded'];

  // Read by handlers that run after this render, without a stale closure.
  pageRef.current = page; rangeInvalidRef.current = rangeInvalid; pageRowsRef.current = pageRows;
  createOpenRef.current = createOpen; editingIdRef.current = editingInvoiceId;
  dialogsOpenRef.current = createOpen || guidedOpen || chooserOpen || !!actionType || !!focLine
    || !!stockReviewFor || !!priceReview || !!quickCustomerFor;

  return (
    <div>
      <div className="page-header">
        <div><h2>Invoices</h2><p>Create invoices for a store. Stock is deducted only when an invoice is fully paid.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={() => void refreshList()} disabled={refreshing} aria-busy={refreshing}
            title="Reload this page of invoices with its count and totals">
            <RefreshCw size={15} className={(loading || refreshing) ? 'spin' : ''} /> {refreshing ? 'Refreshing…' : 'Refresh'}</button>
          {liveLabel && <span className="invoice-live-status" data-live={live.state} title={liveTitle} role="status">{liveLabel}</span>}
          {/* canExport is already Owner/Manager only. */}
          {exportProgress && exportProgress.got < exportProgress.all && (
            <span className="invoice-page-busy" role="status" aria-live="polite">
              Preparing export… {exportProgress.got} of {exportProgress.all}
            </span>
          )}
          {canExport && <XeroExportButton
            stores={stores.map(s2 => ({ id: s2.id, name: s2.name }))}
            defaultStoreId={activeStore ?? ''} />}
          {canExport && <PaymentSummaryExport
            stores={stores.map(s2 => ({ id: s2.id, name: s2.name }))}
            defaultStoreId={activeStore ?? ''} />}
          {canExport && <ExcelExportButton
            rows={sorted}
            /* The export covers every matching invoice, not the page on screen.
               Fetched in batches of 500 so a large one cannot be truncated by
               the API row limit — the failure XERO_ROW_LIMIT_FIX.md records. */
            fetchAll={async () => {
              const all = await fetchAllMatchingInvoices(listQuery,
                (got, total) => setExportProgress({ got, all: total }));
              await loadPaymentMethodsFor(all.map(r => r.id));
              setExportProgress(null);
              return all;
            }}
            filename="invoices" sheetName="Invoices"
            dateOf={(i: Invoice) => i.business_date} dateLabel="Invoice business date" dateTimeZone="Asia/Singapore"
            columns={[
              { header: 'Invoice', value: (i: any) => i.invoice_no },
              { header: 'Date', value: (i: Invoice) => displayInvoiceDate(i) },
              { header: 'Store', value: (i: any) => storeName(i.store_id) },
              { header: 'Customer', value: (i: any) => i.customer_name ?? custName(i.customer_id) },
              { header: 'Total', value: (i: any) => Number(i.total_amount ?? 0) },
              { header: 'Net payments held', value: (i: any) => Number(i.paid_amount ?? 0) },
              { header: 'Instalments', value: (i: any) => instalmentText(i, methods) },
              // Kept in step with the table: the export mirrors these columns,
              // and a sheet missing a column the screen shows is confusing.
              { header: 'Payment', value: (i: any) => (payMethodsByInvoice[i.id] ?? []).join(', ') },
              { header: 'Status', value: (i: any) => INVOICE_STATUS_LABELS[i.status as InvoiceStatus] ?? i.status },
            ]} />}
          <button className="btn btn-primary" onClick={() => { resetCreate(); setCreateOpen(true); }}><Plus size={16} /> New Invoice</button>
        </div>
      </div>

      {splitSummary && (
        <div className="alert alert-success" style={{ marginBottom: 10, display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
          <div>
            <strong>{splitSummary.invoices.length} invoice{splitSummary.invoices.length === 1 ? '' : 's'} created</strong> from {splitSummary.package_name}
            <div style={{ fontSize: 12.5, marginTop: 4 }}>
              {splitSummary.invoices.map((iv: any) => (
                <div key={iv.invoice_id}>{iv.invoice_no} — {custName(iv.customer_id)} — {money(Number(iv.payment_amount ?? 0))}</div>
              ))}
            </div>
          </div>
          <button className="btn btn-secondary btn-sm" onClick={() => setSplitSummary(null)}>Dismiss</button>
        </div>
      )}

          <div style={{ marginBottom: 10 }}>
            <input value={invSearch} onChange={e => setInvSearch(e.target.value)}
              placeholder="Search invoice number, customer, store, payment method or invoice date…"
              style={{ maxWidth: 460 }} />
            {invSearch && (
              <span style={{ marginLeft: 10, fontSize: 12.5, color: 'var(--text-muted)' }}>
                {/* The count is the whole filtered set, not this page. */}
                {pageTotal} match{pageTotal === 1 ? '' : 'es'}
                {pageLoading && <span className="invoice-page-busy" aria-live="polite"> · loading…</span>}
                <span className="invoice-sort-picker">
                  <label htmlFor="invoice-sort">Sort</label>
                  <select id="invoice-sort" value={sortField}
                    onChange={e => { const v = e.target.value; if (isInvoiceSortField(v)) { setSortField(v); } }}>
                    {INVOICE_SORT_FIELDS.map(f => <option key={f.value} value={f.value}>{f.label}</option>)}
                  </select>
                  <button type="button" className="btn btn-secondary btn-sm"
                    aria-label={sortDir === 'asc' ? 'Sorted ascending, switch to descending' : 'Sorted descending, switch to ascending'}
                    onClick={() => setSortDir(d => (d === 'asc' ? 'desc' : 'asc'))}>
                    {sortDir === 'asc' ? '\u25B2' : '\u25BC'}
                  </button>
                </span>
                <button className="btn btn-secondary btn-sm" style={{ marginLeft: 8 }}
                  onClick={() => setInvSearch('')}>Clear</button>
              </span>
            )}
          </div>
      <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
        {statusOptions.map(s => (
          <button key={s} className={`btn btn-sm ${statusFilter === s ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setStatusFilter(s)}>
            {s === 'all' ? 'All' : INVOICE_STATUS_LABELS[s]}
          </button>
        ))}
      </div>

      {refreshError && (
        <div className="alert alert-warning invoice-refresh-error" role="alert" data-testid="invoice-list-refresh-error">
          <div>
            {refreshError.afterSave
              ? <><strong>{refreshError.afterSave}.</strong> The invoice list could not be refreshed and may still show the earlier state. Do not repeat the action. </>
              : <>The invoice list could not be refreshed and may be out of date. </>}
            <span style={{ color: 'var(--text-muted)' }}>{refreshError.message}</span>
          </div>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => void refreshList()} disabled={refreshing}>
            <RefreshCw size={13} className={refreshing ? 'spin' : ''} /> Try again
          </button>
        </div>
      )}
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', marginBottom: 14, alignItems: 'end' }}>
        <label>Date status<select aria-label="Invoice date status" value={dateFilter} onChange={e => {
          const value = e.target.value as typeof dateFilter; setDateFilter(value);
          if (value === 'pending') { setDateFrom(''); setDateTo(''); }
        }}>
          <option value="all">All invoice dates</option><option value="confirmed">Confirmed dates</option>
          <option value="pending">Date from creation only</option>
        </select></label>
        <label>Invoice date from<input aria-label="Invoice date from" type="date" value={dateFrom} max={dateTo || undefined}
          disabled={dateFilter === 'pending'} onChange={e => setDateFrom(e.target.value)} /></label>
        <label>Invoice date to<input aria-label="Invoice date to" type="date" value={dateTo} min={dateFrom || undefined}
          disabled={dateFilter === 'pending'} onChange={e => setDateTo(e.target.value)} /></label>
        <button className="btn btn-secondary btn-sm" onClick={() => { setDateFilter('all'); setDateFrom(''); setDateTo(''); }}>All dates</button>
      </div>
      {rangeInvalid && (
        <p role="alert" data-testid="invoice-date-range-error" style={{ color: 'var(--danger)', fontSize: 12.5, marginTop: -8, marginBottom: 12 }}>
          The "from" date is after the "to" date. Correct the range to filter the list.
        </p>
      )}
      {!rangeInvalid && (dateFrom || dateTo) && dateFilter !== 'pending' && (
        <p data-testid="invoice-date-range-note" style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: -8, marginBottom: 12 }}>
          Showing invoices whose recorded invoice date is {dateFrom && dateTo ? `from ${dateFrom.split('-').reverse().join('/')} to ${dateTo.split('-').reverse().join('/')}` : dateFrom ? `on or after ${dateFrom.split('-').reverse().join('/')}` : `on or before ${dateTo.split('-').reverse().join('/')}`}, both ends included.
          Invoices with no recorded date are not shown; choose "Date from creation only" to see those.
        </p>
      )}
      {dateFilter === 'pending' && <p>These invoices show the date they were created, because no separate invoice date was recorded. Received money is reported on the day it was received, so their reporting is unaffected.
        {isOwnerOrManager(profile?.role) && ' Open an invoice and use Edit Invoice or Correct Invoice to enter a verified date.'}</p>}
      <div className="card">
        <div className="table-wrap">
          {pageError ? (
            <div className="empty-state" role="alert">
              <AlertTriangle size={30} style={{ opacity: 0.5 }} />
              <p style={{ fontWeight: 600, marginTop: 8 }}>The invoice list could not be loaded.</p>
              <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{pageError}</p>
              <button className="btn btn-secondary btn-sm" style={{ marginTop: 10 }}
                onClick={() => void loadPage(page)}>
                <RefreshCw size={13} /> Try again
              </button>
            </div>
          )
          : (loading || (pageLoading && sorted.length === 0)) ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : sorted.length === 0 ? (
            <div className="empty-state">
              <FileText size={32} style={{ opacity: 0.3 }} />
              <p style={{ fontWeight: 600, marginTop: 8 }}>
                {pageTotal === 0 && (debouncedSearch || statusFilter !== 'all' || dateFilter !== 'all' || dateFrom || dateTo)
                  ? 'No invoices match these filters'
                  : 'No invoices yet'}
              </p>
              {pageTotal === 0 && (debouncedSearch || statusFilter !== 'all' || dateFilter !== 'all' || dateFrom || dateTo) && (
                <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
                  Try a different search, or widen the status and date filters.
                </p>
              )}
            </div>
          )
          : (
            <table>
              <thead><tr>
                {([
                  ['invoice_no', 'Invoice', undefined],
                  ['business_date', 'Date', undefined],
                  ['store', 'Store', undefined],
                  ['customer', 'Customer', undefined],
                  ['total', 'Total', 'right'],
                  ['outstanding', 'Outstanding', 'right'],
                ] as [InvoiceSortField, string, 'right' | undefined][]).map(([field, label, align]) => (
                  <th key={field} style={{ textAlign: align }}
                    aria-sort={sortField === field ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'}>
                    <button type="button" className="invoice-sort-header" onClick={() => sortBy(field)}
                      title={`Sort by ${label.toLowerCase()}`}>
                      {label}<span aria-hidden="true">{sortIndicator(field)}</span>
                    </button>
                  </th>
                ))}
                <th>Payment</th>
                <th aria-sort={sortField === 'status' ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'}>
                  <button type="button" className="invoice-sort-header" onClick={() => sortBy('status')}
                    title="Sort by status">Status<span aria-hidden="true">{sortIndicator('status')}</span></button>
                </th>
                <th></th>
              </tr></thead>
              <tbody>
                {sorted.map(inv => (
                  <tr key={inv.id}>
                    <td><strong style={{ fontFamily: 'var(--font-display)' }}>{inv.invoice_no}</strong>
                      {/* A voucher claim is a hand-over document, not a sale. It carries
                          no value, so say so rather than let a S$0.00 row read as one. */}
                      {(inv as any).is_voucher_claim && (
                        <div><span className="badge badge-muted" style={{ fontSize: 10 }}>Voucher claim</span></div>
                      )}</td>
                    <td style={{ fontSize: 12.5, whiteSpace: 'nowrap' }}>{displayInvoiceDate(inv)}</td>
                    <td style={{ fontSize: 12.5 }}>{storeName(inv.store_id)}</td>
                    <td style={{ fontSize: 13 }}>{custName(inv.customer_id)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(inv.total_amount)}</td>
                    <td style={{ textAlign: 'right', color: Number(inv.total_amount) - Number(inv.paid_amount) > 0 ? 'var(--accent)' : 'var(--success)' }}
                      title={`Paid ${money(inv.paid_amount)}`}>
                      {money(Math.max(0, Number(inv.total_amount ?? 0) - Number(inv.paid_amount ?? 0)))}
                    </td>
                    <td style={{ fontSize: 12.5 }}>
                      {(payMethodsByInvoice[inv.id] ?? []).length > 0
                        ? (payMethodsByInvoice[inv.id] ?? []).join(', ')
                        : <span style={{ color: 'var(--text-muted)' }}>—</span>}
                    </td>
                    <td><StatusBadge s={inv.status} /></td>
                    <td>
                      <div style={{ display: 'flex', gap: 4 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openDetail(inv)}><Eye size={13} /> View</button>
                        {inv.status !== 'paid' && inv.status !== 'partially_paid' && inv.status !== 'cancelled' && inv.status !== 'refunded' && Number(inv.paid_amount) === 0 && (
                          <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(inv)}><Trash2 size={13} /></button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {/* Paging sits below the rows whether or not this page has any, so a
              viewer stranded past the end by a filter can still step back. */}
          {!pageError && pageTotal > 0 && (
            <div className="invoice-paging">
              <div className="invoice-paging-count" aria-live="polite">
                {(() => {
                  const first = (page - 1) * pageSize + 1;
                  const last = Math.min(page * pageSize, pageTotal);
                  return `${first}–${last} of ${pageTotal}`;
                })()}
                {pageSummary.matching > 0 && (
                  <span className="invoice-paging-sum">
                    {' · '}{money(pageSummary.total_amount)} total
                    {pageSummary.outstanding > 0 && `, ${money(pageSummary.outstanding)} outstanding`}
                  </span>
                )}
              </div>
              <div className="invoice-paging-controls">
                <label htmlFor="invoice-page-size">Per page</label>
                <select id="invoice-page-size" value={pageSize}
                  onChange={e => setPageSize(Number(e.target.value))}>
                  <option value={25}>25</option>
                  <option value={50}>50</option>
                  <option value={100}>100</option>
                </select>
                <button type="button" className="btn btn-secondary btn-sm"
                  disabled={page <= 1 || pageLoading}
                  onClick={() => setPage(p => Math.max(1, p - 1))}>Previous</button>
                <span className="invoice-paging-where">
                  Page {page} of {Math.max(1, pageCount)}
                </span>
                <button type="button" className="btn btn-secondary btn-sm"
                  disabled={page >= pageCount || pageLoading}
                  onClick={() => setPage(p => p + 1)}>Next</button>
              </div>
            </div>
          )}
        </div>
      </div>


      {createOpen && (
        <Modal title={editingPaid ? "Correct Invoice" : editingInvoiceId ? "Edit Invoice" : "New Invoice"} wide confirmClose onClose={() => { setCreateOpen(false); setEditingInvoiceId(null); setEditingPaid(false); setStockReviewFor(null); }}
          footer={<><button className="btn btn-secondary" onClick={() => { setCreateOpen(false); setEditingInvoiceId(null); setEditingPaid(false); setStockReviewFor(null); }}>Cancel</button>{!splitMode && !correctionPreview && <button className="btn btn-primary" onClick={handleCreate} disabled={cSaving || previewing}>{previewing ? 'Checking…' : cSaving ? 'Saving…' : editingInvoiceId ? 'Review Changes' : 'Create Invoice'}</button>}</>}>
          <div className="form-grid invoice-editor">
            {editingInvoiceId && editConflict && (
              <div className="alert alert-warning" role="alert" data-testid="invoice-edit-conflict" style={{ marginBottom: 0, display: 'block' }}>
                <strong>This invoice was changed by another user or tab while you were editing it.</strong>{' '}
                Your entries are kept. Review the current invoice before saving, so their change is not overwritten unseen.
                {!editConflict.fresh ? (
                  <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                    <button type="button" className="btn btn-secondary btn-sm" onClick={() => void reviewEditConflict()} disabled={editConflict.loading}>
                      {editConflict.loading ? 'Loading…' : 'Review the current invoice'}
                    </button>
                    <button type="button" className="btn btn-secondary btn-sm" onClick={() => void discardAndReopen()}>Discard my entries and reopen</button>
                  </div>
                ) : (
                  <div style={{ marginTop: 8 }}>
                    <table className="invoice-conflict-table">
                      <thead><tr><th></th><th>When you opened it</th><th>Now</th></tr></thead>
                      <tbody>
                        {conflictRows(editBaseRef.current, editConflict.fresh).map(r => (
                          <tr key={r.label} style={{ fontWeight: r.changed ? 700 : 400 }}>
                            <td>{r.label}</td><td>{r.before}</td><td>{r.after}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap', alignItems: 'center' }}>
                      {editConflict.reviewed
                        ? <span>Reviewed. Saving now applies your entries over the invoice as it is now.</span>
                        : <button type="button" className="btn btn-primary btn-sm" onClick={continueAfterReview}>I have reviewed it — keep my entries</button>}
                      <button type="button" className="btn btn-secondary btn-sm" onClick={() => void discardAndReopen()}>Discard my entries and reopen</button>
                    </div>
                  </div>
                )}
              </div>
            )}
            {/* On a correction the audited notice and its required reason come
                first, then the business date. Someone reading downwards learns
                that this is a correction before they are asked to date it. */}
            {editingPaid && (
              <div className="alert alert-warning" style={{ marginBottom: 0 }}>
                <span>⚠</span>
                <div>
                  <strong>Audited invoice correction.</strong> Unchanged lines keep their saved prices and FOC reasons.
                  The balance uses payments less refunds. Correcting a cancelled or refunded invoice preserves its status.
                  <div style={{ marginTop: 8 }}>
                    <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Reason for the correction *</div>
                    <input value={editReason} onChange={e => setEditReason(e.target.value)}
                      placeholder="e.g. Wrong quantity keyed at the till" />
                  </div>
                </div>
              </div>
            )}
            <label>Invoice business date<input type="date" value={cBusinessDate} onChange={e => setCBusinessDate(e.target.value)} /></label>
            {/* A missing historical date stays missing. Filling it with today to
                silence this would invent the date the sale happened on. */}
            {editingInvoiceId && !cBusinessDate && <p>This legacy invoice’s business date is pending review. Enter the date the sale actually happened; it is not filled in for you.</p>}
            {/* The instalment arrangement moved to Record Payment for a new
                invoice. On a correction it stays here, in the payment part of
                the form, so saved values can be seen and edited. */}
            {editingPaid && <InstalmentFields value={cInstalment} onChange={setCInstalment} methods={methods} />}
            <label>Notes<textarea value={cNotes} onChange={e => setCNotes(e.target.value)} /></label>

            {editingPaid && (
              <div className="form-grid-2">
                {/* Referrer: add one that was missed, change it, or clear it. */}
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Referrer / affiliate</label>
                  <SearchSelect placeholder="None — search name, phone or email…"
                    emptyLabel="No affiliate matches"
                    value={cAffiliate}
                    onChange={v => { setCAffiliate(v); setAffTouched(true); }}
                    options={affiliateOptions.map((a: any) => ({
                      value: a.affiliate_id,
                      label: a.full_name,
                      sublabel: [a.phone, a.email].filter(Boolean).join(' · ') || undefined,
                      search: `${a.full_name} ${a.phone ?? ''} ${a.email ?? ''}`,
                    }))} />
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                    Changing this reverses the affiliate commission and re-earns it for whoever is
                    selected here.
                  </div>
                </div>

                {/* Who raised it. Owner only: this changes what the printed
                    document says about who served the customer. */}
                {isOwner(profile?.role) && (
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label>Raised by</label>
                    <select value={cCreatedBy} onChange={e => setCCreatedBy(e.target.value)}>
                      <option value="">— Unchanged —</option>
                      {profiles
                        .filter(u => u.is_active !== false)
                        .map(u => (
                          <option key={u.id} value={u.id}>
                            {u.full_name}{u.role ? ` · ${u.role.replace(/_/g, ' ')}` : ''}
                          </option>
                        ))}
                    </select>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                      Changes the staff signature on the printed invoice. Commission is unaffected —
                      it follows the store's staff, not this field. The person must work at this store.
                    </div>
                  </div>
                )}

                {/* Payments: amount, date received and method — or a receipt that
                    should never have been recorded. Wallet-credit payments are
                    corrected from the payment list, which checks the credit lots. */}
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Payment{paymentsBeforeEdit.length > 1 ? 's' : ''}</label>
                  {paymentsBeforeEdit.length === 0 ? (
                    <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>No payments recorded.</div>
                  ) : paymentsBeforeEdit.map(p2 => {
                    const e = payEdits[p2.id];
                    const setEdit = (patch: Partial<PayEdit>) => setPayEdits(m => ({ ...m, [p2.id]: { ...m[p2.id], ...patch } }));
                    if (!e) return (
                      <div key={p2.id} style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 5 }}>
                        <span style={{ flex: '0 0 84px', fontSize: 12.5, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                          {money(Number(p2.amount))}
                        </span>
                        <span style={{ flex: 1, fontSize: 12.5, color: 'var(--text-muted)' }}>
                          {methods.find(m => m.id === p2.payment_method_id)?.name} — wallet credit; corrected from the payment list, not here
                        </span>
                      </div>
                    );
                    const setPart = (idx: number, patch: Partial<PayPart>) =>
                      setEdit({ parts: e.parts.map((x, j) => j === idx ? { ...x, ...patch } : x) });
                    const methodOptions = methods.filter(m => !(m as any).is_wallet_credit).map(m => ({ value: m.id, label: m.name }));
                    return (
                      <div key={p2.id} style={{ marginBottom: 6 }}>
                        {e.parts.map((part, idx) => (
                          <div key={idx} style={{ display: 'grid', gridTemplateColumns: '104px 148px minmax(140px, 1fr) auto',
                                                  gap: 8, alignItems: 'center', marginBottom: 4, opacity: e.remove ? 0.55 : 1 }}>
                            <input type="number" min="0.01" step="0.01" aria-label="Payment amount" value={part.amount}
                              disabled={e.remove} onChange={ev => setPart(idx, { amount: ev.target.value })} />
                            <input type="date" aria-label="Date received" value={part.date}
                              disabled={e.remove} onChange={ev => setPart(idx, { date: ev.target.value })} />
                            {e.remove
                              ? <span style={{ fontSize: 12.5 }}>{methods.find(m => m.id === part.payment_method_id)?.name}</span>
                              : <InvoiceSearchSelect value={part.payment_method_id} onChange={id => setPart(idx, { payment_method_id: id })}
                                  options={methodOptions} />}
                            {idx === 0 ? (
                              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setEdit({ remove: !e.remove })}
                                title={e.remove ? 'Keep this payment' : 'This receipt was recorded by mistake'}>
                                {e.remove ? 'Keep' : 'Remove'}
                              </button>
                            ) : (
                              <button type="button" className="btn btn-secondary btn-sm" aria-label="Drop this part"
                                onClick={() => setEdit({ parts: e.parts.filter((_, j) => j !== idx) })}>✕</button>
                            )}
                          </div>
                        ))}
                        {!e.remove && (
                          <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginTop: 2 }}>
                            {/* Part of this money came through another method: add a
                                part. Each part becomes a replacement of this receipt. */}
                            <button type="button" className="btn btn-secondary btn-sm"
                              title="Part of this payment came through another method"
                              onClick={() => setEdit({ parts: [...e.parts, { amount: '', date: e.parts[0].date, payment_method_id: e.parts[0].payment_method_id }] })}>
                              + Split across methods
                            </button>
                            {e.parts.length > 1 && (
                              <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                                {e.parts.length} parts totalling {money(e.parts.reduce((sum, x) => sum + (Number(x.amount) || 0), 0))} replace this {money(Number(p2.amount))} receipt.
                              </span>
                            )}
                          </div>
                        )}
                        {e.remove && (
                          <div style={{ fontSize: 11, color: 'var(--danger)', marginTop: 3 }}>
                            Recorded by mistake: this receipt is reversed with the correction’s reason. No refund is recorded, because no money goes back.
                          </div>
                        )}
                      </div>
                    );
                  })}
                  {paymentsBeforeEdit.length > 0 && (() => {
                    // The same arithmetic the preview does, against the form's live total.
                    const kept = paymentsBeforeEdit.reduce((sum, p2) => {
                      const e = payEdits[p2.id];
                      if (!e) return sum + Number(p2.amount);
                      return e.remove ? sum : sum + e.parts.reduce((t, x) => t + (Number(x.amount) || 0), 0);
                    }, 0);
                    const total = previewTotal;
                    const verdict = kept > total + 0.004
                      ? `the invoice stays paid and ${money(kept - total)} shows as refund due`
                      : kept > 0 && kept >= total - 0.004
                        ? 'which still settles the invoice'
                        : kept > 0
                          ? `the invoice ${statusBeforeEdit === 'partially_paid' ? 'stays' : 'goes back to'} partially paid with ${money(total - kept)} outstanding`
                          : 'no payment is left, so the invoice goes back to unpaid';
                    return (
                      <div style={{ fontSize: 12, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>
                        Payments will total <strong>{money(kept)}</strong> of {money(total)} — {verdict}.
                      </div>
                    );
                  })()}
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                    The original receipt stays in history: a change to the amount or date records a reversal and a
                    replacement with the correction’s reason, and no refund. Benefits already issued at payment stay issued.
                  </div>
                </div>
              </div>
            )}
            {quickCustomerFor && (
        <QuickCustomerModal
          onCreated={(id) => {
            // Only the selector that opened this changes. The invoice draft —
            // lines, prices, promotions, staff, dates, notes — is untouched.
            if (quickCustomerFor.target === 'invoice') setCCustomer(id);
            setQuickCustomerFor(null);
            void refreshCustomer(id);
          }}
          onPickedExisting={(id) => {
            if (quickCustomerFor.target === 'invoice') setCCustomer(id);
            setQuickCustomerFor(null);
            void refreshCustomer(id);
          }}
          onClose={() => setQuickCustomerFor(null)}
        />
      )}
      {correctionPreview && (
              <CorrectionPreview preview={correctionPreview} saving={cSaving}
                onBack={() => setCorrectionPreview(null)}
                onConfirm={() => { void handleCreate(); }} />
            )}
            {cErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{cErr}</div></div>}
            {stockReviewFor && editingInvoiceId === stockReviewFor && (
              <InvoiceStockEvidenceReview invoiceId={stockReviewFor}
                onCancel={() => setStockReviewFor(null)}
                onResolved={() => {
                  // The snapshot exists now. Clear the refusal and let the same
                  // Save Changes go through the ordinary protected correction.
                  setStockReviewFor(null);
                  setCErr('The original records are now on file. Press Save Changes again to apply the correction.');
                }} />
            )}
            <div className="form-grid-2">
              <div className="form-group">
                <label>Store *</label>
                {/* Staff assigned to a single store see it fixed, as before.
                    Assigned to several, they choose among exactly those. */}
                {editingPaid && !isStaff ? (
                  <>
                    <select value={cStore} onChange={e => setCStore(e.target.value)}>
                      {storeOptions.map(s2 => <option key={s2.id} value={s2.id}>{s2.name}</option>)}
                    </select>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                      Moving the invoice returns its stock to the current store and takes it from
                      the new one.
                    </div>
                  </>
                ) : isStaff && myStores.length <= 1 ? (
                  <input value={myStores[0]?.store_name
                    ?? stores.find(s => s.id === (assignedStoreId ?? ''))?.name
                    ?? 'No store assigned'} disabled style={{ background: 'var(--surface-2)' }} />
                ) : (
                  <select value={activeStore} disabled={!!editingInvoiceId && !isOwnerOrManager(profile?.role)}
                    title={editingInvoiceId ? "The store cannot be changed on an existing invoice" : undefined}
                    onChange={e => { setCStore(e.target.value); if (!editingInvoiceId) setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); }}>
                    {(!isStaff || staffMustChooseStore) && <option value="">— Select store —</option>}
                    {storeOptions.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                )}
                {isStaff && myStores.length > 1 && (
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                    You are assigned to {myStores.length} stores, so none is chosen for you.
                    The invoice, its prices and its stock all belong to the one you select here.
                  </div>
                )}
              </div>
              <div className="form-group">
                <label>Customer *</label>
                <div className="customer-with-add">
                  <CustomerSearchSelect value={cCustomer} onChange={v => { setCCustomer(v); setCLines(ls => ls); }} />
                  <button type="button" className="btn btn-secondary btn-sm"
                    onClick={() => setQuickCustomerFor({ target: 'invoice' })}>
                    <Plus size={13} aria-hidden="true" /> Add customer
                  </button>
                </div>
              </div>
            </div>
            {issuedHeaderBefore && (issuedHeaderBefore.customer !== cCustomer || issuedHeaderBefore.store !== cStore) && <div className="alert alert-info">
              <p><strong>This invoice issued benefits.</strong> They move with the customer unless
                you say otherwise. The review summary lists exactly what moves before anything is
                saved.</p>
              <div className="benefit-options" role="radiogroup" aria-label="What happens to the benefits">
                <label className={`benefit-option${benefitAction === 'transfer' ? ' picked' : ''}`}>
                  <input type="radio" name="benefit-action" value="transfer"
                    checked={benefitAction === 'transfer'}
                    onChange={() => { setBenefitAction('transfer'); setIssuedRecipientsConfirmed(true); }} />
                  <span>
                    <strong>Move the unused benefits to the new customer</strong>
                    <span className="benefit-option-note">
                      Only the unused benefits this invoice issued. Anything already used stays with
                      whoever used it, and a partly used benefit stops the correction for review.
                    </span>
                  </span>
                </label>
                <label className={`benefit-option${benefitAction === 'keep' ? ' picked' : ''}`}>
                  <input type="radio" name="benefit-action" value="keep"
                    checked={benefitAction === 'keep'}
                    onChange={() => { setBenefitAction('keep'); setIssuedRecipientsConfirmed(true); }} />
                  <span>
                    <strong>Keep the benefits with who holds them now</strong>
                    <span className="benefit-option-note">
                      Only the invoice's customer changes. The invoice still finds these benefits for
                      refunds and later corrections, so the two will differ on screen.
                    </span>
                  </span>
                </label>
              </div>
            </div>}
            {cCustomer && (() => {
              const cust = customerOf(cCustomer);
              const referrer = cust?.referred_by ? customerOf(cust.referred_by) : null;
              return (
                <div className="alert alert-info" style={{ marginBottom: 0 }}>
                  <span>ℹ️</span>
                  <div>{referrer
                    ? <>Commission referrer: <strong>{referrer.full_name}</strong> earns Tier 1 when this invoice is fully paid{referrer.referred_by ? ', and their referrer earns Tier 2.' : '.'}</>
                    : <>This customer has no referrer set, so no commission will be earned. You can set a referrer on the Customers page.</>}</div>
                </div>
              );
            })()}


            {effectiveStore && (
              <div>
                <label>Served by <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— select everyone who served this customer (Owner / Manager / Staff)</span></label>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 6 }}>
                  {serviceStaffOptions.length === 0 && <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No eligible staff found.</span>}
                  {serviceStaffOptions.map(s => {
                    const on = cServiceStaff.includes(s.id);
                    return (
                      <button key={s.id} type="button"
                        className={`btn btn-sm ${on ? 'btn-primary' : 'btn-secondary'}`}
                        onClick={() => setCServiceStaff(prev => on ? prev.filter(x => x !== s.id) : [...prev, s.id])}>
                        {on ? '✓ ' : ''}{s.full_name}
                      </button>
                    );
                  })}
                </div>
                {cServiceStaff.length > 0 && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6 }}>Staff commission will be split equally among {cServiceStaff.length} selected once the invoice is paid.</div>}
              </div>
            )}

            {/* ---- Multi-customer Credit Package / Premium Bundle split ---- */}
            {splitLineId && !editingInvoiceId && effectiveStore && (
              <div className="form-group">
                <label>Customer Allocation</label>
                <div style={{ display: 'flex', gap: 8 }}>
                  <button type="button" className={`btn btn-sm ${!splitMode ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setSplitMode(false)}>Single Customer</button>
                  <button type="button" className={`btn btn-sm ${splitMode ? 'btn-primary' : 'btn-secondary'}`}
                    disabled={!splitOnly}
                    title={splitOnly ? '' : 'Remove other invoice items first'}
                    onClick={() => { if (splitOnly) setSplitMode(true); }}>Split Across Customers</button>
                </div>
                {!splitOnly && <div className="alert alert-warning" style={{ marginTop: 6, marginBottom: 0 }}>Multi-customer splitting cannot be used while other invoice items are present. Remove the other items first.</div>}
              </div>
            )}

            {splitMode && splitOnly && effectiveStore && splitKind === 'credit_package' && (
              <CreditPackageSplitPanel
                storeId={effectiveStore}
                creditPackageId={creditPkgLineId}
                serviceStaff={cServiceStaff}
                affiliateId={cAffiliate || null}
                notes={null}
                onCreated={handleSplitCreated}
                onCancel={() => setSplitMode(false)}
              />
            )}

            {splitMode && splitOnly && effectiveStore && splitKind === 'premium_bundle' && (
              <PremiumBundleSplitPanel
                storeId={effectiveStore}
                bundleId={bundleLineId}
                serviceStaff={cServiceStaff}
                affiliateId={cAffiliate || null}
                notes={null}
                onCreated={handleSplitCreated}
                onCancel={() => setSplitMode(false)}
              />
            )}

            {!splitMode && (<>
            {effectiveStore && (
              <div>
                <label>Items <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— products (priced at this store) or sellable vouchers</span></label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }}>
                  {cLines.map((line, i) => {
                    const price = lineUnit(line);
                    return (
                    <React.Fragment key={i}>
                      <div className="invoice-editor-line" style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                        <select value={line.kind} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, invoice_item_id: undefined, unit_price: undefined, saved_topup: undefined, kind: e.target.value as LineDraft['kind'], product_id: '', voucher_id: '', promotion_id: '', therapy_package_id: '', therapy_service_id: '', therapy_service_name: '',
                            special_product_id: '', rental_rate_type: 'day', rental_periods: 1,
                            credit_package_id: '', premium_bundle_id: '', bundle_voucher_selection: {},
                            rental_start_date: new Date().toISOString().slice(0, 10), rental_return_date: '' } : l))} style={{ width: 130 }}>
                          <option value="product">Product</option>
                          <option value="voucher">Voucher</option>
                          <option value="promotion">Promotion</option>
                          {(therapyPackages.length > 0 || therapyServices.length > 0) && <option value="therapy">Therapy</option>}
                          {creditPkgs.length > 0 && <option value="credit_package">Credit Package</option>}
                          {creditBundles.length > 0 && <option value="premium_bundle">Premium Bundle</option>}
                          {specialProducts.length > 0 && <option value="special_product">Special Product</option>}
                          {specialProducts.length > 0 && <option value="rental">Rental</option>}
                        </select>
                        {(line.kind === 'special_product' || line.kind === 'rental') ? (
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <SearchSelect value={line.special_product_id ?? ''}
                              onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, special_product_id: v } : l))}
                              placeholder="Search special product…"
                              options={specialProducts
                                .filter((sp: any) => line.kind === 'special_product'
                                  ? Number(sp.sale_price) > 0
                                  : (Number(sp.rate_day) > 0 || Number(sp.rate_week) > 0
                                     || Number(sp.rate_month) > 0 || Number(sp.rate_year) > 0))
                                .map((sp: any) => ({
                                  value: sp.id,
                                  label: line.kind === 'special_product'
                                    ? `${sp.name} — ${money(Number(sp.sale_price))}`
                                    : sp.name,
                                  sublabel: line.kind === 'rental' ? `${sp.sku ?? ''} · ${['day','week','month','year'].filter(k => Number(sp[`rate_${k}`]) > 0).map(k => `${k}: ${money(Number(sp[`rate_${k}`]))}`).join(' · ')}` : sp.sku,
                                  search: `${sp.name} ${sp.sku ?? ''}`,
                                  searchPrices: line.kind === 'special_product' ? [sp.sale_price] : ['day','week','month','year'].map(k => Number(sp[`rate_${k}`]) > 0 ? sp[`rate_${k}`] : null),
                                }))} />
                            {line.kind === 'rental' && line.special_product_id && (
                              <div style={{ display: 'flex', gap: 6, marginTop: 6, flexWrap: 'wrap', alignItems: 'flex-end' }}>
                                <div style={{ flex: '0 0 100px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Rate</div>
                                  <select value={line.rental_rate_type ?? 'day'}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, rental_rate_type: e.target.value as any } : l))}>
                                    {(() => {
                                      const sp = specialProducts.find((x: any) => x.id === line.special_product_id);
                                      const avail = (['day','week','month','year'] as const)
                                        .filter(rt => Number(sp?.[`rate_${rt}`] ?? 0) > 0);
                                      return avail.length > 0
                                        ? avail.map(rt => <option key={rt} value={rt}>Per {rt}</option>)
                                        : <option value="">No rental rate set</option>;
                                    })()}
                                  </select>
                                </div>
                                <div style={{ flex: '0 0 80px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Periods</div>
                                  <input type="number" min={1} value={line.rental_periods ?? 1}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i
                                      ? { ...l, rental_periods: Math.min(Math.max(1, Math.floor(+e.target.value || 1)), 3650) } : l))} />
                                </div>
                                <div style={{ flex: '0 0 140px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>From</div>
                                  <input type="date" value={line.rental_start_date ?? ''}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, rental_start_date: e.target.value } : l))} />
                                </div>
                                <div style={{ flex: '0 0 140px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Due back</div>
                                  <input type="date" value={line.rental_return_date ?? ''} min={line.rental_start_date}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, rental_return_date: e.target.value } : l))} />
                                </div>
                              </div>
                            )}
                          </div>
                        ) : line.kind === 'product' ? (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search product name or SKU…"
                            value={line.product_id}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, product_id: v } : l))}
                            options={storeProducts.map(p => { const a = productAvail(p.id); return {
                              value: p.id, label: `${p.name} — ${a.label}${a.needsOverride ? ' *' : ''}`,
                              sublabel: (p as any).sku, search: `${p.name} ${(p as any).sku ?? ''}`, searchPrices: [priceFor(activeStore, p.id)] }; })} />
                        ) : line.kind === 'voucher' ? (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search voucher name or code…"
                            value={line.voucher_id}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, voucher_id: v } : l))}
                            options={sellableVouchers.map(v => ({
                              value: v.id,
                              label: `${v.name}${voucherPrice(v.id) != null ? ` — ${money(voucherPrice(v.id)!)}` : ' — no price for this store'}`,
                              sublabel: (v as any).code, search: `${v.name} ${(v as any).code ?? ''}`, searchPrices: [voucherPrice(v.id)] }))} />
                        ) : line.kind === 'therapy' ? (
                          <div style={{ flex: 1, minWidth: 0 }}>
                          <SearchSelect placeholder="Search therapy package or session…"
                            value={line.therapy_service_id ? `session:${line.therapy_service_id}` : line.therapy_package_id ?? ''}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l,
                              therapy_service_id: v.startsWith('session:') ? v.slice(8) : '',
                              therapy_package_id: v.startsWith('session:') ? '' : v, therapy_benefit_intent: '', unit_price: undefined, quantity: 1 } : l))}
                            options={[
                              ...therapyPackages.map(p => { const pr = therapyPrice(p.id); return {
                                value: p.id, label: `${p.name} (${p.duration_months}mo)${pr != null ? ` — ${money(pr)}` : ' — no price for this store'}`, search: `${p.name} ${(p as any).code ?? ''}`, searchPrices: [pr] }; }),
                              ...therapyServices.map(p => ({ value: `session:${p.id}`, label: `${p.name} — session${sessionPrice(p.id) != null ? ` · ${money(sessionPrice(p.id)!)}` : ' — unavailable'}`, search: `${p.name} ${p.code ?? ''}`, searchPrices: [sessionPrice(p.id)] })),
                              ...(line.therapy_service_id && !therapyServices.some(p => p.id === line.therapy_service_id)
                                ? [{ value: `session:${line.therapy_service_id}`, label: `${line.therapy_service_name || 'Saved therapy session'} (saved)`, search: line.therapy_service_name }] : []),
                            ]} />
                        {(() => {
                          // Only a package that actually offers a choice asks for one.
                          const tp: any = therapyPackages.find((t: any) => t.id === line.therapy_package_id);
                          if (!tp || tp.entitlement_kind !== 'choice') return null;
                          const months = tp.duration_months ?? 0;
                          const qty = tp.voucher_qty ?? 0;
                          const opts: Array<[string, string, string]> = [
                            ['unlimited', `Unlimited therapy — ${months} calendar ${months === 1 ? 'month' : 'months'}`,
                             'Recorded now; it does not start until it is activated.'],
                            ['voucher', `Vouchers — ${qty} ${qty === 1 ? 'voucher' : 'vouchers'}`,
                             'Recorded now; nothing is issued until they are claimed.'],
                            ['', 'Choose later', 'No usable benefit is issued until the customer chooses.'],
                          ];
                          return (
                            <div className="benefit-options" role="radiogroup" aria-label="Benefit for this package">
                              {opts.map(([val, title, note]) => (
                                <label key={val || 'later'}
                                  className={`benefit-option${(line.therapy_benefit_intent ?? '') === val ? ' picked' : ''}`}>
                                  <input type="radio" name={`benefit-${i}`} value={val}
                                    checked={(line.therapy_benefit_intent ?? '') === val}
                                    onChange={() => setCLines(ls => ls.map((l, j) => j === i
                                      ? { ...l, therapy_benefit_intent: val as any } : l))} />
                                  <span>
                                    <strong>{title}</strong>
                                    <span className="benefit-option-note">{note}</span>
                                  </span>
                                </label>
                              ))}
                            </div>
                          );
                        })()}
                          </div>
                        ) : line.kind === 'credit_package' ? (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search Credit Package…"
                            value={line.credit_package_id ?? ''}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, credit_package_id: v, quantity: 1 } : l))}
                            options={creditPkgs.map((p: any) => ({
                              value: p.id,
                              label: `💳 ${p.name} — ${money(Number(p.customer_price))}`,
                              search: `${p.name} ${p.code ?? ''}`, searchPrices: [p.customer_price] }))} />
                        ) : line.kind === 'premium_bundle' ? (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search Premium Bundle…"
                            value={line.premium_bundle_id ?? ''}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, premium_bundle_id: v, quantity: 1, bundle_voucher_selection: {} } : l))}
                            options={creditBundles.map((b: any) => ({
                              value: b.id,
                              label: `💳 ${b.name} — ${money(Number(b.customer_payment_amount))}${b.grants_reward && (b.free_voucher_qty ?? 0) > 0 ? ` · ${b.free_voucher_qty} vouchers` : ''}`,
                              search: `${b.name} ${b.code ?? ''}`, searchPrices: [b.customer_payment_amount] }))} />
                        ) : (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search promotion name or code…"
                            value={line.promotion_id}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, promotion_id: v } : l))}
                            options={promotions.map(p => ({
                              value: p.id,
                              label: `${p.name}${promoPrice(p.id) != null ? ` — ${money(promoPrice(p.id)!)}` : ' — no price for this store'}`,
                              sublabel: (p as any).code, search: `${p.name} ${(p as any).code ?? ''}`, searchPrices: [promoPrice(p.id)] }))} />
                        )}
                        <input type="number" min={1} max={9999}
                          value={(line.kind === 'credit_package' || line.kind === 'premium_bundle') ? 1 : (line.quantity || '')}
                          placeholder="Qty" style={{ width: 70 }}
                          disabled={line.kind === 'credit_package' || line.kind === 'premium_bundle'}
                          title={(line.kind === 'credit_package' || line.kind === 'premium_bundle') ? 'Credit purchases are always quantity 1' : undefined}
                          onChange={e => setCLines(ls => ls.map((l, j) => j === i
                            ? { ...l, quantity: Math.min(Math.max(0, Math.floor(+e.target.value || 0)), 9999) } : l))} />
                        <span style={{ width: 78, textAlign: 'right', fontSize: 13, fontWeight: 600 }}>{price ? money(price * line.quantity) : '—'}</span>
                        <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setCLines(ls => ls.filter((_, j) => j !== i))} disabled={cLines.length === 1}><X size={13} /></button>
                      </div>
                      {editingInvoiceId && isOwnerOrManager(profile?.role) && <label className="invoice-finance-amount">Unit price
                        <input aria-label={`Line ${i + 1} unit price`} type="number" min="0" step="0.01" value={line.unit_price ?? ''}
                          onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, unit_price: Number(e.target.value) } : l))} />
                      </label>}
                      {/* Phase 12 — FOC. Quantity stays full (stock still moves); only the charge drops.
                          Credit purchases don't take a product-style FOC. */}
                      {line.kind !== 'credit_package' && line.kind !== 'premium_bundle'
                        && (line.kind !== 'product' || line.product_id) && (line.quantity ?? 0) > 0 && (
                        <div className="invoice-choice-group" style={{ display: 'flex', gap: 8, alignItems: 'center', marginLeft: 118, marginTop: -2, flexWrap: 'wrap' }}>
                          <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>FOC:</span>
                          <select
                            value={String(line.foc_quantity ?? 0)}
                            onChange={e => { const q = +e.target.value; setCLines(ls => ls.map((l, j) => j === i ? { ...l, foc_quantity: q, ...(q === 0 ? { foc_reason_id: '', foc_reason: '' } : {}) } : l)); }}
                            style={{ width: 108, fontSize: 12.5 }}>
                            <option value="0">None</option>
                            {Array.from({ length: Math.min(Math.max(0, Math.floor(line.quantity || 0)), 100) }, (_, k) => k + 1).map(q => (
                              <option key={q} value={q}>{q === line.quantity ? `All ${q} free` : `${q} free`}</option>
                            ))}
                          </select>
                          {(line.foc_quantity ?? 0) > 0 && (
                            <>
                              <select value={line.foc_reason_id ?? ''}
                                onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, foc_reason_id: e.target.value } : l))}
                                style={{ flex: 1, maxWidth: 220, fontSize: 12.5 }}>
                                <option value="">— Reason (required) —</option>
                                {line.foc_reason_id && !focReasons.some(r => r.id === line.foc_reason_id) && <option value={line.foc_reason_id}>{line.foc_reason || 'Saved FOC reason'} (historical)</option>}
                                {focReasons.map(r => <option key={r.id} value={r.id}>{r.label}{r.requires_note ? ' *' : ''}</option>)}
                              </select>
                              <input type="text" placeholder="Note" value={line.foc_reason ?? ''}
                                onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, foc_reason: e.target.value } : l))}
                                style={{ flex: 1, maxWidth: 200, fontSize: 12.5 }} />
                              {price ? (
                                <span style={{ fontSize: 11.5, color: 'var(--success)' }}>
                                  free {money(price * (line.foc_quantity ?? 0))}
                                </span>
                              ) : null}
                            </>
                          )}
                        </div>
                      )}
                      {line.kind === 'product' && line.product_id && isThirdParty(line.product_id) && (
                        <div style={{ marginLeft: 118, marginTop: -2, fontSize: 11.5, color: 'var(--text-muted)' }}>
                          3rd-party product — discount vouchers don't apply. A manual
                          discount still does.
                        </div>
                      )}
                      {line.kind === 'product' && line.product_id && !isThirdParty(line.product_id) && discountVouchers.length > 0 && (
                        <div className="invoice-choice-group" style={{ display: 'flex', gap: 8, alignItems: 'center', marginLeft: 118, marginTop: -2 }}>
                          <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Line voucher:</span>
                          <select value={line.line_voucher_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, line_voucher_id: e.target.value } : l))} style={{ flex: 1, maxWidth: 320, fontSize: 12.5 }}>
                            <option value="">— None —</option>
                            {discountVouchers.filter(v => v.voucher_kind !== 'fixed_discount' || (v.discount_amount ?? 0) < (lineUnit(line) ?? 0) * line.quantity).map(v => (
                              <option key={v.id} value={v.id}>
                                {v.name} — {v.voucher_kind === 'fixed_discount' ? money(v.discount_amount ?? 0) + ' off' : `${v.discount_percent}% off${v.max_discount_cap ? ` (cap ${money(v.max_discount_cap)})` : ''}`}
                              </option>
                            ))}
                          </select>
                          {line.line_voucher_id && price ? <span style={{ fontSize: 11.5, color: 'var(--success)' }}>− {money(voucherDiscAmount(vouchers.find(v => v.id === line.line_voucher_id), price * line.quantity))}</span> : null}
                        </div>
                      )}
                      {line.kind === 'premium_bundle' && line.premium_bundle_id && (() => {
                        const need = bundleGrants(line.premium_bundle_id);
                        if (need <= 0) {
                          return (
                            <div className="invoice-choice-group" style={{ marginLeft: 28, marginTop: 4, fontSize: 11.5, color: 'var(--text-muted)' }}>
                              This bundle grants no reward vouchers.
                            </div>
                          );
                        }
                        const opts = bundleVoucherOpts[line.premium_bundle_id] ?? [];
                        const basket = line.bundle_voucher_selection ?? {};
                        const chosen = Object.values(basket).reduce((a, c) => a + (c || 0), 0);
                        const setBasket = (fn: (b: Record<string, number>) => Record<string, number>) =>
                          setCLines(ls => ls.map((l, j) => j === i ? { ...l, bundle_voucher_selection: fn(l.bundle_voucher_selection ?? {}) } : l));
                        return (
                          <div className="invoice-choice-group" style={{ marginLeft: 28, marginTop: 6, marginBottom: 6 }}>
                            <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 4 }}>
                              Choose {need} reward voucher(s) — {chosen}/{need} selected
                            </div>
                            <div style={{ maxHeight: 200, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                              {opts.length === 0 && <div style={{ padding: 10, fontSize: 12, color: 'var(--text-muted)' }}>No eligible vouchers available at this store.</div>}
                              {opts.map((v: any) => {
                                const cur = basket[v.voucher_id] ?? 0;
                                const cap = v.available_qty == null ? need : Math.min(need, v.available_qty);
                                return (
                                  <div key={v.voucher_id} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, padding: '6px 9px', borderBottom: '1px solid var(--border)' }}>
                                    <div style={{ fontSize: 12.5 }}>{v.name}
                                      <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{v.available_qty == null ? 'unlimited' : `${v.available_qty} in stock`}</div>
                                    </div>
                                    <div className="invoice-choice-stepper" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                                      <button className="btn btn-secondary btn-sm" disabled={cur <= 0}
                                        onClick={() => setBasket(bk => ({ ...bk, [v.voucher_id]: Math.max(0, (bk[v.voucher_id] ?? 0) - 10) }))}>−10</button>
                                      <span style={{ minWidth: 30, textAlign: 'center', fontSize: 13 }}>{cur}</span>
                                      <button className="btn btn-secondary btn-sm" disabled={chosen >= need || cur >= cap}
                                        onClick={() => setBasket(bk => ({ ...bk, [v.voucher_id]: Math.min(cap, (bk[v.voucher_id] ?? 0) + 10) }))}>+10</button>
                                    </div>
                                  </div>
                                );
                              })}
                            </div>
                            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                              Mix any eligible vouchers up to the required quantity. Stock is checked before the invoice is created.
                            </div>
                          </div>
                        );
                      })()}
                      {line.kind === 'promotion' && line.promotion_id && includedFor(line.promotion_id).length > 0 && (
                        <div className="invoice-choice-group" style={{ marginLeft: 28, marginTop: 6, marginBottom: 6, border: '1px solid var(--border)',
                                      borderRadius: 'var(--radius-sm)', overflow: 'hidden' }}>
                          <div style={{ padding: '6px 10px', background: 'var(--bg)', fontSize: 12, fontWeight: 700 }}>
                            Included in this bundle ({includedFor(line.promotion_id).length})
                          </div>
                          {includedFor(line.promotion_id).map(it => (
                            <div key={it.id} style={{ display: 'flex', justifyContent: 'space-between',
                                                      padding: '5px 10px', fontSize: 12.5, borderTop: '1px solid var(--border)' }}>
                              <span>
                                {it.kind === 'voucher' ? '🎟 ' : it.kind === 'therapy' ? '✨ ' : it.kind === 'credit_package' ? '💳 ' : '📦 '}
                                {it.label}
                              </span>
                              <span style={{ color: 'var(--text-muted)' }}>
                                × {it.qty * line.quantity}
                              </span>
                            </div>
                          ))}
                          <div style={{ padding: '5px 10px', fontSize: 11, color: 'var(--text-muted)', borderTop: '1px solid var(--border)' }}>
                            Always included — no choice needed. The bundle price already covers these.
                          </div>
                        </div>
                      )}
                      {line.kind === 'promotion' && line.promotion_id && groupsFor(line.promotion_id).map(g => {
                        const need = g.choose_qty * line.quantity;
                        const got = selSum(line, g.id);
                        const done = got === need;
                        const isProd = g.item_kind === 'product';
                        const baseline = isProd ? groupBaseline(g.id, effMember) : null;
                        // Which column holds the option's id depends on the
                        // group's kind. This was product-or-voucher only, so a
                        // therapy, credit-package or promotion group showed an
                        // empty picker with nothing to choose.
                        const optionIdOf = (o: any): string | null =>
                          g.item_kind === 'voucher' ? o.voucher_id
                          : g.item_kind === 'therapy' ? o.therapy_package_id
                          : g.item_kind === 'credit_package' ? o.credit_package_id
                          : g.item_kind === 'promotion' ? o.child_promotion_id
                          : o.product_id;
                        const optionItemIds = optionsFor(g.id)
                          .map(optionIdOf)
                          .filter((x): x is string => !!x)
                          .filter(x => !isProd || stockQty(cStore, x) > 0);
                        const pickedIds = Object.entries(line.selections[g.id] ?? {}).filter(([, q]) => (q || 0) > 0).map(([id]) => id);
                        const extraIds = pickedIds.filter(id => !optionItemIds.includes(id));
                        const displayIds = [...optionItemIds, ...extraIds];
                        const itemName = (id: string) =>
                          g.item_kind === 'voucher' ? (vouchers.find(v => v.id === id)?.name ?? '—')
                          : g.item_kind === 'therapy' ? (therapyPackages.find((t: any) => t.id === id)?.name ?? '—')
                          : g.item_kind === 'credit_package' ? (creditPkgs.find((c: any) => c.id === id)?.name ?? '—')
                          : g.item_kind === 'promotion' ? (promotions.find(pr => pr.id === id)?.name ?? '—')
                          : (products.find(p => p.id === id)?.name ?? '—');
                        // Display value inside a promotion choice picker. Products use
                        // the mode-aware store price; the voucher branch shows its
                        // Member/Non-Member store price (no legacy selling_price).
                        // Shown for information. Only a product group can add a
                        // top-up; every other kind is covered by the promotion's
                        // own price, so these figures never change what is charged.
                        const itemPrice = (id: string): number | null =>
                          g.item_kind === 'voucher' ? voucherPrice(id)
                          : g.item_kind === 'promotion' ? promoPrice(id)
                          : isProd ? priceFor(activeStore, id)
                          : null;
                        // The quantity can now be TYPED, not only stepped, since a group
                        // may call for 60 or more. The cap lives here rather than on the
                        // "+" button alone, so a typed figure cannot exceed what the
                        // group needs — the invoice would be rejected otherwise.
                        const setQty = (itemId: string, q: number) => setCLines(ls => ls.map((l, j) => {
                          if (j !== i) return l;
                          const current = l.selections[g.id] ?? {};
                          const wanted = Math.max(0, Math.floor(Number.isFinite(q) ? q : 0));
                          const others = Object.entries(current)
                            .filter(([k]) => k !== itemId)
                            .reduce((a, [, v]) => a + (Number(v) || 0), 0);
                          const room = Math.max(0, (g.choose_qty * l.quantity) - others);
                          return { ...l, selections: { ...l.selections,
                            [g.id]: { ...current, [itemId]: Math.min(wanted, room) } } };
                        }));
                        return (
                          <div key={g.id} className="invoice-choice-group" style={{ marginLeft: 118, border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', overflow: 'hidden' }}>
                            <div className="invoice-choice-header" style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px', background: 'var(--surface-2)' }}>
                              <strong className="invoice-choice-name" style={{ flex: 1, fontSize: 12.5 }}>{g.label}</strong>
                              {isProd && baseline != null && <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>base {money(baseline)}</span>}
                              <span className={`badge ${done ? 'badge-success' : 'badge-danger'}`}>{got} / {need} chosen</span>
                            </div>
                            <div>
                              {displayIds.map(id => {
                                const pr = itemPrice(id);
                                const isListed = optionItemIds.includes(id);
                                const topup = isProd && !isListed && baseline != null && pr != null && pr > baseline ? pr - baseline : 0;
                                const val = line.selections[g.id]?.[id] ?? 0;
                                return (
                                  <div key={id} className="invoice-choice-row" style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 12px', borderTop: '1px solid var(--border)' }}>
                                    <span className="invoice-choice-name" style={{ flex: 1, fontSize: 12.5, fontWeight: val > 0 ? 600 : 400 }}>{itemName(id)}</span>
                                    <span style={{ fontSize: 11.5, color: 'var(--text-muted)', minWidth: 62, textAlign: 'right' }}>{pr != null ? money(pr) : '—'}</span>
                                    <span style={{ fontSize: 11, minWidth: 74, textAlign: 'right', color: topup > 0 ? 'var(--danger)' : 'var(--text-muted)' }}>
                                      {topup > 0 ? `+${money(topup)} top-up` : isProd ? (isListed ? 'included' : 'no top-up') : ''}
                                    </span>
                                    <div className="invoice-choice-stepper" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                                      <button className="btn btn-secondary btn-sm btn-icon" style={{ width: 26, height: 26, padding: 0 }} aria-label={`Remove ${itemName(id)}`} onClick={() => setQty(id, val - 1)} disabled={val <= 0}>−</button>
                                      <input aria-label={`${itemName(id)} quantity`} type="number" min={0} max={need} value={val === 0 ? '' : val}
                                        placeholder="0"
                                        onChange={e => setQty(id, e.target.value === '' ? 0 : +e.target.value)}
                                        onFocus={e => e.currentTarget.select()}
                                        style={{ width: 54, textAlign: 'center', fontSize: 13, fontWeight: 600,
                                                 padding: '2px 4px', height: 26 }} />
                                      <button className="btn btn-secondary btn-sm btn-icon" style={{ width: 26, height: 26, padding: 0 }} aria-label={`Add ${itemName(id)}`} onClick={() => setQty(id, val + 1)} disabled={done}>+</button>
                                    </div>
                                  </div>
                                );
                              })}
                              {isProd && (
                                <div className="invoice-choice-other" style={{ display: 'flex', gap: 8, alignItems: 'center', padding: '8px 12px', borderTop: '1px solid var(--border)', background: 'var(--surface-2)' }}>
                                  <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Other product:</span>
                                  <select value="" onChange={e => { if (e.target.value) setQty(e.target.value, (line.selections[g.id]?.[e.target.value] ?? 0) + 1); }} style={{ flex: 1, fontSize: 12.5 }} disabled={done}>
                                    <option value="">— pick any product (top-up applies above base) —</option>
                                    {storeProducts.filter(p => !displayIds.includes(p.id)).map(p => {
                                      const lm = effMember;
                                      const pr = priceFor(activeStore, p.id, lm);
                                      const tu = baseline != null && pr != null && pr > baseline ? pr - baseline : 0;
                                      return <option key={p.id} value={p.id}>{p.name} — {pr != null ? money(pr) : '—'}{tu > 0 ? ` (+${money(tu)} top-up)` : ''}</option>;
                                    })}
                                  </select>
                                </div>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </React.Fragment>
                    );
                  })}
                </div>
                <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setCLines(ls => [...ls, { kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }])}><Plus size={13} /> Add Item</button>
              </div>
            )}

            {cStore && discountVouchers.length > 0 && (
              <div className="form-group">
                <label>Discount Voucher (optional — one per invoice{hasPromoLine ? '; not available on bundle invoices' : ''})</label>
                <select value={cDiscountVoucher} onChange={e => setCDiscountVoucher(e.target.value)} disabled={hasPromoLine}>
                  <option value="">— None —</option>
                  {eligibleWholeVouchers.map(v => (
                    <option key={v.id} value={v.id}>
                      {v.name} — {v.voucher_kind === 'fixed_discount' ? money(v.discount_amount ?? 0) + ' off' : `${v.discount_percent}% off${v.max_discount_cap ? ` (cap ${money(v.max_discount_cap)})` : ''}`}
                    </option>
                  ))}
                </select>
                <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>Applied to the invoice subtotal. The exact amount is confirmed on the created invoice.</span>
              </div>
            )}

            <div className="form-grid-2">
              <div className="form-group"><label>Manual Discount (S$)</label>
                <input type="number" min={0} step={0.01} value={cDiscount || ''} onChange={e => setCDiscount(+e.target.value)} placeholder="0.00" />
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  Applies to everything on the invoice — products, third-party items, vouchers,
                  promotions and therapy — capped at the subtotal.
                </div>
                {(cDiscount || 0) > 0 && (() => {
                  const required = !editingInvoiceId || Number(cDiscount) !== Number(discountBeforeEdit);
                  return (
                    <div style={{ marginTop: 8 }}>
                      <label htmlFor="manual-discount-reason">Manual discount reason{required && <span aria-hidden="true"> *</span>}</label>
                      <input id="manual-discount-reason" ref={discountReasonRef} value={cDiscountReason} maxLength={300}
                        onChange={e => { setCDiscountReason(e.target.value); if (discountReasonErr) setDiscountReasonErr(null); }}
                        placeholder="Internal — why this discount was given"
                        aria-required={required} aria-invalid={!!discountReasonErr}
                        aria-describedby={discountReasonErr ? 'manual-discount-reason-error' : 'manual-discount-reason-help'} />
                      {discountReasonErr
                        ? <div id="manual-discount-reason-error" role="alert" style={{ fontSize: 12, color: 'var(--danger)', marginTop: 3 }}>{discountReasonErr}</div>
                        : <div id="manual-discount-reason-help" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                            {required
                              ? 'Kept on the invoice record for staff. Never printed or sent to the customer.'
                              : cDiscountReason.trim()
                                ? 'Kept on the invoice record for staff. Never printed or sent to the customer.'
                                : 'No reason was recorded when this discount was given. One is only needed if the amount changes.'}
                          </div>}
                    </div>
                  );
                })()}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
                <div style={{ textAlign: 'right', fontSize: 13, color: 'var(--text-secondary)' }}>Subtotal: <strong>{money(createSubtotal)}</strong></div>
                {focValuePreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--success)' }}>FOC given: {money(focValuePreview)}</div>}
                {topupPreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>+ top-up {money(topupPreview)}</div>}
                {(cDiscount || 0) > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− manual discount {money(cDiscount)}</div>}
                {lineVoucherDiscountPreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− line vouchers {money(lineVoucherDiscountPreview)}</div>}
                {cDiscountVoucher && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− voucher discount {money(voucherDiscountPreview)}</div>}
                <div style={{ textAlign: 'right', fontSize: 16, fontWeight: 700, marginTop: 2 }}>Total: {money(previewTotal)}</div>
              </div>
            </div>
            </>)}
          </div>
        </Modal>
      )}

      {/* Invoice detail + payment modal */}
      {detail && (
        <Modal title={`Invoice ${detail.invoice_no}`} wide onClose={() => setDetail(null)}
          footer={
            detail.status === 'paid'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  {isOwnerOrManager(profile?.role) && (
                    <button className="btn btn-secondary" onClick={openEdit}
                      title="Correct this invoice with a reason and revision history">
                      <FileText size={14} /> Correct Invoice</button>
                  )}
                  {refundCancelButton}
                  {!isOwnerOrManager(profile?.role) && <button className="btn btn-danger" onClick={() => { setActionType('invoice_refund'); setActionReturnStock(true); setActionReason(''); setActionErr(null); }}>Request Refund</button>}</>
              : detail.status === 'cancelled' || detail.status === 'refunded' || detail.status === 'cancellation_requested' || detail.status === 'refund_requested'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>{isOwnerOrManager(profile?.role) && <button className="btn btn-secondary" onClick={openEdit}>Correct Invoice</button>}{refundCancelButton}</>
              : (detail.status === 'unpaid' || detail.status === 'draft') && Number(detail.paid_amount) === 0
                  && !(detail as any).is_topup && !(detail as any).is_exchange && detailPayments.length === 0
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button>
                  <button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  <button className="btn btn-secondary" onClick={openEdit}><FileText size={14} /> Edit Invoice</button>
                  {refundCancelButton}
                  {detail.is_full_foc && Number(detail.total_amount) <= 0
                    ? <button className="btn btn-primary" onClick={handleConfirmFoc} disabled={focBusy}><Sparkles size={15} /> {focBusy ? 'Confirming…' : 'Confirm FOC Invoice'}</button>
                    : <button className="btn btn-primary" onClick={handlePay} disabled={payBusy || Boolean(payBlockedReason)}
                        title={payBlockedReason ?? undefined}><CreditCard size={15} /> {payBusy ? 'Processing…' : 'Record Payment'}</button>}</>
              : detail.status === 'completed_foc'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></>
              : <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  {canManageInvoice && needsAuditedCorrection &&
                    <button className="btn btn-secondary" onClick={openEdit}
                      title="Correct this invoice with a reason and revision history">
                      <FileText size={14} /> Correct Invoice</button>}
                  {refundCancelButton}
                  {detail.is_full_foc && Number(detail.total_amount) <= 0
                    ? <button className="btn btn-primary" onClick={handleConfirmFoc} disabled={focBusy}><Sparkles size={15} /> {focBusy ? 'Confirming…' : 'Confirm FOC Invoice'}</button>
                    : <button className="btn btn-primary" onClick={handlePay} disabled={payBusy || Boolean(payBlockedReason)}
                        title={payBlockedReason ?? undefined}><CreditCard size={15} /> {payBusy ? 'Processing…' : 'Record Payment'}</button>}</>
          }>
          <div className="form-grid">
            {detailReloadError && (
              <div className="alert alert-warning invoice-refresh-error" role="alert" data-testid="invoice-detail-reload-error">
                <div>{detailReloadError}</div>
                <button type="button" className="btn btn-secondary btn-sm" onClick={() => void reloadStaleDetail()}><RefreshCw size={13} /> Reload</button>
              </div>
            )}
            {detailStale && (
              <div className="alert alert-warning invoice-refresh-error" role="alert" data-testid="invoice-detail-stale">
                <div><strong>This invoice was changed by another user or tab</strong> since it was opened. What you have entered here is kept; reload to see the current figures before recording anything.</div>
                <button type="button" className="btn btn-secondary btn-sm" onClick={() => void reloadStaleDetail()}><RefreshCw size={13} /> Reload invoice</button>
              </div>
            )}
            {detailUpdatedNote && (
              <div className="alert alert-info" role="status" data-testid="invoice-detail-updated" style={{ marginBottom: 0 }}>{detailUpdatedNote}</div>
            )}
            {/* Correction lives in the footer now, once, beside Refund / Cancel.
                An ordinary unpaid invoice offers Edit Invoice there instead. */}
            <div data-testid="invoice-detail-date"><strong>Invoice date: {displayInvoiceDate(detail)}</strong>
            </div>
            {Number((detail as any).manual_discount ?? 0) > 0 && (
              <p data-testid="invoice-detail-discount-reason" style={{ fontSize: 12.5, margin: 0 }}>
                Manual discount {money(Number((detail as any).manual_discount))} · internal reason:{' '}
                {String((detail as any).manual_discount_reason ?? '').trim()
                  ? <strong>{(detail as any).manual_discount_reason}</strong>
                  : <em>none recorded (given before reasons were required)</em>}
              </p>
            )}
            {instalmentText(detail as any, methods) && <p>{instalmentText(detail as any, methods)}</p>}
            <InvoiceFinancePanel invoiceId={detail.id} canManage={isOwnerOrManager(profile?.role)} payments={detailPayments} methods={methods} stores={stores}
              requestedMode={financeRequest?.mode ?? null} requestedPaymentId={financeRequest?.paymentId ?? null}
              onRequestHandled={() => setFinanceRequest(null)}
              onActiveChange={active => { financeActiveRef.current = active; }}
              onChanged={async () => {
                // The action is recorded. From here a failure is a display
                // failure: said beside the invoice, never as a failed action.
                const id = detail.id;
                noteLocalChangeRef.current([id]);
                try { await refreshDetail(id); setDetailReloadError(null); }
                catch (e: any) {
                  setDetailReloadError(`The change was saved. This invoice could not be reloaded just now${e?.message ? ` (${e.message})` : ''} — reload to see its updated figures. Do not repeat the action.`);
                }
                void refreshList({ afterSave: 'The change was saved', changed: [id] });
              }} />
            {focErr && <div className="alert alert-danger" style={{ fontSize: 12.5 }}>{focErr}</div>}
            {detailExchange?.found && (
              <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px', background: 'var(--surface-2)', fontSize: 12.5 }}>
                <div style={{ fontWeight: 700, marginBottom: 4 }}>Exchange Invoice — {detailExchange.exchange_no}</div>
                <div style={{ color: 'var(--text-muted)' }}>Original invoice: <b>{detailExchange.original_invoice_no}</b>{detailExchange.reason ? <> · Reason: {detailExchange.reason}</> : null}</div>
                <div style={{ marginTop: 6 }}>
                  <div style={{ fontWeight: 600 }}>Returned</div>
                  {(detailExchange.returned_items ?? []).map((r: any, i: number) => (
                    <div key={i} style={{ display: 'flex', justifyContent: 'space-between' }}><span>{r.product} × {r.quantity}</span><span>{money(Number(r.line_total))}</span></div>
                  ))}
                  <div style={{ fontWeight: 600, marginTop: 4 }}>Replacement</div>
                  {(detailExchange.replacement_items ?? []).map((r: any, i: number) => (
                    <div key={i} style={{ display: 'flex', justifyContent: 'space-between' }}><span>{r.product} × {r.quantity}</span><span>{money(Number(r.line_total))}</span></div>
                  ))}
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4, color: 'var(--success)' }}><span>Exchange credit</span><span>− {money(Number(detailExchange.exchange_credit_applied ?? 0))}</span></div>
                  {Number(detailExchange.nonrefundable ?? 0) > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--text-muted)' }}><span>Non-refundable difference</span><span>{money(Number(detailExchange.nonrefundable))}</span></div>}
                  {Number(detailExchange.foc_waived ?? 0) > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--success)' }}><span>FOC (waived top-up)</span><span>− {money(Number(detailExchange.foc_waived))}</span></div>}
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, marginTop: 2 }}><span>Net top-up paid</span><span>{money(Number(detailExchange.net_topup ?? 0))}</span></div>
                </div>
                <div style={{ color: 'var(--text-muted)', marginTop: 6 }}>Processed by {detailExchange.processed_by ?? '—'} · {detailExchange.processing_store ?? ''}</div>
              </div>
            )}
            {/* Summary */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{storeName(detail.store_id)} · {custName(detail.customer_id)}</div>
                <div style={{ marginTop: 4 }}><StatusBadge s={detail.status} /></div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 20, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(detail.total_amount)}</div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Paid {money(detail.paid_amount)}</div>
                {Number(detail.foc_total ?? 0) > 0 && (
                  <div style={{ fontSize: 12, color: 'var(--success)', fontWeight: 600 }}>
                    {detail.is_full_foc ? 'Fully FOC' : 'Incl. FOC'} {money(Number(detail.foc_total))}
                  </div>
                )}
              </div>
            </div>

            {/* Affiliate selector — only while the invoice is unpaid and unlocked. */}
            {(detail.status === 'unpaid' || detail.status === 'draft') && Number(detail.paid_amount) === 0
              && !(detail as any).is_topup && !(detail as any).is_exchange && detailPayments.length === 0 && (
              <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px' }}>
                <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>Affiliate</div>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                  <SearchSelect style={{ maxWidth: 300, flex: 1 }}
                    placeholder="Search affiliate name, phone or email…"
                    value={(detail as any).affiliate_id ?? (effAffiliate?.affiliate_id ?? '')}
                    disabled={affiliateBusy}
                    onChange={v => changeInvoiceAffiliate(v === '' ? null : v)}
                    options={affiliateOptions.map((a: any) => ({
                      value: a.affiliate_id,
                      label: a.full_name,
                      sublabel: [a.phone, a.email].filter(Boolean).join(' · ') || undefined,
                      search: `${a.full_name} ${a.phone ?? ''} ${a.email ?? ''}`,
                    }))} />
                  {affiliateBusy && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>Saving…</span>}
                </div>
                {affiliateErr && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>{affiliateErr}</div>}
                {effAffiliate?.has_affiliate ? (
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 5 }}>
                    {effAffiliate.source === 'invoice'
                      ? <>Chosen for this invoice: <strong>{effAffiliate.full_name}</strong> earns Tier 1.</>
                      : <>From this customer's referrer: <strong>{effAffiliate.full_name}</strong> earns Tier 1{effAffiliate.tier2_name ? <> and {effAffiliate.tier2_name} earns Tier 2</> : null}.</>}
                    {effAffiliate.is_registered_affiliate === false && (
                      <span style={{ color: 'var(--danger)' }}> This person is not a registered affiliate, so no commission will be paid.</span>
                    )}
                    {effAffiliate.is_registered_affiliate && effAffiliate.is_active_affiliate === false && (
                      <span style={{ color: 'var(--danger)' }}> Their affiliate account is not active, so commission will be blocked.</span>
                    )}
                  </div>
                ) : (
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 5 }}>
                    This customer has no referrer, so no affiliate is credited unless you choose one.
                  </div>
                )}
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                  Choose a different affiliate to credit this sale instead. This can be changed until the invoice is paid.
                </div>
              </div>
            )}

            {revisions.length > 0 && (
              <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
                <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 6 }}>
                  Corrections ({revisions.length})
                </div>
                {revisions.map(r => (
                  <div key={r.revision_no} style={{ fontSize: 12, marginBottom: 4 }}>
                    <strong>#{r.revision_no}</strong>{' '}
                    {new Date(r.edited_at).toLocaleString()} — {r.edited_by_name ?? 'Unknown'}
                    <div style={{ color: 'var(--text-muted)' }}>
                      Was S${Number(r.old_total ?? 0).toFixed(2)} ({String(r.from_status ?? '').replace(/_/g,' ')})
                      {r.edit_reason ? ` · ${r.edit_reason}` : ''}
                    </div>
                  </div>
                ))}
              </div>
            )}
            {sendErr && <div className="alert alert-danger"><span>⚠</span><div>{sendErr}</div></div>}
            {sendNote && <div className="alert alert-info"><span>ℹ</span><div>{sendNote}</div></div>}

            {isOwnerOrManager(profile?.role) && ['draft','unpaid','partially_paid'].includes(detail.status) && (
              <div>
                <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 4 }}>Fulfil from</div>
                <select value={(detail as any).fulfil_warehouse_id ?? ''} disabled={fulfilBusy} style={{ maxWidth: 280 }}
                  onChange={e => setFulfilment(e.target.value === '' ? null : e.target.value)}>
                  <option value="">This store's stock</option>
                  {warehouses.map(w => <option key={w.id} value={w.id}>{w.name} (warehouse)</option>)}
                </select>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                  Choosing a warehouse takes the goods out of warehouse stock instead of this store's.
                  The invoice still belongs to the store for pricing, commission and reporting.
                  Owner/Manager only.
                </div>
                {fulfilErr && <div className="alert alert-danger" style={{ marginTop: 6, marginBottom: 0 }}><span>⚠</span><div>{fulfilErr}</div></div>}
              </div>
            )}

            {invLegacy.length > 0 && (
              <div style={{ border: '1px solid var(--success)', background: 'var(--success-light)', borderRadius: 'var(--radius-sm)', padding: '10px 12px' }}>
                <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>
                  Legacy therapy earned {invLegacy.length > 1 ? `(${invLegacy.length})` : ''}
                </div>
                {invLegacy.map(e => (
                  <div key={e.id} style={{ fontSize: 12, marginBottom: 3 }}>
                    <strong>{e.entitlement_no}</strong> · {e.package_name}
                    {e.entitlement_kind === 'voucher' ? ` · ${e.voucher_qty ?? 0} voucher(s)` : e.duration_months ? ` · ${e.duration_months} months` : ''}
                    {' · '}
                    {e.status === 'pending_activation'
                      ? <span>unclaimed — claim by {e.activation_deadline ? new Date(e.activation_deadline).toLocaleDateString('en-GB') : '—'} under Therapy → Legacy Therapy</span>
                      : <span>{String(e.status).replace('_', ' ')}{e.expiry_date ? ` until ${new Date(e.expiry_date).toLocaleDateString('en-GB')}` : ''}</span>}
                  </div>
                ))}
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                  Earned from this customer's same-day paid total at this store.
                </div>
              </div>
            )}

            {detailRevisions.length > 0 && (
              <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                <b>Edit history:</b> {detailRevisions.map(r =>
                  `#${r.revision_no} ${new Date(r.edited_at).toLocaleString('en-GB')}${r.edit_reason ? ` — ${r.edit_reason}` : ''}`
                ).join(' · ')}
              </div>
            )}
            {/* Items */}
            <div>
              <label>Items</label>
              <table style={{ marginTop: 4 }}>
                <thead><tr><th>Product</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Price</th><th style={{ textAlign: 'right' }}>Total</th></tr></thead>
                <tbody>
                  {detailItems.map(it => {
                    const isPromo = it.line_kind === 'promotion';
                    const fixed = isPromo ? detailPromoItems.filter(p => p.promotion_id === (it as any).promotion_id) : [];
                    const chosen = isPromo ? detailSelections.filter(s => s.invoice_item_id === it.id) : [];
                    // Therapy and credit packages fell through to "—", so a
                    // promotion containing therapy showed a row with no name
                    // once the invoice existed, even though the creation form
                    // named it correctly. Checked by id as well as item_type,
                    // since a chosen option carries the id without the type.
                    const subLabel = (x: any): string => {
                      if (x.item_type === 'product' || x.product_id) return `📦 ${prodName(x.product_id ?? '')}`;
                      if (x.item_type === 'voucher' || x.voucher_id) return `🎟 ${vouchers.find(v => v.id === x.voucher_id)?.name ?? 'Voucher'}`;
                      if (x.item_type === 'promotion') return `🧩 ${promotions.find(p => p.id === x.child_promotion_id)?.name ?? 'Promotion'}`;
                      if (x.item_type === 'therapy' || x.therapy_package_id)
                        return `🧖 ${therapyPackages.find((t: any) => t.id === x.therapy_package_id)?.name ?? 'Therapy'}`;
                      if (x.item_type === 'credit_package' || x.credit_package_id) return '💳 Credit package';
                      if (x.item_type === 'treatment') return `💆 ${x.treatment_name}`;
                      return '—';
                    };
                    return (
                      <React.Fragment key={it.id}>
                        <tr>
                          <td>{it.line_kind === 'voucher' ? `🎟 ${vouchers.find(v => v.id === it.voucher_id)?.name ?? 'Voucher'}` : isPromo ? `🧩 ${promotions.find(p => p.id === (it as any).promotion_id)?.name ?? 'Promotion'}` : (it.line_kind === 'credit_package' || it.line_kind === 'premium_bundle') ? `💳 ${creditLineName(it)}` : it.line_kind === 'therapy' ? ((it as any).therapy_service_name_snapshot || (it as any).plan_name_snapshot || 'Therapy') : prodName(it.product_id ?? '')}
                            {it.line_kind === 'product' && (it as any).line_voucher_id ? <div style={{ fontSize: 11, color: 'var(--success)' }}>🎟 {vouchers.find(v => v.id === (it as any).line_voucher_id)?.name ?? 'Voucher'} − {money(Number((it as any).line_discount ?? 0))}</div> : null}
                            {isPromo && Number((it as any).topup_amount ?? 0) > 0 ? <div style={{ fontSize: 11, color: 'var(--danger)' }}>+ top-up {money(Number((it as any).topup_amount))}</div> : null}
                            {Number(it.foc_quantity ?? 0) === 0 && detail.status !== 'paid' && detail.status !== 'completed_foc'
                              && detail.status !== 'cancelled' && detail.status !== 'refunded' && Number(detail.paid_amount) === 0 && (
                              <div style={{ fontSize: 11 }}>
                                <button className="btn btn-secondary btn-sm" style={{ padding: '1px 7px', fontSize: 10.5 }}
                                  onClick={() => { setFocLine(it); setFocQty(it.quantity); setFocReasonId(''); setFocNote(''); setFocErr(null); }}>
                                  Make FOC
                                </button>
                              </div>
                            )}
                            {Number(it.foc_quantity ?? 0) > 0 && (
                              <div style={{ fontSize: 11, color: 'var(--success)', fontWeight: 600 }}>
                                {it.is_foc ? 'FOC' : `FOC ${it.foc_quantity} of ${it.quantity}`} — free {money(Number(it.foc_amount ?? 0))}
                                {it.foc_reason ? <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}> · {it.foc_reason}</span> : null}
                                {detail.status !== 'paid' && detail.status !== 'completed_foc' && detail.status !== 'cancelled' && detail.status !== 'refunded' && Number(detail.paid_amount) === 0 && (
                                  <button className="btn btn-secondary btn-sm" style={{ marginLeft: 6, padding: '1px 7px', fontSize: 10.5 }}
                                    disabled={focBusy} onClick={() => handleRemoveLineFoc(it.id)}>Remove FOC</button>
                                )}
                              </div>
                            )}
                          </td>
                          <td style={{ textAlign: 'right' }}>{it.quantity}</td>
                          <td style={{ textAlign: 'right' }}>{money(it.unit_price)}</td>
                          <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(it.line_total)}</td>
                        </tr>
                        {fixed.map(f => (
                          <tr key={`f-${f.id}`}>
                            <td colSpan={4} style={{ paddingLeft: 26, fontSize: 12, color: 'var(--text-muted)', borderTop: 'none' }}>
                              └ {subLabel(f)} × {f.quantity * it.quantity} <span style={{ fontSize: 10.5 }}>(included)</span>
                            </td>
                          </tr>
                        ))}
                        {chosen.map(s => (
                          <tr key={`s-${s.id}`}>
                            <td colSpan={4} style={{ paddingLeft: 26, fontSize: 12, color: 'var(--text-muted)', borderTop: 'none' }}>
                              └ {subLabel(s)} × {s.quantity} <span style={{ fontSize: 10.5 }}>(chosen)</span>
                            </td>
                          </tr>
                        ))}
                      </React.Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>

            {/* Existing payments */}
            {detailServiceStaff.length > 0 && (
              <div>
                <label>Served by</label>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 4 }}>
                  {detailServiceStaff.map(id => <span key={id} className="badge badge-primary">{staffName(id)}</span>)}
                </div>
              </div>
            )}

            {detailPayments.length > 0 && (
              <div>
                <label>Payments Recorded</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                  {detailPayments.map(p => (
                    <div key={p.id} className="invoice-payment-record">
                      <span className="invoice-payment-record-label">{methodName(p.payment_method_id)} · {new Date((p as any).effective_at || p.created_at).toLocaleDateString('en-SG')}
                        {(p as any).entry_kind === 'correction_reversal' ? ' · Reversal' : (p as any).entry_kind === 'correction_replacement' ? ' · Replacement' : ''}</span>
                      <span className="invoice-payment-record-actions">
                        <span style={{ fontWeight: 600 }}>{money(Number(p.amount) * ((p as any).entry_kind === 'correction_reversal' ? -1 : 1))}</span>
                        {/* Payment correction belongs with the payment it corrects.
                            It still opens the audited reversal-and-replacement
                            workflow, with its required reason and role check. */}
                        {canManageInvoice && (p as any).entry_kind !== 'correction_reversal'
                          && !detailPayments.some(r => (r as any).corrects_payment_id === p.id && (r as any).entry_kind === 'correction_reversal') && (
                          <button className="btn btn-secondary btn-sm"
                            onClick={() => setFinanceRequest({ mode: 'payment', paymentId: p.id })}
                            title="Correct this payment's amount or date, keeping the original receipt">
                            Correct amount / date</button>
                        )}
                      </span>
                    </div>
                  ))}
                </div>
                <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6 }}>
                  Correcting a payment records a reversal and a replacement. The original receipt stays in this history.
                </p>
              </div>
            )}

            {/* Therapy (spec 4.12) */}
            {detailTherapy?.used && (
              <div>
                <label>Unlimited Therapy</label>
                <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 12, marginTop: 4 }}>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 16px', fontSize: 12.5, marginBottom: 8 }}>
                    <span>Eligible amount: <strong>{money(detailTherapy.eligible_total)}</strong></span>
                    {Number(detailTherapy.topup_amount) > 0 && <span>Qualification top-up: <strong>{money(detailTherapy.topup_amount)}</strong></span>}
                    <span>Applied to packages: <strong>{money(detailTherapy.qualified_total)}</strong></span>
                    {/* DERIVED, not taken from the RPC.
                        forfeited_total is a SUM of a per-entitlement column,
                        but forfeiture belongs to the qualification as a whole —
                        so a group of 8 entitlements reported 8 x S$742 =
                        S$5,936 against an eligible total of S$7,094, which is
                        more than was ever eligible. Eligible less applied is the
                        definition and cannot be multiplied by a row count. */}
                    {(() => {
                      const derived = Math.max(
                        Math.round((Number(detailTherapy.eligible_total ?? 0)
                          - Number(detailTherapy.qualified_total ?? 0)) * 100) / 100, 0);
                      if (derived <= 0) return null;
                      return (
                        <span style={{ color: 'var(--danger)' }}>
                          Forfeited balance: <strong>{money(derived)}</strong>
                        </span>
                      );
                    })()}
                  </div>

                  {(detailTherapy.linked_invoices ?? []).length > 1 && (
                    <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 8 }}>
                      Combined invoices: {(detailTherapy.linked_invoices ?? []).map((li: any, i: number) => (
                        <span key={i}>{i > 0 && ', '}
                          <strong style={{ color: li.is_this_invoice ? 'var(--primary)' : undefined }}>{li.invoice_no}</strong> ({money(li.contributed_amount)})
                        </span>
                      ))}
                    </div>
                  )}

                  {(detailTherapy.entitlements ?? []).map((en: any, i: number) => (
                    <div key={i} style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10, marginBottom: 6 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 6 }}>
                        <div style={{ fontSize: 13 }}>
                          <strong>{en.package_name}</strong>
                          <span style={{ color: 'var(--text-muted)' }}> · {en.entitlement_kind === 'unlimited' ? `${en.duration_months} month(s) unlimited` : `${en.voucher_qty} voucher(s)`}</span>
                          <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                            {en.entitlement_no} · created {new Date(en.created_at).toLocaleDateString()} · activate by {new Date(en.activation_deadline).toLocaleDateString()}
                          </div>
                        </div>
                        <span className={`badge ${en.status === 'expired_before_activation' || en.status === 'cancelled' ? 'badge-danger' : en.status === 'activated' ? 'badge-success' : 'badge-muted'}`}>
                          {String(en.status).replace(/_/g, ' ')}
                        </span>
                      </div>
                      {(en.beneficiaries ?? []).length > 0 && (
                        <div style={{ marginTop: 6, borderTop: '1px solid var(--border)', paddingTop: 6 }}>
                          {(en.beneficiaries ?? []).map((b: any, j: number) => (
                            <div key={j} style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 6, fontSize: 12, marginBottom: 2 }}>
                              <span>
                                <strong>{b.name}</strong>
                                <span style={{ color: 'var(--text-muted)' }}> · {b.portion_months ? `${b.portion_months} mo` : `${b.portion_vouchers} vouchers`}</span>
                                {b.transferred_from && <span style={{ color: 'var(--text-muted)' }}> · transferred from {b.transferred_from}</span>}
                              </span>
                              <span style={{ color: 'var(--text-secondary)' }}>
                                {b.activation_date
                                  ? <>{new Date(b.activation_date).toLocaleDateString()}{b.ending_date ? ` → ${new Date(b.ending_date).toLocaleDateString()}` : ' · no expiry'}</>
                                  : 'not activated'}
                                {' '}<span className={`badge ${b.status === 'active' ? 'badge-success' : b.status === 'scheduled' ? 'badge-primary' : b.status === 'cancelled' || b.status === 'expired_before_activation' ? 'badge-danger' : 'badge-muted'}`} style={{ fontSize: 10 }}>{String(b.status).replace(/_/g, ' ')}</span>
                              </span>
                            </div>
                          ))}
                        </div>
                      )}
                      {(en.beneficiaries ?? []).length === 0 && (
                        <div style={{ marginTop: 6, fontSize: 11.5, color: 'var(--text-muted)' }}>No beneficiary assigned yet.</div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {detailTherapy && !detailTherapy.used && detailTherapy.eligible && legacyDiag && (
              <div className={`alert ${legacyDiag.qualifies ? 'alert-info' : 'alert-warning'}`} style={{ marginBottom: 0 }}>
                <span>💡</span>
                <div>
                  <div>No Legacy therapy from this invoice yet. {legacyDiag.reason}</div>
                  {legacyDiag.day_charged != null && (
                    <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>
                      Same-day paid total at this store: {money(Number(legacyDiag.day_charged))}
                      {legacyDiag.best_tier_amount ? ` · qualifying tier ${money(Number(legacyDiag.best_tier_amount))}` : ''}
                    </div>
                  )}
                </div>
              </div>
            )}
            {detailTherapy && !detailTherapy.used && detailTherapy.eligible && !legacyDiag && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}>
                <span>💡</span>
                <div>This invoice hasn't been used for therapy qualification yet.</div>
              </div>
            )}

            {/* Payment entry (only if not fully paid) */}
            {detail.status !== 'paid' && detail.status !== 'cancelled' && detail.status !== 'refunded' && (() => {
              // Wallet Credit can never pay for a Credit Package or Premium Bundle.
              // If the invoice contains ANY such line, wallet methods are hidden
              // for the WHOLE invoice — the database enforces the same rule, so
              // this only spares the user a rejected attempt.
              const hasCreditLine = detailItems.some(it => it.line_kind === 'credit_package' || it.line_kind === 'premium_bundle');
              return (
              <div>
                {payErr && <div className="alert alert-danger"><span>⚠</span><div>{payErr}</div></div>}
                <label>Record Payment <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— split across methods if needed</span></label>
                {hasCreditLine && (
                  <div className="alert alert-info" style={{ margin: '6px 0' }}>
                    <span>💳</span>
                    <div>Wallet Credit cannot be used to purchase a Credit Package or Premium Bundle.</div>
                  </div>
                )}
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }}>
                  {payLines.map((pl, i) => (
                    <React.Fragment key={i}>
                    <div className="invoice-payment-row" style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                      <InvoiceSearchSelect value={pl.payment_method_id} placeholder="Select payment method"
                        onChange={id => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, payment_method_id: id } : l))}
                        options={[
                          // An arrangement, offered beside the methods because
                          // that is where a person looks for it — but it is
                          // never sent as a payment method.
                          { value: INSTALMENT_METHOD, label: 'Instalment' },
                          ...methods.filter((m: any) => !m.is_wallet_credit || !hasCreditLine).map((m: any) => ({
                            value: m.id, label: m.name + (m.is_wallet_credit ? ` — ${money(Number(payWallet?.categories?.[m.wallet_category] ?? 0))} available` : ''),
                            disabled: m.is_wallet_credit && Number(payWallet?.categories?.[m.wallet_category] ?? 0) <= 0,
                          }))]} />
                      <input type="number" min={0} step={0.01} value={pl.amount || ''}
                        placeholder="Amount" style={{ width: 110 }}
                        onChange={e => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, amount: +e.target.value } : l))} />
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setPayLines(ls => ls.filter((_, j) => j !== i))} disabled={payLines.length === 1}><X size={13} /></button>
                    </div>
                    {pl.payment_method_id === INSTALMENT_METHOD && (
                      <InstalmentPortionFields
                        value={pl.instalment ?? emptyPortion}
                        onChange={v => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, instalment: v } : l))}
                        methods={methods}
                        receivedNow={pl.amount || 0}
                        onReceivedNow={n => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, amount: n } : l))}
                        error={payLineErrors[i] ?? null} />
                    )}
                    </React.Fragment>
                  ))}
                </div>
                <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setPayLines(ls => [...ls, { payment_method_id: '', amount: 0 }])}><Plus size={13} /> Split Payment</button>
                <div className="form-group" style={{ marginTop: 12, maxWidth: 220 }}>
                  <label>Date received</label>
                  <input type="date" value={payDate} max={singaporeToday()}
                    onChange={e => setPayDate(e.target.value)} />
                  <small>Sales are reported on this date. Defaults to today; set it back if the money arrived earlier.</small>
                </div>
                {/* The instalment checkbox that used to sit here imposed ONE
                    arrangement on the whole invoice, so a part-cash,
                    part-instalment settlement could not be recorded. Instalment
                    is now a choice on the payment line it belongs to. */}
                {payOutcome && <div role="status" className="alert alert-info" style={{ marginTop: 10 }}><span>ℹ️</span><div>{payOutcome}</div></div>}
                {payBlockedReason && payLines.some(p => p.amount > 0 || p.payment_method_id) &&
                  <p role="status" style={{ marginTop: 8, fontSize: 12, color: 'var(--text-muted)' }}>{payBlockedReason}</p>}
                {!hasCreditLine && payWallet && Number(payWallet.available_total ?? 0) > 0 && (
                  <div style={{ marginTop: 10, fontSize: 11.5, color: 'var(--text-muted)' }}>
                    Wallet: <strong>{money(Number(payWallet.available_total))}</strong> available —
                    {' '}{(['paid','bonus','legacy','promotional','exchange'] as const)
                      .filter(k => Number(payWallet.categories?.[k] ?? 0) > 0)
                      .map(k => `${k} ${money(Number(payWallet.categories[k]))}`).join(' · ')}
                    <div>Bonus Credit is always spent first, then the oldest eligible credit. Credit-funded value earns no commission.</div>
                  </div>
                )}

                <div style={{ marginTop: 12, padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', fontSize: 13 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Remaining balance</span><strong>{money(Number(detailFinancial?.outstanding ?? 0))}</strong></div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4 }}><span>This payment</span><strong>{money(payTotal)}</strong></div>
                  {payTotal >= Number(detailFinancial?.outstanding ?? 0) - 0.001 && payTotal > 0 && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8, color: 'var(--success)', fontWeight: 600 }}>
                      <CheckCircle2 size={15} /> This completes the invoice — stock will be deducted.
                    </div>
                  )}
                </div>
              </div>
              );
            })()}
          </div>
        </Modal>
      )}

      {/* Refund / cancel request modal */}
      {createdPending && (
        <div role="alert" className="alert alert-warning" style={{ margin: '12px 0' }}>
          <span>⚠</span>
          <div>
            {createdPending.message}
            <div style={{ marginTop: 8, display: 'flex', gap: 8 }}>
              <button className="btn btn-secondary btn-sm" onClick={async () => {
                const { data, error } = await supabase.from('invoices').select('*').eq('id', createdPending.id).single();
                if (error || !data) return;
                setCreatedPending(null);
                await openDetail(data as Invoice);
              }}>Open the invoice</button>
              <button className="btn btn-secondary btn-sm" onClick={() => setCreatedPending(null)}>Dismiss</button>
            </div>
          </div>
        </div>
      )}

      {detail && guidedOpen && (
        <InvoiceGuidedAction
          invoiceId={detail.id}
          canApprove={isOwnerOrManager(profile?.role)}
          onClose={() => setGuidedOpen(false)}
          onDone={async () => {
            // The open invoice first, so the figures behind the dialog are the
            // ones the action just produced; then the list behind it.
            const id = detail.id;
            noteLocalChangeRef.current([id]);
            // The list behind the dialog does not wait on the invoice re-read:
            // if that fails the dialog says so and offers its own retry, and
            // the list must still show what the action did.
            void refreshList({ afterSave: 'The action was recorded', changed: [id] });
            await refreshDetail(id);
          }} />
      )}

      {detail && (
        <InvoiceRefundCancelChooser
          open={chooserOpen}
          invoiceNo={detail.invoice_no} status={detail.status} netReceived={netReceived} refundedAmount={refundedAmount}
          onClose={() => setChooserOpen(false)}
          canRefund={hasRefundablePayment}
          canCancel={cancellable}
          refundBlockedReason="No refundable payment."
          cancelBlockedReason="This invoice is already cancelled or refunded. Reopening is a separate action in the settlement section."
          onChoose={choice => {
            // Opening the chooser mutated nothing; choosing hands over to the
            // existing workflow, which still asks for its own reason and preview.
            setChooserOpen(false);
            setFinanceRequest({ mode: choice });
          }} />
      )}

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

      {priceReview && detail && (
        <PaymentPriceReview review={priceReview} busy={payBusy}
          onClose={() => setPriceReview(null)}
          onConfirm={() => { setPriceReview(null); handlePay(); }} />
      )}
      {focLine && (
        <Modal title="Make line FOC" maxWidth={420} onClose={() => setFocLine(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setFocLine(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={handleApplyLineFoc} disabled={focBusy}>
              {focBusy ? 'Applying…' : 'Apply FOC'}
            </button>
          </>}>
          <div className="form-grid">
            {focErr && <div className="alert alert-danger" style={{ fontSize: 12.5 }}>{focErr}</div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              The full quantity still leaves inventory and any entitlement is still created — only the charge is waived.
            </div>
            <div>
              <label>Free quantity (of {focLine.quantity})</label>
              <select value={String(focQty)} onChange={e => setFocQty(+e.target.value)}>
                {Array.from({ length: Math.min(Math.max(0, Math.floor(focLine.quantity || 0)), 100) }, (_, k) => k + 1).map(q => (
                  <option key={q} value={q}>{q === focLine.quantity ? `All ${q} (full FOC)` : `${q} free`}</option>
                ))}
              </select>
            </div>
            <div>
              <label>Reason <span style={{ color: 'var(--danger)' }}>*</span></label>
              <select value={focReasonId} onChange={e => setFocReasonId(e.target.value)}>
                <option value="">— Select a reason —</option>
                {focReasons.map(r => <option key={r.id} value={r.id}>{r.label}{r.requires_note ? ' (note required)' : ''}</option>)}
              </select>
            </div>
            <div>
              <label>Note</label>
              <input value={focNote} onChange={e => setFocNote(e.target.value)} placeholder="Optional unless the reason requires it" />
            </div>
          </div>
        </Modal>
      )}

    </div>
  );
};

export default InvoicesPage;
