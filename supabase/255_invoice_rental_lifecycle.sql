begin;
-- =====================================================================
-- A CANCELLED INVOICE MUST NOT LEAVE A LIVE RENTAL
--
-- 179 guards the rental lifecycle with
--   status::text in ('active','paid')
-- which leaves two holes at opposite ends of it.
--
-- OVERDUE was not blocked. An overdue rental is the item still out with the
-- customer, past its return date; its invoice could be cancelled and the record
-- of what was rented would simply go. Verified before writing this.
--
-- AWAITING_FULFILMENT and DRAFT were not blocked either, which is right --
-- nothing has been handed over, so there is nothing to return -- but the
-- cancellation then left the rental standing, so the invoice was cancelled and
-- the rental obligation was not. Also verified.
--
-- The rule this migration applies: a rental the customer HAS is a blocker, and
-- a rental the customer has NOT yet received is cancelled with the invoice.
--
--   active, paid, overdue          -> blocked; return or resolve it first
--   awaiting_fulfilment, draft     -> cancelled with the invoice, audited
--   returned, cancelled            -> already finished; nothing to do
--
-- The functions are patched from their installed definitions. 179 owns them,
-- 180-193 and 252 have each already patched them, and restating any of them
-- here would revert whatever else has landed.
--
-- Requires 179. Additive and idempotent.
-- =====================================================================

-- The statuses that mean the customer physically has the item.
create or replace function public.rental_is_outstanding(p_status text)
returns boolean language sql immutable as $$
 select p_status in ('active','paid','overdue')
$$;
comment on function public.rental_is_outstanding(text) is
 'True when a rental is with the customer and must be returned or resolved before '
 'its invoice can be cancelled, corrected or reopened. Overdue counts: late is not finished.';

-- Rentals that have not reached the customer and can be cancelled with the invoice.
create or replace function public.rental_is_unfulfilled(p_status text)
returns boolean language sql immutable as $$
 select p_status in ('awaiting_fulfilment','draft')
$$;

create or replace function public.cancel_invoice_rentals(p_invoice_id uuid,p_reason text)
returns integer language plpgsql security definer set search_path=public as $$
declare r record; n integer:=0;
begin
 for r in select * from public.rentals
           where invoice_id=p_invoice_id and public.rental_is_unfulfilled(status::text)
           for update
 loop
  update public.rentals
     set status='cancelled',cancelled_at=now(),
         notes=concat_ws(E'\n',notes,'Cancelled with its invoice: '||coalesce(p_reason,''))
   where id=r.id;
  perform public.write_audit_ex('rentals',r.id,'rental_cancelled_with_invoice',to_jsonb(r),
    jsonb_build_object('invoice_id',p_invoice_id,'reason',p_reason),'rentals',null,r.store_id);
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.cancel_invoice_rentals(uuid,text) from public,anon,authenticated;

-- ---------------------------------------------------------------------
-- Widen the three guards, and cancel what has not been handed over.
-- ---------------------------------------------------------------------
do $$
declare f text; old_cancel text; new_cancel text; old_reopen text; new_reopen text;
 old_correct text; new_correct text;
begin
 -- 1. Cancellation.
 select pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure) into f;
 if position('public.rental_is_outstanding' in f)=0 then
  old_cancel:=' if exists(select 1 from public.rentals where invoice_id=i.id and status::text in (''active'',''paid'')) then raise exception ''Return or resolve the active rental before cancelling this invoice''; end if;';
  if position(old_cancel in f)=0 then
   raise exception 'Unexpected rental guard in cancel_invoice_recorded; widen it by hand';
  end if;
  new_cancel:=' if exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then raise exception ''Return or resolve the outstanding rental before cancelling this invoice''; end if;'||chr(10)||
              ' perform public.cancel_invoice_rentals(i.id,p_reason);';
  f:=replace(f,old_cancel,new_cancel);
  execute f;
  raise notice 'cancellation now blocks an outstanding rental and cancels an unfulfilled one';
 end if;

 -- 2. Reopening preview.
 select pg_get_functiondef('public.invoice_reopen_preview_before_sessions(uuid)'::regprocedure) into f;
 if position('public.rental_is_outstanding' in f)=0 then
  old_reopen:=' if exists(select 1 from public.rentals where invoice_id=i.id and status::text in (''active'',''paid'')) then';
  if position(old_reopen in f)=0 then
   raise exception 'Unexpected rental guard in invoice_reopen_preview_before_sessions; widen it by hand';
  end if;
  new_reopen:=' if exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then';
  f:=replace(f,old_reopen,new_reopen);
  f:=replace(f,'Resolve the existing active rental in Rentals before reopening',
               'Resolve the outstanding rental in Rentals before reopening');
  execute f;
  raise notice 'reopening preview now reports an overdue rental as a blocker';
 end if;

 -- 3. Operational correction.
 select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 if position('public.rental_is_outstanding' in f)=0 then
  old_correct:=' if v_operational and exists(select 1 from public.rentals where invoice_id=i.id and status::text in (''active'',''paid'')) then';
  if position(old_correct in f)=0 then
   raise exception 'Unexpected rental guard in correct_invoice; widen it by hand';
  end if;
  new_correct:=' if v_operational and exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then';
  f:=replace(f,old_correct,new_correct);
  f:=replace(f,'Return or resolve the active rental before changing its invoice allocation',
               'Return or resolve the outstanding rental before changing its invoice allocation');
  execute f;
  raise notice 'correction now blocks an overdue rental too';
 end if;
end $$;

grant execute on function public.rental_is_outstanding(text) to authenticated;
grant execute on function public.rental_is_unfulfilled(text) to authenticated;

notify pgrst,'reload schema';
commit;
