-- 384_invoice_and_staff_commission_use_the_singapore_date.sql
--
-- WHAT WAS WRONG
--
-- earn_invoice_commission, earn_staff_commission and
-- reearn_invoice_staff_commission (the staff rebase) dated their rows
-- coalesce(paid_at, now())::date. The database runs in UTC, so that is the UTC
-- day. For an invoice paid between 00:00 and 07:59 in Singapore it is the day
-- before, and on the 1st of a month it is the month before: the invoice's line
-- and staff commission was booked in, and paid out with, the previous month.
--
-- Everything else dates commission on the Singapore calendar: package and
-- bundle commission (383), the part-payment layer and its close at full
-- payment (357, sg_today()). The staff rebase also picks its invoices by their
-- Singapore paid date. So one invoice paid early on the 1st was split across
-- two months: its package commission and part-payment close in the new month,
-- its line and staff commission in the old one. 357 noted that split and
-- accepted it.
--
-- In production on 3 Oct 2026 it has touched one invoice, paid at 07:51 on
-- 29 Sep. Its three staff rows (S$8.94, unpaid) are dated 28 Sep: the same
-- month, so no balance or payout moved. They are left as they are.
--
-- THE RULE
--
-- All three now date their rows the Singapore day the invoice was paid in
-- full, the expression 383 uses:
--   coalesce((paid_at at time zone 'Asia/Singapore')::date, sg_today())
--   * Payments recorded from 08:00 to 23:59 in Singapore get the same date as
--     before.
--   * Payments recorded from 00:00 to 07:59 move from the UTC day before to
--     the Singapore day they were paid.
--   * An invoice without a paid date falls back to today in Singapore, not
--     today in UTC.
--
-- WHAT THIS DOES
--
-- Patches the date expression of each function and nothing else: one anchor
-- per function, which must match exactly once, replaced by the Singapore date.
-- The '357:' markers stay in earn_staff_commission and
-- reearn_invoice_staff_commission, so re-running 357 still leaves them alone.
-- (357's own section 2 is amended to the same rule, so a re-run no longer
-- refuses now that earn_invoice_commission has moved on.)
--
-- NOT CHANGED
--
--   * Rows already written, including the three staff rows above. A staff
--     rebase or a correction of that invoice re-dates them to 29 Sep.
--   * invoice_affiliate_commission_preview (357), derived from
--     earn_invoice_commission, keeps its copy of the old date line. It returns
--     amounts, not dates, so nothing it answers changes.
--   * Readers: they bucket by invoice_paid_date, as before.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block), so
-- it is atomic however it is run. Every guard and anchor is checked, and every
-- patched text built, before anything is installed. md5(pg_get_functiondef)
-- must be the production version read on 3 Oct 2026 (BEFORE), or already this
-- migration's version (AFTER), which is left alone so a re-run changes
-- nothing. Anything else refuses. After installing, each function must have
-- its AFTER md5. The patched texts are executed as CREATE OR REPLACE, which
-- keeps owner and grants. Functions only; no data changes.
--
-- BEFORE (production, 3 Oct 2026, md5 of pg_get_functiondef):
--   earn_invoice_commission(uuid)                 2e4942e9ff859b0469fdcd99faf325fd
--   earn_staff_commission(uuid)                   c30c46533c1de8e42f1846d35dfcc2c0
--   reearn_invoice_staff_commission(uuid,text)    5814055c0c30a9831e8bd43ca169900e
-- AFTER (for later guards):
--   earn_invoice_commission(uuid)                 96199e3a2779c4392e936e9e3d0be66b
--   earn_staff_commission(uuid)                   03e4de1a5ba3d372e6cbb4de64b2c92d
--   reearn_invoice_staff_commission(uuid,text)    6b5f9383c2763e0a70da5f21a368b5cd
--
-- Test: scripts/commissions/tests/commission-singapore-date.sql.

set lock_timeout = '5s';

do $mig$
declare
  r record; d text; v text; n int;
  v_fns text[] := '{}'; v_defs text[] := '{}'; i int;
begin
  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    ('earn_invoice_commission(uuid)',
     '2e4942e9ff859b0469fdcd99faf325fd', '96199e3a2779c4392e936e9e3d0be66b',
     E'  v_paid_date := coalesce(v_inv.paid_at, now())::date;\n',
     E'  -- 384: the Singapore day the invoice was paid in full, as package and\n'
     || E'  -- bundle commission (383) and part payments (357) are dated. paid_at::date\n'
     || E'  -- was the UTC day: the day before for a payment made before 08:00.\n'
     || E'  v_paid_date := coalesce((v_inv.paid_at at time zone ''Asia/Singapore'')::date, public.sg_today());\n'),
    ('earn_staff_commission(uuid)',
     'c30c46533c1de8e42f1846d35dfcc2c0', '03e4de1a5ba3d372e6cbb4de64b2c92d',
     E'  v_paid_date := coalesce(v_inv.paid_at, now())::date;\n',
     E'  -- 384: the Singapore day the invoice was paid in full, as part payments\n'
     || E'  -- (357) are dated. paid_at::date was the UTC day: the day before for a\n'
     || E'  -- payment made before 08:00.\n'
     || E'  v_paid_date := coalesce((v_inv.paid_at at time zone ''Asia/Singapore'')::date, public.sg_today());\n'),
    ('reearn_invoice_staff_commission(uuid,text)',
     '5814055c0c30a9831e8bd43ca169900e', '6b5f9383c2763e0a70da5f21a368b5cd',
     E'v_share, ''earned'', coalesce(v_inv.paid_at, now())::date);\n',
     E'v_share, ''earned'', coalesce((v_inv.paid_at at time zone ''Asia/Singapore'')::date, public.sg_today()));  -- 384: the Singapore day\n')
  ) x(fn, before_md5, after_md5, anchor, replacement)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '384: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '384: public.% already dates by the Singapore day; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '384: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    n := (length(d) - length(replace(d, r.anchor, ''))) / length(r.anchor);
    if n <> 1 then
      raise exception '384: the date anchor of public.% was found % times, not once', r.fn, n; end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || replace(d, r.anchor, r.replacement);
  end loop;

  -- ── Install ───────────────────────────────────────────────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('earn_invoice_commission(uuid)', '96199e3a2779c4392e936e9e3d0be66b'),
    ('earn_staff_commission(uuid)', '03e4de1a5ba3d372e6cbb4de64b2c92d'),
    ('reearn_invoice_staff_commission(uuid,text)', '6b5f9383c2763e0a70da5f21a368b5cd')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      raise exception '384: public.% was installed with md5 %, not the tested %', r.fn, v, r.after_md5; end if;
  end loop;
end $mig$;
