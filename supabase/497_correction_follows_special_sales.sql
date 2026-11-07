-- 497_correction_follows_special_sales.sql
--
-- A CORRECTION OF A SPECIAL SALE LINE TAKES THE LINE'S SALES WITH IT
-- (the user, 7 Nov 2026: "fix the corrections gap too". Asked what should happen to a machine
-- already released: "Goes back automatically". Asked about a raised quantity or another
-- machine: "Include it".)
--
-- (The number 497 is this file's name, its errors' prefix, its self-test's error code P0497,
-- its suite's and its UNDO's; if it changes at commit, change it in these places alone.)
--
-- WHAT WAS WRONG
--
--   A special sale line has one sale per unit (special_sales), raised when its invoice is
--   paid. When a correction changed the line, its sales stayed as they were, apart from a
--   waiting one on a line removed (393):
--     - a line removed, or its quantity lowered: a machine already released stayed "Released"
--       and out of stock, with nobody told; on a lowered line even a waiting one kept waiting;
--     - the line changed to another machine: the old machine's sales stayed, and the new
--       machine never joined the waiting list, so nobody was told to deliver it;
--     - the quantity raised: the extra units never joined the waiting list.
--   Production, 7 Nov 2026, read only: 8 released sales, none on a line removed, lowered or
--   changed, and none waiting, so no figure is wrong yet.
--
-- WHAT THIS DOES
--
--   1. invoice_special_sales_follow_lines (new, internal): correct_invoice calls it once the
--      corrected lines are saved, beside what rentals do (458), so the correction summary
--      shows what it does before anyone saves.
--        - Coming off a line: a waiting unit first (it comes off the waiting list), then a
--          released one, the newest first. A released unit goes back on the warehouse or
--          store it left, without a question, as a product's stock does in a correction; its
--          sale is over: cancelled, stock back, "Cancelled (line corrected)", and the Audit Log
--          and special_sale_returns keep it. If it did not really come back, a stock adjustment
--          corrects the count.
--        - A lowered line loses only the units above its new quantity: units a refund already
--          settled are not on the line any more, so lowering a part-refunded line to what is
--          left moves nothing. A machine a supplier sent (494) stays as it is: no stock moves.
--        - Going onto a line: a raised quantity, or another machine on the line, joins the
--          waiting list. A line that has no sale at all stays as it is (the Owner, 6 Oct 2026;
--          393). An invoice paying again after being reopened raises its own at the payment.
--        - Refused in words: a machine whose warehouse or store has been deleted (restore it,
--          or refund it as not returned), and another machine on a line with a refund recorded
--          (the refund belongs to the machine sold: add the other machine as a new line).
--   2. correct_invoice answers what it did ('special'), for the page to say, and hands it to
--      the correction summary; preview_invoice_correction lists it under "Special sales". A
--      summary is undone, so it writes nothing and uses up no sale number.
--   3. return_released_special_stock (496) takes the reason 'line corrected', and
--      special_sale_returns accepts it. Its stock movement is a Cancel Return, as a product's
--      in a correction is.
--   4. restore_released_special_stock (496): only its comment, which said a correction never
--      takes a released unit back.
--
-- WHAT THIS DOES NOT DO
--
--   Nothing changes for an invoice cancelled or refunded, for a rental (458 has its own rules),
--   or for a unit above its line's quantity from before this (none on production); a correction
--   of the customer or the store still leaves a special sale's own customer and store as they
--   were; a waiting sale on an invoice that owes money can still be released, as it could.
--
-- WITH 496
--
--   A unit a correction took off is settled, so a refund or a cancellation does not offer it
--   or put it back again. Reopened and paid again, the invoice raises what its corrected lines
--   hold (create_special_docs_for_invoice is relied on, unchanged).
--
-- UNDO: scripts/special/undo-497.sql (refuses unless each function is 497's version; what a
-- correction has already moved stays moved). A later migration changing these functions must
-- pin 497's AFTER md5s below.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The functions this patches: BEFORE (production now) and AFTER md5s
  c_sig constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'preview_invoice_correction(uuid,jsonb)',
    'return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)',
    'restore_released_special_stock(uuid,text,uuid)'];
  c_before constant text[] := array[
    '04d647e13e9424a9375942e5812e91a2',
    'f26752231c100461e11caddc03c98a33',
    '71c22eb51b75650836e09a95b827c0fe',
    '5f1b3d1d0c78a0c49d7fc2171301f5d1'];
  c_after constant text[] := array[
    '9aac5395dd18fd8349727d6c8aa0c633',
    '13b0925c29bd8ca14d8d8b7bd961fef8',
    '13c9f26bd2c3c275dcee559a22caa8e0',
    'b89207a71e25bd62821c5b61c696eeba'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO file swaps them back.
  c_fn constant int[] := array[1, 1, 1, 1, 2, 3, 3, 4];
  c_anchor constant text[] := array[
$a$ v458_rentals jsonb := '[]'::jsonb;  -- 458: what this correction did to the invoice's rentals$a$,
$a$ v458_rentals := public.invoice_rentals_follow_lines(i.id,v_snapshot->'items',p_reason);$a$,
$a$detail = (select jsonb_build_object('rentals', v458_rentals,  -- 458$a$,
$a$'rentals',v458_rentals)  -- 458: what the correction did to the invoice's rentals, for the page to say$a$,
$a$                    from jsonb_array_elements(v416_dry->'rentals') e)));
    end if;$a$,
$a$-- afresh, as a waiting one cancelled by a refund is (393). p_why is 'refunded' or
-- 'invoice cancelled'. Internal: refund_invoice_recorded, record_invoice_stock_return
-- and restore_released_special_stock call it, in the invoice's own transaction.$a$,
$a$  if p_why is null or p_why not in ('refunded', 'invoice cancelled') then
    raise exception '496: stock comes back for a refund or a cancellation, not "%"', p_why; end if;$a$,
$a$  -- (invoice_action_plan): a unit whose line a correction removed or lowered stays as
  -- it was, never moved without being shown. Returns how many units' sales it settled.
  -- Internal: cancel_invoice_recorded calls it, and not a correction
  -- (restore_invoice_stock is also that), which must never take a released unit back.$a$];
  c_new constant text[] := array[
$n$ v458_rentals jsonb := '[]'::jsonb;  -- 458: what this correction did to the invoice's rentals
 v497_special jsonb := '[]'::jsonb;  -- 497: what this correction did to the invoice's special sales$n$,
$n$ v458_rentals := public.invoice_rentals_follow_lines(i.id,v_snapshot->'items',p_reason);
 -- 497 (the user, 7 Nov 2026): and its special sales follow the corrected lines, here too
 -- so the correction summary says what they become before anyone saves.
 if not same_lines then
   v497_special := public.invoice_special_sales_follow_lines(i.id,v_snapshot->'items',p_reason,p_request_id);
 end if;$n$,
$n$detail = (select jsonb_build_object('rentals', v458_rentals,  -- 458
                        'special', v497_special,  -- 497$n$,
$n$'rentals',v458_rentals,  -- 458: what the correction did to the invoice's rentals, for the page to say
     'special',v497_special)  -- 497: and to its special sales$n$,
$n$                    from jsonb_array_elements(v416_dry->'rentals') e)));
    end if;
    -- 497 (the user, 7 Nov 2026): the special sales that follow the corrected lines,
    -- as the correction answers them.
    if jsonb_array_length(coalesce(v416_dry->'special', '[]'::jsonb)) > 0 then
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(
        'area', 'special_sales', 'change', 'changed',
        'detail', 'Saving does what is listed here.' || case when exists (select 1 from jsonb_array_elements(v416_dry->'special') e where e->>'state' = 'back')
                    then ' A machine going back is added to that stock without anyone being asked, so make sure it really came back; if it did not, correct the count with a stock adjustment.' else '' end,
        'items', (select jsonb_agg(jsonb_build_object('kind', 'special_sale', 'what', e.value->>'what') order by e.ordinality)
                    from jsonb_array_elements(v416_dry->'special') with ordinality e)));
    end if;$n$,
$n$-- afresh, as a waiting one cancelled by a refund is (393). p_why is 'refunded',
-- 'invoice cancelled' or (497) 'line corrected'. Internal: refund_invoice_recorded,
-- record_invoice_stock_return, restore_released_special_stock and
-- invoice_special_sales_follow_lines call it, in the invoice's own transaction.$n$,
$n$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected') then  -- 497
    raise exception '496: stock comes back for a refund, a cancellation or a corrected line, not "%"', p_why; end if;$n$,
$n$  -- (invoice_action_plan). A correction settles the units it takes off a line itself
  -- (497, invoice_special_sales_follow_lines), so its summary shows them first; a unit
  -- above its line's quantity from before that stays as it was, never moved without
  -- being shown. Returns how many units' sales it settled.
  -- Internal: cancel_invoice_recorded calls it; a correction does not.$n$];

  -- The function this adds
  c_add_sig constant text[] := array['invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)'];
  c_add_md5 constant text[] := array['630cd846df0cb44a2b6038e83a46a18d'];
  c_add_def constant text[] := array[
$d1$CREATE OR REPLACE FUNCTION public.invoice_special_sales_follow_lines(p_invoice_id uuid, p_before jsonb, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 497 (the user, 7 Nov 2026): an invoice's special sales follow a correction of its
-- lines. correct_invoice calls it once the corrected lines are saved (p_before: the
-- lines as they were, as its revision snapshot holds them); the correction summary
-- shows what it answers, and undoes it.
--   * Coming off a line (removed, lowered, or another machine on it): a waiting unit
--     first, then a released one, the newest first. A released unit goes back on the
--     warehouse or store it left, without a question, as a product's stock does in a
--     correction (return_released_special_stock). One a supplier sent stays as it is.
--     A unit a refund settled is not on the line any more, so a lowered line loses only
--     what is above its new quantity, and never more than the line came down by.
--   * Going onto a line (a raised quantity, another machine on it): joins the waiting
--     list. A line with no sale at all stays as it is (the Owner, 6 Oct 2026; 393). On
--     an invoice paying again after being reopened, the payment raises it, unless a
--     unit of the line still counts (create_special_docs_for_invoice would then pass
--     the line over). A summary (invoice.correction_preview) only says so, so it uses up
--     no sale number.
--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised.
declare
  v_inv public.invoices%rowtype; b jsonb; li public.invoice_items%rowtype; r record;
  v_line uuid; v_old_sp uuid; v_old_q integer; v_q integer; v_keep integer;
  v_gone boolean; v_swap boolean; v_take integer; v_raise integer; v_i integer; v_name text;
  v_owes boolean;
  v_preview boolean := coalesce(current_setting('invoice.correction_preview', true), '') = 'on';
  v_request uuid := coalesce(p_request_id, gen_random_uuid());
  v_reason text := coalesce(nullif(btrim(p_reason), ''), 'Invoice corrected');
  v_list jsonb := '[]'::jsonb;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or v_inv.status in ('cancelled', 'refunded') then return v_list; end if;
  -- The corrected invoice owes money (before any payment this correction records).
  v_owes := public.invoice_charge_total(p_invoice_id) > public.invoice_net_received(p_invoice_id);

  for b in select e from jsonb_array_elements(coalesce(p_before, '[]'::jsonb)) e
            where e->>'line_kind' = 'special_product' and nullif(e->>'special_product_id', '') is not null
            order by e->>'id'
  loop
    v_line := (b->>'id')::uuid;
    continue when not exists (select 1 from public.special_sales s
                               where s.invoice_id = p_invoice_id and s.invoice_item_id = v_line);
    v_old_sp := (b->>'special_product_id')::uuid;
    v_old_q := greatest(coalesce((b->>'quantity')::integer, 1), 1);
    select * into li from public.invoice_items where id = v_line and invoice_id = p_invoice_id;
    v_gone := li.id is null or li.line_kind::text <> 'special_product';
    v_swap := not v_gone and li.special_product_id is distinct from v_old_sp;
    v_q := case when v_gone then 0 else greatest(coalesce(li.quantity, 1), 1) end;
    continue when not v_gone and not v_swap and v_q = v_old_q;

    -- The refund belongs to the machine sold.
    if v_swap and exists (select 1 from public.invoice_refunds ir
                           where ir.invoice_id = p_invoice_id
                             and (v_inv.reopened_at is null or ir.created_at > v_inv.reopened_at)
                             and (ir.invoice_item_id = v_line
                                  or exists (select 1 from jsonb_array_elements(coalesce(ir.outcome->'lines', '[]'::jsonb)) e
                                              where e->>'invoice_item_id' = v_line::text))) then
      raise exception 'A refund is recorded on this line, so its machine cannot be changed. Keep the line as it is and add the other machine as a new line.';
    end if;

    -- A removed line's waiting units were cancelled as the line went (393): say so.
    if v_gone then
      for r in select s.sale_no, s.special_product_id from public.special_sales s
                where s.invoice_id = p_invoice_id and s.invoice_item_id = v_line
                  and s.status = 'cancelled' and s.cancelled_at = now() and not coalesce(s.stock_returned, false)
                order by s.sale_no desc
      loop
        v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'waiting_off',
          'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id) || ' comes off the waiting list'));
      end loop;
    end if;

    -- Coming off the line.
    if v_gone or v_swap or v_q < v_old_q then
      v_keep := case when v_gone or v_swap then 0 else v_q end;
      perform 1 from public.special_sales s
        where s.invoice_id = p_invoice_id and s.invoice_item_id = v_line for update;
      v_take := null;
      for r in select s.id, s.sale_no, s.special_product_id, s.supplier_id, s.release_movement_id,
                      x.out_qty, x.location_type, x.location_id, x.location_name,
                      case when s.status = 'pending' and s.warehouse_id is null and s.source_store_id is null
                                and s.supplier_id is null then 1
                           when x.out_qty > 0 then 2 else 3 end as place,
                      count(*) over () as n_open
                 from public.special_sales s
                 left join lateral (select rr.quantity - rr.resolved_quantity as out_qty, rr.location_type,
                                           rr.location_id, rr.location_name
                                      from public.special_release_rows(p_invoice_id) rr
                                     where rr.movement_id = s.release_movement_id) x on true
                where s.invoice_id = p_invoice_id and s.invoice_item_id = v_line and s.status <> 'cancelled'
                  and not coalesce(x.out_qty <= 0, false)  -- a refund settled it: not on the line any more
                order by 10, s.sale_no desc
      loop
        if v_take is null then
          v_take := case when v_gone or v_swap then r.n_open
                         else least(greatest(r.n_open - v_keep, 0), v_old_q - v_q) end;
        end if;
        exit when v_take <= 0;
        v_take := v_take - 1;
        v_name := public.special_product_name(r.special_product_id);
        if r.place = 1 then
          perform public.cancel_waiting_special_docs(p_invoice_id, 'line corrected', v_reason, null, array[r.id]);
          v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'waiting_off',
            'what', r.sale_no || ': ' || v_name || ' comes off the waiting list'));
        elsif r.place = 2 then
          if exists (select 1 from public.warehouses w where r.location_type = 'warehouse' and w.id = r.location_id and w.deleted_at is not null)
             or exists (select 1 from public.stores t where r.location_type = 'store' and t.id = r.location_id and t.deleted_at is not null) then
            raise exception '%: % left %, which has been deleted, so it cannot go back there. Restore % first, or take it back with Refund, which can record it as not returned.',
              r.sale_no, v_name, r.location_name, r.location_name;
          end if;
          perform public.return_released_special_stock(p_invoice_id, r.release_movement_id, r.out_qty, 0, 0,
                                                       v_request, v_reason, 'line corrected');
          v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'back',
            'what', r.sale_no || ': ' || v_name || ' goes back to ' || coalesce(r.location_name, 'where it left')));
        else
          v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'stays',
            'what', r.sale_no || ': ' || v_name || ' stays as it is, and no stock moves: '
              || case when r.supplier_id is not null
                      then coalesce((select u.name from public.suppliers u where u.id = r.supplier_id), 'a supplier') || ' sent it'
                      else 'it has no stock movement to reverse' end));
        end if;
      end loop;
    end if;

    -- Going onto the line.
    continue when v_gone;
    v_raise := case when v_swap then v_q else v_q - v_old_q end;
    if v_raise > 0 and (not public.invoice_before_full_payment(p_invoice_id)
                        or exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
                                      and (s.status <> 'cancelled'
                                           or ((s.warehouse_id is not null or s.source_store_id is not null) and not coalesce(s.stock_returned, false))
                                           or coalesce(s.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity')))) then
      if not v_preview then
        -- As create_special_docs_for_invoice raises them: one row per unit.
        for v_i in 1 .. v_raise loop
          insert into public.special_sales
            (sale_no, special_product_id, warehouse_id, customer_id, store_id, quantity,
             unit_price, total_amount, payment_method_id, notes, status, sold_by,
             invoice_id, invoice_item_id)
          values ('SPS-' || to_char(now(),'YYYY') || '-'
             || lpad(nextval('public.special_sale_no_seq')::text, 4, '0'),
             li.special_product_id, null,
             v_inv.customer_id, v_inv.store_id, 1,
             round(coalesce(li.unit_price,0), 2), round(coalesce(li.unit_price,0), 2),
             null, 'From invoice ' || v_inv.invoice_no || ', as corrected', 'pending', auth.uid(),
             p_invoice_id, li.id);
        end loop;
        perform public.write_audit_ex('invoices', p_invoice_id, 'special_docs_awaiting_fulfilment', null,
          jsonb_build_object('count', v_raise, 'invoice_no', v_inv.invoice_no, 'invoice_item_id', li.id, 'correction', true),
          'special', v_reason, v_inv.store_id);
      end if;
      v_list := v_list || jsonb_build_array(jsonb_build_object('state', 'raised',
        'what', v_raise || ' more ' || public.special_product_name(li.special_product_id)
          || case when v_raise = 1 then ' joins' else ' join' end || ' the waiting list'
          || case when v_owes then '; the invoice owes money, so take the payment before releasing it' else '' end));
    end if;
  end loop;
  return v_list;
end $function$
$d1$];

  -- Relied on, not changed (production now)
  c_relied constant text[] := array[
    'create_special_docs_for_invoice(uuid)',
    'cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])',
    'special_release_rows(uuid)',
    'trg_special_docs_follow_line_removed()',
    'invoice_before_full_payment(uuid)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'];
  c_relied_md5 constant text[] := array[
    '540b98385d9632abcc5fe35c23c00bb5',
    'fe4753fffded2cc463dbe24571a9675c',
    'de901e68cc00979dd479a1807ff43f9a',
    '25b2fac3612be3ab56151f3e109c3574',
    '532d7690367fc674737b20420e7fb16c',
    '1f034561a461bdb46a1e6274e0d04606'];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[4]);
  v_make boolean[] := array_fill(false, array[4]);
  v_acl text[] := array_fill(null::text, array[4]);
  v_add_make boolean[] := array_fill(false, array[1]);
  d text; i int;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_owner uuid; t_store uuid; t_wh uuid; t_cust uuid; t_prd uuid; t_prd2 uuid; t_sp uuid; t_sp2 uuid;
  t_inv uuid; t_item uuid; t_item2 uuid; t_item3 uuid; t_a uuid; t_b uuid; t_c uuid; t_d uuid; t_e uuid; t_got jsonb; t_seq bigint;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '497: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '497: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '497: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '497: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '497: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '497: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- The function it adds: not there yet, or as tested.
  for i in 1 .. cardinality(c_add_sig) loop
    if md5(c_add_def[i]) <> c_add_md5[i] then
      raise exception '497: the text of public.% is not the tested one (md5 %)', c_add_sig[i], md5(c_add_def[i]); end if;
    if to_regprocedure('public.' || c_add_sig[i]) is null then
      v_add_make[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))) <> c_add_md5[i] then
      raise exception '497: public.% is there already and is not this version (md5 %)', c_add_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))); end if;
  end loop;

  -- 2. Install: what they call comes first
  if not exists (select 1 from pg_constraint where conrelid = 'public.special_sale_returns'::regclass
                  and conname = 'special_sale_returns_why_check'
                  and pg_get_constraintdef(oid) like '%line corrected%') then
    alter table public.special_sale_returns drop constraint special_sale_returns_why_check;
    alter table public.special_sale_returns add constraint special_sale_returns_why_check
      check (why = any (array['refunded'::text, 'invoice cancelled'::text, 'line corrected'::text]));
  end if;
  for i in 1 .. cardinality(c_add_sig) loop
    if v_add_make[i] then
      execute c_add_def[i];
      -- Functions are not endpoints (339): internal, as the other stock helpers.
      execute format('revoke all on function public.%s from public, anon, authenticated', c_add_sig[i]);
      execute format('grant execute on function public.%s to service_role', c_add_sig[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '497: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '497: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_add_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))) <> c_add_md5[i] then
      raise exception '497: public.% was installed with an md5 other than the tested one', c_add_sig[i]; end if;
    if has_function_privilege('anon', 'public.' || c_add_sig[i], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_add_sig[i], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_add_sig[i], 'execute') then
      raise exception '497: the grants of public.% are not as written', c_add_sig[i]; end if;
  end loop;

  -- 4. Self-test, in a block that is always undone
  -- Made-up records only ("497 Check", @example.invalid, a fictional +61 2 5550 phone);
  -- the invoice and its sales are written straight to their tables with their own numbers,
  -- and raising is tried as a summary, so no sequence but the stock history's is used, and
  -- nothing is paid. It ends by raising P0497, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- A fictional phone no customer holds, in use or deleted (range scans of the two partial phone indexes, as 486's)
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '497: the self-test found no free fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '497chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '497 Check Owner', '497chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code) values ('497 Check ' || t_sfx, '497-' || t_sfx, 'SG') returning id into t_store;
    insert into public.warehouses (name, code) values ('497 Check ' || t_sfx, '497-' || t_sfx) returning id into t_wh;
    insert into public.customers (full_name, phone) values ('497 Check', '+6125550' || lpad(t_base::text, 4, '0')) returning id into t_cust;
    insert into public.products (name, sku, product_type) values ('497 Check ' || t_sfx, '497-P-' || t_sfx, 'third_party') returning id into t_prd;
    insert into public.products (name, sku, product_type) values ('497 Check Other ' || t_sfx, '497-Q-' || t_sfx, 'third_party') returning id into t_prd2;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_prd, 10);
    t_sp := public.upsert_special_product_from_product(null, t_prd, 100);
    t_sp2 := public.upsert_special_product_from_product(null, t_prd2, 100);
    insert into public.invoices (invoice_no, store_id, customer_id, created_by)
    values ('497-CHECK-' || t_sfx, t_store, t_cust, t_owner) returning id into t_inv;
    insert into public.invoice_items (invoice_id, line_kind, special_product_id, quantity, unit_price, line_total)
    values (t_inv, 'special_product', t_sp, 3, 100, 300) returning id into t_item;
    insert into public.invoice_items (invoice_id, line_kind, special_product_id, quantity, unit_price, line_total)
    values (t_inv, 'special_product', t_sp, 1, 100, 100) returning id into t_item2;
    insert into public.invoice_items (invoice_id, line_kind, special_product_id, quantity, unit_price, line_total)
    values (t_inv, 'special_product', t_sp, 1, 100, 100) returning id into t_item3;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('497-CHECK-A-' || t_sfx, t_sp, 1, 100, 100, 'pending', '497 self-test', t_inv, t_item, t_store, t_owner) returning id into t_a;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('497-CHECK-B-' || t_sfx, t_sp, 1, 100, 100, 'pending', '497 self-test', t_inv, t_item, t_store, t_owner) returning id into t_b;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('497-CHECK-C-' || t_sfx, t_sp, 1, 100, 100, 'pending', '497 self-test', t_inv, t_item, t_store, t_owner) returning id into t_c;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('497-CHECK-D-' || t_sfx, t_sp, 1, 100, 100, 'pending', '497 self-test', t_inv, t_item2, t_store, t_owner) returning id into t_d;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes, invoice_id, invoice_item_id, store_id, sold_by)
    values ('497-CHECK-E-' || t_sfx, t_sp, 1, 100, 100, 'pending', '497 self-test', t_inv, t_item3, t_store, t_owner) returning id into t_e;
    perform public.fulfil_special_doc('special_sale', t_a, t_wh, 'warehouse');
    perform public.fulfil_special_doc('special_sale', t_b, t_wh, 'warehouse');
    perform public.fulfil_special_doc('special_sale', t_d, t_wh, 'warehouse');
    if (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 7 then
      raise exception '497: three releases did not leave 7 of 10'; end if;

    -- Lowered from 3 to 2: the waiting unit comes off, and both released units stay.
    update public.invoice_items set quantity = 2 where id = t_item;
    t_got := public.invoice_special_sales_follow_lines(t_inv, jsonb_build_array(jsonb_build_object(
      'id', t_item, 'line_kind', 'special_product', 'special_product_id', t_sp, 'quantity', 3)), '497 self-test', gen_random_uuid());
    if jsonb_array_length(t_got) <> 1 or t_got->0->>'state' <> 'waiting_off'
       or (select status from public.special_sales where id = t_c) <> 'cancelled'
       or (select notes from public.special_sales where id = t_c) not like '%Cancelled (line corrected): 497 self-test%'
       or (select count(*) from public.special_sales where id in (t_a, t_b) and status = 'completed') <> 2
       or (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 7 then
      raise exception '497: a line lowered from 3 to 2 did not take its waiting unit off: %', t_got; end if;

    -- Lowered from 2 to 1: the newest released unit goes back where it left, and its sale is over.
    update public.invoice_items set quantity = 1 where id = t_item;
    t_got := public.invoice_special_sales_follow_lines(t_inv, jsonb_build_array(jsonb_build_object(
      'id', t_item, 'line_kind', 'special_product', 'special_product_id', t_sp, 'quantity', 2)), '497 self-test', gen_random_uuid());
    if jsonb_array_length(t_got) <> 1 or t_got->0->>'state' <> 'back'
       or t_got->0->>'sale_no' <> '497-CHECK-B-' || t_sfx
       or (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 8
       or (select status from public.special_sales where id = t_b) <> 'cancelled'
       or not (select coalesce(stock_returned, false) from public.special_sales where id = t_b)
       or (select status from public.special_sales where id = t_a) <> 'completed'
       or not exists (select 1 from public.special_sale_returns r join public.stock_movements m on m.id = r.return_movement_id
                       where r.special_sale_id = t_b and r.why = 'line corrected' and r.sellable_quantity = 1
                         and m.movement_type::text = 'invoice_cancel_return' and m.to_warehouse_id = t_wh and m.quantity = 1) then
      raise exception '497: a line lowered from 2 to 1 did not put its newest released unit back: %', t_got; end if;

    -- The same quantity again changes nothing.
    t_got := public.invoice_special_sales_follow_lines(t_inv, jsonb_build_array(jsonb_build_object(
      'id', t_item, 'line_kind', 'special_product', 'special_product_id', t_sp, 'quantity', 1)), '497 self-test', gen_random_uuid());
    if t_got <> '[]'::jsonb then raise exception '497: a line that did not change did something: %', t_got; end if;

    -- A line removed: its released unit goes back; a waiting one was cancelled as the line went.
    delete from public.invoice_items where id in (t_item2, t_item3);
    t_got := public.invoice_special_sales_follow_lines(t_inv, jsonb_build_array(
      jsonb_build_object('id', t_item2, 'line_kind', 'special_product', 'special_product_id', t_sp, 'quantity', 1),
      jsonb_build_object('id', t_item3, 'line_kind', 'special_product', 'special_product_id', t_sp, 'quantity', 1)), '497 self-test', gen_random_uuid());
    if jsonb_array_length(t_got) <> 2
       or (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 9
       or (select status from public.special_sales where id = t_d) <> 'cancelled'
       or (select status from public.special_sales where id = t_e) <> 'cancelled'
       or (select count(*) from jsonb_array_elements(t_got) e where e->>'state' in ('back', 'waiting_off')) <> 2 then
      raise exception '497: removed lines did not take their sales with them: %', t_got; end if;

    -- A summary says what would join the waiting list, and raises nothing: another machine on the line.
    perform set_config('invoice.correction_preview', 'on', true);
    t_seq := (select count(*) from public.special_sales where invoice_id = t_inv);
    update public.invoice_items set special_product_id = t_sp2 where id = t_item;
    t_got := public.invoice_special_sales_follow_lines(t_inv, jsonb_build_array(jsonb_build_object(
      'id', t_item, 'line_kind', 'special_product', 'special_product_id', t_sp, 'quantity', 1)), '497 self-test', gen_random_uuid());
    perform set_config('invoice.correction_preview', '', true);
    if (select count(*) from public.special_sales where invoice_id = t_inv) <> t_seq
       or (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prd) <> 10
       or (select count(*) from jsonb_array_elements(t_got) e where e->>'state' = 'raised') <> 1
       or (select count(*) from jsonb_array_elements(t_got) e where e->>'state' = 'back') <> 1 then
      raise exception '497: another machine on a line did not do as it should: %', t_got; end if;

    -- It is internal: a signed-in user cannot call it.
    if has_function_privilege('authenticated', 'public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)', 'execute') then
      raise exception '497: a signed-in user can call the new function'; end if;

    raise exception using errcode = 'P0497', message = '497: self-test done, undone';
  exception when sqlstate 'P0497' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
