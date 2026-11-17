-- 507_only_an_owner_or_manager_gives_credit_away_free.sql
--
-- ONLY AN OWNER OR MANAGER MAKES A CREDIT PACKAGE, PREMIUM BUNDLE, VOUCHER OR
-- THERAPY LINE FREE OF CHARGE
--
--   From the security audit of 17 Nov 2026 (finding H4).
--   The BEFORE md5s below were read from production (head 502) on 17 Nov 2026 and match
--   the local copy built to production's function fingerprint. If production's text
--   differs when this is applied, this file refuses and changes nothing: re-read and re-test.
--   (The number 507 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- THE OWNER'S DECISION (17 Nov 2026, report R4, "Owner/Manager only"): only an Owner or a
-- Manager may make a credit package, premium bundle, voucher or therapy line free of charge.
-- Staff can still make ordinary product lines free. A free line still gives what it gives
-- today (355: an FOC portion of a package is a gift of the package).
--
-- WHAT WAS WRONG
--
--   Adding credit to a wallet with no sale is for an Owner or a Manager
--   (adjust_customer_credit). But apply_line_foc (Make FOC on a saved invoice) lets every
--   staff role except Inventory Manager make any line free, and never looks at what the
--   line is. For a Credit Package or Premium Bundle the free amount counts as paid
--   (credit_line_paid_entitlement, 355), so once the invoice is confirmed the customer has
--   the full paid credit and the bonus for S$0. A voucher or therapy line made free gives
--   the voucher or the sessions for S$0 in the same way. Vouchers and therapy can also be
--   made free on the New Invoice form and in Edit or Correct Invoice (create_invoice,
--   update_invoice_internal); credit packages and bundles cannot (355 refuses that for
--   everyone), so Make FOC is their one route.
--
-- WHAT THIS DOES
--
--   1. apply_line_foc refuses a credit_package, premium_bundle, voucher or therapy line
--      unless the caller is an Owner or a Manager. The server, with no login, passes as before.
--   2. create_invoice refuses a voucher or therapy line sent free of charge unless the
--      caller is an Owner or a Manager.
--   3. update_invoice_internal (Edit Invoice and Correct Invoice) refuses a voucher or
--      therapy line that is new or changed and free of charge, unless the caller is an Owner
--      or a Manager. A line kept exactly as it was saved is not looked at again, so Staff
--      can still edit or correct the other lines of an invoice on which an Owner or Manager
--      made a voucher free.
--   Each refusal reads "Only an Owner or Manager can make a Credit Package, Premium Bundle,
--   voucher or therapy line free of charge." (SQLSTATE 42501).
--
-- WHAT THIS LEAVES ALONE
--
--   * Products, special products, rentals, event tickets and promotions: Staff make them
--     free as today. A promotion that contains vouchers or therapy is a promotion line.
--   * What a free or discounted line gives (full credit, full bonus, vouchers, sessions).
--     A near-total manual discount still gives full bonus credit and vouchers (R4, open).
--   * confirm_foc_invoice and remove_line_foc: any member of staff may still confirm an
--     invoice whose free line an Owner or Manager made, or take an FOC off.
--   * The website's VIP invoices (event_vip_make_invoices) give their vouchers free as the
--     event's acting profile. That profile may be an Owner, Admin or Manager; on 17 Nov 2026
--     both events' acting profiles were Owners and no Admin login was active. An Admin
--     acting profile would now be refused and the order would wait for review.
--   * Invoices already saved with such a line free (production on 17 Nov 2026: 4 voucher
--     lines made free by Staff) are not changed.
--
-- UNDO: run this file's patches backwards (swap c_anchor and c_new and swap c_before and
-- c_after); the three functions go back to their BEFORE text.
--
-- NO SELF-TEST INSIDE; the suite is scripts/invoices/tests/foc-credit-lines-507.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The functions this patches: BEFORE (production, 17 Nov 2026) and AFTER md5s
  c_sig constant text[] := array[
    'apply_line_foc(uuid,integer,uuid,text)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'];
  c_before constant text[] := array[
    '5fbd0b6feb36e11dea6be231ffa0e952',
    '80c80d386a5241e63b353e35e13ef250',
    '1f034561a461bdb46a1e6274e0d04606'];
  c_after constant text[] := array[
    'a249b0e94d4280d6ff4e73fa8e1efbc8',
    '42f00d595a40df157d28a7ea88fbe7ad',
    '09e1d77e450d50fc6195773f92e770e5'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. An undo swaps them back.
  c_fn constant int[] := array[1, 2, 3];
  c_anchor constant text[] := array[
$a$    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'You do not have access to this invoice''s store'; end if;
  end if;$a$,
$a$    raise exception 'Inventory Manager cannot apply FOC';
  end if;$a$,
$a$      perform public.invoice_foc_reason(p_invoice_id,v_item);
    end if;$a$];
  c_new constant text[] := array[
$n$    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'You do not have access to this invoice''s store'; end if;
    -- 507: a Credit Package, Premium Bundle, voucher or therapy line made
    -- free still gives its credit, voucher or sessions (355). That is value
    -- given with no money, which is an Owner's or a Manager's to do (the
    -- Owner, 17 Nov 2026), so Make FOC on such a line is theirs too.
    if v_li.line_kind in ('credit_package', 'premium_bundle', 'voucher', 'therapy')
       and not public.is_owner_or_manager() then
      raise exception 'Only an Owner or Manager can make a Credit Package, Premium Bundle, voucher or therapy line free of charge.'
        using errcode = '42501'; end if;
  end if;$n$,
$n$    raise exception 'Inventory Manager cannot apply FOC';
  end if;
  -- 507: a voucher or therapy line given free is an Owner's or a Manager's
  -- to give (the Owner, 17 Nov 2026). Credit packages and bundles are not
  -- made free here at all (355).
  if not public.is_owner_or_manager()
     and exists (select 1 from jsonb_array_elements(p_items) x
                  where coalesce(x->>'kind','product') in ('voucher','therapy')
                    and (coalesce((x->>'foc_quantity')::integer,0) > 0 or coalesce((x->>'is_foc')::boolean,false))) then
    raise exception 'Only an Owner or Manager can make a Credit Package, Premium Bundle, voucher or therapy line free of charge.'
      using errcode = '42501';
  end if;$n$,
$n$      perform public.invoice_foc_reason(p_invoice_id,v_item);
    end if;
    -- 507: a voucher or therapy line that is new or changed is given free
    -- only by an Owner or a Manager (the Owner, 17 Nov 2026). A line kept as
    -- it was saved has already gone on above, so its FOC stays as it is.
    if v_foc_qty > 0 and v_kind in ('voucher','therapy') and not public.is_owner_or_manager() then
      raise exception 'Only an Owner or Manager can make a Credit Package, Premium Bundle, voucher or therapy line free of charge.'
        using errcode = '42501'; end if;$n$];
  -- Relied on, not changed
  c_relied constant text[] := array[
    'credit_line_paid_entitlement(uuid)',
    'is_owner_or_manager()',
    'confirm_foc_invoice(uuid,text)',
    'invoice_line_matches(uuid,jsonb)',
    'invoice_line_discount_only(uuid,jsonb)',
    'invoice_benefit_price_only(uuid,jsonb)'];
  c_relied_md5 constant text[] := array[
    'da2404a1db281b46a44231bd071a069a',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    'ba8b1ce2a5671989b927891f0cb7b1a2',
    '0c32f7c591efb9864ff5b1cb2201b744',
    'f1d4c93d4369d751d4c837a21bcf51cf',
    '6ffaa825083854f780a77f881523d04f'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  v_make boolean[] := array_fill(false, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  d text; i int;
begin
  perform set_config('lock_timeout', '5s', true);
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '507: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '507: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '507: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '507: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '507: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '507: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '507: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '507: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
