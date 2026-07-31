import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { printA5Document, esc as pesc, money as pmoney, PrintLine, PrintTotal } from '../lib/printDoc';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  SpecialProduct, SpecialProductStock, SpecialSale, Rental, Warehouse, Customer, PaymentMethod,
  SpecialRateType, RentalStatus, ReturnCondition, RATE_TYPE_LABELS, RENTAL_STATUS_LABELS, isOwnerOrManager,
} from '../types';
import { Modal, NoAccess } from '../components/ui';
import { exportCsv } from '../lib/csv';
import { Plus, Pencil, Trash2, RefreshCw, Boxes, KeyRound, ShoppingBag, CalendarClock, X, Download, Printer} from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;
// Local (Singapore) date — never via toISOString, which shifts to UTC.
const todayStr = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

const blank = (p?: SpecialProduct) => ({
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
  const [loading, setLoading] = useState(true);


  const load = useCallback(async () => {
    setLoading(true);
    const [sp, st, sa, re, wh, cu, pm, sto] = await Promise.all([
      supabase.from('special_products').select('*').is('deleted_at', null).order('name'),
      supabase.from('special_product_stock').select('*'),
      supabase.from('special_sales').select('*').order('created_at', { ascending: false }),
      supabase.from('rentals').select('*').order('created_at', { ascending: false }),
      supabase.from('warehouses').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('id,full_name,phone').is('deleted_at', null).order('full_name'),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setRows((sp.data as SpecialProduct[]) ?? []);
    setStock((st.data as SpecialProductStock[]) ?? []);
    setSales((sa.data as SpecialSale[]) ?? []);
    setRentals((re.data as Rental[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    setBrandStores((sto.data as any[]) ?? []);
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

    printA5Document({
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
  const [err, setErr] = useState<string | null>(null);

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (p: SpecialProduct) => { setForm(blank(p)); setEditId(p.id); setErr(null); setModalOpen(true); };
  const handleSave = async () => {
    if (!form.name.trim()) { setErr('Name is required.'); return; }
    if (!form.sku.trim()) { setErr('SKU is required.'); return; }
    setSaving(true); setErr(null);
    const payload = { ...form, name: form.name.trim(), sku: form.sku.trim(), description: form.description.trim() || null };
    const res = editId
      ? await supabase.from('special_products').update(payload).eq('id', editId)
      : await supabase.from('special_products').insert(payload);
    setSaving(false);
    if (res.error) { setErr(res.error.message); return; }
    setModalOpen(false); load();
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
  const submitSale = async () => {
    if (!sProduct || !sWh) { setSErr('Select a product and warehouse.'); return; }
    setSBusy(true); setSErr(null);
    const { error } = await supabase.rpc('create_special_sale', {
      p_special_product_id: sProduct, p_warehouse_id: sWh, p_customer_id: sCustomer || null,
      p_quantity: sQty, p_payment_method_id: sMethod || null, p_reference: sRef.trim() || null, p_notes: null,
    });
    setSBusy(false);
    if (error) { setSErr(error.message); return; }
    setSaleOpen(false); load();
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
  const submitPay = async () => {
    if (!payFor) return;
    setPayBusy(true); setPayErr(null);
    const { error } = await supabase.rpc('pay_rental', { p_rental_id: payFor.id, p_payment_method_id: payMethod || null, p_reference: payRef.trim() || null });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    setPayFor(null); load();
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

  const doExport = () => {
    if (tab === 'sales') exportCsv('special-sales.csv', sales.map(x => ({
      sale_no: x.sale_no, date: new Date(x.created_at).toLocaleDateString(), product: spName(x.special_product_id),
      warehouse: whName(x.warehouse_id), customer: cuName(x.customer_id), qty: x.quantity,
      total: Number(x.total_amount).toFixed(2), method: pmName(x.payment_method_id), status: x.status,
    })));
    else if (tab === 'rentals') exportCsv('rentals.csv', rentals.map(x => ({
      rental_no: x.rental_no, product: spName(x.special_product_id), customer: cuName(x.customer_id),
      qty: x.quantity, rate: `${x.periods} x ${x.rate_type}`, fee: Number(x.rental_fee).toFixed(2),
      start: x.start_date, expected_return: x.expected_return_date,
      status: isOverdue(x) ? 'overdue' : x.status, condition: x.return_condition ?? '',
      late_days: x.late_days, late_fee: Number(x.late_fee_total).toFixed(2),
    })));
    else exportCsv('special-products.csv', rows.map(p => ({
      name: p.name, sku: p.sku, sale_price: Number(p.sale_price).toFixed(2),
      rate_day: Number(p.rate_day).toFixed(2), rate_week: Number(p.rate_week).toFixed(2),
      rate_month: Number(p.rate_month).toFixed(2), rate_year: Number(p.rate_year).toFixed(2),
      late_fee_per_day: Number(p.late_fee_per_day).toFixed(2),
      stock: stockOf(p.id).reduce((t, x) => t + x.current_qty, 0), active: p.is_active ? 'yes' : 'no',
    })));
  };

  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage special products and rentals." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Special Products & Rentals</h2><p>Warehouse-only special products — sold directly or rented (fee upfront, late fee at return). No commission applies.</p></div>
        <div style={{ display: 'flex', gap: 10 }}><button className="btn btn-secondary" onClick={doExport}><Download size={15} /> Export CSV</button><button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button></div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
        <button className={`btn btn-sm ${tab === 'catalog' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('catalog')}><KeyRound size={14} /> Catalog</button>
        <button className={`btn btn-sm ${tab === 'sales' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('sales')}><ShoppingBag size={14} /> Sales</button>
        <button className={`btn btn-sm ${tab === 'rentals' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('rentals')}><CalendarClock size={14} /> Rentals</button>
        <div style={{ flex: 1 }} />
        {tab === 'catalog' && <button className="btn btn-primary btn-sm" onClick={openAdd}><Plus size={14} /> Add Special Product</button>}
        {tab === 'sales' && <button className="btn btn-primary btn-sm" onClick={openSale}><Plus size={14} /> New Sale</button>}
        {tab === 'rentals' && <button className="btn btn-primary btn-sm" onClick={openRent}><Plus size={14} /> New Rental</button>}
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
                  </div></td>
                </tr>);
              })}
              </tbody>
            </table>
        )}
      </div></div>

      {/* Catalog add/edit */}
      {modalOpen && (
        <Modal title={editId ? 'Edit Special Product' : 'Add Special Product'} maxWidth={520} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus /></div>
              <div className="form-group"><label>SKU *</label><input value={form.sku} onChange={e => setForm(f => ({ ...f, sku: e.target.value }))} /></div>
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
        <Modal title={`Stock — ${stockFor.name}`} maxWidth={420} onClose={() => setStockFor(null)}
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
        <Modal title="New Special Sale" maxWidth={480} onClose={() => setSaleOpen(false)}
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
                <select value={sCustomer} onChange={e => setSCustomer(e.target.value)}>
                  <option value="">— Walk-in —</option>
                  {customers.map(c => <option key={c.id} value={c.id}>{c.full_name}</option>)}
                </select>
              </div>
              <div className="form-group"><label>Quantity</label><input type="number" min={1} value={sQty || ''} onChange={e => setSQty(+e.target.value)} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Payment Method</label>
                <select value={sMethod} onChange={e => setSMethod(e.target.value)}>{methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
              </div>
              <div className="form-group"><label>Reference</label><input value={sRef} onChange={e => setSRef(e.target.value)} placeholder="Optional" /></div>
            </div>
            {sProduct && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Total: <strong>{money((rows.find(p => p.id === sProduct)?.sale_price ?? 0) * sQty)}</strong> — paid now; warehouse stock deducts immediately. No commission on special products.</div></div>}
          </div>
        </Modal>
      )}

      {/* New rental */}
      {rentOpen && (
        <Modal title="New Rental" maxWidth={520} onClose={() => setRentOpen(false)}
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
                <select value={rCustomer} onChange={e => setRCustomer(e.target.value)}>
                  <option value="">— Select —</option>
                  {customers.map(c => <option key={c.id} value={c.id}>{c.full_name}</option>)}
                </select>
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
