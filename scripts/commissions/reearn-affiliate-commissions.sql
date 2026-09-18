-- RE-EARN AFFILIATE COMMISSION THAT THE OLD BUILD GOT WRONG
--
-- Until 334, production computed affiliate commission with the 5D2-era
-- earn_invoice_commission. That build credited only the buyer's profile
-- referrer (never the affiliate selected on the invoice), paid people who are
-- not activated affiliates instead of blocking them, and used fixed rates.
-- Every paid invoice carries whatever it decided.
--
-- This walks the paid invoices and asks the reinstalled functions what they
-- earn now, inside a savepoint per invoice:
--
--   * same answer            -> the savepoint is rolled back; the invoice is
--                               not touched, not even a timestamp;
--   * different answer       -> the unpaid rows are reversed with a reason and
--                               the new rows stay, which is what a correction
--                               on the invoice does today; an audit row records
--                               before and after;
--   * money already paid out -> nothing is changed; the invoice is listed for
--                               review, because paid money needs a person.
--
-- Staff commission is not read or written here: the bug never touched it.
--
--   DRY RUN BY DEFAULT. Running this plainly reports what it would do and
--   rolls the whole thing back. It changes nothing unless you pass -v apply=yes.
--
-- Usage
--   Dry run, everything:      psql "$URL" -f scripts/commissions/reearn-affiliate-commissions.sql
--   Only some invoices:       ... -v only='INV-2026-0222,INV-2026-0227'
--   Everything but some:      ... -v skip='INV-2026-0181'
--   FOR REAL:                 ... -v apply=yes
--   Attribute it to a person: add -v actor='<the owner profile uuid>'
--
-- Requires 334. Refuses to run on the old build.

\pset pager off
\set ON_ERROR_STOP on
\if :{?apply} \else \set apply 'no' \endif
\if :{?only}  \else \set only ''   \endif
\if :{?skip}  \else \set skip ''   \endif
\if :{?actor} \else \set actor ''  \endif

begin;

-- psql variables do not reach inside a dollar-quoted block, so they are handed
-- over as transaction-local settings.
select set_config('reearn.only',  :'only',  true) as _only,
       set_config('reearn.skip',  :'skip',  true) as _skip,
       set_config('reearn.actor', :'actor', true) as _actor \gset

create temp table reearn_report(
  seq serial primary key, invoice_no text, outcome text,
  before_rows jsonb, after_rows jsonb, note text) on commit drop;

do $$
declare
  v_reason constant text := 'Re-earned after 334: recomputed by the current commission rules';
  v_actor uuid := nullif(current_setting('reearn.actor', true), '')::uuid;
  v_only text[]; v_skip text[];
  i record; c record; v_before uuid[]; v_old jsonb; v_new jsonb; v_paid integer;
begin
  if position('affiliate_selection_explicit' in
       pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure)) = 0 then
    raise exception 'Apply supabase/334_commission_functions_reinstalled.sql first: the installed earn_invoice_commission is still the old build.';
  end if;
  select array_agg(btrim(x)) into v_only
    from unnest(string_to_array(current_setting('reearn.only', true), ',')) x where btrim(x) <> '';
  select array_agg(btrim(x)) into v_skip
    from unnest(string_to_array(current_setting('reearn.skip', true), ',')) x where btrim(x) <> '';
  if v_actor is not null then
    perform set_config('request.jwt.claim.sub', v_actor::text, true);
  end if;

  -- Only invoices that can carry affiliate commission at all: a selected
  -- affiliate, a referred buyer, an explicit "None", or rows already there.
  for i in
    select inv.id, inv.invoice_no, inv.store_id
      from public.invoices inv
      join public.customers b on b.id = inv.customer_id
     where inv.deleted_at is null
       and inv.status in ('paid', 'completed_foc')
       and (v_only is null or inv.invoice_no = any(v_only))
       and (v_skip is null or not (inv.invoice_no = any(v_skip)))
       and (inv.affiliate_id is not null or b.referred_by is not null
            or coalesce(inv.affiliate_selection_explicit, false)
            or exists (select 1 from public.commissions x where x.invoice_id = inv.id))
     order by inv.invoice_no
  loop
    begin
      select count(*) into v_paid from public.commissions
       where invoice_id = i.id and (payout_id is not null or status = 'paid');
      select array_agg(id) into v_before from public.commissions where invoice_id = i.id;

      -- What stands now: live rows only. Payout adjustments (adjusts_commission_id)
      -- belong to money already paid and are left alone.
      select coalesce(jsonb_agg(jsonb_build_object(
               'to', referrer_customer_id, 'tier', tier, 'item', invoice_item_id,
               'type', product_type, 'line', line_amount, 'rate', rate,
               'amount', commission_amount, 'status', status)
               order by referrer_customer_id, tier, invoice_item_id, commission_amount), '[]'::jsonb)
        into v_old
        from public.commissions
       where invoice_id = i.id and status in ('earned', 'blocked')
         and payout_id is null and adjusts_commission_id is null;

      update public.commissions
         set status = 'reversed', reversed_at = now(), reversal_reason = v_reason
       where invoice_id = i.id and payout_id is null
         and status in ('earned', 'blocked') and adjusts_commission_id is null;

      -- The same calls a payment or a correction makes.
      perform public.earn_invoice_commission(i.id);
      for c in select id from public.credit_package_sales where invoice_id = i.id loop
        perform public.earn_credit_package_commission(c.id);
      end loop;
      for c in select id from public.premium_bundle_sales where invoice_id = i.id loop
        perform public.earn_premium_bundle_commission(c.id);
      end loop;

      select coalesce(jsonb_agg(jsonb_build_object(
               'to', referrer_customer_id, 'tier', tier, 'item', invoice_item_id,
               'type', product_type, 'line', line_amount, 'rate', rate,
               'amount', commission_amount, 'status', status)
               order by referrer_customer_id, tier, invoice_item_id, commission_amount), '[]'::jsonb)
        into v_new
        from public.commissions
       where invoice_id = i.id and not (id = any(coalesce(v_before, '{}'::uuid[])));

      -- Same answer: undo the savepoint so the invoice keeps its original rows.
      if v_new = v_old then
        raise exception using errcode = 'P0901', message = 'unchanged';
      end if;
      -- Money already paid out: undo and hand it to a person.
      if v_paid > 0 then
        raise exception using errcode = 'P0902', message = 'paid rows';
      end if;

      perform public.write_audit_ex('commissions', i.id, 'commission_reearned',
        jsonb_build_object('invoice_no', i.invoice_no, 'rows', v_old),
        jsonb_build_object('invoice_no', i.invoice_no, 'rows', v_new),
        'commissions', v_reason, i.store_id, null, null);
      insert into reearn_report(invoice_no, outcome, before_rows, after_rows)
      values (i.invoice_no, 'changed', v_old, v_new);
    exception
      when sqlstate 'P0901' then
        insert into reearn_report(invoice_no, outcome, before_rows, after_rows)
        values (i.invoice_no, 'unchanged', v_old, v_new);
      when sqlstate 'P0902' then
        insert into reearn_report(invoice_no, outcome, before_rows, after_rows, note)
        values (i.invoice_no, 'review', v_old, v_new,
                'commission on this invoice was already paid out or allocated; the current rules would give what is shown, but nothing was changed');
      when others then
        insert into reearn_report(invoice_no, outcome, note)
        values (i.invoice_no, 'error', sqlerrm);
    end;
  end loop;
end $$;

\echo ''
\echo '=== Invoices whose commission the current rules decide differently ==='
select r.invoice_no, r.outcome,
       (select string_agg(format('%s %s %s (%s)', x->>'tier', c.full_name, x->>'amount', x->>'status'), '; ' order by x->>'tier', c.full_name)
          from jsonb_array_elements(r.before_rows) x
          left join public.customers c on c.id = (x->>'to')::uuid) as before,
       (select string_agg(format('%s %s %s (%s)', x->>'tier', c.full_name, x->>'amount', x->>'status'), '; ' order by x->>'tier', c.full_name)
          from jsonb_array_elements(r.after_rows) x
          left join public.customers c on c.id = (x->>'to')::uuid) as after,
       r.note
  from reearn_report r
 where r.outcome <> 'unchanged'
 order by r.seq;

\echo ''
\echo '=== Summary ==='
select outcome, count(*) as invoices,
       sum((select coalesce(sum((x->>'amount')::numeric), 0) from jsonb_array_elements(before_rows) x where x->>'status' = 'earned')) as earned_before,
       sum((select coalesce(sum((x->>'amount')::numeric), 0) from jsonb_array_elements(after_rows) x where x->>'status' = 'earned')) as earned_after
  from reearn_report
 group by outcome
 order by outcome;

-- Anything other than an explicit apply=yes is a rehearsal.
select (:'apply' = 'yes') as do_commit \gset
\if :do_commit
\echo 'APPLYING: the work above has been committed.'
commit;
\else
\echo 'DRY RUN: nothing was changed. Pass -v apply=yes to commit it.'
rollback;
\endif
