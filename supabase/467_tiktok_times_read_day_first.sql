-- 467_tiktok_times_read_day_first.sql
--
-- TIKTOK'S ORDER TIMES ARE READ DAY FIRST, WHATEVER THE DAY
--
-- WHAT WAS WRONG / WHY
--
--   TikTok's order export (csv and xlsx alike) gives every time as
--   'DD/MM/YYYY HH24:MI:SS', Singapore time. stage_tiktok_orders stores six
--   of them on each row (rts_time, created_time, paid_time, shipped_time,
--   delivered_time, cancelled_time) through tiktok_parse_time (64), which
--   first tried a cast, replace(v, '/', '-')::timestamp. A cast follows the
--   server's DateStyle, which is 'ISO, MDY' on production, so a time whose
--   day is 12 or less was read month first: '11/10/2026 19:02:31' (11
--   October) was stored as 10 November. Only days of 13 and on made the
--   cast fail and reached the day-first reading after it. A time on a day
--   equal to its month (05/05) came out right by chance.
--   The settlement sheet ('YYYY/MM/DD') and the withdrawal records
--   ('YYYY/MM/DD', 375) start with the year, which a cast always reads year,
--   month, day: those were right and stay right.
--
-- PRODUCTION (read only, 24 Oct 2026; counts only)
--
--   * tiktok_order_rows: 181 rows from 17 files, every raw time
--     'DD/MM/YYYY HH24:MI:SS' (the second number is never above 12; the
--     first is above 12 in 352 of the 809 times). 421 of the 809 stored times
--     are day/month-swapped, on 111 rows (73 of them confirmed; 285 of the
--     swapped times are on confirmed rows, 136 on rows of deleted files):
--     created_time 101, paid_time 98, rts_time 92, shipped_time 74,
--     delivered_time 49, cancelled_time 7. Every swapped time is in another
--     month than it should be, and 131 of them are in the future (after
--     24 Oct 2026). Every stored time is exactly what the old function gives
--     for the row's raw text, so the old reading explains them all.
--   * tiktok_settlement_rows (305 rows, order_created_time and settled_time)
--     and tiktok_balance_records (request_date, success_date): none wrong
--     (year first; every bank payout falls on a Wednesday).
--   * Who reads the six order-row times: nobody. No function, view or page
--     reads them; they are written (stage_tiktok_orders) and kept. The Import
--     page fetches whole rows but shows none of the six; its lists and the
--     TikTok reports (report_tiktok_qty_sold, report_tiktok_stock_activity,
--     report_tiktok_imports) date rows by confirmed_at or the file's
--     uploaded_at; the settlement reports, tiktok_reporting_month, the
--     settlement periods, tiktok_xero_payouts and tiktok_bank_payouts (the
--     Xero export) read settled_time and the withdrawal dates, which are
--     right; the Dashboard's TikTok tiles read stock and the order state. So
--     no figure in the app moves, now or when the stored times are put
--     right. 465 reads a row's shipped time from its raw text for this
--     reason.
--
-- THE RULE
--
--   A time that starts with a day and a month ('D/M/YYYY', '/', '.' or '-'
--   between) is read day first, always, by its parts (no cast, so no
--   DateStyle): the day alone, HH24:MI or HH24:MI:SS (with fractions), or an
--   hour with AM/PM. One that is not a real date or time (31/02, a 13th
--   month, 25:00) is null, as an unreadable time already was. One that
--   starts with a four-digit year is read as before. Any other time that
--   starts with two short numbers ('01/07/26') is null rather than a guess,
--   and so is text with no digit (a cast read 'now' as the moment).
--
-- WHAT THIS DOES
--
--   tiktok_parse_time(text) gets the new body (the rule above), and
--   SET search_path TO 'public' as the other TikTok helpers have. It stays
--   IMMUTABLE, plpgsql, not security definer, and keeps its grants
--   (signed-in staff, the service role; not anon). Its callers
--   (stage_tiktok_orders, stage_tiktok_settlement, stage_tiktok_settlement_file)
--   call it by name and are not changed: files staged after this file store
--   the times right.
--
-- NOT CHANGED
--
--   Every other function, every table, column, index, policy and grant. No
--   row is changed: the 421 stored times stay as they are until the separate
--   repair, scripts/tiktok/repair/467-restore-tiktok-order-times.sql, is run
--   with the Owner's go-ahead (confirmed rows are protected by
--   trg_tiktok_row_immutable; the repair says how it handles that).
--
-- NOT COVERED (to tell the owner)
--
--   * The stored times already swapped (above): the repair puts them right.
--     Until then a raw SQL look at TikTok orders by created_time or
--     shipped_time (an ad hoc count of an "October" order, say) is wrong for
--     days of 12 or less; nothing in the app shows them.
--   * A file whose times are month first (a TikTok shop set to a US locale)
--     would now be read day first (or null for days above 12). This shop's
--     files are all day first.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (465 in: 0b8580cda1e2c697a1e9219f95ed3046, 1380
--   functions) -> 467 (this file) -> the repair (separate go-ahead).
--   * Other sessions hold 462 and 463 (invoices) and 466 (affiliate sign-up:
--     existing affiliates sent to sign in). This file changes none of theirs;
--     if one goes first, the fingerprints below differ (re-work them out from
--     production's md5 list) but nothing this file checks does. It pins
--     stage_tiktok_orders and tiktok_evaluate as 465 left
--     them (its self-test stages a file): if a later file changes one, this
--     file refuses, naming it, and changes nothing; re-read, re-pin, re-test.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("already this version; left alone").
--   2. Apply (the MCP's apply_migration with this text verbatim, or the CLI).
--      It checks itself and runs its self-test.
--   3. No page change.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production (24 Oct 2026),
--     the columns the self-test reads are there with these types;
--   * tiktok_parse_time is its BEFORE (replaced; the text written here has
--     the tested AFTER md5) or its AFTER (left alone); no other function
--     takes its name;
--   * afterwards: the md5 is the AFTER one; the grants are as before
--     (compared as sets): signed-in staff and the service role may call it,
--     anon may not;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0467, so it leaves no row): the examples below read under DateStyle
--     'ISO, MDY' and 'ISO, DMY' alike; then a made-up Owner (@example.com)
--     and store stage a made-up two-row file through stage_tiktok_orders (an
--     unmapped SKU: nothing is matched, nothing touches stock, no sequence
--     is used) and the six stored times of each row are the day-first ones.
--   Locks: the function's catalogue row and the self-test's own rows. A file
--   being staged at that moment finishes first or waits (the lock timeout
--   gives up after 5 s and changes nothing).
--
-- BEFORE (production now, 24 Oct 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   tiktok_parse_time(text)                                        d7b6de34d5f955479a4f97ea9df38b0c  (as at 64)
--   relied on, not changed
--   stage_tiktok_orders(uuid,text,text,jsonb)                      9cad8a716950fdaab791f6f42cdddf7c  (465's AFTER; the self-test)
--   tiktok_evaluate(uuid,text,text,integer,text,boolean,boolean)   e099050c8c43c973721229c21adddfd3  (465's AFTER; the self-test)
--   tiktok_access_check(uuid)                                      94b85ae013171b13947013b6e1c06036  (the self-test)
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855  (the self-test)
--   public function fingerprint, production now                    0b8580cda1e2c697a1e9219f95ed3046 (1380 functions)
-- AFTER (for later guards)
--   tiktok_parse_time(text)                                        9ab3b68b4fc30013d6bc75294d68bc66
--   public function fingerprint: production now -> 467 (a second run the
--   same)                                                          732a3805a2fafa035c5a46068026c81f (1380 functions: one
--   replaced). Worked out read-only on production (24 Oct 2026) from its own
--   md5 list with this one put in; confirm it on the dry run.
--
-- Test: scripts/tiktok/tests/times-day-first-467.sql (begin ... rollback; it
-- installs 465 and this file twice, then runs the repair). Fixtures only
-- (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this replaces: BEFORE (production now) and AFTER md5s ══
  c_sig constant text := 'tiktok_parse_time(text)';
  c_before constant text := 'd7b6de34d5f955479a4f97ea9df38b0c';
  c_after constant text := '9ab3b68b4fc30013d6bc75294d68bc66';
  c_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.tiktok_parse_time(p_text text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
-- 467: a time from a TikTok file, read as Singapore time.
-- TikTok's order export gives 'DD/MM/YYYY HH24:MI:SS'. Before 467 a cast
-- was tried first, and a cast follows the server's DateStyle (MDY), so a
-- day of 12 or less was read as the month ('11/10/2026' as 10 November)
-- and only days of 13 and on reached the day-first reading. A time that
-- starts with a day and a month is now read by its parts, day first,
-- always (the day alone, HH24:MI or HH24:MI:SS, an AM/PM hour); one that
-- is not a real date or time (31/02, a 13th month, 25:00) is null.
-- One that starts with a four-digit year ('YYYY/MM/DD', the settlement and
-- withdrawal sheets; 'YYYY-MM-DD HH24:MI[:SS]') is read as before: a cast
-- reads it year, month, day whatever the DateStyle. Any other time that
-- starts with two short numbers ('01/07/26') is null rather than a
-- DateStyle guess, and so is text with no digit ('now').
declare
  v text := nullif(btrim(coalesce(p_text, '')), '');
  m text[];
  v_hour integer;
begin
  if v is null or v !~ '[0-9]' then return null; end if;
  m := regexp_match(v, '^([0-9]{1,2})[/.-]([0-9]{1,2})[/.-]([0-9]{4})(?:[ T]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}(?:\.[0-9]+)?))? *([AaPp][Mm])?)?$');
  if m is not null then
    v_hour := coalesce(m[4], '0')::integer;
    if m[7] is not null then
      if v_hour not between 1 and 12 then return null; end if;
      v_hour := v_hour % 12 + case when upper(m[7]) = 'PM' then 12 else 0 end;
    end if;
    begin
      return make_timestamp(m[3]::integer, m[2]::integer, m[1]::integer, v_hour,
                            coalesce(m[5], '0')::integer, coalesce(m[6], '0')::double precision)
             at time zone 'Asia/Singapore';
    exception when others then return null;
    end;
  end if;
  if v ~ '^[0-9]{1,2}[/. -][0-9]{1,2}([/. -]|$)' then return null; end if;
  begin
    return (replace(v, '/', '-')::timestamp) at time zone 'Asia/Singapore';
  exception when others then return null;
  end;
end $function$
$d1$;

  -- ══ Relied on, not changed (production now; the self-test) ═══════════════
  c_relied constant text[] := array[
    'stage_tiktok_orders(uuid,text,text,jsonb)',
    'tiktok_evaluate(uuid,text,text,integer,text,boolean,boolean)',
    'tiktok_access_check(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_relied_md5 constant text[] := array[
    '9cad8a716950fdaab791f6f42cdddf7c',
    'e099050c8c43c973721229c21adddfd3',
    '94b85ae013171b13947013b6e1c06036',
    'c705c733e213a27f0dc32d54322cc855'];

  -- ══ The self-test's examples: the text and what it must give (UTC) ═══════
  c_in constant text[] := array[
    '11/10/2026 19:02:31',       -- day 11: before 467, 10 November
    '13/10/2026 15:32:09',       -- day 13: read right before 467 too
    '05/05/2026 08:00:00',       -- day = month
    '01/07/2026',                -- the day alone
    '1/7/2026 9:05',             -- one-digit parts, HH24:MI
    '02/03/2026 01:45:00 PM',    -- an AM/PM hour
    '02/03/2026 12:10 AM',
    '09.08.2026 10:00:00',       -- '.' between
    '09-08-2026  10:00:00.250',  -- '-' between, two spaces, a fraction
    '2026/09/07',                -- the settlement and withdrawal sheets
    '2026-07-01 13:45:00',       -- ISO, as before
    '2026/07/01 13:45',
    '31/02/2026 10:00:00',       -- not a real date
    '05/13/2026 10:00:00',       -- a 13th month
    '01/07/2026 25:00',          -- not a real time
    '01/07/26',                  -- a two-digit year: no guess
    'now',                       -- no digit
    '   ',
    null];
  c_out constant text[] := array[
    '2026-10-11 11:02:31+00',
    '2026-10-13 07:32:09+00',
    '2026-05-05 00:00:00+00',
    '2026-06-30 16:00:00+00',
    '2026-07-01 01:05:00+00',
    '2026-03-02 05:45:00+00',
    '2026-03-01 16:10:00+00',
    '2026-08-09 02:00:00+00',
    '2026-08-09 02:00:00.25+00',
    '2026-09-06 16:00:00+00',
    '2026-07-01 05:45:00+00',
    '2026-07-01 05:45:00+00',
    null, null, null, null, null, null, null];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; v_acl text; v_make boolean := false; v_style text;
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_store uuid; t_batch uuid; t_rows jsonb; t_got text; t_want text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──────────────
  -- What it relies on and does not change: as read on production, 24 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '467: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- The columns the self-test reads, with these types.
  select string_agg(x.c || ' ' || x.ty, ', ') into v
    from (values ('batch_id', 'uuid'), ('raw', 'jsonb'), ('rts_time', 'timestamp with time zone'),
                 ('created_time', 'timestamp with time zone'), ('paid_time', 'timestamp with time zone'),
                 ('shipped_time', 'timestamp with time zone'), ('delivered_time', 'timestamp with time zone'),
                 ('cancelled_time', 'timestamp with time zone')) x(c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = 'public.tiktok_order_rows'::regclass and a.attname = x.c and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '467: these columns of tiktok_order_rows are missing or not of this type: %', v; end if;

  -- No other function takes its name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'tiktok_parse_time'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '467: another function takes the name tiktok_parse_time: %', v; end if;

  -- The text written out here is the tested one.
  if md5(c_def) <> c_after then
    raise exception '467: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  if to_regprocedure('public.' || c_sig) is null then raise exception '467: public.% is missing', c_sig; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  -- its grants, to compare after (as sets: production lists them in another
  -- order than a local copy does)
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '467: public.% is already this version; left alone', c_sig;
  elsif md5(d) = c_before then
    v_make := true;
  else
    raise exception '467: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_make then execute c_def; end if;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '467: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl
     or has_function_privilege('anon', 'public.' || c_sig, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_sig, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_sig, 'execute') then
    raise exception '467: the grants of public.% changed', c_sig; end if;
  if (select provolatile <> 'i' or prosecdef or prolang <> (select oid from pg_language where lanname = 'plpgsql')
        from pg_proc where oid = to_regprocedure('public.' || c_sig)) then
    raise exception '467: public.% is not an immutable plpgsql function without security definer', c_sig; end if;

  -- ── 4. Self-test, in a block that is always undone ─────────────────────
  -- Made-up records only ("467 check", @example.com, an unmapped SKU, so
  -- nothing is matched and nothing touches stock; no sequence is used); it
  -- ends by raising P0467, which undoes all it wrote and every setting it
  -- changed.
  begin
    -- The examples, under both DateStyles: the same answers.
    foreach v_style in array array['ISO, MDY', 'ISO, DMY'] loop
      perform set_config('DateStyle', v_style, true);
      for i in 1 .. cardinality(c_in) loop
        if public.tiktok_parse_time(c_in[i]) is distinct from c_out[i]::timestamptz then
          raise exception '467: under DateStyle %, % was read as %, not %',
            v_style, coalesce(quote_literal(c_in[i]), 'null'), coalesce(public.tiktok_parse_time(c_in[i])::text, 'null'),
            coalesce(c_out[i], 'null'); end if;
      end loop;
    end loop;
    perform set_config('DateStyle', 'ISO, MDY', true);  -- production's

    -- A two-row file staged as the Import page sends it: the six times stored
    -- day first.
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    insert into auth.users (id, email) values (gen_random_uuid(), '467-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '467 check', '467-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('467 check ' || t_sfx, '467-' || t_sfx, 'SG') returning id into t_store;
    t_rows := jsonb_build_array(
      jsonb_build_object('order_id', '467CHECK' || t_sfx || 'A', 'seller_sku', '467-' || t_sfx, 'quantity', '1',
        'order_status', 'Delivered', 'created_time', '01/11/2026 09:15:00', 'paid_time', '01/11/2026 09:16:10',
        'rts_time', '03/11/2026 18:00:00', 'shipped_time', '04/11/2026 10:30:00', 'delivered_time', '06/11/2026 14:00:00'),
      jsonb_build_object('order_id', '467CHECK' || t_sfx || 'B', 'seller_sku', '467-' || t_sfx, 'quantity', '1',
        'order_status', 'Canceled', 'created_time', '14/09/2026 23:59:59', 'paid_time', '15/09/2026 00:00:30',
        'cancelled_time', '02/10/2026 08:05:00'));
    t_batch := public.stage_tiktok_orders(t_store, '467 check.csv', null, t_rows);
    -- each row: rts, created, paid, shipped, delivered, cancelled ('-' none)
    select string_agg(r.order_id || ' ' || array_to_string(array[r.rts_time, r.created_time, r.paid_time, r.shipped_time,
                                r.delivered_time, r.cancelled_time]::text[], ' ', '-'), ' | ' order by r.row_no)
      into t_got from public.tiktok_order_rows r where r.batch_id = t_batch;
    t_want := '467CHECK' || t_sfx || 'A ' || array_to_string(array['2026-11-03 10:00:00+00', '2026-11-01 01:15:00+00',
                 '2026-11-01 01:16:10+00', '2026-11-04 02:30:00+00', '2026-11-06 06:00:00+00', null]::timestamptz[]::text[], ' ', '-')
              || ' | 467CHECK' || t_sfx || 'B ' || array_to_string(array[null, '2026-09-14 15:59:59+00',
                 '2026-09-14 16:00:30+00', null, null, '2026-10-02 00:05:00+00']::timestamptz[]::text[], ' ', '-');
    if t_got is distinct from t_want then
      raise exception '467: a staged file did not store its times day first (got %, wanted %)', t_got, t_want; end if;

    raise exception using errcode = 'P0467', message = '467: self-test done, undone';
  exception when sqlstate 'P0467' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
