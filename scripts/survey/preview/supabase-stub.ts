// In-memory stand-in for src/lib/supabase, used only by the Health Surveys
// preview (433). Fixture data only (this repository is public): invented
// customers and forms; phones +65 8433 09xx. ?holds=none shows nothing
// waiting; ?holds=old answers as a server without 433 (no To match tab).
// 468: hs-5 is a form two customers have the phone and the email of (Delete
// for an Owner or Manager); delete_customer retires the one named.
// 468 (A): hs-6 is a form whose phone and email are one customer's, who
// already has a survey: it waits quietly (no Attach; New customer or Close).
// Every call is recorded on window.__calls.
const params = new URLSearchParams(window.location.search);
const holdsMode = params.get('holds') ?? 'some';

const customers = [
  { id: 'c-bee', full_name: 'Bee Hoon Testkoh', phone: '+6584330901', email: 'bee@sig.invalid', notes: null, deleted_at: null,
    date_of_birth: '1961-04-02', created_at: '2026-07-27T02:00:00Z' },
  { id: 'c-siew', full_name: 'Siew Lan (Office) Testchua', phone: '+6584330902', email: 'siew@sig.invalid', notes: null,
    deleted_at: null, date_of_birth: null, created_at: '2026-07-27T02:00:00Z' },
  { id: 'c-siti', full_name: 'Siti Testgmail', phone: '+6584330903', email: 'sitigmail@gmail.com', notes: null,
    deleted_at: null, date_of_birth: '1975-01-09', created_at: '2026-08-04T02:00:00Z' },
  { id: 'c-pei1', full_name: 'Pei Qi Testng', phone: '+6584330904', email: null, notes: null, deleted_at: null,
    date_of_birth: null, created_at: '2026-08-10T02:00:00Z' },
  { id: 'c-pei2', full_name: 'Testng Pei Qi', phone: '+6584330904', email: null, notes: null, deleted_at: null,
    date_of_birth: '1990-06-30', created_at: '2026-09-01T02:00:00Z' },
  { id: 'c-ann', full_name: 'Ann Lee Testtan', phone: '+6584330905', email: 'ann@sig.invalid', notes: null, deleted_at: null,
    date_of_birth: '1970-12-01', created_at: '2026-08-01T02:00:00Z' },
  { id: 'c-jo1', full_name: 'Jo Testdup', phone: '+6584330906', email: 'jo@sig.invalid', notes: null, deleted_at: null,
    date_of_birth: '1982-03-04', created_at: '2026-07-27T02:00:00Z' },
  { id: 'c-jo2', full_name: 'Joanne Testdup', phone: '+6584330906', email: 'jo@sig.invalid', notes: null, deleted_at: null,
    date_of_birth: null, created_at: '2026-09-12T02:00:00Z' },
  { id: 'c-pia', full_name: 'Pia Testsurvey', phone: '+6584330907', email: 'pia@sig.invalid', notes: null, deleted_at: null,
    date_of_birth: '1979-05-06', created_at: '2026-06-02T02:00:00Z' },
];

const cand = (id: string, flags: { phone?: boolean; email?: boolean; name?: boolean }, survey_no: string | null = null) => {
  const c = customers.find(x => x.id === id)!;
  return { customer_id: c.id, full_name: c.full_name, phone: c.phone, email: c.email, date_of_birth: c.date_of_birth,
    created_at: c.created_at, deleted: false, phone_matches: !!flags.phone, email_matches: !!flags.email,
    name_matches: !!flags.name, survey_no };
};

let holds: any[] = holdsMode === 'none' ? [] : [
  { survey_id: 'hs-1', survey_no: 'HS-20261016-a1b2c3', submitted_at: '2026-10-16T02:15:00Z', store_name: 'Preview Main Store',
    event_name: null, full_name: 'Ah Kow Testkoh', date_of_birth: '1988-03-14', sex: 'male', phone: '+6584330901',
    email: 'ahkow@sig.invalid', occupation: 'Engineer', source_label: 'Walk-in', reason: 'phone_in_use',
    held_at: '2026-10-16T02:15:00Z', candidates: [cand('c-bee', { phone: true })] },
  { survey_id: 'hs-2', survey_no: 'HS-20261016-d4e5f6', submitted_at: '2026-10-16T03:40:00Z', store_name: 'Preview Main Store',
    event_name: null, full_name: 'Siew Laan Testchua', date_of_birth: '1966-11-20', sex: 'female', phone: '+6584330902',
    email: 'siew@sig.invalid', occupation: 'Retired', source_label: 'A friend', reason: 'phone_and_email_in_use',
    held_at: '2026-10-16T03:40:00Z', candidates: [cand('c-siew', { phone: true, email: true })] },
  { survey_id: 'hs-3', survey_no: 'HS-20261016-0718aa', submitted_at: '2026-10-16T05:05:00Z', store_name: 'Preview Main Store',
    event_name: 'Roadshow @ Preview Mall', full_name: 'Siti Rahmah Testgmail', date_of_birth: '1975-01-09', sex: 'female',
    phone: '+6584330999', email: 's.i.t.i.gmail@gmail.com', occupation: null, source_label: 'Event Name', reason: 'email_in_use',
    held_at: '2026-10-16T05:05:00Z', candidates: [cand('c-siti', { email: true })] },
  { survey_id: 'hs-4', survey_no: 'HS-20261016-99ab01', submitted_at: '2026-10-16T06:30:00Z', store_name: 'Preview Main Store',
    event_name: null, full_name: 'Qi Pei Testng', date_of_birth: '1990-06-30', sex: 'female', phone: '+6584330904',
    email: 'qipei@sig.invalid', occupation: 'Designer', source_label: 'Instagram', reason: 'several_name_matches',
    held_at: '2026-10-16T06:30:00Z',
    candidates: [cand('c-pei1', { phone: true, name: true }), cand('c-pei2', { phone: true, name: true }, 'HS-20260901-77aa00')] },
  { survey_id: 'hs-5', survey_no: 'HS-20261024-d00001', submitted_at: '2026-10-24T03:10:00Z', store_name: 'Preview Main Store',
    event_name: null, full_name: 'Jody Testdup', date_of_birth: '1982-03-04', sex: 'female', phone: '+6584330906',
    email: 'jo@sig.invalid', occupation: 'Teacher', source_label: 'Walk-in', reason: 'phone_and_email_in_use',
    held_at: '2026-10-24T03:10:00Z',
    candidates: [cand('c-jo1', { phone: true, email: true }), cand('c-jo2', { phone: true, email: true })] },
  { survey_id: 'hs-6', survey_no: 'HS-20261024-a00001', submitted_at: '2026-10-24T05:20:00Z', store_name: 'Preview Main Store',
    event_name: null, full_name: 'Pippa Testsurvey', date_of_birth: null, sex: 'female', phone: '+6584330907',
    email: 'pia@sig.invalid', occupation: null, source_label: 'Walk-in', reason: 'phone_and_email_customer_has_survey',
    held_at: '2026-10-24T05:20:00Z',
    candidates: [cand('c-pia', { phone: true, email: true }, 'HS-20261001-c0ffee')] },
];

const overview = customers.map((c, i) => ({
  customer_id: c.id, full_name: c.full_name, phone: c.phone, email: c.email,
  survey_id: i === 4 ? 's-x' : c.id === 'c-pia' ? 's-pia' : null,
  survey_no: i === 4 ? 'HS-20260901-77aa00' : c.id === 'c-pia' ? 'HS-20261001-c0ffee' : null, source: 'public_form',
  reviewed_at: null, remarks_condition: null, remarks_recommendation: null, remark_count: 0, last_remark_at: null,
  total_count: customers.length,
}));

const tables: Record<string, any[]> = {
  stores: [{ id: 's-1', name: 'Preview Main Store', deleted_at: null, is_active: true }],
  survey_links: [], health_surveys: [], customer_remarks: [], customers,
};

(window as any).__calls = [];
const fail = (message: string) => ({ data: null, error: { message } });

function rpc(name: string, a: any): { data: any; error: any } {
  switch (name) {
    case 'customer_survey_overview': return { data: overview, error: null };
    case 'health_survey_holds_list':
      return holdsMode === 'old'
        ? fail('Could not find the function public.health_survey_holds_list without parameters in the schema cache')
        : { data: holds, error: null };
    case 'attach_held_health_survey': {
      if (!a?.p_note?.trim()) return fail('Add a short note on how you confirmed this is the same person.');
      const f = holds.find(h => h.survey_id === a.p_survey_id);
      if (!f) return fail('This form has already been dealt with.');
      const c = f.candidates.find((x: any) => x.customer_id === a.p_customer_id);
      if (c?.survey_no) return fail(`This customer already has a health survey (${c.survey_no}). A customer can have only one.`);
      holds = holds.filter(h => h !== f);
      return { data: { ok: true, customer_id: a.p_customer_id, survey_no: f.survey_no }, error: null };
    }
    case 'create_customer_from_held_survey': {
      const f = holds.find(h => h.survey_id === a.p_survey_id);
      if (!f) return fail('This form has already been dealt with.');
      holds = holds.filter(h => h !== f);
      return { data: { ok: true, customer_id: 'c-new', survey_no: f.survey_no }, error: null };
    }
    case 'close_held_health_survey': {
      if (!a?.p_reason?.trim()) return fail('A reason is required.');
      const f = holds.find(h => h.survey_id === a.p_survey_id);
      if (!f) return fail('This form has already been dealt with.');
      holds = holds.filter(h => h !== f);
      return { data: { ok: true, survey_no: f.survey_no }, error: null };
    }
    case 'delete_customer': {
      const c = customers.find(x => x.id === a?.p_customer_id && !x.deleted_at);
      if (!c) return fail('That customer does not exist');
      const norm = (v: string) => String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
      if (norm(a.p_confirm_name) !== norm(c.full_name)) return fail(`The name you typed does not match "${c.full_name}"`);
      c.deleted_at = new Date().toISOString();
      holds = holds.map(h => ({ ...h, candidates: h.candidates.map((x: any) => (x.customer_id === c.id ? { ...x, deleted: true } : x)) }));
      return { data: { success: true, full_name: c.full_name }, error: null };
    }
    default: return { data: null, error: null };
  }
}

class Query {
  filters: ((r: any) => boolean)[] = [];
  one = false;
  constructor(public kind: 'table' | 'rpc', public name: string, public args: any) {}
  select() { return this; }
  eq(c: string, v: any) { this.filters.push(r => r[c] === v); return this; }
  is(c: string, v: any) { this.filters.push(r => (r[c] ?? null) === v); return this; }
  in(c: string, vs: any[]) { this.filters.push(r => vs.includes(r[c])); return this; }
  or() { return this; }
  ilike() { return this; }
  order() { return this; }
  limit() { return this; }
  range() { return this; }
  maybeSingle() { this.one = true; return this; }
  single() { this.one = true; return this; }
  insert() { return this; }
  update() { return this; }
  async exec() {
    (window as any).__calls.push({ kind: this.kind, name: this.name, args: this.args });
    await new Promise(r => setTimeout(r, 60));
    if (this.kind === 'rpc') { const r = rpc(this.name, this.args); return { data: structuredClone(r.data), error: r.error }; }
    const rows = (tables[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
    return { data: structuredClone(this.one ? rows[0] ?? null : rows), error: null };
  }
  then(res: any, rej: any) { return this.exec().then(res, rej); }
}

export const supabase: any = {
  from: (name: string) => new Query('table', name, null),
  rpc: (name: string, args?: any) => new Query('rpc', name, args),
  auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) },
};
export default supabase;
