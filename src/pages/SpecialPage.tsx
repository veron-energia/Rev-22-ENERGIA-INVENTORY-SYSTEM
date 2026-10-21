import React, { useEffect, useState, useCallback, useRef } from 'react';
import { Link } from 'react-router-dom';
import { sendViaWhatsAppLink, sendViaEmailAttachment, whatsappNumber, emailAddress, openSendWindow,
  type EmailResult } from '../lib/sendDoc';
import { PdfDoc } from '../lib/invoicePdf';
import { printA5Document, esc as pesc, money as pmoney, PrintLine, PrintTotal } from '../lib/printDoc';
import { supabase, fetchCustomersByIds } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  SpecialProduct, SpecialProductStock, SpecialSale, Rental, Warehouse, Customer, PaymentMethod,
  RentalStatus, ReturnCondition, RATE_TYPE_LABELS, isOwnerOrManager,
} from '../types';
import { specialSaleBadge, rentalStatusLabel, rentalStillWithCustomer } from '../lib/special/waitingItems';
import {
  ReturnForm, initialReturnForm, withReturnedOn, lateDaysOn, lateNotice, lateFeeSum, lateFeeAmounts,
  stockHome, returnProblem, returnRpcArgs, needsStoreChoice, lateFeeStatus, overdueNote, receiptLateFee,
  shortDate, withCondition, isDay,
  type AwaitingRental, type ReceiveChoice, NOT_BACK_YET, receiveHomeLabel, receiveRpcArgs, receivedText,
} from '../lib/special/rentalReturn';
import { type TermsForm, type SoldLine, initialTerms, withTermsChange, termsProblem, termsChanged, termsRpcArgs,
  termsFee, SOLD_LINE_COLUMNS } from '../lib/special/rentalTerms';
import { docStore, docInvoiceIds, invoiceLine, waitingButton, toReceive } from '../lib/special/specialDocs';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, RefreshCw, Boxes, KeyRound, ShoppingBag, CalendarClock, Clock, Printer, MessageCircle, Mail } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';
import { SearchSelect } from '../components/SearchSelect';

const money = (n: number) => `S$${n.toFixed(2)}`;
// Local (Singapore) date — never via toISOString, which shifts to UTC.
const todayStr = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

const blank = (p?: SpecialProduct) => ({
  product_id: (p as any)?.product_id ?? '',
  name: p?.name ?? '', sku: p?.sku ?? '', description: p?.description ?? '',
  sale_price: p?.sale_price ?? 0, rate_day: p?.rate_day ?? 0, rate_week: p?.rate_week ?? 0,
  rate_month: p?.rate_month ?? 0, rate_year: p?.rate_year ?? 0,
  late_fee_per_day: p?.late_fee_per_day ?? 0, is_active: p?.is_active ?? true,
});

const SpecialPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isOwnerOrManager(profile?.role);
  const [tab, setTab] = useState<'catalog' | 'sales' | 'rentals'>('catalog');


  const [rows, setRows] = useState<SpecialProduct[]>([]);
  const [stock, setStock] = useState<SpecialProductStock[]>([]);
  // Store stock is held separately from warehouse stock: the two are counted
  // apart. Declared HERE, above load() and the helpers that read them, so the
  // ordering cannot become a temporal dead zone if this file is reshuffled.
  const [storeStock, setStoreStock] = useState<SpecialProductStock[]>([]);
  // Which total was clicked: the product and whether warehouses or stores.
  const [breakdown, setBreakdown] = useState<{ product: any; kind: 'warehouse' | 'store' } | null>(null);
  const [sales, setSales] = useState<SpecialSale[]>([]);
  const [rentals, setRentals] = useState<Rental[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  // The active stores, offered where staff choose one.
  const [brandStores, setBrandStores] = useState<any[]>([]);
  // Every store the person can read, closed ones too: a receipt carries the
  // letterhead of its own store, whatever has happened to that store since
  // (426, SALES-EXTRAS-16).
  const [allStores, setAllStores] = useState<any[]>([]);
  const [staffProfiles, setStaffProfiles] = useState<any[]>([]);
  // Every special product, deleted ones too: an old rental may be of one, and
  // whether it is a warehouse product decides where its Return puts it back.
  const [spAll, setSpAll] = useState<{ id: string; name: string; product_id: string | null }[]>([]);
  // The invoices the rows name, by id: the one that sold each sale or rental,
  // and a late fee invoiced at a Return (396).
  const [docInvoices, setDocInvoices] = useState<Record<string, { invoice_no: string; status: string }>>({});
  const [loading, setLoading] = useState(true);

  // Paid sales and rentals with no warehouse yet — Owner/Manager assigns one,
  // and only then does stock move. Refresh reloads it with everything else,
  // and a list that could not be read says so rather than "Nothing waiting"
  // (426, SALES-EXTRAS-8).
  const [awaiting, setAwaiting] = useState<any[]>([]);
  const [awaitingFailed, setAwaitingFailed] = useState(false);
  // Availability per waiting document: what each warehouse holds, and how much
  // of it is already claimed by pending transfer requests.
  const [avail, setAvail] = useState<Record<string, any[]>>({});
  const [availFailed, setAvailFailed] = useState(false);
  /** The waiting list, or null when it could not be read. */
  const loadAwaiting = useCallback(async (): Promise<any[] | null> => {
    const { data, error } = await supabase.rpc('special_docs_awaiting_fulfilment');
    if (error) {
      // An old list could release or change what is no longer waiting.
      setAwaiting([]); setAvail({}); setAwaitingFailed(true); setAvailFailed(false);
      return null;
    }
    const list = (data as any[]) ?? [];
    setAwaitingFailed(false);
    setAwaiting(list);
    const map: Record<string, any[]> = {};
    let missed = false;
    await Promise.all(list.map(async r => {
      const { data: a, error: e } = await supabase.rpc('special_product_availability',
        { p_special_product_id: r.special_product_id });
      if (e) missed = true;
      map[r.doc_id] = (a as any[]) ?? [];
    }));
    setAvail(map); setAvailFailed(missed);
    return list;
  }, []);

  /** Everything on the page, the waiting list included. Gives the waiting list back. */
  const load = useCallback(async (): Promise<any[] | null> => {
    setLoading(true);
    const waiting = loadAwaiting();
    const [sp, st, si, sa, re, wh, pm, sto, prof, spa, every] = await Promise.all([
      supabase.from('special_products').select('*').is('deleted_at', null).order('name'),
      supabase.from('warehouse_inventory').select('warehouse_id,product_id,current_qty'),
      supabase.from('store_inventory').select('store_id,product_id,current_qty'),
      supabase.from('special_sales').select('*').order('created_at', { ascending: false }),
      supabase.from('rentals').select('*').order('created_at', { ascending: false }),
      supabase.from('warehouses').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      // The customers table is deliberately absent. It was read whole here and
      // capped at a thousand rows, so a sale or rental belonging to anyone
      // further down the alphabet showed no name at all; and it never asked for
      // email, which is why every Send-by-email button on this page was
      // permanently disabled. Both are answered by the by-id lookup below.
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('profiles').select('id,full_name').is('deleted_at', null),
      supabase.from('special_products').select('id,name,product_id'),
      supabase.from('stores').select('*').order('name'),
    ]);
    const spRows = (sp.data as SpecialProduct[]) ?? [];
    setRows(spRows);
    // A special product IS a warehouse product (migration 108), so its stock is
    // the warehouse stock of the product it points at. Mapped here to the shape
    // the rest of this page already expects.
    const byProduct = new Map<string, string>(
      spRows.map((r: any) => [r.product_id, r.id]).filter(([pid]) => !!pid) as [string, string][]);
    setStock(((st.data as any[]) ?? [])
      .filter(w => byProduct.has(w.product_id))
      .map(w => ({
        id: `${w.warehouse_id}:${w.product_id}`,
        special_product_id: byProduct.get(w.product_id)!,
        warehouse_id: w.warehouse_id,
        current_qty: w.current_qty,
      })) as SpecialProductStock[]);
    setStoreStock(((si.data as any[]) ?? [])
      .filter(w => byProduct.has(w.product_id))
      .map(w => ({
        id: `${w.store_id}:${w.product_id}`,
        special_product_id: byProduct.get(w.product_id)!,
        warehouse_id: w.store_id,          // the location id; a store here
        current_qty: w.current_qty,
      })) as SpecialProductStock[]);
    setSales((sa.data as SpecialSale[]) ?? []);
    setRentals((re.data as Rental[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    // Exactly the customers these sales and rentals name, with the columns the
    // row actions need. Correct at any table size, and it reaches customers who
    // have since been deleted, whose historical sale still names them.
    setCustomers(await fetchCustomersByIds([
      ...((sa.data as any[]) ?? []).map(x => x.customer_id),
      ...((re.data as any[]) ?? []).map(x => x.customer_id),
    ]) as Customer[]);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    setBrandStores((sto.data as any[]) ?? []);
    setAllStores((every.data as any[]) ?? (sto.data as any[]) ?? []);
    setStaffProfiles((prof.data as any[]) ?? []);
    setSpAll((spa.data as any[]) ?? []);
    const invIds = docInvoiceIds([...((sa.data as any[]) ?? []), ...((re.data as any[]) ?? [])]);
    if (invIds.length > 0) {
      const { data: li } = await supabase.from('invoices').select('id,invoice_no,status').in('id', invIds);
      setDocInvoices(Object.fromEntries(((li as any[]) ?? []).map(x => [x.id, { invoice_no: x.invoice_no, status: x.status }])));
    } else setDocInvoices({});
    const left = await waiting;
    setLoading(false);
    return left;
  }, [loadAwaiting]);
  useEffect(() => { void load(); }, [load]);

  const spName = (id: string) => rows.find(r => r.id === id)?.name ?? spAll.find(r => r.id === id)?.name ?? '—';
  const whName = (id: string) => warehouses.find(w => w.id === id)?.name ?? '—';
  const cuName = (id: string | null) => id ? (customers.find(c => c.id === id)?.full_name ?? '—') : '—';
  const pmName = (id: string | null) => id ? (methods.find(m => m.id === id)?.name ?? '—') : '—';
  const storeStockOf = (spId: string, stId?: string) =>
    storeStock.filter(s2 => s2.special_product_id === spId && (!stId || s2.warehouse_id === stId));
  const totalIn = (list: SpecialProductStock[]) => list.reduce((a, b) => a + (b.current_qty || 0), 0);
  const stockOf = (spId: string, whId?: string) => stock.filter(s => s.special_product_id === spId && (!whId || s.warehouse_id === whId));
  const isOverdue = (r: Rental) => (r.status === 'paid' || r.status === 'active') && todayStr() > r.expected_return_date;
  const storeNameOf = (id: string | null | undefined) => id ? (allStores.find((s2: any) => s2.id === id)?.name ?? null) : null;
  // Where a rental went out from: the store it was released from, else its warehouse.
  const releasedFrom = (r: Rental) => r.source_store_id ? (storeNameOf(r.source_store_id) ?? '—') : whName(r.warehouse_id);
  const lateInvoiceNo = (r: Rental) => r.late_fee_invoice_id ? (docInvoices[r.late_fee_invoice_id]?.invoice_no ?? null) : null;
  /** The invoice that sold a sale or rental, as its receipt names it. */
  const soldOnInvoiceNo = (row: any) => row?.invoice_id ? (docInvoices[row.invoice_id]?.invoice_no ?? null) : null;
  /** The store whose letterhead, PayNow details and send log a receipt uses. */
  const receiptStore = (row: any): any => docStore(row, allStores, brandStores[0] ?? null) ?? {};

  // Special sales and rentals are their own transactions with their own numbers,
  // so they get a printable receipt rather than being forced through an invoice.
  // The customer copy as a real A5 PDF, matching the printed receipt.
  const [sendBusy, setSendBusy] = useState<string | null>(null);
  const [fulfilWh, setFulfilWh] = useState<Record<string, string>>({});
  const [fulfilBusy, setFulfilBusy] = useState<string | null>(null);
  const [queueOpen, setQueueOpen] = useState(false);

  // ── Change rental terms (426, SALES-EXTRAS-7) ──
  // Only a rental still waiting (the database refuses any other). Its errors
  // show in its own window; "Due back" follows the start, the rate and the
  // periods (lib/special/rentalTerms), and staff may still type another date.
  // The new fee is shown as the database will work it out: the list rate less
  // the same discount as the invoice line sold it (the owner, 18 Oct 2026).
  const [editRental, setEditRental] = useState<any | null>(null);
  const [rentForm, setRentForm] = useState<TermsForm>(initialTerms({}));
  const [rentOpened, setRentOpened] = useState<TermsForm>(initialTerms({}));
  const [rentBusy, setRentBusy] = useState(false);
  const [rentErr, setRentErr] = useState<string | null>(null);
  const [rentNote, setRentNote] = useState<string | null>(null);
  // The invoice line that sold it: null when it has none, undefined while it
  // is read or when it could not be read (the fee is then said once saved).
  const [rentLine, setRentLine] = useState<SoldLine | null | undefined>(undefined);
  const rentLineFor = useRef<string | null>(null);
  const openRentalEdit = (row: any) => {
    const f = initialTerms(row);
    setEditRental(row); setRentForm(f); setRentOpened(f);
    setRentErr(null); setRentNote(null); setRentLine(undefined);
    rentLineFor.current = row.doc_id;
    const rental: any = rentals.find(r => r.id === row.doc_id);
    if (!rental) return;
    const itemId: string | null = rental.invoice_item_id ?? null;
    if (!itemId) { setRentLine(null); return; }
    void supabase.from('invoice_items').select(SOLD_LINE_COLUMNS).eq('id', itemId).then(({ data, error }: any) => {
      if (rentLineFor.current !== row.doc_id) return;   // another rental's window by now
      const line = error ? undefined : ((data as any[]) ?? []).find(x => x.id === itemId);
      setRentLine(line ?? undefined);
    });
  };
  const rentFee = editRental && rentLine !== undefined
    ? termsFee(editRental, rentLine, rows.find((p: any) => p.id === editRental.special_product_id) ?? null, rentForm)
    : null;
  const changeTerms = (patch: Partial<TermsForm>) => setRentForm(f => withTermsChange(f, patch));
  const rentProblem = termsProblem(rentForm);
  const saveRental = async () => {
    if (!editRental) return;
    if (rentProblem) { setRentErr(rentProblem); return; }
    setRentBusy(true); setRentErr(null);
    const { data, error } = await supabase.rpc('update_pending_rental', termsRpcArgs(editRental.doc_id, rentForm));
    setRentBusy(false);
    if (error) { setRentErr(error.message); return; }
    const diff = Number((data as any)?.difference ?? 0);
    setEditRental(null);
    // The Rentals tab and the waiting list both show the new terms.
    await load();
    if (diff !== 0) {
      // The invoice was settled at the old fee, so say so rather than letting
      // the discrepancy surface later.
      const kept = (data as any)?.discount_kept ? ` (${(data as any).discount_kept})` : '';
      setRentNote(`The rental fee is now ${money(Number((data as any).rental_fee))}${kept} — `
        + `${money(Math.abs(diff))} ${diff > 0 ? 'more' : 'less'} than the `
        + `${money(Number((data as any).invoiced_fee))} already invoiced. `
        + `Collect or refund the difference on the invoice.`);
    }
  };

  const doFulfil = async (row: any) => {
    const wh = fulfilWh[row.doc_id];
    if (!wh) { setErr('Choose a warehouse first.'); return; }
    setFulfilBusy(row.doc_id); setErr(null);
    // The dropdown value is "type:id", since a warehouse and a store could
    // otherwise be indistinguishable by id alone.
    const [locType, locId] = String(wh).includes(':') ? String(wh).split(':') : ['warehouse', String(wh)];
    const { error } = await supabase.rpc('fulfil_special_doc', {
      p_doc_kind: row.doc_kind, p_doc_id: row.doc_id, p_warehouse_id: locId,
      p_location_type: locType,
    });
    setFulfilBusy(null);
    if (error) { setErr(error.message); return; }
    // Clear the choice so a stale warehouse cannot linger against a doc id.
    setFulfilWh(w => { const n = { ...w }; delete n[row.doc_id]; return n; });
    const left = await load();
    // Nothing left to release: close rather than leaving an empty dialog open.
    if (left && left.length === 0) setQueueOpen(false);
  };
  const buildReceiptPdf = (kind: 'sale' | 'rental', row: any): PdfDoc => {
    const prod = rows.find((p: any) => p.id === row.special_product_id);
    const cust = customers.find((c: any) => c.id === row.customer_id);
    const wh = warehouses.find((w: any) => w.id === row.warehouse_id);
    // The row's own store (426): the invoice's, else the one it was released from.
    const b: any = receiptStore(row);
    const fee = Number(kind === 'sale' ? row.total_amount : row.rental_fee) || 0;
    // A late fee invoiced at the Return (396) is on its own invoice: named
    // here, not added again.
    const lateFee = receiptLateFee(row, kind === 'rental' ? lateInvoiceNo(row) : null);
    const late = lateFee.inTotal;
    const d = (v: any) => v ? new Date(v).toLocaleDateString('en-GB') : '';
    return {
      kindLabel: kind === 'sale' ? 'Special Product Sale' : 'Special Product Rental',
      docNo: row.sale_no ?? row.rental_no,
      date: d(row.created_at),
      status: String(row.status ?? '').replace(/_/g, ' '),
      // The invoice that sold it (426).
      headerNote: invoiceLine(soldOnInvoiceNo(row)),
      storeName: b.name ?? null, storeAddress: b.address ?? null,
      storePhone: [b.phone, b.whatsapp_phone ? `WhatsApp ${b.whatsapp_phone}` : '']
        .filter(Boolean).join(' · ') || null,
      customerName: cust?.full_name ?? '—',
      customerContact: [cust?.phone, cust?.email].filter(Boolean).join(' · ') || null,
      lines: [
        {
          name: prod?.name ?? 'Special product', qty: row.quantity,
          unit: Number(kind === 'sale' ? row.unit_price : row.rate_amount) || 0, total: fee,
          notes: [
            ...(prod?.sku ? [`SKU ${prod.sku}`] : []),
            ...(wh?.name ? [`From ${wh.name}`] : []),
            ...(kind === 'rental'
              ? [`${row.periods} x ${row.rate_type}`,
                 `From ${d(row.start_date)} — due back ${d(row.expected_return_date)}`,
                 ...(row.returned_at ? [`Returned ${d(row.returned_at)}`] : []),
                 ...(lateFee.note ? [lateFee.note] : [])]
              : []),
          ],
        },
        ...(late > 0 ? [{
          name: `Late fee — ${row.late_days} day(s)`, qty: row.late_days,
          unit: Number(row.late_fee_per_day ?? 0), total: late,
        }] : []),
      ],
      totals: [
        [kind === 'sale' ? 'Subtotal' : 'Rental fee', `S$${fee.toFixed(2)}`],
        ...(late > 0 ? [['Late fee', `S$${late.toFixed(2)}`] as [string, string]] : []),
      ],
      grandTotal: ['Total', `S$${(fee + late).toFixed(2)}`],
      payments: [
        ...(row.payment_method_id
          ? [[methods.find(m => m.id === row.payment_method_id)?.name ?? 'Payment', `S$${fee.toFixed(2)}`] as [string, string]] : []),
        ...(late > 0 && row.late_payment_method_id
          ? [[`${methods.find(m => m.id === row.late_payment_method_id)?.name ?? 'Payment'} (late fee)`, `S$${late.toFixed(2)}`] as [string, string]] : []),
      ],
      payDetails: [
        b.paynow_uen ? `CIMB UEN: ${b.paynow_uen}` : '',
        b.bank_account ? `CIMB corporate account: ${b.bank_account}` : '',
      ].filter(Boolean),
      staffName: staffProfiles.find((u: any) => u.id === (row.sold_by ?? row.created_by))?.full_name
        ?? profile?.full_name ?? '',
      policyText: b.policy_text ?? null,
      termsText: kind === 'rental'
        ? 'Rented goods remain the property of Rev 22 Pte Ltd. Late returns incur the daily late fee shown above.'
        : undefined,
      footerBits: [
        b.phone ? `DID: ${b.phone}` : '', b.email ? `Email: ${b.email}` : '',
        b.website ? `Website: ${b.website}` : '', b.co_reg_no ? `Co. Reg No.: ${b.co_reg_no}` : '',
      ].filter(Boolean),
    };
  };

  // ── Sending a receipt (B16's sendDoc, INVOICES-AFTER-11 and -M3) ──
  // WhatsApp's window is opened in the click, before anything is awaited, or
  // a phone's pop-up blocker stops it once the PDF is ready; only a window
  // really obtained counts as sent. Email goes from this device's own mail app
  // (the owner, 9 Oct 2026, Q6): the page says where the PDF or its link went,
  // never that it was attached or that the customer got it.
  const sendingRef = useRef(false);
  const [sendNote, setSendNote] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);
  const [emailRetry, setEmailRetry] = useState<{ shareAgain?: EmailResult['shareAgain']; mailto?: string } | null>(null);
  const emailDone = (r: EmailResult) => {
    if (r.shareAgain) {
      setEmailRetry({ shareAgain: r.shareAgain });
      setSendNote({ tone: 'ok', text: 'The PDF is ready. Press "Share the PDF" to choose your mail app.' });
      return;
    }
    if (!r.ok) { setSendNote({ tone: 'error', text: r.reason ?? 'Not sent.' }); return; }
    if (r.mailto) setEmailRetry({ mailto: r.mailto });
    setSendNote({ tone: 'ok', text: r.reason ?? 'Your mail app should open; send the email from there.' });
  };
  /** The share sheet again, from a tap of its own. */
  const shareEmailAgain = async () => {
    const again = emailRetry?.shareAgain;
    if (!again) return;
    setEmailRetry(null); setSendNote(null);
    const r = await again();
    if (r.shareAgain) {
      setEmailRetry({ shareAgain: r.shareAgain });
      setSendNote({ tone: 'error', text: r.reason ?? 'The share sheet did not open.' });
      return;
    }
    emailDone(r);
  };
  const sendReceiptPdf = async (channel: 'whatsapp' | 'email', kind: 'sale' | 'rental', row: any) => {
    if (sendingRef.current) return;
    // AFTER-11: the window opens now, in the click itself.
    const win = channel === 'whatsapp' ? openSendWindow() : undefined;
    sendingRef.current = true;
    setSendBusy(`${channel}-${row.id}`); setSendNote(null); setEmailRetry(null);
    let handedOver = false;
    try {
      const cust = customers.find((c: any) => c.id === row.customer_id);
      const docNo = row.sale_no ?? row.rental_no;
      const args = {
        pdf: buildReceiptPdf(kind, row),
        kindLabel: kind === 'sale' ? 'Sale' : 'Rental',
        docNo, docId: row.id,
        docKind: (kind === 'sale' ? 'special_sale' : 'rental') as 'special_sale' | 'rental',
        // The row's own store files the PDF and the send log (426).
        storeId: receiptStore(row).id ?? null,
        customerId: row.customer_id, customerName: cust?.full_name,
        phone: cust?.phone, email: cust?.email,
      };
      handedOver = true;
      if (channel === 'whatsapp') {
        const r = await sendViaWhatsAppLink(args, { win: win ?? null });
        if (!r.ok) { setSendNote({ tone: 'error', text: r.reason ?? 'Could not send.' }); return; }
        setSendNote({ tone: 'ok', text: `WhatsApp should now be open with the link to ${docNo}; send the message there.` });
        return;
      }
      // Nothing is awaited before this: on a phone the share sheet must open
      // while the tap still counts.
      emailDone(await sendViaEmailAttachment(args));
    } catch (e: any) {
      console.error('The receipt could not be sent', e);
      setSendNote({ tone: 'error', text: `Could not send${e?.message ? ` (${e.message})` : ''}.` });
    } finally {
      // A window opened for a send that never reached WhatsApp is closed.
      if (win && !handedOver) { try { if (!win.closed) win.close(); } catch { /* gone already */ } }
      sendingRef.current = false;
      setSendBusy(null);
    }
  };

  const printReceipt = (kind: 'sale' | 'rental', row: any) => {
    const prod = rows.find((p: any) => p.id === row.special_product_id);
    const cust = customers.find((c: any) => c.id === row.customer_id);
    const wh = warehouses.find((w: any) => w.id === row.warehouse_id);
    const methodName = (id: any) => methods.find(m => m.id === id)?.name ?? '';
    const d = (v: any) => v ? new Date(v).toLocaleDateString('en-GB') : '—';
    // The row's own store (426): the invoice's, else the one it was released from.
    const b: any = receiptStore(row);
    const soldOn = invoiceLine(soldOnInvoiceNo(row));

    const fee = Number(kind === 'sale' ? row.total_amount : row.rental_fee) || 0;
    // A late fee invoiced at the Return (396) is on its own invoice: named
    // here, not added again.
    const lateFee = receiptLateFee(row, kind === 'rental' ? lateInvoiceNo(row) : null);
    const late = lateFee.inTotal;

    const lines: PrintLine[] = kind === 'sale'
      ? [{ name: prod?.name ?? 'Special product', qty: row.quantity,
           unit: Number(row.unit_price ?? 0), total: fee,
           subLines: prod?.sku ? [`SKU ${prod.sku}`] : [] }]
      : [{ name: prod?.name ?? 'Special product', qty: row.quantity,
           unit: Number(row.rate_amount ?? 0), total: fee,
           subLines: [
             ...(prod?.sku ? [`SKU ${prod.sku}`] : []),
             `${row.periods} × ${row.rate_type}`,
             `From ${d(row.start_date)} — due back ${d(row.expected_return_date)}`,
             ...(row.returned_at ? [`Returned ${d(row.returned_at)}${row.return_condition ? ` · ${row.return_condition}` : ''}`] : []),
             ...(lateFee.note ? [lateFee.note] : []),
           ] },
         ...(late > 0 ? [{
           name: `Late fee — ${row.late_days} day(s)`,
           qty: row.late_days, unit: Number(row.late_fee_per_day ?? 0), total: late,
         }] : [])];

    const totals: PrintTotal[] = [
      { label: kind === 'sale' ? 'Subtotal' : 'Rental fee', value: pmoney(fee) },
      ...(late > 0 ? [{ label: 'Late fee', value: pmoney(late) }] : []),
      ...(Number(row.foc_amount ?? 0) > 0 ? [{ label: 'FOC', value: `−${pmoney(row.foc_amount)}` }] : []),
      { label: 'Total', value: pmoney(fee + late - Number(row.foc_amount ?? 0)), grand: true },
    ];

    const payments: [string, string][] = [];
    if (row.payment_method_id) payments.push([methodName(row.payment_method_id), pmoney(fee)]);
    if (late > 0 && row.late_payment_method_id) payments.push([`${methodName(row.late_payment_method_id)} (late fee)`, pmoney(late)]);

    // Printed staff signature: whoever recorded the sale or rental, else the
    // person printing it.
    const signedByName =
      staffProfiles.find((u: any) => u.id === (row.sold_by ?? row.created_by))?.full_name
      ?? profile?.full_name ?? '';
    printA5Document({
      signedByName,
      policyText: b.policy_text ?? null,
      docNo: row.sale_no ?? row.rental_no,
      docTitle: kind === 'sale' ? 'Special Product Sale' : 'Special Product Rental',
      branding: b,
      headerLines: [
        `Date: ${d(row.created_at)}`,
        `Status: ${pesc(String(row.status ?? '').replace(/_/g, ' '))}`,
        ...(soldOn ? [pesc(soldOn)] : []),
        ...(wh?.name ? [`Warehouse: ${pesc(wh.name)}`] : []),
      ],
      billToName: cust?.full_name ?? '—',
      billToLines: [cust?.phone ?? ''].filter(Boolean) as string[],
      itemHeading: kind === 'sale' ? 'Item' : 'Rented Item',
      lines, totals, payments,
      extraBlocks: row.notes ? [`<h2>Notes</h2><div class="mut">${pesc(row.notes)}</div>`] : [],
      termsText: kind === 'rental'
        ? 'Rented goods remain the property of Rev 22 Pte Ltd. Late returns incur the daily late fee shown above. Goods have been checked on collection.'
        : undefined,
    });
  };

  // ── Catalog modal ──
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  const [availableProducts, setAvailableProducts] = useState<any[]>([]);
  const loadAvailableProducts = () => supabase.rpc('products_available_as_special')
    .then(({ data }) => setAvailableProducts((data as any[]) ?? []));
  useEffect(() => { void loadAvailableProducts(); }, []);
  const [err, setErr] = useState<string | null>(null);

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (p: SpecialProduct) => { setForm(blank(p)); setEditId(p.id); setErr(null); setModalOpen(true); };
  const handleSave = async () => {
    if (!editId && !form.product_id) { setErr('Choose the warehouse product this is.'); return; }
    if (!form.sale_price && !form.rate_day && !form.rate_week && !form.rate_month && !form.rate_year) {
      setErr('Set a sale price or at least one rental rate, or this cannot be sold or rented.');
      return;
    }
    setSaving(true); setErr(null);
    // Through the RPC: it derives the name and SKU from the product and applies
    // the same rules the database enforces.
    const { error } = await supabase.rpc('upsert_special_product_from_product', {
      p_id: editId, p_product_id: form.product_id || null,
      p_sale_price: form.sale_price || 0,
      p_rate_day: form.rate_day || 0, p_rate_week: form.rate_week || 0,
      p_rate_month: form.rate_month || 0, p_rate_year: form.rate_year || 0,
      p_late_fee_per_day: form.late_fee_per_day || 0,
      // Emptied, it is sent as '' and the description is cleared (426); null
      // would keep the old one.
      p_description: (form.description ?? '').trim(), p_is_active: form.is_active,
    });
    setSaving(false);
    if (error) { setErr(error.message); return; }
    setModalOpen(false); loadAvailableProducts(); load();
  };
  const handleDelete = async (p: SpecialProduct) => {
    if (!confirm(`Delete special product "${p.name}"?`)) return;
    await supabase.from('special_products').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', p.id);
    load();
  };

  // ── Stock modal ──
  const [stockFor, setStockFor] = useState<SpecialProduct | null>(null);
  const [stockWh, setStockWh] = useState('');
  const [stockQtyIn, setStockQtyIn] = useState(0);
  const [stockBusy, setStockBusy] = useState(false);
  const addStock = async () => {
    if (!stockFor || !stockWh || stockQtyIn <= 0) return;
    setStockBusy(true);
    const { error } = await supabase.rpc('special_stock_in', { p_special_product_id: stockFor.id, p_warehouse_id: stockWh, p_quantity: stockQtyIn, p_note: null });
    setStockBusy(false);
    if (error) { alert(error.message); return; }
    setStockFor(null); load();
  };

  // The old New Sale and New Rental windows, Pay (with wallet credit),
  // Activate and the Cancel buttons of draft or paid documents are gone (426,
  // SALES-EXTRAS-12): sales and rentals are raised on the Invoices page, no
  // screen opened those windows, and their server functions are now the
  // service role's alone. Old rows still print and send.

  // ── Receive returned item (417; the owner, 10 Oct 2026) ──
  // A rental cancelled while the item was still with the customer stays on
  // the Rentals tab until an Owner or Manager records it as back, damaged or
  // lost. Nothing is chosen for them; a good item goes back where it came
  // from unless they pick another active warehouse; damaged and lost items
  // never go back on sale. The database checks each again.
  const [recvFor, setRecvFor] = useState<AwaitingRental | null>(null);
  const [recvChoice, setRecvChoice] = useState<ReceiveChoice>(NOT_BACK_YET);
  const [recvNote, setRecvNote] = useState('');
  const [recvBusy, setRecvBusy] = useState(false);
  const [recvErr, setRecvErr] = useState<string | null>(null);
  const [recvDone, setRecvDone] = useState<string | null>(null);
  const recvRequest = useRef<string | null>(null);
  const openReceive = (r: Rental) => {
    setRecvFor(toReceive(r, {
      item: spName(r.special_product_id),
      store: storeNameOf(r.source_store_id),
      warehouse: warehouses.find(w => w.id === r.warehouse_id)?.name ?? null,
    }));
    setRecvChoice(NOT_BACK_YET); setRecvNote(''); setRecvErr(null); setRecvDone(null);
    recvRequest.current = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function' ? crypto.randomUUID() : null;
  };
  // What was recorded stays said on the Rentals tab once the window closes.
  const closeReceive = () => { setRecvFor(null); setRecvErr(null); };
  const submitReceive = async () => {
    if (!recvFor) return;
    if (!recvChoice.outcome) { setRecvErr('Choose what happened to the item.'); return; }
    if (!recvNote.trim()) { setRecvErr('Write a short note for the history.'); return; }
    setRecvBusy(true); setRecvErr(null);
    const { data, error } = await supabase.rpc('receive_returned_rental',
      receiveRpcArgs(recvFor, recvChoice, recvNote, recvRequest.current));
    setRecvBusy(false);
    if (error) { setRecvErr(error.message); return; }
    setRecvDone(receivedText(recvFor, recvChoice.outcome, data));
    await load();
  };

  // ── Return rental modal (396, the Owner's rules of 6 Oct 2026) ──
  // When it came back, its condition, whether it goes back into stock where it
  // came from, and for a late return "No late fee" (the default) or "Charge
  // late fee", invoiced on an invoice of its own and paid there and then. The
  // rules live in lib/special/rentalReturn; the database checks them again.
  const [retFor, setRetFor] = useState<Rental | null>(null);
  const [retForm, setRetForm] = useState<ReturnForm | null>(null);
  const [retBusy, setRetBusy] = useState(false); const [retErr, setRetErr] = useState<string | null>(null);
  // What the Return recorded, shown in the dialog with the late fee's invoice.
  const [retDone, setRetDone] = useState<any | null>(null);
  const openReturn = (r: Rental) => {
    setRetFor(r); setRetForm(initialReturnForm(r, todayStr())); setRetErr(null); setRetDone(null);
  };
  const closeReturn = () => { setRetFor(null); setRetForm(null); setRetDone(null); setRetErr(null); };
  const setRet = (patch: Partial<ReturnForm>) => setRetForm(f => (f ? { ...f, ...patch } : f));
  // Paid there and then, by a method that is not wallet credit; none chosen for staff.
  const lateFeeMethods = methods.filter(m => !m.is_wallet_credit);
  const retHome = retFor ? stockHome(retFor, {
    warehouses: warehouses.map(w => ({ id: w.id, name: w.name })),
    stores: brandStores.map((s2: any) => ({ id: s2.id, name: s2.name })),
    isWarehouseProduct: !!spAll.find(x => x.id === retFor.special_product_id)?.product_id,
  }) : null;
  const retProblem = retFor && retForm ? returnProblem(retForm, retFor, {
    today: todayStr(), walletMethodIds: methods.filter(m => m.is_wallet_credit).map(m => m.id),
  }) : null;
  const submitReturn = async () => {
    if (!retFor || !retForm) return;
    if (retProblem) { setRetErr(retProblem); return; }
    setRetBusy(true); setRetErr(null);
    const { data, error } = await supabase.rpc('return_rental_with_fee', returnRpcArgs(retFor.id,
      { ...retForm, returnStock: retForm.returnStock && !!retHome?.canRestock }, retFor));
    setRetBusy(false);
    if (error) { setRetErr(error.message); return; }
    setRetDone(data ?? {});
    load();
  };

  const RentalBadge: React.FC<{ r: Rental }> = ({ r }) => {
    const s: RentalStatus = isOverdue(r) ? 'overdue' : r.status;
    const out = rentalStillWithCustomer(r);
    const cls = s === 'returned' ? 'badge-success' : s === 'paid' || s === 'awaiting_fulfilment' ? 'badge-primary'
      : s === 'active' ? 'badge-accent' : s === 'overdue' || out ? 'badge-danger' : 'badge-muted';
    // A cancelled rental says why: refunded, its invoice cancelled, its line
    // removed (393), or that the item is still with the customer (417).
    return <span className={`badge ${cls}`}>{rentalStatusLabel(s, r.notes, r)}</span>;
  };


  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage special products and rentals." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Special Products & Rentals</h2><p>Warehouse-only special products — sold directly or rented (fee upfront, late fee at return). No commission applies.</p></div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <ExcelExportButton
            rows={tab === 'sales' ? sales : tab === 'rentals' ? rentals : rows}
            filename={`special-${tab}`} sheetName="Special"
            dateOf={tab === 'catalog' ? undefined : ((r: any) => r.created_at)}
            dateLabel={tab === 'rentals' ? 'Rental date' : 'Sale date'}
            columns={tab === 'sales' ? [
              { header: 'Sale No', value: (x: any) => x.sale_no },
              { header: 'Invoice', value: (x: any) => soldOnInvoiceNo(x) ?? '' },
              { header: 'Date', value: (x: any) => new Date(x.created_at).toLocaleDateString('en-GB') },
              { header: 'Product', value: (x: any) => rows.find(p => p.id === x.special_product_id)?.name ?? '' },
              { header: 'Customer', value: (x: any) => customers.find(c => c.id === x.customer_id)?.full_name ?? '' },
              { header: 'Qty', value: (x: any) => Number(x.quantity ?? 0) },
              { header: 'Total', value: (x: any) => Number(x.total_amount ?? 0) },
              { header: 'Status', value: (x: any) => x.status },
            ] : tab === 'rentals' ? [
              { header: 'Rental No', value: (x: any) => x.rental_no },
              { header: 'Invoice', value: (x: any) => soldOnInvoiceNo(x) ?? '' },
              { header: 'Date', value: (x: any) => new Date(x.created_at).toLocaleDateString('en-GB') },
              { header: 'Product', value: (x: any) => rows.find(p => p.id === x.special_product_id)?.name ?? '' },
              { header: 'Customer', value: (x: any) => customers.find(c => c.id === x.customer_id)?.full_name ?? '' },
              { header: 'Period', value: (x: any) => `${x.periods} x ${x.rate_type}` },
              { header: 'Fee', value: (x: any) => Number(x.rental_fee ?? 0) },
              { header: 'Late fee', value: (x: any) => Number(x.late_fee_total ?? 0) },
              { header: 'Late fee invoice', value: (x: any) => x.late_fee_invoice_id ? (docInvoices[x.late_fee_invoice_id]?.invoice_no ?? '') : '' },
              { header: 'Due back', value: (x: any) => x.expected_return_date ? new Date(x.expected_return_date).toLocaleDateString('en-GB') : '' },
              { header: 'Status', value: (x: any) => x.status },
            ] : [
              { header: 'Product', value: (p: any) => p.name },
              { header: 'SKU', value: (p: any) => p.sku ?? '' },
              { header: 'Sale price', value: (p: any) => Number(p.sale_price ?? 0) },
              { header: 'Day rate', value: (p: any) => Number(p.rate_day ?? 0) },
              { header: 'Late fee/day', value: (p: any) => Number(p.late_fee_per_day ?? 0) },
            ]} /><button className="btn btn-secondary" onClick={() => { void load(); }}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button></div>
      </div>

      {/* The tabs, the waiting list and the action wrap onto more rows on a
          phone rather than running off the screen (426, SALES-EXTRAS-15). */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 16, flexWrap: 'wrap', alignItems: 'center' }}>
        <button className={`btn btn-sm ${tab === 'catalog' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('catalog')}><KeyRound size={14} /> Catalog</button>
        <button className={`btn btn-sm ${tab === 'sales' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('sales')}><ShoppingBag size={14} /> Sales</button>
        <button className={`btn btn-sm ${tab === 'rentals' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('rentals')}><CalendarClock size={14} /> Rentals</button>
      {/* ---- Waiting for a warehouse: a button, with the detail in a dialog ---- */}
      {/* Always shown, so its colour carries the state: white when there is
          nothing to do, amber when something is waiting, red when the list
          could not be read (426: never "Nothing waiting" then). */}
      {(() => {
        const wb = waitingButton(awaiting.length, awaitingFailed);
        return (
      <button className="btn" style={{
          background: wb.tone === 'waiting' ? 'var(--warning-light)' : wb.tone === 'failed' ? 'var(--danger-light)' : 'var(--surface)',
          borderColor: wb.tone === 'waiting' ? '#fde68a' : wb.tone === 'failed' ? '#fecaca' : 'var(--border)',
          color: wb.tone === 'waiting' ? '#92400e' : wb.tone === 'failed' ? '#991b1b' : 'var(--text-muted)',
          fontWeight: wb.tone === 'none' ? 500 : 700,
          cursor: wb.tone === 'waiting' ? 'pointer' : 'default',
        }}
        disabled={wb.tone !== 'waiting'}
        aria-live="polite"
        onClick={() => awaiting.length > 0 && setQueueOpen(true)}>
        <Clock size={14} />
        {wb.label}
        {wb.tone === 'waiting' && (
          <span style={{
            marginLeft: 8, padding: '1px 8px', borderRadius: 999, fontSize: 11.5,
            fontWeight: 700, background: 'var(--warning)', color: '#fff',
          }}>{awaiting.length}</span>
        )}
      </button>);
      })()}

        <div style={{ flex: 1 }} />
        {tab === 'catalog' && <button className="btn btn-primary btn-sm" onClick={openAdd}><Plus size={14} /> Add Special Product</button>}
        {(tab === 'sales' || tab === 'rentals') && (
          <span style={{ fontSize: 12.5, color: 'var(--text-muted)', flex: '1 1 240px' }}>
            Sales and rentals are now raised on the <strong>Invoices</strong> page, so the customer
            gets one invoice and one receipt. They appear here once paid, waiting for a warehouse.
          </span>
        )}
      </div>

      {/* What a WhatsApp or email send did, said once it is done (426). */}
      {(tab === 'sales' || tab === 'rentals') && sendNote && (
        <div className={`alert ${sendNote.tone === 'error' ? 'alert-danger' : 'alert-info'}`} role="status">
          <span>{sendNote.tone === 'error' ? '⚠' : 'ℹ'}</span>
          <div>
            {sendNote.text}
            {emailRetry?.shareAgain && (
              <div style={{ marginTop: 6 }}><button className="btn btn-secondary btn-sm" onClick={shareEmailAgain}>Share the PDF</button></div>)}
            {emailRetry?.mailto && (
              <div style={{ marginTop: 6 }}><a href={emailRetry.mailto}>Open the email again</a></div>)}
          </div>
        </div>
      )}
      {tab === 'rentals' && recvDone && !recvFor && (
        <div className="alert alert-success" role="status"><span>✓</span><div>{recvDone}</div></div>
      )}

      <div className="card"><div className="table-wrap">
        {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
        : tab === 'catalog' ? (
          rows.length === 0 ? <div className="empty-state"><KeyRound size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No special products yet</p></div>
          : <table>
              <thead><tr><th>Name</th><th>SKU</th><th style={{ textAlign: 'right' }}>Sale</th><th style={{ textAlign: 'right' }}>Day</th><th style={{ textAlign: 'right' }}>Week</th><th style={{ textAlign: 'right' }}>Month</th><th style={{ textAlign: 'right' }}>Year</th><th style={{ textAlign: 'right' }}>Late/day</th><th style={{ textAlign: 'right' }} title="Total held across all warehouses">In warehouses</th><th style={{ textAlign: 'right' }} title="Total held across all stores">In stores</th><th></th></tr></thead>
              <tbody>{rows.map(p => (
                <tr key={p.id}>
                  <td><strong>{p.name}</strong>{!p.is_active && <span className="badge badge-muted" style={{ marginLeft: 6 }}>Inactive</span>}</td>
                  <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{p.sku}</td>
                  <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(p.sale_price)}</td>
                  <td style={{ textAlign: 'right', fontSize: 12.5 }}>{money(p.rate_day)}</td>
                  <td style={{ textAlign: 'right', fontSize: 12.5 }}>{money(p.rate_week)}</td>
                  <td style={{ textAlign: 'right', fontSize: 12.5 }}>{money(p.rate_month)}</td>
                  <td style={{ textAlign: 'right', fontSize: 12.5 }}>{money(p.rate_year)}</td>
                  <td style={{ textAlign: 'right', fontSize: 12.5, color: 'var(--danger)' }}>{money(p.late_fee_per_day)}</td>
                  {/* Two totals, each opening its own breakdown. */}
                  <td style={{ textAlign: 'right' }}>
                    <button className="link-button"
                      onClick={() => setBreakdown({ product: p, kind: 'warehouse' })}
                      title="Show each warehouse"
                      style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer',
                               font: 'inherit', fontWeight: 700,
                               color: totalIn(stockOf(p.id)) > 0 ? 'var(--primary)' : 'var(--text-muted)',
                               textDecoration: 'underline dotted' }}>
                      {totalIn(stockOf(p.id))}
                    </button>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <button className="link-button"
                      onClick={() => setBreakdown({ product: p, kind: 'store' })}
                      title="Show each store"
                      style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer',
                               font: 'inherit', fontWeight: 700,
                               color: totalIn(storeStockOf(p.id)) > 0 ? 'var(--primary)' : 'var(--text-muted)',
                               textDecoration: 'underline dotted' }}>
                      {totalIn(storeStockOf(p.id))}
                    </button>
                  </td>
                  <td><div style={{ display: 'flex', gap: 4 }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => { setStockFor(p); setStockWh(warehouses[0]?.id ?? ''); setStockQtyIn(0); }}><Boxes size={13} /> Stock</button>
                    <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(p)}><Pencil size={13} /></button>
                    <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(p)}><Trash2 size={13} /></button>
                  </div></td>
                </tr>))}
              </tbody>
            </table>
        ) : tab === 'sales' ? (
          sales.length === 0 ? <div className="empty-state"><ShoppingBag size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No special sales yet</p></div>
          : <table>
              <thead><tr><th>Sale</th><th>Product</th><th>Warehouse</th><th>Customer</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Total</th><th>Method</th><th>Status</th><th></th></tr></thead>
              <tbody>{sales.map(s => (
                <tr key={s.id}>
                  <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{s.sale_no}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{new Date(s.created_at).toLocaleDateString()}</div></td>
                  <td><strong>{spName(s.special_product_id)}</strong></td>
                  <td style={{ fontSize: 12.5 }}>{whName(s.warehouse_id)}</td>
                  <td style={{ fontSize: 12.5 }}>{cuName(s.customer_id)}</td>
                  <td style={{ textAlign: 'right' }}>{s.quantity}</td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(s.total_amount))}</td>
                  <td style={{ fontSize: 12 }}>{pmName(s.payment_method_id)}</td>
                  <td>{(() => { const b = specialSaleBadge(s); return <span className={`badge badge-${b.tone}`}>{b.label}</span>; })()}</td>
                  <td><div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => printReceipt('sale', s)} title="Print this sale"><Printer size={13} /> Print</button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('whatsapp', 'sale', s)}
                      disabled={!!sendBusy || !whatsappNumber(customers.find((c: any) => c.id === s.customer_id)?.phone)}
                      title="Send a link by WhatsApp" aria-label={`Send ${s.sale_no} by WhatsApp`}><MessageCircle size={13} /></button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('email', 'sale', s)}
                      disabled={!!sendBusy || !emailAddress(customers.find((c: any) => c.id === s.customer_id)?.email)}
                      title="Email from this device's mail app" aria-label={`Email ${s.sale_no} from this device`}><Mail size={13} /></button>
                  </div></td>
                </tr>))}
              </tbody>
            </table>
        ) : (
          rentals.length === 0 ? <div className="empty-state"><CalendarClock size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No rentals yet</p></div>
          : <table>
              <thead><tr><th>Rental</th><th>Product</th><th>Customer</th><th style={{ textAlign: 'right' }}>Qty</th><th>Period</th><th style={{ textAlign: 'right' }}>Fee</th><th>Due back</th><th>Status</th><th></th></tr></thead>
              <tbody>{rentals.map(r => {
                const overdue = overdueNote(r, todayStr());
                const lateStatus = lateFeeStatus(r, lateInvoiceNo(r));
                return (
                <tr key={r.id}>
                  <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.rental_no}</td>
                  <td><strong>{spName(r.special_product_id)}</strong><div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{releasedFrom(r)}</div></td>
                  <td style={{ fontSize: 12.5 }}>{cuName(r.customer_id)}</td>
                  <td style={{ textAlign: 'right' }}>{r.quantity}</td>
                  <td style={{ fontSize: 12 }}>{r.periods} × {RATE_TYPE_LABELS[r.rate_type].replace('Per ', '').toLowerCase()}{r.periods > 1 ? 's' : ''}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{new Date(r.start_date).toLocaleDateString()} →</div></td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.rental_fee))}
                    {/* 396: the late fee charged at the Return, and its invoice. */}
                    {lateStatus && <div style={{ fontSize: 11, fontWeight: 500, color: Number(r.late_fee_total) > 0 ? 'var(--danger)' : 'var(--text-muted)' }}>
                      {r.late_fee_invoice_id
                        ? <>+{money(Number(r.late_fee_total))} late · <Link to={`/invoices?review=${r.late_fee_invoice_id}`}
                            title="Open the late fee's invoice to print or send it">{lateInvoiceNo(r) ?? 'invoice'}</Link>
                            {docInvoices[r.late_fee_invoice_id] && docInvoices[r.late_fee_invoice_id].status !== 'paid'
                              && ` (${docInvoices[r.late_fee_invoice_id].status.replace(/_/g, ' ')})`}</>
                        : lateStatus}
                    </div>}</td>
                  <td style={{ fontSize: 12 }}>{new Date(r.expected_return_date).toLocaleDateString()}{isOverdue(r) && overdue && <div style={{ fontSize: 11, color: 'var(--danger)' }}>{overdue}</div>}</td>
                  <td><RentalBadge r={r} />{r.return_condition && <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>{r.return_condition}{r.stock_returned === false ? ' · not restocked' : r.stock_returned ? ' · restocked' : ''}</div>}</td>
                  <td><div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                    {(r.status === 'paid' || r.status === 'active') && <button className="btn btn-primary btn-sm" onClick={() => openReturn(r)}>Return</button>}
                    {rentalStillWithCustomer(r) && (
                      <button className="btn btn-primary btn-sm" onClick={() => openReceive(r)}
                        aria-label={`Receive returned item: ${spName(r.special_product_id)} (${r.rental_no})`}>Receive returned item</button>)}
                    <button className="btn btn-secondary btn-sm" onClick={() => printReceipt('rental', r)} title="Print this rental"><Printer size={13} /> Print</button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('whatsapp', 'rental', r)}
                      disabled={!!sendBusy || !whatsappNumber(customers.find((c: any) => c.id === r.customer_id)?.phone)}
                      title="Send a link by WhatsApp" aria-label={`Send ${r.rental_no} by WhatsApp`}><MessageCircle size={13} /></button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('email', 'rental', r)}
                      disabled={!!sendBusy || !emailAddress(customers.find((c: any) => c.id === r.customer_id)?.email)}
                      title="Email from this device's mail app" aria-label={`Email ${r.rental_no} from this device`}><Mail size={13} /></button>
                  </div></td>
                </tr>);
              })}
              </tbody>
            </table>
        )}
      </div></div>

      {/* Catalog add/edit */}
      {breakdown && (() => {
        const isWh = breakdown.kind === 'warehouse';
        const rowsFor = isWh ? stockOf(breakdown.product.id) : storeStockOf(breakdown.product.id);
        // Only locations actually holding some: a list of zeroes is noise.
        const held = rowsFor.filter(r => (r.current_qty || 0) > 0)
          .sort((a, b) => (b.current_qty || 0) - (a.current_qty || 0));
        const nameOf = (id: string) => isWh
          ? (warehouses.find(w => w.id === id)?.name ?? 'Unknown warehouse')
          : (brandStores.find((s2: any) => s2.id === id)?.name ?? 'Unknown store');
        return (
          <Modal title={`${breakdown.product.name} — ${isWh ? 'warehouses' : 'stores'}`}
            maxWidth={480} onClose={() => setBreakdown(null)}
            footer={<button className="btn btn-secondary" onClick={() => setBreakdown(null)}>Close</button>}>
            <div className="form-grid">
              <div style={{ display: 'flex', justifyContent: 'space-between',
                            alignItems: 'baseline', gap: 12 }}>
                <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
                  {isWh ? 'Held in warehouses' : 'Held in stores'}
                </span>
                <span style={{ fontSize: 24, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
                  {totalIn(rowsFor)}
                </span>
              </div>

              {held.length === 0 ? (
                <div style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>
                  None held in any {isWh ? 'warehouse' : 'store'}.
                </div>
              ) : (
                <div className="table-wrap">
                  <table>
                    <thead><tr>
                      <th>{isWh ? 'Warehouse' : 'Store'}</th>
                      <th style={{ textAlign: 'right' }}>Quantity</th>
                    </tr></thead>
                    <tbody>
                      {held.map(r => (
                        <tr key={r.id}>
                          <td>{isWh ? '🏭 ' : '🏪 '}{nameOf(r.warehouse_id)}</td>
                          <td style={{ textAlign: 'right', fontWeight: 600,
                                       fontVariantNumeric: 'tabular-nums' }}>{r.current_qty}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                {isWh
                  ? 'Stores are counted separately — see the "In stores" column.'
                  : 'Warehouses are counted separately — see the "In warehouses" column.'}
              </div>
            </div>
          </Modal>
        );
      })()}

      {queueOpen && (
        <Modal title="Waiting for a warehouse" wide onClose={() => setQueueOpen(false)}
          footer={<button className="btn btn-secondary" onClick={() => setQueueOpen(false)}>Close</button>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            {rentNote && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ</span><div>{rentNote}</div></div>}
            {awaitingFailed && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>Could not load the waiting list. Press Refresh.</div></div>}
            {availFailed && <div className="alert alert-warning" style={{ marginBottom: 0 }}><span>⚠</span><div>Could not load where each item can come from. Press Refresh before releasing.</div></div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              These are paid for and no stock has moved. Choosing a warehouse is what takes the
              goods out of it.
            </div>
            {awaitingFailed ? null : awaiting.length === 0 ? (
              <div style={{ textAlign: 'center', padding: 24, color: 'var(--text-muted)' }}>
                Nothing is waiting — everything paid for has been released.
              </div>
            ) : (
              <div>
                {/* Three columns, one under 640 px (globals.css, 426). */}
                <div className="special-queue-grid special-queue-head">
                  <div>Item</div>
                  <div>Release from</div>
                  <div />
                </div>
{awaiting.map(row => {
            const opts = avail[row.doc_id] ?? [];
            const chosen = opts.find((o: any) => `${o.location_type}:${o.warehouse_id}` === fulfilWh[row.doc_id]);
            const canCover = opts.filter((o: any) => o.available >= row.quantity);
            const isRental = row.doc_kind === 'rental';
            return (
              <div key={row.doc_id} className="special-queue-grid special-queue-row">
                {/* WHAT — the thing itself, read first */}
                <div style={{ minWidth: 0 }}>
                  <div style={{ display: 'flex', gap: 8, alignItems: 'baseline', flexWrap: 'wrap' }}>
                    <span style={{ fontSize: 14, fontWeight: 700 }}>{row.product_name}</span>
                    <span className={`badge ${isRental ? 'badge-accent' : 'badge-muted'}`}
                      style={{ fontSize: 10.5 }}>{isRental ? 'Rental' : 'Sale'}</span>
                    {row.quantity > 1 && <span style={{ fontSize: 13 }}>× {row.quantity}</span>}
                  </div>
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2,
                                overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {row.customer_name ?? '—'} · {row.doc_no}
                    {row.invoice_no ? ` · ${row.invoice_no}` : ''}
                  </div>
                  {isRental && (
                    <div style={{ fontSize: 12, marginTop: 4, display: 'flex',
                                  gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                      <span>
                        <strong>{row.periods} {row.rate_type}{(row.periods ?? 1) > 1 ? 's' : ''}</strong>
                        {row.expected_return_date && (
                          <span style={{ color: 'var(--text-muted)' }}>
                            {' '}· back {new Date(row.expected_return_date).toLocaleDateString('en-GB')}
                          </span>
                        )}
                      </span>
                      {hasAccess && (
                        <button className="btn btn-secondary btn-sm"
                          style={{ padding: '1px 8px', fontSize: 11 }}
                          onClick={() => openRentalEdit(row)}>Change</button>
                      )}
                    </div>
                  )}
                </div>

                {/* WHERE FROM — the decision being made */}
                {hasAccess ? (
                  <div style={{ minWidth: 0 }}>
                    <select value={fulfilWh[row.doc_id] ?? ''} style={{ width: '100%' }}
                      onChange={e => setFulfilWh(w => ({ ...w, [row.doc_id]: e.target.value }))}>
                      <option value="">
                        {opts.length === 0 ? 'Nowhere holds this'
                          : canCover.length === 0 ? `Nowhere has ${row.quantity} free`
                          : `Choose from ${canCover.length} location${canCover.length === 1 ? '' : 's'}…`}
                      </option>
                      {/* The value carries the LOCATION TYPE as well as the id.
                          Without the prefix the id alone was sent, doFulfil
                          defaulted to 'warehouse', and picking a store failed
                          with "That warehouse does not exist". */}
                      {opts.map((o: any) => (
                        <option key={`${o.location_type}:${o.warehouse_id}`}
                          value={`${o.location_type}:${o.warehouse_id}`}
                          disabled={o.available < row.quantity}>
                          {o.location_type === 'store' ? '🏪 ' : '🏭 '}{o.warehouse_name} — {o.available} free
                          {o.available < row.quantity ? ' (not enough)' : ''}
                        </option>
                      ))}
                    </select>
                    {chosen && chosen.reserved > 0 && (
                      <div style={{ fontSize: 11, color: 'var(--warning)', marginTop: 3 }}>
                        {chosen.on_hand} on hand, {chosen.reserved} held by pending transfers
                      </div>
                    )}
                    {opts.length > 0 && canCover.length === 0 && (
                      <div style={{ fontSize: 11, color: 'var(--danger)', marginTop: 3 }}>
                        Add stock, or approve/reject the transfers holding it.
                      </div>
                    )}
                  </div>
                ) : (
                  <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                    Awaiting an Owner or Manager.
                  </div>
                )}

                {/* THE ACTION */}
                {hasAccess ? (
                  <button className="btn btn-primary btn-sm" onClick={() => doFulfil(row)}
                    disabled={fulfilBusy === row.doc_id || !fulfilWh[row.doc_id]
                              || (chosen && chosen.available < row.quantity)}
                    style={{ whiteSpace: 'nowrap' }}>
                    {fulfilBusy === row.doc_id ? 'Releasing…' : 'Release'}
                  </button>
                ) : <span />}
              </div>
            );
          })}
              </div>
            )}
          </div>
        </Modal>
      )}

      {editRental && (
        <Modal title={`Change rental terms — ${editRental.doc_no}`} onClose={() => setEditRental(null)}
          confirmClose={termsChanged(rentForm, rentOpened)}
          footer={<><button className="btn btn-secondary" onClick={() => setEditRental(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveRental} disabled={rentBusy || !!rentProblem}
              title={rentProblem ?? undefined}>
              {rentBusy ? 'Saving…' : 'Save terms'}</button></>}>
          <div className="form-grid">
            {/* Its own error line: the waiting list behind it is covered (426). */}
            {rentErr && <div className="alert alert-danger" style={{ marginBottom: 0 }} role="alert"><span>⚠</span><div>{rentErr}</div></div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              {editRental.product_name} · {editRental.customer_name ?? '—'}
              {editRental.invoice_no ? ` · ${editRental.invoice_no}` : ''}
            </div>
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}><label>Quantity</label>
                <input type="number" min={1} max={999} value={rentForm.quantity}
                  onChange={e => changeTerms({ quantity: +e.target.value })} /></div>
              <div className="form-group" style={{ marginBottom: 0 }}><label>Rate</label>
                <select value={rentForm.rate_type}
                  onChange={e => changeTerms({ rate_type: e.target.value as TermsForm['rate_type'] })}>
                  {(['day','week','month','year'] as const)
                    .filter(rt => Number(rows.find((p: any) => p.id === editRental.special_product_id)?.[`rate_${rt}`] ?? 0) > 0)
                    .map(rt => <option key={rt} value={rt}>Per {rt}</option>)}
                </select></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}><label>Periods</label>
                <input type="number" min={1} max={3650} value={rentForm.periods}
                  onChange={e => changeTerms({ periods: +e.target.value })} /></div>
              <div className="form-group" style={{ marginBottom: 0 }}><label>Starts</label>
                <input type="date" value={rentForm.start_date}
                  onChange={e => changeTerms({ start_date: e.target.value })} /></div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Due back</label>
              <input type="date" value={rentForm.expected_return_date} min={rentForm.start_date}
                onChange={e => { const v = e.target.value; setRentForm(f => ({ ...f, expected_return_date: v })); }} />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                Worked out from the start and the periods. You can type another date; late fees count from it.</div></div>
            {rentProblem && !rentErr && <div style={{ fontSize: 12, color: 'var(--danger)' }}>{rentProblem}</div>}
            {/* The fee as the save will work it out (426): the same discount as sold. */}
            <div className="alert alert-warning" style={{ marginBottom: 0 }} role="status" aria-live="polite" data-rental-fee>
              <span>⚠</span>
              {!rentFee ? (
                <div>
                  {/* No paid amount is named here: the rental's own fee can be the value before a line
                      discount, or from before a correction of the invoice. */}
                  The fee will be worked out when you save: a change of the dates alone keeps it as sold, and a
                  new quantity, rate or number of periods is priced at the list rate with the same discount as sold.
                  You will be told any difference to collect or refund on the invoice.
                </div>
              ) : rentFee.problem ? (
                <div>{rentFee.problem}</div>
              ) : rentFee.datesOnly ? (
                <div>
                  The fee stays <strong>{money(rentFee.before)}</strong>: a change of the dates alone keeps it.
                  A new quantity, rate or number of periods is priced at the list rate with the same discount as sold.
                </div>
              ) : (
                <div>
                  New fee <strong>{money(rentFee.fee ?? 0)}</strong>
                  {' '}({money(rentFee.list ?? 0)} at the list rate{rentFee.discount ? `; ${rentFee.discount}` : ''}).{' '}
                  {(rentFee.difference ?? 0) === 0
                    ? <>The same as the {money(rentFee.before)} already invoiced.</>
                    : <>That is {money(Math.abs(rentFee.difference ?? 0))} {(rentFee.difference ?? 0) > 0 ? 'more' : 'less'} than
                      the {money(rentFee.before)} already invoiced — {(rentFee.difference ?? 0) > 0 ? 'collect' : 'refund'} the
                      difference on the invoice.</>}
                </div>
              )}
            </div>
          </div>
        </Modal>
      )}

      {modalOpen && (
        <Modal title={editId ? 'Edit Special Product' : 'Add Special Product'} wide onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            {/* The product IS the special product: its name, SKU and stock all
                come from the warehouse, so the two can never disagree. */}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Product *</label>
              {editId ? (
                <input value={`${form.name}${form.sku ? ` (${form.sku})` : ''}`} disabled
                  style={{ background: 'var(--surface-2)' }} />
              ) : (
                <SearchSelect value={form.product_id ?? ''}
                  onChange={(v: string) => {
                    const p = availableProducts.find((x: any) => x.product_id === v);
                    setForm(f => ({ ...f, product_id: v, name: p?.name ?? '', sku: p?.sku ?? '' }));
                  }}
                  placeholder="Search a warehouse product by name or SKU…"
                  options={availableProducts.map((p: any) => ({
                    value: p.product_id,
                    label: p.name,
                    sublabel: `${p.sku ?? '—'} · ${p.total_stock} in warehouse stock`,
                    search: `${p.name} ${p.sku ?? ''}`,
                  }))} />
              )}
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                {editId
                  ? 'The product cannot be changed once added — remove this entry and add the other product instead.'
                  : 'Stock is the warehouse stock. Renting or selling a unit reduces the same figure a transfer would draw on.'}
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Sale Price (S$)</label><input type="number" min={0} step={0.01} value={form.sale_price || ''} onChange={e => setForm(f => ({ ...f, sale_price: +e.target.value }))} /></div>
              <div className="form-group"><label>Late Fee / day (S$)</label><input type="number" min={0} step={0.01} value={form.late_fee_per_day || ''} onChange={e => setForm(f => ({ ...f, late_fee_per_day: +e.target.value }))} /></div>
            </div>
            <div>
              <label>Rental rates (S$ per unit) <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— leave 0 to disable that duration</span></label>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8, marginTop: 6 }}>
                {(['rate_day','rate_week','rate_month','rate_year'] as const).map(k => (
                  <div className="form-group" key={k} style={{ marginBottom: 0 }}>
                    <label style={{ fontSize: 11 }}>{k === 'rate_day' ? 'Day' : k === 'rate_week' ? 'Week' : k === 'rate_month' ? 'Month' : 'Year'}</label>
                    <input type="number" min={0} step={0.01} value={form[k] || ''} onChange={e => setForm(f => ({ ...f, [k]: +e.target.value }))} />
                  </div>
                ))}
              </div>
            </div>
            <div className="form-group"><label>Description</label><textarea rows={2} value={form.description} onChange={e => { const v = e.target.value; setForm(f => ({ ...f, description: v })); }} placeholder="Optional" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
          </div>
        </Modal>
      )}

      {/* Stock modal */}
      {stockFor && (
        <Modal title={`Stock — ${stockFor.name}`} wide onClose={() => setStockFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setStockFor(null)}>Close</button><button className="btn btn-primary" onClick={addStock} disabled={stockBusy || !stockWh || stockQtyIn <= 0}>{stockBusy ? 'Adding…' : 'Add Stock'}</button></>}>
          <div className="form-grid">
            <div className="form-grid-2">
              <div className="form-group"><label>Warehouse</label>
                <select value={stockWh} onChange={e => setStockWh(e.target.value)}>{warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}</select>
              </div>
              <div className="form-group"><label>Add Quantity</label><input type="number" min={1} value={stockQtyIn || ''} onChange={e => setStockQtyIn(+e.target.value)} /></div>
            </div>
            <div>
              <label>Current stock by warehouse</label>
              {totalIn(storeStockOf(stockFor.id)) > 0 && (
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 4 }}>
                  A further <strong>{totalIn(storeStockOf(stockFor.id))}</strong> is held in stores.
                  Stock is added to warehouses here; store stock arrives by transfer.
                </div>
              )}
              <table style={{ marginTop: 4 }}>
                <thead><tr><th>Warehouse</th><th style={{ textAlign: 'right' }}>Qty</th></tr></thead>
                <tbody>
                  {stockOf(stockFor.id).length === 0 ? <tr><td colSpan={2} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 14 }}>No stock yet</td></tr>
                    : stockOf(stockFor.id).map(s => <tr key={s.id}><td>{whName(s.warehouse_id)}</td><td style={{ textAlign: 'right', fontWeight: 600 }}>{s.current_qty}</td></tr>)}
                </tbody>
              </table>
            </div>
          </div>
        </Modal>
      )}

      {/* Receive returned item (417; the owner, 10 Oct 2026) */}
      {recvFor && (
        <Modal title={`Receive returned item — ${recvFor.rental_no}`} maxWidth={520} onClose={closeReceive}
          confirmClose={!recvDone && (recvChoice.outcome !== '' || recvNote.trim() !== '')}
          footer={recvDone
            ? <button className="btn btn-primary" onClick={closeReceive}>Done</button>
            : <><button className="btn btn-secondary" onClick={closeReceive}>Cancel</button>
              <button className="btn btn-primary" onClick={submitReceive}
                disabled={recvBusy || !recvChoice.outcome || !recvNote.trim()}>
                {recvBusy ? 'Recording…' : 'Record what came back'}</button></>}>
          {recvDone ? (
            <div className="alert alert-success" style={{ marginBottom: 0 }} role="status"><span>✓</span><div>{recvDone}</div></div>
          ) : (
          <div className="form-grid">
            {recvErr && <div className="alert alert-danger" style={{ marginBottom: 0 }} role="alert"><span>⚠</span><div>{recvErr}</div></div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              {recvFor.item} × {recvFor.quantity} · {cuName(rentals.find(x => x.id === recvFor.rental_id)?.customer_id ?? null)}.
              {' '}This rental was cancelled while the item was still with the customer. Record it only when
              it is actually in your hands. Damaged and lost items are never put back on sale.
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>What happened *</label>
              <select value={recvChoice.outcome} aria-label={`What happened to ${recvFor.rental_no}`}
                onChange={e => { const v = e.target.value as ReceiveChoice['outcome']; setRecvChoice(c => ({ ...c, outcome: v })); }}>
                <option value="">Choose…</option>
                <option value="good">Back in good condition — on sale again</option>
                <option value="damaged">Back but damaged — not for sale</option>
                <option value="lost">Lost — never came back</option>
              </select></div>
            {recvChoice.outcome === 'good' && (
              <div className="form-group" style={{ marginBottom: 0 }}><label>Goes back to</label>
                <select value={recvChoice.warehouseId} aria-label={`Where ${recvFor.rental_no} goes back to`}
                  onChange={e => { const v = e.target.value; setRecvChoice(c => ({ ...c, warehouseId: v })); }}>
                  <option value="">{receiveHomeLabel(recvFor)}</option>
                  {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
                </select></div>)}
            <div className="form-group" style={{ marginBottom: 0 }}><label>Note *</label>
              <input value={recvNote} onChange={e => setRecvNote(e.target.value)}
                placeholder="For the history, e.g. who brought it back" /></div>
          </div>
          )}
        </Modal>
      )}

      {/* Return rental (396) */}
      {retFor && retForm && (() => {
        const late = lateDaysOn(retFor, retForm.returnedOn);
        const charging = retForm.choice === 'charge' && late > 0;
        const fee = lateFeeAmounts(retForm, retFor);
        const sum = lateFeeSum(retForm, retFor);
        const needStore = needsStoreChoice(retFor);
        const done = retDone;
        return (
        <Modal title={`Return — ${retFor.rental_no}`} maxWidth={520} onClose={closeReturn}
          // A stray tap on the backdrop asks before a half-filled Return is
          // lost (426, SALES-EXTRAS-15); once recorded it closes straight away.
          confirmClose={!done}
          footer={done
            ? <button className="btn btn-primary" onClick={closeReturn}>Done</button>
            : <><button className="btn btn-secondary" onClick={closeReturn}>Cancel</button>
              <button className="btn btn-primary" onClick={submitReturn} disabled={retBusy || !!retProblem}
                title={retProblem ?? undefined}>
                {retBusy ? 'Recording…' : charging && fee.total > 0 ? `Confirm Return · collect ${money(fee.total)}` : 'Confirm Return'}</button></>}>
          {done ? (
            <div className="form-grid">
              <div className="alert alert-success" style={{ marginBottom: 0 }}><span>✓</span><div>
                <strong>{retFor.rental_no}</strong> returned on {shortDate(String(done.returned_on ?? retForm.returnedOn))}.
                {Number(done.restocked_quantity ?? 0) > 0
                  ? done.stock_location_type === 'special_stock'
                    ? <> {done.restocked_quantity} put back into the old special stock at {done.stock_location_name ?? 'its warehouse'}; warehouse stock did not change.</>
                    : <> {done.restocked_quantity} put back into {done.stock_location_name ?? 'its'} stock.</>
                  : done.stock_note ? <> {done.stock_note}</> : <> No stock changed.</>}
              </div></div>
              {done.invoice_id ? (
                <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', fontSize: 13 }}>
                  Late fee <strong>{money(Number(done.late_fee_total ?? 0))}</strong> invoiced and paid on{' '}
                  <strong>{done.invoice_no}</strong>{done.store_name ? <> ({done.store_name})</> : null}.
                  <div style={{ marginTop: 8, display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                    <Link className="btn btn-secondary btn-sm" to={`/invoices?review=${done.invoice_id}`}>
                      Open invoice {done.invoice_no}</Link>
                    <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>to print it or send it to the customer</span>
                  </div>
                </div>
              ) : Number(done.late_days ?? 0) > 0
                ? <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{done.late_days} day{Number(done.late_days) === 1 ? '' : 's'} late, no late fee charged.</div>
                : null}
            </div>
          ) : (
          <div className="form-grid">
            {retErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{retErr}</div></div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              {spName(retFor.special_product_id)} × {retFor.quantity} · {cuName(retFor.customer_id)} ·
              {' '}out {shortDate(retFor.start_date)}, due back {shortDate(retFor.expected_return_date)}
            </div>
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}><label>Returned on</label>
                <input type="date" value={retForm.returnedOn} min={String(retFor.start_date).slice(0, 10)} max={todayStr()}
                  onChange={e => setRetForm(f => (f ? withReturnedOn(f, retFor, e.target.value) : f))} /></div>
              <div className="form-group" style={{ marginBottom: 0 }}><label>Condition</label>
                <select value={retForm.condition}
                  onChange={e => { const c = e.target.value as ReturnCondition; setRetForm(f => (f ? withCondition(f, c) : f)); }}>
                  <option value="good">Good</option><option value="damaged">Damaged</option><option value="lost">Lost</option>
                </select>
              </div>
            </div>
            {retHome?.canRestock ? (
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: retForm.condition === 'lost' ? 'not-allowed' : 'pointer', padding: '10px 12px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                {/* A lost unit never goes back into stock: "Lost" unticks and locks the box. */}
                <input type="checkbox" checked={retForm.returnStock} disabled={retForm.condition === 'lost'}
                  onChange={e => setRet({ returnStock: e.target.checked })} style={{ width: 'auto' }} />
                <div><div style={{ fontSize: 13, fontWeight: 600 }}>{retHome.label}</div>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                  {retForm.condition === 'lost' ? 'A lost unit does not go back into stock: no stock changes.' : retHome.hint}</div></div>
              </label>
            ) : retHome && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>{retHome.note}</div></div>
            )}
            {/* Nothing about lateness until a date is chosen (a cleared date input gives ''). */}
            {!isDay(retForm.returnedOn) ? null : late === 0 ? (
              <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>{lateNotice(retFor, retForm.returnedOn)}</div></div>
            ) : (
              <>
                <div className="alert alert-warning" style={{ marginBottom: 0 }}><span>⚠</span><div>{lateNotice(retFor, retForm.returnedOn)}</div></div>
                <div style={{ display: 'flex', gap: 6 }} role="radiogroup" aria-label="Late fee">
                  <button type="button" role="radio" aria-checked={retForm.choice === 'none'}
                    className={`btn btn-sm ${retForm.choice === 'none' ? 'btn-primary' : 'btn-secondary'}`}
                    onClick={() => setRet({ choice: 'none' })}>No late fee</button>
                  <button type="button" role="radio" aria-checked={retForm.choice === 'charge'}
                    className={`btn btn-sm ${retForm.choice === 'charge' ? 'btn-primary' : 'btn-secondary'}`}
                    onClick={() => setRet({ choice: 'charge' })}>Charge late fee</button>
                </div>
                {charging && (
                  <>
                    <div className="form-grid-2">
                      <div className="form-group" style={{ marginBottom: 0 }}><label>Days to charge</label>
                        <input type="number" min={1} max={late} step={1} value={retForm.days}
                          onChange={e => setRet({ days: e.target.value })} />
                        <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Up to {late}; fewer needs no reason.</div></div>
                      <div className="form-group" style={{ marginBottom: 0 }}><label>Daily late fee (S$) *</label>
                        <input type="number" min={0} step={0.01} value={retForm.rate} placeholder="Type the rate"
                          onChange={e => setRet({ rate: e.target.value })} />
                        {retFor.quantity > 1 && <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Per unit, for {retFor.quantity} units.</div>}</div>
                    </div>
                    <div className="form-grid-2">
                      <div className="form-group" style={{ marginBottom: 0 }}><label>Discount</label>
                        <select value={retForm.discount} onChange={e => setRet({ discount: e.target.value as ReturnForm['discount'] })}>
                          <option value="">No discount</option>
                          <option value="manual">Amount (S$)</option>
                          <option value="percentage">Percentage (%)</option>
                        </select></div>
                      {retForm.discount === 'manual' && (
                        <div className="form-group" style={{ marginBottom: 0 }}><label>Discount (S$)</label>
                          <input type="number" min={0} step={0.01} value={retForm.discountAmount}
                            onChange={e => setRet({ discountAmount: e.target.value })} /></div>)}
                      {retForm.discount === 'percentage' && (
                        <div className="form-group" style={{ marginBottom: 0 }}><label>Discount (%)</label>
                          <input type="number" min={0} max={100} step={0.001} value={retForm.discountPercent}
                            onChange={e => setRet({ discountPercent: e.target.value })} /></div>)}
                    </div>
                    {retForm.discount && (
                      <div className="form-group" style={{ marginBottom: 0 }}><label>Reason for the discount *</label>
                        <input value={retForm.discountReason} onChange={e => setRet({ discountReason: e.target.value })}
                          placeholder="Internal: stays on the invoice for staff, never printed" /></div>)}
                    {sum && <div style={{ fontSize: 13 }}>Late fee: {sum}</div>}
                    <div className="form-grid-2">
                      <div className="form-group" style={{ marginBottom: 0 }}><label>Paid by *</label>
                        <select value={retForm.paymentMethodId} onChange={e => setRet({ paymentMethodId: e.target.value })}>
                          <option value="">Choose…</option>
                          {lateFeeMethods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                        </select></div>
                      <div className="form-group" style={{ marginBottom: 0 }}><label>Reference</label>
                        <input value={retForm.reference} onChange={e => setRet({ reference: e.target.value })} placeholder="Optional" /></div>
                    </div>
                    {needStore && (
                      <div className="form-group" style={{ marginBottom: 0 }}><label>Invoice in store *</label>
                        <select value={retForm.storeId} onChange={e => setRet({ storeId: e.target.value })}>
                          <option value="">Choose…</option>
                          {brandStores.map((s2: any) => <option key={s2.id} value={s2.id}>{s2.name}</option>)}
                        </select>
                        <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>This rental has no store of its own.</div></div>)}
                    <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                      Confirm Return invoices the late fee on an invoice of its own, for {cuName(retFor.customer_id)},
                      {' '}dated {shortDate(retForm.returnedOn)}, and records its payment. No commission is earned on it.
                    </div>
                  </>
                )}
              </>
            )}
            {retProblem && !retErr && <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{retProblem}</div>}
          </div>
          )}
        </Modal>
        );
      })()}
    </div>
  );
};

export default SpecialPage;
