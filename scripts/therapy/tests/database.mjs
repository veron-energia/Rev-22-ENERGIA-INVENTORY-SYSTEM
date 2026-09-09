// Migrations 220-223 against the isolated local database, and — the point of
// this file — agreement between the SQL and the JavaScript.
//
//   scripts/auth-email/bootstrap-local.sh start
//   npm run test:therapy:db
//
// The expiry rule exists twice: once in src/lib/therapy/expiry.mjs for the page
// and once in migration 220 for every server-side path. Two implementations of
// one rule drift unless something compares them, so most of this file does.

import { execFileSync } from 'node:child_process';
import {
  baseExpiry, adjustedExpiry, calendarDaysRemaining, nextConsecutiveStart,
} from '../../../src/lib/therapy/expiry.mjs';

process.env.PGHOST ??= '/tmp'; process.env.PGPORT ??= '55442';
process.env.PGUSER ??= 'postgres'; process.env.PGDATABASE ??= 'energia_auth_email_test';
if (process.env.PGDATABASE !== 'energia_auth_email_test' || process.env.PGPORT !== '55442') {
  throw new Error('Refusing to run outside the disposable database on port 55442.');
}
const args = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'];
const sql = s => execFileSync('psql', [...args, '-c', s], { encoding: 'utf8' }).trim();
const json = s => JSON.parse(sql(s));
// Each psql invocation is its own session, so a set_config in one is gone by the
// next. Anything depending on session state has to travel with its query.
const sqlAs = (role, s) =>
  execFileSync('psql', [...args,
    '-c', `select set_config('test.role', '${role}', false), set_config('test.store_access', 'all', false);`,
    '-c', s], { encoding: 'utf8' }).trim().split('\n').filter(Boolean).pop();
// Tolerates the table not existing yet, which is the case on a first ever run.
const sqlSafe = s => { try { return sql(s); } catch { return null; } };
const fails = (s, run = sql) => {
  try { run(s); return null; } catch (e) { return String(e.stderr ?? e.message); }
};

let pass = 0;
const ok = (label, cond, detail = '') => {
  console.log(`${cond ? 'PASS' : 'FAIL'}: ${label}${detail ? ` — ${detail}` : ''}`);
  if (!cond) process.exitCode = 1; else pass++;
};

const apply = f => execFileSync('psql', [...args, '-f', f], { encoding: 'utf8' });
apply('scripts/therapy/tests/prior-state.sql');

// Clear the calendar BEFORE the migrations run, so migration 224 reseeds into
// an empty table. Doing it afterwards left the previous run's fixture closures
// in place, and one of them lands inside the twelve-month window the seed check
// measures — a test contaminating its own later assertion.
sqlSafe(`delete from public.therapy_closure_dates;`);
for (const f of ['220_therapy_holiday_calendars', '221_therapy_reward_choices',
                 '222_therapy_customer_summaries', '223_therapy_activation_and_sequencing',
                 '224_therapy_singapore_calendar_seed',
                 '225_therapy_expiry_base_correction',
                 '226_therapy_historical_claims']) {
  apply(`supabase/${f}.sql`);
  apply(`supabase/${f}.sql`);            // idempotence is part of the contract
}
ok('migrations 220-226 apply over the pre-220 schema, and apply again, cleanly', true);

{
  // The seeded calendar, checked against the gazette this file was written from.
  const seeded = sql(`select count(*) from public.therapy_closure_dates
                       where source = 'mom.gov.sg' and deleted_at is null;`);
  ok('the Singapore calendar seeds 26 gazetted dates, once', seeded === '26', `${seeded} rows`);

  const pairs = sql(`select count(*) from public.therapy_closure_dates
                      where observed_for is not null and deleted_at is null and source = 'mom.gov.sg';`);
  ok('and records the four observed substitutes with the Sunday they stand in for',
     pairs === '4', `${pairs} substitutes`);

  const sundays = sql(`select count(*) from public.therapy_closure_dates
                        where source = 'mom.gov.sg' and deleted_at is null
                          and extract(dow from closure_date) = 0;`);
  ok('the Sundays themselves are recorded too, so the explanation can show why they add nothing',
     sundays === '4', `${sundays} Sundays`);

  // A full year on the real calendar: 11 eligible dates, 2 Sundays skipped.
  const real = sql(`select added_days from public.therapy_adjusted_expiry(
                      '2026-09-08', 12, 'SG', null, 'purchased');`);
  ok('a 12-month package on the real Singapore calendar gains 11 days, not 13',
     real === '11', `gained ${real}`);
}

// --- fixtures ---------------------------------------------------------------
const STORE = '11111111-1111-1111-1111-111111111111';
sql(`insert into public.stores (id, name) values ('${STORE}','Main') on conflict do nothing;`);
sql(`delete from public.therapy_calendar_coverage;
     delete from public.therapy_expiry_adjustments;
     delete from public.customer_reward_vouchers;
     delete from public.voucher_redemptions;
     delete from public.purchased_therapy_entitlements;
     delete from public.therapy_entitlements;
     delete from public.therapy_package_rules;
     delete from public.therapy_closure_dates;
     delete from public.customers;`);

const cust = (name, phone) =>
  sql(`insert into public.customers (full_name, phone) values ('${name}','${phone}') returning id;`);
const A = cust('Alice Tan', '+6591110001');
const B = cust('Bob Lim', '+6591110002');
// Two different people who share one phone number — the system supports this.
const SHARED1 = cust('Chen Wei', '+6598887777');
const SHARED2 = cust('Chen Mei', '+6598887777');

const closure = (date, kind, name, country = 'SG') =>
  sql(`insert into public.therapy_closure_dates (closure_date, kind, name, country_code)
       values ('${date}','${kind}','${name}',${country === null ? 'null' : `'${country}'`})
       on conflict do nothing returning id;`);

// =============================================================================
// The calculation
// =============================================================================
{
  // Every case the node tests cover, asked of the database as well.
  closure('2026-01-15', 'public_holiday', 'Thursday holiday');
  closure('2026-01-11', 'public_holiday', 'Sunday holiday');
  closure('2026-02-05', 'company_closure', 'Stocktake');
  closure('2026-01-15', 'company_closure', 'Same day, second record');

  // membership_expiry() is not installed — Phase 19 dropped it and migration 72
  // moved purchased therapy onto therapy_expiry(). Both conventions therefore
  // resolve to the same base here, including at 29 February, and the JS is
  // asked for the 'legacy' rule for every case because that is the only rule.
  ok('membership_expiry is absent, as it is in production',
     sql(`select count(*) from pg_proc where proname = 'membership_expiry'
           and pronamespace = 'public'::regnamespace;`) === '0');
  ok('both conventions resolve to the same base, so no entitlement kind is treated differently',
     sql(`select public.therapy_base_expiry('2024-02-29', 12, 'legacy')
                 = public.therapy_base_expiry('2024-02-29', 12, 'purchased');`) === 't');

  const cases = [
    ['2026-01-05', 1, 'legacy'], ['2026-01-05', 1, 'purchased'],
    ['2026-01-31', 1, 'legacy'], ['2024-01-31', 1, 'legacy'],
    ['2024-02-29', 12, 'legacy'], ['2024-02-29', 12, 'purchased'],
    ['2026-06-01', 6, 'legacy'], ['2025-12-20', 3, 'purchased'],
  ];
  const closures = json(`select coalesce(jsonb_agg(jsonb_build_object('date', closure_date)), '[]')
                           from public.therapy_closure_dates where deleted_at is null;`);
  const bad = [];
  for (const [d, m, conv] of cases) {
    const s = sql(`select base_expiry || '|' || adjusted_expiry || '|' || added_days
                     from public.therapy_adjusted_expiry('${d}', ${m}, 'SG', null, '${conv}');`);
    const j = adjustedExpiry({ activationDate: d, months: m, closures, convention: 'legacy' });
    const js = `${j.baseExpiry}|${j.adjustedExpiry}|${j.addedDays}`;
    if (s !== js) bad.push(`${d}+${m}m/${conv}: sql=${s} js=${js}`);
  }
  ok('SQL and JS agree on every expiry case, both conventions', bad.length === 0, bad.join('; '));
}

{
  const r = sql(`select added_days from public.therapy_adjusted_expiry('2026-01-05', 1, 'SG', null, 'legacy');`);
  ok('an ordinary Sunday, and a holiday falling on one, add nothing', r === '2',
     `added ${r} (the Thursday twice-recorded holiday and the 5 Feb closure only)`);
}

{
  // Isolated on its own country so no other closure can be in the window and
  // make a wrong answer look right.
  closure('2026-04-15', 'public_holiday', 'Songkran', 'TH');
  closure('2026-04-15', 'company_closure', 'Songkran — shop shut', 'TH');
  const one = sql(`select added_days from public.therapy_adjusted_expiry('2026-04-01', 1, 'TH', null, 'legacy');`);
  const rows = sql(`select count(*) from public.therapy_closure_dates
                     where closure_date='2026-04-15' and deleted_at is null;`);
  ok('one date recorded twice is one lost day, not two', one === '1' && rows === '2',
     `${rows} records, ${one} day added`);
}

{
  // 15 Jan pushes 4 Feb to the 5th; the 5th is itself a closure, so it extends again.
  const r = json(`select public.therapy_expiry_explanation('2026-01-05', 1, 'SG', null, 'legacy');`);
  ok('the extension repeats until it stops moving',
     r.base_expiry === '2026-02-04' && r.adjusted_expiry === '2026-02-06' && r.added_days === 2,
     `${r.base_expiry} -> ${r.adjusted_expiry} (+${r.added_days})`);
  ok('the explanation lists the dates responsible, and the Sundays it skipped',
     r.applied.length === 2 && r.skipped_sundays.length === 1,
     `applied=${r.applied.length} skipped=${r.skipped_sundays.length}`);
}

{
  // Vesak 2026: Sunday 31 May, observed Monday 1 June.
  closure('2026-05-31', 'public_holiday', 'Vesak Day');
  sql(`insert into public.therapy_closure_dates (closure_date, kind, name, country_code, observed_for)
       values ('2026-06-01','public_holiday','Vesak Day (observed)','SG','2026-05-31') on conflict do nothing;`);
  const r = json(`select public.therapy_expiry_explanation('2026-05-04', 1, 'SG', null, 'legacy');`);
  ok('a substitute holiday on the Monday is the date that earns the day',
     r.added_days === 1 && r.applied.some(a => a.date === '2026-06-01')
       && !r.applied.some(a => a.date === '2026-05-31'), JSON.stringify(r.applied.map(a => a.date)));
}

{
  // A country-specific closure must not extend everybody.
  closure('2026-03-10', 'public_holiday', 'Malaysia-only holiday', 'MY');
  const sg = sql(`select added_days from public.therapy_adjusted_expiry('2026-03-02', 1, 'SG', null, 'legacy');`);
  const my = sql(`select added_days from public.therapy_adjusted_expiry('2026-03-02', 1, 'MY', null, 'legacy');`);
  ok("one country's holiday does not extend another country's customers",
     sg === '0' && my === '1', `SG added ${sg}, MY added ${my}`);

  sql(`insert into public.therapy_closure_dates (closure_date, kind, name, country_code)
       values ('2026-03-11','company_closure','Company-wide shutdown', null) on conflict do nothing;`);
  const sg2 = sql(`select added_days from public.therapy_adjusted_expiry('2026-03-02', 1, 'SG', null, 'legacy');`);
  ok('an all-countries closure extends everyone', sg2 === '1', `SG added ${sg2}`);
}

{
  // With no country assigned, country-specific closures do not apply at all —
  // and the answer is reported as unverified rather than presented as a fact.
  const none = sql(`select added_days from public.therapy_adjusted_expiry('2026-01-05', 1, null, null, 'legacy');`);
  const gaps = json(`select public.therapy_calendar_gaps('2026-01-05','2026-02-04', null, null);`);
  ok('an unassigned country picks up no country calendar, and is flagged unverified',
     none === '0' && gaps.verified === false,
     `added ${none}, verified=${gaps.verified}`);

  const unverified = json(`select public.therapy_calendar_gaps('2026-01-05','2026-02-04','SG', null);`);
  ok('a year nobody has confirmed is not called verified',
     unverified.verified === false && unverified.missing_years.includes(2026));

  sqlAs('owner', `select public.set_therapy_calendar_coverage('SG', 2026, '*', true, 'mom.gov.sg', 'gazette');`);
  const verified = json(`select public.therapy_calendar_gaps('2026-01-05','2026-02-04','SG', null);`);
  ok('once confirmed against a source, the year counts as covered', verified.verified === true);

  const regional = json(`select public.therapy_calendar_gaps('2026-01-05','2026-02-04','MY', null);`);
  ok('a country whose holidays vary by region is not verified without one',
     regional.verified === false && regional.requires_region === true);
}

// =============================================================================
// Applying it to entitlements
// =============================================================================
const purchased = (customer, months, status, activation, expiry, country = null) =>
  sql(`insert into public.purchased_therapy_entitlements
        (entitlement_no, customer_id, store_id, package_name, duration_months,
         activation_deadline, activation_date, expiry_date, status, holiday_country)
       values ('P-${Math.random().toString(36).slice(2, 9)}','${customer}','${STORE}','Unlimited',${months},
               '2027-12-31', ${activation ? `'${activation}'` : 'null'},
               ${expiry ? `'${expiry}'` : 'null'}, '${status}',
               ${country ? `'${country}'` : 'null'}) returning id;`);

{
  const active = purchased(A, 1, 'active', '2026-01-05', '2026-02-04', 'SG');
  const expired = purchased(B, 1, 'expired', '2025-01-05', '2025-02-04', 'SG');

  const before = sql(`select count(*) from public.therapy_recalculation_preview(null, null);`);
  ok('the preview covers active and scheduled entitlements only', before === '1', `${before} rows`);

  const row = json(`select to_jsonb(p) from public.therapy_recalculation_preview(null,null) p limit 1;`);
  ok('the preview shows the base, the proposal and the change, and writes nothing',
     row.base_expiry === '2026-02-04' && row.proposed_expiry === '2026-02-06' && row.change_days === 2,
     `${row.current_expiry} -> ${row.proposed_expiry}`);
  ok('nothing was written by the preview',
     sql(`select expiry_date from public.purchased_therapy_entitlements where id='${active}';`) === '2026-02-04');

  const applied = JSON.parse(sqlAs('owner', `select public.therapy_apply_recalculation(null, null, false, null);`));
  ok('applying it lengthens the active entitlement', applied.updated === 1, JSON.stringify(applied));
  ok('and the new expiry is stored with its base and day count',
     sql(`select expiry_date || '|' || base_expiry_date || '|' || closure_days_added
            from public.purchased_therapy_entitlements where id='${active}';`) === '2026-02-06|2026-02-04|2',
     sql(`select expiry_date from public.purchased_therapy_entitlements where id='${active}';`));

  const again = JSON.parse(sqlAs('owner', `select public.therapy_apply_recalculation(null, null, false, null);`));
  ok('running it again changes nothing — the days are not added twice',
     again.updated === 0 && again.unchanged === 1, JSON.stringify(again));
  ok('the expiry is still the same after the second run',
     sql(`select expiry_date from public.purchased_therapy_entitlements where id='${active}';`) === '2026-02-06');

  ok('an expired entitlement is left alone',
     sql(`select expiry_date from public.purchased_therapy_entitlements where id='${expired}';`) === '2025-02-04');

  // Removing a calendar entry would shorten a granted expiry.
  sqlAs('owner', `select public.delete_therapy_closure_date(
    (select id from public.therapy_closure_dates where closure_date='2026-02-05' limit 1), 'entered in error');`);
  const shorten = JSON.parse(sqlAs('owner', `select public.therapy_apply_recalculation(null, null, false, null);`));
  ok('removing a closure never silently shortens what was granted',
     shorten.skipped_would_shorten === 1 && shorten.updated === 0, JSON.stringify(shorten));
  ok('and the granted expiry still stands',
     sql(`select expiry_date from public.purchased_therapy_entitlements where id='${active}';`) === '2026-02-06');

  const noReason = fails(`select public.therapy_apply_recalculation(null, null, true, '');`,
                         s => sqlAs('owner', s));
  ok('shortening without a reason is refused', noReason !== null && /requires a reason/.test(noReason));

  const forced = JSON.parse(sqlAs('owner',
    `select public.therapy_apply_recalculation(null, null, true, 'Closure was recorded in error');`));
  ok('an Owner can shorten it deliberately, with a reason on the record', forced.updated === 1);
  ok('and the correction is audited with both dates',
     sql(`select old_expiry || '->' || new_expiry from public.therapy_expiry_adjustments
           where action='recalculated' order by created_at desc limit 1;`) === '2026-02-06->2026-02-05');

  // put it back for later tests
  closure('2026-02-05', 'company_closure', 'Stocktake');
  sqlAs('owner', `select public.therapy_apply_recalculation(null, null, false, null);`);
}

{
  const cashier = fails(`select public.therapy_apply_recalculation(null, null, false, null);`,
                        s => sqlAs('cashier', s));
  ok('a cashier cannot recalculate expiry dates', cashier !== null && /Owner or Manager/.test(cashier));
  const cashierCal = fails(
    `select public.upsert_therapy_closure_date(null,'2026-07-01','company_closure','Sneaky',null,null,null,null,null,null);`,
    s => sqlAs('cashier', s));
  ok('a cashier cannot edit the holiday calendar', cashierCal !== null && /Owner or Manager/.test(cashierCal));
  // RLS cannot be demonstrated from this harness — it connects as the database
  // owner, who bypasses every policy. What IS checkable, and is the actual
  // guarantee, is that no write policy exists: with RLS enabled and only a
  // select policy, a direct insert by any ordinary role has nothing to permit it.
  const writePolicies = sql(`select count(*) from pg_policies
                              where tablename = 'therapy_closure_dates' and cmd <> 'SELECT';`);
  const rlsOn = sql(`select relrowsecurity from pg_class where oid = 'public.therapy_closure_dates'::regclass;`);
  ok('the calendar has row-level security on and no write policy, so writes must go through the functions',
     rlsOn === 't' && writePolicies === '0', `rls=${rlsOn} write policies=${writePolicies}`);
}

// =============================================================================
// A phone change must not move an activated entitlement
// =============================================================================
{
  const e = purchased(A, 1, 'active', '2026-01-05', '2026-02-06', 'SG');
  sql(`update public.customers set phone = '+60123456789' where id = '${A}';`);
  const after = sql(`select expiry_date || '|' || coalesce(holiday_country,'-')
                       from public.purchased_therapy_entitlements where id='${e}';`);
  ok('changing a phone number does not move an activated entitlement', after === '2026-02-06|SG', after);
  sql(`update public.customers set phone = '+6591110001' where id = '${A}';`);
}

// =============================================================================
// Consecutive packages
// =============================================================================
{
  // Activation refuses a date in the past, so these dates are relative to the
  // database's own today rather than fixed — a test that only passes in a
  // particular month is a test that stops passing.
  const today = sql(`select public.sg_today();`);
  const day = n => sql(`select ('${today}'::date + ${n})::text;`);
  const runningUntil = day(30);

  sql(`delete from public.purchased_therapy_entitlements;`);
  purchased(A, 1, 'active', day(-5), runningUntil, 'SG');

  const next = json(`select public.therapy_next_available_start('${A}', '${today}');`);
  ok('a second package is suggested for the day after the adjusted expiry',
     next.suggested_start === day(31) && next.would_overlap_if_started_today === true,
     `${next.suggested_start} (existing runs to ${runningUntil})`);
  ok('and the JS agrees',
     nextConsecutiveStart([runningUntil], today) === next.suggested_start);

  const p2 = purchased(A, 1, 'pending_activation', null, null, 'SG');
  const blocked = json(`select public.activate_purchased_therapy('${p2}', '${day(10)}', 'test');`);
  ok('activating into an existing period is not done by accident',
     blocked.activated === false && blocked.requires_confirmation === true
       && blocked.suggested_start === day(31), JSON.stringify(blocked).slice(0, 100));
  ok('and the refused activation changed nothing',
     sql(`select status from public.purchased_therapy_entitlements where id='${p2}';`) === 'pending_activation');

  const allowed = json(`select public.activate_purchased_therapy('${p2}', '${day(31)}', 'test', 'SG');`);
  const expectedBase = sql(`select public.therapy_expiry('${day(31)}'::date, 1);`);
  ok('activating after the predecessor works, on the one calendar-month convention',
     allowed.activated === true && allowed.base_expiry === expectedBase,
     `base ${allowed.base_expiry}, expected ${expectedBase}`);
  ok('and its expiry is never earlier than its base — closures only ever add',
     allowed.expiry_date >= allowed.base_expiry);

  const overlap = purchased(A, 1, 'pending_activation', null, null, 'SG');
  const forced = json(`select public.activate_purchased_therapy('${overlap}', '${day(10)}', 'deliberate', 'SG', null, true);`);
  ok('a deliberate overlap is allowed and recorded as one',
     forced.activated === true && forced.overlapped === true);

  const recon = sql(`select count(*) from public.therapy_successor_reconciliation();`);
  ok('a successor that is not consecutive is listed for review', Number(recon) >= 1, `${recon} rows`);
}

// =============================================================================
// Reward choices
// =============================================================================
{
  sql(`insert into public.therapy_package_rules (name, store_id, qualifying_amount, entitlement_kind, duration_months, voucher_qty, applies_to, tier_key) values
    ('1 Month Unlimited (Customer)','${STORE}', 994,'unlimited',1,null,'customer','customer:994.00:${STORE}'),
    ('10 Therapy Vouchers (Customer)','${STORE}', 994,'voucher',null,10,'customer','customer:994.00:${STORE}'),
    ('10 Therapy Vouchers (Affiliate)','${STORE}', 994,'voucher',null,10,'affiliate','affiliate:994.00:${STORE}');`);

  const ent = (no, amount, earner) =>
    sql(`insert into public.therapy_entitlements
          (entitlement_no, customer_id, store_id, package_name, entitlement_kind, duration_months,
           qualifying_amount, qualified_value, earner_kind, status, activation_deadline)
         values ('${no}','${B}','${STORE}','1 Month Unlimited','unlimited',1,${amount},${amount},
                 '${earner}','pending_activation','2027-12-31') returning id;`);

  const hist = ent('H794', 794, 'customer');
  const curr = ent('C994', 994, 'customer');
  const aff  = ent('A994', 994, 'affiliate');

  ok('a current entitlement offers both alternatives',
     sql(`select count(*) from public.legacy_reward_options('${curr}');`) === '2');
  // A threshold change must not take back what was already earned. This
  // entitlement has no rule to trace, so only its own snapshot is offered — but
  // it IS offered, and it can be claimed.
  const histOpts = json(`select jsonb_agg(to_jsonb(o)) from public.legacy_reward_options('${hist}') o;`);
  ok('a historical S$794 entitlement is still claimable as what it was granted',
     histOpts.length === 1 && histOpts[0].is_entitlement_snapshot === true
       && histOpts[0].entitlement_kind === 'unlimited' && histOpts[0].rule_id === null,
     JSON.stringify(histOpts.map(o => `${o.entitlement_kind}/${o.availability}`)));

  const diag = json(`select public.legacy_reward_options_diagnostic('${hist}');`);
  ok('and the diagnostic says it is claimable but has no alternative to choose',
     diag.claimable === true && diag.configured_option_count === 0 && diag.has_choice === false
       && /S\$794/.test(JSON.stringify(diag.reasons)), JSON.stringify(diag.reasons).slice(0, 110));

  const affDiag = json(`select public.legacy_reward_options_diagnostic('${aff}');`);
  ok('an affiliate with only a voucher rule configured is still told which rule to add',
     /add an affiliate rule/.test(JSON.stringify(affDiag.reasons)),
     JSON.stringify(affDiag.configured_option_kinds));

  // The case the owner actually hits: the SAME rules, threshold raised. rule_id
  // still points at them, so both alternatives come back with nothing to configure.
  {
    // The reward voucher has to exist before anything can be claimed with it.
    sql(`insert into public.vouchers (id, name, voucher_kind, code, reward_eligible, qty_type)
         values ('55555555-5555-5555-5555-555555555555','Therapy Session','normal','TS',true,'unlimited')
         on conflict do nothing;`);

    const traced = sql(`insert into public.therapy_entitlements
      (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
       duration_months, qualifying_amount, qualified_value, earner_kind, status, activation_deadline)
      values ('T794','${B}','${STORE}',
              (select id from public.therapy_package_rules where name='1 Month Unlimited (Customer)'),
              '1 Month Unlimited','unlimited',1, 794, 794,'customer','pending_activation','2027-12-31')
      returning id;`);
    const opts = json(`select jsonb_agg(to_jsonb(o)) from public.legacy_reward_options('${traced}') o;`);
    ok('an entitlement earned under a threshold that was later raised keeps BOTH alternatives',
       opts.length === 2 && opts.every(o => o.is_entitlement_snapshot === false)
         && opts.map(o => o.entitlement_kind).sort().join(',') === 'unlimited,voucher',
       JSON.stringify(opts.map(o => `${o.entitlement_kind}/${o.availability}`)));
    ok('and no manual mapping was needed to get there',
       sql(`select coalesce(reward_tier_key, '(none)') from public.therapy_entitlements
             where id = '${traced}';`) === '(none)');

    // Retired alternatives from the earned tier are still offered, labelled.
    sql(`update public.therapy_package_rules set is_active = false
          where name = '10 Therapy Vouchers (Customer)';`);
    const retired = json(`select jsonb_agg(to_jsonb(o)) from public.legacy_reward_options('${traced}') o;`);
    ok('a retired alternative from that tier is still offered, flagged as no longer current',
       retired.length === 2 && retired.some(o => o.availability === 'retired'),
       JSON.stringify(retired.map(o => `${o.entitlement_kind}/${o.availability}`)));
    sql(`update public.therapy_package_rules set is_active = true
          where name = '10 Therapy Vouchers (Customer)';`);

    // And it can actually be claimed as the alternative it was denied before.
    const claimedAlt = json(`select public.claim_legacy_therapy('${traced}', null,
      (select id from public.therapy_package_rules where name='10 Therapy Vouchers (Customer)'),
      '[{"voucher_id":"55555555-5555-5555-5555-555555555555","quantity":10}]'::jsonb);`);
    ok('a S$794 entitlement can be claimed as the voucher alternative it was earned with',
       claimedAlt.kind === 'voucher' && claimedAlt.issued_vouchers[0].quantity === 10);
    ok('and its qualifying amount is still S$794 — history is not rewritten',
       sql(`select qualifying_amount from public.therapy_entitlements where id='${traced}';`) === '794.00');
  }

  // An entitlement with no rule and no matching amount is claimable from its
  // snapshot, with no rule passed at all.
  {
    const orphan = sql(`insert into public.therapy_entitlements
      (entitlement_no, customer_id, store_id, package_name, entitlement_kind, duration_months,
       qualifying_amount, qualified_value, earner_kind, status, activation_deadline)
      values ('ORPH','${B}','${STORE}','1 Month Unlimited','unlimited',1, 594, 594,
              'customer','pending_activation','2027-12-31') returning id;`);
    const res = json(`select public.claim_legacy_therapy('${orphan}', public.sg_today(), null, null, 'SG');`);
    ok('an entitlement whose originating rule is gone entirely can still be claimed',
       res.success === true && res.kind === 'unlimited' && res.status === 'active',
       `${res.status} to ${res.expiry_date}`);
  }

  const noReason = fails(`select public.therapy_map_entitlement_tier('${hist}','customer:994.00:${STORE}','');`,
                         s => sqlAs('owner', s));
  ok('mapping a historical entitlement without a reason is refused',
     noReason !== null && /requires a reason/.test(noReason));

  const asCashier = fails(`select public.therapy_map_entitlement_tier('${hist}','customer:994.00:${STORE}','x');`,
                          s => sqlAs('cashier', s));
  ok('and a cashier cannot map one at all', asCashier !== null && /Owner or Manager/.test(asCashier));

  sqlAs('owner', `select public.therapy_map_entitlement_tier('${hist}','customer:994.00:${STORE}',
                    'Confirmed against the 2024 promotion sheet');`);
  ok('once mapped, the historical entitlement has a real choice',
     sql(`select count(*) from public.legacy_reward_options('${hist}');`) === '2');
  ok('and its qualifying amount is untouched — history is not rewritten',
     sql(`select qualifying_amount from public.therapy_entitlements where id='${hist}';`) === '794.00');

  sql(`insert into public.therapy_package_rules (name, store_id, qualifying_amount, entitlement_kind, duration_months, applies_to, tier_key)
       values ('1 Month Unlimited (Affiliate)','${STORE}', 994,'unlimited',1,'affiliate','affiliate:994.00:${STORE}');`);
  ok('an affiliate can choose either reward once both are configured',
     sql(`select count(*) from public.legacy_reward_options('${aff}');`) === '2');

  // Claiming
  sql(`insert into public.vouchers (id, name, voucher_kind, code, reward_eligible, qty_type)
       values ('55555555-5555-5555-5555-555555555555','Therapy Session','normal','TS',true,'unlimited')
       on conflict do nothing;`);
  const voucherRule = sql(`select id from public.therapy_package_rules
                            where name='10 Therapy Vouchers (Customer)';`);
  const unlimitedRule = sql(`select id from public.therapy_package_rules
                              where name='1 Month Unlimited (Customer)';`);

  const wrongQty = fails(`select public.claim_legacy_therapy('${curr}', null, '${voucherRule}',
    '[{"voucher_id":"55555555-5555-5555-5555-555555555555","quantity":7}]'::jsonb);`);
  ok('a voucher claim must add up to the entitled quantity',
     wrongQty !== null && /exactly 10/.test(wrongQty));

  const claimed = json(`select public.claim_legacy_therapy('${curr}', null, '${voucherRule}',
    '[{"voucher_id":"55555555-5555-5555-5555-555555555555","quantity":10}]'::jsonb);`);
  ok('claiming vouchers issues them and starts no therapy period',
     claimed.kind === 'voucher' && claimed.expiry_date === null
       && claimed.issued_vouchers.length === 1 && claimed.issued_vouchers[0].quantity === 10,
     JSON.stringify(claimed.issued_vouchers));
  ok('the confirmation reports what the database actually wrote',
     sql(`select coalesce(sum(quantity),0) from public.customer_reward_vouchers
           where entitlement_id='${curr}';`) === '10');

  const twice = fails(`select public.claim_legacy_therapy('${curr}', null, '${unlimitedRule}', null);`);
  ok('the same unit cannot then be claimed as unlimited therapy as well',
     twice !== null && /Only an unclaimed entitlement/.test(twice));

  const foreign = sql(`insert into public.therapy_package_rules
    (name, store_id, qualifying_amount, entitlement_kind, duration_months, applies_to, tier_key)
    values ('Other tier','${STORE}', 1500,'unlimited',3,'customer','customer:1500.00:${STORE}') returning id;`);
  const wrongTier = fails(`select public.claim_legacy_therapy('${hist}', null, '${foreign}', null);`);
  ok('a reward from another tier cannot be claimed',
     wrongTier !== null && /not an alternative/.test(wrongTier));

  // A claim date must not be in the past, so the closure is placed relative to
  // today and the expected answer is derived, not written down.
  const today = sql(`select public.sg_today();`);
  const start = sql(`select ('${today}'::date + 3)::text;`);
  const holiday = sql(`select ('${today}'::date + 10)::text;`);
  // Move it off a Sunday, which would correctly earn nothing.
  const eligible = sql(`select case when extract(dow from '${holiday}'::date) = 0
                                    then ('${holiday}'::date + 1)::text else '${holiday}' end;`);
  closure(eligible, 'public_holiday', 'Claim-path holiday');
  const wantBase = sql(`select public.therapy_expiry('${start}'::date, 1);`);

  const unlim = json(`select public.claim_legacy_therapy('${hist}', '${start}', '${unlimitedRule}', null, 'SG');`);
  ok('a Legacy unlimited claim gets the closure extension too, on the Legacy convention',
     unlim.kind === 'unlimited' && unlim.base_expiry === wantBase
       && unlim.closure_days_added >= 1 && unlim.expiry_date > unlim.base_expiry,
     `base ${unlim.base_expiry} (expected ${wantBase}) -> ${unlim.expiry_date} (+${unlim.closure_days_added})`);
  ok('and the claim stored the country it was calculated with',
     sql(`select holiday_country || '|' || closure_days_added
            from public.therapy_entitlements where id='${hist}';`) === `SG|${unlim.closure_days_added}`);
}

// =============================================================================
// Customer summaries
// =============================================================================
{
  sql(`insert into public.vouchers (id, name, voucher_kind, code)
       values ('66666666-6666-6666-6666-666666666666','$20 Off','fixed_discount','D20')
       on conflict do nothing;`);
  sql(`insert into public.customer_reward_vouchers (customer_id, voucher_id, store_id, quantity, status, source_type) values
    ('${B}','55555555-5555-5555-5555-555555555555','${STORE}', 3,'redeemed','legacy_entitlement'),
    ('${B}','55555555-5555-5555-5555-555555555555','${STORE}', 2,'held','premium_bundle'),
    ('${B}','55555555-5555-5555-5555-555555555555','${STORE}', 1,'revoked','premium_bundle'),
    ('${B}','66666666-6666-6666-6666-666666666666','${STORE}', 4,'held','promotion');`);
  // A redemption record for the same use. Counting both would double count.
  sql(`insert into public.voucher_redemptions (voucher_id, customer_id, discount_applied)
       values ('55555555-5555-5555-5555-555555555555','${B}', 0);`);

  const row = json(`select to_jsonb(s) from public.therapy_customer_summary(null, 50, 0, false) s
                     where s.customer_id = '${B}';`);
  // Derived from the table rather than written down: earlier tests in this file
  // claim rewards for the same customer, and a hardcoded total would only be
  // testing that nobody added a row above.
  const want = json(`select jsonb_build_object(
      'issued',   coalesce(sum(crv.quantity) filter (where v.voucher_kind = 'normal'), 0),
      'redeemed', coalesce(sum(crv.quantity) filter (where v.voucher_kind = 'normal' and crv.status = 'redeemed'), 0),
      'held',     coalesce(sum(crv.quantity) filter (where v.voucher_kind = 'normal' and crv.status = 'held'), 0),
      'money',    coalesce(sum(crv.quantity) filter (where v.voucher_kind <> 'normal' and crv.status = 'held'), 0),
      'redemption_rows', (select count(*) from public.voucher_redemptions where customer_id = '${B}'))
    from public.customer_reward_vouchers crv
    join public.vouchers v on v.id = crv.voucher_id
   where crv.customer_id = '${B}';`);
  ok('the balance comes from the issued rows, and a redemption record is not counted twice',
     row.therapy_vouchers_issued === want.issued && row.therapy_vouchers_redeemed === want.redeemed
       && row.therapy_vouchers_remaining === want.held && want.redemption_rows > 0,
     `issued=${row.therapy_vouchers_issued}/${want.issued} redeemed=${row.therapy_vouchers_redeemed}/${want.redeemed} `
     + `remaining=${row.therapy_vouchers_remaining}/${want.held}, with ${want.redemption_rows} redemption record(s) present`);
  ok('money-off vouchers are counted in their own unit, not added to sessions',
     row.money_vouchers_remaining === want.money && row.therapy_vouchers_remaining === want.held
       && want.money !== want.held);
  ok('revoked vouchers are shown separately and are not spendable',
     row.vouchers_revoked === 1);

  const detail = json(`select public.therapy_customer_detail('${B}');`);
  const sessions = detail.vouchers.filter(v => v.unit === 'session');
  ok('every voucher line names where it came from',
     sessions.length >= 2 && sessions.every(v => v.source && v.source !== 'Source not recorded'),
     sessions.map(v => `${v.source}:${v.remaining}`).join(', '));
  ok('and the lines add up to the summary — one grant per line, nothing lost or doubled',
     sessions.reduce((n, v) => n + v.remaining, 0) === row.therapy_vouchers_remaining
       && sessions.reduce((n, v) => n + v.issued, 0) === row.therapy_vouchers_issued,
     `lines total ${sessions.reduce((n, v) => n + v.remaining, 0)}, summary says ${row.therapy_vouchers_remaining}`);
  ok('and lists redemption history without adding it to the balance',
     detail.redemptions.length === 1 && detail.revocations.length === 1);
  ok('an entitlement is shown as the source of its vouchers, not as a second balance',
     detail.unlimited.every(u => u.kind === 'purchased' || u.kind === 'legacy'));

  // Two people, one phone number.
  sql(`insert into public.customer_reward_vouchers (customer_id, voucher_id, store_id, quantity, status, source_type)
       values ('${SHARED1}','55555555-5555-5555-5555-555555555555','${STORE}', 5,'held','promotion'),
              ('${SHARED2}','55555555-5555-5555-5555-555555555555','${STORE}', 8,'held','promotion');`);
  const shared = json(`select jsonb_agg(jsonb_build_object('id', s.customer_id, 'n', s.therapy_vouchers_remaining))
                         from public.therapy_customer_summary('+6598887777', 50, 0, false) s;`);
  ok('two customers sharing a phone number stay separate',
     shared.length === 2 && shared.map(x => x.n).sort().join(',') === '5,8',
     JSON.stringify(shared.map(x => x.n)));

  // Pagination must not change any total.
  const page = json(`select jsonb_agg(jsonb_build_object('n', s.therapy_vouchers_remaining, 't', s.total_customers))
                       from public.therapy_customer_summary(null, 1, 0, false) s;`);
  const all = json(`select jsonb_agg(jsonb_build_object('n', s.therapy_vouchers_remaining))
                      from public.therapy_customer_summary(null, 500, 0, false) s;`);
  ok('a page limit changes which customers are listed, never their totals',
     page.length === 1 && page[0].t === all.length
       && all.find(x => x.n === page[0].n) !== undefined,
     `page says ${page[0].t} customers, full list has ${all.length}`);

  const days = sql(`select current_unlimited_days_remaining from public.therapy_customer_summary(null,500,0,false)
                     where customer_id='${A}' and current_unlimited_expiry is not null;`);
  if (days !== '') {
    const expiry = sql(`select current_unlimited_expiry from public.therapy_customer_summary(null,500,0,false)
                         where customer_id='${A}';`);
    const today = sql(`select public.sg_today();`);
    ok('calendar days remaining is inclusive and matches the JS',
       Number(days) === calendarDaysRemaining(expiry, today), `sql=${days} js=${calendarDaysRemaining(expiry, today)}`);
  }
}

console.log(`\n${pass} checks passed.`);
