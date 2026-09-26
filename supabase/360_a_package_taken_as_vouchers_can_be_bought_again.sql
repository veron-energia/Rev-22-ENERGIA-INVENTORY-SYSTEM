-- 360_a_package_taken_as_vouchers_can_be_bought_again.sql
--
-- WHAT THE OWNER DECIDED (25 Sep 2026)
--
-- A customer may buy the same package again while an earlier unit of it was
-- taken as vouchers — whether the package only ever grants vouchers, or the
-- customer chose vouchers on a choice package. Such a unit holds vouchers, not a
-- period of unlimited therapy, so it is not a "current entitlement" of that
-- package.
--
-- WHAT THIS CHANGES
--
--   1. create_invoice (8 arguments), update_invoice_internal, add_therapy_line:
--      the "already has a current entitlement for this package" check leaves
--      out units taken as vouchers.
--   2. excl_pte_same_package_no_overlap: a vouchers-only unit is marked active on
--      the day it is sold, with no expiry, so the constraint read it as a period
--      running for ever and refused a second one at payment. Units taken as
--      vouchers are left out of it; every unlimited period is still covered.
--   3. switch_therapy_benefit / purchased_therapy_unit_state: switching a unit
--      taken as vouchers back to unlimited therapy is refused, and not offered,
--      while the customer holds a current unit of the same package bought on
--      another invoice, or an unpaid invoice that will create one — the
--      situation the check in (1) exists to prevent
--      (therapy_switch_back_blocker). Units bought together on one invoice are
--      unaffected.
--   4. therapy_next_available_start: a unit taken as vouchers is no longer listed
--      as "unlimited therapy running" when a start date overlaps.
--
-- NOT CHANGED
--
--   * A unit waiting for its choice, or taken as unlimited therapy, still stops
--     a second purchase of the same package while it is current.
--   * The unused 7-argument create_invoice overload.
--   * Two unpaid invoices for the same package can still both be paid (the
--     check runs when an invoice is created, as before); two periods of one
--     package still never share days (359).
--   * A correction that changes a package line's price is still refused while
--     that invoice's own unit is current (the check does not leave out the
--     invoice's own unit); a vouchers-only line now gets through it.
--   * Units already sold, and everything 359 does.
--
-- SAFETY
--
-- Needs 359. Each patched function is guarded by the md5 of the production
-- version (25 Sep 2026, after 359) and by an anchor that must occur the stated
-- number of times; a function already carrying "360:" is left alone. The
-- constraint is replaced only if it is exactly the version expected.

set lock_timeout = '5s';

do $mig$
begin
  if to_regprocedure('public.claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)') is null then
    raise exception '360: apply 359 first'; end if;
end $mig$;

-- ── 1. buying the same package again ────────────────────────────────────────
do $mig$
declare f record; d text; n int; v_md5 text;
        a text := $a$and status in ('active','scheduled','pending_activation')) then$a$;
        r text := $r$and status in ('active','scheduled','pending_activation')
                    and benefit_choice is distinct from 'voucher') then  -- 360: vouchers hold no therapy period$r$;
begin
  for f in select * from (values
      ('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', 'b0100dff2b5a091be5e3422db66bbbbb'),
      ('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', '17b6c94777c78701b15db6c140a544fe'),
      ('public.add_therapy_line(uuid,uuid,text)', 'a50bc4417f6c0e75fb0ec7b61844b8d1')) v(sig, want)
  loop
    d := pg_get_functiondef(f.sig::regprocedure);
    if position('360:' in d) > 0 then raise notice '360: % already patched; left alone.', f.sig; continue; end if;
    v_md5 := md5(d);
    if v_md5 <> f.want then
      raise exception '360: % is not the version this was tested against (md5 %)', f.sig, v_md5; end if;
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    if n <> 1 then raise exception '360: % guard anchor found % times', f.sig, n; end if;
    execute replace(d, a, r);
  end loop;
end $mig$;

-- ── 2. the no-overlap constraint no longer sees units taken as vouchers ──────
do $mig$
declare v_def text;
  v_old text := 'EXCLUDE USING gist (customer_id WITH =, package_id WITH =, daterange(activation_date, expiry_date, ''[]''::text) WITH &&) WHERE ((((activation_date IS NOT NULL) AND (expiry_date IS NOT NULL) AND ((status = ANY (ARRAY[''active''::text, ''scheduled''::text, ''expired''::text])) = false)) OR (status = ''active''::text)))';
begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conrelid = 'public.purchased_therapy_entitlements'::regclass and conname = 'excl_pte_same_package_no_overlap';
  if v_def is not null and position('benefit_choice' in v_def) > 0 then
    raise notice '360: excl_pte_same_package_no_overlap already leaves out vouchers; left alone.'; return; end if;
  if v_def is distinct from v_old then
    raise exception '360: excl_pte_same_package_no_overlap is not the version this was tested against: %', v_def; end if;

  alter table public.purchased_therapy_entitlements drop constraint excl_pte_same_package_no_overlap;
  alter table public.purchased_therapy_entitlements
    add constraint excl_pte_same_package_no_overlap
    exclude using gist (customer_id with =, package_id with =,
                        daterange(activation_date, expiry_date, '[]') with &&)
    where ((((activation_date is not null) and (expiry_date is not null)
              and ((status = any (array['active','scheduled','expired'])) = false))
             or (status = 'active'))
           and benefit_choice is distinct from 'voucher');
end $mig$;

comment on constraint excl_pte_same_package_no_overlap on public.purchased_therapy_entitlements is
  'Two periods of unlimited therapy from the same package never share days. Units taken as vouchers hold no period and are left out (360).';

-- ── 3. switching back to unlimited ──────────────────────────────────────────
create or replace function public.therapy_switch_back_blocker(p_purchased_id uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- 360: what stops a unit taken as vouchers turning back into unlimited
  -- therapy: another current unit of the same package bought on another
  -- invoice, or an unpaid invoice that will create one when it is paid.
  -- Null when nothing does.
  select coalesce(
    (select 'a current purchase ' || o.entitlement_no
       from public.purchased_therapy_entitlements e
       join public.purchased_therapy_entitlements o
         on o.customer_id = e.customer_id and o.package_id = e.package_id and o.id <> e.id
      where e.id = p_purchased_id
        and o.invoice_id is distinct from e.invoice_id
        and o.status in ('active','scheduled','pending_activation')
        and o.benefit_choice is distinct from 'voucher'
      order by o.created_at limit 1),
    (select 'an unpaid invoice ' || i.invoice_no
       from public.purchased_therapy_entitlements e
       join public.invoices i
         on i.customer_id = e.customer_id and i.id is distinct from e.invoice_id
        and i.status in ('unpaid','partially_paid') and i.deleted_at is null
      cross join lateral public.invoice_therapy_entitlements_due(i.id) due
      where e.id = p_purchased_id and due.therapy_package_id = e.package_id
      order by i.created_at limit 1))
$function$;

revoke all on function public.therapy_switch_back_blocker(uuid) from public, anon, authenticated;
grant execute on function public.therapy_switch_back_blocker(uuid) to service_role;

do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.switch_therapy_benefit(uuid,text,text,uuid)'::regprocedure);
  if position('360:' in d) > 0 then raise notice '360: switch_therapy_benefit already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'ddbd571f6a84cb21d1f3356d49caa88a' then
    raise exception '360: switch_therapy_benefit is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$  if e.benefit_choice = p_new_choice then
    raise exception 'That is already the chosen benefit'; end if;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '360: switch_therapy_benefit anchor found % times', n; end if;
  execute replace(d, a, a || $r$
  -- 360: a unit taken as vouchers lets the customer buy the package again; it
  -- cannot then turn back into a second current period of the same package.
  -- (purchased_therapy_unit_state already says so; this is the backstop.)
  if p_new_choice = 'unlimited' and public.therapy_switch_back_blocker(p_purchased_id) is not null then
    raise exception 'This customer already has % for this package, so this one cannot be switched to unlimited therapy.',
      public.therapy_switch_back_blocker(p_purchased_id);
  end if;$r$);
end $mig$;

do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.purchased_therapy_unit_state(uuid)'::regprocedure);
  if position('360:' in d) > 0 then raise notice '360: purchased_therapy_unit_state already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '03a31261010a61b5b32fe386af12b73a' then
    raise exception '360: purchased_therapy_unit_state is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$      then 'Vouchers from this unit have already been claimed. Use the correction or refund workflow.'
    else null end;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '360: purchased_therapy_unit_state anchor found % times', n; end if;
  execute replace(d, a, $r$      then 'Vouchers from this unit have already been claimed. Use the correction or refund workflow.'
    -- 360: the only switch open to a unit taken as vouchers is back to
    -- unlimited therapy, which a later purchase of the same package rules out.
    when e.benefit_choice = 'voucher' and public.therapy_switch_back_blocker(e.id) is not null
      then 'This customer already has ' || public.therapy_switch_back_blocker(e.id)
           || ' for this package, so this one cannot be switched to unlimited therapy.'
    else null end;$r$);
end $mig$;

-- ── 4. the overlap answer lists therapy periods only ────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.therapy_next_available_start(uuid,date)'::regprocedure);
  if position('360:' in d) > 0 then raise notice '360: therapy_next_available_start already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '3b744f8ef0602e115fecd6255f91650f' then
    raise exception '360: therapy_next_available_start is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$from public.purchased_therapy_entitlements
       where customer_id = p_customer_id and status in ('active','scheduled')$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 2 then raise exception '360: therapy_next_available_start anchor found % times', n; end if;
  execute replace(d, a, $r$from public.purchased_therapy_entitlements
       where customer_id = p_customer_id and status in ('active','scheduled')
         and benefit_choice is distinct from 'voucher'  -- 360: vouchers are not a period$r$);
end $mig$;

notify pgrst, 'reload schema';
