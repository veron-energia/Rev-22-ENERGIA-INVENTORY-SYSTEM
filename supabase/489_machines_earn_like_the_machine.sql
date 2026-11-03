-- 489_machines_earn_like_the_machine.sql
--
-- A SPECIAL PRODUCT OR A RENTAL EARNS COMMISSION LIKE THE MACHINE IT IS,
-- FROM THE MOMENT THIS IS APPLIED; WHAT WAS ALREADY EARNED STAYS
-- (the user's answers in chat, 3 Nov 2026: "Third-party rate, like the
-- machine" and "Keep what's already earned")
--
-- (The number 489 is this file's name, its errors' prefix, its self-test's
-- error code P0489 and its suite's; if it changes at commit, change it in
-- these places alone.)
--
-- WHAT WAS WRONG
--
--   A special product, sold or rented, sits on its invoice line with no
--   product_id (invoice_items.special_product_id instead), so
--   earn_invoice_commission's coalesce(p.product_type, 'own') counted every
--   such line as our own: Tier 1 at our own rate (15% on 3 Nov 2026). Yet 9
--   of the 10 special products in use are linked (special_products.
--   product_id) to third-party machines, and the same machine sold as a
--   product line earns the third-party rate (4.5%). On 3 Nov: 12 special
--   product lines and 10 rental lines of third-party machines, 4 rental
--   lines of our own one.
--
-- WHAT THIS DOES
--
--   app_settings.machine_commission_from (new) is set to the moment this file
--   is applied. A special-product or rental line on an invoice CREATED from
--   then on takes the product type of the machine its special product is
--   linked to, exactly as that machine sold as a product line would:
--   * third-party: Tier 1 at the third-party rate and Tier 2 its share of
--     that, and no share of the invoice's Discount Voucher or Save Earth (as
--     any third-party line);
--   * no commission: nothing;
--   * our own: our own rate, as before.
--   A special product linked to no machine stays ours, as before.
--
--   An invoice created before keeps the rule it was sold under for good,
--   also when a refund, cancellation, reopening, correction, payment change
--   or reconcile recalculates it later: the rule is decided inside
--   earn_invoice_commission from the invoice's created_at, which cannot
--   change (invoice_created_at_immutable). So nothing already earned or shown
--   to an affiliate is cut, a part-paid invoice that straddles the change
--   included. invoice_affiliate_commission_preview, which the part-payment
--   layer (357) and the correction preview read, changes the same way, so
--   part payments, previews and settlement agree.
--
-- WHAT IT DOES NOT DO
--
--   * No commission row is recalculated or touched. The 3 special-product
--     lines earned at 15% and unpaid on 3 Nov (S$371.47) stay as they are.
--   * A rental's late fee still earns nothing (396). An old-style rental with
--     no invoice still earns nothing.
--   * Promotions cannot hold a special product (promotion_items has no such
--     column), so promotions are unchanged; so are products, vouchers,
--     therapy, tickets, Credit Packages and Premium Bundles.
--   * The other questions found on 3 Nov are left for the Owner: package and
--     bundle commission not checking that the earner is an active affiliate,
--     blind boxes counted as ours, the MWOL promotion counted as ours at
--     Adelphi, recalculation with today's referrer and rates.
--
-- UNDO
--
--   update public.app_settings set machine_commission_from = null where id = true;
--   With no cut-off every invoice is on the old rule again, through the same
--   functions: v_machine_new is false for all, and each change below is then
--   a no-op. Nothing else needs undoing; the column can stay.
--
-- DEPLOY ORDER (each step with the user's go-ahead in chat)
--
--   production now (479 + 481 in: e15db582, 1399 functions) -> 489.
--   * 487 and 488 (another session, paused) do not replace these two
--     functions. 490 (the Rules page) does not depend on this file, but
--     states its rule.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the second run changes nothing ("already this version").
--   2. Apply. It checks itself and runs its self-test.
--   3. No page change.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * both functions are their BEFORE (replaced; the texts written here have
--     the tested AFTER md5s) or their AFTER (left alone), and the columns the
--     change reads are there;
--   * the column is added if missing and set only when empty, so a second
--     run keeps the first run's moment;
--   * afterwards: the md5s are the AFTER ones and the grants are as before
--     (compared as sets);
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0489, so it leaves no row): made-up machines (ours, third-party, no
--     commission) and special products linked to them and one linked to
--     none, on two made-up invoices, one created before the cut-off and one
--     after; what each line earns, through the preview and through
--     earn_invoice_commission, which must agree.
--   Locks: the two functions' catalogue rows, app_settings' single row and
--   the self-test's own rows. The lock timeout gives up after 5 s and
--   changes nothing.
--
-- BEFORE (production now, 3 Nov 2026; md5 of pg_get_functiondef with
-- search_path public)
--   * earn_invoice_commission(uuid): 6156b2e1ee51da5146a5a7acc16091ce
--   * invoice_affiliate_commission_preview(uuid):
--     f42363390bc620c1b7ee35efbfed20fc
-- AFTER (for later guards)
--   * earn_invoice_commission(uuid): 40b040e35b23940bb19e14e53bdd4daa
--   * invoice_affiliate_commission_preview(uuid):
--     072803880358cb84d7f148a06a27596e
--   * public function fingerprint, production now -> 489 (a second run the
--     same): 8cc90cc4845ce620f441367b67aa5cb5 (1399 functions: two
--     replaced); grant list unchanged (0f4b7be625fb254e90a0efc361334dfe).
--     Worked out on a copy of production at 481 (rc481_live, e15db582).
--
-- Test: scripts/commissions/tests/machine-commission-489.sql (begin ...
-- rollback; it installs this file twice, then sells, pays, part-pays and
-- refunds machines through the app's own calls). Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The functions this replaces: BEFORE (production now) and AFTER md5s ══
  c_sig constant text[] := array['earn_invoice_commission(uuid)', 'invoice_affiliate_commission_preview(uuid)'];
  c_before constant text[] := array['6156b2e1ee51da5146a5a7acc16091ce', 'f42363390bc620c1b7ee35efbfed20fc'];
  c_after constant text[] := array['40b040e35b23940bb19e14e53bdd4daa', '072803880358cb84d7f148a06a27596e'];
  c_def constant text[] := array[
$d1$CREATE OR REPLACE FUNCTION public.earn_invoice_commission(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_line_after numeric; v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric;
  v_paid_date date; v_own_orig numeric; v_third_orig numeric; v_tot_orig numeric; v_portion numeric;
  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;
  v_manual_part numeric; v_rest numeric; v_all_base numeric;  -- 391
  v_sel_own numeric; v_sel_third numeric; v_is_third boolean;
  v_t1_status text; v_t1_block text; v_t2_status text := 'earned'; v_t2_block text;
  v_rate_t1_own numeric; v_rate_t1_third numeric; v_rate_t2_own numeric; v_rate_t2_third numeric;
  v_machine_new boolean;  -- 489
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  -- Tier 1 is the affiliate explicitly chosen on the invoice, when there is one;
  -- otherwise it falls back to the customer's own referrer. Tier 2 is always the
  -- person who referred Tier 1.
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return; end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_tier1
      from public.customer_affiliates a where a.id = v_inv.affiliate_id;
    select c.referred_by into v_tier2
      from public.customers c where c.id = v_tier1;
  else
    select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  end if;
  if v_tier1 is null then return; end if;
  -- A customer never earns commission on their own purchase.
  if v_tier1 = v_inv.customer_id then return; end if;

  -- Editable commission rates (fall back to the historical defaults).
  select coalesce(commission_tier1_own_rate, 15), coalesce(commission_tier1_third_rate, 4.5),
         coalesce(commission_tier2_own_rate, 5), coalesce(commission_tier2_third_rate, 5),
         coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third, v_machine_new
    from public.app_settings where id = true;
  -- 489 (3 Nov 2026): a special product or a rental on an invoice created
  -- from app_settings.machine_commission_from on earns like the machine it
  -- is (special_products.product_id): a third-party machine at the
  -- third-party rates, a no-commission one nothing. An older invoice keeps
  -- the rule it was sold under, also when it is recalculated: its
  -- created_at cannot change. Not linked to a machine, it is ours, as before.

  -- Phase 5: resolve each tier's affiliate eligibility INDEPENDENTLY. A tier
  -- that is not an eligible affiliate still gets its commission row, but with
  -- status='blocked' + reason, so it is visible for reports yet never paid and
  -- never released. Tier 1 blocked does not block Tier 2 and vice-versa.
  v_t1_status := case when public.is_eligible_affiliate(v_tier1) then 'earned' else 'blocked' end;
  v_t1_block := case when v_t1_status='blocked' then public.affiliate_block_reason(v_tier1) else null end;
  if v_tier2 is not null then
    v_t2_status := case when public.is_eligible_affiliate(v_tier2) then 'earned' else 'blocked' end;
    v_t2_block := case when v_t2_status='blocked' then public.affiliate_block_reason(v_tier2) else null end;
  end if;

  -- 384: the Singapore day the invoice was paid in full, as package and
  -- bundle commission (383) and part payments (357) are dated. paid_at::date
  -- was the UTC day: the day before for a payment made before 08:00.
  v_paid_date := coalesce((v_inv.paid_at at time zone 'Asia/Singapore')::date, public.sg_today());
  select coalesce(sum(line_discount),0) into v_line_disc_sum from public.invoice_items where invoice_id = p_invoice_id;
  v_invoice_level := coalesce(v_inv.discount_total,0) - v_line_disc_sum;

  -- 391: the manual discount reaches every line (99), so each line gives up
  -- its share of it, third-party lines included. The rest (the Discount
  -- Voucher, Save Earth) is still given on our own lines only. The manual
  -- part is read as the Discounts report reads it.
  v_manual_part := least(coalesce(v_inv.manual_discount,0), greatest(v_invoice_level,0));
  v_rest := v_invoice_level - v_manual_part;
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_all_base
  from public.invoice_items ii where ii.invoice_id = p_invoice_id;

  -- The rest's base excludes 3rd-party product lines (489: and special
  -- products and rentals of third-party machines, from the cut-off).
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  left join public.special_products sp on sp.id = ii.special_product_id
  left join public.products mp on mp.id = sp.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental')
             and coalesce(mp.product_type::text, 'own') = 'third_party');

  for v_item in
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
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
  loop
    v_is_third := (v_item.line_kind in ('product','special_product','rental') and v_item.ptype = 'third_party');
    -- Wallet-funded value never earns commission.
    v_line_net := greatest(v_item.line_total - coalesce(v_item.line_discount,0)
                           - coalesce(v_item.wallet_funded,0), 0);
    -- 391: every line its share of the manual discount; our own lines
    -- also their share of the rest.
    v_line_after := v_line_net
      - case when v_manual_part <> 0 and v_all_base > 0 then v_manual_part * (v_line_net / v_all_base) else 0 end
      - case when not v_is_third and v_base_total > 0 then v_rest * (v_line_net / v_base_total) else 0 end;
    if v_line_after < 0 then v_line_after := 0; end if;
    if v_line_after = 0 then continue; end if;

    if v_item.line_kind = 'promotion' then
      select
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

      v_own_orig := v_own_orig + v_sel_own;
      v_third_orig := v_third_orig + v_sel_third;
      v_tot_orig := v_own_orig + v_third_orig;
      if v_tot_orig <= 0 then v_own_orig := 1; v_third_orig := 0; v_tot_orig := 1; end if;

      if v_own_orig > 0 then
        v_portion := round(v_line_after * v_own_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * v_rate_t1_own / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'own', v_portion, v_rate_t1_own, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * v_rate_t2_own / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'own', v_t1_amt, v_rate_t2_own, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * v_rate_t1_third / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'third_party', v_portion, v_rate_t1_third, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * v_rate_t2_third / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'third_party', v_t1_amt, v_rate_t2_third, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

    else
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then v_rate_t1_third else v_rate_t1_own end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
      values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', v_ptype, v_line_after, v_t1_rate, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * (case when v_ptype = 'third_party' then v_rate_t2_third else v_rate_t2_own end) / 100.0, 2);
        if v_t2_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', v_ptype, v_t1_amt, (case when v_ptype = 'third_party' then v_rate_t2_third else v_rate_t2_own end), v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
        end if;
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $function$
$d1$,
$d2$CREATE OR REPLACE FUNCTION public.invoice_affiliate_commission_preview(p_invoice_id uuid)
 RETURNS TABLE(o_invoice_item_id uuid, o_buyer uuid, o_referrer uuid, o_tier text, o_product_type text, o_line_amount numeric, o_rate numeric, o_amount numeric, o_status text, o_block_reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 357: derived from earn_invoice_commission (md5 2e4942e9ff859b0469fdcd99faf325fd). Writes nothing.
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_line_after numeric; v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric;
  v_paid_date date; v_own_orig numeric; v_third_orig numeric; v_tot_orig numeric; v_portion numeric;
  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;
  v_manual_part numeric; v_rest numeric; v_all_base numeric;  -- 391
  v_sel_own numeric; v_sel_third numeric; v_is_third boolean;
  v_t1_status text; v_t1_block text; v_t2_status text := 'earned'; v_t2_block text;
  v_rate_t1_own numeric; v_rate_t1_third numeric; v_rate_t2_own numeric; v_rate_t2_third numeric;
  v_machine_new boolean;  -- 489
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  -- Tier 1 is the affiliate explicitly chosen on the invoice, when there is one;
  -- otherwise it falls back to the customer's own referrer. Tier 2 is always the
  -- person who referred Tier 1.
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return; end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_tier1
      from public.customer_affiliates a where a.id = v_inv.affiliate_id;
    select c.referred_by into v_tier2
      from public.customers c where c.id = v_tier1;
  else
    select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  end if;
  if v_tier1 is null then return; end if;
  -- A customer never earns commission on their own purchase.
  if v_tier1 = v_inv.customer_id then return; end if;

  -- Editable commission rates (fall back to the historical defaults).
  select coalesce(commission_tier1_own_rate, 15), coalesce(commission_tier1_third_rate, 4.5),
         coalesce(commission_tier2_own_rate, 5), coalesce(commission_tier2_third_rate, 5),
         coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third, v_machine_new
    from public.app_settings where id = true;
  -- 489 (3 Nov 2026): a special product or a rental on an invoice created
  -- from app_settings.machine_commission_from on earns like the machine it
  -- is (special_products.product_id): a third-party machine at the
  -- third-party rates, a no-commission one nothing. An older invoice keeps
  -- the rule it was sold under, also when it is recalculated: its
  -- created_at cannot change. Not linked to a machine, it is ours, as before.

  -- Phase 5: resolve each tier's affiliate eligibility INDEPENDENTLY. A tier
  -- that is not an eligible affiliate still gets its commission row, but with
  -- status='blocked' + reason, so it is visible for reports yet never paid and
  -- never released. Tier 1 blocked does not block Tier 2 and vice-versa.
  v_t1_status := case when public.is_eligible_affiliate(v_tier1) then 'earned' else 'blocked' end;
  v_t1_block := case when v_t1_status='blocked' then public.affiliate_block_reason(v_tier1) else null end;
  if v_tier2 is not null then
    v_t2_status := case when public.is_eligible_affiliate(v_tier2) then 'earned' else 'blocked' end;
    v_t2_block := case when v_t2_status='blocked' then public.affiliate_block_reason(v_tier2) else null end;
  end if;

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  select coalesce(sum(line_discount),0) into v_line_disc_sum from public.invoice_items where invoice_id = p_invoice_id;
  v_invoice_level := coalesce(v_inv.discount_total,0) - v_line_disc_sum;

  -- 391: the manual discount reaches every line (99), so each line gives up
  -- its share of it, third-party lines included. The rest (the Discount
  -- Voucher, Save Earth) is still given on our own lines only. The manual
  -- part is read as the Discounts report reads it.
  v_manual_part := least(coalesce(v_inv.manual_discount,0), greatest(v_invoice_level,0));
  v_rest := v_invoice_level - v_manual_part;
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_all_base
  from public.invoice_items ii where ii.invoice_id = p_invoice_id;

  -- The rest's base excludes 3rd-party product lines (489: and special
  -- products and rentals of third-party machines, from the cut-off).
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  left join public.special_products sp on sp.id = ii.special_product_id
  left join public.products mp on mp.id = sp.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party')
    and not (v_machine_new and ii.line_kind in ('special_product','rental')
             and coalesce(mp.product_type::text, 'own') = 'third_party');

  for v_item in
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
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
  loop
    v_is_third := (v_item.line_kind in ('product','special_product','rental') and v_item.ptype = 'third_party');
    -- Wallet-funded value never earns commission.
    v_line_net := greatest(v_item.line_total - coalesce(v_item.line_discount,0)
                           - coalesce(v_item.wallet_funded,0), 0);
    -- 391: every line its share of the manual discount; our own lines
    -- also their share of the rest.
    v_line_after := v_line_net
      - case when v_manual_part <> 0 and v_all_base > 0 then v_manual_part * (v_line_net / v_all_base) else 0 end
      - case when not v_is_third and v_base_total > 0 then v_rest * (v_line_net / v_base_total) else 0 end;
    if v_line_after < 0 then v_line_after := 0; end if;
    if v_line_after = 0 then continue; end if;

    if v_item.line_kind = 'promotion' then
      select
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

      v_own_orig := v_own_orig + v_sel_own;
      v_third_orig := v_third_orig + v_sel_third;
      v_tot_orig := v_own_orig + v_third_orig;
      if v_tot_orig <= 0 then v_own_orig := 1; v_third_orig := 0; v_tot_orig := 1; end if;

      if v_own_orig > 0 then
        v_portion := round(v_line_after * v_own_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * v_rate_t1_own / 100.0, 2);
        if v_t1_amt > 0 then
          return query select v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'own', v_portion, v_rate_t1_own, v_t1_amt, v_t1_status::text, v_t1_block;
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * v_rate_t2_own / 100.0, 2);
            if v_t2_amt > 0 then
              return query select v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'own', v_t1_amt, v_rate_t2_own, v_t2_amt, v_t2_status::text, v_t2_block;
            end if;
          end if;
        end if;
      end if;

      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * v_rate_t1_third / 100.0, 2);
        if v_t1_amt > 0 then
          return query select v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'third_party', v_portion, v_rate_t1_third, v_t1_amt, v_t1_status::text, v_t1_block;
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * v_rate_t2_third / 100.0, 2);
            if v_t2_amt > 0 then
              return query select v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'third_party', v_t1_amt, v_rate_t2_third, v_t2_amt, v_t2_status::text, v_t2_block;
            end if;
          end if;
        end if;
      end if;

    else
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then v_rate_t1_third else v_rate_t1_own end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      return query select v_item.id, v_inv.customer_id, v_tier1, 'tier1', v_ptype, v_line_after, v_t1_rate, v_t1_amt, v_t1_status::text, v_t1_block;

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * (case when v_ptype = 'third_party' then v_rate_t2_third else v_rate_t2_own end) / 100.0, 2);
        if v_t2_amt > 0 then
          return query select v_item.id, v_inv.customer_id, v_tier2, 'tier2', v_ptype, v_t1_amt, (case when v_ptype = 'third_party' then v_rate_t2_third else v_rate_t2_own end), v_t2_amt, v_t2_status::text, v_t2_block;
        end if;
      end if;
    end if;
  end loop;

  
end; $function$
$d2$];

  v_path text := current_setting('search_path');
  d text; v text; i int; v_acl text[] := array[null, null]::text[]; v_make boolean[] := array[false, false];
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_owner uuid; t_store uuid; t_ref uuid; t_buyer uuid;
  t_m_own uuid; t_m_third uuid; t_m_nc uuid; t_sp_own uuid; t_sp_third uuid; t_sp_nc uuid; t_sp_none uuid;
  t_from timestamptz; t_old uuid; t_new uuid; t_got text; t_want text; t_r1o numeric; t_r1t numeric;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──
  -- The columns the change reads, with these types.
  select string_agg(x.t || '.' || x.c || ' ' || x.ty, ', ') into v
    from (values ('invoice_items', 'special_product_id', 'uuid'),
                 ('invoice_items', 'line_kind', 'invoice_line_kind'),
                 ('special_products', 'product_id', 'uuid'),
                 ('products', 'product_type', 'product_type'),
                 ('invoices', 'created_at', 'timestamp with time zone')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = ('public.' || x.t)::regclass and a.attname = x.c and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '489: these columns are missing or not of this type: %', v; end if;
  -- The cut-off rests on an invoice's created_at never changing.
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.invoices'::regclass and not t.tgisinternal and t.tgenabled = 'O'
                    and pg_get_triggerdef(t.oid) = 'CREATE TRIGGER invoice_created_at_immutable BEFORE UPDATE OF created_at ON public.invoices FOR EACH ROW EXECUTE FUNCTION guard_invoice_created_at()') then
    raise exception '489: invoices.created_at is no longer guarded (invoice_created_at_immutable), so the cut-off would not hold'; end if;

  for i in 1 .. 2 loop
    -- The text written out here is the tested one.
    if md5(c_def[i]) <> c_after[i] then
      raise exception '489: the text of public.% is not the tested one (md5 %)', c_sig[i], md5(c_def[i]); end if;
    -- The function: its BEFORE (replaced) or its AFTER (left alone).
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '489: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    -- its grants, to compare after (as sets: production lists them in another
    -- order than a local copy does)
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '489: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
    else
      raise exception '489: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- ── 2. Install ──
  alter table public.app_settings add column if not exists machine_commission_from timestamptz;
  comment on column public.app_settings.machine_commission_from is
    '489: from this moment (invoices.created_at), a special product or a rental earns commission like the machine it is linked to (special_products.product_id). Null: never (the rule before 489).';
  -- Set once: a second run keeps the first run's moment.
  update public.app_settings set machine_commission_from = now() where id = true and machine_commission_from is null;
  for i in 1 .. 2 loop
    if v_make[i] then execute c_def[i]; end if;
  end loop;

  -- ── 3. Checks after installing ──
  for i in 1 .. 2 loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '489: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '489: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  select machine_commission_from into t_from from public.app_settings where id = true;
  if t_from is null then raise exception '489: app_settings has no settings row (id = true), or its machine_commission_from is not set'; end if;

  -- ── 4. Self-test, in a block that is always undone ──
  -- Made-up records only ("489 Check", @example.invalid, fictional +61 2 5550
  -- phones); the invoices are written straight to their tables with their own
  -- numbers, so no sequence is used, and nothing is paid, so no stock moves.
  -- It ends by raising P0489, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- Two fictional phones in a row that no customer, in use or deleted, holds.
    -- (range scans of the two partial phone indexes, as 486's: 13,098 customers on
    -- 3 Nov 2026, too many to read whole within the statement timeout)
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '489: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 1) n);
    -- A made-up active Owner, signed in for this block.
    insert into auth.users (id, email) values (gen_random_uuid(), '489chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '489 Check Owner', '489chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code) values ('489 Check ' || t_sfx, '489-' || t_sfx, 'SG') returning id into t_store;
    -- A referrer and a buyer they referred.
    insert into public.customers (full_name, phone) values ('489 Check Referrer', t_ph[1]) returning id into t_ref;
    insert into public.customers (full_name, phone, referred_by) values ('489 Check Buyer', t_ph[2], t_ref) returning id into t_buyer;
    -- Machines of each type, special products linked to each, and one linked to none.
    insert into public.products (name, sku, product_type) values ('489 Check Own Machine', '489-MO-' || t_sfx, 'own') returning id into t_m_own;
    insert into public.products (name, sku, product_type) values ('489 Check Third Machine', '489-MT-' || t_sfx, 'third_party') returning id into t_m_third;
    insert into public.products (name, sku, product_type) values ('489 Check Fee Machine', '489-MN-' || t_sfx, 'no_commission') returning id into t_m_nc;
    insert into public.special_products (name, sku, sale_price, rate_month, product_id) values ('489 Check SP Own', '489-SO-' || t_sfx, 100, 100, t_m_own) returning id into t_sp_own;
    insert into public.special_products (name, sku, sale_price, rate_month, product_id) values ('489 Check SP Third', '489-ST-' || t_sfx, 100, 100, t_m_third) returning id into t_sp_third;
    insert into public.special_products (name, sku, sale_price, rate_month, product_id) values ('489 Check SP Fee', '489-SN-' || t_sfx, 100, 100, t_m_nc) returning id into t_sp_nc;
    insert into public.special_products (name, sku, sale_price, rate_month) values ('489 Check SP None', '489-SX-' || t_sfx, 100, 100) returning id into t_sp_none;
    -- One invoice created a day before the cut-off, one at or after it, each
    -- with the same five S$100 lines.
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, created_at)
    values ('489-CHECK-OLD-' || t_sfx, t_store, t_buyer, t_owner, t_from - interval '1 day') returning id into t_old;
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, created_at)
    values ('489-CHECK-NEW-' || t_sfx, t_store, t_buyer, t_owner, greatest(now(), t_from)) returning id into t_new;
    insert into public.invoice_items (invoice_id, line_kind, special_product_id, quantity, unit_price, line_total)
    select inv, k::public.invoice_line_kind, sp, 1, 100, 100
      from unnest(array[t_old, t_new]) inv
     cross join (values ('special_product', t_sp_own), ('special_product', t_sp_third), ('rental', t_sp_third),
                        ('special_product', t_sp_nc), ('special_product', t_sp_none)) l(k, sp);
    select commission_tier1_own_rate, commission_tier1_third_rate into t_r1o, t_r1t from public.app_settings where id = true;

    -- What each line earns at Tier 1, labelled by its machine, through the preview.
    t_want := 'fee special_product own, none special_product own, own special_product own, third rental own, third special_product own';
    select string_agg(x, ', ' order by x) into t_got
      from (select case ii.special_product_id when t_sp_own then 'own' when t_sp_third then 'third' when t_sp_nc then 'fee' else 'none' end
                   || ' ' || ii.line_kind::text || ' ' || p.o_product_type as x
              from public.invoice_affiliate_commission_preview(t_old) p join public.invoice_items ii on ii.id = p.o_invoice_item_id
             where p.o_tier = 'tier1') s;
    if t_got is distinct from t_want then
      raise exception '489: an invoice created before the cut-off: its lines earn as %, not as before (%)', coalesce(t_got, 'nothing'), t_want; end if;
    t_want := 'none special_product own, own special_product own, third rental third_party, third special_product third_party';
    select string_agg(x, ', ' order by x) into t_got
      from (select case ii.special_product_id when t_sp_own then 'own' when t_sp_third then 'third' when t_sp_nc then 'fee' else 'none' end
                   || ' ' || ii.line_kind::text || ' ' || p.o_product_type as x
              from public.invoice_affiliate_commission_preview(t_new) p join public.invoice_items ii on ii.id = p.o_invoice_item_id
             where p.o_tier = 'tier1') s;
    if t_got is distinct from t_want then
      raise exception '489: an invoice created from the cut-off: its lines earn as %, not %', coalesce(t_got, 'nothing'), t_want; end if;
    if exists (select 1 from public.invoice_affiliate_commission_preview(t_new) p
                where p.o_tier = 'tier1' and p.o_rate <> case p.o_product_type when 'third_party' then t_r1t else t_r1o end) then
      raise exception '489: a line from the cut-off is not at its type''s Tier 1 rate'; end if;

    -- earn_invoice_commission writes exactly what the preview shows.
    perform public.earn_invoice_commission(t_new);
    select string_agg(x, ', ' order by x) into t_want
      from (select p.o_invoice_item_id::text || p.o_tier || p.o_product_type || round(p.o_line_amount, 2)::text || p.o_amount::text as x
              from public.invoice_affiliate_commission_preview(t_new) p) s;
    select string_agg(x, ', ' order by x) into t_got
      from (select c.invoice_item_id::text || c.tier::text || c.product_type::text || c.line_amount::text || c.commission_amount::text as x
              from public.commissions c where c.invoice_id = t_new) s;
    if t_got is distinct from t_want then
      raise exception '489: earn_invoice_commission wrote other rows than the preview shows'; end if;

    raise exception using errcode = 'P0489', message = '489: self-test done, undone';
  exception when sqlstate 'P0489' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
