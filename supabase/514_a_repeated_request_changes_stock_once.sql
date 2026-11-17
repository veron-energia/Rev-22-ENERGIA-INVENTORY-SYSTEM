-- 514_a_repeated_request_changes_stock_once.sql
--
-- A REPEATED REQUEST CHANGES STOCK ONCE
--
--   From the security audit of 17 Nov 2026 (finding L3).
--   The BEFORE md5s and rights below were compared with production on 17 Nov 2026 (head 513)
--   and match. If production differs when this is applied, it refuses and changes nothing.
--   (The number 514 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   Four buttons changed stock or handed vouchers over with no request id: Add stock on the
--   Vouchers page (voucher_stock_in) and on the Special page (special_stock_in), Apply
--   Correction on the TikTok Import page (correct_tiktok_row), and Collect on the voucher
--   hand-over window (claim_entitlement_vouchers). A second click before the first answer
--   came back, or the same request sent again after its answer was lost, did it twice: the
--   stock was added twice, the TikTok correction made twice, the vouchers handed over twice
--   while the reward still had some left. record_stock_use, the old one-product stock use,
--   had no id either; the page has used record_stock_uses, which takes one, since 345.
--
-- WHAT THIS DOES
--
--   * request_replies (new table, server functions only): the first answer to such a request,
--     kept against the request id the page sent, with what was asked (an md5) and who asked.
--     The request id is its primary key, so a request is answered once.
--   * voucher_stock_in, special_stock_in, correct_tiktok_row and claim_entitlement_vouchers
--     each have a new signature with p_request_id, which is required. The page sends one id
--     per window. The same id again, with the same details, by the same login, gets the first
--     answer back and changes nothing; the same id with other details, or from another login,
--     is refused. A request that failed kept nothing, so it can be sent again. Two at the same
--     moment wait for each other. The work itself is the old signature's, unchanged.
--   * The old signatures, without a request id, are left open here, so the pages loaded before
--     this keep working until the new ones are deployed. 515 closes them to logins once the
--     pages call the new signatures.
--
-- WHAT THIS LEAVES ALONE
--
--   * New Invoice and Edit Invoice: the page sends a request id made once per form, and the
--     database already holds them unique (invoices_create_request_id_key,
--     invoice_revision_request); an edit also carries the edit count it was opened at. The id
--     stays optional there for the server's own callers.
--   * record_stock_uses keeps its optional p_request_id; the page sends one.
--   * The bodies of the four old functions, and record_stock_use (515 closes it to logins).
--
-- UNDO
--
--   Undo 515 first. Then drop the four new signatures, request_reply_first,
--   request_reply_keep and the table request_replies. The pages must go back to the old
--   calls first.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/one-change-per-request-514-515.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Relied on, not changed: the work each new signature hands to, and the staff test.
  c_relied constant text[] := array[
    'voucher_stock_in(uuid,uuid,integer,text)',
    'special_stock_in(uuid,uuid,integer,text)',
    'correct_tiktok_row(uuid,integer,text)',
    'claim_entitlement_vouchers(uuid,jsonb,text)',
    'record_stock_use(text,uuid,uuid,integer,text,text)',
    'require_active_staff(text[])'];
  c_relied_md5 constant text[] := array[
    '56c7d10cf8266f6cc4ec4d1e8aae6e69',
    'ca2e27a7b55af096a20db61b3953f7dd',
    '9aae10ba9e12e372756a2abf7d383e41',
    '5a2e078df74a2763b6975bb939847b7a',
    'db278faba262b0a3801944cd821a62fd',
    '877b3aa74cea559881979bb161c450e2'];

  c_table_def constant text := $t$create table public.request_replies (
  request_id uuid primary key,
  action text not null,
  actor uuid,
  args_md5 text not null,
  reply jsonb not null,
  created_at timestamptz not null default now()
)$t$;
  c_table_cols constant text :=
    'request_id uuid NO,action text NO,actor uuid YES,args_md5 text NO,reply jsonb NO,created_at timestamp with time zone NO';
  c_table_note constant text :=
    '514: the first answer to a request that must not change things twice (Add stock on Vouchers and Special, a TikTok correction, a voucher hand-over), kept against the request id the page sent. Server functions only.';

  -- The new functions: whole texts, the md5 each is installed with, and its rights.
  c_new_sig constant text[] := array[
    'request_reply_first(text,uuid,text)',
    'request_reply_keep(text,uuid,text,jsonb)',
    'voucher_stock_in(uuid,uuid,integer,text,uuid)',
    'special_stock_in(uuid,uuid,integer,text,uuid)',
    'correct_tiktok_row(uuid,integer,text,uuid)',
    'claim_entitlement_vouchers(uuid,jsonb,text,uuid)'];
  c_new_md5 constant text[] := array[
    '96ce4a8c58d277dae7f7288c6dc8516d',
    'b33ea076cb723bceceae161d3bcd702d',
    '724182e6c425f8522baaa54360523f16',
    '807eebea43ef139b82b9933e92b17d07',
    '95c00f51cd8ff31abd1f58918d5043ca',
    'ceccabc80c3015aec2172de0f6cbde65'];
  c_new_grantees constant text[] := array[
    'service_role',
    'service_role',
    'authenticated, service_role',
    'authenticated, service_role',
    'authenticated, service_role',
    'authenticated, service_role'];
  c_new_acl constant text[] := array[
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_new_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.request_reply_first(p_action text, p_request_id uuid, p_args_md5 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 514: the first step of a change a repeated request must not make twice.
-- Null: nothing was done for this request id yet, so go on. Otherwise the
-- first answer, when the id comes again with the same details from the same
-- login. Two requests with one id wait for each other here.
declare r public.request_replies%rowtype;
begin
  if p_request_id is null then
    raise exception 'REQUEST_ID_REQUIRED: This window is out of date. Reload the page and try again.'
      using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('request-reply:' || p_request_id::text, 0));
  select * into r from public.request_replies where request_id = p_request_id;
  if not found then
    return null;
  end if;
  if r.action is distinct from p_action or r.args_md5 is distinct from p_args_md5
     or r.actor is distinct from auth.uid() then
    raise exception 'REQUEST_ID_REUSED: This request was already used for another change. Close the window and open it again.'
      using errcode = '22023';
  end if;
  return r.reply;
end
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.request_reply_keep(p_action text, p_request_id uuid, p_args_md5 text, p_reply jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 514: the first answer, kept against its request id. The id is the
  -- table's key, so a second answer for it is refused.
  insert into public.request_replies (request_id, action, actor, args_md5, reply)
  values (p_request_id, p_action, auth.uid(), p_args_md5, p_reply)
  returning reply
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.voucher_stock_in(p_voucher_id uuid, p_store_id uuid, p_quantity integer, p_note text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 514: Add stock on the Vouchers page, once per request. The page sends one
-- request id per window; the same request again gets the first answer back
-- and adds nothing. The work is the four-argument voucher_stock_in's.
declare
  v_args constant text := md5(jsonb_build_array(p_voucher_id, p_store_id, p_quantity, p_note)::text);
  v_reply jsonb;
begin
  perform public.require_active_staff();
  v_reply := public.request_reply_first('voucher_stock_in', p_request_id, v_args);
  if v_reply is not null then
    return v_reply;
  end if;
  perform public.voucher_stock_in(p_voucher_id, p_store_id, p_quantity, p_note);
  return public.request_reply_keep('voucher_stock_in', p_request_id, v_args, jsonb_build_object('success', true));
end
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.special_stock_in(p_special_product_id uuid, p_warehouse_id uuid, p_quantity integer, p_note text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 514: Add stock on the Special page, once per request. The page sends one
-- request id per window; the same request again gets the first answer back
-- and adds nothing. The work is the four-argument special_stock_in's.
declare
  v_args constant text := md5(jsonb_build_array(p_special_product_id, p_warehouse_id, p_quantity, p_note)::text);
  v_reply jsonb;
begin
  perform public.require_active_staff();
  v_reply := public.request_reply_first('special_stock_in', p_request_id, v_args);
  if v_reply is not null then
    return v_reply;
  end if;
  v_reply := public.special_stock_in(p_special_product_id, p_warehouse_id, p_quantity, p_note);
  return public.request_reply_keep('special_stock_in', p_request_id, v_args, v_reply);
end
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.correct_tiktok_row(p_row_id uuid, p_qty_delta integer, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 514: Apply Correction on the TikTok Import page, once per request. The
-- page sends one request id per window; the same request again gets the
-- first answer back and makes no second correction. The work is the
-- three-argument correct_tiktok_row's.
declare
  v_args constant text := md5(jsonb_build_array(p_row_id, p_qty_delta, p_reason)::text);
  v_reply jsonb;
begin
  perform public.require_active_staff();
  v_reply := public.request_reply_first('correct_tiktok_row', p_request_id, v_args);
  if v_reply is not null then
    return v_reply;
  end if;
  perform public.correct_tiktok_row(p_row_id, p_qty_delta, p_reason);
  return public.request_reply_keep('correct_tiktok_row', p_request_id, v_args, jsonb_build_object('success', true));
end
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.claim_entitlement_vouchers(p_entitlement_id uuid, p_selections jsonb, p_note text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 514: Collect on the voucher hand-over window, once per request. The window
-- sends one request id until a hand-over goes through; the same request again
-- gets the first answer (the same document) back and hands nothing more over.
-- The work is the three-argument claim_entitlement_vouchers's.
declare
  v_args constant text := md5(jsonb_build_array(p_entitlement_id, p_selections, p_note)::text);
  v_reply jsonb;
begin
  perform public.require_active_staff();
  v_reply := public.request_reply_first('claim_entitlement_vouchers', p_request_id, v_args);
  if v_reply is not null then
    return v_reply;
  end if;
  v_reply := public.claim_entitlement_vouchers(p_entitlement_id, p_selections, p_note);
  return public.request_reply_keep('claim_entitlement_vouchers', p_request_id, v_args, v_reply);
end
$function$
$def$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_make_table boolean := false;
  v_make boolean[] := array_fill(false, array[6]);
  i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '514: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The table: missing (made), or 514's already (left alone).
  if to_regclass('public.request_replies') is null then
    v_make_table := true;
  elsif (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'request_replies') = c_table_cols
        and obj_description('public.request_replies'::regclass, 'pg_class') = c_table_note then
    raise notice '514: public.request_replies is already there; left alone';
  else
    raise exception '514: a table public.request_replies is there, but not 514''s. Re-read it before applying.';
  end if;

  -- The new functions: missing (made), or 514's already with its rights (left alone).
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null then
      v_make[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) = c_new_md5[i]
          and (select coalesce(string_agg(x::text, ',' order by x::text), '')
                 from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) = c_new_acl[i] then
      raise notice '514: public.% is already there; left alone', c_new_sig[i];
    else
      raise exception '514: a function public.% is there, but not 514''s. Re-read it before applying.', c_new_sig[i];
    end if;
  end loop;

  -- 2. Install
  if v_make_table then
    execute c_table_def;
    execute format('comment on table public.request_replies is %L', c_table_note);
    alter table public.request_replies enable row level security;
    revoke all on table public.request_replies from public, anon, authenticated;
  end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if v_make[i] then
      execute c_new_def[i];
      execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
      execute format('grant execute on function public.%s to %s', c_new_sig[i], c_new_grantees[i]);
    end if;
  end loop;

  -- 3. Checks after installing
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'request_replies') is distinct from c_table_cols
     or not (select relrowsecurity from pg_class where oid = 'public.request_replies'::regclass)
     or has_table_privilege('anon', 'public.request_replies', 'select')
     or has_table_privilege('authenticated', 'public.request_replies', 'select')
     or has_table_privilege('authenticated', 'public.request_replies', 'insert') then
    raise exception '514: public.request_replies is not as tested (its columns, its row security, or a login can reach it)';
  end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '514: public.% was installed with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i] then
      raise exception '514: the rights on public.% are not the tested ones', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '514: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
