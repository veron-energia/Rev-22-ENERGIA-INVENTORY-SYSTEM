-- =====================================================================
-- ENERGIA — CORRECTING WHO RAISED AN INVOICE
--
-- invoices.created_by is the person the invoice is attributed to, and it is
-- what prints on the STAFF SIGNATURE line. When someone rings a sale up on a
-- colleague's logged-in till, the wrong name is printed on the customer's copy
-- and there is currently no way to put it right.
--
-- Scope, deliberately narrow:
--
--   * OWNER ONLY. Not Managers. This rewrites who a document says served the
--     customer, which is closer to an audit record than an operational field.
--   * Commission is NOT affected. Neither earn_staff_commission() nor
--     earn_invoice_commission() reads created_by — staff commission is shared
--     across the store's assigned staff, and affiliate commission follows
--     affiliate_id. Verified before building this, so correcting the name
--     cannot quietly move anybody's money.
--   * The previous value is recorded in the audit trail, so the original
--     attribution is never lost.
--
-- Additive and idempotent. Run AFTER 115.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.correct_invoice_created_by(
  p_invoice_id uuid, p_staff_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_old_name text; v_new_name text; v_role text;
begin
  -- Owner only: this changes what a printed document says about who served the
  -- customer, so it sits above the usual Owner/Manager line.
  if public.current_user_role() <> 'owner' then
    raise exception 'Only an Owner can change who an invoice is attributed to';
  end if;

  select * into v_inv from public.invoices where id = p_invoice_id and deleted_at is null;
  if not found then raise exception 'Invoice not found'; end if;
  if p_staff_id is null then raise exception 'Choose who raised this invoice'; end if;

  select full_name, role into v_new_name, v_role from public.profiles
   where id = p_staff_id and coalesce(is_active, true);
  if v_new_name is null then
    raise exception 'That person is not an active user'; end if;

  -- The person must actually work at the store the invoice belongs to, unless
  -- they are an Owner or Manager, who are not assignment-scoped. Otherwise a
  -- sale could be attributed to someone who has never worked there.
  if v_role not in ('owner','admin','manager')
     and not exists (select 1 from public.user_store_assignments usa
                      where usa.user_id = p_staff_id and usa.store_id = v_inv.store_id) then
    raise exception '% is not assigned to the store this invoice belongs to', v_new_name;
  end if;

  select full_name into v_old_name from public.profiles where id = v_inv.created_by;

  if v_inv.created_by = p_staff_id then
    return jsonb_build_object('changed', false, 'staff_name', v_new_name);
  end if;

  update public.invoices set created_by = p_staff_id where id = p_invoice_id;

  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_attribution_corrected',
    jsonb_build_object('created_by', v_inv.created_by, 'name', v_old_name),
    jsonb_build_object('created_by', p_staff_id, 'name', v_new_name),
    'invoices', p_reason, v_inv.store_id);

  return jsonb_build_object('changed', true,
    'was', coalesce(v_old_name, '—'), 'now', v_new_name,
    'note', 'Commission is unaffected: it follows the store''s staff and the invoice affiliate, not this field.');
end $function$;

-- Who may be attributed an invoice at a given store, for the picker.
create or replace function public.invoice_attribution_candidates(p_store_id uuid)
returns table(staff_id uuid, full_name text, role text)
language sql stable security definer set search_path to 'public' as $function$
  select p.id, p.full_name, p.role::text
    from public.profiles p
   where coalesce(p.is_active, true)
     and (
       p.role in ('owner','admin','manager')
       or exists (select 1 from public.user_store_assignments usa
                   where usa.user_id = p.id and usa.store_id = p_store_id)
     )
   order by case p.role::text when 'staff' then 0 else 1 end, p.full_name
$function$;

notify pgrst, 'reload schema';
