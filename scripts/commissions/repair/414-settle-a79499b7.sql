-- 414 repair: record as settled the S$555.27 one affiliate owed back on
-- 9 Oct 2026.
--
-- The Owner said on 9 Oct 2026 that this deduction (commission paid out and
-- then taken back, recovered from later commission since 410) was settled
-- outside the app: taken off a payment to the affiliate that the app did not
-- record. Afterwards the affiliate owes nothing and is owed nothing; their
-- October S$7.08 stays counted against the debt. This writes one settlement,
-- through affiliate_deduction_settlement_record (the function the Commissions
-- page's Mark as settled uses), as the Owner named below: method "Paid off
-- outside the app", S$555.27, settled on 9 Oct 2026, the note below. It is
-- audited like a settlement made on the page, and an Owner or Manager can
-- void it there with a reason. No commission row, take-back or payout is
-- touched.
--
-- Run it once, after 414, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres), with the Owner's go-ahead. It is one
-- statement, so it is atomic. It acts only while the affiliate still owes
-- exactly S$555.27 back and has no settlement yet; otherwise it changes
-- nothing and says why. A second run changes nothing (the request id is
-- fixed, and a settlement already made with it, voided or not, is left as it
-- is). It prints amounts and ids only (a notice), never a name or a phone.
-- Expected on production (9 Oct 2026): "S$555.27 recorded as settled ...
-- owes back S$0.00, is owed S$0.00".
--
-- c_actor is the Owner account the settlement is recorded under (created_by,
-- and the audit row). It is the Owner login used for the earlier owner
-- actions run this way; change it to the other Owner's id before running if
-- the Owner wants it recorded under theirs.
--
-- To check afterwards (ids and amounts only):
--   select s.id, s.amount, s.settled_on, s.method, s.created_by, s.voided_at
--     from public.affiliate_deduction_settlements s
--    where s.referrer_customer_id = 'a79499b7-e02d-4330-9007-8deaa82d67ef';
--   select owed, unpaid, deduction, payable from public.affiliate_referrer_balances()
--    where referrer = 'a79499b7-e02d-4330-9007-8deaa82d67ef';
--   -- expected: one settlement of 555.27, not voided; 0, 0, 0, 0

do $repair$
declare
  c_referrer constant uuid := 'a79499b7-e02d-4330-9007-8deaa82d67ef';
  c_actor    constant uuid := '0e857a04-89f4-4b3e-adf2-c9fbd799d46c';
  c_amount   constant numeric := 555.27;
  c_on       constant date := date '2026-10-09';
  c_method   constant text := 'paid_outside_app';
  c_note     constant text := 'Settled outside the app (the Owner, 9 Oct 2026).';
  -- Fixed, so a second run is answered by the first settlement, never a new one.
  c_request  constant uuid := '41400000-a794-49b7-8000-000000555270';
  c_record_after   constant text := 'e0c89b33a3bb8e7d79cf6ccf67fd1e2b';  -- 414's AFTER
  c_balances_after constant text := '84c0741e983c8f483d677353c732d891';  -- 414's AFTER
  v_path text := current_setting('search_path');
  v_prior public.affiliate_deduction_settlements;
  v_owed numeric; v_deduction numeric; v_months text; v_res jsonb; r record;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)') is null
     or md5(pg_get_functiondef('public.affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)'::regprocedure))
        <> c_record_after
     or md5(pg_get_functiondef('public.affiliate_month_balances()'::regprocedure)) <> c_balances_after then
    raise exception '414 repair: 414 is not in (its functions are missing or not its versions); apply 414 first'; end if;

  -- A second run: the settlement this made is there; leave it as it is.
  select * into v_prior from public.affiliate_deduction_settlements s where s.request_id = c_request;
  if found then
    if v_prior.referrer_customer_id <> c_referrer or v_prior.amount <> c_amount or v_prior.settled_on <> c_on
       or v_prior.method <> c_method or v_prior.note <> c_note then
      raise exception '414 repair: settlement % carries this script''s request id with other details; nothing was changed', v_prior.id; end if;
    raise notice '414 repair: already recorded (settlement %, %); nothing changed', v_prior.id,
      case when v_prior.voided_at is null then 'in force' else 'voided since' end;
    perform set_config('search_path', v_path, true);
    return;
  end if;

  -- Only the case the Owner decided on.
  if not exists (select 1 from public.customers c where c.id = c_referrer) then
    raise exception '414 repair: the affiliate % is not there; nothing was changed', c_referrer; end if;
  if exists (select 1 from public.affiliate_deduction_settlements s
              where s.referrer_customer_id = c_referrer and s.voided_at is null) then
    raise exception '414 repair: the affiliate already has a settlement in force (made on the page?); nothing was changed. Re-read it with the Owner.'; end if;
  select b.owed, b.deduction into v_owed, v_deduction from public.affiliate_referrer_balances() b where b.referrer = c_referrer;
  if v_deduction is distinct from c_amount or v_owed is distinct from -c_amount then
    raise exception '414 repair: the affiliate owes back S$% (net %), not S$555.27 as on 9 Oct 2026; nothing was changed. Re-read it with the Owner.',
      coalesce(v_deduction, 0), coalesce(v_owed, 0); end if;
  select string_agg(to_char(b.month, 'YYYY-MM') || ' ' || b.earned || '/' || b.adjustments || '/' || b.paid || '/' || b.balance,
                    '; ' order by b.month) into v_months
    from public.affiliate_month_balances() b where b.referrer = c_referrer;
  if v_months is distinct from '2026-09 1705.59/-991.64/1276.30/-562.35; 2026-10 100.80/0/93.72/7.08' then
    raise exception '414 repair: the affiliate''s months are not as read on 9 Oct 2026 (%); nothing was changed. Re-read them with the Owner.', v_months; end if;
  if not exists (select 1 from public.profiles p where p.id = c_actor and p.role = 'owner' and p.is_active
                  and p.deleted_at is null and coalesce(p.invitation_status, 'accepted') = 'accepted') then
    raise exception '414 repair: % is not an active Owner; nothing was changed', c_actor; end if;

  v_res := public.affiliate_deduction_settlement_record(c_referrer, c_amount, c_on, c_method, c_note, c_request, c_actor);

  -- Afterwards: nothing owed either way, the commission rows and payouts as they were.
  select b.owed, b.deduction into v_owed, v_deduction from public.affiliate_referrer_balances() b where b.referrer = c_referrer;
  if v_owed <> 0 or v_deduction <> 0 then
    raise exception '414 repair: after recording, the affiliate still nets to S$%; nothing was changed', v_owed; end if;
  select string_agg(to_char(b.month, 'YYYY-MM') || ' ' || b.balance || ' settled ' || b.settled, '; ' order by b.month) into v_months
    from public.affiliate_month_balances() b where b.referrer = c_referrer;
  if v_months is distinct from '2026-09 -7.08 settled 555.27; 2026-10 7.08 settled 0' then
    raise exception '414 repair: after recording, the months are not as tested (%); nothing was changed', v_months; end if;
  if (select count(*) from public.audit_logs a where a.record_id = (v_res->>'id')::uuid
        and a.action = 'affiliate_deduction_settled' and a.changed_by = c_actor) <> 1 then
    raise exception '414 repair: the settlement was not audited; nothing was changed'; end if;

  raise notice '414 repair: S$555.27 recorded as settled (settlement %, paid off outside the app, 2026-10-09); the affiliate owes back S$0.00, is owed S$0.00',
    v_res->>'id';
  perform set_config('search_path', v_path, true);
end $repair$;
