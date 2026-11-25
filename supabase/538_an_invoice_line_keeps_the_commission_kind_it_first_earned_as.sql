-- 538_an_invoice_line_keeps_the_commission_kind_it_first_earned_as.sql
--
-- AN INVOICE LINE KEEPS THE COMMISSION KIND IT FIRST EARNED AS; AN OWNER CAN CORRECT AN
-- INVOICE'S KEPT RATES AND LINE KINDS, WITH A REASON, A PREVIEW AND AN AUDIT ENTRY
--
--   From the security audit of 17 Nov 2026 (finding M12, its other road, found on 25 Nov 2026).
--   The BEFORE md5s and the relied-on md5s below are those of production after 535 (head
--   20261125092903, function fingerprint d5a6f4f95d0b2a45873d98026ce08a1b/1450). If production
--   differs when this is applied, it refuses and changes nothing. It needs 535 (it builds on
--   535's kept rates, their table and helpers, and 535's earn functions).
--   (The number 538 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 538 comments it writes into the functions below (and so their AFTER md5s,
--   also in scripts/commissions/undo-538.sql and in the suites that know them), and in the name
--   and path of its suite.)
--
-- WHAT WAS WRONG
--
--   535 kept the rates an invoice first earned at, but not what kind each line earned as. Every
--   time an invoice is worked out again (a correction, a reconcile, a refund, an affiliate change,
--   a part payment), earn_invoice_commission and the part-payment preview read each line's kind
--   from the catalogue as it is now: the product's type (own, third party, no commission), for a
--   special product or a rental from the machine-commission cut-off the machine's type (489), and
--   a promotion line's own and third-party values (its items' types and store prices, and the
--   choices' types and prices). So save_product(<id>, '{"product_type":"third_party"}') followed
--   by any correction of an old invoice re-priced its commission, paid-out commission too
--   (through 410's netting). An Owner, a Manager and an Inventory Manager can save products.
--   And a mistaken kept rate (535) could be put right only in SQL.
--
-- THE RULE (the user, 25 Nov 2026)
--
--   1. "Keep each line's type": an invoice line keeps the commission kind it first earned as. A
--      later product change never re-prices older invoices; new sales use the current type.
--   2. "Owner repair, recorded": an Owner can correct one invoice's kept rates and line kinds,
--      with a reason. Its commission is then worked out again the usual way (paid-out commission
--      becomes an adjustment through 410's netting, as for any correction); the change goes in
--      the audit log with the old and new values and the reason. Admin is excluded; a Manager,
--      anyone else and the secret key are refused. A preview shows the commission before and
--      after per tier, and the page asks to confirm after it.
--
-- WHAT THIS DOES (every role refusal is errcode 42501, in the words the pages show)
--
--   * A new table, public.invoice_line_commission_kinds: one row per invoice line that earns by
--     its kind (every line but a credit package, a premium bundle and a late fee, which have none
--     of their own), no-commission lines included: its kind (own, third_party, no_commission),
--     for a promotion line its own and third-party values, whether it came from the backfill, and
--     when. Only its owner (postgres) reads or writes it, as 535's table (row security on, no
--     rule, every grant revoked); it goes with its line and its invoice.
--   * Three helpers only postgres can call (their callers are postgres-owned definers):
--       invoice_line_kinds_for(invoice): each such line's kind as kept, else as earn_invoice_commission
--         read it before 538 (the product's type; from the cut-off a special product's or a
--         rental's machine; a promotion line's own and third-party values from its items and its
--         choices at the invoice's store). Writes nothing.
--       record_invoice_line_kinds(invoice, kinds): keeps the kinds given (or, given none, the ones
--         read now) for every line not kept yet; a line kept already is left as it is.
--       invoice_has_unkept_line_kinds(invoice): whether a line has no kept kind yet.
--   * earn_invoice_commission and invoice_affiliate_commission_preview read each line's kind once,
--     through the first helper, and use it for the rest's base (third-party lines excluded), for
--     the line's own or third-party rate, to leave out no-commission lines, and for a promotion
--     line's split. earn_invoice_commission keeps what it used with 535's rates (once the invoice
--     has a commission row), so the kinds are kept at the same moment and under the same invoice
--     lock as 535's first kept rates; the lock is now taken also while a line has no kept kind.
--     earn_credit_package_commission and earn_premium_bundle_commission keep the invoice's line
--     kinds with 535's rates too (they use none themselves), under the same lock.
--     sync_instalment_commissions (part payments) keeps them with the rates the first time, and
--     also when a line has no kept kind yet, and reads its targets again from what it kept.
--     A line added later (a correction that adds one) has its kind read when the invoice is next
--     worked out with commission rows, and keeps that from then on.
--   * Before anything changes it refuses when a line (not a promotion line, whose rows are of
--     both kinds by design) on an invoice with kept rates has standing commission rows (earned,
--     paid or blocked, adjusting no other row, above 0) of more than one kind: "538: n line(s) on
--     m invoice(s) have standing commission rows of more than one kind, so the kind they earned
--     as is not clear. Look at them before applying; nothing was changed."
--   * Backfill: every line of every invoice with kept rates (535) keeps the kind its standing
--     rows carry (commissions.product_type), else its kind now; a promotion line keeps the own
--     and third-party amounts of its standing tier 1 rows, else its values now. So a line whose
--     product's type changed since it earned keeps the kind it earned as. Production, read only
--     on 25 Nov 2026: 245 standing rows, 140 of them on lines with no product (packages,
--     bundles); exactly 1 standing row (1 invoice, paid out, S$103.20) differs from its product's
--     type now (own, now third_party); the backfill keeps own for it. Every other line keeps the
--     kind the catalogue gives it now, so what each invoice earns when worked out again is as
--     before, and for that one line as it earned.
--   * Three functions for the Owner (an active Owner: require_active_staff() and
--     current_user_role() = 'owner'; anyone else, the secret key included: "Only an Owner can
--     correct an invoice's kept commission rates or line kinds."):
--       invoice_commission_kept_basis(invoice): the kept rates, each line (its name, its kind, whether
--         kept) and the commission now per tier (earned and paid rows, adjustments included).
--       preview_invoice_commission_correction(invoice, rates, kinds): the same correction, worked
--         out and then undone (nothing stays): the old and new rates and kinds, and the commission
--         per tier before and after.
--       correct_invoice_commission_basis(invoice, rates, kinds, reason, request id): keeps the new
--         rates (any of tier1_own, tier1_third, tier2_own, tier2_third, each 0 to 100) and line
--         kinds (own, third_party, no_commission), works the invoice's commission out again
--         (reconcile_invoice_commissions, with 410's netting of anything paid out), and writes the
--         audit entry invoice_commission_basis_corrected (module commission) with the old and new
--         rates and kinds, the totals before and after, and the reason. A repeat with the same
--         request id returns the first answer and changes nothing.
--     Refusals, with nothing changed: no reason, "Give the reason for the correction."; an invoice
--     that keeps no rates, "This invoice has earned no affiliate commission yet, so it keeps no
--     rates or line kinds to correct."; a rate key or value out of place, "A rate is tier1_own,
--     tier1_third, tier2_own or tier2_third, each a number from 0 to 100."; a line not on the
--     invoice or a package, bundle or late-fee line, "That line is not on this invoice, or it is a
--     package, a bundle or a late fee (they have no kind of their own)."; a kind out of place,
--     "A line's kind is own, third_party or no_commission."; nothing different, "Nothing would
--     change: these are the rates and kinds this invoice keeps." The work itself is in
--     invoice_commission_correction_apply(invoice, rates, kinds, reason), which only postgres can
--     call.
--
-- WHAT STAYS
--
--   * What every invoice earns today, and every commission row written.
--   * A credit package's or premium bundle's line: its rates from its sale's snapshot and the
--     fixed third-party classification (package_commission_classification), as before.
--   * Staff commission: it reads no line kind.
--   * A promotion line kept from its standing rows: its own and third-party amounts are the
--     rounded portions its rows carry; worked out again, a portion can differ from the row by a
--     cent where the two portions did not add up to the line exactly.
--   * A line kind corrected by the Owner applies to the whole line (a promotion line's own and
--     third-party values are not corrected here).
--   * The products themselves, save_product, and who may save them.
--
-- UNDO
--
--   scripts/commissions/undo-538.sql (it refuses unless every function here is exactly 538's, the
--   new functions and the table are 538's, and nothing else uses them): each function is put back
--   exactly as it was, the new functions are dropped, and the table is dropped with every kind
--   kept in it (it says how many, and how many differ from the catalogue then: those lines would
--   be re-priced at their next correction). Commission rows already written keep their amounts.
--   Run it before scripts/commissions/undo-535.sql, which refuses while 538 uses its table and
--   helpers. A later migration changing any of these must pin 538's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/commissions/tests/line-keeps-its-kind-538.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched and new ones rely on, as tested: the caller's role and active-staff
  -- check, the audit writer, the reconcile the correction runs, a promotion's items, 535's two
  -- helpers, and the part-payment test and targets (which call the patched preview).
  c_relied constant text[] := array[
    'current_user_role()',
    'require_active_staff(text[])',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'reconcile_invoice_commissions(uuid,text)',
    'promotion_commission_items(uuid,uuid,integer,text)',
    'invoice_affiliate_rates_for(uuid)',
    'record_invoice_affiliate_rates(uuid,numeric,numeric,numeric,numeric)',
    'invoice_instalment_commission_active(uuid)',
    'invoice_instalment_commission_targets(uuid)'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    '877b3aa74cea559881979bb161c450e2',
    'c705c733e213a27f0dc32d54322cc855',
    '3c267728e215d17ebeb9cfe9cb7db47c',
    '4cd784251e0c6a5861b004d91e50389c',
    '64e6ed85a8f169477fc85bd8452da453',
    'ae5132e23be0b0acbdec3d92e500bd4c',
    '1cfc14db26aaef668cee010fadbddfe3',
    'dc47c3c7b9e41d67b89713fce2a4b480'];
  -- The table, made first (the helpers read it).
  c_table_def constant text :=
$d$create table public.invoice_line_commission_kinds (
  invoice_item_id uuid primary key references public.invoice_items(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  kind text not null constraint invoice_line_commission_kinds_kind check (kind in ('own', 'third_party', 'no_commission')),
  own_value numeric constraint invoice_line_commission_kinds_own_value check (own_value is null or own_value >= 0),
  third_value numeric constraint invoice_line_commission_kinds_third_value check (third_value is null or third_value >= 0),
  backfilled boolean not null default false,
  recorded_at timestamptz not null default now()
)$d$;
  c_table_comment constant text :=
    '538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line''s type"): the commission kind each '
    'invoice line first earned as (own, third_party, no_commission; a promotion line''s own and third-party values), kept '
    'by record_invoice_line_kinds and read by invoice_line_kinds_for in earn_invoice_commission and the part-payment '
    'preview. backfilled: kept by 538 for an invoice with kept rates (535). Corrected only by an Owner '
    '(correct_invoice_commission_basis). No login reads or writes it.';
  c_table_acl constant text := 'postgres=arwdDxtm/postgres';
  -- The new functions: their signatures, text and grants.
  c_new_sig constant text[] := array[
    'invoice_line_kinds_for(uuid)',
    'invoice_has_unkept_line_kinds(uuid)',
    'record_invoice_line_kinds(uuid,jsonb)',
    'invoice_commission_correction_apply(uuid,jsonb,jsonb,text)',
    'invoice_commission_kept_basis(uuid)',
    'preview_invoice_commission_correction(uuid,jsonb,jsonb)',
    'correct_invoice_commission_basis(uuid,jsonb,jsonb,text,uuid)'];
  c_new_def constant text[] := array[
$d$CREATE OR REPLACE FUNCTION public.invoice_line_kinds_for(p_invoice_id uuid)
 RETURNS TABLE(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type"):
  -- each invoice line that earns by its kind (all but a credit package, a premium bundle and a late
  -- fee), with the kind it keeps (invoice_line_commission_kinds), else the kind
  -- earn_invoice_commission read before 538: the product's type, from the machine-commission
  -- cut-off (489) a special product's or a rental's machine's type, and for a promotion line its
  -- own and third-party values from its items (promotion_commission_items) and its choices at
  -- the invoice's store. Writes nothing.
  select ii.id,
         coalesce(k.kind,
           case when coalesce(i.created_at >= a.machine_commission_from, false)
                     and ii.line_kind in ('special_product', 'rental')
                then coalesce(mp.product_type::text, 'own')
                else coalesce(p.product_type::text, 'own') end),
         case when k.invoice_item_id is not null then k.own_value
              when ii.line_kind = 'promotion' then pc.own_value + sel.own_value end,
         case when k.invoice_item_id is not null then k.third_value
              when ii.line_kind = 'promotion' then pc.third_value + sel.third_value end,
         k.invoice_item_id is not null
    from public.invoice_items ii
    join public.invoices i on i.id = ii.invoice_id
    join public.app_settings a on a.id = true
    left join public.invoice_line_commission_kinds k on k.invoice_item_id = ii.id
    left join public.products p on p.id = ii.product_id
    left join public.special_products sp on sp.id = ii.special_product_id
    left join public.products mp on mp.id = sp.product_id
    left join lateral (
      select coalesce(sum(case when x.ptype = 'third_party' then 0 else x.original_value end), 0) as own_value,
             coalesce(sum(case when x.ptype = 'third_party' then x.original_value else 0 end), 0) as third_value
        from public.promotion_commission_items(ii.promotion_id, i.store_id, ii.quantity, ii.price_mode) x
       where ii.line_kind = 'promotion' and k.invoice_item_id is null) pc on true
    left join lateral (
      select coalesce(sum(case
               when s.product_id is not null and coalesce(pp.product_type::text, 'own') <> 'third_party'
                 then coalesce(spp.selling_price, 0) * s.quantity
               when s.voucher_id is not null
                 then coalesce(vsp.selling_price, vv.selling_price, 0) * s.quantity
               else 0 end), 0) as own_value,
             coalesce(sum(case
               when s.product_id is not null and coalesce(pp.product_type::text, 'own') = 'third_party'
                 then coalesce(spp.selling_price, 0) * s.quantity
               else 0 end), 0) as third_value
        from public.invoice_promotion_selections s
        left join public.products pp on pp.id = s.product_id
        left join public.store_product_prices spp on spp.store_id = i.store_id and spp.product_id = s.product_id
          and spp.is_active = true and spp.deleted_at is null
        left join public.vouchers vv on vv.id = s.voucher_id
        left join public.voucher_store_prices vsp on vsp.store_id = i.store_id and vsp.voucher_id = s.voucher_id
          and vsp.deleted_at is null
       where s.invoice_item_id = ii.id and ii.line_kind = 'promotion' and k.invoice_item_id is null) sel on true
   where ii.invoice_id = p_invoice_id
     and ii.line_kind::text not in ('credit_package', 'premium_bundle', 'late_fee')
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.invoice_has_unkept_line_kinds(p_invoice_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 538 (security audit of 17 Nov 2026, M12): whether a line of the invoice that earns by its kind
  -- has no kept kind yet (the invoice has not earned, or the line was added since).
  select exists (select 1 from public.invoice_items ii
                  where ii.invoice_id = p_invoice_id
                    and ii.line_kind::text not in ('credit_package', 'premium_bundle', 'late_fee')
                    and not exists (select 1 from public.invoice_line_commission_kinds k where k.invoice_item_id = ii.id))
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.record_invoice_line_kinds(p_invoice_id uuid, p_kinds jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type"):
  -- keeps, for every line not kept yet, the kind given (as invoice_line_kinds_for gave it to the
  -- run that earned), or, given none, its kind now. A line kept already is left as it is.
  insert into public.invoice_line_commission_kinds (invoice_item_id, invoice_id, kind, own_value, third_value)
  select k.invoice_item_id, p_invoice_id, k.kind, k.own_value, k.third_value
    from jsonb_to_recordset(coalesce(p_kinds,
           (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from public.invoice_line_kinds_for(p_invoice_id) x)))
         as k(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
   where not coalesce(k.kept, false)
     and exists (select 1 from public.invoice_items ii where ii.id = k.invoice_item_id and ii.invoice_id = p_invoice_id)
  on conflict (invoice_item_id) do nothing
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.invoice_commission_correction_apply(p_invoice_id uuid, p_rates jsonb, p_kinds jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_old_rates jsonb; v_new_rates jsonb; v_old_kinds jsonb; v_new_kinds jsonb;
  v_before jsonb; v_after jsonb; r record; e record; v numeric;
begin
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Owner repair, recorded"): an
  -- invoice's kept rates and line kinds corrected, and its commission worked out again the usual
  -- way (reconcile_invoice_commissions: anything paid out is netted, 410). Called by
  -- correct_invoice_commission_basis, and by preview_invoice_commission_correction, which undoes it.
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found.'; end if;
  if not exists (select 1 from public.invoice_affiliate_rates k where k.invoice_id = p_invoice_id) then
    raise exception 'This invoice has earned no affiliate commission yet, so it keeps no rates or line kinds to correct.'; end if;
  -- A line added since the invoice last earned is kept first, as it is now.
  perform public.record_invoice_line_kinds(p_invoice_id, null);
  select jsonb_build_object('tier1_own', k.tier1_own_rate, 'tier1_third', k.tier1_third_rate,
                            'tier2_own', k.tier2_own_rate, 'tier2_third', k.tier2_third_rate)
    into v_old_rates from public.invoice_affiliate_rates k where k.invoice_id = p_invoice_id;
  select coalesce(jsonb_object_agg(k.invoice_item_id::text, k.kind), '{}'::jsonb) into v_old_kinds
    from public.invoice_line_commission_kinds k where k.invoice_id = p_invoice_id;
  v_new_rates := v_old_rates;
  for r in select x.key, x.value from jsonb_each(coalesce(p_rates, '{}'::jsonb)) x loop
    begin
      v := (r.value #>> '{}')::numeric;
    exception when others then
      v := null;
    end;
    if r.key not in ('tier1_own', 'tier1_third', 'tier2_own', 'tier2_third') or v is null or v < 0 or v > 100 then
      raise exception 'A rate is tier1_own, tier1_third, tier2_own or tier2_third, each a number from 0 to 100.'; end if;
    v_new_rates := v_new_rates || jsonb_build_object(r.key, v);
  end loop;
  v_new_kinds := v_old_kinds;
  for e in select x.invoice_item_id, x.kind
             from jsonb_to_recordset(case when jsonb_typeof(p_kinds) = 'array' then p_kinds else '[]'::jsonb end)
                  as x(invoice_item_id uuid, kind text) loop
    if e.invoice_item_id is null or not (v_old_kinds ? e.invoice_item_id::text) then
      raise exception 'That line is not on this invoice, or it is a package, a bundle or a late fee (they have no kind of their own).'; end if;
    if e.kind is null or e.kind not in ('own', 'third_party', 'no_commission') then
      raise exception 'A line''s kind is own, third_party or no_commission.'; end if;
    v_new_kinds := v_new_kinds || jsonb_build_object(e.invoice_item_id::text, e.kind);
  end loop;
  if v_new_rates = v_old_rates and v_new_kinds = v_old_kinds then
    raise exception 'Nothing would change: these are the rates and kinds this invoice keeps.'; end if;
  select jsonb_build_object('tier1', coalesce(sum(c.commission_amount) filter (where c.tier::text = 'tier1'), 0),
                            'tier2', coalesce(sum(c.commission_amount) filter (where c.tier::text = 'tier2'), 0))
    into v_before from public.commissions c where c.invoice_id = p_invoice_id and c.status::text in ('earned', 'paid');
  update public.invoice_affiliate_rates
     set tier1_own_rate = (v_new_rates ->> 'tier1_own')::numeric, tier1_third_rate = (v_new_rates ->> 'tier1_third')::numeric,
         tier2_own_rate = (v_new_rates ->> 'tier2_own')::numeric, tier2_third_rate = (v_new_rates ->> 'tier2_third')::numeric
   where invoice_id = p_invoice_id and v_new_rates is distinct from v_old_rates;
  update public.invoice_line_commission_kinds k
     set kind = v_new_kinds ->> k.invoice_item_id::text
   where k.invoice_id = p_invoice_id and k.kind is distinct from v_new_kinds ->> k.invoice_item_id::text;
  perform public.reconcile_invoice_commissions(p_invoice_id,
    'Commission rates or line kinds corrected by the Owner: ' || coalesce(p_reason, ''));
  select jsonb_build_object('tier1', coalesce(sum(c.commission_amount) filter (where c.tier::text = 'tier1'), 0),
                            'tier2', coalesce(sum(c.commission_amount) filter (where c.tier::text = 'tier2'), 0))
    into v_after from public.commissions c where c.invoice_id = p_invoice_id and c.status::text in ('earned', 'paid');
  return jsonb_build_object('invoice_no', v_inv.invoice_no,
    'old', jsonb_build_object('rates', v_old_rates, 'kinds', v_old_kinds),
    'new', jsonb_build_object('rates', v_new_rates, 'kinds', v_new_kinds),
    'before', v_before, 'after', v_after);
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.invoice_commission_kept_basis(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Owner repair, recorded"):
  -- for the Owner's correction window, an invoice's kept rates (none: it has not earned), each
  -- line's kind and whether it is kept, and its commission now per tier (earned and paid rows,
  -- adjustments included).
  perform public.require_active_staff();
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can correct an invoice''s kept commission rates or line kinds.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'rates', (select jsonb_build_object('tier1_own', k.tier1_own_rate, 'tier1_third', k.tier1_third_rate,
                                        'tier2_own', k.tier2_own_rate, 'tier2_third', k.tier2_third_rate)
                from public.invoice_affiliate_rates k where k.invoice_id = p_invoice_id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id', k.invoice_item_id,
                                 'name', coalesce(ii.item_name_snapshot, pr.name, ii.line_kind::text),
                                 'line_kind', ii.line_kind, 'kind', k.kind, 'kept', k.kept) order by ii.id), '[]'::jsonb)
                from public.invoice_line_kinds_for(p_invoice_id) k
                join public.invoice_items ii on ii.id = k.invoice_item_id
                left join public.products pr on pr.id = ii.product_id),
    'totals', (select jsonb_build_object('tier1', coalesce(sum(c.commission_amount) filter (where c.tier::text = 'tier1'), 0),
                                         'tier2', coalesce(sum(c.commission_amount) filter (where c.tier::text = 'tier2'), 0))
                 from public.commissions c where c.invoice_id = p_invoice_id and c.status::text in ('earned', 'paid')));
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.preview_invoice_commission_correction(p_invoice_id uuid, p_rates jsonb, p_kinds jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Owner repair, recorded"): the
  -- correction, worked out exactly as correct_invoice_commission_basis does it, then undone: nothing
  -- stays. The old and new rates and kinds, and the commission per tier before and after.
  perform public.require_active_staff();
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can correct an invoice''s kept commission rates or line kinds.' using errcode = '42501'; end if;
  begin
    v := public.invoice_commission_correction_apply(p_invoice_id, p_rates, p_kinds, 'preview');
    raise exception using errcode = 'P0538', message = '538 preview: undone';
  exception when sqlstate 'P0538' then
    null;
  end;
  return v || jsonb_build_object('preview', true);
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.correct_invoice_commission_basis(p_invoice_id uuid, p_rates jsonb, p_kinds jsonb, p_reason text, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; v_prev jsonb;
begin
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Owner repair, recorded"): an
  -- Owner corrects one invoice's kept rates and line kinds, with a reason; its commission is worked
  -- out again (anything paid out netted, 410) and the change is in the audit log with the old and
  -- new values, the totals before and after, and the reason. A repeat with the same request id
  -- returns the first answer.
  perform public.require_active_staff();
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can correct an invoice''s kept commission rates or line kinds.' using errcode = '42501'; end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'Give the reason for the correction.'; end if;
  if p_request_id is not null then
    select a.new_data -> 'result' into v_prev from public.audit_logs a
     where a.record_id = p_invoice_id and a.action = 'invoice_commission_basis_corrected'
       and a.new_data ->> 'request_id' = p_request_id::text
     order by a.created_at limit 1;
    if v_prev is not null then return v_prev; end if;
  end if;
  v := public.invoice_commission_correction_apply(p_invoice_id, p_rates, p_kinds, btrim(p_reason));
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_commission_basis_corrected', v -> 'old',
    (v -> 'new') || jsonb_build_object('before', v -> 'before', 'after', v -> 'after',
                                        'request_id', p_request_id, 'result', v),
    'commission', btrim(p_reason), (select i.store_id from public.invoices i where i.id = p_invoice_id));
  return v;
end $function$
$d$];
  c_new_md5 constant text[] := array['bb51dfc8861272bc615dd0630f2a9acf', 'c290de63f7dafbee0ac84cfd7c3260a8', '125d4d8fd4311f4b6683e73a99f03425', '7eef1a9a0af66041c3c9fda94a168f09', '744568fa22216bd52b92810e46a82165', '96d01915bbf6787d773ece636fb654cf', '4e8433353b98a5b824e00b39eda11c18'];
  c_new_acl constant text[] := array[
    'postgres=X/postgres', 'postgres=X/postgres', 'postgres=X/postgres', 'postgres=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  -- The functions patched.
  c_sig constant text[] := array[
    'earn_invoice_commission(uuid)',
    'invoice_affiliate_commission_preview(uuid)',
    'earn_credit_package_commission(uuid)',
    'earn_premium_bundle_commission(uuid)',
    'sync_instalment_commissions(uuid,text,date,boolean,boolean)'];
  c_before constant text[] := array[
    '762c06868e2c2256f008b9468b8a255b',
    '927b9e2129e354c0f061a713083cdb54',
    '44d10e4bcceb9a94080f1802c1da946f',
    '86ea3b1215ed6fd896bfd63ceba21152',
    '98fbe647100e8890957f098c6d90fca4'];
  c_after constant text[] := array['8d7ccdee4eae2359b56995ebf60dbcfa', 'df92dacb660319a7c4ae44b439b1adaf', 'd2d6c3a32c89a329852d2680aa66e504', '5bb0f5bf338a73f4b040dac2cf9e905c', '1f56177897bb6b67c276626128184c86'];
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- The patches, each found exactly once in its function (1 earn_invoice_commission,
  -- 2 invoice_affiliate_commission_preview, 3 earn_credit_package_commission,
  -- 4 earn_premium_bundle_commission, 5 sync_instalment_commissions): the kinds' variable; the
  -- kinds read once; the rest's base; the loop's lines; a promotion line's values; the lock (also
  -- while a line has no kept kind); keeping the kinds with the rates.
  c_fn constant int[] := array[1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 1, 3, 4, 3, 4, 5];
  c_anchor constant text[] := array[
$a$  v_machine_new boolean;  -- 489
$a$,
$a$  v_machine_new boolean;  -- 489
$a$,
$a$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$a$,
$a$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$a$,
$a$  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  left join public.special_products sp on sp.id = ii.special_product_id
  left join public.products mp on mp.id = sp.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental')
             and coalesce(mp.product_type::text, 'own') = 'third_party');
$a$,
$a$  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  left join public.special_products sp on sp.id = ii.special_product_id
  left join public.products mp on mp.id = sp.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental')
             and coalesce(mp.product_type::text, 'own') = 'third_party');
$a$,
$a$    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           case when v_machine_new and ii.line_kind in ('special_product','rental')
                then coalesce(mp.product_type::text, 'own')
                else coalesce(p.product_type::text, 'own') end as ptype,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    left join public.special_products sp on sp.id = ii.special_product_id
    left join public.products mp on mp.id = sp.product_id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and case when v_machine_new and ii.line_kind in ('special_product','rental')
               then coalesce(mp.product_type::text, 'own')
               else coalesce(p.product_type::text, 'own') end <> 'no_commission'
$a$,
$a$    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           case when v_machine_new and ii.line_kind in ('special_product','rental')
                then coalesce(mp.product_type::text, 'own')
                else coalesce(p.product_type::text, 'own') end as ptype,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    left join public.special_products sp on sp.id = ii.special_product_id
    left join public.products mp on mp.id = sp.product_id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and case when v_machine_new and ii.line_kind in ('special_product','rental')
               then coalesce(mp.product_type::text, 'own')
               else coalesce(p.product_type::text, 'own') end <> 'no_commission'
$a$,
$a$      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity, v_item.price_mode);

      select
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') <> 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          when s.voucher_id is not null
            then coalesce(vsp.selling_price, vv.selling_price, 0) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          else 0 end),0)
        into v_sel_own, v_sel_third
      from public.invoice_promotion_selections s
      left join public.products pp on pp.id = s.product_id
      left join public.store_product_prices spp on spp.store_id = v_inv.store_id and spp.product_id = s.product_id
        and spp.is_active = true and spp.deleted_at is null
      left join public.vouchers vv on vv.id = s.voucher_id
      left join public.voucher_store_prices vsp on vsp.store_id = v_inv.store_id and vsp.voucher_id = s.voucher_id
        and vsp.deleted_at is null
      where s.invoice_item_id = v_item.id;
$a$,
$a$      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity, v_item.price_mode);

      select
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') <> 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          when s.voucher_id is not null
            then coalesce(vsp.selling_price, vv.selling_price, 0) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          else 0 end),0)
        into v_sel_own, v_sel_third
      from public.invoice_promotion_selections s
      left join public.products pp on pp.id = s.product_id
      left join public.store_product_prices spp on spp.store_id = v_inv.store_id and spp.product_id = s.product_id
        and spp.is_active = true and spp.deleted_at is null
      left join public.vouchers vv on vv.id = s.voucher_id
      left join public.voucher_store_prices vsp on vsp.store_id = v_inv.store_id and vsp.voucher_id = s.voucher_id
        and vsp.deleted_at is null
      where s.invoice_item_id = v_item.id;
$a$,
$a$  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform 1 from public.invoices i535 where i535.id = p_invoice_id for update;
$a$,
$a$    perform public.record_invoice_affiliate_rates(p_invoice_id, v_rate_t1_own, v_rate_t1_third,
      v_rate_t2_own, v_rate_t2_third);
$a$,
$a$  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$a$,
$a$  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$a$,
$a$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$a$,
$a$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$a$,
$a$     and not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, r535.tier1_own, r535.tier1_third,
              r535.tier2_own, r535.tier2_third)
       from public.invoice_affiliate_rates_for(p_invoice_id) r535;
$a$];
  c_new constant text[] := array[
$n$  v_machine_new boolean;  -- 489
  v538_kinds jsonb;  -- 538: each line's commission kind, kept or read now
$n$,
$n$  v_machine_new boolean;  -- 489
  v538_kinds jsonb;  -- 538: each line's commission kind, kept or read now
$n$,
$n$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type"):
  -- each line's commission kind (own, third party, no commission; a special product's or a
  -- rental's machine; a promotion line's own and third-party values) is the one kept for it
  -- when the invoice first earned (invoice_line_commission_kinds), else read from the catalogue
  -- now, as before, and kept below once the invoice has a commission row. Read once, here, so
  -- what is kept is exactly what this run used.
  select coalesce(jsonb_agg(to_jsonb(k538)), '[]'::jsonb) into v538_kinds
    from public.invoice_line_kinds_for(p_invoice_id) k538;
$n$,
$n$    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
  -- 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type"):
  -- each line's commission kind (own, third party, no commission; a special product's or a
  -- rental's machine; a promotion line's own and third-party values) is the one kept for it
  -- when the invoice first earned (invoice_line_commission_kinds), else read from the catalogue
  -- now, as before, and kept below once the invoice has a commission row. Read once, here, so
  -- what is kept is exactly what this run used.
  select coalesce(jsonb_agg(to_jsonb(k538)), '[]'::jsonb) into v538_kinds
    from public.invoice_line_kinds_for(p_invoice_id) k538;
$n$,
$n$  -- 538: the line's kept kind (or its kind now) in place of the catalogue's.
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
    on k538.invoice_item_id = ii.id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and k538.kind = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental') and k538.kind = 'third_party');
$n$,
$n$  -- 538: the line's kept kind (or its kind now) in place of the catalogue's.
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
    on k538.invoice_item_id = ii.id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and k538.kind = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental') and k538.kind = 'third_party');
$n$,
$n$    -- 538: each line's kind (and a promotion line's own and third-party values) as kept, or now.
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           k538.kind as ptype, k538.own_value as own538, k538.third_value as third538,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
      on k538.invoice_item_id = ii.id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and k538.kind <> 'no_commission'
$n$,
$n$    -- 538: each line's kind (and a promotion line's own and third-party values) as kept, or now.
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           k538.kind as ptype, k538.own_value as own538, k538.third_value as third538,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    join jsonb_to_recordset(v538_kinds) as k538(invoice_item_id uuid, kind text, own_value numeric, third_value numeric, kept boolean)
      on k538.invoice_item_id = ii.id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and ii.line_kind::text <> 'late_fee'  -- 396: a rental's late fee earns none
      and k538.kind <> 'no_commission'
$n$,
$n$      -- 538: the promotion line's own and third-party values as kept, or worked out now from
      -- its items and choices as before (invoice_line_kinds_for).
      v_own_orig := coalesce(v_item.own538, 0); v_third_orig := coalesce(v_item.third538, 0);
      v_sel_own := 0; v_sel_third := 0;
$n$,
$n$      -- 538: the promotion line's own and third-party values as kept, or worked out now from
      -- its items and choices as before (invoice_line_kinds_for).
      v_own_orig := coalesce(v_item.own538, 0); v_third_orig := coalesce(v_item.third538, 0);
      v_sel_own := 0; v_sel_third := 0;
$n$,
$n$  -- 538: also until every line's kind is kept.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id)
     or public.invoice_has_unkept_line_kinds(p_invoice_id) then
    perform 1 from public.invoices i535 where i535.id = p_invoice_id for update;
$n$,
$n$    perform public.record_invoice_affiliate_rates(p_invoice_id, v_rate_t1_own, v_rate_t1_third,
      v_rate_t2_own, v_rate_t2_third);
    -- 538: and every line's kind, as this run used it (a line added later: its kind now).
    perform public.record_invoice_line_kinds(p_invoice_id, v538_kinds);
$n$,
$n$  -- 538: also until every line's kind is kept.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id)
     or public.invoice_has_unkept_line_kinds(s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$n$,
$n$  -- 538: also until every line's kind is kept.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id)
     or public.invoice_has_unkept_line_kinds(s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
$n$,
$n$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
    -- 538: and every line's kind on the invoice, as it is now where none is kept.
    perform public.record_invoice_line_kinds(s.invoice_id, null);
$n$,
$n$    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
    -- 538: and every line's kind on the invoice, as it is now where none is kept.
    perform public.record_invoice_line_kinds(s.invoice_id, null);
$n$,
$n$     -- 538: also the first time a line's kind is not kept yet (a line added later)
     and (not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id)
          or public.invoice_has_unkept_line_kinds(p_invoice_id)) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, r535.tier1_own, r535.tier1_third,
              r535.tier2_own, r535.tier2_third)
       from public.invoice_affiliate_rates_for(p_invoice_id) r535;
    -- 538: and every line's kind, as it is now where none is kept; the targets are read again below.
    perform public.record_invoice_line_kinds(p_invoice_id, null);
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[5]);
  v_done int := 0; v_new_done int := 0; v_table_done boolean;
  v_bad text := ''; v_off int; v_off_inv int; v_n int; v_lines int; v_differ int; v_differ_inv int;
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function or table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '538: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regclass('public.invoice_affiliate_rates') is null or to_regclass('public.invoice_items') is null
     or to_regclass('public.commissions') is null or to_regclass('public.products') is null
     or to_regclass('public.special_products') is null or to_regclass('public.invoice_promotion_selections') is null then
    raise exception '538: a table it reads (invoice_affiliate_rates, invoice_items, commissions, products, special_products, invoice_promotion_selections) is missing'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '538: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception '538: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) = c_before[i] then
      v_def[i] := d;
    else
      raise exception '538: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is not null then
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
        raise exception '538: a function public.% is there, but not 538''s. Re-read it before applying.', c_new_sig[i]; end if;
      v_new_done := v_new_done + 1;
    end if;
  end loop;
  v_table_done := to_regclass('public.invoice_line_commission_kinds') is not null;
  if v_table_done and obj_description(to_regclass('public.invoice_line_commission_kinds'), 'pg_class') is distinct from c_table_comment then
    raise exception '538: a table public.invoice_line_commission_kinds is there, but not 538''s. Re-read it before applying.'; end if;
  if v_done = cardinality(c_sig) and v_new_done = cardinality(c_new_sig) and v_table_done then
    raise exception '538 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_new_done > 0 or v_table_done then
    raise exception '538: only part of it is in on this database (% of % functions patched, % of % new functions, table %). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), v_new_done, cardinality(c_new_sig), case when v_table_done then 'there' else 'missing' end; end if;
  -- The backfill keeps, for each line, the kind its standing rows carry; a line (not a promotion
  -- line) whose standing rows carry more than one kind has no clear kind, and it refuses.
  select count(*), count(distinct ii.invoice_id) into v_off, v_off_inv
    from public.invoice_items ii
    join public.invoice_affiliate_rates r on r.invoice_id = ii.invoice_id
   where ii.line_kind::text not in ('promotion', 'credit_package', 'premium_bundle', 'late_fee')
     and (select count(distinct c.product_type::text) from public.commissions c
           where c.invoice_item_id = ii.id and c.status::text in ('earned', 'paid', 'blocked')
             and c.adjusts_commission_id is null and c.commission_amount > 0) > 1;
  if v_off > 0 then
    raise exception '538: % line(s) on % invoice(s) have standing commission rows of more than one kind, so the kind they earned as is not clear. Look at them before applying; nothing was changed.',
      v_off, v_off_inv; end if;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '538: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_after[i] then
      v_bad := v_bad || format(' %s=%s', c_sig[i], md5(v_def[i])); end if;
    if position('538 (security audit' in v_def[i]) = 0 and position('-- 538:' in v_def[i]) = 0 then
      raise exception '538: the patched text of public.% has no 538 marker', c_sig[i]; end if;
  end loop;
  if v_bad <> '' then
    raise exception '538: the patched text is not the tested one:%', v_bad; end if;

  -- 2. Install: the table, then the new functions (the patched ones call them)
  execute c_table_def;
  create index invoice_line_commission_kinds_invoice on public.invoice_line_commission_kinds (invoice_id);
  execute format('comment on table public.invoice_line_commission_kinds is %L', c_table_comment);
  alter table public.invoice_line_commission_kinds enable row level security;
  revoke all on table public.invoice_line_commission_kinds from public, anon, authenticated, service_role;
  for i in 1 .. cardinality(c_new_sig) loop
    execute c_new_def[i];
    if c_new_acl[i] = 'postgres=X/postgres' then
      execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
    else
      execute format('revoke all on function public.%s from public, anon', c_new_sig[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', c_new_sig[i]);
    end if;
  end loop;
  -- The backfill: every line of every invoice with kept rates keeps the kind its standing rows
  -- carry, else its kind now; a promotion line the own and third-party amounts of its standing
  -- tier 1 rows, else its values now.
  insert into public.invoice_line_commission_kinds (invoice_item_id, invoice_id, kind, own_value, third_value, backfilled)
  select k.invoice_item_id, r.invoice_id,
         case when ii.line_kind::text <> 'promotion' and lr.n > 0 then lr.kind1 else k.kind end,
         case when ii.line_kind::text = 'promotion' and lr.n1 > 0 then lr.own1 else k.own_value end,
         case when ii.line_kind::text = 'promotion' and lr.n1 > 0 then lr.third1 else k.third_value end,
         true
    from public.invoice_affiliate_rates r
   cross join lateral public.invoice_line_kinds_for(r.invoice_id) k
    join public.invoice_items ii on ii.id = k.invoice_item_id
   cross join lateral (
     select count(*) as n, min(c.product_type::text) as kind1,
            count(*) filter (where c.tier::text = 'tier1') as n1,
            coalesce(sum(c.line_amount) filter (where c.tier::text = 'tier1' and c.product_type::text <> 'third_party'), 0) as own1,
            coalesce(sum(c.line_amount) filter (where c.tier::text = 'tier1' and c.product_type::text = 'third_party'), 0) as third1
       from public.commissions c
      where c.invoice_item_id = ii.id and c.status::text in ('earned', 'paid', 'blocked')
        and c.adjusts_commission_id is null and c.commission_amount > 0) lr;
  get diagnostics v_n = row_count;
  select count(*), count(distinct k.invoice_id) into v_differ, v_differ_inv
    from public.invoice_line_commission_kinds k
    join public.invoice_items ii on ii.id = k.invoice_item_id
    left join public.products p on p.id = ii.product_id
   where ii.line_kind::text = 'product' and k.kind is distinct from coalesce(p.product_type::text, 'own');
  raise notice '538: % line(s) of % invoice(s) with kept rates keep their kind; % product line(s) on % invoice(s) keep a kind other than their product''s type now (the kind they earned as).',
    v_n, (select count(*) from public.invoice_affiliate_rates), v_differ, v_differ_inv;
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;

  -- 3. Checks after installing
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_class c, unnest(c.relacl) x where c.oid = 'public.invoice_line_commission_kinds'::regclass) is distinct from c_table_acl
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.invoice_line_commission_kinds'::regclass) then
    raise exception '538: public.invoice_line_commission_kinds can be read or written by a login or the service role'; end if;
  select count(*) into v_lines from public.invoice_items ii
    join public.invoice_affiliate_rates r on r.invoice_id = ii.invoice_id
   where ii.line_kind::text not in ('credit_package', 'premium_bundle', 'late_fee');
  if v_lines <> v_n then
    raise exception '538: the backfill does not cover every line of the invoices with kept rates (% of %)', v_n, v_lines; end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '538: public.% was made with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i]
       or has_function_privilege('anon', to_regprocedure('public.' || c_new_sig[i]), 'execute') then
      raise exception '538: the grants of public.% are not the tested ones', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '538: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl then
      raise exception '538: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '538: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
