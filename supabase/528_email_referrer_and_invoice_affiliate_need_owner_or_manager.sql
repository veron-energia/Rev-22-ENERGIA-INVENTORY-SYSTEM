-- 528_email_referrer_and_invoice_affiliate_need_owner_or_manager.sql
--
-- A CUSTOMER'S EMAIL NEEDS A REASON, AND AN AFFILIATE'S AN OWNER OR MANAGER; STAFF ADD A
-- REFERRER ONLY ON THE DAY THE CUSTOMER IS MADE; ONLY AN OWNER OR MANAGER CHANGES THE AFFILIATE
-- ON AN INVOICE ALREADY MADE
--
--   From the security audit of 17 Nov 2026 (finding M11).
--   The BEFORE md5s and the relied-on md5s below are those of production after 527 (the local
--   copy of 19 Nov 2026). If production differs when this is applied, it refuses and changes
--   nothing.
--   (The number 528 is this file's name and its errors' prefix; if it changes at commit,
--   change it there, in the 528 comments it writes into the five functions (and so their AFTER
--   md5s, also in scripts/customers/undo-528.sql and in the suites that know them), and in the
--   name and path of its suite.)
--
-- WHAT WAS WRONG
--
--   Any Staff login could set the fields that prove a portal login and decide who earns
--   commission:
--     1. A customer's email was changed with no reason (update_customer on the Customers page,
--        and update_survey_particulars_v2, whose Edit details on a health survey carries a new
--        email onto the customer). Since 508 the record's email decides whether a portal login
--        attached to it is proven (affiliate_login_link_proof, proof (d): the login's verified
--        email is the record's email), so a changed email could open an affiliate's portal to
--        whoever owns the new inbox.
--     2. Staff could set the referrer of ANY customer who had none (update_customer), however
--        old the customer; the referrer then earns commission on what the customer buys.
--     3. Staff could put any active affiliate on an unpaid invoice after it was made
--        (set_invoice_affiliate, the Affiliate box of the invoice view); that affiliate then earns
--        tier 1 on it. They could also change it in a correction (correct_invoice: an unpaid
--        invoice's Edit Invoice, and a paid or part-paid one Staff may correct since 377): its
--        check of who may change the invoice's attribution covers "Raised by" only.
--
-- THE RULE (the user, 19 Nov 2026)
--
--   1. "Every change of a customer's email needs a reason (like a phone change). Staff can
--      still change a plain customer's email (with a reason). The email of a customer who is an
--      affiliate or has a portal login can be changed only by an Owner or Manager (with a
--      reason). Affiliates keep changing their own email in the portal."
--   2. "Staff can set a missing referrer when they create the customer or on the same day
--      (Singapore date). Adding a referrer to a customer created before today needs an Owner or
--      Manager. Changing or removing a referrer stays Owner/Manager only."
--   3. "Changing the affiliate on an existing unpaid invoice needs an Owner or Manager.
--      Choosing the affiliate while making an invoice stays with staff." And (the same day), in
--      every path, the invoice view and corrections alike, paid or unpaid: "Owner/Manager for
--      every change".
--
-- WHAT THIS DOES
--
--   * customer_is_affiliate_or_portal_login(customer), new, for signed-in staff and the
--     service role: true when the customer is an affiliate (a customer_affiliates row not
--     deleted, whatever its status) or has a portal login (an affiliate_accounts row, claimed or
--     disabled: a disabled login can be switched back on, and its proof (d) would then read the
--     email). The one place this is decided; the two functions below and the pages ask it.
--   * update_customer: a changed email needs a reason ('A reason is required to change a
--     customer's email', as a phone change), kept in its audit row as before; for such a
--     customer only an Owner or Manager changes it (42501). A referrer added to a customer whose
--     created_at, as a Singapore date, is before public.sg_today() needs an Owner or Manager
--     (42501, pointing to Correct Referrer); on the day it is made Staff add it as before.
--     Changing or removing a referrer is refused as before (Correct Referrer).
--   * update_survey_particulars_v2: the same email rule when the survey's new email goes onto
--     the customer (a survey with no customer, or an email the customer already has, is not a
--     customer's email change).
--   * set_invoice_affiliate: only an Owner or Manager (42501), before anything is read or
--     locked; the rest as before (unpaid only, store access, an active affiliate, its revision
--     and audit rows).
--   * correct_invoice: a correction that changes who earns tier 1 (the affiliate sent is not
--     the invoice's, or "none" is sent where the customer's referrer earned) is refused for
--     anyone but an Owner or Manager (42501, set_invoice_affiliate's words), before anything
--     is written. Sending the affiliate the invoice has is no change (the explicit flag matters
--     only when there is no affiliate: earn_invoice_commission, invoice_effective_affiliate).
--     Every other check and message is word for word as before; Staff still correct a paid or
--     part-paid invoice (377) when they leave the affiliate alone.
--   "An Owner or Manager" is public.is_owner_or_manager(): an ACTIVE Owner or Manager, as
--   Correct Referrer asks (the old Admin role is not one, so it is treated as Staff here). A call
--   with no login (the service role) is not one either: no server path changes an affiliate's
--   email, adds a referrer or calls set_invoice_affiliate (read on the copy of 19 Nov 2026), so
--   one that did would be refused, not let through.
--
-- WHAT THIS LEAVES ALONE
--
--   * The affiliate's own email change in the portal (491/493: the affiliate-details Edge
--     Function, affiliate_detail_change_finish, the service role; it never calls these).
--   * affiliate_login_link_proof (a changed email still counts as proof (d); the Owner/Manager
--     rule is the guard, the user's choice).
--   * Making a customer (create_customer_quick: Staff set the referrer as before) and making an
--     invoice with its affiliate (create_invoice_with_details, create_split_credit_package_
--     invoices, create_split_premium_bundle_invoices: none calls set_invoice_affiliate).
--   * Correct Referrer (reassign_customer_referrer), unchanged.
--   * link_affiliate_signup (an Owner or Manager; it gives update_customer a reason, so it copies
--     the sign-up email as before).
--   * The grants of the four changed functions; every row already written; no data changes.
--
-- UNDO
--
--   First put back the pages of before 528 (they call customer_is_affiliate_or_portal_login).
--   Then scripts/customers/undo-528.sql (it refuses unless the five functions are 528's
--   versions): update_customer, update_survey_particulars_v2, set_invoice_affiliate and
--   correct_invoice are put back exactly as they were, and customer_is_affiliate_or_portal_login
--   is dropped. The audit rows stay. A later migration changing any of the four must pin 528's
--   AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/customers/tests/email-referrer-invoice-affiliate-528.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched and new ones rely on, as tested; and link_affiliate_signup, the one
  -- other function that calls update_customer (an Owner or Manager, with a reason).
  c_relied constant text[] := array[
    'require_active_staff(text[])',
    'is_owner_or_manager()',
    'sg_today()',
    'affiliate_login_link_proof(uuid,uuid)',
    'link_affiliate_signup(uuid,uuid,text,uuid,boolean)'];
  c_relied_md5 constant text[] := array[
    '877b3aa74cea559881979bb161c450e2',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '1c1289f18e24d8370e9a6364c9c06fca',
    '2484fb464733c124213b96152837a660',
    '198780b31301695db55c4a39ba9618f8'];
  -- The functions patched.
  c_sig constant text[] := array[
    'update_customer(uuid,jsonb,text,timestamp with time zone)',
    'update_survey_particulars_v2(uuid,jsonb,text)',
    'set_invoice_affiliate(uuid,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)'];
  c_before constant text[] := array[
    '6511100316418394409d8baf1d2b52e0',
    '45ebc42b54405810b104d4c0c292dcf5',
    'eb4dc4b9b7eda73ef75a122d48dcdb6a',
    'cea93a5dd73d429f6437f4c9a8fcaa52'];
  c_after constant text[] := array[
    '0d988feda9c7b39cf7fd23790d7eac56',
    'c8df8ff415d633bd29a1d6cd752eff73',
    'fc8ee382615ab8779fe9283656f1ba26',
    'aaf592490eb5d13ca2ccb0544f48f647'];
  -- Their grants, before and after (signed-in logins and the service role, as before).
  c_acl constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- Five patches, each found exactly once in its function: two in update_customer (the
  -- referrer added, the email changed), one in update_survey_particulars_v2 (the email the
  -- customer gets), one in set_invoice_affiliate (who may), one in correct_invoice (who may
  -- change the affiliate).
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
  -- The new function.
  c_new_sig constant text[] := array[
    'customer_is_affiliate_or_portal_login(uuid)'];
  c_new_md5 constant text[] := array[
    '1482d6488135976f8ffec3ec684bbc70'];
  c_new_grantees constant text[] := array[
    'authenticated, service_role'];
  c_new_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_new_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.customer_is_affiliate_or_portal_login(p_customer_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026): the customers whose email
  -- only an Owner or Manager changes, the one place this is decided (update_customer,
  -- update_survey_particulars_v2 and the pages ask it). An affiliate: a customer_affiliates row
  -- not deleted, whatever its status. A portal login: an affiliate_accounts row, claimed or
  -- disabled (a disabled login can be switched back on, and the record's email can then prove
  -- it, affiliate_login_link_proof (d)). Signed-in staff only (any active staff role); the
  -- service role passes.
  perform public.require_active_staff();
  if p_customer_id is null then return false; end if;
  return exists (select 1 from public.customer_affiliates a where a.customer_id = p_customer_id and a.deleted_at is null)
      or exists (select 1 from public.affiliate_accounts x where x.customer_id = p_customer_id);
end $function$
$def$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[4]);
  v_make boolean[] := array_fill(false, array[4]);
  v_acl text[] := array_fill(null::text, array[4]);
  v_make_new boolean[] := array_fill(false, array[1]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '528: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  -- What the rules read: the customer's created_at, an affiliate record and a portal login.
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'customers' and column_name = 'created_at' and is_nullable = 'NO')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'customer_affiliates' and column_name = 'deleted_at')
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'affiliate_accounts' and column_name = 'customer_id') then
    raise exception '528: public.customers.created_at (not null), public.customer_affiliates.deleted_at or public.affiliate_accounts.customer_id is missing';
  end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '528: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if v_acl[i] is distinct from c_acl then
      raise exception '528: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_sig[i], v_acl[i]; end if;
    if md5(d) = c_after[i] then
      raise notice '528: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '528: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '528: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '528: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;
  -- The new function: missing (made), or 528's already with its rights (left alone).
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(c_new_def[i]) <> c_new_md5[i] then
      raise exception '528: the text of public.% in this file is not the tested one (md5 %)', c_new_sig[i], md5(c_new_def[i]); end if;
    if to_regprocedure('public.' || c_new_sig[i]) is null then
      v_make_new[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) = c_new_md5[i]
          and (select coalesce(string_agg(x::text, ',' order by x::text), '')
                 from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) = c_new_acl[i] then
      raise notice '528: public.% is already there; left alone', c_new_sig[i];
    else
      raise exception '528: a function public.% is there, but not 528''s. Re-read it before applying.', c_new_sig[i];
    end if;
  end loop;

  -- 2. Install: the new function first (the patched ones call it)
  for i in 1 .. cardinality(c_new_sig) loop
    if v_make_new[i] then
      execute c_new_def[i];
      execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
      execute format('grant execute on function public.%s to %s', c_new_sig[i], c_new_grantees[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '528: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '528: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '528: public.% was installed with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i] then
      raise exception '528: the rights on public.% are not the tested ones', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '528: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
