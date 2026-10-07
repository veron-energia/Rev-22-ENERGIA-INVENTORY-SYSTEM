// A stand-in for src/lib/supabase, used only by the stock loans preview. It
// talks to nothing: every store, product, customer and loan here is an
// invented fixture, kept in memory and lost on reload. The RPCs follow 401's
// rules closely enough to press through the screens (stock leaves on lend,
// comes back on return, a short line refuses, a retry of the same form is
// answered once and a changed one refused).
//   ?role=staff|manager|admin|owner|inventory_manager (default owner)
//   ?assigned=st-a   the stores the person is assigned to (default both);
//                    Owner and Admin act at every store regardless
//   ?drop=1          every save is made but its answer is lost (a network
//                    error with no code), to see the form lock and the retry
//   ?slow=st-a       that location's On loan list answers 1.5 s late, to
//                    switch stores while it is on its way
import { sgToday } from '../../../src/lib/stock-loans/stockLoans';

const params = new URLSearchParams(location.search);
const role = params.get('role') ?? 'owner';
const assigned = (params.get('assigned') ?? 'st-a,st-b').split(',');
const dropAnswers = params.get('drop') === '1';
const slowAt = params.get('slow');
const canWarehouse = ['owner', 'manager', 'inventory_manager'].includes(role);
const seesAll = ['owner', 'admin', 'manager'].includes(role);
const storeAccess = (id: string) => ['owner', 'admin'].includes(role) || assigned.includes(id);
const today = sgToday();
const addDays = (n: number) => {
  const d = new Date(`${today}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};

const STORES = [
  { id: 'st-a', name: 'Fixture Store A', code: 'FXA', is_active: true, deleted_at: null },
  { id: 'st-b', name: 'Fixture Store B', code: 'FXB', is_active: true, deleted_at: null },
];
const WAREHOUSES = [{ id: 'wh-1', name: 'Fixture Warehouse', code: 'FXW', is_active: true, deleted_at: null }];
const PRODUCTS = [
  { id: 'p-mat', name: 'Fixture Mat', sku: 'FX-MAT', is_active: true, deleted_at: null, is_important: true },
  { id: 'p-lamp', name: 'Fixture Lamp', sku: 'FX-LAMP', is_active: true, deleted_at: null, is_important: false },
  { id: 'p-kit', name: 'Fixture Demo Kit', sku: 'FX-KIT', is_active: true, deleted_at: null, is_important: false },
  { id: 'p-cup', name: 'Fixture Cup', sku: 'FX-CUP', is_active: true, deleted_at: null, is_important: false },
];
const CUSTOMERS = [
  { id: 'c-jane', full_name: 'Jane Tan', phone: '+6591390401', email: 'jane@sig.invalid', notes: null, deleted_at: null },
  { id: 'c-rex', full_name: 'Rex Teo', phone: '+6591390402', email: null, notes: null, deleted_at: null },
];
const AFFILIATES = new Set(['c-rex']);
const name = (table: { id: string; name: string }[], id: string) => table.find(x => x.id === id)?.name ?? '?';

const store_inventory = [
  { id: 'si1', store_id: 'st-a', product_id: 'p-mat', current_qty: 8, low_stock_threshold: 3 },
  { id: 'si2', store_id: 'st-a', product_id: 'p-lamp', current_qty: 4, low_stock_threshold: 0 },
  { id: 'si3', store_id: 'st-a', product_id: 'p-cup', current_qty: 0, low_stock_threshold: 0 },
  { id: 'si4', store_id: 'st-b', product_id: 'p-mat', current_qty: 5, low_stock_threshold: 0 },
];
const warehouse_inventory = [
  { id: 'wi1', warehouse_id: 'wh-1', product_id: 'p-mat', current_qty: 40, low_stock_threshold: 10 },
  { id: 'wi2', warehouse_id: 'wh-1', product_id: 'p-kit', current_qty: 6, low_stock_threshold: 0 },
];
const inv = (type: string, loc: string) => type === 'store'
  ? store_inventory.filter(r => r.store_id === loc) : warehouse_inventory.filter(r => r.warehouse_id === loc);
function adjust(type: string, loc: string, product: string, delta: number) {
  const rows: any[] = type === 'store' ? store_inventory : warehouse_inventory;
  const key = type === 'store' ? 'store_id' : 'warehouse_id';
  let row = rows.find(r => r[key] === loc && r.product_id === product);
  if (!row) { row = { id: `new-${rows.length}`, [key]: loc, product_id: product, current_qty: 0, low_stock_threshold: 0 }; rows.push(row); }
  row.current_qty += delta;
}
const have = (type: string, loc: string, product: string) => inv(type, loc).find(r => r.product_id === product)?.current_qty ?? 0;

type Line = { line_id: string; product_id: string; qty_out: number; qty_returned: number; qty_used: number; qty_lost: number };
type Ev = { id: string; line_id: string; outcome: string; quantity: number; condition: string | null; location_type: string | null;
  location_id: string | null; note: string | null; recorded_at: string; recorded_by_name: string; request_id: string | null };
type Loan = { id: string; loan_no: string; status: 'open' | 'closed'; location_type: string; location_id: string;
  customer_id: string | null; borrower_name: string | null; purpose: string | null; lent_at: string; lent_by_name: string;
  expected_return_date: string; closed_at: string | null; lines: Line[]; events: Ev[]; request_id: string | null };
let seq = 3, useSeq = 85;
const loans: Loan[] = [
  { id: 'l-1', loan_no: 'LOAN-000001', status: 'open', location_type: 'store', location_id: 'st-a', customer_id: 'c-jane',
    borrower_name: null, purpose: 'Home trial', lent_at: `${addDays(-9)}T03:00:00Z`, lent_by_name: 'Preview staff',
    expected_return_date: addDays(-2), closed_at: null, request_id: null, events: [],
    lines: [{ line_id: 'ln-1', product_id: 'p-mat', qty_out: 1, qty_returned: 0, qty_used: 0, qty_lost: 0 }] },
  { id: 'l-2', loan_no: 'LOAN-000002', status: 'open', location_type: 'store', location_id: 'st-a', customer_id: null,
    borrower_name: 'Roadshow at the fixture mall', purpose: 'Display set', lent_at: `${addDays(-1)}T01:00:00Z`, lent_by_name: 'Preview owner',
    expected_return_date: addDays(3), closed_at: null, request_id: null,
    lines: [{ line_id: 'ln-2', product_id: 'p-mat', qty_out: 2, qty_returned: 1, qty_used: 0, qty_lost: 0 },
            { line_id: 'ln-3', product_id: 'p-lamp', qty_out: 2, qty_returned: 0, qty_used: 0, qty_lost: 0 }],
    events: [{ id: 'e-1', line_id: 'ln-2', outcome: 'returned', quantity: 1, condition: 'good', location_type: 'store', location_id: 'st-b',
      note: 'Dropped at B', recorded_at: `${today}T02:00:00Z`, recorded_by_name: 'Preview staff', request_id: null }] },
  { id: 'l-3', loan_no: 'LOAN-000003', status: 'open', location_type: 'warehouse', location_id: 'wh-1', customer_id: 'c-rex',
    borrower_name: null, purpose: null, lent_at: `${addDays(-3)}T01:00:00Z`, lent_by_name: 'Preview manager',
    expected_return_date: today, closed_at: null, request_id: null, events: [],
    lines: [{ line_id: 'ln-4', product_id: 'p-kit', qty_out: 2, qty_returned: 0, qty_used: 0, qty_lost: 0 }] },
];
const left = (l: Line) => l.qty_out - l.qty_returned - l.qty_used - l.qty_lost;
const placeName = (type: string | null, id: string | null) => !type || !id ? null : type === 'store' ? name(STORES, id) : name(WAREHOUSES, id);
const json = (l: Loan) => {
  const c = CUSTOMERS.find(x => x.id === l.customer_id);
  const overdue = l.status === 'open' && l.expected_return_date < today;
  return {
    id: l.id, loan_no: l.loan_no, status: l.status, location_type: l.location_type, location_id: l.location_id,
    location_name: placeName(l.location_type, l.location_id), customer_id: l.customer_id,
    borrower: c?.full_name ?? l.borrower_name, borrower_phone: c?.phone ?? null, is_affiliate: AFFILIATES.has(l.customer_id ?? ''),
    purpose: l.purpose, lent_at: l.lent_at, lent_by_name: l.lent_by_name, expected_return_date: l.expected_return_date,
    overdue, days_overdue: overdue ? Math.round((Date.parse(today) - Date.parse(l.expected_return_date)) / 86400000) : 0,
    closed_at: l.closed_at, outstanding: l.lines.reduce((n, x) => n + left(x), 0),
    lines: l.lines.map(x => ({ ...x, product_name: name(PRODUCTS, x.product_id), sku: PRODUCTS.find(p => p.id === x.product_id)?.sku, outstanding: left(x) })),
    events: l.events.map(e => ({ ...e, product_name: name(PRODUCTS, l.lines.find(x => x.line_id === e.line_id)!.product_id),
      location_name: placeName(e.location_type, e.location_id) })),
  };
};
const fail = (message: string) => ({ data: null, error: { message, code: 'P0001' } });
const ok = (data: unknown) => ({ data, error: null });
const canAct = (type: string, id: string) => type === 'store' ? storeAccess(id) : canWarehouse;
const canSee = (type: string, id: string) => canAct(type, id) || seesAll;
// The first answer of a save is lost (?drop=1): the save is made, the page hears nothing.
const dropped = new Set<string>();
const answer = (requestId: string | null, result: { data: any; error: any }) => {
  if (!dropAnswers || !requestId || result.error || dropped.has(requestId)) return result;
  dropped.add(requestId);
  return { data: null, error: { message: 'TypeError: Failed to fetch', code: '' } };
};
const same = (x: unknown, y: unknown) => JSON.stringify(x) === JSON.stringify(y);
const usesByRequest = new Map<string, { form: unknown; uses: unknown[] }>();
const lendForm = (a: any) => ({ t: a.p_location_type, l: a.p_location_id, c: a.p_customer_id ?? null, n: a.p_borrower_name ?? null,
  p: a.p_purpose ?? null, d: a.p_expected_return_date,
  lines: [...a.p_lines].sort((x: any, y: any) => x.product_id.localeCompare(y.product_id)) });
const lendForms = new Map<string, unknown>();
const returnForms = new Map<string, unknown>();
const where = (type: string) => type === 'warehouse' ? 'this warehouse' : 'this store';

const RPC: Record<string, (a: any) => { data: any; error: any }> = {
  set_product_important: () => ok(null),
  set_low_stock_threshold: () => ok(null),
  stock_loans_at: a => {
    if (!canSee(a.p_location_type, a.p_location_id)) return fail(`No access to this ${a.p_location_type}`);
    const mine = loans.filter(l => l.location_type === a.p_location_type && l.location_id === a.p_location_id);
    return ok({ today, can_act: canAct(a.p_location_type, a.p_location_id),
      open: mine.filter(l => l.status === 'open').sort((x, y) => x.expected_return_date.localeCompare(y.expected_return_date)).map(json),
      closed: a.p_include_closed ? mine.filter(l => l.status === 'closed').map(json) : [] });
  },
  customer_stock_loans: a => ok(loans.filter(l => l.customer_id === a.p_customer_id).map(json)),
  record_stock_uses: a => {
    const form = { t: a.p_location_type, l: a.p_location_id, r: a.p_reason, n: a.p_note ?? null,
      lines: [...a.p_lines].sort((x: any, y: any) => x.product_id.localeCompare(y.product_id)) };
    const before = a.p_request_id && usesByRequest.get(a.p_request_id);
    if (before) return same(before.form, form)
      ? ok({ success: true, replayed: true, uses: before.uses })
      : fail(`This form was already saved as ${before.uses.map((u: any) => `${u.use_no} (${name(PRODUCTS, u.product_id)} ×${u.quantity})`).join(', ')}, and has been changed since: nothing more was recorded. Close it, and record anything else as a new use.`);
    if (a.p_location_type === 'warehouse' && !canWarehouse) return fail('You do not have permission to use stock from a warehouse');
    if (a.p_location_type === 'store' && !storeAccess(a.p_location_id)) return fail('No access to this store');
    for (const l of a.p_lines) {
      const h = have(a.p_location_type, a.p_location_id, l.product_id);
      if (h < l.quantity) return fail(`Only ${h} of "${name(PRODUCTS, l.product_id)}" in stock at ${where(a.p_location_type)}`);
    }
    const uses = a.p_lines.map((l: any) => { adjust(a.p_location_type, a.p_location_id, l.product_id, -l.quantity);
      return { use_no: `USE-${String(++useSeq).padStart(6, '0')}`, product_id: l.product_id, quantity: l.quantity }; });
    if (a.p_request_id) usesByRequest.set(a.p_request_id, { form, uses });
    return answer(a.p_request_id, ok({ success: true, replayed: false, uses }));
  },
  lend_stock: a => {
    const again = loans.find(l => l.request_id && l.request_id === a.p_request_id);
    if (again) return same(lendForms.get(again.request_id!), lendForm(a))
      ? ok({ success: true, replayed: true, loan_id: again.id, loan_no: again.loan_no, loan: json(again) })
      : fail(`This form was already saved as ${again.loan_no}, and has been changed since: nothing more was lent. Close it, and lend anything else as a new loan.`);
    if (!canAct(a.p_location_type, a.p_location_id)) return fail(a.p_location_type === 'warehouse' ? 'You do not have permission to lend stock from a warehouse' : 'No access to this store');
    if (a.p_expected_return_date < today) return fail('The expected return date cannot be in the past');
    for (const l of a.p_lines) {
      const h = have(a.p_location_type, a.p_location_id, l.product_id);
      if (h < l.quantity) return fail(`Only ${h} of "${name(PRODUCTS, l.product_id)}" in stock at ${where(a.p_location_type)}, so ${l.quantity} cannot be lent`);
    }
    const loan: Loan = { id: `l-${++seq}`, loan_no: `LOAN-${String(seq).padStart(6, '0')}`, status: 'open',
      location_type: a.p_location_type, location_id: a.p_location_id, customer_id: a.p_customer_id, borrower_name: a.p_borrower_name,
      purpose: a.p_purpose, lent_at: new Date().toISOString(), lent_by_name: `Preview ${role}`, expected_return_date: a.p_expected_return_date,
      closed_at: null, request_id: a.p_request_id, events: [],
      lines: a.p_lines.map((l: any, i: number) => ({ line_id: `ln-${seq}-${i}`, product_id: l.product_id, qty_out: l.quantity, qty_returned: 0, qty_used: 0, qty_lost: 0 })) };
    for (const l of a.p_lines) adjust(a.p_location_type, a.p_location_id, l.product_id, -l.quantity);
    loans.push(loan);
    if (a.p_request_id) lendForms.set(a.p_request_id, lendForm(a));
    return answer(a.p_request_id, ok({ success: true, replayed: false, loan_id: loan.id, loan_no: loan.loan_no, loan: json(loan) }));
  },
  return_stock_loan: a => {
    const loan = loans.find(l => l.id === a.p_loan_id);
    if (!loan) return fail('Loan not found');
    if (a.p_request_id && loan.events.some(e => e.request_id === a.p_request_id)) {
      return same(returnForms.get(a.p_request_id), { e: a.p_entries, n: a.p_note ?? null })
        ? ok({ success: true, replayed: true, closed: loan.status === 'closed', loan: json(loan) })
        : fail(`This form was already saved for ${loan.loan_no}, and has been changed since: nothing more was recorded. Close it, and record anything else as a new take-back.`);
    }
    if (!canAct(loan.location_type, loan.location_id)) return fail(loan.location_type === 'warehouse' ? 'You do not have permission to take back a loan from a warehouse' : 'No access to this store');
    if (loan.status !== 'open') return fail(`${loan.loan_no} is already closed: everything on it is accounted for`);
    for (const e of a.p_entries) {
      if (e.outcome === 'returned' && e.location_type === 'warehouse' && !canWarehouse) return fail('You do not have permission to take stock back into a warehouse');
    }
    for (const line of loan.lines) {
      const asked = a.p_entries.filter((e: any) => e.line_id === line.line_id).reduce((n: number, e: any) => n + e.quantity, 0);
      if (asked > left(line)) return fail(`Only ${left(line)} of "${name(PRODUCTS, line.product_id)}" still out on ${loan.loan_no}, so ${asked} cannot be accounted for`);
    }
    for (const e of a.p_entries) {
      const line = loan.lines.find(x => x.line_id === e.line_id)!;
      if (e.outcome === 'returned') { line.qty_returned += e.quantity; adjust(e.location_type, e.location_id, line.product_id, e.quantity); }
      if (e.outcome === 'used') line.qty_used += e.quantity;
      if (e.outcome === 'lost') line.qty_lost += e.quantity;
      loan.events.push({ id: `e-${Math.random()}`, line_id: e.line_id, outcome: e.outcome, quantity: e.quantity,
        condition: e.outcome === 'returned' ? (e.condition ?? 'good') : e.condition ?? null,
        location_type: e.outcome === 'returned' ? e.location_type : null, location_id: e.outcome === 'returned' ? e.location_id : null,
        note: a.p_note, recorded_at: new Date().toISOString(), recorded_by_name: `Preview ${role}`, request_id: a.p_request_id });
    }
    const closed = loan.lines.every(l => left(l) === 0);
    if (closed) { loan.status = 'closed'; loan.closed_at = new Date().toISOString(); }
    if (a.p_request_id) returnForms.set(a.p_request_id, { e: a.p_entries, n: a.p_note ?? null });
    return answer(a.p_request_id, ok({ success: true, replayed: false, closed, loan: json(loan) }));
  },
};

const TABLES: Record<string, any[]> = {
  stores: STORES, warehouses: WAREHOUSES, products: PRODUCTS, customers: CUSTOMERS, store_inventory, warehouse_inventory,
};
function table(nameOf: string) {
  let rows = [...(TABLES[nameOf] ?? [])];
  let single = false;
  const b: any = {
    then: (res: any, rej: any) => Promise.resolve({ data: single ? rows[0] ?? null : rows.map(r => ({ ...r })), error: null }).then(res, rej),
  };
  for (const m of ['select', 'order', 'limit', 'neq', 'not', 'range', 'in', 'gt']) b[m] = () => b;
  b.is = (c: string, v: unknown) => { rows = rows.filter(r => !(c in r) || r[c] === v); return b; };
  b.eq = (c: string, v: unknown) => { rows = rows.filter(r => !(c in r) || r[c] === v); return b; };
  b.or = (expr: string) => {
    const m = /ilike\.%([^%]*)%/.exec(expr);
    const q = (m?.[1] ?? '').toLowerCase();
    if (q) rows = rows.filter(r => JSON.stringify(r).toLowerCase().includes(q));
    return b;
  };
  b.maybeSingle = () => { single = true; return b; };
  return b;
}

export const supabase = {
  from: table,
  rpc: async (fn: string, args: any) => {
    await new Promise(r => setTimeout(r, fn === 'stock_loans_at' && args?.p_location_id === slowAt ? 1500 : 120));
    return RPC[fn] ? RPC[fn](args ?? {}) : { data: null, error: null };
  },
} as any;
