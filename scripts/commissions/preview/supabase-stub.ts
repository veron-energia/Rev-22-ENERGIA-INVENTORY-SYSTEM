// A stand-in for src/lib/supabase, used only by the preview harness.
//
// Answers what ReportsPage reads, with fixture data shaped as migration 358
// returns it, so the Sales by Service Staff tab renders its real markup. It
// talks to nothing; the people and invoices are fixtures.

const STAFF = [
  { id: 's-a', full_name: 'Fixture Staff A', role: 'staff', work_phone: null, is_active: true },
  { id: 's-b', full_name: 'Fixture Staff B', role: 'staff', work_phone: null, is_active: true },
  { id: 's-c', full_name: 'Fixture Staff C', role: 'staff', work_phone: null, is_active: true },
];
const today = new Date().toISOString().slice(0, 10);
// #reports-error: the staff report fails; #reports-stale: money recorded after the page loaded.
const mode = window.location.hash.replace('#reports-', '');

// Reports: six receipts, two of them last month, and the staff report that
// splits them (all time). Revenue ties to the cent: 2027.01.
const prev = new Date(); prev.setDate(1); prev.setMonth(prev.getMonth() - 1); prev.setDate(18);
const prevDay = prev.toISOString().slice(0, 10);
const INVOICES = ['i1', 'i2', 'i3', 'i4', 'i5', 'i6'].map((id, n) => ({
  id, invoice_no: `INV-FIX-000${n + 1}`, store_id: 'st', customer_id: 'cu', status: n === 3 || n === 4 ? 'partially_paid' : 'paid',
  total_amount: 0, created_by: 'p-owner', deleted_at: null,
}));
const LEDGER = [
  { invoice_id: 'i1', event_id: 'e1', sales_date: today, amount: 10.00, event_kind: 'receipt' },
  { invoice_id: 'i2', event_id: 'e2', sales_date: today, amount: 10.01, event_kind: 'receipt' },
  { invoice_id: 'i3', event_id: 'e3', sales_date: today, amount: 457.00, event_kind: 'receipt' },
  { invoice_id: 'i6', event_id: 'e6', sales_date: today, amount: 50.00, event_kind: 'receipt' },
  { invoice_id: 'i4', event_id: 'e4', sales_date: prevDay, amount: 1000.00, event_kind: 'receipt' },
  { invoice_id: 'i5', event_id: 'e5', sales_date: prevDay, amount: 500.00, event_kind: 'receipt' },
];
const STAFF_SALES = {
  basis: 'fixture', revenue: 2027.01, backfill_in: 0, backfill_out: 0, staff_total: 2027.01, difference: 0,
  credited_as_creator: 957, wallet_credit_not_counted: 400,
  rows: [
    { staff_id: 'p-mgr', staff_name: 'Fixture Manager', is_active: true, invoices_served: 2, shared_sales: 957.00, credited_as_creator: 957.00, backfilled_in: 0, receipts_on_invoices_served: 957.00 },
    { staff_id: 's-a', staff_name: 'Fixture Staff A', is_active: true, invoices_served: 4, shared_sales: 356.69, credited_as_creator: 0, backfilled_in: 0, receipts_on_invoices_served: 1070.01 },
    { staff_id: 's-b', staff_name: 'Fixture Staff B', is_active: true, invoices_served: 4, shared_sales: 356.67, credited_as_creator: 0, backfilled_in: 0, receipts_on_invoices_served: 1070.01 },
    { staff_id: 's-c', staff_name: 'Fixture Staff C', is_active: false, invoices_served: 4, shared_sales: 356.65, credited_as_creator: 0, backfilled_in: 0, receipts_on_invoices_served: 1070.01 },
  ],
};

const TABLES: Record<string, () => any> = {
  invoices: () => INVOICES,
  profiles: () => STAFF,
};

const query = (table: string) => {
  const result = () => ({ data: TABLES[table]?.() ?? [], error: null });
  const q: any = {
    select: () => q, order: () => q, range: () => q, is: () => q, eq: () => q, gte: () => q, lte: () => q,
    single: () => Promise.resolve(result()),
    maybeSingle: () => Promise.resolve(result()),
    then: (res: any, rej: any) => Promise.resolve(result()).then(res, rej),
  };
  return q;
};

export const supabase = {
  from: (table: string) => query(table),
  rpc: (fn: string) => {
    // What the Reports page reads: chainable like a query.
    const data = fn === 'invoice_sales_ledger' ? LEDGER
      : fn === 'report_sales_by_service_staff'
        ? (mode === 'stale' ? { ...STAFF_SALES, revenue: STAFF_SALES.revenue + 50, staff_total: STAFF_SALES.staff_total + 50 } : STAFF_SALES)
      : fn === 'report_foc_summary' ? {} : [];
    const error = fn === 'report_sales_by_service_staff' && mode === 'error'
      ? { message: 'canceling statement due to statement timeout' } : null;
    const q: any = {
      order: () => q, range: () => q, gte: () => q, lte: () => q, eq: () => q,
      then: (res: any, rej: any) => Promise.resolve({ data: error ? null : data, error }).then(res, rej),
    };
    return q;
  },
};
