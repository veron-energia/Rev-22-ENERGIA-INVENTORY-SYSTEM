begin;
-- =====================================================================
-- A SOLD VOUCHER BECOMES A RECORDED ENTITLEMENT
--
-- Selling a voucher on an invoice deducted store stock and took the customer's
-- money, and recorded nothing about what the customer now held. So
-- invoice_untracked_voucher() -- correctly, on the evidence available --
-- refused to refund any voucher line, and 187 documented that as a pending
-- review workflow.
--
-- It was refusing NEW sales too, not only historical ones. That is not a
-- historical-evidence gap; it is a missing issuance step. Verified before
-- writing this: a voucher sold and paid for entirely under the current code
-- still could not be refunded.
--
-- What changes: paying an invoice now issues the units it sold, into the same
-- customer_reward_vouchers model the package and bundle paths already use, with
-- a matching invoice_benefit_values row. Everything downstream -- refund
-- revocation (174), cancellation (179), unused-recipient transfer (186),
-- reopening (184) and, for a therapy voucher, the rights snapshot (241) --
-- already knows how to handle that shape, so none of it needed changing.
--
-- The guard becomes evidence-based rather than blanket: a line with issued
-- units is refundable, a line without them stays pending review. Vouchers
-- inside a promotion keep needing recorded component allocations, because their
-- share of a bundled price genuinely is not derivable -- that part of 187's
-- limitation is real and stays.
--
-- Nothing is backfilled. An invoice paid before this migration has no issued
-- units and remains a review case; inventing them would be inventing what a
-- customer was given.
--
-- Requires 174, 178, 179, 184, 186 and 187. Additive and idempotent.
-- =====================================================================

create or replace function public.issue_sold_vouchers_for_invoice(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; it record; rv uuid; n integer:=0; paid numeric; units integer;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or i.customer_id is null then return 0; end if;

 for it in select * from public.invoice_items
            where invoice_id=p_invoice_id and line_kind='voucher' and voucher_id is not null
            order by id
 loop
  -- Idempotent: paying twice, a replayed trigger or a reopening must not hand
  -- the customer a second set of units.
  if exists(select 1 from public.customer_reward_vouchers
             where source_type='invoice_voucher_sale' and source_id=it.id) then continue; end if;

  units:=greatest(coalesce(it.quantity,1),1);
  insert into public.customer_reward_vouchers
   (customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id,notes)
  values (i.customer_id,it.voucher_id,i.store_id,units,'held',auth.uid(),
          'invoice_voucher_sale',it.id,'Sold on invoice '||coalesce(i.invoice_no,'(no number)'))
  returning id into rv;

  -- The paid value is what this line actually charged after its discount, not a
  -- catalogue price. It is what caps any later refund.
  paid:=coalesce(public.invoice_discounted_line_value(it.id),0);
  insert into public.invoice_benefit_values
   (invoice_id,invoice_item_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
  values (p_invoice_id,it.id,rv,paid,units,'Issued at sale',auth.uid());

  n:=n+1;
 end loop;

 if n>0 then
  perform public.write_audit_ex('invoices',p_invoice_id,'sold_voucher_units_issued',null,
    jsonb_build_object('lines',n),'invoices',null,i.store_id);
 end if;
 return n;
end $$;
revoke all on function public.issue_sold_vouchers_for_invoice(uuid) from public,anon,authenticated;

create or replace function public.trg_issue_sold_vouchers_on_paid()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status::text='paid' and old.status::text is distinct from 'paid' then
  perform public.issue_sold_vouchers_for_invoice(new.id);
 end if;
 return null;
end $$;

drop trigger if exists issue_sold_vouchers_on_paid on public.invoices;
create trigger issue_sold_vouchers_on_paid after update on public.invoices
 for each row execute function public.trg_issue_sold_vouchers_on_paid();

-- Evidence-based, not blanket. Unchanged for promotion-embedded vouchers, whose
-- share of a bundled price still has to be recorded by a person through
-- record_invoice_benefit_values before a refund can be allocated.
create or replace function public.invoice_untracked_voucher(p_invoice_id uuid,p_item_id uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(
  select 1 from public.invoice_items it
   where it.invoice_id=p_invoice_id and (p_item_id is null or it.id=p_item_id)
     and (
       it.line_kind='voucher'
       or (it.line_kind='promotion' and (
            exists(select 1 from public.invoice_stock_components sc
                    where sc.invoice_item_id=it.id and sc.kind='voucher')
            or exists(select 1 from public.invoice_promotion_selections s
                       where s.invoice_item_id=it.id and s.voucher_id is not null)))
     )
     -- The line is untracked only when nothing records what was issued for it.
     and not exists(select 1 from public.invoice_benefit_values b
                     where b.invoice_item_id=it.id and b.reward_voucher_id is not null))
$$;
revoke all on function public.invoice_untracked_voucher(uuid,uuid) from public,anon,authenticated;

-- Lines still awaiting review, for the existing diagnostics.
create or replace function public.invoice_untracked_voucher_lines()
returns table(invoice_id uuid,invoice_no text,invoice_item_id uuid,line_kind text,
              voucher_id uuid,voucher_name text,quantity integer,paid_at timestamptz)
language sql stable security definer set search_path=public as $$
 select i.id,i.invoice_no,it.id,it.line_kind::text,it.voucher_id,v.name,it.quantity,i.paid_at
   from public.invoice_items it
   join public.invoices i on i.id=it.invoice_id
   left join public.vouchers v on v.id=it.voucher_id
  where public.invoice_untracked_voucher(i.id,it.id)
    and i.status::text in ('paid','partially_paid','cancelled','refunded')
  order by i.paid_at desc nulls last
$$;
grant execute on function public.invoice_untracked_voucher_lines() to authenticated;

-- ---------------------------------------------------------------------
-- Refunding a voucher line must revoke what it refunds.
--
-- The benefit block inside refund_invoice_recorded is gated on
--   if it.line_kind in ('credit_package','premium_bundle') then
-- so a voucher line skipped it entirely: the benefits array was accepted and
-- ignored, the money went back and the customer kept the voucher. Verified
-- before writing this, with and without an explicit allocation.
--
-- The gate is widened to include a voucher line that has issued units, and the
-- credit-source assertion inside it stays restricted to the credit lines it was
-- written for. The function is patched from its installed definition rather
-- than restated: 174 owns it and 187, 191 and 252 have each already patched it.
-- ---------------------------------------------------------------------
create or replace function public.invoice_line_has_issued_vouchers(p_item_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.invoice_benefit_values b
                where b.invoice_item_id=p_item_id and b.reward_voucher_id is not null)
$$;
revoke all on function public.invoice_line_has_issued_vouchers(uuid) from public,anon,authenticated;

do $$
declare f text; anchor text; replacement text;
begin
 select pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 if position('public.invoice_line_has_issued_vouchers(it.id)' in f)>0 then
  raise notice 'voucher lines already reach the benefit revocation block'; return;
 end if;

 anchor:='     if it.line_kind in (''credit_package'',''premium_bundle'') then
       perform public.assert_invoice_credit_source_evidence(i.id,it.id);';
 if position(anchor in f)=0 then
  raise exception 'Unexpected refund benefit gate; widen it by hand rather than guessing';
 end if;

 replacement:='     if it.line_kind in (''credit_package'',''premium_bundle'') or public.invoice_line_has_issued_vouchers(it.id) then
       if it.line_kind in (''credit_package'',''premium_bundle'') then
         perform public.assert_invoice_credit_source_evidence(i.id,it.id);
       end if;';
 f:=replace(f,anchor,replacement);

 -- The message names what it now covers.
 f:=replace(f,'Select recorded unused benefit allocations for this credit/bundle refund',
              'Select the recorded unused benefit allocations for this refund (credit, bundle or issued voucher units)');
 execute f;
 raise notice 'refunding a voucher line now revokes the units it refunds';
end $$;

notify pgrst,'reload schema';
commit;
