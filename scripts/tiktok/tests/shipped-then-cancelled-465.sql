-- A TikTok order shipped and then cancelled before the importer first saw it is taken off stock and waits
-- for its physical return, as one cancelled after a shipped import does (465).
--
--   G  The AFTER md5s; the 6-argument tiktok_evaluate is gone, the 7-argument one and
--      tiktok_row_shows_shipped are the server's alone; stage_tiktok_orders, refresh_tiktok_staging and
--      confirm_tiktok_batch keep their grants (signed-in staff and the service role, never anon). What the
--      helper reads as shipped: a shipped or a delivered time, not a ready-to-ship time or a tracking id.
--   A  Cancelled with a shipped time, first seen (the 24 Oct 2026 shape: one unit, shipped by courier,
--      cancelled six days later): staged "New — Will Deduct, Awaiting Return", 1; confirmed: one unit off
--      the store, a store_sale row noted "TikTok import <file> (shipped, then <status>) — order <id>", the
--      item deducted 1 and shipped, one physical return waiting for 1 that names the row; the result counts
--      it deducted and awaiting.
--   B  The same row in the next file: "Awaiting Physical Return", 0; confirmed: nothing more.
--   C  Its physical return restocked: the unit back, deducted 0; the next file: "Already Imported", 0,
--      nothing moves, nothing opened.
--   D  Another such order resolved as No Stock Return (lost): the next file is "Already Imported", 0; no
--      second physical return, nothing moves, the deduction stays 1 (before 465: another physical return
--      for the same parcel, each file).
--   E  First seen To Ship (deducted), then shipped and cancelled between two files: "Awaiting Physical
--      Return", 0 (before 465: "Updated — Stock Return", put back automatically); confirmed: its physical
--      return opened for 1.
--   F  Unchanged: cancelled with no shipped time, first seen (a ready-to-ship time and a tracking id only):
--      "Already Imported", 0, nothing; To Ship then cancelled with no shipped time: "Updated — Stock
--      Return", put back automatically; Shipped then cancelled (the path 65 made): "Awaiting Physical
--      Return", its return opened for what was deducted; a Completed row: "New — Will Deduct"; cancelled
--      with only a delivered time, first seen: taken off and awaiting.
--   L  An order already held with nothing deducted and not shipped (the 24 Oct order as it is in
--      production): a later file's cancelled row with its shipped time is "Already Imported", 0; confirmed,
--      nothing moves and nothing is opened (taking it off is the Owner's decision).
--   N  Negative stock: first seen shipped and cancelled with none on the shelf: "Negative Stock Warning";
--      confirm refuses without the explicit go-ahead, and with it and a reason takes it below zero and opens
--      the physical return.
--   V  A voucher mapping: one voucher unit off (a TikTok voucher sale of 1), restocked: back.
--   R  refresh_tiktok_staging: a row staged before its SKU was mapped is re-read with the row's shipped time.
--   M  465 twice changes nothing; its first run changes only its functions (stage, refresh and confirm
--      patched; the 6-argument tiktok_evaluate dropped; the 7-argument one and the helper added); each run
--      leaves no row and uses no sequence (its self-test).
--
-- Disposable local database only (production as it is on 24 Oct 2026: 464 in); everything is rolled back.
-- Every name, email, order id and SKU is invented (T465, @example.com). It installs, inside this
-- transaction, production's bodies of current_user_role, user_has_store_access, require_active_staff and
-- resolve_tiktok_physical_return (406/430; a shared local database may hold older ones), then 465 twice.
-- Run on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/tiktok/tests/shipped-then-cancelled-465.sql
-- Every check runs, then the file fails if any did.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- ═════ Production's bodies (24 Oct 2026) of the helpers a local copy may hold older ═════
CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS user_role
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 406: the role of an ACTIVE member of staff, else null. A deactivated
  -- employee, a pending or cancelled invitee and a deleted profile are nobody,
  -- as in user_admin_role(). Every policy and function that reads this takes
  -- null to mean "not staff".
  select p.role from public.profiles p
   where p.id = auth.uid() and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted'
$function$;
CREATE OR REPLACE FUNCTION public.user_has_store_access(target_store_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: as before, every store for an active Owner or Admin, and their
  -- assigned stores for any other active member of staff. Active as in
  -- current_user_role(): active, not deleted, invitation accepted (before
  -- 430 it asked only "active").
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  -- STABLE. A read rule asks current_user_store_ids() once per query instead
  -- of calling this per row.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and (p.role in ('owner', 'admin')
                         or exists (select 1 from public.user_store_assignments usa
                                     where usa.user_id = p.id and usa.store_id = target_store_id)))
$function$;
CREATE OR REPLACE FUNCTION public.require_active_staff(p_roles text[] DEFAULT NULL::text[])
 RETURNS user_role
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role;
begin
  -- 406: the first statement of a staff page's server function. Being signed
  -- in does not make a login staff: affiliates sign in, a login could be
  -- created by anyone, and a deactivated employee keeps their password. Only an
  -- active, accepted, not-deleted profile passes (as in user_admin_role), and
  -- with p_roles only a profile whose role is one of them. Refused: 42501.
  --
  -- The server is not a login. The service role (website orders, the Edge
  -- Functions), pg_cron and migrations carry neither the anon nor the
  -- authenticated role, and pass; a request from a browser always carries one.
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') then
    return null;
  end if;
  select p.role into v_role from public.profiles p
   where p.id = auth.uid() and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted';
  if v_role is null then
    raise exception 'Only active Energia staff can do this.' using errcode = '42501';
  end if;
  if p_roles is not null and not (v_role::text = any (p_roles)) then
    raise exception 'Your role cannot do this.' using errcode = '42501';
  end if;
  return v_role;
end
$function$;
revoke all on function public.require_active_staff(text[]) from public, anon, authenticated;
grant execute on function public.require_active_staff(text[]) to service_role;
CREATE OR REPLACE FUNCTION public.resolve_tiktok_physical_return(p_return_id uuid, p_restock boolean, p_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_pr public.tiktok_physical_returns%rowtype; v_row public.tiktok_order_rows%rowtype; v_role user_role;
begin
  perform public.require_active_staff();  -- 406: active staff only
  v_role := public.current_user_role();
  select * into v_pr from public.tiktok_physical_returns where id = p_return_id for update;
  if not found then raise exception 'Physical return not found'; end if;
  -- Spec: Owner, Manager, or Staff assigned to the store.
  if not (v_role in ('owner','manager')
          or (v_role = 'staff' and public.user_has_store_access(v_pr.store_id))) then
    raise exception 'Only Owners, Managers or Staff assigned to this store can confirm physical returns'; end if;
  if v_pr.status <> 'awaiting' then raise exception 'This physical return is already resolved'; end if;

  if p_restock then
    if v_pr.order_row_id is not null then
      select * into v_row from public.tiktok_order_rows where id = v_pr.order_row_id;
      perform public.apply_tiktok_stock_delta(
        v_pr.store_id, v_row.matched_kind, v_row.matched_id, -v_pr.expected_qty,
        v_row.id, v_pr.order_id, v_pr.seller_sku, 'TikTok physical return');
    end if;
    update public.tiktok_order_state
       set deducted_qty = greatest(0, deducted_qty - v_pr.expected_qty), updated_at = now()
     where store_id = v_pr.store_id and order_id = v_pr.order_id and seller_sku = v_pr.seller_sku;
    update public.tiktok_physical_returns
       set status = 'restocked', resolved_by = auth.uid(), resolved_at = now(),
           resolution_reason = nullif(trim(coalesce(p_reason,'')),''), resolution_note = nullif(trim(coalesce(p_note,'')),'')
     where id = p_return_id;
  else
    if coalesce(p_reason,'') not in ('damaged','lost','not_received','other') then
      raise exception 'No Stock Return requires a reason: damaged, lost, not_received or other'; end if;
    if p_reason = 'other' and nullif(trim(coalesce(p_note,'')),'') is null then
      raise exception 'Please describe the reason when choosing "other"'; end if;
    update public.tiktok_physical_returns
       set status = 'no_restock', resolved_by = auth.uid(), resolved_at = now(),
           resolution_reason = p_reason, resolution_note = nullif(trim(coalesce(p_note,'')),'')
     where id = p_return_id;
  end if;

  perform public.write_audit_ex('tiktok_physical_returns', p_return_id,
    case when p_restock then 'tiktok_physical_return_restocked' else 'tiktok_physical_return_no_restock' end,
    null,
    jsonb_build_object('order_id', v_pr.order_id, 'seller_sku', v_pr.seller_sku,
                       'expected_qty', v_pr.expected_qty, 'reason', p_reason, 'note', p_note),
    'tiktok_import', p_reason, v_pr.store_id);
end $function$;

-- ═════ Helpers ═════
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
create function pg_temp.seqs() returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(sequencename, coalesce(last_value, 0)), '{}'::jsonb) from pg_sequences where schemaname = 'public' $$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language plpgsql as
$$begin
  perform set_config('search_path', 'public', true);
  return query select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
end$$;
-- An order row as the Import page sends it (the order id gets the run's suffix).
create function pg_temp.ln(ord text, sku_key text, st text, extra jsonb default '{}'::jsonb) returns jsonb language sql as
$$ select jsonb_build_object('order_id', 'T465-' || pg_temp.tx('sfx') || '-' || ord, 'seller_sku', pg_temp.tx(sku_key),
     'quantity', '1', 'order_status', pg_temp.tx(st), 'product_name', 'T465 item') || extra $$;
create function pg_temp.oid_(ord text) returns text language sql as $$ select 'T465-' || pg_temp.tx('sfx') || '-' || ord $$;
create function pg_temp.stage(rows jsonb, file text) returns uuid language sql as
$$ select public.stage_tiktok_orders(pg_temp.fx('store'), 'T465 ' || file || '.csv', null, rows) $$;
create function pg_temp.confirm(b uuid) returns jsonb language sql as
$$ select public.confirm_tiktok_batch(b, null, false, null) $$;
create function pg_temp.staged(b uuid, ord text) returns text language sql as
$$ select staging_status || ' ' || stock_delta from public.tiktok_order_rows where batch_id = b and order_id = pg_temp.oid_(ord) $$;
create function pg_temp.qty(item text) returns int language sql as
$$ select current_qty from public.store_inventory where store_id = pg_temp.fx('store') and product_id = pg_temp.fx(item) $$;
create function pg_temp.vqty() returns int language sql as
$$ select current_qty from public.voucher_store_stock where store_id = pg_temp.fx('store') and voucher_id = pg_temp.fx('voucher') $$;
create function pg_temp.state(ord text) returns text language sql as
$$ select deducted_qty || ' ' || was_shipped || ' ' || last_status from public.tiktok_order_state
    where store_id = pg_temp.fx('store') and order_id = pg_temp.oid_(ord) $$;
create function pg_temp.returns_(ord text) returns text language sql as
$$ select coalesce(string_agg(status || ' ' || expected_qty, ', ' order by created_at, id), '') from public.tiktok_physical_returns
    where store_id = pg_temp.fx('store') and order_id = pg_temp.oid_(ord) $$;
create function pg_temp.return_id(ord text) returns uuid language sql as
$$ select id from public.tiktok_physical_returns where store_id = pg_temp.fx('store') and order_id = pg_temp.oid_(ord) and status = 'awaiting' $$;
create function pg_temp.moves(ord text) returns text language sql as
$$ select coalesce(string_agg(movement_type::text || ' ' || quantity || ' ' || notes, ' | ' order by created_at, id), '')
     from public.stock_movements where from_store_id = pg_temp.fx('store') and notes like '%order ' || pg_temp.oid_(ord) $$;

-- ═════ Fixtures (invented) ═════
do $$
declare o constant uuid := gen_random_uuid(); st uuid; sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
  p uuid; e uuid; v uuid;
begin
  insert into tx values ('sfx', sfx), ('sku', 'T465-SOAP-' || sfx), ('sku_empty', 'T465-EMPTY-' || sfx),
    ('sku_v', 'T465-VCH-' || sfx), ('sku_new', 'T465-NEW-' || sfx),
    ('cancel', 'T465 Canceled ' || sfx), ('toship', 'T465 To Ship ' || sfx), ('shipped', 'T465 Shipped ' || sfx),
    ('completed', 'T465 Completed ' || sfx);
  insert into auth.users(id, email) values (o, 't465-owner-' || sfx || '@example.com');
  insert into public.profiles(id, full_name, email, role, is_active) values (o, 'T465 Owner', 't465-owner-' || sfx || '@example.com', 'owner', true);
  insert into public.stores(name, code, country_code) values ('T465 Store ' || sfx, 'T465' || sfx, 'SG') returning id into st;
  insert into public.products(name, sku) values ('T465 Soap ' || sfx, 'T465P' || sfx) returning id into p;
  insert into public.products(name, sku) values ('T465 Empty ' || sfx, 'T465E' || sfx) returning id into e;
  insert into public.vouchers(name, code, voucher_kind, selling_price, qty_type, is_active)
  values ('T465 Voucher ' || sfx, 'T465V' || sfx, 'normal', 10, 'limited', true) returning id into v;
  insert into fx values ('owner', o), ('store', st), ('soap', p), ('empty', e), ('voucher', v);
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, p, 20), (st, e, 0);
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (v, st, 5);
  insert into public.tiktok_sku_aliases(store_id, seller_sku, target_kind, target_id, created_by)
  values (st, pg_temp.tx('sku'), 'product', p, o), (st, pg_temp.tx('sku_empty'), 'product', e, o),
         (st, pg_temp.tx('sku_v'), 'voucher', v, o);
  insert into public.tiktok_status_mappings(status_label, status_norm, action, marks_shipped)
  select x.l, public.tiktok_norm_status(x.l), x.a, x.s
    from (values (pg_temp.tx('cancel'), 'return', false), (pg_temp.tx('toship'), 'deduct', false),
                 (pg_temp.tx('shipped'), 'deduct', true), (pg_temp.tx('completed'), 'deduct', true)) x(l, a, s);
end $$;
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);

-- ═════ M: install 465 (twice) ═════
create temp table snap(k text primary key, v jsonb);
insert into snap select 'rows', pg_temp.row_counts();
insert into snap select 'seqs', pg_temp.seqs();
create temp table md5_before as select * from pg_temp.fn_md5s();
\ir ../../../supabase/465_tiktok_shipped_then_cancelled_waits_for_return.sql
create temp table md5_once as select * from pg_temp.fn_md5s();
select pg_temp.check((select v from snap where k = 'rows') = pg_temp.row_counts(), 'M 465 leaves no row');
select pg_temp.check((select v from snap where k = 'seqs') = pg_temp.seqs(), 'M 465 uses no sequence');
insert into tx select 'changed', string_agg(coalesce(a.fn, b.fn) || case when a.fn is null then ' added' when b.fn is null then ' dropped' else ' changed' end,
                                            ', ' order by coalesce(a.fn, b.fn) collate "C")
  from md5_before a full join md5_once b on b.fn = a.fn where a.md5 is distinct from b.md5;
select pg_temp.check(pg_temp.tx('changed')
  = 'confirm_tiktok_batch(uuid,jsonb,boolean,text) changed, refresh_tiktok_staging(uuid) changed, '
    || 'stage_tiktok_orders(uuid,text,text,jsonb) changed, tiktok_evaluate(uuid,text,text,integer,text,boolean) dropped, '
    || 'tiktok_evaluate(uuid,text,text,integer,text,boolean,boolean) added, tiktok_row_shows_shipped(jsonb) added',
  'M its first run changes only its five functions (three patched, tiktok_evaluate replaced, the helper added): ' || pg_temp.tx('changed'));
\ir ../../../supabase/465_tiktok_shipped_then_cancelled_waits_for_return.sql
select pg_temp.check(not exists (select 1 from md5_once a full join pg_temp.fn_md5s() b on b.fn = a.fn where a.md5 is distinct from b.md5),
  'M a second run changes nothing');
select set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);

-- ═════ G ═════
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = x.fn) = x.md5, 'G AFTER md5 of ' || x.fn)
  from (values ('tiktok_evaluate(uuid,text,text,integer,text,boolean,boolean)', 'e099050c8c43c973721229c21adddfd3'),
               ('tiktok_row_shows_shipped(jsonb)', '6e51262ec7a94429da6f5c397bd0d836'),
               ('stage_tiktok_orders(uuid,text,text,jsonb)', '9cad8a716950fdaab791f6f42cdddf7c'),
               ('refresh_tiktok_staging(uuid)', 'e86e136864942da175725d394d8f0817'),
               ('confirm_tiktok_batch(uuid,jsonb,boolean,text)', '4b7b3844d884efa3f5f81d7770048daf')) x(fn, md5);
select pg_temp.check(to_regprocedure('public.tiktok_evaluate(uuid,text,text,integer,text,boolean)') is null,
  'G the 6-argument tiktok_evaluate is gone');
select pg_temp.check(not has_function_privilege('anon', 'public.' || f, 'execute')
    and not has_function_privilege('authenticated', 'public.' || f, 'execute')
    and has_function_privilege('service_role', 'public.' || f, 'execute'), 'G ' || f || ' is the server''s alone')
  from unnest(array['tiktok_evaluate(uuid,text,text,integer,text,boolean,boolean)', 'tiktok_row_shows_shipped(jsonb)']) f;
select pg_temp.check(not has_function_privilege('anon', 'public.' || f, 'execute')
    and has_function_privilege('authenticated', 'public.' || f, 'execute')
    and has_function_privilege('service_role', 'public.' || f, 'execute'), 'G ' || f || ' stays callable by signed-in staff, never anon')
  from unnest(array['stage_tiktok_orders(uuid,text,text,jsonb)', 'refresh_tiktok_staging(uuid)', 'confirm_tiktok_batch(uuid,jsonb,boolean,text)']) f;
select pg_temp.check(
  public.tiktok_row_shows_shipped('{"shipped_time": "13/10/2026 10:00:00"}')
  and public.tiktok_row_shows_shipped('{"delivered_time": "15/10/2026 10:00:00"}')
  and public.tiktok_row_shows_shipped('{"shipped_time": "2026-10-13 10:00"}')
  and not public.tiktok_row_shows_shipped('{"rts_time": "12/10/2026 18:00:00", "tracking_id": "T465TRACK", "package_id": "T465PKG"}')
  and not public.tiktok_row_shows_shipped('{"shipped_time": ""}')
  and not public.tiktok_row_shows_shipped('{"shipped_time": " -- "}')
  and not public.tiktok_row_shows_shipped('{}')
  and not public.tiktok_row_shows_shipped(null),
  'G shipped means a shipped or delivered time; a ready-to-ship time, a tracking id, a blank or a dash are not');
select pg_temp.check((select staging_status || ' ' || stock_delta || ' ' || matched_kind
                        from public.tiktok_evaluate(pg_temp.fx('store'), 'T465-' || pg_temp.tx('sfx') || '-six', pg_temp.tx('sku'), 2,
                                                    pg_temp.tx('completed'), false)) = 'New — Will Deduct 2 product',
  'G a 6-argument call (as the 427 repair makes) still reaches tiktok_evaluate: a Completed row, "New — Will Deduct"');

-- ═════ A: cancelled with a shipped time, first seen ═════
do $$ declare b uuid; r jsonb; begin
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('A', 'sku', 'cancel', jsonb_build_object(
         'created_time', '12/10/2026 11:00:00', 'rts_time', '12/10/2026 18:00:00', 'shipped_time', '13/10/2026 10:00:00',
         'cancelled_time', '19/10/2026 12:00:00', 'return_quantity', '1', 'tracking_id', 'T465TRACKA', 'package_id', 'T465PKGA',
         'shipping_provider', 'T465 Post', 'sku_subtotal_after', '0.01'))), 'file 1');
  insert into fx values ('batchA', b);
  perform pg_temp.check(pg_temp.staged(b, 'A') = 'New — Will Deduct, Awaiting Return 1',
    'A staged "New — Will Deduct, Awaiting Return", 1 (got ' || coalesce(pg_temp.staged(b, 'A'), 'nothing') || ')');
  perform pg_temp.check(pg_temp.qty('soap') = 20 and pg_temp.returns_('A') = '', 'A staging moves nothing');
  r := pg_temp.confirm(b);
  perform pg_temp.check((r->>'applied')::int = 1 and (r->>'units_deducted')::int = 1 and (r->>'awaiting_physical_return')::int = 1
                        and (r->>'units_returned')::int = 0, 'A the confirm counts it deducted and awaiting (' || r::text || ')');
  perform pg_temp.check(pg_temp.qty('soap') = 19, 'A one unit off the store');
  perform pg_temp.check(pg_temp.moves('A') = 'store_sale 1 TikTok import T465 file 1.csv (shipped, then ' || lower(pg_temp.tx('cancel'))
                        || ') — order ' || pg_temp.oid_('A'), 'A one store_sale row, noted (' || pg_temp.moves('A') || ')');
  perform pg_temp.check(pg_temp.state('A') = '1 true ' || pg_temp.tx('cancel'), 'A the item is deducted 1 and shipped');
  perform pg_temp.check(pg_temp.returns_('A') = 'awaiting 1', 'A one physical return waits for 1');
  perform pg_temp.check((select pr.order_row_id = o.id from public.tiktok_physical_returns pr
                           join public.tiktok_order_rows o on o.batch_id = b and o.order_id = pg_temp.oid_('A')
                          where pr.order_id = pg_temp.oid_('A')),
    'A the physical return names the confirmed row (so a Stock Return knows what to put back)');
  perform pg_temp.check((select confirmed and staging_status = 'New — Will Deduct, Awaiting Return' and stock_delta = 1
                           from public.tiktok_order_rows where batch_id = b), 'A the row is confirmed as staged');
end $$;

-- ═════ B: the same row in the next file ═════
do $$ declare b uuid; begin
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('A', 'sku', 'cancel', jsonb_build_object('shipped_time', '13/10/2026 10:00:00'))), 'file 2');
  perform pg_temp.check(pg_temp.staged(b, 'A') = 'Awaiting Physical Return 0', 'B the next file: "Awaiting Physical Return", 0');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 19 and pg_temp.returns_('A') = 'awaiting 1' and pg_temp.state('A') = '1 true ' || pg_temp.tx('cancel'),
    'B confirmed: nothing more (still one physical return, 19 on the shelf, deducted 1)');
end $$;

-- ═════ C: restocked ═════
do $$ declare b uuid; begin
  perform public.resolve_tiktok_physical_return(pg_temp.return_id('A'), true, null, 'T465 parcel back');
  perform pg_temp.check(pg_temp.qty('soap') = 20 and pg_temp.returns_('A') = 'restocked 1' and pg_temp.state('A') like '0 true %',
    'C a Stock Return puts the unit back; deducted 0');
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('A', 'sku', 'cancel', jsonb_build_object('shipped_time', '13/10/2026 10:00:00'))), 'file 3');
  perform pg_temp.check(pg_temp.staged(b, 'A') = 'Already Imported 0', 'C the next file: "Already Imported", 0');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 20 and pg_temp.returns_('A') = 'restocked 1', 'C confirmed: nothing moves, nothing opened');
end $$;

-- ═════ D: No Stock Return, then later files ═════
do $$ declare b uuid; begin
  perform pg_temp.confirm(pg_temp.stage(jsonb_build_array(pg_temp.ln('D', 'sku', 'cancel', jsonb_build_object('shipped_time', '03/10/2026 09:15:00'))), 'file 4'));
  perform pg_temp.check(pg_temp.qty('soap') = 19 and pg_temp.returns_('D') = 'awaiting 1', 'D a second such order: off and awaiting');
  perform public.resolve_tiktok_physical_return(pg_temp.return_id('D'), false, 'lost', null);
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('D', 'sku', 'cancel', jsonb_build_object('shipped_time', '03/10/2026 09:15:00'))), 'file 5');
  perform pg_temp.check(pg_temp.staged(b, 'D') = 'Already Imported 0', 'D after a No Stock Return the next file is "Already Imported", 0 (was "Awaiting Physical Return")');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.returns_('D') = 'no_restock 1', 'D no second physical return for the same parcel');
  perform pg_temp.check(pg_temp.qty('soap') = 19 and pg_temp.state('D') = '1 true ' || pg_temp.tx('cancel'),
    'D nothing moves; the deduction stays 1 (a later file does not wipe it)');
  perform pg_temp.confirm(pg_temp.stage(jsonb_build_array(pg_temp.ln('D', 'sku', 'cancel', jsonb_build_object('shipped_time', '03/10/2026 09:15:00'))), 'file 6'));
  perform pg_temp.check(pg_temp.returns_('D') = 'no_restock 1' and pg_temp.state('D') like '1 %', 'D and again');
end $$;

-- ═════ E: To Ship, then shipped and cancelled between two files ═════
do $$ declare b uuid; begin
  perform pg_temp.confirm(pg_temp.stage(jsonb_build_array(pg_temp.ln('E', 'sku', 'toship', jsonb_build_object('rts_time', '05/10/2026 10:00:00'))), 'file 7'));
  perform pg_temp.check(pg_temp.qty('soap') = 18 and pg_temp.state('E') = '1 false ' || pg_temp.tx('toship'), 'E To Ship: deducted, not shipped');
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('E', 'sku', 'cancel', jsonb_build_object(
         'rts_time', '05/10/2026 10:00:00', 'shipped_time', '06/10/2026 14:00:00', 'cancelled_time', '09/10/2026 09:00:00'))), 'file 8');
  perform pg_temp.check(pg_temp.staged(b, 'E') = 'Awaiting Physical Return 0',
    'E cancelled with a shipped time: "Awaiting Physical Return", 0 (was "Updated — Stock Return", -1)');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 18 and pg_temp.returns_('E') = 'awaiting 1', 'E confirmed: nothing put back, its physical return opened for 1');
end $$;

-- ═════ F: unchanged ═════
do $$ declare b uuid; begin
  -- Cancelled before shipment, first seen (packed, a tracking id, never shipped).
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('F1', 'sku', 'cancel', jsonb_build_object(
         'rts_time', '08/08/2026 18:00:00', 'tracking_id', 'T465TRACKF1', 'package_id', 'T465PKGF1', 'cancelled_time', '11/08/2026 09:00:00'))), 'file 9');
  perform pg_temp.check(pg_temp.staged(b, 'F1') = 'Already Imported 0', 'F cancelled with no shipped time, first seen: "Already Imported", 0');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 18 and pg_temp.returns_('F1') = '' and pg_temp.state('F1') = '0 false ' || pg_temp.tx('cancel'),
    'F confirmed: nothing taken, nothing expected');
  -- To Ship, then cancelled with no shipped time: put back automatically.
  perform pg_temp.confirm(pg_temp.stage(jsonb_build_array(pg_temp.ln('F2', 'sku', 'toship')), 'file 10'));
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('F2', 'sku', 'cancel', jsonb_build_object('rts_time', '05/10/2026 10:00:00'))), 'file 11');
  perform pg_temp.check(pg_temp.staged(b, 'F2') = 'Updated — Stock Return -1', 'F To Ship then cancelled unshipped: "Updated — Stock Return", -1');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 18 and pg_temp.returns_('F2') = '', 'F confirmed: put back automatically, no physical return');
  -- Shipped, then cancelled (the path 65 made).
  perform pg_temp.confirm(pg_temp.stage(jsonb_build_array(pg_temp.ln('F3', 'sku', 'shipped', jsonb_build_object('shipped_time', '01/10/2026 12:00:00'))), 'file 12'));
  perform pg_temp.check(pg_temp.qty('soap') = 17 and pg_temp.state('F3') = '1 true ' || pg_temp.tx('shipped'), 'F Shipped: deducted and shipped');
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('F3', 'sku', 'cancel')), 'file 13');
  perform pg_temp.check(pg_temp.staged(b, 'F3') = 'Awaiting Physical Return 0', 'F Shipped then cancelled: "Awaiting Physical Return", 0');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 17 and pg_temp.returns_('F3') = 'awaiting 1', 'F confirmed: its physical return opened for what was deducted');
  -- A completed order.
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('F4', 'sku', 'completed', jsonb_build_object(
         'shipped_time', '02/10/2026 12:00:00', 'delivered_time', '04/10/2026 12:00:00'))), 'file 14');
  perform pg_temp.check(pg_temp.staged(b, 'F4') = 'New — Will Deduct 1', 'F a Completed row: "New — Will Deduct", 1');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 16 and pg_temp.returns_('F4') = '', 'F confirmed: one off, nothing expected back');
  -- Cancelled with only a delivered time, first seen.
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('F5', 'sku', 'cancel', jsonb_build_object('delivered_time', '04/10/2026 12:00:00'))), 'file 15');
  perform pg_temp.check(pg_temp.staged(b, 'F5') = 'New — Will Deduct, Awaiting Return 1', 'F cancelled with only a delivered time, first seen: taken off and awaiting');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 15 and pg_temp.returns_('F5') = 'awaiting 1', 'F confirmed: one off, its physical return opened');
end $$;

-- ═════ L: an order held with nothing deducted and not shipped (as the 24 Oct order is) ═════
do $$ declare b uuid; begin
  insert into public.tiktok_order_state(store_id, order_id, seller_sku, deducted_qty, last_status, was_shipped)
  values (pg_temp.fx('store'), pg_temp.oid_('L'), pg_temp.tx('sku'), 0, pg_temp.tx('cancel'), false);
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('L', 'sku', 'cancel', jsonb_build_object(
         'shipped_time', '13/10/2026 10:00:00', 'cancelled_time', '19/10/2026 12:00:00'))), 'file 16');
  perform pg_temp.check(pg_temp.staged(b, 'L') = 'Already Imported 0', 'L a later file of an order already held: "Already Imported", 0');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 15 and pg_temp.returns_('L') = '' and pg_temp.state('L') like '0 %',
    'L confirmed: nothing moves and nothing is opened (the Owner decides)');
end $$;

-- ═════ N: negative stock ═════
do $$ declare b uuid; e text; begin
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('N', 'sku_empty', 'cancel', jsonb_build_object('shipped_time', '10/10/2026 10:00:00'))), 'file 17');
  perform pg_temp.check(pg_temp.staged(b, 'N') = 'Negative Stock Warning 1', 'N none on the shelf: "Negative Stock Warning", 1');
  e := pg_temp.err(format('select public.confirm_tiktok_batch(%L, null, false, null)', b));
  perform pg_temp.check(e like 'NEGATIVE_STOCK_CONFIRMATION_REQUIRED%' and pg_temp.qty('empty') = 0 and pg_temp.returns_('N') = '',
    'N confirm refuses without the go-ahead, and changes nothing (' || coalesce(e, 'no error') || ')');
  perform public.confirm_tiktok_batch(b, null, true, 'T465 parcel already left');
  perform pg_temp.check(pg_temp.qty('empty') = -1 and pg_temp.returns_('N') = 'awaiting 1' and pg_temp.state('N') like '1 true %',
    'N with the go-ahead and a reason: below zero, and its physical return opened');
end $$;

-- ═════ V: a voucher mapping ═════
do $$ declare r jsonb; begin
  r := pg_temp.confirm(pg_temp.stage(jsonb_build_array(pg_temp.ln('V', 'sku_v', 'cancel', jsonb_build_object('shipped_time', '11/10/2026 10:00:00'))), 'file 18'));
  perform pg_temp.check(pg_temp.vqty() = 4 and pg_temp.returns_('V') = 'awaiting 1'
      and (select sum(quantity) from public.tiktok_voucher_sales where order_id = pg_temp.oid_('V')) = 1,
    'V a voucher: one off (a TikTok voucher sale of 1), awaiting');
  perform public.resolve_tiktok_physical_return(pg_temp.return_id('V'), true, null, null);
  perform pg_temp.check(pg_temp.vqty() = 5 and (select sum(quantity) from public.tiktok_voucher_sales where order_id = pg_temp.oid_('V')) = 0,
    'V restocked: back');
end $$;

-- ═════ R: refresh_tiktok_staging ═════
do $$ declare b uuid; begin
  b := pg_temp.stage(jsonb_build_array(pg_temp.ln('R', 'sku_new', 'cancel', jsonb_build_object('shipped_time', '12/10/2026 10:00:00'))), 'file 19');
  perform pg_temp.check(pg_temp.staged(b, 'R') = 'Unmatched SKU 0', 'R staged before its SKU is mapped: "Unmatched SKU"');
  insert into public.tiktok_sku_aliases(store_id, seller_sku, target_kind, target_id, created_by)
  values (pg_temp.fx('store'), pg_temp.tx('sku_new'), 'product', pg_temp.fx('soap'), pg_temp.fx('owner'));
  perform public.refresh_tiktok_staging(b);
  perform pg_temp.check(pg_temp.staged(b, 'R') = 'New — Will Deduct, Awaiting Return 1', 'R mapped and refreshed: read with the row''s shipped time');
  perform pg_temp.confirm(b);
  perform pg_temp.check(pg_temp.qty('soap') = 14 and pg_temp.returns_('R') = 'awaiting 1', 'R confirmed: one off, awaiting');
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 465 checks passed.';
end $$;
rollback;
