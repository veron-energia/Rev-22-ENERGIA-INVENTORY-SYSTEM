-- 362_a_correction_settles_the_therapy_it_changes.sql
--
-- THE GAP
--
-- A promotion (or a therapy line) that grants a therapy package issues purchased
-- therapy units against its invoice line when the invoice is paid
-- (invoice_therapy_entitlements_due, create_purchased_therapy_for_invoice).
-- correct_invoice rewrites lines through update_invoice_internal, which deletes
-- every line missing from the new payload. purchased_therapy_entitlements
-- .invoice_item_id is ON DELETE SET NULL, so swapping such a line out (or
-- changing its kind: the correction form clears the line id) left the unit
-- 'pending_activation' on no line: still claimable, though what granted it was
-- gone. A line kept under its id but given another promotion, or a lower
-- quantity, kept units it no longer grants. And a correction that swapped in
-- therapy on a paid invoice issued nothing, because units are only issued when
-- the invoice's status changes to paid. correct_invoice refused only while a
-- unit on the invoice was 'active' or 'expired'. Production: INV-2026-0086
-- (UTP-0000002 detached, UTP-0000003 issued on re-payment, by an older path).
--
-- WHAT THE OWNER DECIDED (26 Sep 2026)
--
--   1. Therapy a correction takes away closes if unused: the unit becomes
--      'cancelled', with an audit row, and vouchers not yet collected from it
--      are withdrawn (trg_revoke_therapy_unit_on_close). The correction is
--      refused while any of those units has been used (therapy_unit_consumed,
--      359: started, ended, or vouchers collected); Refund / Cancel ends used
--      therapy, with an amount.
--   2. Therapy a correction adds is issued at the correction when the invoice
--      is still paid in full (or FOC) afterwards, on the same terms as a sale
--      (one year to activate from the invoice's payment date). If the
--      correction leaves a balance, it is issued when that is paid, as before.
--   3. A unit whose package the corrected line still grants is kept: same
--      number, deadline and any choice made. Only the difference is closed or
--      issued. Confirmed the same day: when the line is deleted and the
--      package added back on a new line, the unit moves to that line.
--
-- WHAT THIS CHANGES
--
--   * correct_invoice, around update_invoice_internal:
--       - before: therapy_units_before_correction notes the lines the
--         correction removes or rewrites (a line kept as it is, or with only
--         its price changed, is not one of them) and the open units they hold,
--         and locks those units and their voucher allowances;
--       - after the lines are replaced: settle_corrected_therapy_units keeps
--         each unit its own line still grants; otherwise moves it to a line
--         this correction added or rewrote that grants the same package (so
--         deleting a line and adding it back keeps the unit, as (3) does for
--         a line kept under its id); otherwise closes it, and refuses if it
--         was used. Used units are kept first, then in the order issued;
--       - after the status is settled: issue_therapy_of_corrected_lines issues
--         what the added or rewritten lines grant, when the invoice is paid.
--     The result, the revision's after-snapshot and the correction's audit
--     row carry 'therapy': {closed, moved, issued} (entitlement numbers).
--   * create_purchased_therapy_for_invoice(uuid, uuid[]): the issuing body,
--     limited to the given lines (null = every line). The one-argument version,
--     which the paid trigger calls, now calls it with null; nothing else about
--     issuing changes.
--
-- WHY ONLY THE LINES A CORRECTION CHANGES
--
-- What a promotion grants is read from the live catalogue (promotion_items),
-- not from a snapshot. Reconciling every line would let an unrelated
-- correction close or issue therapy on an untouched line after the promotion
-- was edited. Untouched lines keep what they issued.
--
-- NOT CHANGED
--
--   * The existing refusal of any line, customer or store change while a unit
--     anywhere on the invoice is 'active' or 'expired'.
--   * A unit already on no line (UTP-0000002's shape) is left as it is: the
--     proposed repair in scripts/therapy/repair-promotion-therapy-units.sql
--     deals with that one.
--   * A closed unit leaves its line (invoice_item_id null, as the foreign key
--     already does when the line is deleted; the audit row keeps the line), so
--     the line can grant that package again later. Refunded units stay on
--     their line, so they are never issued again.
--   * A correction still cannot change which therapy a promotion's choice
--     group picked: invoice_line_matches compares selections by product and
--     voucher only, so such a change is not saved (unchanged by 362).
--   * update_invoice_internal still refuses a rewritten therapy line whose
--     package the customer holds a current unit of, including that line's own
--     unit (the 360 note).
--
-- SAFETY
--
-- Needs 359 and 360. Every patched function is guarded by the md5 of the
-- production version (26 Sep 2026) and by anchors that must each occur once;
-- a function already carrying "362:" is left alone, so a second run changes
-- nothing. New functions are internal (service_role only, 339). Functions
-- only; no data changes.

set lock_timeout = '5s';

do $mig$
begin
  if to_regprocedure('public.claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)') is null
     or to_regprocedure('public.therapy_unit_consumed(uuid)') is null then
    raise exception '362: apply 359 first'; end if;
  if to_regprocedure('public.therapy_switch_back_blocker(uuid)') is null then
    raise exception '362: apply 360 first'; end if;
end $mig$;

-- ── 1. issuing therapy for some lines of an invoice ─────────────────────────
do $mig$
declare d text; n int; v_md5 text;
        a_head text := 'public.create_purchased_therapy_for_invoice(p_invoice_id uuid)';
        a_loop text := $a$  for v_due in select * from public.invoice_therapy_entitlements_due(p_invoice_id)
  loop$a$;
begin
  d := pg_get_functiondef('public.create_purchased_therapy_for_invoice(uuid)'::regprocedure);
  if position('362:' in d) > 0 then
    raise notice '362: create_purchased_therapy_for_invoice already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '09ac9be8a09071d64e631c03e3a504ec' then
    raise exception '362: create_purchased_therapy_for_invoice is not the version this was tested against (md5 %)', v_md5; end if;
  n := (length(d) - length(replace(d, a_head, ''))) / length(a_head);
  if n <> 1 then raise exception '362: create_purchased_therapy_for_invoice header found % times', n; end if;
  n := (length(d) - length(replace(d, a_loop, ''))) / length(a_loop);
  if n <> 1 then raise exception '362: create_purchased_therapy_for_invoice loop anchor found % times', n; end if;

  -- The same body, limited to the given lines.
  d := replace(d, a_head, 'public.create_purchased_therapy_for_invoice(p_invoice_id uuid, p_lines uuid[])');
  d := replace(d, a_loop, $r$  -- 362: p_lines limits this to those lines of the invoice; null = every line.
  for v_due in select * from public.invoice_therapy_entitlements_due(p_invoice_id) due
                where p_lines is null or due.invoice_item_id = any(p_lines)
  loop$r$);
  execute d;
  revoke all on function public.create_purchased_therapy_for_invoice(uuid,uuid[]) from public, anon, authenticated;
  grant execute on function public.create_purchased_therapy_for_invoice(uuid,uuid[]) to service_role;

  -- The paid trigger's entry point: every line, through the same body.
  execute $f$create or replace function public.create_purchased_therapy_for_invoice(p_invoice_id uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  -- 362: every line of the invoice. The body is the two-argument version, which
  -- a correction also calls for just the lines it added or rewrote.
  return public.create_purchased_therapy_for_invoice(p_invoice_id, null::uuid[]);
end $function$$f$;
end $mig$;

-- ── 2. before the lines are replaced ────────────────────────────────────────
create or replace function public.therapy_units_before_correction(p_invoice_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
-- 362: taken by correct_invoice just before it replaces the lines.
--   lines   every line the invoice had
--   changed the lines this correction removes or rewrites (not a line kept as
--           it is, nor one whose price alone changes)
--   held    the open therapy units those lines hold, with their line
--   had     every therapy unit the invoice had
-- The held units and their voucher allowances are locked first, so a start or a
-- voucher collection at the same moment is seen by the check, not missed.
declare v_changed uuid[];
begin
  v_changed := array(
    select ii.id from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and not exists (select 1 from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x
                        where nullif(x->>'invoice_item_id','')::uuid = ii.id
                          and (public.invoice_line_matches(ii.id, x)
                               or public.invoice_benefit_price_only(ii.id, x)))
     order by ii.id);

  perform 1 from public.purchased_therapy_entitlements e
    where e.invoice_item_id = any(v_changed) and e.status not in ('cancelled','refunded')
    order by e.id for update;
  perform 1 from public.therapy_entitlements te
    where te.id in (select e.voucher_entitlement_id from public.purchased_therapy_entitlements e
                     where e.invoice_item_id = any(v_changed) and e.status not in ('cancelled','refunded'))
    order by te.id for update;

  return jsonb_build_object(
    'lines', to_jsonb(array(select id from public.invoice_items where invoice_id = p_invoice_id order by id)),
    'changed', to_jsonb(v_changed),
    'held', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'line', e.invoice_item_id) order by e.id), '[]'::jsonb)
               from public.purchased_therapy_entitlements e
              where e.invoice_item_id = any(v_changed) and e.status not in ('cancelled','refunded')),
    'had', (select coalesce(jsonb_agg(e.id order by e.id), '[]'::jsonb)
              from public.purchased_therapy_entitlements e where e.invoice_id = p_invoice_id));
end $function$;

-- Not an endpoint (339). Here, not at the end, so a run that stops partway
-- never leaves it callable.
revoke all on function public.therapy_units_before_correction(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.therapy_units_before_correction(uuid,jsonb) to service_role;

-- ── 3. after the lines are replaced: keep, move or close ────────────────────
create or replace function public.settle_corrected_therapy_units(p_invoice_id uuid, p_before jsonb,
  p_reason text, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
-- 362: the open units of the lines a correction removed or rewrote, set against
-- what the corrected invoice grants. p_before is therapy_units_before_correction.
-- Each unit, used ones first and then in the order issued:
--   1. stays if its own line still grants its package (owner, 26 Sep: keep it);
--   2. else moves to a line this correction added or rewrote that grants the
--      package and has room, so deleting a line and adding it back keeps it;
--   3. else closes ('cancelled'); refused if it was used.
-- Nothing changes unless every unit that has to close is unused.
declare
  v_scope uuid[];                 -- lines now on the invoice that this correction added or rewrote
  v_room jsonb := '{}'::jsonb;    -- 'line/package' -> units those lines grant and do not hold yet
  u record; e public.purchased_therapy_entitlements%rowtype;
  v_key text; v_to uuid; v_line uuid; v_store uuid; v_used text;
  v_keep uuid[] := '{}'; v_moves jsonb := '[]'::jsonb; v_close uuid[] := '{}';
  v_closed jsonb := '[]'::jsonb; v_moved jsonb := '[]'::jsonb;
begin
  if p_before is null or jsonb_array_length(coalesce(p_before->'held', '[]'::jsonb)) = 0 then
    return '{}'::jsonb; end if;
  select store_id into v_store from public.invoices where id = p_invoice_id;

  v_scope := array(
    select ii.id from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and (ii.id in (select x::uuid from jsonb_array_elements_text(p_before->'changed') x)
            or ii.id not in (select x::uuid from jsonb_array_elements_text(p_before->'lines') x)));
  for u in select due.invoice_item_id as line, due.therapy_package_id as pkg, sum(due.qty)::int as qty
             from public.invoice_therapy_entitlements_due(p_invoice_id) due
            where due.invoice_item_id = any(v_scope)
            group by 1, 2
  loop
    v_room := v_room || jsonb_build_object(u.line::text || '/' || u.pkg::text, u.qty);
  end loop;

  -- 1. its own line
  for u in select e2.id, e2.package_id, (h->>'line')::uuid as line
             from jsonb_array_elements(p_before->'held') h
             join public.purchased_therapy_entitlements e2 on e2.id = (h->>'id')::uuid
            where e2.status not in ('cancelled','refunded')
            order by public.therapy_unit_consumed(e2.id) desc, e2.unit_index nulls last, e2.created_at, e2.id
  loop
    v_key := u.line::text || '/' || u.package_id::text;
    if coalesce((v_room->>v_key)::int, 0) > 0 then
      v_room := jsonb_set(v_room, array[v_key], to_jsonb((v_room->>v_key)::int - 1));
      v_keep := v_keep || u.id;
    end if;
  end loop;

  -- 2. another line of this correction, or 3. closed
  for u in select e2.id, e2.package_id, (h->>'line')::uuid as line
             from jsonb_array_elements(p_before->'held') h
             join public.purchased_therapy_entitlements e2 on e2.id = (h->>'id')::uuid
            where e2.status not in ('cancelled','refunded')
            order by public.therapy_unit_consumed(e2.id) desc, e2.unit_index nulls last, e2.created_at, e2.id
  loop
    continue when u.id = any(v_keep);
    select split_part(r.key, '/', 1)::uuid into v_to
      from jsonb_each_text(v_room) r
     where split_part(r.key, '/', 2) = u.package_id::text and r.value::int > 0
     order by r.key limit 1;
    if v_to is not null then
      v_key := v_to::text || '/' || u.package_id::text;
      v_room := jsonb_set(v_room, array[v_key], to_jsonb((v_room->>v_key)::int - 1));
      v_moves := v_moves || jsonb_build_array(jsonb_build_object('id', u.id, 'from', u.line, 'to', v_to));
    else
      v_close := v_close || u.id;
    end if;
  end loop;

  select string_agg(x.entitlement_no, ', ' order by x.entitlement_no) into v_used
    from public.purchased_therapy_entitlements x
   where x.id = any(v_close) and public.therapy_unit_consumed(x.id);
  if v_used is not null then
    raise exception 'Therapy from a line this correction removes or changes has been started or has ended, or vouchers from it were collected (%). Keep that line, or end the therapy with Refund / Cancel on the invoice first.', v_used;
  end if;

  for u in select (m->>'id')::uuid as id, (m->>'from')::uuid as f, (m->>'to')::uuid as t
             from jsonb_array_elements(v_moves) m
  loop
    select * into e from public.purchased_therapy_entitlements where id = u.id;
    update public.purchased_therapy_entitlements
       set invoice_item_id = u.t, updated_by = auth.uid(), updated_at = now()
     where id = u.id;
    perform public.write_audit_ex('purchased_therapy_entitlements', u.id, 'moved_by_invoice_correction',
      jsonb_build_object('invoice_item_id', u.f),
      jsonb_build_object('invoice_item_id', u.t, 'request_id', p_request_id),
      'therapy', p_reason, v_store);
    v_moved := v_moved || to_jsonb(e.entitlement_no);
  end loop;

  for e in select * from public.purchased_therapy_entitlements where id = any(v_close) order by entitlement_no
  loop
    select (h->>'line')::uuid into v_line from jsonb_array_elements(p_before->'held') h
     where (h->>'id')::uuid = e.id;
    -- Closing withdraws vouchers not yet collected (trg_revoke_therapy_unit_on_close).
    -- The unit leaves its line, as it does when the line is deleted, so the
    -- line can grant the package again; the audit row keeps the line.
    update public.purchased_therapy_entitlements
       set status = 'cancelled', invoice_item_id = null, updated_by = auth.uid(), updated_at = now()
     where id = e.id;
    perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'closed_by_invoice_correction',
      jsonb_build_object('status', e.status, 'benefit_choice', e.benefit_choice, 'invoice_item_id', v_line),
      jsonb_build_object('status', 'cancelled', 'request_id', p_request_id,
        'line_removed', not exists (select 1 from public.invoice_items where id = v_line)),
      'therapy', p_reason, v_store);
    v_closed := v_closed || to_jsonb(e.entitlement_no);
  end loop;

  return jsonb_strip_nulls(jsonb_build_object(
    'closed', case when jsonb_array_length(v_closed) > 0 then v_closed end,
    'moved', case when jsonb_array_length(v_moved) > 0 then v_moved end));
end $function$;

revoke all on function public.settle_corrected_therapy_units(uuid,jsonb,text,uuid) from public, anon, authenticated;
grant execute on function public.settle_corrected_therapy_units(uuid,jsonb,text,uuid) to service_role;

-- ── 4. after the status is settled: issue what was added ────────────────────
create or replace function public.issue_therapy_of_corrected_lines(p_invoice_id uuid, p_before jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
-- 362: therapy the lines a correction added or rewrote grant, issued now when
-- the invoice is paid in full (or FOC), as a sale issues it at payment (owner,
-- 26 Sep). Otherwise the paid trigger issues it when the balance is paid.
-- Lines the correction left alone are not topped up here. Returns the units
-- the correction created, including any the paid trigger issued during it.
declare v_scope uuid[]; v_status text;
begin
  if p_before is null then return '{}'::jsonb; end if;
  select status::text into v_status from public.invoices where id = p_invoice_id;
  v_scope := array(
    select ii.id from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and (ii.id in (select x::uuid from jsonb_array_elements_text(p_before->'changed') x)
            or ii.id not in (select x::uuid from jsonb_array_elements_text(p_before->'lines') x)));
  if v_status in ('paid','completed_foc')
     and exists (select 1 from public.invoice_therapy_entitlements_due(p_invoice_id) due
                  where due.invoice_item_id = any(v_scope)) then
    perform public.create_purchased_therapy_for_invoice(p_invoice_id, v_scope);
  end if;
  return jsonb_strip_nulls(jsonb_build_object('issued',
    (select jsonb_agg(e.entitlement_no order by e.entitlement_no)
       from public.purchased_therapy_entitlements e
      where e.invoice_id = p_invoice_id
        and e.id not in (select x::uuid from jsonb_array_elements_text(p_before->'had') x))));
end $function$;

revoke all on function public.issue_therapy_of_corrected_lines(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.issue_therapy_of_corrected_lines(uuid,jsonb) to service_role;

-- ── 5. correct_invoice calls them ───────────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a record;
begin
  d := pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure);
  if position('362:' in d) > 0 then raise notice '362: correct_invoice already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'd1db5369ed8c579ca206ff65eb15f1f6' then
    raise exception '362: correct_invoice is not the version this was tested against (md5 %)', v_md5; end if;

  for a in select * from (values
    (1, $a$ v_operational boolean; v_stock_change boolean; v_had_stock boolean; v_after jsonb;$a$,
        $r$ v_operational boolean; v_stock_change boolean; v_had_stock boolean; v_after jsonb;
 v362_before jsonb; v362_therapy jsonb := '{}'::jsonb;$r$),
    (2, $a$  perform public.update_invoice_internal(i.id,n.customer_id,n.affiliate_id,p_items,$a$,
        $r$  -- 362: the lines this correction removes or rewrites, and the therapy they
  -- issued, noted (and locked) before the lines are replaced.
  v362_before := public.therapy_units_before_correction(i.id,p_items);
  perform public.update_invoice_internal(i.id,n.customer_id,n.affiliate_id,p_items,$r$),
    (3, $a$  perform set_config('invoice.manual_discount_reason','',true);$a$,
        $r$  perform set_config('invoice.manual_discount_reason','',true);
  -- 362: that therapy follows the corrected lines: kept, moved to a line this
  -- correction added, or closed if unused (refused if used).
  v362_therapy := public.settle_corrected_therapy_units(i.id,v362_before,p_reason,p_request_id);$r$),
    (4, $a$ update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;$a$,
        $r$ update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;
 -- 362: therapy the added or rewritten lines grant, issued now if the invoice is paid.
 if v362_before is not null then
   v362_therapy := v362_therapy || public.issue_therapy_of_corrected_lines(i.id,v362_before); end if;$r$),
    (5, $a$ into v_after from public.invoices v where v.id=i.id;$a$,
        $r$ into v_after from public.invoices v where v.id=i.id;
 if v362_therapy <> '{}'::jsonb then v_after := v_after || jsonb_build_object('therapy',v362_therapy); end if;$r$),
    (6, $a$jsonb_build_object('success',true,'revision',v_rev);$a$,
        $r$jsonb_build_object('success',true,'revision',v_rev,'therapy',v362_therapy);$r$)
  ) v(k, anchor, repl)
  loop
    n := (length(d) - length(replace(d, a.anchor, ''))) / length(a.anchor);
    if n <> 1 then raise exception '362: correct_invoice anchor % found % times', a.k, n; end if;
    d := replace(d, a.anchor, a.repl);
  end loop;
  execute d;
end $mig$;

notify pgrst, 'reload schema';
