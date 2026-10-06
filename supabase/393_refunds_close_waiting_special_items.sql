-- 393_refunds_close_waiting_special_items.sql
--
-- WHAT WAS WRONG (found 5-6 Oct 2026)
--
-- Paying an invoice with a special product or a rental on it raises a special
-- sale (SPS-) or a rental (RNT-) that waits on the Special page, under
-- "Waiting for a warehouse", until an Owner or Manager releases it from a
-- warehouse or a store. Nothing closed those items when the sale fell away:
--
--   * refund_invoice_recorded touched neither special sales nor rentals, so a
--     refunded machine stayed on the waiting list and could still be released;
--   * cancel_invoice_recorded cancelled the invoice's rentals (300) but not its
--     special sales;
--   * a line removed from the invoice by a correction left its item waiting;
--   * the waiting list (special_docs_awaiting_fulfilment) and Release
--     (fulfil_special_doc) never looked at the invoice at all;
--   * create_special_docs_for_invoice skipped a line with ANY item, even a
--     cancelled one, so a refunded invoice reopened and paid again would never
--     bring its item back once refunds closed it;
--   * a correction that adds a special or rental line to a paid invoice (or
--     replaces one: changing a line's kind removes it and adds a new one)
--     never raised its item, because only a payment raises them.
--
-- In production on 6 Oct 2026 three special sales on two refunded invoices
-- were still waiting, and any of them could still have been released, taking
-- stock out of a warehouse for a sale that no longer exists.
--
-- THE RULES (the Owner, 6 Oct 2026)
--
--   1. When an invoice is refunded or cancelled, or a special or rental line is
--      removed from it, its WAITING items (a special sale 'pending', a rental
--      'awaiting_fulfilment', neither released from a warehouse nor a store)
--      are cancelled: status 'cancelled', cancelled_at, a note saying why
--      ("Cancelled (refunded): <reason>"), and an audit row. They leave the
--      waiting list and stay on the Sales and Rentals tabs as cancelled.
--      Items already released are not touched by this.
--   2. A partial refund asks, for each waiting item on the invoice, "Is the
--      customer still taking this item?". Yes keeps it waiting; No cancels it
--      when the refund is recorded. A refund that leaves the invoice refunded
--      cancels them all without asking. Refunds are requested and approved
--      later, so the answer is stored with the request and honoured when it is
--      approved. With no answer (an older request, another caller) an item is
--      cancelled only when the refund takes its line's whole value back (to
--      the cent), and otherwise keeps waiting.
--   3. Release refuses an item whose invoice is refunded, cancelled or deleted,
--      or whose line no longer exists, and says why. The waiting list leaves
--      those out too.
--   4. A refunded or cancelled invoice that is reopened and paid again brings
--      its item back.
--   5. Items already waiting on an invoice that is refunded, cancelled or
--      deleted are cancelled now, once.
--
-- WHAT THIS DOES
--
--   * special_doc_invoice_problem(invoice, line): why an item may not be
--     released against its invoice, in words, or null.
--   * cancel_waiting_special_docs(invoice, why, reason[, line][, items]):
--     cancels the invoice's waiting items (or one line's, or the listed ones),
--     with the note and an audit row ('waiting_item_cancelled').
--   * settle_waiting_special_docs_on_refund(invoice, lines, reason): rule 2.
--     The answers ride on the refund's lines, as
--       "waiting": [{"doc_id": "<item id>", "still_taking": true|false}]
--     on any one of them; each must name an item on the invoice, once.
--   * trg_special_docs_follow_line_removed, on invoice_items after delete:
--     a removed line cancels its waiting items (rule 1). Lines are removed by
--     update_invoice_internal, the corrections' writer; a trigger also covers
--     any later path.
--   * refund_invoice_recorded: calls settle_waiting_special_docs_on_refund
--     after the invoice's status is settled (rules 1 and 2).
--   * resolve_invoice_action_v2: the approved refund carries the requester's
--     answers, stored in the request's lines by request_invoice_action_v2
--     (which keeps its lines as given and needs no change).
--   * cancel_invoice_recorded: cancels the waiting special sales beside the
--     rentals it already cancels (rule 1).
--   * special_docs_awaiting_fulfilment and fulfil_special_doc: rule 3.
--   * create_special_docs_for_invoice: a waiting item cancelled before the
--     invoice was last reopened no longer counts as the line's item, so
--     paying the reopened invoice raises a new one (rule 4). An item
--     cancelled since still counts, and so does one that was ever released (a
--     rental cancelled with its invoice while still out, awaiting its return),
--     so neither is raised twice.
--   * reopen_invoice: an invoice reopened straight to paid (its money was
--     still held, as after a cancellation) raises its items again; otherwise
--     the payment that settles it does (rule 4).
--   * correct_invoice: a correction that makes an invoice paid raises the
--     items of its special and rental lines, as paying does. On an invoice
--     that was already paid, only the lines the correction added are raised
--     (create_special_docs_for_invoice is told which, through the
--     transaction's energia.special_docs_only setting); a line that was
--     already there without an item, from before invoices raised them, is
--     left alone (the Owner, 6 Oct 2026). Without this, rule 1's removed-line
--     cancellation would leave a paid machine whose line was replaced (its
--     kind changed) with nothing waiting at all.
--   * The one-off cancellation of rule 5, counted in a notice. Production on
--     6 Oct 2026: 3 special sales on 2 refunded invoices, no rentals.
--
-- NOT CHANGED
--
--   * Released items (a special sale 'completed', a rental 'active', 'paid',
--     'overdue' or 'returned'): their stock has moved and they are settled
--     through their own return flows. cancel_invoice_rentals still handles
--     the rentals of a cancelled invoice as 300 made it, and a released item
--     is never raised again for its line.
--   * A correction that only changes a waiting line's quantity or machine
--     (the line keeps its id) leaves its item as it was. A correction that
--     changes no line raises nothing, unless it makes the invoice paid.
--   * A paid special or rental line that has never had an item (production
--     on 6 Oct 2026: one rental line, on an invoice corrected once) gets one
--     only when a later correction changes that invoice's lines, as any line
--     without an item would.
--   * Direct special sales and rentals made on the Special page with no
--     invoice.
--   * request_invoice_action_v2, invoice_action_plan and the plan hash: the
--     answers do not change what a refund returns.
--   * The legacy request_invoice_action (no plan; Approvals cannot approve it).
--   * No other data.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block), so
-- it is atomic however it is run. Every guard and anchor is checked, and every
-- patched text built, before anything is installed. md5(pg_get_functiondef)
-- of each patched function must be the production version read on 6 Oct 2026
-- (BEFORE), or already this migration's version (AFTER), which is left alone
-- so a re-run changes nothing. A new function that exists with any other text
-- refuses. Every anchor must match exactly once. Patches are executed as
-- CREATE OR REPLACE, which keeps owner and grants. The new functions are
-- revoked from public, anon and authenticated and granted to service_role
-- (339): they are reached only from inside SECURITY DEFINER functions and the
-- trigger. After installing, every function must have its AFTER md5 and the
-- grants are checked. The trigger is created only if it is not there, and the
-- one-off cancellation finds nothing the second time.
--
-- 363 (written, not applied on 6 Oct 2026) patches refund_invoice_recorded,
-- resolve_invoice_action_v2 and cancel_invoice_recorded from the same BEFORE
-- versions, so whichever of the two is applied second refuses until it is
-- re-based. 393's anchors were checked against 363's versions and each still
-- matches once: after 363, only these three BEFORE md5s (and their AFTERs)
-- would change. correct_invoice is patched often (362, 370, 377, 384, 385);
-- if it has moved on, 393 refuses rather than guessing.
--
-- BEFORE (production, 6 Oct 2026, md5 of pg_get_functiondef):
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)                7dd62acaef1c995cc5e12effff6640fb
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)    67e3cc6b44eb8d259d92ae5e27a304ee
--   cancel_invoice_recorded(uuid,text,uuid)                                   c84a8a4f259cfc2c52ab92f80cac5e17
--   fulfil_special_doc(text,uuid,uuid,text)                                   663c2a87ed4dad84fbd0cd534079d065
--   special_docs_awaiting_fulfilment()                                        0388e03efa9d77a23560ea1486704b1e
--   create_special_docs_for_invoice(uuid)                                     f906c0dfebf2e9ef501c68885bc55bef
--   reopen_invoice(uuid,text,uuid)                                            ede44e307def001381fb3e2d48919e24
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                               66be5d3ccebee3ee6526b170906f367b
-- AFTER (for later guards):
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)                42de7a5ac079fe706968e90d038cd5a5
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)    ff29fda79f9a5e0676bc023f2f5a06e0
--   cancel_invoice_recorded(uuid,text,uuid)                                   30d643c7890c12d885ad83ba61ccf49a
--   fulfil_special_doc(text,uuid,uuid,text)                                   76f9495c44e017beb5275ed8a8112fda
--   special_docs_awaiting_fulfilment()                                        ff0f89048581abdfac941fdf84e39514
--   create_special_docs_for_invoice(uuid)                                     e5503f03bf5b615ec9b948fecdc52b55
--   reopen_invoice(uuid,text,uuid)                                            64cdf1f76339f7b9c0676b3411e84a83
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                               dee0cc78f37f8444c6d13547648e7529
--   special_doc_invoice_problem(uuid,uuid)                                   be2b8ec5a4003a1dca34e17a82f89932
--   cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])                   fe4753fffded2cc463dbe24571a9675c
--   settle_waiting_special_docs_on_refund(uuid,jsonb,text)                    307f671efc73adf5ebf8fedd9c880812
--   trg_special_docs_follow_line_removed()                                    25b2fac3612be3ab56151f3e109c3574
--
-- Test: scripts/special/tests/refund-closes-waiting.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New functions ──────────────────────────────────────────────────────────
  c_problem_def constant text := $def$
create or replace function public.special_doc_invoice_problem(p_invoice_id uuid, p_invoice_item_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $fn$
  -- 393: why an item may no longer be released against its invoice, in words,
  -- or null when it may. An item sold without an invoice has nothing to check.
  select case
           when i.deleted_at is not null then 'its invoice ' || i.invoice_no || ' was deleted'
           when i.status = 'refunded' then 'its invoice ' || i.invoice_no || ' was refunded'
           when i.status = 'cancelled' then 'its invoice ' || i.invoice_no || ' was cancelled'
           when p_invoice_item_id is not null and not exists (
                  select 1 from public.invoice_items ii
                   where ii.id = p_invoice_item_id and ii.invoice_id = i.id)
             then 'its line was removed from invoice ' || i.invoice_no
         end
    from public.invoices i
   where i.id = p_invoice_id
$fn$
$def$;
  c_cancel_waiting_def constant text := $def$
create or replace function public.cancel_waiting_special_docs(p_invoice_id uuid, p_why text, p_reason text,
  p_invoice_item_id uuid default null, p_doc_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
-- 393: cancels the invoice's items still waiting for a warehouse: a special
-- sale not yet released, a rental not yet handed over. Only one line's when a
-- line is given, only the listed ones when ids are given. Released items are
-- never touched; their stock has moved and they have their own return flows.
-- The note says why ("Cancelled (refunded): ..."), which the Special page shows.
declare r record; v_note text; n integer := 0;
begin
  v_note := 'Cancelled (' || p_why || ')' || coalesce(': ' || nullif(btrim(p_reason), ''), '');
  for r in select * from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status = 'pending'
              and s.warehouse_id is null and s.source_store_id is null
              and (p_invoice_item_id is null or s.invoice_item_id = p_invoice_item_id)
              and (p_doc_ids is null or s.id = any (p_doc_ids))
            order by s.sale_no for update
  loop
    update public.special_sales
       set status = 'cancelled', cancelled_at = now(), notes = concat_ws(E'\n', notes, v_note)
     where id = r.id;
    perform public.write_audit_ex('special_sales', r.id, 'waiting_item_cancelled', to_jsonb(r),
      jsonb_build_object('status', 'cancelled', 'why', p_why, 'doc_no', r.sale_no,
        'invoice_id', p_invoice_id, 'invoice_item_id', r.invoice_item_id),
      'special', v_note, r.store_id);
    n := n + 1;
  end loop;
  for r in select * from public.rentals x
            where x.invoice_id = p_invoice_id and x.status = 'awaiting_fulfilment'
              and x.warehouse_id is null and x.source_store_id is null
              and (p_invoice_item_id is null or x.invoice_item_id = p_invoice_item_id)
              and (p_doc_ids is null or x.id = any (p_doc_ids))
            order by x.rental_no for update
  loop
    update public.rentals
       set status = 'cancelled', cancelled_at = now(), notes = concat_ws(E'\n', notes, v_note)
     where id = r.id;
    perform public.write_audit_ex('rentals', r.id, 'waiting_item_cancelled', to_jsonb(r),
      jsonb_build_object('status', 'cancelled', 'why', p_why, 'doc_no', r.rental_no,
        'invoice_id', p_invoice_id, 'invoice_item_id', r.invoice_item_id),
      'special', v_note, r.store_id);
    n := n + 1;
  end loop;
  return n;
end $fn$
$def$;
  c_settle_def constant text := $def$
create or replace function public.settle_waiting_special_docs_on_refund(p_invoice_id uuid, p_lines jsonb, p_reason text)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
-- 393: what a recorded refund does to the invoice's items still waiting for a
-- warehouse (the Owner, 6 Oct 2026). A refund that leaves the invoice
-- refunded cancels them all. Otherwise each follows the answer staff gave to
-- "Is the customer still taking this item?", carried on the refund's lines as
--   "waiting": [{"doc_id": "<item id>", "still_taking": true|false}]
-- and with no answer an item is cancelled only when this refund takes its
-- line's whole value back (to the cent); otherwise it keeps waiting.
declare
  v_inv public.invoices%rowtype; v_answers jsonb := '{}'; a jsonb; d record;
  v_keep boolean; v_value numeric; v_refunded numeric; n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if exists (select 1 from jsonb_array_elements(coalesce(p_lines, '[]')) e
              where e ? 'waiting' and jsonb_typeof(e->'waiting') is distinct from 'array') then
    raise exception 'The answers about waiting items must be a list'; end if;

  -- The answers, checked: each names an item on this invoice, once, yes or no.
  for a in select q from jsonb_array_elements(coalesce(p_lines, '[]')) e,
                         jsonb_array_elements(coalesce(e->'waiting', '[]')) q
  loop
    if jsonb_typeof(a->'still_taking') is distinct from 'boolean' then
      raise exception 'Say whether the customer is still taking each waiting item (yes or no)'; end if;
    if not exists (select 1 from public.special_sales
                    where id::text = lower(a->>'doc_id') and invoice_id = p_invoice_id)
       and not exists (select 1 from public.rentals
                        where id::text = lower(a->>'doc_id') and invoice_id = p_invoice_id) then
      raise exception 'A waiting item answered for is not on this invoice'; end if;
    if v_answers ? lower(a->>'doc_id') then
      raise exception 'Answer once for each waiting item'; end if;
    v_answers := v_answers || jsonb_build_object(lower(a->>'doc_id'), a->'still_taking');
  end loop;

  if v_inv.status in ('refunded', 'cancelled') then
    return public.cancel_waiting_special_docs(p_invoice_id, 'refunded', p_reason);
  end if;

  for d in select s.id, s.invoice_item_id from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status = 'pending'
              and s.warehouse_id is null and s.source_store_id is null
           union all
           select x.id, x.invoice_item_id from public.rentals x
            where x.invoice_id = p_invoice_id and x.status = 'awaiting_fulfilment'
              and x.warehouse_id is null and x.source_store_id is null
  loop
    if v_answers ? d.id::text then
      v_keep := (v_answers->>d.id::text)::boolean;
    elsif d.invoice_item_id is not null and exists (
            select 1 from jsonb_array_elements(coalesce(p_lines, '[]')) e
             where e->>'invoice_item_id' = d.invoice_item_id::text and e ? 'amount') then
      -- Refunded on this line since the invoice was last reopened, this
      -- refund included, as refund_invoice_recorded counts it.
      v_value := coalesce(public.invoice_discounted_line_value(d.invoice_item_id), 0);
      select coalesce(sum((e->>'amount')::numeric), 0) into v_refunded
        from public.invoice_refunds r, jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e
       where r.invoice_id = p_invoice_id
         and (v_inv.reopened_at is null or r.created_at > v_inv.reopened_at)
         and e->>'invoice_item_id' = d.invoice_item_id::text;
      v_keep := not (v_value > 0 and v_refunded >= v_value - 0.01);
    else
      v_keep := true;
    end if;
    if not v_keep then
      n := n + public.cancel_waiting_special_docs(p_invoice_id, 'refunded', p_reason, null, array[d.id]);
    end if;
  end loop;
  return n;
end $fn$
$def$;
  c_trigger_def constant text := $def$
create or replace function public.trg_special_docs_follow_line_removed()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- 393: a line removed from its invoice cancels its item still waiting for a
  -- warehouse. A released item is left alone.
  perform public.cancel_waiting_special_docs(old.invoice_id, 'line removed', null, old.id);
  return old;
end $fn$
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  c_refund_a constant text :=
       E' perform public.reconcile_invoice_commissions(i.id,''Refund: ''||p_reason);\n';
  c_refund_r constant text :=
       E' -- 393: its items still waiting for a warehouse follow the refund: all\n'
    || E' -- cancelled when it closes the invoice, otherwise as staff answered.\n'
    || E' perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);\n'
    || E' perform public.reconcile_invoice_commissions(i.id,''Refund: ''||p_reason);\n';

  c_resolve_a1 constant text :=
       E' v_exec numeric; v_planned numeric; v_alloc numeric; v_assigned numeric; v_n int; v_idx int;\n';
  c_resolve_r1 constant text :=
       E' v_exec numeric; v_planned numeric; v_alloc numeric; v_assigned numeric; v_n int; v_idx int;\n'
    || E' v_waiting jsonb;  -- 393\n';
  c_resolve_a2 constant text :=
       E'   raise exception ''There is nothing left to refund on this invoice''; end if;\n'
    || E'  v_refund:=public.refund_invoice_recorded(i.id,v_lines,v_sources,v_stock,coalesce(p_note,r.reason),r.id);\n';
  c_resolve_r2 constant text :=
       E'   raise exception ''There is nothing left to refund on this invoice''; end if;\n'
    || E'  -- 393: the requester''s answers to "Is the customer still taking this\n'
    || E'  -- item?", kept in the request''s lines, go with the refund.\n'
    || E'  select jsonb_agg(q) into v_waiting\n'
    || E'    from jsonb_array_elements(coalesce(r.payload->''lines'',''[]'')) l,\n'
    || E'         jsonb_array_elements(case when jsonb_typeof(l->''waiting'')=''array'' then l->''waiting'' else ''[]''::jsonb end) q;\n'
    || E'  if v_waiting is not null then v_lines:=jsonb_set(v_lines,''{0,waiting}'',v_waiting); end if;\n'
    || E'  v_refund:=public.refund_invoice_recorded(i.id,v_lines,v_sources,v_stock,coalesce(p_note,r.reason),r.id);\n';

  c_cancel_a constant text :=
       E' perform public.cancel_invoice_rentals(i.id,p_reason);\n';
  c_cancel_r constant text :=
       E' perform public.cancel_invoice_rentals(i.id,p_reason);\n'
    || E' -- 393: and its special sales still waiting for a warehouse.\n'
    || E' perform public.cancel_waiting_special_docs(i.id,''invoice cancelled'',p_reason);\n';

  c_fulfil_a1 constant text :=
       E'  v_avail record; v_loc_name text; v_type public.location_type;\n';
  c_fulfil_r1 constant text :=
       E'  v_avail record; v_loc_name text; v_type public.location_type;\n'
    || E'  v_problem text;  -- 393\n';
  c_fulfil_a2 constant text :=
       E'    raise exception ''Unknown document kind "%"'', p_doc_kind;\n'
    || E'  end if;\n';
  c_fulfil_r2 constant text :=
       E'    raise exception ''Unknown document kind "%"'', p_doc_kind;\n'
    || E'  end if;\n'
    || E'\n'
    || E'  -- 393: never release an item its invoice no longer sells (refunded,\n'
    || E'  -- cancelled or deleted, or its line removed), whatever a list showed.\n'
    || E'  select public.special_doc_invoice_problem(d.invoice_id, d.invoice_item_id) into v_problem\n'
    || E'    from (select invoice_id, invoice_item_id from public.special_sales\n'
    || E'           where p_doc_kind = ''special_sale'' and id = p_doc_id\n'
    || E'          union all\n'
    || E'          select invoice_id, invoice_item_id from public.rentals\n'
    || E'           where p_doc_kind = ''rental'' and id = p_doc_id) d;\n'
    || E'  if v_problem is not null then\n'
    || E'    raise exception ''% cannot be released: %. It is no longer waiting for a warehouse.'', v_no, v_problem;\n'
    || E'  end if;\n';

  c_list_a1 constant text :=
       E'   where s.warehouse_id is null and s.source_store_id is null and s.status <> ''cancelled''\n';
  c_list_r1 constant text :=
       E'   where s.warehouse_id is null and s.source_store_id is null and s.status <> ''cancelled''\n'
    || E'     and public.special_doc_invoice_problem(s.invoice_id, s.invoice_item_id) is null  -- 393\n';
  c_list_a2 constant text :=
       E'   where r.warehouse_id is null and r.source_store_id is null and r.status <> ''cancelled''\n';
  c_list_r2 constant text :=
       E'   where r.warehouse_id is null and r.source_store_id is null and r.status <> ''cancelled''\n'
    || E'     and public.special_doc_invoice_problem(r.invoice_id, r.invoice_item_id) is null  -- 393\n';

  c_docs_a constant text :=
       E'    if exists (select 1 from public.special_sales where invoice_item_id = v_it.id)\n'
    || E'       or exists (select 1 from public.rentals where invoice_item_id = v_it.id) then\n';
  c_docs_r constant text :=
       E'    -- 393: a correction of an invoice that was already paid names the\n'
    || E'    -- lines it added, and only those are raised; a line that was already\n'
    || E'    -- on the paid invoice without an item is left alone (the Owner, 6 Oct).\n'
    || E'    if coalesce(current_setting(''energia.special_docs_only'', true), '''') <> ''''\n'
    || E'       and position('','' || v_it.id::text || '','' in\n'
    || E'                    '','' || current_setting(''energia.special_docs_only'', true) || '','') = 0 then\n'
    || E'      continue;\n'
    || E'    end if;\n'
    || E'    -- 393: a waiting item cancelled before the invoice was last reopened\n'
    || E'    -- does not count, so a refunded or cancelled invoice reopened and paid\n'
    || E'    -- again raises its item afresh. One cancelled since then still counts,\n'
    || E'    -- and so does one ever released (a rental cancelled while still out),\n'
    || E'    -- so neither is raised twice.\n'
    || E'    if exists (select 1 from public.special_sales where invoice_item_id = v_it.id\n'
    || E'                and (status <> ''cancelled'' or warehouse_id is not null or source_store_id is not null\n'
    || E'                     or coalesce(cancelled_at, ''infinity'') > coalesce(v_inv.reopened_at, ''-infinity'')))\n'
    || E'       or exists (select 1 from public.rentals where invoice_item_id = v_it.id\n'
    || E'                and (status <> ''cancelled'' or warehouse_id is not null or source_store_id is not null\n'
    || E'                     or coalesce(cancelled_at, ''infinity'') > coalesce(v_inv.reopened_at, ''-infinity''))) then\n';

  c_reopen_a constant text :=
       E' update public.invoices set status=v_status,paid_amount=n,reopened_at=clock_timestamp(),edit_count=coalesce(edit_count,0)+1,edited_at=now(),edited_by=auth.uid() where id=i.id;\n';
  c_reopen_r constant text :=
       E' update public.invoices set status=v_status,paid_amount=n,reopened_at=clock_timestamp(),edit_count=coalesce(edit_count,0)+1,edited_at=now(),edited_by=auth.uid() where id=i.id;\n'
    || E' -- 393: reopened straight to paid (its money was still held), its special\n'
    || E' -- items and rentals wait for a warehouse again. Otherwise the payment\n'
    || E' -- that settles it raises them.\n'
    || E' if v_status=''paid'' then perform public.create_special_docs_for_invoice(i.id); end if;\n';

  c_correct_decl_a constant text :=
       E' v362_before jsonb; v362_therapy jsonb := ''{}''::jsonb;\n';
  c_correct_decl_r constant text :=
       E' v362_before jsonb; v362_therapy jsonb := ''{}''::jsonb;\n'
    || E' v393_before uuid[];  -- 393: the lines before this correction\n';
  c_correct_lines_a constant text :=
       E'  perform public.update_invoice_internal(i.id,n.customer_id,n.affiliate_id,p_items,';
  c_correct_lines_r constant text :=
       E'  v393_before := array(select id from public.invoice_items where invoice_id = i.id);\n'
    || E'  perform public.update_invoice_internal(i.id,n.customer_id,n.affiliate_id,p_items,';
  c_correct_a constant text :=
       E' update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;\n';
  c_correct_r constant text :=
       E' update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;\n'
    || E' -- 393: a correction that makes the invoice paid raises its special and\n'
    || E' -- rental items, as paying does. On an invoice that was already paid,\n'
    || E' -- only the lines this correction added are raised; a line that was\n'
    || E' -- already there without an item is left alone (the Owner, 6 Oct 2026).\n'
    || E' -- A removed line''s waiting item was cancelled as the line went.\n'
    || E' if v_status=''paid'' and i.status is distinct from ''paid'' then\n'
    || E'   perform public.create_special_docs_for_invoice(i.id);\n'
    || E' elsif v_status=''paid'' and not same_lines then\n'
    || E'   perform set_config(''energia.special_docs_only'', coalesce((select string_agg(ii.id::text, '','')\n'
    || E'     from public.invoice_items ii where ii.invoice_id = i.id\n'
    || E'      and not (ii.id = any(coalesce(v393_before, ''{}''::uuid[])))), ''''), true);\n'
    || E'   if current_setting(''energia.special_docs_only'', true) <> '''' then\n'
    || E'     perform public.create_special_docs_for_invoice(i.id); end if;\n'
    || E'   perform set_config(''energia.special_docs_only'', '''', true);\n'
    || E' end if;\n';

  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}';
begin
  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
     '7dd62acaef1c995cc5e12effff6640fb', '42de7a5ac079fe706968e90d038cd5a5', array[[c_refund_a, c_refund_r]]),
    ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
     '67e3cc6b44eb8d259d92ae5e27a304ee', 'ff29fda79f9a5e0676bc023f2f5a06e0', array[[c_resolve_a1, c_resolve_r1], [c_resolve_a2, c_resolve_r2]]),
    ('cancel_invoice_recorded(uuid,text,uuid)',
     'c84a8a4f259cfc2c52ab92f80cac5e17', '30d643c7890c12d885ad83ba61ccf49a', array[[c_cancel_a, c_cancel_r]]),
    ('fulfil_special_doc(text,uuid,uuid,text)',
     '663c2a87ed4dad84fbd0cd534079d065', '76f9495c44e017beb5275ed8a8112fda', array[[c_fulfil_a1, c_fulfil_r1], [c_fulfil_a2, c_fulfil_r2]]),
    ('special_docs_awaiting_fulfilment()',
     '0388e03efa9d77a23560ea1486704b1e', 'ff0f89048581abdfac941fdf84e39514', array[[c_list_a1, c_list_r1], [c_list_a2, c_list_r2]]),
    ('create_special_docs_for_invoice(uuid)',
     'f906c0dfebf2e9ef501c68885bc55bef', 'e5503f03bf5b615ec9b948fecdc52b55', array[[c_docs_a, c_docs_r]]),
    ('reopen_invoice(uuid,text,uuid)',
     'ede44e307def001381fb3e2d48919e24', '64cdf1f76339f7b9c0676b3411e84a83', array[[c_reopen_a, c_reopen_r]]),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)',
     '66be5d3ccebee3ee6526b170906f367b', 'dee0cc78f37f8444c6d13547648e7529', array[[c_correct_decl_a, c_correct_decl_r], [c_correct_lines_a, c_correct_lines_r], [c_correct_a, c_correct_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '393: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '393: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '393: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '393: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  for r in select * from (values
    ('special_doc_invoice_problem(uuid,uuid)', 'be2b8ec5a4003a1dca34e17a82f89932'),
    ('cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])', 'fe4753fffded2cc463dbe24571a9675c'),
    ('settle_waiting_special_docs_on_refund(uuid,jsonb,text)', '307f671efc73adf5ebf8fedd9c880812'),
    ('trg_special_docs_follow_line_removed()', '25b2fac3612be3ab56151f3e109c3574')) x(fn, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '393: a different public.% already exists (md5 %)', r.fn,
        md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))); end if;
  end loop;

  -- ── Install: the helpers first, then the patched functions that call them ──
  execute c_problem_def;
  execute c_cancel_waiting_def;
  execute c_settle_def;
  execute c_trigger_def;
  foreach v in array array['special_doc_invoice_problem(uuid,uuid)',
                           'cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])',
                           'settle_waiting_special_docs_on_refund(uuid,jsonb,text)',
                           'trg_special_docs_follow_line_removed()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', v);
    execute format('grant execute on function public.%s to service_role', v);
  end loop;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.invoice_items'::regclass
                    and tgname = 'special_docs_follow_line_removed' and not tgisinternal) then
    create trigger special_docs_follow_line_removed after delete on public.invoice_items
      for each row execute function public.trg_special_docs_follow_line_removed();
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', '42de7a5ac079fe706968e90d038cd5a5'),
    ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', 'ff29fda79f9a5e0676bc023f2f5a06e0'),
    ('cancel_invoice_recorded(uuid,text,uuid)', '30d643c7890c12d885ad83ba61ccf49a'),
    ('fulfil_special_doc(text,uuid,uuid,text)', '76f9495c44e017beb5275ed8a8112fda'),
    ('special_docs_awaiting_fulfilment()', 'ff0f89048581abdfac941fdf84e39514'),
    ('create_special_docs_for_invoice(uuid)', 'e5503f03bf5b615ec9b948fecdc52b55'),
    ('reopen_invoice(uuid,text,uuid)', '64cdf1f76339f7b9c0676b3411e84a83'),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'dee0cc78f37f8444c6d13547648e7529'),
    ('special_doc_invoice_problem(uuid,uuid)', 'be2b8ec5a4003a1dca34e17a82f89932'),
    ('cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])', 'fe4753fffded2cc463dbe24571a9675c'),
    ('settle_waiting_special_docs_on_refund(uuid,jsonb,text)', '307f671efc73adf5ebf8fedd9c880812'),
    ('trg_special_docs_follow_line_removed()', '25b2fac3612be3ab56151f3e109c3574')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '393: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The pages still reach what they call; the helpers are endpoints for nobody.
  foreach v in array array['refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
                           'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
                           'cancel_invoice_recorded(uuid,text,uuid)',
                           'fulfil_special_doc(text,uuid,uuid,text)',
                           'special_docs_awaiting_fulfilment()',
                           'reopen_invoice(uuid,text,uuid)',
                           'correct_invoice(uuid,jsonb,jsonb,text,uuid)'] loop
    if not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '393: public.% is no longer callable by staff', v; end if;
  end loop;
  foreach v in array array['special_doc_invoice_problem(uuid,uuid)',
                           'cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])',
                           'settle_waiting_special_docs_on_refund(uuid,jsonb,text)',
                           'trg_special_docs_follow_line_removed()',
                           'create_special_docs_for_invoice(uuid)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '393: public.% is callable by a client role', v; end if;
  end loop;

  -- ── Rule 5: items still waiting on an invoice that is already closed ──────
  n := 0;
  for r in select i2.id,
                  case when i2.deleted_at is not null then 'invoice deleted'
                       when i2.status = 'refunded' then 'refunded'
                       else 'invoice cancelled' end as why
             from public.invoices i2
            where (i2.deleted_at is not null or i2.status in ('refunded', 'cancelled'))
              and (exists (select 1 from public.special_sales s
                            where s.invoice_id = i2.id and s.status = 'pending'
                              and s.warehouse_id is null and s.source_store_id is null)
                or exists (select 1 from public.rentals x
                            where x.invoice_id = i2.id and x.status = 'awaiting_fulfilment'
                              and x.warehouse_id is null and x.source_store_id is null))
            order by i2.invoice_no
  loop
    n := n + public.cancel_waiting_special_docs(r.id, r.why,
      'the invoice was already closed when 393 was applied');
  end loop;
  raise notice '393: % waiting item(s) on refunded, cancelled or deleted invoices cancelled', n;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
