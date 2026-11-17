-- 513_old_invoice_and_transfer_routes_are_closed.sql
--
-- THE OLD INVOICE AND TRANSFER ROUTES ARE CLOSED TO LOGINS
--
--   From the security audit of 17 Nov 2026 (finding L2).
--   The BEFORE md5 and rights below were compared with production on 17 Nov 2026 (head 512)
--   and match. If production differs when this is applied, it refuses and changes nothing.
--   (The number 513 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   Older ways in were still open to every signed-in member of staff, beside the routes the
--   pages use, and they skip what those routes check:
--   * create_invoice. New Invoice uses create_invoice_with_details, which checks the business
--     date (never after today), refuses a customer record a merge retired or Delete customer
--     removed, asks the reason for a manual discount, keeps the printed note to 500
--     characters and gives back the invoice a resent request already made. It then calls
--     create_invoice. Called on its own, create_invoice skips all of that.
--   * update_invoice, the old Edit Invoice. It hands the change to correct_invoice without a
--     request id, so a resent request is not recognised. Nothing calls it.
--   * repair_create_invoice_package_branches(), a one-off repair from 302 that rewrites
--     create_invoice and update_invoice. Nothing calls it. It runs with the caller's own
--     rights, which cannot rewrite either, but it does not belong in the API.
--   * create_transfer_request for Staff. The Transfers page sends a Staff request through
--     create_staff_transfer_request: it names only the store the stock is for, and an Owner
--     or Manager chooses where it comes from at Review. create_transfer_request lets the
--     caller choose the source, so Staff could still pick any warehouse, or another of their
--     stores, themselves.
--
-- WHAT THIS DOES
--
--   * create_invoice, update_invoice and repair_create_invoice_package_branches(): signed-in
--     logins can no longer call them. The service role and the database's own functions
--     still can: create_invoice_with_details and correct_invoice run with their owner's
--     rights, so New Invoice and Edit Invoice work as before.
--   * create_transfer_request refuses Staff, after its checks of the two ends, which keep
--     their own messages ("Staff ask for stock with New Transfer on the Transfers page; an
--     Owner or Manager chooses where it comes from."). Owners, Admins, Managers and Inventory
--     Managers use it as before. Its three Staff checks of the two ends (no warehouse to
--     warehouse; only their own stores) are replaced by the refusal, as Staff no longer get
--     that far.
--
-- WHAT THIS LEAVES ALONE
--
--   * create_staff_transfer_request, create_invoice_with_details and correct_invoice, the
--     pages' routes (relied on, checked below).
--   * The bodies of create_invoice, update_invoice and the repair function.
--
-- UNDO
--
--   create_transfer_request: run this block with c_before and c_after swapped and c_anchor
--   and c_new swapped (it then refuses unless the function is 513's version). The rights:
--   grant execute on function public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb),
--   public.update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text) and
--   public.repair_create_invoice_package_branches() to authenticated. A later migration
--   changing create_transfer_request must pin 513's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/old-routes-closed-513.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function this patches: BEFORE (production, 17 Nov 2026) and AFTER md5s
  c_sig constant text[] := array[
    'create_transfer_request(text,text,uuid,text,uuid,jsonb,text)'];
  c_before constant text[] := array[
    '99d7e65385165464fb6e4395f4d4c25f'];
  c_after constant text[] := array[
    'ab4312ec8850847b9058d07776cb1d15'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO swaps them back.
  c_fn constant int[] := array[1];
  c_anchor constant text[] := array[
$a$  if v_role = 'staff' then
    if v_src_type='warehouse' and v_dst_type='warehouse' then raise exception 'Staff cannot request warehouse-to-warehouse transfers'; end if;
    if v_src_type='store' and not public.user_has_store_access(p_source_id) then raise exception 'Staff can only transfer from their assigned store'; end if;
    if v_dst_type='store' and not public.user_has_store_access(p_dest_id) then raise exception 'Staff can only transfer to their assigned store'; end if;
  end if;$a$];
  c_new constant text[] := array[
$n$  -- 513: Staff ask for stock through create_staff_transfer_request (New
  -- Transfer on the Transfers page), which leaves where it comes from to an
  -- Owner or Manager at Review. This route lets the caller choose the source,
  -- and was still open to Staff (security audit of 17 Nov 2026, L2).
  if v_role = 'staff' then
    raise exception 'Staff ask for stock with New Transfer on the Transfers page; an Owner or Manager chooses where it comes from.'
      using errcode = '42501';
  end if;$n$];
  -- Signed-in logins can no longer call these. Their bodies stay; the service role and the
  -- database's own functions (SECURITY DEFINER) still can.
  c_revoke constant text[] := array[
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text)',
    'repair_create_invoice_package_branches()'];
  c_rights_before constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_rights_after constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- Relied on, not changed: the pages' routes, which must run with their owner's rights to
  -- keep calling create_invoice and update_invoice's work, and Staff's transfer route.
  c_relied constant text[] := array[
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'create_staff_transfer_request(jsonb,text,uuid)',
    'current_user_role()'];
  c_relied_md5 constant text[] := array[
    '0ac29c7aa909dd756ec572645ca86448',
    'cea93a5dd73d429f6437f4c9a8fcaa52',
    'cc32ec91b2e223c67da957dd792af12e',
    '519b0a33a3548f970c5d585b6e76a389'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_revoke boolean[] := array_fill(false, array[3]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '513: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  -- The pages' routes keep working only while they run with their owner's rights, and
  -- Staff keep a way to ask for stock only while they can call create_staff_transfer_request.
  if not (select bool_and(p.prosecdef) from pg_proc p
           where p.oid in (to_regprocedure('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'),
                           to_regprocedure('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'))) then
    raise exception '513: create_invoice_with_details or correct_invoice no longer runs with its owner''s rights'; end if;
  if not has_function_privilege('authenticated', 'public.create_staff_transfer_request(jsonb,text,uuid)', 'execute') then
    raise exception '513: signed-in logins cannot call create_staff_transfer_request, Staff''s way to ask for stock'; end if;

  -- The function it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '513: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '513: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '513: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '513: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '513: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- The functions closed to logins: signed-in logins can call them (revoked), or no longer
  -- can (left alone). Rights are compared as sets.
  for i in 1 .. cardinality(c_revoke) loop
    if to_regprocedure('public.' || c_revoke[i]) is null then raise exception '513: public.% is missing', c_revoke[i]; end if;
    d := (select coalesce(string_agg(x::text, ',' order by x::text), '')
            from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i]));
    if d = c_rights_before then
      v_revoke[i] := true;
    elsif d = c_rights_after then
      raise notice '513: signed-in logins already cannot call public.%; left alone', c_revoke[i];
    else
      raise exception '513: the rights on public.% are not the ones this was tested against (%). Re-read them and re-test before applying.', c_revoke[i], d;
    end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_revoke) loop
    if v_revoke[i] then
      execute format('revoke execute on function public.%s from authenticated', c_revoke[i]);
    end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '513: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '513: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_revoke) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i])) is distinct from c_rights_after
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_revoke[i]), 'execute')
       or has_function_privilege('anon', to_regprocedure('public.' || c_revoke[i]), 'execute') then
      raise exception '513: the rights on public.% are not postgres and service_role alone', c_revoke[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
