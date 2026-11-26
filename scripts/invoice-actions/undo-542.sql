-- UNDO of 542 (with the user's go-ahead). It takes 542's text out of the four functions it changed
-- (the request's read rule in invoice_action_request_detail, the two stock rules in
-- refund_invoice_recorded, the approval entry in complete_invoice_finance_request, the store check
-- on a resolved request in resolve_invoice_action_v2, and the search path public, pg_temp in all
-- four), putting each back exactly as before 542 (md5s below), puts the read rule of
-- approval_requests back ("read own or manager+", 407), and drops invoice_line_holds_stock.
-- Afterwards any staff login with access to the invoice's store reads a refund or cancellation
-- request's details, an Admin and any Manager read every invoice request, a refund takes stock
-- answers for any of the invoice's deductions, and a direct action approves a waiting request with
-- no approval entry: L20 open again. Audit Log entries written since 542 stay (536). Run it BEFORE
-- scripts/customers/undo-540.sql.
--
-- It refuses, with nothing changed, unless every function 542 made or changed is exactly 542's and
-- no other function calls the helper. One transaction, all or nothing; it waits at most 5 seconds
-- for a lock. The 542 row in supabase_migrations.schema_migrations stays; with the user's OK,
-- remove that one row or record this UNDO beside it.
do $undo$
declare
  c_sig constant text[] := array[
    'invoice_action_request_detail(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'complete_invoice_finance_request()',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)'];
  c_before constant text[] := array[
    'c91613824dc7894cc3fc933898f5678c',
    '4f81d244db8f8c5b6d35143456fa8cc7',
    '9df7e408a0053d14a23e5b58ea9e5780',
    'd1ab83e457684ad3d010dd5a92719570'];
  c_after constant text[] := array[
    'd70250367385b0dec1ea5273d85e796c',
    '7802bc26966f422978e2b764b289944f',
    'ce65794aff1f9e1f3953a82012dc377e',
    'beb94a98887d55d8698a830f489e1225'];
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_sp_old constant text := E' SET search_path TO ''public''\n';
  c_sp_new constant text := E' SET search_path TO ''public'', ''pg_temp''\n';
  c_fn constant int[] := array[1, 2, 2, 3, 4];
  c_anchor constant text[] := array[
-- 1 invoice_action_request_detail: the request's rule
$a$ if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice request not accessible'; end if;
$a$,
-- 2 refund_invoice_recorded: a line refunded with no answer waits only on its own stock
$a$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
$a$,
-- 3 refund_invoice_recorded: an answer is for a refunded line's stock
$a$   if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
$a$,
-- 4 complete_invoice_finance_request
$a$begin
 if tg_table_name='invoice_refunds' then
  update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
    response_note='Refund recorded with line, payment-source and stock evidence; request '||new.request_id
    where related_record_id=new.invoice_id and request_type='invoice_refund' and status='pending'
      and (id=new.request_id or public.invoice_charge_total(new.invoice_id)<=0);
 elsif new.status='cancelled' then
  update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
    response_note='Audited cancellation recorded'
    where related_record_id=new.id and request_type='invoice_cancel' and status='pending';
 end if;
 return new;
$a$,
-- 5 resolve_invoice_action_v2: a resolved request's outcome, store first
$a$ if r.status<>'pending' then
  return jsonb_build_object('request_id',r.id,'status',r.status,'already_resolved',true,$a$];
  c_new constant text[] := array[
-- 1
$n$ if not found or not public.user_has_store_access(i.store_id) then
  raise exception 'Invoice request not accessible'; end if;
 -- 542 (security audit of 17 Nov 2026, L20; the user, 26 Nov 2026: "Requester sees own"): as
 -- 297 states it ("What an approver is shown, and who may see it"): an Owner, or a Manager with
 -- access to the invoice's store (above), and the member of staff who raised this request.
 -- Anyone else, other Staff of the store and an Admin among them, is refused.
 if coalesce(public.current_user_role()::text, '') not in ('owner', 'manager')
    and r.requested_by is distinct from auth.uid() then
  raise exception 'Invoice request not accessible'; end if;
$n$,
-- 2
$n$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
      -- 542 (security audit of 17 Nov 2026, L20): this line's own stock, as the answers below are
      -- held to it; another line's unanswered stock does not hold this line up.
      and public.invoice_line_holds_stock(it.id,qs.product_id)
$n$,
-- 3
$n$   if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
   -- 542 (security audit of 17 Nov 2026, L20): an answer is for the stock of a line this refund is
   -- for (its product, its promotion's products, or stock no line holds), never a line still billed.
   if not exists(select 1 from jsonb_array_elements(p_lines) pl
                  where nullif(pl->>'invoice_item_id','') is not null
                    and public.invoice_line_holds_stock((pl->>'invoice_item_id')::uuid,sm.product_id)) then
     raise exception 'Answer for the stock of the lines being refunded: "%" is not on a line this refund covers. Nothing was recorded.',
       (select pr.name from public.products pr where pr.id=sm.product_id); end if;
$n$,
-- 4
$n$declare ar public.approval_requests%rowtype; v_note text;
begin
 -- 542 (security audit of 17 Nov 2026, L20): a waiting request marked approved here by a direct
 -- action (a refund that closes the invoice out, or a cancellation made outside the request) gets
 -- the approval's Audit Log entry, invoice_action_approved, as resolve_invoice_action_v2 writes
 -- one. The request's own approval writes its entry itself, so none here for it: a refund recorded
 -- under the request's id, or a cancellation whose invoice revision carries it.
 if tg_table_name='invoice_refunds' then
  v_note:='Refund recorded with line, payment-source and stock evidence; request '||new.request_id;
  for ar in select * from public.approval_requests
             where related_record_id=new.invoice_id and request_type='invoice_refund' and status='pending'
               and (id=new.request_id or public.invoice_charge_total(new.invoice_id)<=0)
             order by id for update loop
   update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
     response_note=v_note
    where id=ar.id;
   if ar.id is distinct from new.request_id then
    perform public.write_audit_ex('approval_requests',ar.id,'invoice_action_approved',to_jsonb(ar),
      jsonb_build_object('status','approved','approved_by',auth.uid(),'response_note',v_note,
        'direct_action','refund','invoice_refund_id',new.id,'refund_request_id',new.request_id),
      'invoices',v_note,(select iv.store_id from public.invoices iv where iv.id=new.invoice_id));
   end if;
  end loop;
 elsif new.status='cancelled' then
  v_note:='Audited cancellation recorded';
  for ar in select * from public.approval_requests
             where related_record_id=new.id and request_type='invoice_cancel' and status='pending'
             order by id for update loop
   update public.approval_requests set status='approved',approved_by=auth.uid(),approved_at=now(),
     response_note=v_note
    where id=ar.id;
   if not exists (select 1 from public.invoice_revisions rv where rv.invoice_id=new.id and rv.request_id=ar.id) then
    perform public.write_audit_ex('approval_requests',ar.id,'invoice_action_approved',to_jsonb(ar),
      jsonb_build_object('status','approved','approved_by',auth.uid(),'response_note',v_note,
        'direct_action','cancellation'),
      'invoices',v_note,new.store_id);
   end if;
  end loop;
 end if;
 return new;
$n$,
-- 5
$n$ if r.status<>'pending' then
  -- 542 (security audit of 17 Nov 2026, L20): what a resolved request did is told only to an Owner
  -- or a Manager with access to the invoice's store, as for one still waiting (below).
  if not public.user_has_store_access((select iv.store_id from public.invoices iv where iv.id=r.related_record_id)) then
   raise exception 'Invoice not accessible'; end if;
  return jsonb_build_object('request_id',r.id,'status',r.status,'already_resolved',true,$n$];
  -- approval_requests' read rule: before, the source given to alter policy, and after (as
  -- pg_get_expr prints it). Invoice requests follow 297's rule; other requests as before.
  c_pol_name constant text := 'read approval requests';
  c_pol_before constant text := '(((requested_by = ( SELECT auth.uid() AS uid)) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR ( SELECT is_manager_or_above() AS is_manager_or_above))';
  c_pol_new_src constant text := $p$((requested_by = (select auth.uid())) and ((select public.current_user_role()) is not null))
    or ((request_type <> all (array['invoice_cancel', 'invoice_refund'])) and (select public.is_manager_or_above()))
    or ((request_type = any (array['invoice_cancel', 'invoice_refund']))
        and (((select public.current_user_role()) = 'owner'::public.user_role)
             or (((select public.current_user_role()) = 'manager'::public.user_role)
                 and exists (select 1 from public.invoices iv
                              where iv.id = approval_requests.related_record_id and public.user_has_store_access(iv.store_id)))))$p$;
  c_pol_after constant text := $q$(((requested_by = ( SELECT auth.uid() AS uid)) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR ((request_type <> ALL (ARRAY['invoice_cancel'::text, 'invoice_refund'::text])) AND ( SELECT is_manager_or_above() AS is_manager_or_above)) OR ((request_type = ANY (ARRAY['invoice_cancel'::text, 'invoice_refund'::text])) AND ((( SELECT current_user_role() AS current_user_role) = 'owner'::user_role) OR ((( SELECT current_user_role() AS current_user_role) = 'manager'::user_role) AND (EXISTS ( SELECT 1
   FROM invoices iv
  WHERE ((iv.id = approval_requests.related_record_id) AND user_has_store_access(iv.store_id))))))))$q$;
  c_pol_before_src constant text := '((requested_by = (select auth.uid())) and ((select public.current_user_role()) is not null)) or (select public.is_manager_or_above())';
  c_new_sig constant text := 'invoice_line_holds_stock(uuid,uuid)';
  c_new_md5 constant text := 'dbec8434a00e2969cf41c7145be440af';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[cardinality(c_sig)]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      raise exception 'undo 542: public.% is missing. Nothing was changed.', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_before[i] then
      raise exception 'undo 542: public.% is already its version of before 542; 542 is not in. Nothing was changed.', c_sig[i]; end if;
    if md5(d) <> c_after[i] then
      raise exception 'undo 542: public.% is not 542''s version (md5 %). Nothing was changed.', c_sig[i], md5(d); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 542: the grants of public.% are not the tested ones. Nothing was changed.', c_sig[i]; end if;
    if (length(d) - length(replace(d, c_sp_new, ''))) / length(c_sp_new) <> 1 then
      raise exception 'undo 542: public.% has no single search_path public, pg_temp. Nothing was changed.', c_sig[i]; end if;
    v_def[i] := replace(d, c_sp_new, c_sp_old);
  end loop;
  if to_regprocedure('public.' || c_new_sig) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig))) <> c_new_md5 then
    raise exception 'undo 542: public.% is missing or not 542''s. Nothing was changed.', c_new_sig; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
     and p.oid not in (select to_regprocedure('public.' || x) from unnest(c_sig || array[c_new_sig]) x)
     and pg_get_functiondef(p.oid) ~ 'invoice_line_holds_stock';
  if d is not null then
    raise exception 'undo 542: invoice_line_holds_stock is also used by %. Nothing was changed.', d; end if;
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.approval_requests'::regclass and p.polname = c_pol_name) is distinct from c_pol_after then
    raise exception 'undo 542: the read rule of public.approval_requests is not 542''s. Nothing was changed.'; end if;
  for i in reverse cardinality(c_fn) .. 1 loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'undo 542: 542''s text % is not found exactly once in public.%. Nothing was changed.', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'undo 542: public.% without 542''s text is not its version of before 542 (md5 %). Nothing was changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Put back (the functions first: refund_invoice_recorded calls the helper)
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  execute format('drop function public.%s', c_new_sig);
  execute format('alter policy %I on public.approval_requests using (%s)', c_pol_name, c_pol_before_src);

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before[i]
       or (select coalesce(string_agg(x::text, ',' order by x::text), '')
             from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception 'undo 542: public.% is not as before 542 after putting it back', c_sig[i]; end if;
  end loop;

  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.approval_requests'::regclass and p.polname = c_pol_name) is distinct from c_pol_before then
    raise exception 'undo 542: the read rule of public.approval_requests is not as before 542 after putting it back'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
