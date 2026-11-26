-- 544_wallet_credit_pays_special_and_consignment_products.sql
--
-- WALLET CREDIT PAYS SPECIAL PRODUCTS AND CONSIGNMENT PRODUCTS
--
--   The owner's request (26 Nov 2026): Premium Bundle credit may pay for special products and for
--   consignment products on invoices. The owner's answers the same day: other credit (refund
--   credit, manual top-ups, exchange, opening balance, transfer: the 'open' policy) may pay both
--   too; Credit Package credit pays neither unless an Owner ticks them in that package's Rules.
--   The BEFORE md5s and the relied-on md5s below are those of production after 540 (head
--   20261125171841, function fingerprint 18fcffcae0f51cc09245231c3779585e/1462). If production
--   differs when this is applied, it refuses and changes nothing.
--   (The number 544 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 544 comments it writes into the functions below (and so their AFTER md5s,
--   also in scripts/credit-policy/undo-544.sql and in the suite that knows them), and in the
--   name and path of its suite.)
--
-- WHAT WAS WRONG
--
--   A special product and a consignment product are both sold as an invoice line of kind
--   'special_product' (a consignment product is a special_products row with is_consignment; the
--   invoice form's "Consignment" category is the page's alone). invoice_line_credit_purpose gives
--   such a line the purpose 'special_product', and purchase_category had no branch for it, so its
--   category was 'unknown', which credit_policy_allows and credit_lot_allows_category refuse for
--   every credit. Premium Bundle lots also keep the purpose list fixed at their sale (product,
--   voucher, promotion, therapy, rental; 80, 154, 356, 476), which never named special products,
--   and credit_lot_snapshot_allows held them to it. So no credit of any kind could pay a special
--   or consignment line. Production, read only on 26 Nov 2026: 23 special_product lines (16 of
--   them consignment), 2 of them on unpaid invoices; special_credit_allocations 0 rows ever; no
--   wallet allocation on a special_product line; no package has rules of its own
--   (credit_package_spending_rules 0 rows: every package uses the defaults).
--
-- THE RULE
--
--   1. Two new categories: a special product's line is 'special_product'; a consignment
--      product's line (special_products.is_consignment) is 'consignment_product'.
--   2. Premium Bundle credit ('bundle_any') pays both.
--   3. Other credit ('open') pays both. The line that decides it is credit_policy_allows'
--      'open' branch (not changed here: it refuses only 'credit_package', 'premium_bundle' and
--      'unknown'); to stop 'open' credit paying them, add the two categories to that list.
--   4. Credit Package credit pays neither by default (credit_package_default_rules is not
--      changed). Both are offered in each package's Rules (credit_spendable_categories), so an
--      Owner can tick them per package; credit_package_effective_rules passes a package's ticked
--      categories through as before.
--   5. Rentals and late fees stay 'unknown': no credit pays them. Credit never buys a credit
--      package or a premium bundle. 'unknown' stays refused.
--
-- WHAT THIS DOES
--
--   * purchase_category gains a fifth argument, p_special_product_id (default null): with the
--     purpose 'special_product' it gives 'consignment_product' or 'special_product' by that
--     special product's is_consignment, and 'unknown' without it. Every other purpose as before.
--     The four-argument function is dropped and the five-argument one made in its place, with
--     the same grants (signed-in logins and the service role; not anon); a call with four
--     arguments works as before.
--   * credit_lot_line_allowed and credit_lot_line_reason (the invoice path: Record Payment, the
--     Pay dialog, the "available" amount of each wallet method, Correct payment) pass the line's
--     special_product_id.
--   * pay_special_with_credit is dropped. It was the old Special page's wallet payment for a
--     special sale or a rental (426 left it to the service role alone). Nothing calls it, read on
--     26 Nov 2026: no page (src/), no Edge Function, no script but tests, no SQL function, no
--     trigger or other object, and only postgres and the service role may execute it. It never
--     succeeded (no credit could pay 'unknown'), so special_credit_allocations has 0 rows. With
--     the new categories it would for the first time take a customer's credit, and it checks
--     neither the amount against the sale, nor the sale's status or customer, nor whether the
--     sale is on an invoice (which is paid through the invoice). Special and consignment products
--     are paid on their invoice lines only.
--   * credit_lot_snapshot_allows: a Premium Bundle lot's fixed purpose list no longer stops a
--     special product's line; the category check (rules 1 to 3) decides it, as it already does
--     for a credit package's lots. Every other lot and purpose as before (an 'open' lot keeps its
--     own list, which on production is always empty: no limit).
--   * credit_spendable_categories (the Rules screen's boxes, the check of a rules change, and
--     what a bundle's or other credit's summary lists) and customer_credit_eligibility (each
--     lot's list of what it may pay) name the two new categories.
--
-- WHAT STAYS
--
--   * Every lot, ledger row, allocation and payment already recorded. No lot's purpose list is
--     rewritten; new Premium Bundle lots still record the same fixed list (it no longer limits
--     special products).
--   * A refund of a special or consignment line paid with credit gives the credit back to the
--     lot it came from, by the same functions as any other line (refund_invoice_recorded,
--     correct_invoice_payment).
--   * refund_special_credit, as it is (only the service role may call it; with no wallet payment
--     of a special document there is nothing for it to give back). consume_customer_credit, as it
--     is: it calls purchase_category with four arguments, and a special product's purpose with no
--     special product stays 'unknown'.
--   * The category is read when the credit is spent: a special product made a consignment
--     product later (set_special_product_consignment) is paid as what it is at that moment.
--   * credit_policy_reason's words for package credit ("can only pay for individual therapy
--     sessions ...") are the policy's old words, not the package's rules, as before for every
--     category.
--   * Premium Bundle lots still cannot pay event tickets (their fixed list has no 'event'), as
--     before; customer_credit_eligibility still lists event tickets for them.
--
-- UNDO
--
--   scripts/credit-policy/undo-544.sql (it refuses unless every function here is exactly 544's,
--   with 544's grants, nothing else calls purchase_category, and no pay_special_with_credit is
--   there): each function is put back exactly as it was, purchase_category with four arguments
--   again, and pay_special_with_credit exactly as it was, for the service role. Credit already spent on
--   special and consignment lines stays spent (it counts them). A later migration changing any of
--   these must pin 544's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/credit-policy/tests/special-and-consignment-credit-544.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the changed ones call, or that call them, as tested (production after 540).
  c_relied constant text[] := array[
    'credit_lot_allows_category(uuid,text)',
    'credit_lot_allows(jsonb,text,uuid)',
    'credit_policy_allows(text,text)',
    'credit_policy_reason(text,text)',
    'credit_lot_policy(text,text,boolean)',
    'credit_lot_policy_for(uuid)',
    'credit_package_effective_rules(uuid)',
    'preview_credit_package_policy_change(uuid,text[],text[])',
    'set_credit_package_spending_rules(uuid,text[],text[],text)',
    'credit_lot_spending_summary(uuid)',
    'invoice_line_credit_purpose(text)',
    'invoice_credit_transfer_origin(uuid)',
    'allocate_invoice_wallet_credit(uuid,numeric,text,text)',
    'invoice_wallet_availability(uuid)',
    'record_invoice_payment(uuid,jsonb,uuid)',
    'consume_customer_credit(uuid,numeric,text,uuid,uuid,text,text,text,uuid)',
    'refund_special_credit(text,uuid)',
    'ensure_customer_wallet(uuid)'];
  c_relied_md5 constant text[] := array[
    '935acacb64f836a97f0a1b4458d70d96',
    '1f3de218c56a63cb912e664be15463fb',
    '504f3055b3f1c1a038c5cae217e37fd6',
    'a0a94d8eae927cbf06abcb23f561cd46',
    'd9a97af64871c4ebcff8d1f6c15f68a6',
    'ccdd506e78c7cdca97194fde87cdcc42',
    '0b8e865eb1c56e15db885753ffe6f1ee',
    'b58ab22624fafeed4a4a83f8d5385246',
    '3b2bc1e2fd1e9e02089cfd6b45aae11d',
    'a541b3e203b5e72e3ea971920f3b8aff',
    'ff61d218e5bd8f272885216e23c0a1a6',
    '1e8beeccfbf7e432edffc1598acddb53',
    'da8aa986c92d765a8028741f33bf56b0',
    '8d828727572b013bc54a2b07e6a3f7a0',
    '9c70097ed4da614fb9dcc66fdfcdb7d6',
    'fa07fb9251a38f41d42899a3f2a0ba61',
    '42e436aa44046d4cb1748641cd8a5257',
    '8ef18daebbbe3c12f2024290ea8416e8'];
  -- The functions changed in place (the same signature; their grants are kept).
  c_sig constant text[] := array[
    'credit_lot_line_allowed(uuid,uuid)',
    'credit_lot_line_reason(uuid,uuid)',
    'credit_lot_snapshot_allows(uuid,jsonb,text,uuid)',
    'credit_spendable_categories()',
    'customer_credit_eligibility(uuid)'];
  c_before constant text[] := array[
    '7d81252612104b1012b6d78513092091',
    'e5089d02f8c68bd36b6c8ff99dabf675',
    '1d78a592687366f98b52adcb655c51fb',
    'a3539af5c86c7abdb2bcff6d8d4f0611',
    'be6d5329add18038c24848c168db8785'];
  c_after constant text[] := array[
    '0f0d897d308247887577641b820aeeca',
    'be8cceed5351686edb119a4681e9fa56',
    'cd832a1758e45b4261b2f9058691d55c',
    'b25fcf7b6780171f904a3a652d93cbb6',
    '2bd2cf2f59028bc403b155f98929d719'];
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres'];
  c_def constant text[] := array[
$d$CREATE OR REPLACE FUNCTION public.credit_lot_line_allowed(p_lot_id uuid, p_invoice_item_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_policy text := public.credit_lot_policy_for(p_lot_id);
  v_it record; v_purpose text; v_cat text; v_components integer; v_bad integer;
begin
  if v_policy is null then return false; end if;

  select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
    into v_it from public.invoice_items ii where ii.id = p_invoice_item_id;
  if not found then return false; end if;
  v_purpose := v_it.purpose;

  if v_purpose <> 'promotion' then
    -- 544 (the owner, 26 Nov 2026): a special product's line names its special product, so its
    -- category is 'special_product' or 'consignment_product' (purchase_category).
    v_cat := public.purchase_category(v_purpose, v_it.product_id, v_it.voucher_id, v_it.therapy_service_id,
                                      v_it.special_product_id);
    return public.credit_lot_allows_category(p_lot_id, v_cat);
  end if;

  -- Composite. An unrestricted-enough policy still has to clear every part.
  select count(*),
         count(*) filter (where not public.credit_lot_allows_category(p_lot_id,
           public.purchase_category(
             case when s.product_id is not null then 'product'
                  when s.voucher_id is not null then 'voucher'
                  else 'unknown' end,
             s.product_id, s.voucher_id, null)))
    into v_components, v_bad
    from public.invoice_promotion_selections s
   where s.invoice_item_id = p_invoice_item_id;

  if coalesce(v_components, 0) = 0 then
    -- Nothing recorded to check. An 'open' or bundle policy keeps its existing
    -- freedom; a package-restricted one does not get the benefit of the doubt.
    return v_policy in ('open','bundle_any');
  end if;
  return v_bad = 0;
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.credit_lot_line_reason(p_lot_id uuid, p_invoice_item_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_policy text := public.credit_lot_policy_for(p_lot_id);
  v_it record; v_cat text;
begin
  if public.credit_lot_line_allowed(p_lot_id, p_invoice_item_id) then return null; end if;
  select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
    into v_it from public.invoice_items ii where ii.id = p_invoice_item_id;
  if not found then return 'That invoice line no longer exists.'; end if;

  if v_it.purpose = 'promotion' then
    return case when v_policy in ('open','bundle_any')
      then 'This promotion contains items this balance cannot pay for, and the parts cannot be separated safely. Use another payment method for this line.'
      else public.credit_policy_reason(v_policy, 'promotion')
           || ' A promotion containing other items does not change that.' end;
  end if;
  -- 544 (the owner, 26 Nov 2026): with the line's special product, as credit_lot_line_allowed.
  v_cat := public.purchase_category(v_it.purpose, v_it.product_id, v_it.voucher_id, v_it.therapy_service_id,
                                    v_it.special_product_id);
  return public.credit_policy_reason(v_policy, v_cat);
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.credit_lot_snapshot_allows(p_lot_id uuid, p_restrictions jsonb, p_purpose text, p_voucher_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare orig public.customer_credit_lots%rowtype; v_policy text; v_ids jsonb;
begin
 select * into orig from public.customer_credit_lots
  where id = public.invoice_credit_transfer_origin(p_lot_id);
 if not found then return public.credit_lot_allows(p_restrictions, p_purpose, p_voucher_id); end if;

 v_policy := public.credit_lot_policy(orig.source_type, orig.category, orig.source_record_id is not null);
 -- 544 (the owner, 26 Nov 2026): Premium Bundle credit may pay special and consignment products.
 -- A bundle's lots keep the purpose list fixed at its sale (product, voucher, promotion, therapy,
 -- rental), which never named special products; for them the category check
 -- (credit_lot_allows_category, purchase_category) decides a special product's line, as it does
 -- for a credit package. The lots themselves are not changed.
 if v_policy = 'bundle_any' and p_purpose = 'special_product' then return true; end if;
 if v_policy not in ('package_paid','package_bonus') then
  return public.credit_lot_allows(p_restrictions, p_purpose, p_voucher_id);
 end if;

 -- Category is credit_lot_allows_category()'s decision now. Only an explicit
 -- voucher list still binds, and only when a voucher is what is being bought.
 v_ids := coalesce(p_restrictions->'allowed_voucher_ids', '[]'::jsonb);
 if p_purpose <> 'voucher' or jsonb_array_length(v_ids) = 0 then return true; end if;
 if p_voucher_id is null then return false; end if;
 return v_ids ? p_voucher_id::text;
end $function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.credit_spendable_categories()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
 select array['therapy_session','unlimited_therapy','session_voucher','money_voucher',
              'own_product','third_party_product','other_product','promotion',
              'event_ticket',  -- 370: event tickets
              'special_product','consignment_product']::text[]  -- 544: special and consignment products
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.customer_credit_eligibility(p_customer_id uuid)
 RETURNS TABLE(lot_id uuid, category text, source_type text, source_name text, policy text, policy_label text, remaining numeric, needs_review boolean, allowed_categories text[], explanation text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.category, l.source_type,
         coalesce(cp.name, pb.name, l.reference_no, l.source_type),
         public.credit_lot_policy_for(l.id),
         case public.credit_lot_policy_for(l.id)
           when 'package_paid'  then 'Therapy sessions and therapy vouchers only'
           when 'package_bonus' then 'Own-brand products only'
           when 'bundle_any'    then 'Anything except new credit packages and premium bundles'
           when 'open'          then 'Anything except new credit packages and premium bundles'
           else 'Needs review before it can be spent' end,
         l.remaining_amount,
         public.credit_lot_policy_for(l.id) = 'needs_review',
         coalesce((select array_agg(c order by c) from unnest(array[
             'own_product','third_party_product','other_product','session_voucher',
             'money_voucher','therapy_session','unlimited_therapy','promotion',
             'event_ticket',  -- 370: event tickets
             'special_product','consignment_product']) c  -- 544: special and consignment products
            -- The list a person sees must be the list that will actually
            -- be honoured, so it resolves the same way spending does.
            where public.credit_lot_allows_category(l.id, c)), '{}'),
         public.credit_policy_reason(
           public.credit_lot_policy_for(l.id), 'unknown')
    from public.customer_credit_lots l
    left join public.customer_credit_lots origin on origin.id=public.invoice_credit_transfer_origin(l.id)
    left join public.credit_packages cp
      on origin.source_type = 'credit_package' and cp.id = origin.source_record_id
    left join public.premium_bundles pb
      on origin.source_type = 'premium_bundle' and pb.id = origin.source_record_id
   where public.can_view_customer_credit() and l.customer_id = p_customer_id and l.status = 'active' and l.remaining_amount > 0
   order by l.category, l.effective_date
$function$
$d$];
  -- purchase_category gains a fifth argument (the line's special product), so the old one is
  -- dropped and the new one made, with the same grants.
  c_pc_old constant text := 'purchase_category(text,uuid,uuid,uuid)';
  c_pc_old_md5 constant text := '98902394fbeb61b8635044f7c82a9b42';
  c_pc_new constant text := 'purchase_category(text,uuid,uuid,uuid,uuid)';
  c_pc_new_md5 constant text := '6b66bb3fd20a6e1bc22f0918740052f7';
  c_pc_acl constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_pc_def constant text := $d$CREATE OR REPLACE FUNCTION public.purchase_category(p_purpose text, p_product_id uuid DEFAULT NULL::uuid, p_voucher_id uuid DEFAULT NULL::uuid, p_therapy_service_id uuid DEFAULT NULL::uuid, p_special_product_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 544 (the owner, 26 Nov 2026: wallet credit may pay special and consignment products):
  -- p_special_product_id is the special product of a special product's line. Its category is
  -- 'consignment_product' when that special product is a consignment product
  -- (special_products.is_consignment), else 'special_product'; without it (or with no such
  -- special product) it stays 'unknown', which no credit pays. A rental stays 'unknown'.
  select case p_purpose
    when 'product' then
      case (select p.product_type::text from public.products p where p.id = p_product_id)
        when 'own' then 'own_product'
        when 'third_party' then 'third_party_product'
        when 'no_commission' then 'other_product'
        else 'unknown' end
    when 'voucher' then
      case (select v.voucher_kind::text from public.vouchers v where v.id = p_voucher_id)
        when 'normal' then 'session_voucher'
        when 'fixed_discount' then 'money_voucher'
        when 'percentage_discount' then 'money_voucher'
        else 'unknown' end
    when 'therapy' then
      case when p_therapy_service_id is not null then 'therapy_session' else 'unlimited_therapy' end
    when 'credit_package' then 'credit_package'
    when 'premium_bundle' then 'premium_bundle'
    when 'promotion' then 'promotion'
    when 'event' then 'event_ticket'         -- 370: a ticket's category
    when 'event_ticket' then 'event_ticket'
    when 'special_product' then              -- 544: a special or consignment product
      case (select sp.is_consignment from public.special_products sp where sp.id = p_special_product_id)
        when true then 'consignment_product'
        when false then 'special_product'
        else 'unknown' end
    else 'unknown'
  end
$function$
$d$;
  -- The only functions that call purchase_category: the two changed here, and
  -- consume_customer_credit (not changed; it calls it with four arguments, as before).
  c_pc_callers constant text[] := array['consume_customer_credit', 'credit_lot_line_allowed', 'credit_lot_line_reason'];
  -- pay_special_with_credit is dropped: no page, Edge Function, script or SQL function calls it,
  -- and with the two new categories it would for the first time take a customer's credit for a
  -- special sale or a rental, with no check of the amount, the sale or the customer. The undo
  -- makes it again exactly, with its grants.
  c_pay constant text := 'pay_special_with_credit(text,uuid,uuid,numeric,uuid)';
  c_pay_md5 constant text := '5496ea7f657d49629653defc905c88f2';
  c_pay_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_pay_drop constant boolean := true;

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_done int := 0; v_pc_done boolean; v_pay_done boolean; v_bad text := '';
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
      raise exception '544: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if (select a.atttypid from pg_attribute a
       where a.attrelid = to_regclass('public.special_products') and a.attname = 'is_consignment' and not a.attisdropped)
       is distinct from 'boolean'::regtype
     or not (select a.attnotnull from pg_attribute a
              where a.attrelid = to_regclass('public.special_products') and a.attname = 'is_consignment' and not a.attisdropped)
     or not exists (select 1 from pg_attribute a where a.attrelid = to_regclass('public.invoice_items')
                     and a.attname = 'special_product_id' and not a.attisdropped)
     or not exists (select 1 from pg_attribute a where a.attrelid = to_regclass('public.special_sales')
                     and a.attname = 'special_product_id' and not a.attisdropped) then
    raise exception '544: special_products.is_consignment (boolean, not null), invoice_items.special_product_id or special_sales.special_product_id is not as tested'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '544: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '544: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) <> c_before[i] then
      raise exception '544: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'purchase_category') <> 1 then
    raise exception '544: there is not exactly one public.purchase_category. Re-read them before applying.'; end if;
  if to_regprocedure('public.' || c_pc_new) is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_pc_new))) <> c_pc_new_md5 then
      raise exception '544: a function public.% is there, but not 544''s. Re-read it before applying.', c_pc_new; end if;
    v_pc_done := true;
  elsif to_regprocedure('public.' || c_pc_old) is not null
        and md5(pg_get_functiondef(to_regprocedure('public.' || c_pc_old))) = c_pc_old_md5 then
    v_pc_done := false;
  else
    raise exception '544: public.% is not the version this was tested against. Re-read it and re-test before applying.', c_pc_old;
  end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x
       where p.pronamespace = 'public'::regnamespace and p.proname = 'purchase_category') is distinct from c_pc_acl then
    raise exception '544: the grants of public.purchase_category are not the tested ones. Re-read them before applying.'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pay_special_with_credit') > 1 then
    raise exception '544: there is more than one public.pay_special_with_credit. Re-read them before applying.'; end if;
  if to_regprocedure('public.' || c_pay) is null then
    v_pay_done := c_pay_drop;
  elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_pay))) = c_pay_md5
        and (select coalesce(string_agg(x::text, ',' order by x::text), '')
               from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_pay)) is not distinct from c_pay_acl then
    v_pay_done := not c_pay_drop;
  else
    raise exception '544: public.% is not the version (or has not the grants) this was tested against. Re-read it before applying.', c_pay;
  end if;
  if v_done = cardinality(c_sig) and v_pc_done and v_pay_done then
    raise exception '544 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_pc_done or (v_pay_done and c_pay_drop) then
    raise exception '544: only part of it is in on this database (% of % functions changed, purchase_category %, pay_special_with_credit %). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), case when v_pc_done then 'changed' else 'not changed' end,
      case when to_regprocedure('public.' || c_pay) is null then 'dropped' else 'there' end; end if;
  -- Nothing calls pay_special_with_credit, and nothing depends on it.
  select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '') into v_bad
    from pg_proc p
   where p.prosrc ~ 'pay_special_with_credit\s*\('
     and p.proname <> 'pay_special_with_credit'
     and p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace);
  if v_bad <> '' then
    raise exception '544: functions call pay_special_with_credit (%). Re-read them before applying; nothing was changed.', v_bad; end if;
  if exists (select 1 from pg_depend dp where dp.refobjid = to_regprocedure('public.' || c_pay) and dp.deptype <> 'p') then
    raise exception '544: an object depends on public.%. Re-read it before applying; nothing was changed.', c_pay; end if;
  -- Nothing but the three functions changed here calls purchase_category (a caller left out
  -- would still work, with no special product, but it would not have been tested).
  select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '') into v_bad
    from pg_proc p
   where p.prosrc ~ 'purchase_category\s*\('
     and p.proname <> all (c_pc_callers || array['purchase_category'])
     and p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace);
  if v_bad <> '' then
    raise exception '544: other functions call purchase_category (%). Re-read them before applying; nothing was changed.', v_bad; end if;
  if exists (select 1 from pg_depend dp where dp.refobjid = to_regprocedure('public.' || c_pc_old) and dp.deptype = 'n') then
    raise exception '544: an object depends on public.%. Re-read it before applying; nothing was changed.', c_pc_old; end if;
  -- The texts installed are the tested ones.
  for i in 1 .. cardinality(c_sig) loop
    if md5(c_def[i]) <> c_after[i] then
      v_bad := v_bad || format(' %s=%s', c_sig[i], md5(c_def[i])); end if;
  end loop;
  if md5(c_pc_def) <> c_pc_new_md5 then v_bad := v_bad || format(' %s=%s', c_pc_new, md5(c_pc_def)); end if;
  if v_bad <> '' then
    raise exception '544: the text is not the tested one:%', v_bad; end if;

  -- 2. Install: purchase_category first (the changed functions call it with five arguments)
  execute format('drop function public.%s', c_pc_old);
  execute c_pc_def;
  execute format('revoke all on function public.%s from public, anon', c_pc_new);
  execute format('grant execute on function public.%s to authenticated, service_role', c_pc_new);
  for i in 1 .. cardinality(c_sig) loop
    execute c_def[i];
  end loop;
  if c_pay_drop then
    execute format('drop function public.%s', c_pay);
  end if;

  -- 3. Checks after installing
  if c_pay_drop and to_regprocedure('public.' || c_pay) is not null then
    raise exception '544: public.% is still there', c_pay; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_pc_new))) <> c_pc_new_md5
     or to_regprocedure('public.' || c_pc_old) is not null then
    raise exception '544: public.% was made other than tested', c_pc_new; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_pc_new)) is distinct from c_pc_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_pc_new), 'execute') then
    raise exception '544: the grants of public.% are not the tested ones', c_pc_new; end if;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '544: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '544: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '544: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
