-- 363_a_promotion_refund_closes_its_therapy.sql
--
-- THE GAP
--
--   A promotion that includes a therapy package grants purchased therapy units
--   (invoice_therapy_entitlements_due: promotion_items.therapy_package_id and
--   invoice_promotion_selections), each linked to the PROMOTION line and priced
--   at 0. refund_invoice_recorded closes units only for line_kind = 'therapy';
--   for a promotion line it moves stock and nothing else. So a refunded
--   promotion leaves its therapy with the customer, unused and claimable.
--   All 12 purchased units in production came from promotion lines.
--   (INV-2026-0160 / UTP-0000006 is the one case so far; it was refunded by the
--   pre-guided path, which no longer exists. See PROMOTION_THERAPY_REFUNDS.md
--   for the proposed repair, which this migration does not do.)
--
-- THE RULE, AS ALREADY SET FOR THERAPY SOLD ON ITS OWN LINE (296, 359)
--
--   * Unused units are refunded with their line. No override.
--   * A unit that has been used (therapy started or ended, or vouchers
--     collected: therapy_unit_consumed, 359) ends only on an Owner or Manager's
--     'therapy_activated' override with a reason and an amount. Its history is
--     kept and vouchers not yet collected are withdrawn (the 314 trigger).
--
-- WHAT THIS DOES
--
--   1. close_invoice_therapy_units: closes units by that rule, all or none: if
--      one used unit lacks the override, nothing closes. It locks the units and
--      their voucher allowances before it looks, so a unit started or a voucher
--      collected at the same moment is seen. It serves a line, or the units no
--      line holds (a correction deleted their line).
--   2. invoice_action_plan lists the units each line closes, raises
--      'therapy_activated' with an amount when any of them has been used, says
--      so in the summary, and returns them as effects.therapy_closed. The units
--      are part of the line, so the plan hash covers them.
--      - A cancellation, a full refund, or any refund that takes what is left
--        of the line: all of its units. A part refund of N of M copies: its
--        share, ceil(units the line granted x N / M), unused first.
--      - Units no line holds: on a cancellation, a full refund, or a part
--        refund that pays back all that is left of the invoice, the unused ones
--        close; one that has been used is left running, as before, and the
--        plan says so (effects.therapy_left).
--      - A promotion's goods are listed by 361 (a_promotion_refund_lists_its_
--        stock). Stock is now one entry per movement: a product line and a
--        promotion that draw on one movement produced two entries, and the
--        screen confirms one row per movement, so the second was lost.
--      - A therapy override's default amount is its line's figure after the
--        money cap, so the pre-filled amount is one that can be taken.
--   3. resolve_invoice_action_v2 closes exactly the units the reviewed plan
--      lists, before any money moves, and tells the refund engine so, which
--      then closes nothing of its own on those lines. An override may name its
--      line (invoice_item_id), so two lines needing the same override each get
--      their own reason and amount; one that names no line serves every line
--      with its code, as before. The therapy override reaches only a line whose
--      review asked for it. An amount that pays back all of a line whose plan
--      ends only part of its therapy is refused. A therapy line stating 0 is no
--      longer sent to the engine, which refuses a zero line: its therapy ends
--      here on that override. On a cancellation it also ends started therapy sold on
--      its own line under the override the approver gave; until now that
--      override was asked for and then ignored unless the refund was recorded
--      at the same time, leaving the therapy running on a cancelled invoice.
--   4. refund_invoice_recorded (the Finance panel calls it directly): a
--      promotion line refunded IN FULL closes its units; used ones need the
--      override, which the Finance panel never sends, so it refuses and points
--      to Refund / Cancel. A part refund by amount leaves the units alone.
--      When the refund closes the whole invoice, unused units no line holds
--      close, as a cancellation already closes them. It locks every therapy
--      unit on the invoice (and its voucher allowance) before it touches
--      benefits or voucher stock, in the order the Claim window takes them.
--   5. cancel_invoice_recorded (also called directly): no longer closes a unit
--      whose vouchers were collected as if unused (359 says it is used), and
--      refuses while used therapy on a line is still open, pointing to
--      Refund / Cancel, instead of cancelling around therapy that keeps
--      running. This applies to therapy sold on its own line too.
--
-- OWNER DECISIONS THIS ENCODES (recommended defaults; see the report)
--
--   A. A part refund by amount (Finance panel) keeps the therapy.
--   B. A part refund of N of M copies closes ceil(units x N / M), unused first.
--   C. A direct cancellation refuses while therapy on a line has been used.
--
-- NOT CHANGED
--
--   * Therapy sold on its own line: refund rules as 296 and 359. Its
--     cancellation now ends started therapy on the override (3), and a direct
--     cancellation of it is refused while it has been used (C).
--   * A line with nothing left to refund (a free line) is not refunded, so its
--     therapy is not touched by a refund; a cancellation closes it as before.
--   * No valuation for therapy inside a promotion is invented: unused units
--     are closed at no separate price (they were sold at 0), used ones take the
--     amount the Owner or Manager states for the whole line.
--   * Commission follows the money (reconcile_invoice_commissions), as for any
--     promotion refund.
--   * Existing data. INV-2026-0160 / UTP-0000006 and the orphan UTP-0000002 on
--     INV-2026-0086 are left for the owner-approved repair.
--
-- SAFETY
--
-- Needs 359 and 361 (invoice_action_plan is patched on top of 361's version).
-- Every patched function is guarded by the md5 of the production version it
-- was tested against (26 Sep 2026) and by anchors that must each occur exactly
-- once. A function already carrying this migration's own mark is left alone;
-- the four must be all unpatched or all patched, never a mix.

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run it as one: psql -1 -v ON_ERROR_STOP=1 -f <this file>.
set lock_timeout = '5s';

do $mig$
declare v_state text;
begin
  if to_regprocedure('public.therapy_unit_consumed(uuid)') is null
     or to_regprocedure('public.revoke_therapy_unit_benefit(uuid,text)') is null then
    raise exception '363: apply 359 first'; end if;
  if to_regprocedure('public.invoice_line_stock_products(uuid)') is null then
    raise exception '363: apply 361 (a_promotion_refund_lists_its_stock) first'; end if;
  -- Each function: 'mine' (already patched by this file), 'base' (the tested
  -- production version) or anything else. All four must agree.
  select string_agg(f.name||'='||case
           when position(f.mark in pg_get_functiondef(f.sig::regprocedure)) > 0 then 'mine'
           when md5(pg_get_functiondef(f.sig::regprocedure)) = f.base then 'base'
           else 'other' end, ' ' order by f.name)
    into v_state
    from (values
      ('invoice_action_plan','public.invoice_action_plan(uuid,text,jsonb)','v363_units','1c8fa5626062d09ba0cc1a4dca9d0e93'),
      ('resolve_invoice_action_v2','public.resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)','v363_ov','67e3cc6b44eb8d259d92ae5e27a304ee'),
      ('refund_invoice_recorded','public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)','v363_marker','7dd62acaef1c995cc5e12effff6640fb'),
      ('cancel_invoice_recorded','public.cancel_invoice_recorded(uuid,text,uuid)','v363_used','c84a8a4f259cfc2c52ab92f80cac5e17')) f(name,sig,mark,base);
  if v_state not in ('cancel_invoice_recorded=base invoice_action_plan=base refund_invoice_recorded=base resolve_invoice_action_v2=base',
                     'cancel_invoice_recorded=mine invoice_action_plan=mine refund_invoice_recorded=mine resolve_invoice_action_v2=mine') then
    raise exception '363: the functions it patches are not all at the tested version, or already patched by it: %', v_state; end if;
end $mig$;

-- ── 1. close therapy units ──────────────────────────────────────────────────
create or replace function public.close_invoice_therapy_units(
  p_invoice_id uuid,
  p_invoice_item_id uuid,
  p_unit_ids uuid[],
  p_override jsonb,
  p_amount numeric,
  p_reason text,
  p_request_id uuid,
  p_context text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
-- 363: the units of one line of the invoice, or (p_invoice_item_id null) the
-- units no line holds. p_unit_ids null = every open one. p_override is the
-- Owner or Manager's 'therapy_activated' override; p_amount what the line
-- refunds under it (recorded with the termination). Closed units are skipped.
declare e public.purchased_therapy_entitlements%rowtype; v_store uuid; v_used text;
        v_refunded jsonb := '[]'; v_ended jsonb := '[]';
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can close therapy with its invoice line'; end if;
  select store_id into v_store from public.invoices where id = p_invoice_id;
  if not found or not public.user_has_store_access(v_store) then
    raise exception 'Invoice not accessible'; end if;
  if p_invoice_item_id is not null and not exists (select 1 from public.invoice_items
                                                    where id = p_invoice_item_id and invoice_id = p_invoice_id) then
    raise exception 'Invoice line not found'; end if;
  if exists (select 1 from unnest(coalesce(p_unit_ids, '{}'::uuid[])) u
              where not exists (select 1 from public.purchased_therapy_entitlements x
                                 where x.id = u and x.invoice_id = p_invoice_id
                                   and x.invoice_item_id is not distinct from p_invoice_item_id)) then
    raise exception 'A therapy unit to close does not belong to this invoice line'; end if;

  -- Lock the units and their voucher allowances first, so nothing is started
  -- and no voucher is collected between the check and the close.
  perform 1 from public.purchased_therapy_entitlements x
    where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
      and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded')
    order by x.id for update;
  perform 1 from public.therapy_entitlements te
    where te.id in (select x.voucher_entitlement_id from public.purchased_therapy_entitlements x
                     where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
                       and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded'))
    order by te.id for update;

  select string_agg(x.entitlement_no, ', ' order by x.entitlement_no) into v_used
    from public.purchased_therapy_entitlements x
   where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
     and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded')
     and public.therapy_unit_consumed(x.id);
  if v_used is not null then
    if coalesce(p_override->>'code','') <> 'therapy_activated'
       or nullif(trim(coalesce(p_override->>'reason','')),'') is null then
      raise exception 'Therapy from this line has been started or has ended, or vouchers from it were collected (%). It ends only on an Owner or Manager''s authorization with an amount: use Refund / Cancel on the invoice.', v_used; end if;
    if (p_override->>'amount') is null or (p_override->>'amount')::numeric < 0 then
      raise exception 'No valuation exists for therapy that has been used (%). An Owner or Manager must state the refund amount with a reason.', v_used; end if;
  end if;

  for e in select * from public.purchased_therapy_entitlements x
            where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
              and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded')
            order by x.unit_index nulls last, x.entitlement_no
  loop
    if public.therapy_unit_consumed(e.id) then
      update public.purchased_therapy_entitlements
         set status = 'refunded', updated_by = auth.uid(), updated_at = now() where id = e.id;
      perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'authorized_termination',
        jsonb_build_object('status', e.status, 'activation_date', e.activation_date,
          'expiry_date', e.expiry_date, 'benefit_choice', e.benefit_choice),
        jsonb_build_object('status', 'refunded', 'override', p_override, 'request_id', p_request_id,
          'amount', p_amount, 'invoice_item_id', p_invoice_item_id, 'context', p_context),
        'refunds', p_reason, v_store);
      v_ended := v_ended || to_jsonb(e.entitlement_no);
    else
      update public.purchased_therapy_entitlements
         set status = 'refunded', updated_by = auth.uid(), updated_at = now() where id = e.id;
      perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'closed_with_invoice_line',
        jsonb_build_object('status', e.status, 'benefit_choice', e.benefit_choice),
        jsonb_build_object('status', 'refunded', 'request_id', p_request_id,
          'invoice_item_id', p_invoice_item_id, 'context', p_context),
        'refunds', p_reason, v_store);
      v_refunded := v_refunded || to_jsonb(e.entitlement_no);
    end if;
  end loop;
  return jsonb_build_object('refunded', v_refunded, 'terminated', v_ended);
end $function$;

-- Not an endpoint (339). Here, not at the end, so a run that stops partway
-- never leaves it callable.
revoke all on function public.close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text) from public, anon, authenticated;
grant execute on function public.close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text) to service_role;

-- ── 2. the plan lists them ──────────────────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.invoice_action_plan(uuid,text,jsonb)'::regprocedure);
  if position('v363_units' in d) > 0 then raise notice '363: invoice_action_plan already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '1c8fa5626062d09ba0cc1a4dca9d0e93' then
    raise exception '363: invoice_action_plan is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$ v_new_sel jsonb; v_cap numeric; v_one numeric; v_removed numeric;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan declare anchor found % times', n; end if;
  d := replace(d, a, a || $r$
 v363_units jsonb; v363_used text; v363_granted int;
 v363_detached jsonb; v363_bb boolean;$r$);

  -- 361's promotion branch skips a movement an earlier line already listed, so
  -- with a product line read first the promotion's goods went unlisted. Every
  -- line now offers its share; the merge pass below adds them up and caps the
  -- sum at what is outstanding, whatever order the lines come in.
  a := $a$       or not ((s->>'product_id')::uuid in (select public.invoice_line_stock_products(it.id)))
       or v_stock @> jsonb_build_array(jsonb_build_object('movement_id', s->>'movement_id'));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan 361 skip anchor found % times', n; end if;
  d := replace(d, a, $r$       or not ((s->>'product_id')::uuid in (select public.invoice_line_stock_products(it.id)));
     -- 363: a movement another line listed is offered again for this line's
     -- share; the merge before the money section adds and caps them.$r$);

  -- (b) the therapy units of a line
  a := $a$  if it.therapy_service_id is not null then$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan units anchor found % times', n; end if;
  d := replace(d, a, $r$  -- 363: therapy a promotion (or bundle) granted closes with its line: all of
  -- it for a cancellation, a full refund, or a refund taking what is left of
  -- the line (the refund engine's own "in full"); otherwise its share of the
  -- units the line granted, units not yet used first. A used unit needs the
  -- same override as therapy sold on its own line.
  v363_units:=null; v363_used:=null;
  if it.line_kind::text<>'therapy' then
   select count(*) into v363_granted from public.purchased_therapy_entitlements where invoice_item_id=it.id;
   select jsonb_agg(jsonb_build_object('id',q.id,'entitlement_no',q.entitlement_no,'package',q.package_name,
            'status',q.status,'benefit',q.benefit_choice,'used',q.used,'activation_date',q.activation_date) order by q.rn),
          string_agg(case when q.used then q.entitlement_no end,', ' order by q.rn)
     into v363_units, v363_used
     from (select e.id, e.entitlement_no, e.package_name, e.status, e.benefit_choice, e.activation_date,
                  public.therapy_unit_consumed(e.id) used,
                  row_number() over (order by public.therapy_unit_consumed(e.id), e.unit_index nulls last, e.entitlement_no) rn,
                  count(*) over () cnt
             from public.purchased_therapy_entitlements e
            where e.invoice_item_id=it.id and e.status not in ('cancelled','refunded')) q
    where q.rn<=case when v_qty>=v_full_qty or v_amount>=v_line_rem then q.cnt
                     else ceil(v363_granted*v_qty::numeric/v_full_qty) end;
   if v363_used is not null then
    -- A line whose refund is fixed by its unused vouchers or credit takes no
    -- amount of its own: the refund engine accepts only that figure.
    v363_bb:=v_has_ben or it.line_kind::text in ('credit_package','premium_bundle');
    v_codes:=v_codes||jsonb_build_array('therapy_activated');
    v_over:=v_over||jsonb_build_array(jsonb_build_object('code','therapy_activated','amount_required',not v363_bb,
     'invoice_item_id',it.id,'default_amount',v_amount,
     'message','Therapy from '||coalesce(x->>'name','this promotion')||' has been started or has ended, or vouchers from it have already been collected ('||v363_used||'). Ending it keeps that history and withdraws any vouchers not yet collected. '||
       case when v363_bb
         then 'The refund for this line is the value of its unused vouchers or credit, as shown above; an Owner or Manager must give a reason.'
         else 'Therapy inside a promotion has no price of its own, so an Owner or Manager must state the refund amount for this line with a reason.' end));
   end if;
  end if;
$r$ || a);

  a := $a$   'benefit_backed',coalesce((select sum((q->>'amount')::numeric) from jsonb_array_elements(v_ben) q),0)));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan line anchor found % times', n; end if;
  d := replace(d, a, $r$   'benefit_backed',coalesce((select sum((q->>'amount')::numeric) from jsonb_array_elements(v_ben) q),0))
   -- 363: only lines that close therapy carry the key, so other plans hash as before
   ||case when v363_units is not null then jsonb_build_object('therapy_units',v363_units) else '{}'::jsonb end);$r$);

  -- (c) one stock entry per movement; units no line holds
  a := $a$ -- ---- money that can actually go back ------------------------------------$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan money anchor found % times', n; end if;
  d := replace(d, a, $r$ -- 363: one stock entry per movement. A product line and a promotion (or two
 -- lines of one product) can draw on the same movement, and the screen
 -- confirms one row per movement, so a second row for it was lost.
 select coalesce(jsonb_agg(m.e order by m.first),'[]'::jsonb) into v_stock
   from (select min(t.ord) first,
                (array_agg(t.k order by t.ord))[1]
                  ||jsonb_build_object('proposed_sellable',
                      least(sum((t.k->>'proposed_sellable')::int),max((t.k->>'outstanding')::int))) e
           from jsonb_array_elements(v_stock) with ordinality t(k,ord)
          group by t.k->>'movement_id') m;

$r$ || a);

  a := $a$ for x in select * from jsonb_array_elements(v_over) loop$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan summary anchor found % times', n; end if;
  d := replace(d, a, $r$ -- 363: a therapy override's default amount is its line's figure after the
 -- money cap, so the pre-filled amount is one that can be taken.
 v_over:=(select coalesce(jsonb_agg(case when t.ov->>'code'='therapy_activated' and t.ov ? 'invoice_item_id'
            then jsonb_set(t.ov,'{default_amount}',coalesce((select l->'amount' from jsonb_array_elements(v_sel) l
                   where l->>'invoice_item_id'=t.ov->>'invoice_item_id' limit 1),t.ov->'default_amount'))
            else t.ov end order by t.n),'[]'::jsonb)
          from jsonb_array_elements(v_over) with ordinality t(ov,n));
 -- 363: therapy no line holds (a correction deleted its line). An action that
 -- closes the invoice (a cancellation, a full refund, or a part refund that
 -- pays back all that is left) closes the unused ones; a used one is left.
 v363_detached:=null;
 if p_action in ('cancel','refund_full')
    or (p_action='refund_partial' and public.invoice_charge_total(i.id)-v_total<=0) then
  select jsonb_agg(jsonb_build_object('id',e.id,'entitlement_no',e.entitlement_no,'package',e.package_name,
           'status',e.status,'benefit',e.benefit_choice,'used',public.therapy_unit_consumed(e.id)) order by e.entitlement_no)
    into v363_detached
    from public.purchased_therapy_entitlements e
   where e.invoice_id=i.id and e.invoice_item_id is null and e.status not in ('cancelled','refunded');
 end if;
 -- 363: each therapy unit the action closes, by name.
 for x in select * from jsonb_array_elements(v_sel) loop
  for b in select * from jsonb_array_elements(coalesce(x->'therapy_units','[]')) loop
   v_sum:=v_sum||jsonb_build_array(case when (b->>'used')::boolean
     then 'End therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||') from '||(x->>'name')||': it has been used, so only on the override below.'
     else 'Close therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||') from '||(x->>'name')||': not used yet'||
          case when b->>'benefit'='voucher' then '; vouchers not yet collected are withdrawn' else '' end||'.' end);
  end loop;
 end loop;
 for b in select * from jsonb_array_elements(coalesce(v363_detached,'[]')) loop
  v_sum:=v_sum||jsonb_build_array(case when (b->>'used')::boolean
    then 'Therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||') is on no invoice line (a correction removed its line) and has been used, so it is left running.'
    else 'Close therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||'), which is on no invoice line: not used yet.' end);
 end loop;
$r$ || a);

  a := $a$    'stock_returned',v_stock,$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan effects anchor found % times', n; end if;
  d := replace(d, a, $r$    -- 363: therapy units this action closes
    'therapy_closed',(select coalesce(jsonb_agg(q.t order by q.o),'[]'::jsonb) from (
        select 1 o, jsonb_build_object('entitlement_no',tu->>'entitlement_no','package',tu->>'package',
                 'used',(tu->>'used')::boolean,'benefit',tu->>'benefit','line',ll->>'name') t
          from jsonb_array_elements(v_sel) ll,
               jsonb_array_elements(coalesce(ll->'therapy_units','[]'::jsonb)) tu
        union all
        select 2, jsonb_build_object('entitlement_no',du->>'entitlement_no','package',du->>'package',
                 'used',false,'benefit',du->>'benefit','line','no invoice line')
          from jsonb_array_elements(coalesce(v363_detached,'[]'::jsonb)) du
         where not (du->>'used')::boolean) q),
    -- 363: used therapy no line holds, which this action leaves running
    'therapy_left',(select coalesce(jsonb_agg(jsonb_build_object('entitlement_no',du->>'entitlement_no',
          'package',du->>'package','line','no invoice line') order by du->>'entitlement_no'),'[]'::jsonb)
        from jsonb_array_elements(coalesce(v363_detached,'[]'::jsonb)) du where (du->>'used')::boolean),
$r$ || a);

  a := $a$  'overrides_required',v_over,'blockers',v_block,'summary',v_sum,$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan result anchor found % times', n; end if;
  d := replace(d, a, a || $r$
  'detached_therapy',coalesce(v363_detached,'[]'::jsonb),$r$);

  a := $a$  'plan_hash',md5(jsonb_build_object('a',p_action,'t',v_total,'d',v_due,'l',v_sel,'s',v_src,'k',v_stock,'o',v_over)::text));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: invoice_action_plan hash anchor found % times', n; end if;
  d := replace(d, a, $r$  -- 363: units no line holds are hashed only when there are any
  'plan_hash',md5((jsonb_build_object('a',p_action,'t',v_total,'d',v_due,'l',v_sel,'s',v_src,'k',v_stock,'o',v_over)
    ||case when v363_detached is not null then jsonb_build_object('u',v363_detached) else '{}'::jsonb end)::text));$r$);
  execute d;
end $mig$;

-- ── 3. the guided flow closes what was reviewed ─────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)'::regprocedure);
  if position('v363_ov' in d) > 0 then raise notice '363: resolve_invoice_action_v2 already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '67e3cc6b44eb8d259d92ae5e27a304ee' then
    raise exception '363: resolve_invoice_action_v2 is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$ v_exec numeric; v_planned numeric; v_alloc numeric; v_assigned numeric; v_n int; v_idx int;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: resolve_invoice_action_v2 declare anchor found % times', n; end if;
  d := replace(d, a, a || $r$
 v363_ov jsonb; v363_amt numeric;$r$);

  -- (a) an override that names its line counts for that line only
  a := $a$  select q into ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'=x->>'code' and nullif(trim(coalesce(q->>'reason','')),'') is not null limit 1;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: resolve_invoice_action_v2 missing anchor found % times', n; end if;
  d := replace(d, a, $r$  -- 363: an override may name its line (invoice_item_id), so two lines needing
  -- the same override each get their own reason and amount. One that names no
  -- line serves every line with its code, as before.
  select q into ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'=x->>'code' and nullif(trim(coalesce(q->>'reason','')),'') is not null
     and (nullif(q->>'invoice_item_id','') is null or x->>'invoice_item_id' is null
          or q->>'invoice_item_id'=x->>'invoice_item_id')
   order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc,
            ((q->>'amount') is not null)=coalesce((x->>'amount_required')::boolean,false) desc limit 1;$r$);

  -- (b) the refund payload: per-line overrides; a therapy line stating 0 is not sent
  a := $a$          coalesce((select round((q->>'amount')::numeric,2) from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                     where (q->>'amount') is not null
                       and coalesce(l->'override_codes','[]') ? (q->>'code') limit 1),
                   (l->>'amount')::numeric),
          'benefits',coalesce(l->'benefits','[]'),
          'override',(select q from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                       where coalesce(l->'override_codes','[]') ? (q->>'code') limit 1))),'[]')
   into v_lines from jsonb_array_elements(v_plan->'lines') l
  where (l->>'amount')::numeric>0
     or exists(select 1 from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                where (q->>'amount') is not null and coalesce(l->'override_codes','[]') ? (q->>'code'));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: resolve_invoice_action_v2 lines anchor found % times', n; end if;
  d := replace(d, a, $r$          -- 363: an override naming this line first, then one by code alone
          coalesce((select round((q->>'amount')::numeric,2) from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                     where (q->>'amount') is not null
                       and coalesce(l->'override_codes','[]') ? (q->>'code')
                       and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                       -- an amount naming no line never lands on a line whose
                       -- refund is fixed by its vouchers or credit
                       and (q->>'invoice_item_id'=l->>'invoice_item_id'
                            or not exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                                           where po->>'code'=q->>'code' and po->>'invoice_item_id'=l->>'invoice_item_id'
                                             and not coalesce((po->>'amount_required')::boolean,true)))
                     order by (q->>'invoice_item_id' is not distinct from l->>'invoice_item_id') desc limit 1),
                   (l->>'amount')::numeric),
          'benefits',coalesce(l->'benefits','[]'),
          'override',(select q from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                       where coalesce(l->'override_codes','[]') ? (q->>'code')
                         and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                       order by (q->>'invoice_item_id' is not distinct from l->>'invoice_item_id') desc,
                                ((q->>'amount') is not null) desc limit 1))),'[]')
   into v_lines from jsonb_array_elements(v_plan->'lines') l
  where ((l->>'amount')::numeric>0
     or exists(select 1 from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                where (q->>'amount') is not null and coalesce(l->'override_codes','[]') ? (q->>'code')
                  and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                  and (q->>'invoice_item_id'=l->>'invoice_item_id'
                            or not exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                                           where po->>'code'=q->>'code' and po->>'invoice_item_id'=l->>'invoice_item_id'
                                             and not coalesce((po->>'amount_required')::boolean,true)))))
    -- 363: a line whose used therapy is ended with 0 stated refunds nothing, and
    -- the engine refuses a zero line; its therapy is ended below instead.
    and not (coalesce(l->'override_codes','[]') ? 'therapy_activated'
             and coalesce((select round((q->>'amount')::numeric,2) from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                            where (q->>'amount') is not null and coalesce(l->'override_codes','[]') ? (q->>'code')
                              and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                              and (q->>'invoice_item_id'=l->>'invoice_item_id'
                            or not exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                                           where po->>'code'=q->>'code' and po->>'invoice_item_id'=l->>'invoice_item_id'
                                             and not coalesce((po->>'amount_required')::boolean,true)))
                            order by (q->>'invoice_item_id' is not distinct from l->>'invoice_item_id') desc limit 1),
                          (l->>'amount')::numeric)<=0);$r$);

  -- (c) close what the plan listed, before any money moves
  a := $a$ if v_action='cancel' then$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: resolve_invoice_action_v2 close anchor found % times', n; end if;
  d := replace(d, a, $r$ -- 363: therapy the reviewed plan closes goes first, exactly as reviewed
 -- (the plan hash covers it), and the refund engine is told so, so it closes
 -- nothing of its own on these lines. The override reaches only a line whose
 -- review asked for it; the amount stated with it is recorded.
 perform set_config('invoice.therapy_reviewed',r.id::text,true);
 for x in select * from jsonb_array_elements(v_plan->'lines') loop
  continue when jsonb_typeof(x->'therapy_units') is distinct from 'array';
  v363_ov:=null;
  if coalesce(x->'override_codes','[]'::jsonb) ? 'therapy_activated' then
   select q into v363_ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
    where q->>'code'='therapy_activated'
      and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=x->>'invoice_item_id')
    order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc, ((q->>'amount') is not null) desc limit 1;
  end if;
  -- what this line refunds: the amount stated for it, else the reviewed figure
  v363_amt:=coalesce((select (l->>'amount')::numeric from jsonb_array_elements(v_lines) l
                       where l->>'invoice_item_id'=x->>'invoice_item_id' limit 1),0);
  -- An amount that pays back all of the line must not leave part of its
  -- therapy open: the review has to have listed all of it.
  if coalesce((x->>'remaining_value')::numeric,0)>0 and v363_amt>=(x->>'remaining_value')::numeric
     and exists(select 1 from public.purchased_therapy_entitlements e
                 where e.invoice_item_id=(x->>'invoice_item_id')::uuid and e.status not in ('cancelled','refunded')
                   and e.id::text not in (select u->>'id' from jsonb_array_elements(x->'therapy_units') u)) then
   raise exception 'The amount stated pays back all of %, but the reviewed plan ends only part of its therapy. Refund it with Full refund, or state a smaller amount.', x->>'name'; end if;
  -- A line whose refund is fixed by its vouchers or credit states no amount
  -- (whatever an override naming no line says); the termination records the
  -- line's own figure.
  if v363_ov is not null and ((v363_ov->>'amount') is null
     or exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                where po->>'code'='therapy_activated' and po->>'invoice_item_id'=x->>'invoice_item_id'
                  and not coalesce((po->>'amount_required')::boolean,true))) then
   v363_ov:=v363_ov||jsonb_build_object('amount',v363_amt); end if;
  perform public.close_invoice_therapy_units(i.id,(x->>'invoice_item_id')::uuid,
    array(select (u->>'id')::uuid from jsonb_array_elements(x->'therapy_units') u),
    v363_ov,coalesce(round((v363_ov->>'amount')::numeric,2),v363_amt),coalesce(p_note,r.reason),r.id,v_action);
 end loop;
 -- Unused therapy no line holds, as listed; a used one is left running.
 if jsonb_typeof(v_plan->'detached_therapy')='array'
    and exists(select 1 from jsonb_array_elements(v_plan->'detached_therapy') du where not (du->>'used')::boolean) then
  perform public.close_invoice_therapy_units(i.id,null,
    array(select (du->>'id')::uuid from jsonb_array_elements(v_plan->'detached_therapy') du where not (du->>'used')::boolean),
    null,0,coalesce(p_note,r.reason),r.id,v_action);
 end if;
 -- Started therapy sold on its own line whose line refunds nothing (0 stated)
 -- is not sent to the refund engine, so it ends here on its override.
 for x in select * from jsonb_array_elements(v_plan->'lines') loop
  continue when x->>'line_kind'<>'therapy' or not coalesce(x->'override_codes','[]'::jsonb) ? 'therapy_activated'
             or exists(select 1 from jsonb_array_elements(v_lines) l where l->>'invoice_item_id'=x->>'invoice_item_id');
  select q into v363_ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'='therapy_activated'
     and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=x->>'invoice_item_id')
   order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc, ((q->>'amount') is not null) desc limit 1;
  perform public.close_invoice_therapy_units(i.id,(x->>'invoice_item_id')::uuid,null,v363_ov,0,
    coalesce(p_note,r.reason),r.id,v_action);
 end loop;

$r$ || a);

  -- (d) a cancellation ends started therapy sold on its own line
  a := $a$  v_cancel:=public.cancel_invoice_recorded(i.id,coalesce(p_note,r.reason),r.id);$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: resolve_invoice_action_v2 cancel anchor found % times', n; end if;
  d := replace(d, a, $r$  -- 363: started therapy sold on its own line ends with the cancellation, on
  -- the override the approver gave. A refund recorded above has already ended
  -- it; otherwise the override was asked for and the therapy kept running.
  for x in select * from jsonb_array_elements(v_plan->'lines') loop
   continue when x->>'line_kind'<>'therapy' or not coalesce(x->'override_codes','[]'::jsonb) ? 'therapy_activated';
   select q into v363_ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
    where q->>'code'='therapy_activated'
      and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=x->>'invoice_item_id')
    order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc, ((q->>'amount') is not null) desc limit 1;
   perform public.close_invoice_therapy_units(i.id,(x->>'invoice_item_id')::uuid,null,v363_ov,
     round((v363_ov->>'amount')::numeric,2),coalesce(p_note,r.reason),r.id,'cancel');
  end loop;
$r$ || a);
  execute d;
end $mig$;

-- ── 4. the refund engine: a whole promotion line takes its therapy ──────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure);
  if position('v363_marker' in d) > 0 then raise notice '363: refund_invoice_recorded already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '7dd62acaef1c995cc5e12effff6640fb' then
    raise exception '363: refund_invoice_recorded is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$ if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: refund_invoice_recorded lock anchor found % times', n; end if;
  d := replace(d, a, a || $r$
 -- 363 (v363_marker): every therapy unit on the invoice and its voucher
 -- allowance are locked before any benefit or voucher stock is touched, in the
 -- order the Claim window takes them (unit, allowance, stock), so the two
 -- cannot wait on each other.
 perform 1 from public.purchased_therapy_entitlements
   where invoice_id=i.id and status not in ('cancelled','refunded') order by id for update;
 perform 1 from public.therapy_entitlements te
   where te.id in (select voucher_entitlement_id from public.purchased_therapy_entitlements
                    where invoice_id=i.id and status not in ('cancelled','refunded'))
   order by te.id for update;$r$);

  a := $a$   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: refund_invoice_recorded line anchor found % times', n; end if;
  d := replace(d, a, $r$   -- 363: a promotion (or bundle) line refunded in full closes the therapy it
   -- granted; used units only on the 'therapy_activated' override, for the
   -- amount refunded on this line. A part refund by amount leaves it. The
   -- guided flow has already closed exactly what its reviewed plan listed.
   if it.id is not null and it.line_kind::text<>'therapy'
      and coalesce(current_setting('invoice.therapy_reviewed',true),'') is distinct from p_request_id::text
      and not coalesce((x->>'overpayment')::boolean,false)
      and v_amount>=greatest(v_line_paid-v_refunded,0)
      and exists(select 1 from public.purchased_therapy_entitlements
                  where invoice_item_id=it.id and status not in ('cancelled','refunded')) then
     if coalesce(x->'override'->>'code','')='therapy_activated'
        and (x->'override'->>'amount') is not null
        and round((x->'override'->>'amount')::numeric,2)<>v_amount
        and exists(select 1 from public.purchased_therapy_entitlements
                    where invoice_item_id=it.id and status not in ('cancelled','refunded') and public.therapy_unit_consumed(id)) then
       raise exception 'The authorized termination amount must match the refund allocated to this line'; end if;
     perform public.close_invoice_therapy_units(i.id,it.id,null,x->'override',v_amount,p_reason,p_request_id,'refund');
   end if;
$r$ || a);

  a := $a$   perform public.writeoff_released_credit_on_close(i.id, p_reason, 'refund');$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: refund_invoice_recorded close anchor found % times', n; end if;
  d := replace(d, a, a || $r$
   -- 363: unused therapy no line holds (a correction deleted its line) closes
   -- with a fully refunded invoice, as a cancellation closes it, on every path
   -- (the guided flow has usually closed it already, as its plan listed).
   -- Units still on a line follow their line. Locked first, then checked.
   if true then
     perform 1 from public.purchased_therapy_entitlements
       where invoice_id=i.id and invoice_item_id is null and status in ('pending_activation','scheduled')
       order by id for update;
     perform 1 from public.therapy_entitlements te
       where te.id in (select voucher_entitlement_id from public.purchased_therapy_entitlements
                        where invoice_id=i.id and invoice_item_id is null and status in ('pending_activation','scheduled'))
       order by te.id for update;
     for a in select * from public.purchased_therapy_entitlements
               where invoice_id=i.id and invoice_item_id is null and status in ('pending_activation','scheduled')
                 and not public.therapy_unit_consumed(id) loop
       update public.purchased_therapy_entitlements set status='refunded',updated_by=auth.uid(),updated_at=now() where id=a.id;
       perform public.write_audit_ex('purchased_therapy_entitlements',a.id,'closed_with_invoice',
         jsonb_build_object('status',a.status,'invoice_item_id',a.invoice_item_id),
         jsonb_build_object('status','refunded','request_id',p_request_id),'refunds',p_reason,i.store_id);
     end loop;
   end if;$r$);
  execute d;
end $mig$;

-- ── 5. a direct cancellation does not close used therapy, or leave it running
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure);
  if position('v363_used' in d) > 0 then raise notice '363: cancel_invoice_recorded already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'c84a8a4f259cfc2c52ab92f80cac5e17' then
    raise exception '363: cancel_invoice_recorded is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$declare i public.invoices%rowtype; v_lot record; v_rev int; r record;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: cancel_invoice_recorded declare anchor found % times', n; end if;
  d := replace(d, a, a || ' v363_used text;');

  a := $a$ if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: cancel_invoice_recorded lock anchor found % times', n; end if;
  d := replace(d, a, a || $r$
 -- 363: every therapy unit on the invoice and its voucher allowance are locked
 -- before any voucher stock is touched, in the order the Claim window takes
 -- them (unit, allowance, stock).
 perform 1 from public.purchased_therapy_entitlements
   where invoice_id=i.id and status not in ('cancelled','refunded') order by id for update;
 perform 1 from public.therapy_entitlements te
   where te.id in (select voucher_entitlement_id from public.purchased_therapy_entitlements
                    where invoice_id=i.id and status not in ('cancelled','refunded'))
   order by te.id for update;$r$);

  a := $a$ update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_id=i.id and status in ('pending_activation','scheduled');$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '363: cancel_invoice_recorded therapy anchor found % times', n; end if;
  d := replace(d, a, $r$ -- 363: therapy on a line that has been used (started, ended, or vouchers
 -- collected) ends only on an Owner or Manager's authorization with an amount,
 -- which Refund / Cancel records before it gets here. It is not closed as if
 -- unused, and the invoice is not cancelled around it while it keeps running.
 -- A used unit no line holds (a correction deleted its line) is left as it is,
 -- as before. The units and their allowances were locked at the start.
 select string_agg(entitlement_no,', ' order by entitlement_no) into v363_used
   from public.purchased_therapy_entitlements
  where invoice_id=i.id and invoice_item_id is not null and status not in ('cancelled','refunded')
    and public.therapy_unit_consumed(id);
 if v363_used is not null then
   raise exception 'Therapy from this invoice has been started or has ended, or vouchers from it were collected (%). Cancel it with Refund / Cancel on the invoice, where an Owner or Manager authorizes ending it and states the amount.', v363_used; end if;
 update public.purchased_therapy_entitlements set status='refunded',updated_at=now()
  where invoice_id=i.id and status in ('pending_activation','scheduled') and not public.therapy_unit_consumed(id);$r$);
  execute d;
end $mig$;

notify pgrst, 'reload schema';
