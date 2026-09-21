begin;
-- =====================================================================
-- A CHOICE GROUP CAN OFFER A PROMOTION
--
-- A promotion's choice group is a "choose N from ..." that the cashier resolves
-- at the till. The screen offers four kinds — Products, Vouchers, Therapy,
-- Credit packages — and the owner asked for a fifth: a group whose options are
-- other promotions.
--
-- TWO OF THE FOUR NEVER WORKED.
--
-- promotion_choice_options still carries the constraint it was created with,
-- before therapy and credit packages were added as kinds:
--
--     CHECK (product_id is not null or voucher_id is not null)
--
-- So an option holding only a therapy package, or only a credit package, is
-- refused by the database. The dropdown offers them, the insert fails, and the
-- raw constraint error is what the user sees. Measured on production: 34 choice
-- groups and 73 options exist, and not one of them is therapy or credit package,
-- which is what you would expect of two kinds that cannot be saved.
--
-- That constraint also blocks the new kind, so it has to be rewritten either
-- way. This migration therefore does three things:
--
--   1. replaces the stale constraint with one that covers every kind, so
--      therapy and credit-package options can be saved at all;
--   2. adds child_promotion_id, and widens item_kind to include 'promotion';
--   3. enforces the nesting rules on the way in.
--
-- WHY A TRIGGER. Choice groups and options are inserted straight from the
-- browser — src/pages/PromotionsPage.tsx writes to these tables with no RPC in
-- between — so there is nowhere else to put a rule. The row-level policy limits
-- writes to owners and managers, which is authorisation, not validation.
--
-- The rules are not new ones. A promotion offered in a choice group faces
-- exactly the checks validate_promotion_child already applies to a promotion
-- nested as an included item: it cannot be itself, nesting stops at two levels
-- in both directions, and a promotion that has its own choice groups cannot be
-- offered — otherwise the cashier picks a promotion and is immediately asked to
-- pick again inside it, which is the case that rule exists to prevent.
-- =====================================================================

-- ---- 1. every kind may be stored -------------------------------------------
do $$
declare v_bad int;
begin
  -- An option must name exactly one thing. Check the existing rows satisfy that
  -- before making it a rule, rather than discovering it during the ALTER.
  select count(*) into v_bad from public.promotion_choice_options
   where (product_id is not null)::int + (voucher_id is not null)::int
       + (therapy_package_id is not null)::int + (credit_package_id is not null)::int <> 1;
  if v_bad > 0 then
    raise exception '346: % existing choice option(s) name none or several things; reconcile them before tightening the constraint', v_bad;
  end if;
end $$;

alter table public.promotion_choice_options
  drop constraint if exists promotion_choice_options_check;

alter table public.promotion_choice_options
  add column if not exists child_promotion_id uuid references public.promotions(id);

alter table public.promotion_choice_options
  add constraint promotion_choice_options_name_exactly_one check (
    (product_id is not null)::int + (voucher_id is not null)::int
  + (therapy_package_id is not null)::int + (credit_package_id is not null)::int
  + (child_promotion_id is not null)::int = 1
  );

-- ---- 2. the new kind -------------------------------------------------------
do $$
declare v_con text;
begin
  select conname into v_con from pg_constraint
   where conrelid = 'public.promotion_choice_groups'::regclass
     and contype = 'c' and pg_get_constraintdef(oid) like '%item_kind%';
  if v_con is null then
    raise exception '346: no item_kind check constraint found on promotion_choice_groups';
  end if;
  execute format('alter table public.promotion_choice_groups drop constraint %I', v_con);
end $$;

alter table public.promotion_choice_groups
  add constraint promotion_choice_groups_item_kind_check check (
    item_kind = any (array['product','voucher','therapy','credit_package','promotion'])
  );

-- ---- 3. the rules, on the way in -------------------------------------------
-- SECURITY DEFINER because validate_promotion_child is granted to nobody (339);
-- a nested call inside a definer function runs as the owner, which is the
-- established pattern here.
create or replace function public.trg_promotion_choice_option_valid()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare
  v_parent uuid;
  v_kind text;
begin
  select g.promotion_id, g.item_kind into v_parent, v_kind
    from public.promotion_choice_groups g where g.id = new.group_id;
  if v_parent is null then
    raise exception 'That choice group no longer exists.';
  end if;

  -- The option must match the kind its group advertises, or the till is asked
  -- to price something the group was not built for.
  if (v_kind = 'product'        and new.product_id is null)
  or (v_kind = 'voucher'        and new.voucher_id is null)
  or (v_kind = 'therapy'        and new.therapy_package_id is null)
  or (v_kind = 'credit_package' and new.credit_package_id is null)
  or (v_kind = 'promotion'      and new.child_promotion_id is null) then
    raise exception 'This group offers %, so each option must be a %.', v_kind, v_kind;
  end if;

  -- The same rules a nested included item faces. Reused, not reinvented.
  if new.child_promotion_id is not null then
    perform public.validate_promotion_child(v_parent, new.child_promotion_id);
  end if;

  return new;
end $$;

revoke all on function public.trg_promotion_choice_option_valid() from public, anon, authenticated;
grant execute on function public.trg_promotion_choice_option_valid() to service_role;

drop trigger if exists promotion_choice_option_valid on public.promotion_choice_options;
create trigger promotion_choice_option_valid
  before insert or update on public.promotion_choice_options
  for each row execute function public.trg_promotion_choice_option_valid();

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='promotion_choice_options'
                    and column_name='child_promotion_id') then
    raise exception '346: child_promotion_id was not added';
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid='public.promotion_choice_groups'::regclass
                    and pg_get_constraintdef(oid) like '%promotion%'
                    and pg_get_constraintdef(oid) like '%item_kind%') then
    raise exception '346: item_kind still refuses the promotion kind';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgrelid='public.promotion_choice_options'::regclass
                    and tgname='promotion_choice_option_valid') then
    raise exception '346: choice options are still written without validation';
  end if;
  raise notice '346: choice groups may offer promotions; therapy and credit-package options can now be saved at all';
end $$;

notify pgrst, 'reload schema';
commit;
