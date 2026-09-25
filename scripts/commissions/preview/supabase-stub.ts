// A stand-in for src/lib/supabase, used only by the preview harness.
//
// Answers what StaffCommissionsPage and ReportsPage read, with fixture data
// shaped as migrations 357 and 358 return it, so the part-payment review and
// the Sales by Service Staff tab render their real markup. It talks to nothing;
// the people and invoices are fixtures.

const STAFF = [
  { id: 's-a', full_name: 'Fixture Staff A', role: 'staff', work_phone: null, is_active: true },
  { id: 's-b', full_name: 'Fixture Staff B', role: 'staff', work_phone: null, is_active: true },
  { id: 's-c', full_name: 'Fixture Staff C', role: 'staff', work_phone: null, is_active: true },
];
const today = new Date().toISOString().slice(0, 10);
let switchOn: string | null = null;
// #reports-error: the staff report fails; #reports-stale: money recorded after the page loaded.
const mode = window.location.hash.replace('#reports-', '');
const lastMonth = (() => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 1); d.setDate(18); return d.toISOString().slice(0, 10); })();

// What registering would add: three staff sharing part payments on four
// invoices, and one affiliate — one invoice payable, one recorded as blocked.
const BACKFILL = [
  ...['s-a', 's-b', 's-c'].flatMap((id, i) => [
    { ledger: 'staff', beneficiary_id: id, beneficiary_name: STAFF[i].full_name, invoice_id: 'i1', invoice_no: 'INV-FIX-0001', earned_amount: 30.00, blocked_amount: 0, credit_date: today },
    { ledger: 'staff', beneficiary_id: id, beneficiary_name: STAFF[i].full_name, invoice_id: 'i2', invoice_no: 'INV-FIX-0002', earned_amount: 5.00, blocked_amount: 0, credit_date: today },
    { ledger: 'staff', beneficiary_id: id, beneficiary_name: STAFF[i].full_name, invoice_id: 'i3', invoice_no: 'INV-FIX-0003', earned_amount: 19.63, blocked_amount: 0, credit_date: today },
    { ledger: 'staff', beneficiary_id: id, beneficiary_name: STAFF[i].full_name, invoice_id: 'i4', invoice_no: 'INV-FIX-0004', earned_amount: 22.80, blocked_amount: 0, credit_date: today },
  ]),
  { ledger: 'affiliate', beneficiary_id: 'c-1', beneficiary_name: 'Fixture Referrer', invoice_id: 'i3', invoice_no: 'INV-FIX-0003', earned_amount: 88.34, blocked_amount: 0, credit_date: today },
  { ledger: 'affiliate', beneficiary_id: 'c-2', beneficiary_name: 'Fixture Not Activated', invoice_id: 'i1', invoice_no: 'INV-FIX-0001', earned_amount: 0, blocked_amount: 45.00, credit_date: today },
  // Receipts from last month whose staff-sales credit moves to this month (358).
  ...['s-a', 's-b', 's-c'].map((id, i) => (
    { ledger: 'sales', beneficiary_id: id, beneficiary_name: STAFF[i].full_name, invoice_id: 'i1', invoice_no: 'INV-FIX-0001', earned_amount: [666.67, 666.67, 666.66][i], blocked_amount: 0, credit_date: today })),
  { ledger: 'sales', beneficiary_id: 'p-mgr', beneficiary_name: 'Fixture Manager', invoice_id: 'i2', invoice_no: 'INV-FIX-0002', earned_amount: 500, blocked_amount: 0, credit_date: today },
];

const COMMISSIONS = [
  { id: 'r1', invoice_id: 'i9', staff_id: 's-a', store_id: 'st', invoice_total: 1000, share_ratio: 0.333333, rate: 3, commission_amount: 10, status: 'earned', invoice_paid_date: today, payout_id: null, reversed_at: null, reversal_reason: null, created_at: today, earning_basis: 'settlement' },
  { id: 'r2', invoice_id: 'i9', staff_id: 's-b', store_id: 'st', invoice_total: 1000, share_ratio: 0.333333, rate: 3, commission_amount: 10, status: 'earned', invoice_paid_date: today, payout_id: null, reversed_at: null, reversal_reason: null, created_at: today, earning_basis: 'settlement' },
  // A part-payment share (357): the rebase never touches it.
  { id: 'r4', invoice_id: 'i4', staff_id: 's-a', store_id: 'st', invoice_total: 133.33, share_ratio: 0.333333, rate: 3, commission_amount: 4, status: 'earned', invoice_paid_date: today, payout_id: null, reversed_at: null, reversal_reason: null, created_at: today, earning_basis: 'instalment' },
  // Taken back after it was paid out: a month holding only this has nothing to pay.
  { id: 'r3', invoice_id: 'i8', staff_id: 's-c', store_id: 'st', invoice_total: -200, share_ratio: 0.333333, rate: 3, commission_amount: -6, status: 'earned', invoice_paid_date: lastMonth, payout_id: null, reversed_at: null, reversal_reason: 'Future payout adjustment: payment corrected', created_at: today, earning_basis: 'settlement' },
];

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
  staff_commissions: () => COMMISSIONS,
  staff_commission_payouts: () => [],
  profiles: () => STAFF,
  payment_methods: () => [{ id: 'pm-cash', name: 'Cash', is_active: true }],
  app_settings: () => ({ staff_commission_rate: 3, instalment_commission_from: switchOn }),
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
  rpc: (fn: string, args: any = {}) => {
    if (fn === 'commission_instalment_backfill') {
      // The review is read in pages (.range); Register is awaited directly.
      const paged = (rows: any[]) => {
        const q: any = {
          range: (from: number, to: number) => Promise.resolve({ data: rows.slice(from, to + 1), error: null }),
          then: (res: any, rej: any) => Promise.resolve({ data: rows, error: null }).then(res, rej),
        };
        return q;
      };
      if (switchOn) return paged([]);
      if (!args.p_apply) return paged(BACKFILL);
      const total = BACKFILL.filter(r => r.ledger !== 'sales').reduce((t, r) => t + r.earned_amount, 0);
      const sales = BACKFILL.filter(r => r.ledger === 'sales').reduce((t, r) => t + r.earned_amount, 0);
      if (Math.round(sales * 100) !== Math.round(Number(args.p_expected_sales ?? 0) * 100)) {
        return Promise.resolve({ data: null, error: { message: `The earlier receipts to credit now total ${sales.toFixed(2)}, not the ${args.p_expected_sales} that was reviewed. Run the review again.` } });
      }
      if (Math.round(total * 100) !== Math.round(Number(args.p_expected_total) * 100)) {
        return Promise.resolve({ data: null, error: { message: `The part-payment total is now ${total.toFixed(2)}, not the ${args.p_expected_total} that was reviewed. Run the review again.` } });
      }
      switchOn = args.p_credit_date ?? today;
      return Promise.resolve({ data: BACKFILL, error: null });
    }
    // Everything else the Reports page reads: chainable like a query.
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
