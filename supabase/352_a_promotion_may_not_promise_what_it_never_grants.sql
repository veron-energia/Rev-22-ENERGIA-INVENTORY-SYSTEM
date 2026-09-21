-- 352_a_promotion_may_not_promise_what_it_never_grants.sql
--
-- The promotion editor offers "Credit package" as an included item, and (since
-- 346) as a choice-group kind. Neither is ever issued. A customer can pay for a
-- promotion built that way and receive no credit at all:
--
--   * create_invoice never reads promotion_items, so no credit_package line is
--     built from a promotion's contents;
--   * issue_credit_lines_for_invoice — the only thing that grants credit —
--     gates on line_kind in ('credit_package','premium_bundle'), and a
--     promotion sells as line_kind 'promotion';
--   * 349 records a chosen credit package in invoice_promotion_selections, but
--     nothing reads those rows to issue anything.
--
-- Nobody has stepped on it yet. At the time of writing production holds 0
-- promotion_items with a credit package, 0 choice groups of that kind, 0 choice
-- options carrying one, and 0 recorded selections — against 224 promotion lines
-- sold. The offer has simply never been taken up.
--
-- Making it TRUE is the better fix and is being built separately (350 and 351
-- in this directory, deliberately NOT applied — see the note at the end). That
-- work turned out to touch the wallet, refund, commission and exchange paths,
-- and two adversarial review rounds found money-losing defects in it. Until it
-- is finished and proven, the honest thing is to stop offering something the
-- system does not do, rather than to leave a loaded trap in the editor.
--
-- This migration therefore refuses the authoring, with a message that says why
-- and what to do instead. It grants nothing, issues nothing, and changes no
-- existing row.

set lock_timeout = '5s';

-- ── 0. refuse to run if it would invalidate existing data ────────────────────
-- If any of these exist, somebody HAS built one, and the right response is to
-- look at it rather than to start rejecting edits to it.
do $mig$
declare v_items int; v_groups int; v_options int; v_sel int;
begin
  select count(*) into v_items from public.promotion_items
   where item_type::text = 'credit_package' or credit_package_id is not null;
  select count(*) into v_groups from public.promotion_choice_groups where item_kind = 'credit_package';
  select count(*) into v_options from public.promotion_choice_options where credit_package_id is not null;
  select count(*) into v_sel from public.invoice_promotion_selections where credit_package_id is not null;

  if v_items + v_groups + v_options + v_sel > 0 then
    raise exception '352: refusing to close the trap while % promotion item(s), % choice group(s), % option(s) and % recorded selection(s) already use a credit package. Review those first — customers may have paid for them.',
      v_items, v_groups, v_options, v_sel;
  end if;
end $mig$;

-- ── 1. the included-items path ───────────────────────────────────────────────
-- Anchored replacement rather than a rewrite: add_promotion_item keeps its exact
-- signature, so PostgREST still resolves the one candidate it has today and no
-- overload can appear. (Granting two candidates is how 339 took transfer
-- requests down; 348 cleaned it up. Not repeating it.)
do $mig$
declare v_src text;
  c_anchor constant text := '  if p_item_type = ''credit_package'' and p_credit_package_id is null then' || chr(10) ||
                            '    raise exception ''Select a credit package''; end if;';
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'add_promotion_item' and p.pronamespace = 'public'::regnamespace;
  if v_src is null then raise exception '352: add_promotion_item not found'; end if;
  if position('352:' in v_src) > 0 then
    raise notice '352: add_promotion_item already refuses a package; left alone.'; return; end if;
  if position(c_anchor in v_src) = 0 then
    raise exception '352: add_promotion_item is not the one this migration was written against';
  end if;

  execute replace(v_src, c_anchor,
    '  -- 352: a package inside a promotion is never issued. Refuse to author it' || chr(10) ||
    '  -- rather than let a customer pay for credit they will not receive. The' || chr(10) ||
    '  -- comparison is on text so this still holds if the enum later gains' || chr(10) ||
    '  -- premium_bundle before the issuing side is finished.' || chr(10) ||
    '  if p_item_type::text in (''credit_package'', ''premium_bundle'') then' || chr(10) ||
    '    raise exception ''A credit package or premium bundle inside a promotion is not issued yet: the customer would pay for the promotion and receive no credit. Sell the package on its own line, or on its own invoice, until this is supported.'';' || chr(10) ||
    '  end if;');
end $mig$;

-- ── 2. the choice-group path ─────────────────────────────────────────────────
-- 346 widened item_kind to five values, which incidentally unblocked
-- credit_package groups that had never been saveable. Therapy stays — a therapy
-- choice IS issued, by invoice_therapy_entitlements_due. Only the credit
-- package is a promise nothing keeps.
do $mig$
declare v_con text;
begin
  select conname into v_con from pg_constraint
   where conrelid = 'public.promotion_choice_groups'::regclass
     and contype = 'c' and pg_get_constraintdef(oid) like '%item_kind%';
  if v_con is null then raise exception '352: no item_kind check constraint on promotion_choice_groups'; end if;

  if (select pg_get_constraintdef(oid) from pg_constraint where conname = v_con
        and conrelid = 'public.promotion_choice_groups'::regclass) not like '%credit_package%' then
    raise notice '352: choice groups already refuse credit packages; left alone.'; return; end if;

  execute format('alter table public.promotion_choice_groups drop constraint %I', v_con);
  alter table public.promotion_choice_groups
    add constraint promotion_choice_groups_item_kind_check check (
      item_kind = any (array['product','voucher','therapy','promotion']));
end $mig$;

-- And the options themselves, which the editor writes directly.
do $mig$
begin
  if exists (select 1 from pg_constraint
              where conrelid = 'public.promotion_choice_options'::regclass
                and conname = 'promotion_choice_options_no_credit_package') then
    raise notice '352: choice options already refuse credit packages; left alone.'; return; end if;

  alter table public.promotion_choice_options
    add constraint promotion_choice_options_no_credit_package
    check (credit_package_id is null);
end $mig$;

-- ── 3. guards ────────────────────────────────────────────────────────────────
do $mig$
declare v_n int;
begin
  if (select prosrc from pg_proc where proname = 'add_promotion_item'
        and pronamespace = 'public'::regnamespace) not like '%352:%' then
    raise exception '352: a credit package can still be added to a promotion'; end if;

  select count(*) into v_n from pg_proc
   where proname = 'add_promotion_item' and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then
    raise exception '352: % overloads of add_promotion_item; PostgREST needs exactly one', v_n; end if;

  if not has_function_privilege('authenticated', (select oid from pg_proc
       where proname = 'add_promotion_item' and pronamespace = 'public'::regnamespace), 'execute') then
    raise exception '352: staff can no longer edit promotions at all'; end if;

  if (select pg_get_constraintdef(oid) from pg_constraint
       where conrelid = 'public.promotion_choice_groups'::regclass
         and contype = 'c' and pg_get_constraintdef(oid) like '%item_kind%' limit 1) like '%credit_package%' then
    raise exception '352: a choice group can still be set to credit_package'; end if;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.promotion_choice_options'::regclass
                    and conname = 'promotion_choice_options_no_credit_package') then
    raise exception '352: a credit package can still be offered as a choice option'; end if;

  -- The kinds that DO work must still work.
  if (select pg_get_constraintdef(oid) from pg_constraint
       where conrelid = 'public.promotion_choice_groups'::regclass
         and contype = 'c' and pg_get_constraintdef(oid) like '%item_kind%' limit 1)
     not like '%therapy%' then
    raise exception '352: therapy choice groups were removed, and those are issued'; end if;

  raise notice '352 applied: a promotion can no longer promise a package it never grants.';
end $mig$;

notify pgrst, 'reload schema';

-- ── a note on 350 and 351 ────────────────────────────────────────────────────
-- supabase/350_a_package_inside_a_promotion_grants_it.sql and
-- supabase/351_a_promotion_keeps_its_own_money.sql make the offer TRUE instead
-- of withdrawing it. They are finished enough to pass their own tests and have
-- been applied to local and integration databases, but they are NOT applied to
-- production and must not be until the following are resolved:
--
--   * a promotion's granted benefits are recorded with paid_value = 0, and
--     refund_invoice_recorded refuses any benefit with paid_value <= 0 — so
--     such a sale could never be refunded, and record_invoice_benefit_values
--     (the Owner repair path) rejects a promotion line, so it could not be
--     repaired either. The refund basis has to be decoupled from the
--     commission basis in capture_invoice_benefit_values;
--   * create_bundle_exchange pays out promotion_original_total without
--     revoking credit the promotion already granted;
--   * effective_from is not checked when a package is put into a promotion, so
--     an ordinary catalogue schedule can still make settlement fail at the till;
--   * choice-group packages have no sellability guard at all.
--
-- When that work resumes, 352 must be reverted in the same change: it is the
-- thing standing in front of the trap, and the grant is what removes the need
-- for it.
