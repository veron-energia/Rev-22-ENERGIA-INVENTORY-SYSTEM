-- 414_affiliate_deduction_settlements.sql
--
-- WHAT WAS WRONG
--
--   Since 410 (live 9 Oct 2026) an affiliate whose commission was paid out
--   and then taken back carries a deduction, recovered from their later
--   commission. The Commissions page says "Affiliate owes S$X back; recovered
--   from later commission first." There was no way to record that such a debt
--   was settled some other way: paid back, written off, or taken off a payment
--   made outside the app. On production on 9 Oct 2026 one affiliate owed
--   S$555.27 (September: earned 1705.59, adjustments -991.64, paid 1276.30,
--   balance -562.35; October: earned 100.80, paid 93.72, balance 7.08). The
--   Owner says it was settled outside the app; the app kept asking for it.
--
--   Separately, the Dashboard's "Unpaid commission" added up the commission
--   rows marked earned (S$96.62 on production, 9 Oct 2026). That took one
--   affiliate's take-backs off everyone else's commission and left out the
--   unpaid part of rows paid out in part, so it agreed with no other page
--   (what affiliates are owed, each one's months netted: S$737.03).
--
-- THE RULES (the Owner, 9 Oct 2026)
--
--   1. The S$555.27 was settled outside the app (taken off a payment to the
--      affiliate that the app did not record). It is recorded as settled;
--      afterwards that affiliate owes nothing and is owed nothing. October's
--      S$7.08 stays counted against the debt. (Recorded by
--      scripts/commissions/repair/414-settle-a79499b7.sql, not here.)
--   2. "Mark as settled", for the future, for Owners and Managers (the roles
--      that record payouts). How it was settled: "Paid back to us", "Written
--      off" or "Paid off outside the app"; the amount (at first, and at most,
--      the deduction still owed; above 0); the date it was settled (Singapore,
--      not in the future); a note (required).
--   3. The commission take-backs and the payouts are never deleted or changed:
--      a settlement is its own dated, audited record. A mistaken one is undone
--      by an Owner or Manager with a reason (a void, not a delete), also
--      audited.
--   4. The affiliate's portal shows the amount settled ("Deduction
--      settled"), never the note, the method or who recorded it (the Owner,
--      9 Oct 2026).
--   5. A settlement is matched to the months still owed back, oldest first,
--      each time it is read. A later correction in an older month may move
--      the per-month figures, never the totals (accepted by the Owner, 9 Oct
--      2026).
--   6. If a take-back is lowered after a settlement, the extra is held under
--      review and nothing is paid against it until the Owner decides (the
--      Owner, 9 Oct 2026: left as it is for now).
--
-- WHAT THIS DOES
--
--   * affiliate_deduction_settlements (new table): one row per settlement:
--     the affiliate, the amount, the date it was settled, how, the note, who
--     recorded it and when, the request id (a retry records it once), and,
--     once voided, when, by whom and why. Row level security on, no rules; no
--     client role may touch it (339); the service role may read it. A trigger
--     refuses deleting a settlement and changing one, except voiding it once
--     and the affiliate it belongs to (merging two customer records moves it
--     with the person, as their payouts move).
--   * affiliate_month_balances() (replaced; one column added at the end,
--     settled): an affiliate's settlements count against the months they owe
--     back on, oldest first, each up to what that month is below zero, so a
--     month's balance (earned + adjustments - paid + settled) is never raised
--     above zero by a settlement and every positive month is still commission
--     a payout can be allocated to. The months a settlement is shown against
--     are worked out each time it is read, so they can change when a later
--     correction lands in an older month (a take-back dated in August, after
--     a settlement of 9 Oct, takes part of it to August); what the affiliate
--     owes or is owed in all, what is payable and the payout caps do not. The
--     page says so. What settlements come to beyond what the months now owe
--     back (only possible after a later correction lowers a take-back) is
--     shown in the month of the latest settlement, flagged for review ("...
--     Review with the Owner before recording a payout for this month."), so it
--     is never offered as payable and no payout is recorded against it. With
--     no settlement every row is exactly as before. Every figure built on it
--     follows: what an affiliate is owed or owes back
--     (affiliate_referrer_balances, unchanged), the payout cap
--     (affiliate_payout_save), the Commissions page, the Referrers tab and its
--     detail, the Affiliates page, the portal.
--     (Counting a settlement in the month it was settled, as first proposed,
--     would raise that month above the commission behind it: on production,
--     October would show S$562.35, and the next commission would be offered
--     against October, where Record payout cannot allocate it.)
--   * affiliate_deduction_settlement_record(...) (new; internal, the service
--     role's alone): rule 2's checks, for a named Owner or Manager: under
--     the payouts' lock (payouts and commission changes take it too) and a
--     row lock on the affiliate, the amount may not be more than the
--     deduction owed then, so two clicks cannot both pass; the date may not be
--     after today in Singapore, before 1 Jan 2020, or before the affiliate's
--     first payout (a deduction cannot be settled before the payout that made
--     it); a request id already used returns its first answer. Audited
--     (audit_logs, affiliate_deduction_settled).
--   * affiliate_deduction_settlement_void(...) (new; internal): the void, for
--     a named Owner or Manager, with a reason; idempotent on its request id.
--     Audited (affiliate_deduction_settlement_voided).
--   * record_affiliate_deduction_settlement(...) and
--     void_affiliate_deduction_settlement(...) (new; for signed-in staff): the
--     page's two actions. First statement require_active_staff('{owner,
--     manager}') (406), then the internal function as the caller.
--   * affiliate_payout_overview() (patched): adds 'settlements', every
--     settlement (voided ones too) with who recorded or voided it, newest
--     first. Every key it sent is still sent; each month in 'groups' also
--     carries 'settled'.
--   * affiliate_portal_earnings() (patched): unpaid and deduction count the
--     settlements, and the summary carries 'settled' (the amount only; never
--     the note, how it was settled or who recorded it).
--     affiliate_portal_dashboard passes the summary on unchanged.
--   * referrer_earnings(uuid) (patched): the lifetime figures and each month
--     also carry 'settled'.
--   * report_affiliates() (replaced; one column added at the end, settled):
--     the Reports page's Commission tab works Outstanding and Deduction to
--     recover out with it.
--   * dashboard_summary() (patched): adds 'unpaid_commission' (every
--     affiliate's unpaid, as the Commissions page nets it) and
--     'commission_deductions' (what is still to be recovered). The Dashboard
--     shows the first as "Unpaid commission".
--   * affiliate_payout_save(...) (patched; record_ and correct_affiliate_payout
--     reach it): a payout that adds to a month the month balances put under
--     review is refused with that review, as the page already disables Record
--     payout there. Before, it read only affiliate_payout_review and the
--     month's balance, so a month holding settlements beyond what is now owed
--     back could still be paid through the API. Lowering a payout is not
--     affected. Everything else in it is as 410 left it.
--
-- NOT CHANGED
--
--   * No commission row, take-back, payout or allocation is written or
--     changed, and no settlement is recorded here.
--   * affiliate_referrer_balances, record_ and correct_affiliate_payout
--     (they call affiliate_payout_save), affiliate_payout_review, referrer_list,
--     affiliate_directory, affiliate_admin_directory,
--     affiliate_portal_dashboard, affiliate_portal_payouts (the portal's
--     payouts list), reconcile_invoice_commissions and every rule of earning
--     or taking back. Those that read affiliate_month_balances or
--     affiliate_referrer_balances count the settlements through them.
--   * Staff commission.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. The
--   definitions are read and compared with the search path set to public.
--   Each changed function must be the production version read on 9 Oct 2026
--   (BEFORE) or already this migration's (AFTER), which is left alone, so a
--   re-run changes nothing; each new function and the table must be missing
--   or already exactly this version, and all of them in or none; no other
--   function takes any of these names. The functions relied on must be the
--   versions read on 9 Oct 2026, and the columns read of profiles, customers,
--   audit_logs and commission_payouts must be there. Every anchor must match
--   exactly once, and every text built is checked against its AFTER md5
--   before anything is installed. Patched functions are installed with
--   CREATE OR REPLACE, which keeps their grants. affiliate_month_balances and
--   report_affiliates gain a column, which CREATE OR REPLACE cannot do: they
--   are dropped and created again in the same statement (nothing depends on
--   them in the catalogue; the functions that call them name them in their
--   text) and given back exactly the grants they had, checked after. The new
--   internal functions are revoked from public, anon and authenticated and
--   granted to the service role; the two page functions are granted to
--   authenticated and the service role, not anon. Afterwards every md5,
--   grant, the table, its rules and its trigger are as tested; then, switching
--   role and inside a block that is always undone, a made-up Owner settles
--   part of a made-up affiliate's deduction and voids it, the figures follow,
--   and Staff, a login with no profile and the anon key are refused. Nothing
--   is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   changed
--   affiliate_month_balances()                    2860675d40499f788036b76be3094702
--   affiliate_payout_overview()                   9a1c584766b2aaefb07012895932c0c8  (410's AFTER)
--   affiliate_portal_earnings()                   248af74df2f705e43ee110dbaaf4f6fa  (410's AFTER)
--   referrer_earnings(uuid)                       b74826ed6ccfbc82cff8258b0678ec12
--   report_affiliates()                           f1215960b13d75026fd2f4a3464af0cb
--   dashboard_summary()                           96ddc8f96a9bb00a222f11860d2ac221  (406's AFTER)
--   affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)
--                                                 59707475f768cbd500a47912524bd947  (410's AFTER)
--   new (missing): affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid),
--     affiliate_deduction_settlement_void(uuid,text,uuid,uuid),
--     record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid),
--     void_affiliate_deduction_settlement(uuid,text,uuid),
--     trg_affiliate_deduction_settlement_guard(), table affiliate_deduction_settlements
--   relied on, not changed
--   affiliate_referrer_balances()                 54ef098ba8f9e3d81bb45906c4607ab6  (410's AFTER)
--   affiliate_payout_review(uuid,date)            b8e330efcb88277f965f67386406e0a4
--   affiliate_payout_access(boolean)              90b7399378a7604afd4af97c059d0703
--   affiliate_payout_lock()                       c410a35592ecae0ec9af516e5595f272
--   commission_reporting_rows()                   96962fa272f3eb35111c6ac199255410
--   affiliate_directory()                         308a1721fce357e9aede2d4d9b06a6af
--   current_affiliate_customer_id()               51695acf5f26ce3918d6003d0c980b0f
--   require_active_staff(text[])                  877b3aa74cea559881979bb161c450e2  (406's AFTER)
--   sg_today()                                    1c1289f18e24d8370e9a6364c9c06fca
--   public function fingerprint                   675ac22c631079b58f06813d0d463fa3
-- AFTER (for later guards):
--   affiliate_month_balances()                    84c0741e983c8f483d677353c732d891
--   affiliate_payout_overview()                   2da2a55dade2e16282c03ec3fc3b221d
--   affiliate_portal_earnings()                   adc91a9be47aff2d0c1bc60eb4834cef
--   referrer_earnings(uuid)                       f5fe44e5f1ffb14d895721698d6ad212
--   report_affiliates()                           84aa4032d794ecdd58e1ec4ae9b9adbc
--   dashboard_summary()                           d29c77f8ce2fda5e81b134bdced16dcc
--   affiliate_payout_save(...)                    dd2993318ffef5c8f60b1e8513ed1902
--   affiliate_deduction_settlement_record(...)    e0c89b33a3bb8e7d79cf6ccf67fd1e2b
--   affiliate_deduction_settlement_void(...)      b5d0a22532b8ab71677825643714734f
--   record_affiliate_deduction_settlement(...)    70976b9267b703dc4899b518f46f7ec9
--   void_affiliate_deduction_settlement(...)      6be0c40f6fbe4d6910e1fe749f733c0e
--   trg_affiliate_deduction_settlement_guard()    2d0f81e74105134faea2d26842f45a6b
--   public function fingerprint                   af220b17c3d38e0ac75375c31ed12f2b
--
-- DEPLOY ORDER: this, then (with the Owner's go-ahead) the repair script once
-- (scripts/commissions/repair/414-settle-a79499b7.sql), then the front end
-- (pushing to main deploys it). The pages live now keep working against
-- this: every key and column they read is still sent with the same value.
-- Between the repair and the new front end, the Commissions, Affiliates and
-- portal pages already show the settled deduction as gone; the Reports
-- page's Commission tab (which works its figures out itself and does not
-- know the new column) still shows it as Deduction to recover, and the
-- Dashboard keeps its old figure, until the new pages load. The new pages
-- against a database without this show no settlements and the Dashboard's
-- old figure, and Mark as settled would fail (the function is missing), so
-- this goes first.
--
-- Test: scripts/commissions/tests/deduction-settlement.sql (every figure
-- before and after a settlement and a void, the refusals, a retry, a re-run,
-- the guards, the grants), scripts/commissions/tests/settle-repair-414.sql
-- (the repair), scripts/commissions/tests/deduction-settlement-panel.test.mjs
-- and deduction-settlement-presentation.test.mjs (the page),
-- scripts/reports/tests/reports-page.test.mjs, and
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── affiliate_month_balances, replaced (a column added) ──────────────────
  c_balances_def constant text := $def$CREATE OR REPLACE FUNCTION public.affiliate_month_balances()
 RETURNS TABLE(referrer uuid, month date, earned numeric, adjustments numeric, paid numeric, balance numeric, tier1 numeric, tier2 numeric, review_reason text, settled numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 -- 414: each affiliate's commission by month (invoice paid date), as before,
 -- and the deductions they settled (affiliate_deduction_settlements, voided
 -- ones left out; the Owner, 9 Oct 2026). A settlement counts against the
 -- months the affiliate owes back on (balance below zero), oldest first, each
 -- up to what it is below zero: it never makes a month payable, so a month
 -- above zero is still commission a payout can be allocated to. The months a
 -- settlement is shown against are worked out each time, so they can change
 -- when a later correction lands in an older month; what the affiliate owes
 -- or is owed in all does not. What the settlements come to beyond what the
 -- months now owe back (a later correction lowered a take-back) is shown in
 -- the month of the latest settlement, under review, so it is never paid out
 -- (affiliate_payout_save refuses a payout there too). With no settlement
 -- every row is as before 414.
 --   balance  earned + adjustments - paid + settled
 --   settled  what of the affiliate's settlements this month takes
 with c as(select referrer_customer_id referrer,date_trunc('month',invoice_paid_date)::date as month,
  coalesce(sum(commission_amount) filter(where commission_amount>=0),0) earned,
  coalesce(sum(commission_amount) filter(where commission_amount<0),0) adjustments,
  coalesce(sum(commission_amount) filter(where tier='tier1'),0) tier1,coalesce(sum(commission_amount) filter(where tier='tier2'),0) tier2
  from public.commissions where status in ('earned','paid') group by 1,2),
 p as(select referrer_customer_id referrer,payout_month as month,sum(total_amount) paid from public.commission_payouts where status='paid' group by 1,2),
 m as(select coalesce(c.referrer,p.referrer) referrer,coalesce(c.month,p.month) as month,coalesce(c.earned,0) earned,coalesce(c.adjustments,0) adjustments,
  coalesce(p.paid,0) paid,coalesce(c.tier1,0) tier1,coalesce(c.tier2,0) tier2
  from c full join p using(referrer,month)),
 s as(select st.referrer_customer_id referrer,sum(st.amount) total,date_trunc('month',max(st.settled_on))::date last_month
  from public.affiliate_deduction_settlements st where st.voided_at is null group by 1),
 l as(select s.referrer,s.total,s.last_month,
  greatest(s.total-coalesce((select sum(greatest(m.paid-m.earned-m.adjustments,0)) from m where m.referrer=s.referrer),0),0) leftover
  from s),
 a as(select m.* from m
  union all
  select l.referrer,l.last_month,0,0,0,0,0 from l
   where l.leftover>0 and not exists(select 1 from m where m.referrer=l.referrer and m.month=l.last_month)),
 x as(select a.*,a.earned+a.adjustments-a.paid net,
  least(greatest(a.paid-a.earned-a.adjustments,0),
        greatest(coalesce(l.total,0)-coalesce(sum(greatest(a.paid-a.earned-a.adjustments,0))
          over(partition by a.referrer order by a.month nulls last,a.earned,a.paid rows between unbounded preceding and 1 preceding),0),0))
  +case when a.month=l.last_month then l.leftover else 0 end settled,
  coalesce(a.month=l.last_month and l.leftover>0,false) over_settled,l.leftover
  from a left join l using(referrer))
 select x.referrer,x.month,x.earned,x.adjustments,x.paid,x.net+x.settled,x.tier1,x.tier2,
  case when x.month is null then 'Commission date is missing. Review the original invoice before recording a payout.'
   when x.over_settled then 'Deductions marked as settled come to S$'||to_char(x.leftover,'FM999999990.00')
    ||' more than this affiliate now owes back. Review with the Owner before recording a payout for this month.'
   else public.affiliate_payout_review(x.referrer,x.month) end,
  x.settled
 from x
$function$
$def$;

  -- ── New: a settlement recorded, for a named Owner or Manager ─────────────
  c_record_def constant text := $def$CREATE OR REPLACE FUNCTION public.affiliate_deduction_settlement_record(p_referrer uuid, p_amount numeric, p_settled_on date, p_method text, p_note text, p_request_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text; v_note text := btrim(coalesce(p_note, '')); v_deduction numeric; v_first date;
  v_prior public.affiliate_deduction_settlements; v_row public.affiliate_deduction_settlements;
begin
  -- 414: an affiliate's deduction (commission paid out and then taken back,
  -- recovered from their later commission) marked as settled some other way:
  -- paid back to us, written off, or paid off outside the app (the Owner,
  -- 9 Oct 2026). A dated record of its own; the take-backs and payouts stay
  -- as they are. It counts against the affiliate's months through
  -- affiliate_month_balances. The page reaches this through
  -- record_affiliate_deduction_settlement, as the signed-in Owner or Manager;
  -- the server names one (p_actor).
  if p_request_id is null then
    raise exception 'A request identifier is required. Refresh and try again.'; end if;
  select p.role::text into v_role from public.profiles p
   where p.id = p_actor and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted';
  if v_role is null or v_role not in ('owner', 'manager') then
    raise exception 'Only active Owners and Managers can mark a deduction as settled.' using errcode = '42501'; end if;
  -- One at a time with payouts and commission changes, which move the
  -- deduction too (they take the same lock).
  perform public.affiliate_payout_lock();
  select * into v_prior from public.affiliate_deduction_settlements s where s.request_id = p_request_id;
  if found then
    if v_prior.referrer_customer_id is distinct from p_referrer or v_prior.amount is distinct from p_amount
       or v_prior.settled_on is distinct from p_settled_on or v_prior.method is distinct from p_method
       or v_prior.note is distinct from v_note or v_prior.created_by is distinct from p_actor then
      raise exception 'This request identifier was already used with different details. Refresh the payouts before trying again.'; end if;
    return jsonb_build_object('id', v_prior.id, 'referrer', v_prior.referrer_customer_id, 'amount', v_prior.amount,
                              'settled_on', v_prior.settled_on, 'method', v_prior.method);
  end if;
  if p_amount is null or p_amount::text in ('NaN', 'Infinity', '-Infinity') or p_amount <= 0
     or p_amount >= 10000000000 or round(p_amount, 2) <> p_amount then
    raise exception 'Enter an amount above S$0.00 with at most two decimal places.'; end if;
  if p_settled_on is null or p_settled_on > public.sg_today() then
    raise exception 'Enter the date it was settled. It cannot be after today in Singapore.'; end if;
  if p_settled_on < date '2020-01-01' then
    raise exception 'Enter the date it was settled. It cannot be before 1 Jan 2020.'; end if;
  if p_method is null or p_method not in ('paid_back', 'written_off', 'paid_outside_app') then
    raise exception 'Choose how it was settled: paid back to us, written off, or paid off outside the app.'; end if;
  if v_note = '' then
    raise exception 'A note is required: say how and why it was settled.'; end if;
  if char_length(v_note) > 2000 then
    raise exception 'The note is too long (2,000 characters at most).'; end if;
  perform 1 from public.customers c where c.id = p_referrer for no key update;
  if not found then
    raise exception 'Affiliate not found.'; end if;
  select r.deduction into v_deduction from public.affiliate_referrer_balances() r where r.referrer = p_referrer;
  v_deduction := coalesce(v_deduction, 0);
  if v_deduction <= 0 then
    raise exception 'This affiliate owes nothing back, so there is nothing to settle. Refresh the summary.'; end if;
  if p_amount > v_deduction then
    raise exception 'S$% is more than the S$% this affiliate owes back. Enter at most S$%.',
      to_char(p_amount, 'FM999999990.00'), to_char(v_deduction, 'FM999999990.00'), to_char(v_deduction, 'FM999999990.00'); end if;
  -- A deduction exists only after a payout to the affiliate, so it cannot
  -- have been settled before the first one (a mistyped date would otherwise
  -- show the settlement against a month with nothing in it).
  select min(p.payment_date) into v_first from public.commission_payouts p
   where p.referrer_customer_id = p_referrer and p.status = 'paid';
  if v_first is not null and p_settled_on < v_first then
    raise exception 'The date it was settled cannot be before the first payout to this affiliate, on %.',
      to_char(v_first, 'FMDD Mon YYYY'); end if;
  insert into public.affiliate_deduction_settlements
    (referrer_customer_id, amount, settled_on, method, note, created_by, request_id)
  values (p_referrer, p_amount, p_settled_on, p_method, v_note, p_actor, p_request_id)
  returning * into v_row;
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, reason)
  values ('affiliate_deduction_settlements', v_row.id, 'affiliate_deduction_settled',
          jsonb_build_object('deduction', v_deduction),
          to_jsonb(v_row) || jsonb_build_object('deduction_after', v_deduction - v_row.amount),
          p_actor, v_role, 'commissions', v_note);
  return jsonb_build_object('id', v_row.id, 'referrer', v_row.referrer_customer_id, 'amount', v_row.amount,
                            'settled_on', v_row.settled_on, 'method', v_row.method);
end
$function$
$def$;

  -- ── New: a settlement voided, for a named Owner or Manager ───────────────
  c_void_def constant text := $def$CREATE OR REPLACE FUNCTION public.affiliate_deduction_settlement_void(p_settlement_id uuid, p_reason text, p_request_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text; v_reason text := btrim(coalesce(p_reason, ''));
  v_old public.affiliate_deduction_settlements; v_row public.affiliate_deduction_settlements;
begin
  -- 414: a settlement recorded by mistake is voided, with a reason, never
  -- deleted (the Owner, 9 Oct 2026). It stays listed, marked void, and stops
  -- counting: the affiliate owes that part back again, recovered from their
  -- later commission. The page reaches this through
  -- void_affiliate_deduction_settlement; the server names the Owner or
  -- Manager (p_actor).
  if p_request_id is null then
    raise exception 'A request identifier is required. Refresh and try again.'; end if;
  select p.role::text into v_role from public.profiles p
   where p.id = p_actor and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted';
  if v_role is null or v_role not in ('owner', 'manager') then
    raise exception 'Only active Owners and Managers can void a settlement.' using errcode = '42501'; end if;
  perform public.affiliate_payout_lock();
  select * into v_old from public.affiliate_deduction_settlements s where s.id = p_settlement_id for update;
  if not found then
    raise exception 'Settlement not found. Refresh the payouts.'; end if;
  if v_old.voided_at is not null then
    if v_old.void_request_id = p_request_id and v_old.voided_by = p_actor and v_old.void_reason = v_reason then
      return jsonb_build_object('id', v_old.id, 'referrer', v_old.referrer_customer_id, 'amount', v_old.amount, 'voided', true);
    end if;
    raise exception 'This settlement was already voided. Refresh the payouts.'; end if;
  if exists (select 1 from public.affiliate_deduction_settlements s where s.void_request_id = p_request_id) then
    raise exception 'This request identifier was already used with different details. Refresh the payouts before trying again.'; end if;
  if v_reason = '' then
    raise exception 'A reason is required to void a settlement.'; end if;
  if char_length(v_reason) > 2000 then
    raise exception 'The reason is too long (2,000 characters at most).'; end if;
  update public.affiliate_deduction_settlements s
     set voided_at = now(), voided_by = p_actor, void_reason = v_reason, void_request_id = p_request_id
   where s.id = p_settlement_id
  returning * into v_row;
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, reason)
  values ('affiliate_deduction_settlements', v_row.id, 'affiliate_deduction_settlement_voided',
          to_jsonb(v_old), to_jsonb(v_row), p_actor, v_role, 'commissions', v_reason);
  return jsonb_build_object('id', v_row.id, 'referrer', v_row.referrer_customer_id, 'amount', v_row.amount, 'voided', true);
end
$function$
$def$;

  -- ── New: the page's two actions ──────────────────────────────────────────
  c_record_page_def constant text := $def$CREATE OR REPLACE FUNCTION public.record_affiliate_deduction_settlement(p_referrer_customer_id uuid, p_amount numeric, p_settled_on date, p_method text, p_note text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  -- 414: the Commissions page's "Mark as settled", as the signed-in Owner or
  -- Manager (affiliate_deduction_settlement_record holds the rules).
  if auth.uid() is null then
    raise exception 'Sign in as an Owner or Manager to mark a deduction as settled.' using errcode = '42501'; end if;
  return public.affiliate_deduction_settlement_record(p_referrer_customer_id, p_amount, p_settled_on, p_method,
                                                      p_note, p_request_id, auth.uid());
end
$function$
$def$;
  c_void_page_def constant text := $def$CREATE OR REPLACE FUNCTION public.void_affiliate_deduction_settlement(p_settlement_id uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  -- 414: the Commissions page's Void on a settlement, as the signed-in Owner
  -- or Manager (affiliate_deduction_settlement_void holds the rules).
  if auth.uid() is null then
    raise exception 'Sign in as an Owner or Manager to void a settlement.' using errcode = '42501'; end if;
  return public.affiliate_deduction_settlement_void(p_settlement_id, p_reason, p_request_id, auth.uid());
end
$function$
$def$;

  -- ── New: settlements are voided, never deleted or rewritten ──────────────
  c_guard_def constant text := $def$CREATE OR REPLACE FUNCTION public.trg_affiliate_deduction_settlement_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 414: a settlement is its own dated, audited record (the Owner, 9 Oct
  -- 2026). It is never deleted, and never changed but by voiding it once. The
  -- affiliate it belongs to may change: merging two customer records moves it
  -- with the person (merge_customer_records), as their payouts move.
  if tg_op = 'DELETE' then
    raise exception 'A deduction settlement is never deleted. Void it instead, with a reason.';
  end if;
  if (new.id, new.amount, new.settled_on, new.method, new.note, new.created_by, new.created_at, new.request_id)
     is distinct from (old.id, old.amount, old.settled_on, old.method, old.note, old.created_by, old.created_at, old.request_id) then
    raise exception 'A deduction settlement is not changed once recorded. Void it, with a reason, and record it again.';
  end if;
  if old.voided_at is not null
     and (new.voided_at, new.voided_by, new.void_reason, new.void_request_id)
         is distinct from (old.voided_at, old.voided_by, old.void_reason, old.void_request_id) then
    raise exception 'A voided deduction settlement stays voided.';
  end if;
  return new;
end
$function$
$def$;

  -- ── Patched: the overview lists the settlements ──────────────────────────
  c_overview_a constant text := $q$  'payouts',(select coalesce(jsonb_agg(to_jsonb(p)-'original_record' order by payment_date desc,created_at desc,id),'[]') from public.commission_payouts p),$q$;
  c_overview_r constant text := $q$  -- 414: deductions marked as settled, newest first; a voided one stays
  -- listed, marked void. Each month in 'groups' carries what it takes of them
  -- (settled).
  'settlements',(select coalesce(jsonb_agg(((to_jsonb(s)-'request_id')-'void_request_id')
     ||jsonb_build_object('created_by_name',cp.full_name,'voided_by_name',vp.full_name)
     order by s.settled_on desc,s.created_at desc,s.id),'[]')
   from public.affiliate_deduction_settlements s left join public.profiles cp on cp.id=s.created_by
   left join public.profiles vp on vp.id=s.voided_by),
  'payouts',(select coalesce(jsonb_agg(to_jsonb(p)-'original_record' order by payment_date desc,created_at desc,id),'[]') from public.commission_payouts p),$q$;

  -- ── Patched: the portal counts the settlements ───────────────────────────
  c_earn_decl_a constant text := $q$        v_unpaid numeric; v_paid numeric; v_reversed numeric; v_blocked numeric; v_lifetime numeric;$q$;
  c_earn_decl_r constant text := $q$        v_unpaid numeric; v_paid numeric; v_reversed numeric; v_blocked numeric; v_lifetime numeric;
        v_settled numeric;  -- 414: deductions settled$q$;
  c_earn_net_a constant text := $q$  v_unpaid:=v_lifetime-v_paid;$q$;
  c_earn_net_r constant text := $q$  -- 414: a deduction settled (paid back, written off, or taken off a payment
  -- outside the app) is recovered; a settlement voided is not.
  select coalesce(sum(s.amount),0) into v_settled from public.affiliate_deduction_settlements s
   where s.referrer_customer_id=v_me and s.voided_at is null;
  v_unpaid:=v_lifetime-v_paid+v_settled;$q$;
  c_earn_sum_a constant text := $q$      'deduction', greatest(-v_unpaid, 0), 'paid', v_paid,$q$;
  c_earn_sum_r constant text := $q$      'deduction', greatest(-v_unpaid, 0), 'paid', v_paid,
      'settled', v_settled,  -- 414: the amount only, never the note or how$q$;

  -- ── Patched: the Referrers tab's detail carries the settlements ──────────
  c_refearn_life_a constant text := $q$'total_earned',(select coalesce(sum(balance),0) from public.affiliate_month_balances() where referrer=p_customer_id));$q$;
  c_refearn_life_r constant text := $q$'total_earned',(select coalesce(sum(balance),0) from public.affiliate_month_balances() where referrer=p_customer_id),
    -- 414: deductions settled (paid back, written off, or taken off a payment outside the app).
    'settled',(select coalesce(sum(s.amount),0) from public.affiliate_deduction_settlements s where s.referrer_customer_id=p_customer_id and s.voided_at is null));$q$;
  c_refearn_month_a constant text := $q$'total',earned+adjustments,'review_reason',review_reason) order by month desc)$q$;
  c_refearn_month_r constant text := $q$'total',earned+adjustments,'review_reason',review_reason,'settled',settled) order by month desc)$q$;

  -- ── Replaced: the Reports page's affiliate rows carry the settlements ────
  c_report_ret_a constant text := $q$tier1_earned numeric, tier2_earned numeric)$q$;
  c_report_ret_r constant text := $q$tier1_earned numeric, tier2_earned numeric, settled numeric)$q$;
  c_report_col_a constant text := $q$and cm.tier = 'tier2' and cm.status in ('earned','paid')),0)
  from public.affiliate_directory() d$q$;
  c_report_col_r constant text := $q$and cm.tier = 'tier2' and cm.status in ('earned','paid')),0),
    -- 414: deductions settled (paid back, written off, or taken off a payment
    -- outside the app); the Commission tab counts them in Outstanding.
    coalesce((select sum(s.amount) from public.affiliate_deduction_settlements s where s.referrer_customer_id = d.customer_id and s.voided_at is null),0)
  from public.affiliate_directory() d$q$;

  -- ── Patched: the Dashboard's unpaid commission, as the Commissions page ──
  c_dash_a constant text := $q$  return v_out || jsonb_build_object('today_sales',$q$;
  c_dash_r constant text := $q$  -- 414: what affiliates are still owed, each one's months netted and never
  -- below 0 (affiliate_referrer_balances, as the Commissions page shows it),
  -- and what is still to be recovered from them.
  v_out := v_out || (select jsonb_build_object('unpaid_commission', coalesce(sum(r.unpaid), 0),
                                               'commission_deductions', coalesce(sum(r.deduction), 0))
                       from public.affiliate_referrer_balances() r);
  return v_out || jsonb_build_object('today_sales',$q$;

  -- ── Patched: no payout for a month under review in the month balances ───
  c_save_a constant text := $q$  select b.balance into available from public.affiliate_month_balances() b where b.referrer=v_referrer and b.month=v_month;$q$;
  c_save_r constant text := $q$  -- 414: a month under review in the month balances (deductions marked as
  -- settled come to more than the affiliate now owes back) is not paid more,
  -- as the Commissions page shows it.
  select b.balance,b.review_reason into available,issue from public.affiliate_month_balances() b where b.referrer=v_referrer and b.month=v_month;
  if delta>0 and issue is not null then raise exception '%',issue; end if;$q$;

  -- ── AFTER md5s ───────────────────────────────────────────────────────────
  c_balances_after  constant text := '84c0741e983c8f483d677353c732d891';
  c_overview_after  constant text := '2da2a55dade2e16282c03ec3fc3b221d';
  c_earnings_after  constant text := 'adc91a9be47aff2d0c1bc60eb4834cef';
  c_refearn_after   constant text := 'f5fe44e5f1ffb14d895721698d6ad212';
  c_report_after    constant text := '84aa4032d794ecdd58e1ec4ae9b9adbc';
  c_dash_after      constant text := 'd29c77f8ce2fda5e81b134bdced16dcc';
  c_save_after      constant text := 'dd2993318ffef5c8f60b1e8513ed1902';
  c_record_after    constant text := 'e0c89b33a3bb8e7d79cf6ccf67fd1e2b';
  c_void_after      constant text := 'b5d0a22532b8ab71677825643714734f';
  c_record_page_after constant text := '70976b9267b703dc4899b518f46f7ec9';
  c_void_page_after constant text := '6be0c40f6fbe4d6910e1fe749f733c0e';
  c_guard_after     constant text := '2d0f81e74105134faea2d26842f45a6b';

  -- The table as this makes it: columns in order, then constraints by text.
  c_cols constant text := 'id uuid not null default gen_random_uuid()|referrer_customer_id uuid not null|amount numeric(12,2) not null|settled_on date not null|method text not null|note text not null|created_by uuid not null|created_at timestamp with time zone not null default now()|request_id uuid not null|voided_at timestamp with time zone|voided_by uuid|void_reason text|void_request_id uuid';
  c_cons constant text := 'CHECK ((((voided_at IS NULL) AND (voided_by IS NULL) AND (void_reason IS NULL) AND (void_request_id IS NULL)) OR ((voided_at IS NOT NULL) AND (voided_by IS NOT NULL) AND (btrim(void_reason) <> ''''::text) AND (char_length(void_reason) <= 2000) AND (void_request_id IS NOT NULL))))|CHECK (((btrim(note) <> ''''::text) AND (char_length(note) <= 2000)))|CHECK ((amount > (0)::numeric))|CHECK ((method = ANY (ARRAY[''paid_back''::text, ''written_off''::text, ''paid_outside_app''::text])))|FOREIGN KEY (created_by) REFERENCES profiles(id)|FOREIGN KEY (referrer_customer_id) REFERENCES customers(id)|FOREIGN KEY (voided_by) REFERENCES profiles(id)|PRIMARY KEY (id)|UNIQUE (request_id)|UNIQUE (void_request_id)';
  c_trigger constant text := 'CREATE TRIGGER affiliate_deduction_settlement_guard BEFORE DELETE OR UPDATE ON public.affiliate_deduction_settlements FOR EACH ROW EXECUTE FUNCTION trg_affiliate_deduction_settlement_guard()';
  c_new constant text[] := array['affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)',
                                 'affiliate_deduction_settlement_void(uuid,text,uuid,uuid)',
                                 'trg_affiliate_deduction_settlement_guard()',
                                 'record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)',
                                 'void_affiliate_deduction_settlement(uuid,text,uuid)'];
  c_internal constant text[] := array['affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)',
                                      'affiliate_deduction_settlement_void(uuid,text,uuid,uuid)',
                                      'trg_affiliate_deduction_settlement_guard()'];
  c_page constant text[] := array['record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)',
                                  'void_affiliate_deduction_settlement(uuid,text,uuid)'];
  c_rebuilt constant text[] := array['affiliate_month_balances()', 'report_affiliates()'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_drop boolean[] := '{}';
  v_table_new boolean; v_trigger_new boolean; v_n_new int;
  v_acl_before text[]; v_acl_after text[];
  v_owner uuid; v_staff uuid; v_aff uuid; v_set jsonb; v_x jsonb; v_out text;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing changes unless all pass ───────
  -- In install order: the month balances (they read the table, made first),
  -- the Reports rows, the page readers, then the new functions.
  for r in select * from (values
    ('affiliate_month_balances()', '2860675d40499f788036b76be3094702', c_balances_after, c_balances_def, null::text[], true),
    ('report_affiliates()', 'f1215960b13d75026fd2f4a3464af0cb', c_report_after, null::text,
     array[[c_report_ret_a, c_report_ret_r], [c_report_col_a, c_report_col_r]], true),
    ('affiliate_payout_overview()', '9a1c584766b2aaefb07012895932c0c8', c_overview_after, null::text,
     array[[c_overview_a, c_overview_r]], false),
    ('affiliate_portal_earnings()', '248af74df2f705e43ee110dbaaf4f6fa', c_earnings_after, null::text,
     array[[c_earn_decl_a, c_earn_decl_r], [c_earn_net_a, c_earn_net_r], [c_earn_sum_a, c_earn_sum_r]], false),
    ('referrer_earnings(uuid)', 'b74826ed6ccfbc82cff8258b0678ec12', c_refearn_after, null::text,
     array[[c_refearn_life_a, c_refearn_life_r], [c_refearn_month_a, c_refearn_month_r]], false),
    ('dashboard_summary()', '96ddc8f96a9bb00a222f11860d2ac221', c_dash_after, null::text,
     array[[c_dash_a, c_dash_r]], false),
    ('affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)', '59707475f768cbd500a47912524bd947',
     c_save_after, null::text, array[[c_save_a, c_save_r]], false),
    ('trg_affiliate_deduction_settlement_guard()', null::text, c_guard_after, c_guard_def, null::text[], false),
    ('affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)', null::text, c_record_after, c_record_def, null::text[], false),
    ('affiliate_deduction_settlement_void(uuid,text,uuid,uuid)', null::text, c_void_after, c_void_def, null::text[], false),
    ('record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)', null::text, c_record_page_after, c_record_page_def, null::text[], false),
    ('void_affiliate_deduction_settlement(uuid,text,uuid)', null::text, c_void_page_after, c_void_page_def, null::text[], false)
  ) x(fn, before_md5, after_md5, whole, edits, rebuilt)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      if r.before_md5 is not null then
        raise exception '414: public.% is missing', r.fn; end if;
      d := r.whole;
    else
      d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
      v := md5(d);
      if v = r.after_md5 then
        continue;  -- already this version; left alone
      elsif r.before_md5 is null then
        raise exception '414: public.% already exists with another text (md5 %). Re-read it and re-test before applying.', r.fn, v;
      elsif v <> r.before_md5 then
        raise exception '414: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
      end if;
      if r.edits is null then
        d := r.whole;
      else
        for k in 1 .. array_length(r.edits, 1) loop
          n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
          if n <> 1 then
            raise exception '414: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
          d := replace(d, r.edits[k][1], r.edits[k][2]);
        end loop;
      end if;
    end if;
    if md5(d) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || md5(d)); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
    v_drop := v_drop || (r.rebuilt and to_regprocedure('public.' || r.fn) is not null);
  end loop;
  if v_bad is not null then
    raise exception '414: a text built is not the tested one: %', v_bad; end if;

  -- The new functions and the table: all in, or none.
  select count(*) into v_n_new from unnest(c_new) f where to_regprocedure('public.' || f) is not null;
  v_table_new := to_regclass('public.affiliate_deduction_settlements') is null;
  select count(*) = 0 into v_trigger_new from pg_trigger t
   where t.tgrelid = to_regclass('public.affiliate_deduction_settlements') and not t.tgisinternal;
  if not ((v_n_new = 0 and v_table_new and v_trigger_new)
          or (v_n_new = cardinality(c_new) and not v_table_new and not v_trigger_new)) then
    raise exception '414: only part of this migration is installed (% of % new functions, table %, trigger %); re-read and re-test',
      v_n_new, cardinality(c_new), case when v_table_new then 'missing' else 'there' end,
      case when v_trigger_new then 'missing' else 'there' end; end if;
  if not v_table_new then
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                      || case when a.attnotnull then ' not null' else '' end
                      || coalesce(' default ' || pg_get_expr(dd.adbin, dd.adrelid), ''), '|' order by a.attnum) into v
      from pg_attribute a left join pg_attrdef dd on dd.adrelid = a.attrelid and dd.adnum = a.attnum
     where a.attrelid = 'public.affiliate_deduction_settlements'::regclass and a.attnum > 0 and not a.attisdropped;
    if v is distinct from c_cols then
      raise exception '414: public.affiliate_deduction_settlements exists and is not this migration''s (%)', v; end if;
    select string_agg(pg_get_constraintdef(k2.oid), '|' order by pg_get_constraintdef(k2.oid) collate "C") into v
      from pg_constraint k2 where k2.conrelid = 'public.affiliate_deduction_settlements'::regclass;
    if v is distinct from c_cons then
      raise exception '414: public.affiliate_deduction_settlements has other constraints (%)', v; end if;
    select string_agg(pg_get_triggerdef(t.oid), '|' order by t.tgname) into v
      from pg_trigger t where t.tgrelid = 'public.affiliate_deduction_settlements'::regclass and not t.tgisinternal;
    if v is distinct from c_trigger then
      raise exception '414: public.affiliate_deduction_settlements has other triggers (%)', v; end if;
  end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('affiliate_month_balances', 'report_affiliates', 'affiliate_payout_overview',
                       'affiliate_portal_earnings', 'referrer_earnings', 'dashboard_summary', 'affiliate_payout_save',
                       'affiliate_deduction_settlement_record', 'affiliate_deduction_settlement_void',
                       'record_affiliate_deduction_settlement', 'void_affiliate_deduction_settlement',
                       'trg_affiliate_deduction_settlement_guard')
     and p.oid::regprocedure::text not in ('affiliate_month_balances()', 'report_affiliates()', 'affiliate_payout_overview()',
                       'affiliate_portal_earnings()', 'referrer_earnings(uuid)', 'dashboard_summary()',
                       'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)',
                       'affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)',
                       'affiliate_deduction_settlement_void(uuid,text,uuid,uuid)',
                       'record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)',
                       'void_affiliate_deduction_settlement(uuid,text,uuid)',
                       'trg_affiliate_deduction_settlement_guard()');
  if v_bad is not null then
    raise exception '414: another function takes one of these names: %', v_bad; end if;

  -- Relied on, not changed: the versions read on 9 Oct 2026 (the netting
  -- built on the month balances, a month's review, the
  -- commission page's access rule, the payouts' lock, the reporting rows and
  -- the directory behind the Reports rows, the portal's affiliate, the staff
  -- check, today in Singapore).
  for r in select * from (values
    ('affiliate_referrer_balances()', '54ef098ba8f9e3d81bb45906c4607ab6'),
    ('affiliate_payout_review(uuid,date)', 'b8e330efcb88277f965f67386406e0a4'),
    ('affiliate_payout_access(boolean)', '90b7399378a7604afd4af97c059d0703'),
    ('affiliate_payout_lock()', 'c410a35592ecae0ec9af516e5595f272'),
    ('commission_reporting_rows()', '96962fa272f3eb35111c6ac199255410'),
    ('affiliate_directory()', '308a1721fce357e9aede2d4d9b06a6af'),
    ('current_affiliate_customer_id()', '51695acf5f26ce3918d6003d0c980b0f'),
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '414: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;

  -- The columns read, as read on 9 Oct 2026.
  for r in select * from (values
    ('public.profiles', 'deleted_at timestamp with time zone|full_name text not null|id uuid not null|invitation_status text|is_active boolean not null|role user_role not null',
     array['id', 'role', 'is_active', 'deleted_at', 'invitation_status', 'full_name']),
    ('public.customers', 'id uuid not null', array['id']),
    ('public.commission_payouts', 'payment_date date not null|payout_month date not null|referrer_customer_id uuid not null|status text not null|total_amount numeric(12,2) not null',
     array['referrer_customer_id', 'payout_month', 'payment_date', 'total_amount', 'status']),
    ('public.audit_logs', 'action text not null|actor_role text|changed_by uuid|module text|new_data jsonb|old_data jsonb|reason text|record_id uuid|table_name text not null',
     array['table_name', 'record_id', 'action', 'old_data', 'new_data', 'changed_by', 'actor_role', 'module', 'reason'])
  ) x(tbl, shape, cols)
  loop
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                      '|' order by a.attname) into v
      from pg_attribute a
     where a.attrelid = r.tbl::regclass and a.attnum > 0 and not a.attisdropped and a.attname = any (r.cols);
    if v is distinct from r.shape then
      raise exception '414: % is not shaped as read on 9 Oct 2026 (%)', r.tbl, v; end if;
  end loop;

  -- The grants of what is changed, as a set, to compare after.
  select array_agg(x order by x collate "C") into v_acl_before from (
    select p.oid::regprocedure::text || ':' || coalesce(a.grantee::regrole::text, 'public') || ':' || a.privilege_type x
      from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.pronamespace = 'public'::regnamespace
       and p.oid::regprocedure::text in ('affiliate_month_balances()', 'report_affiliates()', 'affiliate_payout_overview()',
                                         'affiliate_portal_earnings()', 'referrer_earnings(uuid)', 'dashboard_summary()',
                                         'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)')
       and a.grantee <> p.proowner) g;

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_table_new then
    create table public.affiliate_deduction_settlements (
      id uuid primary key default gen_random_uuid(),
      referrer_customer_id uuid not null references public.customers(id),
      amount numeric(12,2) not null check (amount > 0),
      settled_on date not null,
      method text not null check (method in ('paid_back', 'written_off', 'paid_outside_app')),
      note text not null check (btrim(note) <> '' and char_length(note) <= 2000),
      created_by uuid not null references public.profiles(id),
      created_at timestamptz not null default now(),
      request_id uuid not null unique,
      voided_at timestamptz,
      voided_by uuid references public.profiles(id),
      void_reason text,
      void_request_id uuid unique,
      check ((voided_at is null and voided_by is null and void_reason is null and void_request_id is null)
             or (voided_at is not null and voided_by is not null and btrim(void_reason) <> ''
                 and char_length(void_reason) <= 2000 and void_request_id is not null)));
    create index affiliate_deduction_settlements_referrer_idx
      on public.affiliate_deduction_settlements (referrer_customer_id) where voided_at is null;
    comment on table public.affiliate_deduction_settlements is
      '414: an affiliate''s deduction (commission paid out and then taken back) marked as settled: paid back, written off or paid off outside the app. Voided, never deleted. Written by affiliate_deduction_settlement_record() and _void() only.';
  end if;
  alter table public.affiliate_deduction_settlements enable row level security;
  revoke all on table public.affiliate_deduction_settlements from public, anon, authenticated, service_role;
  grant select on table public.affiliate_deduction_settlements to service_role;

  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    if v_drop[i] then
      execute format('drop function public.%s', v_fns[i]);
    end if;
    execute v_defs[i];
    if v_fns[i] = any (c_internal) or v_fns[i] = 'affiliate_month_balances()' then
      execute format('revoke all on function public.%s from public, anon, authenticated', v_fns[i]);
      execute format('grant execute on function public.%s to service_role', v_fns[i]);
    elsif v_fns[i] = any (c_page) or v_fns[i] = 'report_affiliates()' then
      execute format('revoke all on function public.%s from public, anon', v_fns[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', v_fns[i]);
    end if;
  end loop;

  if v_trigger_new then
    create trigger affiliate_deduction_settlement_guard
      before update or delete on public.affiliate_deduction_settlements
      for each row execute function public.trg_affiliate_deduction_settlement_guard();
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  v_bad := null;
  for r in select * from (values
    ('affiliate_month_balances()', c_balances_after), ('report_affiliates()', c_report_after),
    ('affiliate_payout_overview()', c_overview_after), ('affiliate_portal_earnings()', c_earnings_after),
    ('referrer_earnings(uuid)', c_refearn_after), ('dashboard_summary()', c_dash_after),
    ('affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)', c_save_after),
    ('trg_affiliate_deduction_settlement_guard()', c_guard_after),
    ('affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)', c_record_after),
    ('affiliate_deduction_settlement_void(uuid,text,uuid,uuid)', c_void_after),
    ('record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)', c_record_page_after),
    ('void_affiliate_deduction_settlement(uuid,text,uuid)', c_void_page_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
    if (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = to_regprocedure('public.' || r.fn))
       is distinct from current_user then
      raise exception '414: public.% is not owned by the role that checked it', r.fn; end if;
  end loop;
  if v_bad is not null then
    raise exception '414: installed with md5s other than the tested ones: %', v_bad; end if;
  select string_agg(pg_get_triggerdef(t.oid), '|' order by t.tgname) into v
    from pg_trigger t where t.tgrelid = 'public.affiliate_deduction_settlements'::regclass
     and not t.tgisinternal and t.tgenabled = 'O';
  if v is distinct from c_trigger then
    raise exception '414: the trigger on public.affiliate_deduction_settlements is not as tested (%)', v; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_deduction_settlements'::regclass) then
    raise exception '414: row level security is off on public.affiliate_deduction_settlements'; end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'affiliate_deduction_settlements') then
    raise exception '414: public.affiliate_deduction_settlements has a rule; it should have none'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  -- What was changed or rebuilt has exactly the grants it had.
  select array_agg(x order by x collate "C") into v_acl_after from (
    select p.oid::regprocedure::text || ':' || coalesce(a.grantee::regrole::text, 'public') || ':' || a.privilege_type x
      from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.pronamespace = 'public'::regnamespace
       and p.oid::regprocedure::text in ('affiliate_month_balances()', 'report_affiliates()', 'affiliate_payout_overview()',
                                         'affiliate_portal_earnings()', 'referrer_earnings(uuid)', 'dashboard_summary()',
                                         'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)')
       and a.grantee <> p.proowner) g;
  if v_acl_after is distinct from v_acl_before then
    raise exception '414: the grants of the changed functions changed (% before, % after)', v_acl_before, v_acl_after; end if;
  if v_acl_after is distinct from array[
       'affiliate_month_balances():service_role:EXECUTE', 'affiliate_payout_overview():authenticated:EXECUTE',
       'affiliate_payout_overview():service_role:EXECUTE',
       'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid):service_role:EXECUTE',
       'affiliate_portal_earnings():authenticated:EXECUTE',
       'affiliate_portal_earnings():service_role:EXECUTE', 'dashboard_summary():authenticated:EXECUTE',
       'dashboard_summary():service_role:EXECUTE', 'referrer_earnings(uuid):authenticated:EXECUTE',
       'referrer_earnings(uuid):service_role:EXECUTE', 'report_affiliates():authenticated:EXECUTE',
       'report_affiliates():service_role:EXECUTE'] then
    raise exception '414: the grants of the changed functions are not the ones read on 9 Oct 2026 (%)', v_acl_after; end if;
  -- The internal ones are the service role's alone (339); the page's two are
  -- signed-in staff's, never the anon key's.
  foreach v in array c_internal loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = to_regprocedure('public.' || v) and a.grantee = 0) then
      raise exception '414: public.% is not the service role''s alone', v; end if;
  end loop;
  foreach v in array c_page loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = to_regprocedure('public.' || v) and a.grantee = 0) then
      raise exception '414: public.% is not signed-in staff''s and the service role''s alone', v; end if;
  end loop;
  if has_table_privilege('anon', 'public.affiliate_deduction_settlements', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.affiliate_deduction_settlements', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.affiliate_deduction_settlements', 'insert,update,delete,truncate,references,trigger')
     or not has_table_privilege('service_role', 'public.affiliate_deduction_settlements', 'select') then
    raise exception '414: the grants on public.affiliate_deduction_settlements are not as tested'; end if;

  -- ── Behaviour, switching role (nothing is printed, no row remains) ───────
  -- A signed-in login with no profile, and the anon key: refused.
  foreach v in array array['authenticated', 'anon'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', v)::text, true);
    execute format('set local role %I', v);
    begin
      perform public.record_affiliate_deduction_settlement(gen_random_uuid(), 1, public.sg_today(), 'written_off', '414 check', gen_random_uuid());
      raise exception '414: % may mark a deduction as settled', v;
    exception when insufficient_privilege then null;
    end;
    begin
      perform count(*) from public.affiliate_deduction_settlements;
      raise exception '414: % may read affiliate_deduction_settlements', v;
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- A made-up Owner settles part of a made-up affiliate's deduction (a payout
  -- of S$100.00 with nothing behind it: S$100.00 owed back), then voids it;
  -- Staff are refused. Always undone.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '414-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '414-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '414 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff')) x(id, role) on x.id = u.id;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    insert into public.customers (full_name, phone) values ('414 check affiliate', '+6591414099') returning id into v_aff;
    insert into public.commission_payouts (payout_month, referrer_customer_id, total_amount, status)
    values ((date_trunc('month', public.sg_today()) - interval '1 month')::date, v_aff, 100, 'paid');
    if (select r2.deduction from public.affiliate_referrer_balances() r2 where r2.referrer = v_aff) is distinct from 100.00 then
      raise exception '414: the check''s affiliate does not owe S$100.00 back'; end if;

    execute 'set local role authenticated';
    begin
      perform public.record_affiliate_deduction_settlement(v_aff, 100.01, public.sg_today(), 'paid_back', '414 check', gen_random_uuid());
      raise exception '414: more than the deduction was accepted';
    exception when raise_exception then
      if sqlerrm not like 'S$100.01 is more than the S$100.00 this affiliate owes back.%' then raise; end if;
    end;
    v_set := public.record_affiliate_deduction_settlement(v_aff, 60, public.sg_today(), 'paid_back', '414 check', '00000000-0000-4000-8000-000000000414');
    if public.record_affiliate_deduction_settlement(v_aff, 60, public.sg_today(), 'paid_back', '414 check', '00000000-0000-4000-8000-000000000414')
       is distinct from v_set then
      raise exception '414: a retry of the same request did not give the same answer'; end if;
    v_x := (select g from jsonb_array_elements(public.affiliate_payout_overview()->'referrers') g where g->>'referrer' = v_aff::text);
    if (v_x->>'deduction')::numeric <> 40 or (v_x->>'unpaid')::numeric <> 0
       or (select count(*) from jsonb_array_elements(public.affiliate_payout_overview()->'settlements') g
            where g->>'id' = v_set->>'id' and g->>'created_by_name' = '414 check' and not g ? 'request_id') <> 1 then
      raise exception '414: after settling S$60.00 the overview does not show S$40.00 still owed and the settlement (%)', v_x; end if;
    perform public.void_affiliate_deduction_settlement((v_set->>'id')::uuid, '414 check', gen_random_uuid());
    execute 'reset role';
    if (select r2.deduction from public.affiliate_referrer_balances() r2 where r2.referrer = v_aff) is distinct from 100.00
       or (select count(*) from public.audit_logs al where al.record_id = (v_set->>'id')::uuid
            and al.action in ('affiliate_deduction_settled', 'affiliate_deduction_settlement_voided') and al.changed_by = v_owner) <> 2 then
      raise exception '414: voiding did not put the deduction back, or was not audited'; end if;
    begin
      delete from public.affiliate_deduction_settlements where id = (v_set->>'id')::uuid;
      raise exception '414: a settlement was deleted';
    exception when raise_exception then
      if sqlerrm not like 'A deduction settlement is never deleted.%' then raise; end if;
    end;

    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.record_affiliate_deduction_settlement(v_aff, 10, public.sg_today(), 'written_off', '414 check', gen_random_uuid());
      raise exception '414: Staff may mark a deduction as settled';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    raise exception using errcode = 'P0414', message = '414: check done, undone';
  exception when sqlstate 'P0414' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
