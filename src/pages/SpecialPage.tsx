import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { sendViaWhatsAppLink, sendViaEmailAttachment, whatsappNumber, emailAddress } from '../lib/sendDoc';
import { PdfDoc } from '../lib/invoicePdf';
import { printA5Document, esc as pesc, money as pmoney, PrintLine, PrintTotal } from '../lib/printDoc';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  SpecialProduct, SpecialProductStock, SpecialSale, Rental, Warehouse, Customer, PaymentMethod,
  SpecialRateType, RentalStatus, ReturnCondition, RATE_TYPE_LABELS, RENTAL_STATUS_LABELS, isOwnerOrManager,
} from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, RefreshCw, Boxes, KeyRound, ShoppingBag, CalendarClock, Clock, X, Download, Printer, MessageCircle, Mail} from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';
import { CustomerSearchSelect } from '../components/SearchSelect';
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

// Pure-UTC date arithmetic so the local→UTC conversion can never eat a day.
const addPeriods = (start: string, rateType: SpecialRateType, periods: number): string => {
  const [y, m, dd] = start.split('-').map(Number);
  const d = new Date(Date.UTC(y, m - 1, dd));
  if (rateType === 'day') d.setUTCDate(d.getUTCDate() + periods);
  else if (rateType === 'week') d.setUTCDate(d.getUTCDate() + 7 * periods);
  else if (rateType === 'month') d.setUTCMonth(d.getUTCMonth() + periods);
  else d.setUTCFullYear(d.getUTCFullYear() + periods);
  return d.toISOString().slice(0, 10);
};

const SpecialPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isOwnerOrManager(profile?.role);
  const [tab, setTab] = useState<'catalog' | 'sales' | 'rentals'>('catalog');


  const [rows, setRows] = useState<SpecialProduct[]>([]);
  const [stock, setStock] = useState<SpecialProductStock[]>([]);
  const [sales, setSales] = useState<SpecialSale[]>([]);
  const [rentals, setRentals] = useState<Rental[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  // Branding for printing. Rentals and special sales belong to a warehouse,
  // so the letterhead is taken from the store.
  const [brandStores, setBrandStores] = useState<any[]>([]);
  const [staffProfiles, setStaffProfiles] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);


  const load = useCallback(async () => {
    setLoading(true);
    const [sp, st, sa, re, wh, cu, pm, sto, prof] = await Promise.all([
      supabase.from('special_products').select('*').is('deleted_at', null).order('name'),
      supabase.from('warehouse_inventory').select('warehouse_id,product_id,current_qty'),
      supabase.from('special_sales').select('*').order('created_at', { ascending: false }),
      supabase.from('rentals').select('*').order('created_at', { ascending: false }),
      supabase.from('warehouses').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('id,full_name,phone').is('deleted_at', null).order('full_name'),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('profiles').select('id,full_name').is('deleted_at', null),
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
    setSales((sa.data as SpecialSale[]) ?? []);
    setRentals((re.data as Rental[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    setBrandStores((sto.data as any[]) ?? []);
    setStaffProfiles((prof.data as any[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const spName = (id: string) => rows.find(r => r.id === id)?.name ?? '—';
  const whName = (id: string) => warehouses.find(w => w.id === id)?.name ?? '—';
  const cuName = (id: string | null) => id ? (customers.find(c => c.id === id)?.full_name ?? '—') : '—';
  const pmName = (id: string | null) => id ? (methods.find(m => m.id === id)?.name ?? '—') : '—';
  const stockOf = (spId: string, whId?: string) => stock.filter(s => s.special_product_id === spId && (!whId || s.warehouse_id === whId));
  const isOverdue = (r: Rental) => (r.status === 'paid' || r.status === 'active') && todayStr() > r.expected_return_date;
  const latePreview = (r: Rental) => {
    const days = Math.max(0, Math.round((new Date(todayStr()).getTime() - new Date(r.expected_return_date).getTime()) / 86400000));
    return { days, total: days * r.late_fee_per_day * r.quantity };
  };

  // Special sales and rentals are their own transactions with their own numbers,
  // so they get a printable receipt rather than being forced through an invoice.
  // The customer copy as a real A5 PDF, matching the printed receipt.
  const [sendBusy, setSendBusy] = useState<string | null>(null);
  // Paid sales and rentals with no warehouse yet — Owner/Manager assigns one,
  // and only then does stock move.
  const [awaiting, setAwaiting] = useState<any[]>([]);
  const [fulfilWh, setFulfilWh] = useState<Record<string, string>>({});
  const [fulfilBusy, setFulfilBusy] = useState<string | null>(null);
  const [editRental, setEditRental] = useState<any | null>(null);
  const [rentForm, setRentForm] = useState<any>({});
  const [rentBusy, setRentBusy] = useState(false);
  const [rentNote, setRentNote] = useState<string | null>(null);
  const [queueOpen, setQueueOpen] = useState(false);

  const openRentalEdit = (row: any) => {
    setEditRental(row);
    setRentForm({
      quantity: row.quantity ?? 1, rate_type: row.rate_type ?? 'day',
      periods: row.periods ?? 1,
      start_date: row.start_date ? String(row.start_date).slice(0, 10) : '',
      expected_return_date: row.expected_return_date ? String(row.expected_return_date).slice(0, 10) : '',
    });
    setRentNote(null);
  };
  const saveRental = async () => {
    if (!editRental) return;
    setRentBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('update_pending_rental', {
      p_rental_id: editRental.doc_id,
      p_quantity: Number(rentForm.quantity) || 1,
      p_rate_type: rentForm.rate_type,
      p_periods: Number(rentForm.periods) || 1,
      p_start_date: rentForm.start_date || null,
      p_expected_return_date: rentForm.expected_return_date || null,
    });
    setRentBusy(false);
    if (error) { setErr(error.message); return; }
    const diff = Number((data as any)?.difference ?? 0);
    setEditRental(null);
    await loadAwaiting();
    if (diff !== 0) {
      // The invoice was settled at the old fee, so say so rather than letting
      // the discrepancy surface later.
      setRentNote(`The rental fee is now ${money(Number((data as any).rental_fee))} — `
        + `${money(Math.abs(diff))} ${diff > 0 ? 'more' : 'less'} than the `
        + `${money(Number((data as any).invoiced_fee))} already invoiced. `
        + `Collect or refund the difference on the invoice.`);
    }
  };
  // Availability per waiting document: what each warehouse holds, and how much
  // of it is already claimed by pending transfer requests.
  const [avail, setAvail] = useState<Record<string, any[]>>({});
  const loadAwaiting = async () => {
    const { data } = await supabase.rpc('special_docs_awaiting_fulfilment');
    const rows = (data as any[]) ?? [];
    setAwaiting(rows);
    const map: Record<string, any[]> = {};
    await Promise.all(rows.map(async r => {
      const { data: a } = await supabase.rpc('special_product_availability',
        { p_special_product_id: r.special_product_id });
      map[r.doc_id] = (a as any[]) ?? [];
    }));
    setAvail(map);
  };
  useEffect(() => { void loadAwaiting(); }, []);

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
    const { data } = await supabase.rpc('special_docs_awaiting_fulfilment');
    const left = (data as any[]) ?? [];
    await loadAwaiting(); load();
    // Nothing left to release: close rather than leaving an empty dialog open.
    if (left.length === 0) setQueueOpen(false);
  };
  const buildReceiptPdf = (kind: 'sale' | 'rental', row: any): PdfDoc => {
    const prod = rows.find((p: any) => p.id === row.special_product_id);
    const cust = customers.find((c: any) => c.id === row.customer_id);
    const wh = warehouses.find((w: any) => w.id === row.warehouse_id);
    const b: any = brandStores[0] ?? {};
    const fee = Number(kind === 'sale' ? row.total_amount : row.rental_fee) || 0;
    const late = Number(row.late_fee_total ?? 0);
    const d = (v: any) => v ? new Date(v).toLocaleDateString('en-GB') : '';
    return {
      kindLabel: kind === 'sale' ? 'Special Product Sale' : 'Special Product Rental',
      docNo: row.sale_no ?? row.rental_no,
      date: d(row.created_at),
      status: String(row.status ?? '').replace(/_/g, ' '),
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
                 ...(row.returned_at ? [`Returned ${d(row.returned_at)}`] : [])]
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

  const sendReceiptPdf = async (channel: 'whatsapp' | 'email', kind: 'sale' | 'rental', row: any) => {
    const cust = customers.find((c: any) => c.id === row.customer_id);
    setSendBusy(`${channel}-${row.id}`); setErr(null);
    const args = {
      pdf: buildReceiptPdf(kind, row),
      kindLabel: kind === 'sale' ? 'Sale' : 'Rental',
      docNo: row.sale_no ?? row.rental_no, docId: row.id,
      docKind: (kind === 'sale' ? 'special_sale' : 'rental') as 'special_sale' | 'rental',
      storeId: brandStores[0]?.id ?? null,
      customerId: row.customer_id, customerName: cust?.full_name,
      phone: cust?.phone, email: cust?.email,
    };
    const r = channel === 'whatsapp'
      ? await sendViaWhatsAppLink(args)
      : await sendViaEmailAttachment(args);
    setSendBusy(null);
    if (!r.ok) { setErr(r.reason ?? 'Could not send.'); return; }
    // A link or a share sheet is not the same as an attached PDF; say which.
    if ((r as any).reason) setErr((r as any).reason);
  };

  const printReceipt = (kind: 'sale' | 'rental', row: any) => {
    const prod = rows.find((p: any) => p.id === row.special_product_id);
    const cust = customers.find((c: any) => c.id === row.customer_id);
    const wh = warehouses.find((w: any) => w.id === row.warehouse_id);
    const methodName = (id: any) => methods.find(m => m.id === id)?.name ?? '';
    const d = (v: any) => v ? new Date(v).toLocaleDateString('en-GB') : '—';

    const fee = Number(kind === 'sale' ? row.total_amount : row.rental_fee) || 0;
    const late = Number(row.late_fee_total ?? 0);

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
      policyText: (brandStores[0] as any)?.policy_text ?? null,
      docNo: row.sale_no ?? row.rental_no,
      docTitle: kind === 'sale' ? 'Special Product Sale' : 'Special Product Rental',
      branding: brandStores[0] ?? {},
      headerLines: [
        `Date: ${d(row.created_at)}`,
        `Status: ${pesc(String(row.status ?? '').replace(/_/g, ' '))}`,
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
      p_description: form.description.trim() || null, p_is_active: form.is_active,
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

  // ── New sale modal ──
  const [saleOpen, setSaleOpen] = useState(false);
  const [sProduct, setSProduct] = useState(''); const [sWh, setSWh] = useState('');
  const [sCustomer, setSCustomer] = useState(''); const [sQty, setSQty] = useState(1);
  const [sMethod, setSMethod] = useState(''); const [sRef, setSRef] = useState('');
  const [sBusy, setSBusy] = useState(false); const [sErr, setSErr] = useState<string | null>(null);
  const openSale = () => { setSProduct(''); setSWh(warehouses[0]?.id ?? ''); setSCustomer(''); setSQty(1); setSMethod(methods[0]?.id ?? ''); setSRef(''); setSErr(null); setSaleOpen(true); };
  // Phase 30: a special sale may be part- or fully funded from the customer's
  // wallet, provided their credit permits the Special Products category.
  const [sUseCredit, setSUseCredit] = useState(false);
  const [sCreditAmt, setSCreditAmt] = useState('');
  const [sWallet, setSWallet] = useState<any>(null);
  useEffect(() => {
    if (!sCustomer) { setSWallet(null); return; }
    supabase.rpc('customer_credit_balances', { p_customer_id: sCustomer })
      .then(({ data }) => setSWallet(data ?? null));
  }, [sCustomer]);

  const submitSale = async () => {
    if (!sProduct || !sWh) { setSErr('Select a product and warehouse.'); return; }
    if (sUseCredit && !sCustomer) { setSErr('Wallet credit needs a customer.'); return; }
    if (!sProduct || !sWh) { setSErr('Select a product and warehouse.'); return; }
    setSBusy(true); setSErr(null);
    const { error } = await supabase.rpc('create_special_sale', {
      p_special_product_id: sProduct, p_warehouse_id: sWh, p_customer_id: sCustomer || null,
      p_quantity: sQty, p_payment_method_id: sMethod || null, p_reference: sRef.trim() || null, p_notes: null,
    });
    if (error) { setSBusy(false); setSErr(error.message); return; }

    // Apply wallet credit to the sale just created. Done as a second step
    // because create_special_sale owns the stock movement and numbering.
    if (sUseCredit && Number(sCreditAmt) > 0) {
      const { data: latest } = await supabase.from('special_sales')
        .select('id').eq('customer_id', sCustomer).order('created_at', { ascending: false }).limit(1);
      const saleId = (latest as any[])?.[0]?.id;
      if (saleId) {
        const { error: cErr } = await supabase.rpc('pay_special_with_credit', {
          p_doc_kind: 'special_sale', p_doc_id: saleId, p_customer_id: sCustomer,
          p_amount: Number(sCreditAmt), p_store_id: brandStores[0]?.id ?? null,
        });
        if (cErr) {
          setSBusy(false);
          setSErr(`The sale was created, but the wallet payment failed: ${cErr.message}`);
          load(); return;
        }
      }
    }
    setSBusy(false);
    setSaleOpen(false); setSUseCredit(false); setSCreditAmt('');
    load();
  };
  const cancelSale = async (s: SpecialSale) => {
    const back = confirm(`Cancel sale ${s.sale_no}?\n\nOK = return stock to warehouse · Cancel = keep stock out`);
    if (!confirm(`Confirm cancelling ${s.sale_no} (stock ${back ? 'WILL' : 'will NOT'} return)?`)) return;
    const { error } = await supabase.rpc('cancel_special_sale', { p_sale_id: s.id, p_return_stock: back, p_note: null });
    if (error) alert(error.message); else load();
  };

  // ── New rental modal ──
  const [rentOpen, setRentOpen] = useState(false);
  const [rProduct, setRProduct] = useState(''); const [rWh, setRWh] = useState('');
  const [rCustomer, setRCustomer] = useState(''); const [rQty, setRQty] = useState(1);
  const [rRate, setRRate] = useState<SpecialRateType>('day'); const [rPeriods, setRPeriods] = useState(1);
  const [rStart, setRStart] = useState(todayStr());
  const [rBusy, setRBusy] = useState(false); const [rErr, setRErr] = useState<string | null>(null);
  const rExpected = useMemo(() => addPeriods(rStart, rRate, rPeriods || 1), [rStart, rRate, rPeriods]);
  const rProductObj = rows.find(x => x.id === rProduct);
  const rRateAmount = rProductObj ? (rRate === 'day' ? rProductObj.rate_day : rRate === 'week' ? rProductObj.rate_week : rRate === 'month' ? rProductObj.rate_month : rProductObj.rate_year) : 0;
  const openRent = () => { setRProduct(''); setRWh(warehouses[0]?.id ?? ''); setRCustomer(''); setRQty(1); setRRate('day'); setRPeriods(1); setRStart(todayStr()); setRErr(null); setRentOpen(true); };
  const submitRent = async () => {
    if (!rProduct || !rWh || !rCustomer) { setRErr('Select a product, warehouse, and customer.'); return; }
    setRBusy(true); setRErr(null);
    const { error } = await supabase.rpc('create_rental', {
      p_special_product_id: rProduct, p_warehouse_id: rWh, p_customer_id: rCustomer,
      p_quantity: rQty, p_rate_type: rRate, p_periods: rPeriods,
      p_start_date: rStart, p_expected_return_date: rExpected, p_notes: null,
    });
    setRBusy(false);
    if (error) { setRErr(error.message); return; }
    setRentOpen(false); load();
  };

  // ── Pay rental modal ──
  const [payFor, setPayFor] = useState<Rental | null>(null);
  const [payMethod, setPayMethod] = useState(''); const [payRef, setPayRef] = useState('');
  const [payBusy, setPayBusy] = useState(false); const [payErr, setPayErr] = useState<string | null>(null);
  // Phase 30: a rental fee may be met from wallet credit that permits Rentals.
  const [payUseCredit, setPayUseCredit] = useState(false);
  const [payCreditAmt, setPayCreditAmt] = useState('');
  const [payWallet, setPayWallet] = useState<any>(null);
  useEffect(() => {
    if (!payFor?.customer_id) { setPayWallet(null); return; }
    supabase.rpc('customer_credit_balances', { p_customer_id: payFor.customer_id })
      .then(({ data }) => setPayWallet(data ?? null));
    setPayUseCredit(false); setPayCreditAmt('');
  }, [payFor?.customer_id]);

  const submitPay = async () => {
    if (!payFor) return;
    setPayBusy(true); setPayErr(null);

    // Credit first, so the remainder settles against the chosen method.
    if (payUseCredit && Number(payCreditAmt) > 0) {
      const { error: cErr } = await supabase.rpc('pay_special_with_credit', {
        p_doc_kind: 'rental', p_doc_id: payFor.id, p_customer_id: payFor.customer_id,
        p_amount: Number(payCreditAmt), p_store_id: brandStores[0]?.id ?? null,
      });
      if (cErr) { setPayBusy(false); setPayErr(cErr.message); return; }
    }

    const { error } = await supabase.rpc('pay_rental', { p_rental_id: payFor.id, p_payment_method_id: payMethod || null, p_reference: payRef.trim() || null });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    setPayFor(null); setPayUseCredit(false); setPayCreditAmt(''); load();
  };
  const doActivate = async (r: Rental) => {
    const { error } = await supabase.rpc('activate_rental', { p_rental_id: r.id });
    if (error) alert(error.message); else load();
  };
  const doCancelRental = async (r: Rental) => {
    const needsStock = r.status === 'paid' || r.status === 'active';
    const back = needsStock ? confirm(`Cancel ${r.rental_no}?\n\nOK = return stock to warehouse · Cancel = keep stock out`) : false;
    if (!confirm(`Confirm cancelling ${r.rental_no}?`)) return;
    const { error } = await supabase.rpc('cancel_rental', { p_rental_id: r.id, p_return_stock: back, p_note: null });
    if (error) alert(error.message); else load();
  };

  // ── Return rental modal ──
  const [retFor, setRetFor] = useState<Rental | null>(null);
  const [retCondition, setRetCondition] = useState<ReturnCondition>('good');
  const [retStock, setRetStock] = useState(true);
  const [retMethod, setRetMethod] = useState(''); const [retRef, setRetRef] = useState('');
  const [retBusy, setRetBusy] = useState(false); const [retErr, setRetErr] = useState<string | null>(null);
  const openReturn = (r: Rental) => {
    setRetFor(r); setRetCondition('good'); setRetStock(true);
    setRetMethod(methods[0]?.id ?? ''); setRetRef(''); setRetErr(null);
  };
  const submitReturn = async () => {
    if (!retFor) return;
    const late = latePreview(retFor);
    setRetBusy(true); setRetErr(null);
    const { error } = await supabase.rpc('return_rental', {
      p_rental_id: retFor.id, p_condition: retCondition, p_return_stock: retStock,
      p_late_payment_method_id: late.total > 0 ? (retMethod || null) : null,
      p_late_reference: late.total > 0 ? (retRef.trim() || null) : null, p_note: null,
    });
    setRetBusy(false);
    if (error) { setRetErr(error.message); return; }
    setRetFor(null); load();
  };

  const RentalBadge: React.FC<{ r: Rental }> = ({ r }) => {
    const s: RentalStatus = isOverdue(r) ? 'overdue' : r.status;
    const cls = s === 'returned' ? 'badge-success' : s === 'paid' ? 'badge-primary' : s === 'active' ? 'badge-accent'
      : s === 'overdue' ? 'badge-danger' : s === 'cancelled' ? 'badge-muted' : 'badge-muted';
    return <span className={`badge ${cls}`}>{RENTAL_STATUS_LABELS[s]}</span>;
  };


  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage special products and rentals." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Special Products & Rentals</h2><p>Warehouse-only special products — sold directly or rented (fee upfront, late fee at return). No commission applies.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={tab === 'sales' ? sales : tab === 'rentals' ? rentals : rows}
            filename={`special-${tab}`} sheetName="Special"
            dateOf={tab === 'catalog' ? undefined : ((r: any) => r.created_at)}
            dateLabel={tab === 'rentals' ? 'Rental date' : 'Sale date'}
            columns={tab === 'sales' ? [
              { header: 'Sale No', value: (x: any) => x.sale_no },
              { header: 'Date', value: (x: any) => new Date(x.created_at).toLocaleDateString('en-GB') },
              { header: 'Product', value: (x: any) => rows.find(p => p.id === x.special_product_id)?.name ?? '' },
              { header: 'Customer', value: (x: any) => customers.find(c => c.id === x.customer_id)?.full_name ?? '' },
              { header: 'Qty', value: (x: any) => Number(x.quantity ?? 0) },
              { header: 'Total', value: (x: any) => Number(x.total_amount ?? 0) },
              { header: 'Status', value: (x: any) => x.status },
            ] : tab === 'rentals' ? [
              { header: 'Rental No', value: (x: any) => x.rental_no },
              { header: 'Date', value: (x: any) => new Date(x.created_at).toLocaleDateString('en-GB') },
              { header: 'Product', value: (x: any) => rows.find(p => p.id === x.special_product_id)?.name ?? '' },
              { header: 'Customer', value: (x: any) => customers.find(c => c.id === x.customer_id)?.full_name ?? '' },
              { header: 'Period', value: (x: any) => `${x.periods} x ${x.rate_type}` },
              { header: 'Fee', value: (x: any) => Number(x.rental_fee ?? 0) },
              { header: 'Late fee', value: (x: any) => Number(x.late_fee_total ?? 0) },
              { header: 'Due back', value: (x: any) => x.expected_return_date ? new Date(x.expected_return_date).toLocaleDateString('en-GB') : '' },
              { header: 'Status', value: (x: any) => x.status },
            ] : [
              { header: 'Product', value: (p: any) => p.name },
              { header: 'SKU', value: (p: any) => p.sku ?? '' },
              { header: 'Sale price', value: (p: any) => Number(p.sale_price ?? 0) },
              { header: 'Day rate', value: (p: any) => Number(p.rate_day ?? 0) },
              { header: 'Late fee/day', value: (p: any) => Number(p.late_fee_per_day ?? 0) },
            ]} /><button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button></div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
        <button className={`btn btn-sm ${tab === 'catalog' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('catalog')}><KeyRound size={14} /> Catalog</button>
        <button className={`btn btn-sm ${tab === 'sales' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('sales')}><ShoppingBag size={14} /> Sales</button>
        <button className={`btn btn-sm ${tab === 'rentals' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('rentals')}><CalendarClock size={14} /> Rentals</button>
      {/* ---- Waiting for a warehouse: a button, with the detail in a dialog ---- */}
      {/* Always shown, so its colour carries the state: white when there is
          nothing to do, amber when something is waiting. */}
      <button className="btn" style={{
          marginBottom: 16,
          background: awaiting.length > 0 ? 'var(--warning-light)' : 'var(--surface)',
          borderColor: awaiting.length > 0 ? '#fde68a' : 'var(--border)',
          color: awaiting.length > 0 ? '#92400e' : 'var(--text-muted)',
          fontWeight: awaiting.length > 0 ? 700 : 500,
          cursor: awaiting.length > 0 ? 'pointer' : 'default',
        }}
        disabled={awaiting.length === 0}
        onClick={() => awaiting.length > 0 && setQueueOpen(true)}>
        <Clock size={14} />
        {awaiting.length > 0 ? 'Waiting for a warehouse' : 'Nothing waiting for a warehouse'}
        {awaiting.length > 0 && (
          <span style={{
            marginLeft: 8, padding: '1px 8px', borderRadius: 999, fontSize: 11.5,
            fontWeight: 700, background: 'var(--warning)', color: '#fff',
          }}>{awaiting.length}</span>
        )}
      </button>


        <div style={{ flex: 1 }} />
        {tab === 'catalog' && <button className="btn btn-primary btn-sm" onClick={openAdd}><Plus size={14} /> Add Special Product</button>}
        {(tab === 'sales' || tab === 'rentals') && (
          <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
            Sales and rentals are now raised on the <strong>Invoices</strong> page, so the customer
            gets one invoice and one receipt. They appear here once paid, waiting for a warehouse.
          </span>
        )}
      </div>

      <div className="card"><div className="table-wrap">
        {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
        : tab === 'catalog' ? (
          rows.length === 0 ? <div className="empty-state"><KeyRound size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No special products yet</p></div>
          : <table>
              <thead><tr><th>Name</th><th>SKU</th><th style={{ textAlign: 'right' }}>Sale</th><th style={{ textAlign: 'right' }}>Day</th><th style={{ textAlign: 'right' }}>Week</th><th style={{ textAlign: 'right' }}>Month</th><th style={{ textAlign: 'right' }}>Year</th><th style={{ textAlign: 'right' }}>Late/day</th><th style={{ textAlign: 'right' }}>Stock</th><th></th></tr></thead>
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
                  <td style={{ textAlign: 'right' }}>{stockOf(p.id).reduce((s, x) => s + x.current_qty, 0)}</td>
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
                  <td>{s.status === 'paid' ? <span className="badge badge-success">Paid</span> : <span className="badge badge-muted">Cancelled{s.stock_returned ? ' · stock back' : ''}</span>}</td>
                  <td><div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => printReceipt('sale', s)} title="Print this sale"><Printer size={13} /> Print</button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('whatsapp', 'sale', s)}
                      disabled={!whatsappNumber(customers.find((c: any) => c.id === s.customer_id)?.phone)}
                      title="Send by WhatsApp"><MessageCircle size={13} /></button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('email', 'sale', s)}
                      disabled={!emailAddress(customers.find((c: any) => c.id === s.customer_id)?.email)}
                      title="Send by email"><Mail size={13} /></button>
                    {s.status === 'paid' && <button className="btn btn-danger btn-sm" onClick={() => cancelSale(s)}>Cancel</button>}
                  </div></td>
                </tr>))}
              </tbody>
            </table>
        ) : (
          rentals.length === 0 ? <div className="empty-state"><CalendarClock size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No rentals yet</p></div>
          : <table>
              <thead><tr><th>Rental</th><th>Product</th><th>Customer</th><th style={{ textAlign: 'right' }}>Qty</th><th>Period</th><th style={{ textAlign: 'right' }}>Fee</th><th>Due back</th><th>Status</th><th></th></tr></thead>
              <tbody>{rentals.map(r => {
                const late = latePreview(r);
                return (
                <tr key={r.id}>
                  <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.rental_no}</td>
                  <td><strong>{spName(r.special_product_id)}</strong><div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{whName(r.warehouse_id)}</div></td>
                  <td style={{ fontSize: 12.5 }}>{cuName(r.customer_id)}</td>
                  <td style={{ textAlign: 'right' }}>{r.quantity}</td>
                  <td style={{ fontSize: 12 }}>{r.periods} × {RATE_TYPE_LABELS[r.rate_type].replace('Per ', '').toLowerCase()}{r.periods > 1 ? 's' : ''}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{new Date(r.start_date).toLocaleDateString()} →</div></td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.rental_fee))}{r.late_fee_total > 0 && <div style={{ fontSize: 11, color: 'var(--danger)' }}>+{money(Number(r.late_fee_total))} late</div>}</td>
                  <td style={{ fontSize: 12 }}>{new Date(r.expected_return_date).toLocaleDateString()}{isOverdue(r) && late.days > 0 && <div style={{ fontSize: 11, color: 'var(--danger)' }}>{late.days}d late · {money(late.total)}</div>}</td>
                  <td><RentalBadge r={r} />{r.return_condition && <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>{r.return_condition}{r.stock_returned === false ? ' · not restocked' : r.stock_returned ? ' · restocked' : ''}</div>}</td>
                  <td><div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                    {r.status === 'draft' && <>
                      <button className="btn btn-primary btn-sm" onClick={() => { setPayFor(r); setPayMethod(methods[0]?.id ?? ''); setPayRef(''); setPayErr(null); }}>Pay</button>
                      <button className="btn btn-secondary btn-sm" onClick={() => doCancelRental(r)}>Cancel</button>
                    </>}
                    {r.status === 'paid' && <>
                      <button className="btn btn-primary btn-sm" onClick={() => doActivate(r)}>Activate</button>
                      <button className="btn btn-secondary btn-sm" onClick={() => openReturn(r)}>Return</button>
                      <button className="btn btn-danger btn-sm" onClick={() => doCancelRental(r)}>Cancel</button>
                    </>}
                    {r.status === 'active' && <button className="btn btn-primary btn-sm" onClick={() => openReturn(r)}>Return</button>}
                    <button className="btn btn-secondary btn-sm" onClick={() => printReceipt('rental', r)} title="Print this rental"><Printer size={13} /> Print</button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('whatsapp', 'rental', r)}
                      disabled={!whatsappNumber(customers.find((c: any) => c.id === r.customer_id)?.phone)}
                      title="Send by WhatsApp"><MessageCircle size={13} /></button>
                    <button className="btn btn-secondary btn-sm" onClick={() => sendReceiptPdf('email', 'rental', r)}
                      disabled={!emailAddress(customers.find((c: any) => c.id === r.customer_id)?.email)}
                      title="Send by email"><Mail size={13} /></button>
                  </div></td>
                </tr>);
              })}
              </tbody>
            </table>
        )}
      </div></div>

      {/* Catalog add/edit */}
      {queueOpen && (
        <Modal title="Waiting for a warehouse" wide onClose={() => setQueueOpen(false)}
          footer={<button className="btn btn-secondary" onClick={() => setQueueOpen(false)}>Close</button>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            {rentNote && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ</span><div>{rentNote}</div></div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              These are paid for and no stock has moved. Choosing a warehouse is what takes the
              goods out of it.
            </div>
            {awaiting.length === 0 ? (
              <div style={{ textAlign: 'center', padding: 24, color: 'var(--text-muted)' }}>
                Nothing is waiting — everything paid for has been released.
              </div>
            ) : (
              <div>
                <div style={{
                  display: 'grid',
                  gridTemplateColumns: 'minmax(260px, 2fr) minmax(280px, 1.4fr) auto',
                  gap: 20, fontSize: 11, fontWeight: 700, letterSpacing: '0.04em',
                  textTransform: 'uppercase', color: 'var(--text-muted)', paddingBottom: 6,
                }}>
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
              <div key={row.doc_id} style={{
                display: 'grid',
                gridTemplateColumns: 'minmax(260px, 2fr) minmax(280px, 1.4fr) auto',
                gap: 20, alignItems: 'center',
                padding: '14px 0', borderTop: '1px solid var(--border)',
              }}>
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
                      {opts.map((o: any) => (
                        <option key={o.warehouse_id} value={o.warehouse_id}
                          disabled={o.available < row.quantity}>
                          {o.warehouse_name} — {o.available} free
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
          footer={<><button className="btn btn-secondary" onClick={() => setEditRental(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveRental} disabled={rentBusy}>
              {rentBusy ? 'Saving…' : 'Save terms'}</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              {editRental.product_name} · {editRental.customer_name ?? '—'}
              {editRental.invoice_no ? ` · ${editRental.invoice_no}` : ''}
            </div>
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}><label>Quantity</label>
                <input type="number" min={1} max={999} value={rentForm.quantity}
                  onChange={e => setRentForm((f: any) => ({ ...f, quantity: Math.max(1, Math.floor(+e.target.value || 1)) }))} /></div>
              <div className="form-group" style={{ marginBottom: 0 }}><label>Rate</label>
                <select value={rentForm.rate_type}
                  onChange={e => setRentForm((f: any) => ({ ...f, rate_type: e.target.value }))}>
                  {(['day','week','month','year'] as const)
                    .filter(rt => Number(rows.find((p: any) => p.id === editRental.special_product_id)?.[`rate_${rt}`] ?? 0) > 0)
                    .map(rt => <option key={rt} value={rt}>Per {rt}</option>)}
                </select></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}><label>Periods</label>
                <input type="number" min={1} max={3650} value={rentForm.periods}
                  onChange={e => setRentForm((f: any) => ({ ...f, periods: Math.max(1, Math.floor(+e.target.value || 1)) }))} /></div>
              <div className="form-group" style={{ marginBottom: 0 }}><label>Starts</label>
                <input type="date" value={rentForm.start_date}
                  onChange={e => setRentForm((f: any) => ({ ...f, start_date: e.target.value }))} /></div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Due back</label>
              <input type="date" value={rentForm.expected_return_date} min={rentForm.start_date}
                onChange={e => setRentForm((f: any) => ({ ...f, expected_return_date: e.target.value }))} /></div>
            <div className="alert alert-warning" style={{ marginBottom: 0 }}>
              <span>⚠</span>
              <div>
                This invoice has already been paid at <strong>{money(Number(editRental.rental_fee ?? 0))}</strong>.
                Changing the quantity, rate or periods changes the fee — you will be told the
                difference so it can be collected or refunded on the invoice.
              </div>
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
            <div className="form-group"><label>Description</label><textarea rows={2} value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="Optional" /></div>
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

      {/* New sale */}
      {saleOpen && (
        <Modal title="New Special Sale" wide onClose={() => setSaleOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setSaleOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={submitSale} disabled={sBusy}>{sBusy ? 'Selling…' : 'Complete Sale'}</button></>}>
          <div className="form-grid">
            {sErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{sErr}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Special Product *</label>
                <select value={sProduct} onChange={e => setSProduct(e.target.value)}>
                  <option value="">— Select —</option>
                  {rows.filter(p => p.is_active).map(p => <option key={p.id} value={p.id}>{p.name} — {money(p.sale_price)}</option>)}
                </select>
              </div>
              <div className="form-group"><label>Warehouse *</label>
                <select value={sWh} onChange={e => setSWh(e.target.value)}>{warehouses.map(w => <option key={w.id} value={w.id}>{w.name}{sProduct ? ` (${stockOf(sProduct, w.id)[0]?.current_qty ?? 0} in stock)` : ''}</option>)}</select>
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Customer</label>
                <CustomerSearchSelect value={sCustomer} onChange={setSCustomer}
                  placeholder="Search name, phone or email — or leave blank for walk-in" />
              </div>
              <div className="form-group"><label>Quantity</label><input type="number" min={1} value={sQty || ''} onChange={e => setSQty(+e.target.value)} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Payment Method</label>
                <select value={sMethod} onChange={e => setSMethod(e.target.value)}>{methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
              </div>
              <div className="form-group"><label>Reference</label><input value={sRef} onChange={e => setSRef(e.target.value)} placeholder="Optional" /></div>
            </div>

            {/* Wallet credit — only offered where the customer actually has some. */}
            {sCustomer && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                  <input type="checkbox" style={{ width: 'auto' }} checked={sUseCredit}
                    onChange={e => {
                      setSUseCredit(e.target.checked);
                      if (e.target.checked && !sCreditAmt) {
                        const total = (rows.find(p => p.id === sProduct)?.sale_price ?? 0) * sQty;
                        const avail = Number(sWallet?.available_total ?? 0);
                        setSCreditAmt(String(Math.min(total, avail).toFixed(2)));
                      }
                    }} />
                  Pay with wallet credit
                </label>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>
                  Wallet balance: <strong>{money(Number(sWallet?.available_total ?? 0))}</strong>.
                  Only credit permitted for <strong>Special Products</strong> can be used, and
                  Bonus Credit is spent first.
                </div>
                {sUseCredit && (
                  <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end', marginTop: 6 }}>
                    <div style={{ flex: '0 0 160px' }}>
                      <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Credit to apply (S$)</div>
                      <input type="number" min={0} step={0.01} value={sCreditAmt}
                        onChange={e => setSCreditAmt(e.target.value)} />
                    </div>
                    <div style={{ fontSize: 12.5, paddingBottom: 6 }}>
                      Remaining to pay by {methods.find(m => m.id === sMethod)?.name ?? 'the chosen method'}:{' '}
                      <strong>{money(Math.max(
                        (rows.find(p => p.id === sProduct)?.sale_price ?? 0) * sQty - Number(sCreditAmt || 0), 0))}</strong>
                    </div>
                  </div>
                )}
              </div>
            )}

            {sProduct && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Total: <strong>{money((rows.find(p => p.id === sProduct)?.sale_price ?? 0) * sQty)}</strong> — paid now; warehouse stock deducts immediately. Credit-funded value earns no commission; externally paid value still qualifies for Legacy Therapy.</div></div>}
          </div>
        </Modal>
      )}

      {/* New rental */}
      {rentOpen && (
        <Modal title="New Rental" wide onClose={() => setRentOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setRentOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={submitRent} disabled={rBusy}>{rBusy ? 'Creating…' : 'Create Rental (Draft)'}</button></>}>
          <div className="form-grid">
            {rErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{rErr}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Special Product *</label>
                <select value={rProduct} onChange={e => setRProduct(e.target.value)}>
                  <option value="">— Select —</option>
                  {rows.filter(p => p.is_active).map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </div>
              <div className="form-group"><label>Warehouse *</label>
                <select value={rWh} onChange={e => setRWh(e.target.value)}>{warehouses.map(w => <option key={w.id} value={w.id}>{w.name}{rProduct ? ` (${stockOf(rProduct, w.id)[0]?.current_qty ?? 0} in stock)` : ''}</option>)}</select>
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Customer *</label>
                <CustomerSearchSelect value={rCustomer} onChange={setRCustomer}
                  placeholder="Search name, phone or email…" />
              </div>
              <div className="form-group"><label>Quantity</label><input type="number" min={1} value={rQty || ''} onChange={e => setRQty(+e.target.value)} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Rate</label>
                <select value={rRate} onChange={e => setRRate(e.target.value as SpecialRateType)}>
                  {(['day','week','month','year'] as SpecialRateType[]).map(t => {
                    const amt = rProductObj ? (t === 'day' ? rProductObj.rate_day : t === 'week' ? rProductObj.rate_week : t === 'month' ? rProductObj.rate_month : rProductObj.rate_year) : 0;
                    return <option key={t} value={t} disabled={!!rProductObj && amt <= 0}>{RATE_TYPE_LABELS[t]}{rProductObj ? ` — ${money(amt)}` : ''}</option>;
                  })}
                </select>
              </div>
              <div className="form-group"><label>Duration ({rRate}s)</label><input type="number" min={1} value={rPeriods || ''} onChange={e => setRPeriods(+e.target.value)} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Start Date</label><input type="date" value={rStart} onChange={e => setRStart(e.target.value)} /></div>
              <div className="form-group"><label>Expected Return</label><input type="date" value={rExpected} readOnly style={{ background: 'var(--surface-2)' }} /></div>
            </div>
            {rProduct && rRateAmount > 0 && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>
                Rental fee: <strong>{money(rRateAmount * rPeriods * rQty)}</strong> ({money(rRateAmount)} × {rPeriods} × {rQty}) — collected on Pay; stock deducts then.
                Late fee after {new Date(rExpected).toLocaleDateString()}: <strong>{money((rProductObj?.late_fee_per_day ?? 0) * rQty)}/day</strong>.
              </div></div>
            )}
          </div>
        </Modal>
      )}

      {/* Pay rental */}
      {payFor && (
        <Modal title={`Pay Rental — ${payFor.rental_no}`} maxWidth={420} onClose={() => setPayFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPayFor(null)}>Cancel</button><button className="btn btn-primary" onClick={submitPay} disabled={payBusy}>{payBusy ? 'Processing…' : `Collect ${money(Number(payFor.rental_fee))}`}</button></>}>
          <div className="form-grid">
            {payErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{payErr}</div></div>}
            <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', fontSize: 13 }}>
              <strong>{spName(payFor.special_product_id)}</strong> × {payFor.quantity} · {payFor.periods} {payFor.rate_type}{payFor.periods > 1 ? 's' : ''}<br />
              Fee: <strong>{money(Number(payFor.rental_fee))}</strong> — stock deducts on payment.
            </div>
            <div className="form-group"><label>Payment Method</label>
              <select value={payMethod} onChange={e => setPayMethod(e.target.value)}>{methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
            </div>
            <div className="form-group"><label>Reference</label><input value={payRef} onChange={e => setPayRef(e.target.value)} placeholder="Optional" /></div>

            {payFor.customer_id && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                  <input type="checkbox" style={{ width: 'auto' }} checked={payUseCredit}
                    onChange={e => {
                      setPayUseCredit(e.target.checked);
                      if (e.target.checked && !payCreditAmt) {
                        setPayCreditAmt(String(Math.min(
                          Number(payFor.rental_fee), Number(payWallet?.available_total ?? 0)).toFixed(2)));
                      }
                    }} />
                  Pay with wallet credit
                </label>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>
                  Wallet balance: <strong>{money(Number(payWallet?.available_total ?? 0))}</strong>.
                  Only credit permitted for <strong>Rentals</strong> can be used, Bonus Credit first.
                  Rental value never counts toward Legacy Therapy, however it is paid.
                </div>
                {payUseCredit && (
                  <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end', marginTop: 6 }}>
                    <div style={{ flex: '0 0 160px' }}>
                      <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Credit to apply (S$)</div>
                      <input type="number" min={0} step={0.01} value={payCreditAmt}
                        onChange={e => setPayCreditAmt(e.target.value)} />
                    </div>
                    <div style={{ fontSize: 12.5, paddingBottom: 6 }}>
                      Remaining: <strong>{money(Math.max(Number(payFor.rental_fee) - Number(payCreditAmt || 0), 0))}</strong>
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        </Modal>
      )}

      {/* Return rental */}
      {retFor && (() => { const late = latePreview(retFor); return (
        <Modal title={`Return — ${retFor.rental_no}`} maxWidth={460} onClose={() => setRetFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setRetFor(null)}>Cancel</button><button className="btn btn-primary" onClick={submitReturn} disabled={retBusy}>{retBusy ? 'Processing…' : 'Confirm Return'}</button></>}>
          <div className="form-grid">
            {retErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{retErr}</div></div>}
            <div className="form-group"><label>Condition</label>
              <select value={retCondition} onChange={e => setRetCondition(e.target.value as ReturnCondition)}>
                <option value="good">Good</option><option value="damaged">Damaged</option><option value="lost">Lost</option>
              </select>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', padding: '10px 12px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
              <input type="checkbox" checked={retStock} onChange={e => setRetStock(e.target.checked)} style={{ width: 'auto' }} />
              <div><div style={{ fontSize: 13, fontWeight: 600 }}>Return {retFor.quantity} to warehouse stock</div>
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Untick for lost or unusable items.</div></div>
            </label>
            {late.total > 0 ? (
              <>
                <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div><strong>{late.days} day{late.days > 1 ? 's' : ''} late</strong> — late fee {money(retFor.late_fee_per_day)} × {late.days} × {retFor.quantity} = <strong>{money(late.total)}</strong>, collected now.</div></div>
                <div className="form-grid-2">
                  <div className="form-group"><label>Late Fee Payment Method *</label>
                    <select value={retMethod} onChange={e => setRetMethod(e.target.value)}>{methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
                  </div>
                  <div className="form-group"><label>Reference</label><input value={retRef} onChange={e => setRetRef(e.target.value)} placeholder="Optional" /></div>
                </div>
              </>
            ) : <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Returned on time — no late fee.</div></div>}
          </div>
        </Modal>
      ); })()}
    </div>
  );
};

export default SpecialPage;
