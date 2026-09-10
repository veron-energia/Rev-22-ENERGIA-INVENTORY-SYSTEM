begin;
-- =====================================================================
-- CHANGING THE STORE ON AN INVOICE THAT PREDATES STOCK SNAPSHOTS
--
-- Reported: correcting the Store on a paid invoice fails with
--   "Historical component snapshots need review before changing stock or
--    selections; metadata can still be corrected"
--
-- Reproduced in an isolated fixture, and the cause is exact. Migration 177
-- added invoice_stock_components and set invoices.stock_snapshot_version to
-- DEFAULT 1 — a default binds new rows only, so every invoice created before
-- 177 was applied still has NULL there and no component rows. 172's guard is
--
--   v_stock_change := ... or n.store_id <> i.store_id;
--   if v_operational and i.stock_snapshot_version is null
--      and exists(... line_kind in ('promotion','voucher')) then raise ...
--
-- so a store change on such an invoice is refused, while metadata corrections
-- are allowed — exactly the reported behaviour. The guard is right to refuse:
-- moving an invoice between stores moves stock, and it will not do that against
-- components it cannot see.
--
-- But refusing forever is not the answer either, because for most lines the
-- evidence DOES exist and simply was never copied into the snapshot table:
--
--   a product line     — the line itself names the product and the quantity
--   a voucher line     — the line itself names the voucher and the quantity,
--                        and invoice_voucher_movements corroborates the store
--   promotion choices  — invoice_promotion_selections is the customer's actual
--                        recorded choice, not a guess
--
-- One thing genuinely is not recorded: the FIXED contents of a promotion as it
-- stood on the day. promotion_stock_items() answers from TODAY'S definition, so
-- this migration never uses it silently. A person is shown what today's
-- definition says, and must confirm it matches what was sold, or supply what
-- was. That confirmation is recorded with their name and reason.
--
-- Nothing is repriced, no benefit is moved, and no stock is returned here. This
-- migration only restores the snapshot the correction needs, then gets out of
-- the way so the existing protected correction runs unchanged.
--
-- Requires 172, 177 and 187. Additive and idempotent.
-- =====================================================================

-- Provenance lives here rather than on the component rows: component_source has
-- to keep the values 177's capture trigger manages, or a later edit of the line
-- would leave orphaned duplicates behind.
create table if not exists public.invoice_stock_component_rebuilds(
 id uuid primary key default gen_random_uuid(),
 invoice_id uuid not null references public.invoices(id),
 request_id uuid,
 reason text not null,
 evidence jsonb not null,
 components jsonb not null,
 confirmed_lines jsonb not null default '[]'::jsonb,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now());
create index if not exists invoice_stock_component_rebuilds_invoice
 on public.invoice_stock_component_rebuilds(invoice_id);
create unique index if not exists invoice_stock_component_rebuilds_request
 on public.invoice_stock_component_rebuilds(request_id) where request_id is not null;
alter table public.invoice_stock_component_rebuilds enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public'
                and tablename='invoice_stock_component_rebuilds' and policyname='read stock rebuilds') then
  create policy "read stock rebuilds" on public.invoice_stock_component_rebuilds for select to authenticated
   using(exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));
 end if;
end $$;

-- ---------------------------------------------------------------------
-- 0. A separate defect, found while reproducing the reported one.
--
-- 177 renamed the original expansion to invoice_required_stock_legacy, whose
-- quantity is BIGINT (it comes from a sum()), and had the new
-- invoice_required_stock declare quantity INTEGER. The fallback branch --
-- the one taken for exactly the invoices this migration is about, those with
-- no snapshot -- returns the legacy rows straight through, so PostgreSQL
-- raises "structure of query does not match function result type".
--
-- That means invoice_required_stock() has been failing for EVERY pre-177
-- invoice, and with it confirm_foc_invoice, ensure_invoice_stock_deducted,
-- invoice_stock_to_deduct and every stock diagnostic. It went unnoticed
-- because the invoice fixtures only ever create new invoices, which take the
-- snapshot branch.
--
-- One cast. The function is patched from its installed definition; 177 owns it.
-- ---------------------------------------------------------------------
do $$
declare f text; anchor text;
begin
 select pg_get_functiondef('public.invoice_required_stock(uuid)'::regprocedure) into f;
 if position('r.quantity::int from public.invoice_required_stock_legacy' in f)>0 then
  raise notice 'invoice_required_stock already casts the legacy quantity'; return;
 end if;
 anchor:='return query select r.kind,r.item_id,r.quantity from public.invoice_required_stock_legacy(p_invoice_id) r;';
 if position(anchor in f)=0 then
  raise exception 'Unexpected invoice_required_stock fallback; add the cast by hand';
 end if;
 execute replace(f,anchor,
  'return query select r.kind,r.item_id,r.quantity::int from public.invoice_required_stock_legacy(p_invoice_id) r;');
 raise notice 'invoice_required_stock now works for invoices with no snapshot';
end $$;

-- A readable label for a line, from whichever catalogue row it points at.
create or replace function public.invoice_line_label(p_item_id uuid)
returns text language sql stable security definer set search_path=public as $$
 select coalesce(p.name,v.name,pr.name,it.line_kind::text)
   from public.invoice_items it
   left join public.products p on p.id=it.product_id
   left join public.vouchers v on v.id=it.voucher_id
   left join public.promotions pr on pr.id=it.promotion_id
  where it.id=p_item_id
$$;
grant execute on function public.invoice_line_label(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 1. What evidence exists, line by line. Read-only.
--
--    status:
--      captured           the snapshot is already there; nothing to do
--      reconstructable    the original records answer this line completely
--      needs_confirmation only today's promotion definition is available
--      not_applicable     this line kind consumes no tracked stock
--      missing            nothing on record answers it
-- ---------------------------------------------------------------------
create or replace function public.invoice_stock_component_evidence(p_invoice_id uuid)
returns table(invoice_item_id uuid, line_kind text, description text,
              evidence_status text, evidence_source text, proposed jsonb, missing text)
language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype; it record; v_sel jsonb; v_fixed jsonb; v_has_snapshot boolean;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found then return; end if;
 if not public.user_has_store_access(i.store_id) then
  raise exception 'No access to this invoice' using errcode='42501'; end if;

 for it in select * from public.invoice_items where invoice_id=p_invoice_id order by id loop
  v_has_snapshot:=exists(select 1 from public.invoice_stock_components c where c.invoice_item_id=it.id);

  if v_has_snapshot and i.stock_snapshot_version is not null then
   return query select it.id,it.line_kind::text,
     public.invoice_line_label(it.id),'captured',
     'Recorded when the invoice was created',
     coalesce((select jsonb_agg(jsonb_build_object('kind',c.kind,'item_id',c.item_id,'quantity',c.quantity))
                 from public.invoice_stock_components c where c.invoice_item_id=it.id),'[]'::jsonb),
     null::text;
   continue;
  end if;

  if it.line_kind='product' and it.product_id is not null then
   return query select it.id,'product',public.invoice_line_label(it.id),'reconstructable',
     'The invoice line itself records the product and quantity',
     jsonb_build_array(jsonb_build_object('kind','product','item_id',it.product_id,'quantity',it.quantity,'component_source','fixed')),
     null::text;

  elsif it.line_kind='voucher' and it.voucher_id is not null then
   if exists(select 1 from public.vouchers where id=it.voucher_id and qty_type='limited') then
    return query select it.id,'voucher',public.invoice_line_label(it.id),'reconstructable',
      case when exists(select 1 from public.invoice_voucher_movements m where m.invoice_id=p_invoice_id and m.voucher_id=it.voucher_id)
           then 'The invoice line, corroborated by the recorded voucher stock movement'
           else 'The invoice line itself records the voucher and quantity' end,
      jsonb_build_array(jsonb_build_object('kind','voucher','item_id',it.voucher_id,'quantity',it.quantity,'component_source','fixed')),
      null::text;
   else
    return query select it.id,'voucher',public.invoice_line_label(it.id),'not_applicable',
      'An unlimited voucher consumes no tracked stock','[]'::jsonb,null::text;
   end if;

  elsif it.line_kind='promotion' and it.promotion_id is not null then
   -- The customer's recorded choices are authoritative history.
   -- Grouped first, then aggregated: jsonb_agg over sum() is a nested aggregate.
   select coalesce(jsonb_agg(jsonb_build_object('kind',t.kind,'item_id',t.item_id,
            'quantity',t.qty,'component_source','selection')),'[]'::jsonb)
     into v_sel
     from (select case when s.product_id is not null then 'product' else 'voucher' end as kind,
                  coalesce(s.product_id,s.voucher_id) as item_id, sum(s.quantity)::int as qty
             from public.invoice_promotion_selections s
             left join public.vouchers v on v.id=s.voucher_id
            where s.invoice_item_id=it.id and (s.product_id is not null or v.qty_type='limited')
            group by 1,2) t;
   -- Today's definition of the fixed part. Shown, never applied on its own.
   select coalesce(jsonb_agg(jsonb_build_object('kind',r.kind,'item_id',r.item_id,'quantity',r.quantity,'component_source','fixed')),'[]'::jsonb)
     into v_fixed from public.promotion_stock_items(it.promotion_id,it.quantity) r;

   if jsonb_array_length(coalesce(v_fixed,'[]'::jsonb))=0 then
    return query select it.id,'promotion',public.invoice_line_label(it.id),
      case when jsonb_array_length(coalesce(v_sel,'[]'::jsonb))>0 then 'reconstructable' else 'missing' end,
      'The customer''s recorded promotion choices',
      coalesce(v_sel,'[]'::jsonb),
      case when jsonb_array_length(coalesce(v_sel,'[]'::jsonb))>0 then null
           else 'This promotion line has no recorded choices and no fixed contents on record.' end;
   else
    return query select it.id,'promotion',public.invoice_line_label(it.id),'needs_confirmation',
      'Recorded choices, plus this promotion''s CURRENT fixed contents',
      coalesce(v_sel,'[]'::jsonb)||coalesce(v_fixed,'[]'::jsonb),
      'The fixed contents of this promotion as it stood on the sale date are not recorded. '
      'Confirm that the contents shown still match what was sold, or supply what was.';
   end if;

  else
   return query select it.id,it.line_kind::text,public.invoice_line_label(it.id),
     'not_applicable','This line kind consumes no tracked stock','[]'::jsonb,null::text;
  end if;
 end loop;
end $$;
grant execute on function public.invoice_stock_component_evidence(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Rebuild the snapshot from that evidence. Owner or Manager only.
--
--    p_confirmations: [{invoice_item_id, confirmed: true}]
--                  or [{invoice_item_id, components:[{kind,item_id,quantity}]}]
--    The first accepts the contents shown; the second states what was actually
--    sold. A line needing confirmation and given neither stops the whole call.
-- ---------------------------------------------------------------------
create or replace function public.rebuild_invoice_stock_components(
 p_invoice_id uuid, p_reason text, p_confirmations jsonb default '[]'::jsonb,
 p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; e record; conf jsonb; comps jsonb:='[]'::jsonb;
 evidence jsonb:='[]'::jsonb; confirmed jsonb:='[]'::jsonb; c jsonb; blocked text[]:='{}';
 v_existing jsonb; n integer:=0;
begin
 if not public.is_owner_or_manager() then
  raise exception 'Only an Owner or Manager can review historical stock evidence' using errcode='42501'; end if;
 if coalesce(btrim(p_reason),'')='' then raise exception 'A reason is required'; end if;

 -- Replay safety: the same request returns its original outcome untouched.
 if p_request_id is not null then
  select jsonb_build_object('success',true,'replayed',true,'components',r.components)
    into v_existing from public.invoice_stock_component_rebuilds r where r.request_id=p_request_id;
  if v_existing is not null then return v_existing; end if;
 end if;

 select * into i from public.invoices where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) then
  raise exception 'No access to this invoice' using errcode='42501'; end if;
 if i.stock_snapshot_version is not null then
  return jsonb_build_object('success',true,'unchanged',true,
    'message','This invoice already has recorded stock components.'); end if;

 for e in select * from public.invoice_stock_component_evidence(p_invoice_id) loop
  evidence:=evidence||jsonb_build_array(jsonb_build_object(
    'invoice_item_id',e.invoice_item_id,'status',e.evidence_status,'source',e.evidence_source));
  if e.evidence_status='not_applicable' or e.evidence_status='captured' then continue; end if;

  if e.evidence_status='missing' then
   blocked:=array_append(blocked,coalesce(e.description,'a line')||' — '||coalesce(e.missing,'no evidence on record'));
   continue;
  end if;

  if e.evidence_status='needs_confirmation' then
   select x into conf from jsonb_array_elements(coalesce(p_confirmations,'[]'::jsonb)) x
    where x->>'invoice_item_id'=e.invoice_item_id::text;
   if conf is null then
    blocked:=array_append(blocked,coalesce(e.description,'a line')||' — '||coalesce(e.missing,'needs confirmation'));
    continue;
   end if;
   confirmed:=confirmed||jsonb_build_array(conf);
   if jsonb_typeof(conf->'components')='array' then
    -- The reviewer stated what was sold; the selections still come from record.
    comps:=comps||(select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',e.invoice_item_id,
             'kind',y->>'kind','item_id',y->>'item_id','quantity',(y->>'quantity')::int,'component_source','fixed')),'[]'::jsonb)
           from jsonb_array_elements(conf->'components') y);
    comps:=comps||(select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',e.invoice_item_id,
             'kind',y->>'kind','item_id',y->>'item_id','quantity',(y->>'quantity')::int,'component_source','selection')),'[]'::jsonb)
           from jsonb_array_elements(e.proposed) y where y->>'component_source'='selection');
   elsif coalesce((conf->>'confirmed')::boolean,false) then
    comps:=comps||(select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',e.invoice_item_id,
             'kind',y->>'kind','item_id',y->>'item_id','quantity',(y->>'quantity')::int,
             'component_source',y->>'component_source')),'[]'::jsonb)
           from jsonb_array_elements(e.proposed) y);
   else
    blocked:=array_append(blocked,coalesce(e.description,'a line')||' — confirmation was neither given nor replaced');
    continue;
   end if;
  else
   comps:=comps||(select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',e.invoice_item_id,
            'kind',y->>'kind','item_id',y->>'item_id','quantity',(y->>'quantity')::int,
            'component_source',y->>'component_source')),'[]'::jsonb)
          from jsonb_array_elements(e.proposed) y);
  end if;
 end loop;

 if array_length(blocked,1)>0 then
  raise exception 'These lines still need evidence before the snapshot can be rebuilt: %',
    array_to_string(blocked,'; ');
 end if;

 for c in select * from jsonb_array_elements(comps) loop
  insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source)
  values((c->>'invoice_item_id')::uuid,c->>'kind',(c->>'item_id')::uuid,
         (c->>'quantity')::int,c->>'component_source')
  on conflict (invoice_item_id,kind,item_id,component_source)
   do update set quantity=excluded.quantity;
  n:=n+1;
 end loop;

 -- Version 1 is what every downstream reader tests for. Provenance is recorded
 -- in the rebuild row rather than in this number, so invoice_required_stock and
 -- 177's capture trigger keep working on this invoice exactly as on any other.
 update public.invoices set stock_snapshot_version=1 where id=p_invoice_id;

 insert into public.invoice_stock_component_rebuilds
  (invoice_id,request_id,reason,evidence,components,confirmed_lines,created_by)
 values (p_invoice_id,p_request_id,btrim(p_reason),evidence,comps,confirmed,auth.uid());

 perform public.write_audit_ex('invoices',p_invoice_id,'stock_components_rebuilt',null,
   jsonb_build_object('components',n,'evidence',evidence,'confirmed',confirmed,'reason',btrim(p_reason)),
   'invoices',null,i.store_id);

 return jsonb_build_object('success',true,'components',comps,'component_rows',n);
end $$;
grant execute on function public.rebuild_invoice_stock_components(uuid,text,jsonb,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. What moving this invoice to another store would actually mean.
-- ---------------------------------------------------------------------
create or replace function public.invoice_store_change_preview(p_invoice_id uuid, p_store_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype; v_needs jsonb; v_short jsonb; v_review boolean; v_vouchers jsonb;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.user_has_store_access(i.store_id) or not public.user_has_store_access(p_store_id) then
  raise exception 'You need access to both the current and the destination store' using errcode='42501'; end if;

 v_review:=i.stock_snapshot_version is null
   and exists(select 1 from public.invoice_items where invoice_id=p_invoice_id
               and line_kind in ('promotion','voucher'));

 -- What the invoice consumes, from the recorded components where they exist.
 select coalesce(jsonb_agg(jsonb_build_object('kind',r.kind,'item_id',r.item_id,'quantity',r.quantity)),'[]'::jsonb)
   into v_needs from public.invoice_required_stock(p_invoice_id) r;

 -- Where the destination cannot cover it. Products read store_inventory;
 -- vouchers read voucher_store_stock.
 select coalesce(jsonb_agg(jsonb_build_object('kind',x.kind,'item_id',x.item_id,'name',x.name,
          'required',x.required,'available',x.available,'short',x.required-x.available)),'[]'::jsonb)
   into v_short
   from (select r.kind,r.item_id,
           case when r.kind='product' then (select p.name from public.products p where p.id=r.item_id)
                else (select v.name from public.vouchers v where v.id=r.item_id) end as name,
           r.quantity as required,
           case when r.kind='product'
                then coalesce((select si.current_qty from public.store_inventory si
                                where si.store_id=p_store_id and si.product_id=r.item_id),0)
                else coalesce((select vs.current_qty from public.voucher_store_stock vs
                                where vs.store_id=p_store_id and vs.voucher_id=r.item_id),0) end as available
         from public.invoice_required_stock(p_invoice_id) r) x
  where x.required>x.available;

 select coalesce(jsonb_agg(jsonb_build_object('voucher_id',m.voucher_id,'from_store',i.store_id,'to_store',p_store_id)),'[]'::jsonb)
   into v_vouchers from (select distinct voucher_id from public.invoice_voucher_movements where invoice_id=p_invoice_id) m;

 return jsonb_build_object(
  'invoice_no',i.invoice_no,
  'from_store',(select jsonb_build_object('id',s.id,'name',s.name) from public.stores s where s.id=i.store_id),
  'to_store',(select jsonb_build_object('id',s.id,'name',s.name) from public.stores s where s.id=p_store_id),
  'review_required',v_review,
  'review_reason',case when v_review then
    'This invoice predates stock snapshots. Its components must be reviewed and rebuilt before its store can change.' end,
  'required_stock',v_needs,
  'shortages',v_short,
  'voucher_locations',v_vouchers,
  -- Stated, not performed: nothing here returns or re-deducts anything.
  'stock_note','Moving the invoice re-deducts its components at the destination and reverses the outstanding deduction at the source. Damaged, not-returned, already-returned and already-refunded quantities are never returned to sellable stock.',
  'commission_note','Commission follows the invoice''s current rules and is recalculated on save; completed payouts are preserved and offset against future commission.',
  'blocked',coalesce(v_review,false) or jsonb_array_length(v_short)>0);
end $$;
grant execute on function public.invoice_store_change_preview(uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
