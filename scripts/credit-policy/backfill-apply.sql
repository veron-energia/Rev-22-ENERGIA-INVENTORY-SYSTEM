-- RELEASE PAID CREDIT ON INVOICES THAT WERE ALREADY PART PAID BEFORE 327
--
-- 327 releases credit when a payment is recorded, so money received before it
-- was installed released nothing. This walks the invoices that are still short
-- and calls the same function a payment would, which means the amounts are
-- decided by exactly the rule 327 already enforces and not by a second one
-- written here.
--
--   DRY RUN BY DEFAULT. Running this plainly reports what it would do and then
--   rolls the whole thing back. It changes nothing unless you pass -v apply=yes.
--
-- Usage
--   Dry run, everything:        psql "$URL" -f backfill-apply.sql
--   Dry run, last 180 days:     psql "$URL" -v max_age_days=180 -f backfill-apply.sql
--   FOR REAL, last 180 days:    psql "$URL" -v max_age_days=180 -v apply=yes -f backfill-apply.sql
--   Attribute it to a person:   add -v actor='<the owner profile uuid>'
--
-- Run backfill-preview.sql first. It is read-only and tells you the size of
-- this before you decide how far back to go.

\pset pager off
\set ON_ERROR_STOP on
-- Defaults, used when the caller does not pass them.
\if :{?max_age_days} \else \set max_age_days 36500 \endif
\if :{?apply}        \else \set apply 'no'         \endif
\if :{?actor}        \else \set actor ''           \endif

begin;

-- psql variables do not reach inside a dollar-quoted block, so they are handed
-- over as settings first.
select set_config('backfill.actor', :'actor', true),
       set_config('backfill.max_age_days', :'max_age_days', true);

do $$
declare
  v_actor text := nullif(current_setting('backfill.actor', true), '');
  v_max_age int := coalesce(nullif(current_setting('backfill.max_age_days', true), '')::int, 36500);
  r record; res jsonb; v_released numeric;
  n_invoices int := 0; n_lines int := 0; total numeric := 0;
begin
  -- Credit granted by this run is attributed to whoever is named, so the wallet
  -- history does not show an anonymous grant.
  if v_actor is not null then
    perform set_config('request.jwt.claim.sub', v_actor, true);
  end if;

  raise notice 'Backfill: invoices up to % days old%',
    v_max_age, case when v_actor is null then ' (no actor named)' else ' as ' || v_actor end;

  for r in
    select distinct i.id, i.invoice_no, i.status::text as status,
           coalesce(i.business_date, i.created_at::date) as inv_date
      from public.invoices i
      join public.invoice_items it on it.invoice_id = i.id and it.line_kind = 'credit_package'
     where i.deleted_at is null
       and i.status not in ('cancelled','refunded','draft')
       and it.credit_issued_at is null
       and it.credit_split_allocation_id is null
       and not exists (select 1 from public.invoice_credit_splits x where x.invoice_item_id = it.id)
       and coalesce(i.paid_amount,0) > 0
       and (current_date - coalesce(i.business_date, i.created_at::date)) <= v_max_age
     order by inv_date, i.invoice_no
  loop
    -- The same call a payment makes. It grants the difference between what the
    -- money justifies and what has already gone out, so an invoice that somehow
    -- released already is left alone.
    res := public.release_credit_package_paid_credit(r.id);
    select coalesce(sum((x->>'released')::numeric), 0)
      into v_released from jsonb_array_elements(coalesce(res->'released','[]'::jsonb)) x;
    if v_released > 0 then
      n_invoices := n_invoices + 1;
      n_lines := n_lines + jsonb_array_length(res->'released');
      total := total + v_released;
      raise notice '  % (%, %) released %', r.invoice_no, r.status, r.inv_date, v_released;
    end if;
  end loop;

  raise notice '----';
  raise notice 'Released % across % line(s) on % invoice(s).', total, n_lines, n_invoices;
end $$;

-- Anything other than an explicit apply=yes is a rehearsal.
select (:'apply' = 'yes') as do_commit \gset
\if :do_commit
\echo 'APPLYING: the work above has been committed.'
commit;
\else
\echo 'DRY RUN: nothing was changed. Pass -v apply=yes to commit it.'
rollback;
\endif
