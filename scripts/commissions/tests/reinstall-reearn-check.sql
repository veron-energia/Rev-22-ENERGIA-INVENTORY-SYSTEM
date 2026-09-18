-- Assertions for the reinstall + re-earn test. Run with -v phase=dry after the
-- rehearsal, -v phase=applied after the real run, -v phase=again after a
-- second real run (which must find nothing left to do). Isolated local
-- database only.
\set ON_ERROR_STOP on
\if :{?rows} \else \set rows '' \endif
select set_config('reearn.test_phase', :'phase', false) as _phase,
       set_config('reearn.test_rows', :'rows', false) as _rows \gset

create function pg_temp.check(ok boolean, message text) returns void language plpgsql as
$$ begin if ok is distinct from true then raise exception 'FAIL (%): %', current_setting('reearn.test_phase'), message; end if; end $$;

-- Live rows for one fixture invoice, as "tier name amount status".
create function pg_temp.live(p_no text) returns text language sql as $$
  select coalesce(string_agg(format('%s %s %s %s', x.tier, c.full_name, x.commission_amount, x.status), '; '
                             order by x.tier, c.full_name), '')
    from public.commissions x
    join public.invoices i on i.id = x.invoice_id
    join public.customers c on c.id = x.referrer_customer_id
   where i.invoice_no = p_no and x.status <> 'reversed'
$$;
create function pg_temp.reversed(p_no text) returns integer language sql as $$
  select count(*)::integer from public.commissions x join public.invoices i on i.id = x.invoice_id
   where i.invoice_no = p_no and x.status = 'reversed'
$$;

do $$
declare phase text := current_setting('reearn.test_phase'); n integer;
begin
  -- 334 itself: the markers of every patch are present.
  perform pg_temp.check(position('affiliate_selection_explicit' in pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure)) > 0, '334 reinstalled earn_invoice_commission');
  perform pg_temp.check(position('affiliate_selection_explicit=true' in pg_get_functiondef('public.set_invoice_affiliate(uuid,uuid)'::regprocedure)) > 0, '334 reinstalled set_invoice_affiliate');

  if phase = 'dry' then
    -- The rehearsal changed nothing: the old build's rows stand untouched.
    perform pg_temp.check(pg_temp.live('REEARN-0222') = '', 'dry: 0222 still has nothing');
    perform pg_temp.check(pg_temp.live('REEARN-0227') = 'tier1 Reearn Alaric (duplicate) 3.30 earned', 'dry: 0227 still credits the duplicate');
    perform pg_temp.check(pg_temp.live('REEARN-0158') = 'tier1 Reearn Zoe 112.05 earned; tier2 Reearn Chiao 5.60 earned', 'dry: 0158 still at 5%');
    perform pg_temp.check(pg_temp.live('REEARN-NONE') = 'tier1 Reearn Erin 30.00 earned', 'dry: explicit None still paid');
    perform pg_temp.check(pg_temp.live('REEARN-0220') = '', 'dry: 0220 still has nothing');
    perform pg_temp.check((select count(*) from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no like 'REEARN-%' and x.status = 'reversed') = 0, 'dry: nothing reversed');
    perform pg_temp.check(not exists (select 1 from public.audit_logs where action = 'commission_reearned'), 'dry: no audit rows');
    return;
  end if;

  -- After the real run.
  perform pg_temp.check(pg_temp.live('REEARN-0222') = 'tier1 Reearn Marlinah 11.55 earned', '0222: the selected affiliate earns 15% of the discounted line');
  perform pg_temp.check(pg_temp.reversed('REEARN-0222') = 0, '0222: nothing to reverse');

  perform pg_temp.check(pg_temp.live('REEARN-0227') = 'tier1 Reearn Alaric Ong 3.30 earned', '0227: commission moves to the selected affiliate');
  perform pg_temp.check(pg_temp.reversed('REEARN-0227') = 1, '0227: the duplicate''s row is reversed');
  perform pg_temp.check((select bool_and(reversal_reason like 'Re-earned after 334%') from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no = 'REEARN-0227' and x.status = 'reversed'), '0227: reversal carries the reason');

  perform pg_temp.check(pg_temp.live('REEARN-0158') = 'tier1 Reearn Zoe 112.05 earned; tier2 Reearn Chiao 39.22 blocked', '0158: tier 2 at the configured 35%, blocked for a person not activated');
  perform pg_temp.check((select block_reason = 'Affiliate Not Activated' from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no = 'REEARN-0158' and x.tier = 'tier2' and x.status = 'blocked'), '0158: block reason recorded');

  perform pg_temp.check(pg_temp.live('REEARN-0215') = 'tier1 Reearn Madalene 38.85 earned', '0215: same answer');
  perform pg_temp.check(pg_temp.reversed('REEARN-0215') = 0, '0215: untouched, no reversal');
  perform pg_temp.check((select count(*) = 1 from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no = 'REEARN-0215'), '0215: still one row, the original');

  perform pg_temp.check(pg_temp.live('REEARN-PAID') = 'tier1 Reearn Carol 15.00 paid', 'PAID: money already paid out is not touched');
  perform pg_temp.check(pg_temp.reversed('REEARN-PAID') = 0, 'PAID: no reversal');
  perform pg_temp.check((select count(*) = 1 from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no = 'REEARN-PAID'), 'PAID: no new rows');

  perform pg_temp.check(pg_temp.live('REEARN-NONE') = '', 'NONE: an explicit None earns nothing');
  perform pg_temp.check(pg_temp.reversed('REEARN-NONE') = 1, 'NONE: the old row is reversed');

  perform pg_temp.check((select count(*) = 0 from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no = 'REEARN-REFUNDED'), 'REFUNDED: left alone');

  perform pg_temp.check(pg_temp.live('REEARN-0220') = 'tier1 Reearn Ivy 9.15 earned; tier1 Reearn Ivy 9.15 earned', '0220: each promotion line earns for the selected affiliate');

  -- One audit row per changed invoice, none for the unchanged or reviewed.
  select count(*) into n from public.audit_logs a
   where a.action = 'commission_reearned'
     and a.record_id in (select id from public.invoices where invoice_no in ('REEARN-0222','REEARN-0227','REEARN-0158','REEARN-NONE','REEARN-0220'));
  perform pg_temp.check(n = 5, format('five audit rows for the five changed invoices, got %s', n));
  perform pg_temp.check(not exists (select 1 from public.audit_logs a where a.action = 'commission_reearned'
     and a.record_id in (select id from public.invoices where invoice_no in ('REEARN-0215','REEARN-PAID','REEARN-REFUNDED'))), 'no audit row where nothing changed');

  if phase = 'again' then
    -- The second real run found the same answer everywhere: no new rows, no
    -- new reversals, no new audit rows beyond the five.
    perform pg_temp.check((select count(*) from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no like 'REEARN-%') = current_setting('reearn.test_rows')::integer, 'again: no new rows since the first real run');
    perform pg_temp.check((select count(*) from public.audit_logs where action = 'commission_reearned') = 5, 'again: still five audit rows');
  end if;
end $$;
