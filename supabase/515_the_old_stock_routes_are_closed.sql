-- 515_the_old_stock_routes_are_closed.sql
--
-- THE OLD STOCK ROUTES, WITHOUT A REQUEST ID, ARE CLOSED TO LOGINS
--
--   From the security audit of 17 Nov 2026 (finding L3), after 514.
--   The rights below were compared with production on 17 Nov 2026 (head 514) and match. If
--   production differs when this is applied, it refuses and changes nothing.
--   (The number 515 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   514 gave Add stock (Vouchers and Special pages), Apply Correction (TikTok Import) and
--   Collect (the voucher hand-over window) new signatures that require a request id, so a
--   repeated request changes things once. It left the old signatures open, so the pages
--   loaded before it kept working until the new ones were deployed. Without a request id
--   they still do the work twice when a request comes twice. So did record_stock_use, the
--   old one-product stock use, which no page calls.
--
-- WHAT THIS DOES
--
--   Signed-in logins can no longer call voucher_stock_in, special_stock_in,
--   correct_tiktok_row or claim_entitlement_vouchers without a request id, nor
--   record_stock_use. The service role and the database's own functions still can:
--   514's new signatures, claim_purchased_therapy, event_vip_gift_give,
--   give_referral_campaign_reward and record_stock_uses call them with their owner's rights.
--   A page loaded before the pages that send a request id gets "permission denied" on those
--   four buttons until it is reloaded.
--
-- UNDO
--
--   grant execute on function public.voucher_stock_in(uuid,uuid,integer,text),
--   public.special_stock_in(uuid,uuid,integer,text), public.correct_tiktok_row(uuid,integer,text),
--   public.claim_entitlement_vouchers(uuid,jsonb,text) and
--   public.record_stock_use(text,uuid,uuid,integer,text,text) to authenticated.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/one-change-per-request-514-515.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Signed-in logins can no longer call these. Their bodies stay.
  c_revoke constant text[] := array[
    'voucher_stock_in(uuid,uuid,integer,text)',
    'special_stock_in(uuid,uuid,integer,text)',
    'correct_tiktok_row(uuid,integer,text)',
    'claim_entitlement_vouchers(uuid,jsonb,text)',
    'record_stock_use(text,uuid,uuid,integer,text,text)'];
  c_rights_before constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_rights_after constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- Relied on, not changed: 514's signatures, which the pages call instead (with their
  -- rights), and the server functions that call the closed ones with their owner's rights.
  c_relied constant text[] := array[
    'voucher_stock_in(uuid,uuid,integer,text,uuid)',
    'special_stock_in(uuid,uuid,integer,text,uuid)',
    'correct_tiktok_row(uuid,integer,text,uuid)',
    'claim_entitlement_vouchers(uuid,jsonb,text,uuid)',
    'record_stock_uses(text,uuid,jsonb,text,text,uuid)'];
  c_relied_md5 constant text[] := array[
    '724182e6c425f8522baaa54360523f16',
    '807eebea43ef139b82b9933e92b17d07',
    '95c00f51cd8ff31abd1f58918d5043ca',
    'ceccabc80c3015aec2172de0f6cbde65',
    '8cab37c88f3f46548d941cd100eb1a78'];
  c_relied_acl constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_callers constant text[] := array[
    'claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)',
    'event_vip_gift_give(uuid,uuid,date,uuid)',
    'give_referral_campaign_reward(text,uuid,uuid,jsonb,text)',
    'record_stock_uses(text,uuid,jsonb,text,text,uuid)'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_revoke boolean[] := array_fill(false, array[5]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_relied[i])) <> c_relied_acl then
      raise exception '515: public.% is missing, not the version this was tested against, or not callable by signed-in logins. Apply 514 first, or re-read it.', c_relied[i];
    end if;
  end loop;
  if exists (select 1 from pg_proc p where p.oid = any (array(select to_regprocedure('public.' || x) from unnest(c_callers) x))
              and not p.prosecdef)
     or (select count(*) from unnest(c_callers) x where to_regprocedure('public.' || x) is not null) <> cardinality(c_callers) then
    raise exception '515: a server function that calls the closed ones is missing or no longer runs with its owner''s rights';
  end if;
  for i in 1 .. cardinality(c_revoke) loop
    if to_regprocedure('public.' || c_revoke[i]) is null then raise exception '515: public.% is missing', c_revoke[i]; end if;
    d := (select coalesce(string_agg(x::text, ',' order by x::text), '')
            from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i]));
    if d = c_rights_before then
      v_revoke[i] := true;
    elsif d = c_rights_after then
      raise notice '515: signed-in logins already cannot call public.%; left alone', c_revoke[i];
    else
      raise exception '515: the rights on public.% are not the ones this was tested against (%). Re-read them and re-test before applying.', c_revoke[i], d;
    end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_revoke) loop
    if v_revoke[i] then
      execute format('revoke execute on function public.%s from authenticated', c_revoke[i]);
    end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_revoke) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_revoke[i])) is distinct from c_rights_after
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_revoke[i]), 'execute')
       or has_function_privilege('anon', to_regprocedure('public.' || c_revoke[i]), 'execute') then
      raise exception '515: the rights on public.% are not postgres and service_role alone', c_revoke[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
