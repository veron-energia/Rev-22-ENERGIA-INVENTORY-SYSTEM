-- UNDO of 528 (with the user's go-ahead). It puts update_customer, update_survey_particulars_v2,
-- set_invoice_affiliate and correct_invoice back to their text before 528 (md5 65111003…,
-- 45ebc42b…, eb4dc4b9…, cea93a5d…) and drops customer_is_affiliate_or_portal_login: a customer's
-- email changes with no reason, by any Staff login, an affiliate's and a portal login's too;
-- Staff add a referrer to a customer of any age; Staff change the affiliate on an unpaid invoice,
-- and in a correction (the security audit's M11 open again). The grants of the four functions
-- stay as they are; the audit rows written while 528 was in stay.
--
-- FIRST put back the pages of before 528: the Customers page and the health survey window call
-- customer_is_affiliate_or_portal_login when Edit opens (without it the email field simply stays
-- open, and the page logs the error).
--
-- It refuses, with nothing changed, unless the five functions are exactly 528's versions (so a
-- later version is never overwritten). One transaction, all or nothing; it waits at most 5
-- seconds for a lock. The 528 row in supabase_migrations.schema_migrations stays; with the
-- user's OK, remove that one row (found by its name,
-- 528_email_referrer_and_invoice_affiliate_need_owner_or_manager) or record this UNDO beside it.
--
-- The patch texts below are 528's, the other way round: each 528 text is found exactly once and
-- put back as it was.
do $undo$
declare
  c_sig constant text[] := array[
    'update_customer(uuid,jsonb,text,timestamp with time zone)',
    'update_survey_particulars_v2(uuid,jsonb,text)',
    'set_invoice_affiliate(uuid,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)'];
  c_528 constant text[] := array[
    '0d988feda9c7b39cf7fd23790d7eac56',
    'c8df8ff415d633bd29a1d6cd752eff73',
    'fc8ee382615ab8779fe9283656f1ba26',
    'aaf592490eb5d13ca2ccb0544f48f647'];
  c_before_528 constant text[] := array[
    '6511100316418394409d8baf1d2b52e0',
    '45ebc42b54405810b104d4c0c292dcf5',
    'eb4dc4b9b7eda73ef75a122d48dcdb6a',
    'cea93a5dd73d429f6437f4c9a8fcaa52'];
  c_new_sig constant text[] := array['customer_is_affiliate_or_portal_login(uuid)'];
  c_new_md5 constant text[] := array['1482d6488135976f8ffec3ec684bbc70'];
  c_fn constant int[] := array[1, 1, 2, 3, 4];
  c_anchor constant text[] := array[
-- 1 update_customer: a referrer added
$a$    if not exists (select 1 from public.customers r where r.id = v_new.referred_by and r.deleted_at is null) then
      raise exception 'That referrer is not on the customer list';
    end if;
  end if;
$a$,
-- 1 update_customer: the email
$a$    perform set_config('energia.phone_change_reason', v_reason, true);
  end if;

  update public.customers c
$a$,
-- 2 update_survey_particulars_v2: the email the customer gets
$a$      perform set_config('energia.phone_change_reason', v_reason, true);
    end if;
  end if;
$a$,
-- 3 set_invoice_affiliate
$a$begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
$a$,
-- 4 correct_invoice
$a$ -- 370: the names of people on unchanged ticket lines.
 perform public.event_sync_ticket_names(i.id,p_items);
$a$];
  c_new constant text[] := array[
-- 1 update_customer: a referrer added
$n$    if not exists (select 1 from public.customers r where r.id = v_new.referred_by and r.deleted_at is null) then
      raise exception 'That referrer is not on the customer list';
    end if;
    -- 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026): the referrer decides who
    -- earns commission. Staff add a missing one on the day the customer is made (its created_at
    -- as a Singapore date is today); to a customer made before today only an Owner or Manager
    -- adds one.
    if (v_old.created_at at time zone 'Asia/Singapore')::date < public.sg_today()
       and not public.is_owner_or_manager() then
      raise exception 'Only an Owner or Manager can add a referrer to a customer created before today. Use Correct Referrer.'
        using errcode = '42501';
    end if;
  end if;
$n$,
-- 1 update_customer: the email
$n$    perform set_config('energia.phone_change_reason', v_reason, true);
  end if;
  -- 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026): the record's email can
  -- prove a portal login (affiliate_login_link_proof). Every change of it needs a reason (kept
  -- in the audit row); an affiliate's or a portal login's only an Owner or Manager changes.
  if 'email' = any (v_changed) then
    if not public.is_owner_or_manager() and public.customer_is_affiliate_or_portal_login(p_customer_id) then
      raise exception 'Only an Owner or Manager can change the email of an affiliate or a customer with a portal login'
        using errcode = '42501';
    end if;
    if v_reason is null then
      raise exception 'A reason is required to change a customer''s email';
    end if;
  end if;

  update public.customers c
$n$,
-- 2 update_survey_particulars_v2: the email the customer gets
$n$      perform set_config('energia.phone_change_reason', v_reason, true);
    end if;
    -- 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026): a new email for the
    -- customer, as on the Customers page (update_customer): a reason, and an affiliate's or a
    -- portal login's only an Owner or Manager changes.
    if v_cafter ? 'email' then
      if not public.is_owner_or_manager() and public.customer_is_affiliate_or_portal_login(v_cold.id) then
        raise exception 'Only an Owner or Manager can change the email of an affiliate or a customer with a portal login'
          using errcode = '42501';
      end if;
      if v_reason is null then
        raise exception 'A reason is required to change a customer''s email';
      end if;
    end if;
  end if;
$n$,
-- 3 set_invoice_affiliate
$n$begin
  -- 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026): the affiliate on an
  -- invoice already made (it earns tier 1) is changed by an Owner or Manager only. Staff choose
  -- it while making the invoice (create_invoice_with_details), as before.
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can change the affiliate on an invoice after it is made'
      using errcode = '42501';
  end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
$n$,
-- 4 correct_invoice
$n$ -- 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026: "Owner/Manager for every
 -- change"): the affiliate on an invoice already made (it earns tier 1) is changed by an Owner
 -- or Manager only, in a correction as in set_invoice_affiliate, paid or unpaid. A change is
 -- another affiliate, or "none" where the customer's referrer earned (the explicit flag decides
 -- only when there is no affiliate); the affiliate the invoice has, sent again, is none.
 -- Checked before anything is written.
 if p_header ? 'affiliate_id'
    and (nullif(p_header->>'affiliate_id','')::uuid is distinct from i.affiliate_id
         or (i.affiliate_id is null and not coalesce(i.affiliate_selection_explicit,false)))
    and not public.is_owner_or_manager() then
   raise exception 'Only an Owner or Manager can change the affiliate on an invoice after it is made' using errcode = '42501'; end if;
 -- 370: the names of people on unchanged ticket lines.
 perform public.event_sync_ticket_names(i.id,p_items);
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[4]);
  v_acl text[] := array_fill(null::text, array[4]);
  i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception 'UNDO 528: public.% is missing', c_sig[i]; end if;
    v_def[i] := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(v_def[i]) <> c_528[i] then
      raise exception 'UNDO 528: public.% is not 528''s version (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception 'UNDO 528: public.% is missing or not 528''s version. Nothing changed.', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 528: patch % does not find 528''s text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before_528[i] then
      raise exception 'UNDO 528: the text put back for public.% is not the one before 528 (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Put back, then drop the new function (no function calls it any more)
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    execute format('drop function public.%s', c_new_sig[i]);
  end loop;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before_528[i] then
      raise exception 'UNDO 528: public.% was put back with an md5 other than the one before 528', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception 'UNDO 528: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is not null then
      raise exception 'UNDO 528: public.% is still there', c_new_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
