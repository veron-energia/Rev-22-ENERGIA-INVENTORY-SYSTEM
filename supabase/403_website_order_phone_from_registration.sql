-- 403_website_order_phone_from_registration.sql
--
-- WHAT WAS WRONG (found 8 Oct 2026)
--
--   The first real HitPay order on the seminar website's channel came in with
--   no buyer phone: HitPay passed on the buyer's email but no name and no
--   phone, so the website sent the name "Website buyer" and no phone.
--   web_order_paid kept it, and web_order_make_invoice put it in Needs review
--   with "The buyer's phone number could not be read, so the customer must be
--   chosen": web_order_customer finds a buyer by phone alone.
--
--   The next morning the buyer registered on the website, and its names
--   message carried the buyer's WhatsApp number (order.buyer.whatsapp).
--   web_order_names keeps only the name parts and the email of order.buyer:
--   it was written for buyers whose contacts come with the payment. So the
--   WhatsApp was dropped and the order kept waiting.
--
--   On the Event page, the Website orders tab's Create the invoice dialog then
--   offered the customers with the buyer's phone (none), "Create a new
--   customer" (which needs the phone, so it failed with the same reason) and
--   "Match automatically" (the same). There was no way to choose an existing
--   customer, although web_order_resolve takes any customer that exists and
--   is not deleted.
--
-- THE RULES (the Owner, 8 Oct 2026, final)
--
--   1. "Use it and retry": when the payment gave no phone and the
--      registration brings the buyer's WhatsApp, it becomes the order's buyer
--      phone, and the order is matched again exactly as an order of its
--      channel is at payment: one customer with that phone, an invoice for
--      them; none, a new customer with that phone (the channel's source and
--      details, the name the buyer registered with); two or more, the order
--      waits in Needs review with them as the candidates. A phone HitPay did
--      give is never overwritten.
--   2. "Yes, add a search": the Create the invoice dialog lets a Manager find
--      any existing customer by name, phone or email and choose them, beside
--      the options it has (the page; nothing here).
--   3. The order already waiting in production: staff choose its customer
--      with the new search. Nothing here changes data.
--   4. Guest lines whose WhatsApp is the buyer's: staff fix them by hand. How
--      guests are linked does not change.
--   5. "Hold back and wait": before the order is matched again (rule 1), when
--      the event already has a ticket invoice made by hand, and no website
--      order's, for the WhatsApp the registration brings, the order is not
--      invoiced. It keeps waiting in Needs review for a Manager, who links it
--      to that invoice (Link invoice) or, if it is another sale, creates its
--      invoice (Create invoice).
--
-- WHAT THIS DOES
--
--   web_order_names (patched; the service role's alone, as before):
--   * An order still waiting for its invoice (recorded, or needs review)
--     whose payment gave no phone takes the registration's
--     order.buyer.whatsapp, when that can be read, as its buyer_phone, in the
--     update that keeps the names. An audit row (web_orders,
--     web_order_phone_from_registration) keeps the phone it took. A phone
--     the payment gave is never replaced, even one the phone policy cannot
--     read (that order waits, as before, for staff to find the customer);
--     nor is one an earlier registration gave (a later registration with
--     another WhatsApp changes nothing; staff can still choose the customer).
--   * The order is then matched again when it waits only because its phone
--     could not be read (needs review, with exactly that reason), it now has
--     a phone that can be read, and its channel would have invoiced it at
--     payment: the channel is live, and it is not a test payment the channel
--     does not accept. The retry is web_order_paid's own call,
--     web_order_make_invoice(order), made after the names are kept: an
--     invoice made now carries the names the buyer registered, and a new
--     customer the name parts. 373's time rules are part of that call and are
--     judged now, as for any invoice made later than the payment: a
--     registration more than 7 days after the payment waits for a Manager to
--     check the payment in HitPay (a HitPay refund is not brought in), and
--     their Match automatically then uses the WhatsApp. A business refusal
--     puts the order back in review with the new reason and the candidates
--     (web_order_make_invoice). A passing fault keeps the names and the
--     phone; the website does not send names it has had an answer to again,
--     so the order waits for staff with a reason that says the invoice must
--     be created (Match automatically then uses the WhatsApp).
--   * Before an order is matched again, as above, an invoice made by hand
--     holds it back: web_order_hand_invoices, the list's hint, finds a ticket
--     invoice of the channel's event that is not deleted, cancelled or
--     refunded, is no website order's, and has the phone on its customer or
--     on one of its guests. The order then keeps waiting in Needs review,
--     with a reason that says so and the customers with the phone as its
--     candidates; no invoice or customer is made, and the names, the phone
--     and its audit row are kept as above. The website is answered as for
--     any waiting order. The list shows its hint ("Possibly already invoiced
--     by hand"), and a Manager links the order (Link invoice) or creates its
--     invoice (Create invoice; Match automatically uses the WhatsApp). The
--     reason is no longer the phone's, so names sent again do not match it.
--   * A recorded order on a live channel is matched when its names come, as
--     it always was (by the WhatsApp, when it took one); that first match is
--     not held, as at payment.
--   * On a record-only or off channel the phone is only kept: a Manager's
--     Create invoice (Match automatically) then uses it.
--   * The rest is as before: names that do not fit the number of people are
--     not used (nor is the WhatsApp); an invoiced or refused order takes no
--     phone and is never matched again (an invoiced one is renamed, as
--     before); staff-link orders are never reached.
--   web_orders_list (patched; Owners, Admins and Managers, as before): each
--   order also carries buyer_first_name and buyer_last_name (the page shows
--   the registered name where the payment gave "Website buyer"),
--   buyer_phone_readable (whether the phone policy reads the buyer phone) and
--   buyer_phone_from_registration (whether it came from the registration:
--   its audit row).
--
-- NOT CHANGED
--
--   * No table, column, constraint or row. No new function, so no new grant;
--     the two patched functions keep theirs.
--   * web_order_paid, web_order_make_invoice, web_order_customer,
--     web_order_resolve, web_order_phone_customers and the phone policy
--     (normalize_customer_phone): the retry calls them as they are.
--     web_order_resolve already takes any customer that exists and is not
--     deleted, which is what the page's new search sends.
--   * Guests: web_order_people still gives the buyer's line the first
--     person's WhatsApp, else the buyer phone; web_order_rename_people keeps
--     what staff set on a guest. No guest is linked to a customer by phone.
--   * The staff link (web_order_door), the website's sync (web_order_sync;
--     it sends a phone taken from the registration as the order's
--     buyer_phone, as it sends any) and the guest list (event_guest_list).
--   * web_order_hand_invoices, called as it is. The website calls with no
--     store access, so the hold is judged by the invoices it finds, never by
--     their numbers (which it gives only to staff of the invoice's store).
--   * At payment (web_order_paid) an invoice made by hand for the event with
--     the payment's phone still does not hold the order back; nor at a
--     recorded order's first match when its names come.
--   * Production's waiting order: no data changes. Its names are in, and the
--     website does not send names it has had an answer to again, so this does
--     not reach it: staff choose its customer with the page's search.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block),
-- so it is atomic however it is run. Every guard and anchor is checked, and
-- every patched text built, before anything is installed. md5(pg_get_
-- functiondef) of each patched function must be the production version read
-- on 8 Oct 2026 (BEFORE), or already this migration's version (AFTER), which
-- is left alone so a re-run changes nothing. The functions relied on but not
-- changed must be the versions read on 8 Oct 2026. Every anchor must match
-- exactly once. Patches are executed as CREATE OR REPLACE, which keeps owner
-- and grants; no overload is added (another function of either name
-- refuses). The definitions are read and compared with the search path set
-- to public, as they were read. After installing, both functions must have
-- their AFTER md5, and their grants must be the ones they had: web_order_names
-- the service role's alone, web_orders_list staff's and the service role's,
-- neither callable signed out. No data changes.
--
-- BEFORE (production, 8 Oct 2026, md5 of pg_get_functiondef):
--   web_order_names(jsonb)                                          aa7926944b7cfb4a5d549c62c298cdb3
--   web_orders_list(uuid)                                           fa7b5e6baaac862b3435779d59bfa6b1
--   (relied on, not changed)
--   web_order_paid(jsonb)                                           2b9aa2607e6ce7918216cf064d969f4a
--   web_order_make_invoice(uuid,uuid,boolean,boolean)               a89168963591c78841c5dc37c12162b8
--   web_order_customer(web_orders,web_order_channels,uuid,boolean)  0b362a76ac3b0f161abc9bfd1a001b20
--   web_order_resolve(uuid,uuid,boolean)                            19736dc2ca96cf2b01a6a5bbfc9c9b49
--   web_order_phone_customers(text)                                 7a42cbcbbfadd5b91e7aa3a41b68c7e8
--   web_order_hand_invoices(web_orders,web_order_channels)          11622af802bf89cd0fec4fb02d1970b9
--   normalize_customer_phone(text)                                  b2bfac910e0c9eff402ba44e19750bee
--   web_order_people(web_orders,uuid)                               3ae3ffcdbac166868e3e06ec45485b37
--   web_order_apply_names(uuid)                                     863426cdc5cd8d07acc2a12893e18210
--   web_order_rename_people(uuid)                                   6cee4a256e7ce27d40f6889ba044da58
--   web_order_door(jsonb)                                           72401d643162c7082f7d15f39ab88de0
--   web_order_sync(text)                                            69dcb1b15f20f7343c1976efa8318b44
--   event_guest_list(uuid)                                          cbe2f3ef06fe97e59fc2e3b19fd35cac
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)  c705c733e213a27f0dc32d54322cc855
-- AFTER (for later guards):
--   web_order_names(jsonb)                                          ee0f8373fad4bfb71850574553d5fe1c
--   web_orders_list(uuid)                                           f81cb1da6aaf379f8a1c7233371602b9
--
-- DEPLOY ORDER: this, then the page (it reads the new fields as optional, so
-- the page live now keeps working; the new page against a database without
-- this shows the payment's name and offers the search, which works already).
-- The edge function and the website are unchanged.
--
-- Test: scripts/web-orders/tests/registration-phone.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── Anchors and their replacements ─────────────────────────────────────────
  c_names_decl_a constant text :=
       E'declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v_att jsonb; v_note text; v_same boolean;\n';
  c_names_decl_r constant text :=
       E'declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v_att jsonb; v_note text; v_same boolean;\n'
    || E'  v403_phone text; v403_retry boolean;  -- 403: the WhatsApp the buyer registered with; whether to match again\n'
    || E'  v403_now public.web_orders%rowtype; v403_hold boolean := false;  -- 403: the order with that phone; held back by an invoice made by hand\n';
  c_names_phone_a constant text :=
       E'  update public.web_orders\n'
    || E'     set attendees = v_att, names_at = now(),\n';
  c_names_phone_r constant text :=
       E'  -- 403: an order still waiting for its invoice whose payment gave no phone\n'
    || E'  -- (HitPay gave none) takes the WhatsApp the buyer registered with, when\n'
    || E'  -- that can be read (the Owner, 8 Oct 2026). A phone the payment gave is\n'
    || E'  -- never replaced, even one the phone policy cannot read; nor is one an\n'
    || E'  -- earlier registration gave.\n'
    || E'  if o.status in (''recorded'', ''needs_review'') and nullif(btrim(coalesce(o.buyer_phone, '''')), '''') is null\n'
    || E'     and public.normalize_customer_phone(p_order->''buyer''->>''whatsapp'') is not null then\n'
    || E'    v403_phone := btrim(p_order->''buyer''->>''whatsapp'');\n'
    || E'  end if;\n'
    || E'  update public.web_orders\n'
    || E'     set attendees = v_att, names_at = now(),\n';
  c_names_set_a constant text :=
       E'         buyer_email = coalesce(nullif(btrim(coalesce(p_order->''buyer''->>''email'', '''')), ''''), buyer_email),\n'
    || E'         updated_at = now()\n'
    || E'   where id = o.id;\n';
  c_names_set_r constant text :=
       E'         buyer_email = coalesce(nullif(btrim(coalesce(p_order->''buyer''->>''email'', '''')), ''''), buyer_email),\n'
    || E'         buyer_phone = coalesce(v403_phone, buyer_phone),  -- 403\n'
    || E'         updated_at = now()\n'
    || E'   where id = o.id;\n'
    || E'  if v403_phone is not null then\n'
    || E'    perform public.write_audit_ex(''web_orders'', o.id, ''web_order_phone_from_registration'',\n'
    || E'      jsonb_build_object(''buyer_phone'', o.buyer_phone),\n'
    || E'      jsonb_build_object(''buyer_phone'', v403_phone, ''order_id'', o.stripe_session_id), ''events'', null, ch.store_id);\n'
    || E'  end if;\n'
    || E'  -- 403: an order that waits only because its phone could not be read is\n'
    || E'  -- matched again once it has one, as it would have been at payment: on a\n'
    || E'  -- live channel (below), and not for a test payment the channel does not\n'
    || E'  -- accept.\n'
    || E'  v403_retry := o.status = ''needs_review''\n'
    || E'    and coalesce(o.review_reason, '''') = ''The buyer''''s phone number could not be read, so the customer must be chosen''\n'
    || E'    and (o.livemode or ch.allow_test)\n'
    || E'    and public.normalize_customer_phone(coalesce(v403_phone, o.buyer_phone)) is not null;\n'
    || E'  -- 403: before an order is matched again, a ticket invoice made by hand\n'
    || E'  -- for the event with its phone, and no website order''s, holds it back\n'
    || E'  -- for a Manager: Link invoice, or Create invoice if it is another sale\n'
    || E'  -- (the Owner, 8 Oct 2026: "Hold back and wait"). It is the list''s hint,\n'
    || E'  -- asked of the order with the phone it now has; only whether it finds an\n'
    || E'  -- invoice counts (the website has no store access, so it is given no\n'
    || E'  -- numbers). The order already waits, so only its reason and candidates\n'
    || E'  -- change. A recorded order''s first match is not held, as at payment.\n'
    || E'  if v403_retry and ch.mode = ''live'' then\n'
    || E'    v403_now := o;\n'
    || E'    v403_now.buyer_phone := coalesce(v403_phone, o.buyer_phone);\n'
    || E'    v403_hold := public.web_order_hand_invoices(v403_now, ch) <> ''[]''::jsonb;\n'
    || E'  end if;\n'
    || E'  if v403_hold then\n'
    || E'    update public.web_orders\n'
    || E'       set review_reason = ''The buyer''''s WhatsApp from the registration is on a ticket invoice made by hand for this event: use Link invoice if that invoice is this order''''s, otherwise Create invoice'',\n'
    || E'           candidate_customer_ids = public.web_order_phone_customers(public.normalize_customer_phone(v403_now.buyer_phone)),\n'
    || E'           updated_at = now()\n'
    || E'     where id = o.id;\n'
    || E'  end if;\n';
  c_names_retry_a constant text :=
       E'  elsif o.status = ''recorded'' and ch.mode = ''live'' then\n';
  c_names_retry_r constant text :=
       E'  elsif (o.status = ''recorded'' or v403_retry) and ch.mode = ''live'' and not v403_hold then\n';
  c_names_fault_a constant text :=
       E'      -- next delivery of the payment, or by staff.\n'
    || E'      return jsonb_build_object(''status'', ''recorded'', ''invoice_no'', null,\n';
  c_names_fault_r constant text :=
       E'      -- next delivery of the payment, or by staff. 403: the website does not\n'
    || E'      -- send names it has had an answer to again, so an order matched again\n'
    || E'      -- waits for staff, with its phone and a reason that says so.\n'
    || E'      if v403_retry then\n'
    || E'        update public.web_orders\n'
    || E'           set review_reason = ''The invoice could not be made when the buyer''''s WhatsApp came with the registration, so it must be created'',\n'
    || E'               updated_at = now()\n'
    || E'         where id = o.id;\n'
    || E'        return jsonb_build_object(''status'', ''needs_review'', ''invoice_no'', null,\n'
    || E'          ''review_reason'', ''The invoice could not be made when the buyer''''s WhatsApp came with the registration, so it must be created'');\n'
    || E'      end if;\n'
    || E'      return jsonb_build_object(''status'', ''recorded'', ''invoice_no'', null,\n';

  c_list_a constant text :=
       E'               ''buyer_name'', o.buyer_name, ''buyer_email'', o.buyer_email, ''buyer_phone'', o.buyer_phone,\n';
  c_list_r constant text :=
       E'               ''buyer_name'', o.buyer_name, ''buyer_email'', o.buyer_email, ''buyer_phone'', o.buyer_phone,\n'
    || E'               -- 403: the name parts the buyer registered with, whether the phone\n'
    || E'               -- can be read, and whether it came from the registration.\n'
    || E'               ''buyer_first_name'', o.buyer_first_name, ''buyer_last_name'', o.buyer_last_name,\n'
    || E'               ''buyer_phone_readable'', public.normalize_customer_phone(o.buyer_phone) is not null,\n'
    || E'               ''buyer_phone_from_registration'', exists (select 1 from public.audit_logs a\n'
    || E'                                                         where a.record_id = o.id and a.table_name = ''web_orders''\n'
    || E'                                                           and a.action = ''web_order_phone_from_registration''),\n';

  c_names_after constant text := 'ee0f8373fad4bfb71850574553d5fe1c';
  c_list_after constant text := 'f81cb1da6aaf379f8a1c7233371602b9';

  v_path text := current_setting('search_path');
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
begin
  -- pg_get_functiondef names a parameter's type as the search path shows it,
  -- so the definitions are read and compared with public alone, as they were
  -- read on 8 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    ('web_order_names(jsonb)', 'aa7926944b7cfb4a5d549c62c298cdb3', c_names_after,
     array[[c_names_decl_a, c_names_decl_r], [c_names_phone_a, c_names_phone_r], [c_names_set_a, c_names_set_r],
           [c_names_retry_a, c_names_retry_r], [c_names_fault_a, c_names_fault_r]]),
    ('web_orders_list(uuid)', 'fa7b5e6baaac862b3435779d59bfa6b1', c_list_after, array[[c_list_a, c_list_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '403: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '403: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '403: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '403: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  -- Relied on, not changed: the versions read on 8 Oct 2026 (how an order is
  -- handed in, invoiced and matched by phone, which the retry repeats; the
  -- invoices made by hand that hold it back; the people and names on its
  -- ticket; what staff call; the staff link, the sync and the guest list,
  -- which read the buyer phone; the audit row).
  for r in select * from (values
    ('web_order_paid(jsonb)', '2b9aa2607e6ce7918216cf064d969f4a'),
    ('web_order_make_invoice(uuid,uuid,boolean,boolean)', 'a89168963591c78841c5dc37c12162b8'),
    ('web_order_customer(public.web_orders,public.web_order_channels,uuid,boolean)', '0b362a76ac3b0f161abc9bfd1a001b20'),
    ('web_order_resolve(uuid,uuid,boolean)', '19736dc2ca96cf2b01a6a5bbfc9c9b49'),
    ('web_order_phone_customers(text)', '7a42cbcbbfadd5b91e7aa3a41b68c7e8'),
    ('web_order_hand_invoices(public.web_orders,public.web_order_channels)', '11622af802bf89cd0fec4fb02d1970b9'),
    ('normalize_customer_phone(text)', 'b2bfac910e0c9eff402ba44e19750bee'),
    ('web_order_people(public.web_orders,uuid)', '3ae3ffcdbac166868e3e06ec45485b37'),
    ('web_order_apply_names(uuid)', '863426cdc5cd8d07acc2a12893e18210'),
    ('web_order_rename_people(uuid)', '6cee4a256e7ce27d40f6889ba044da58'),
    ('web_order_door(jsonb)', '72401d643162c7082f7d15f39ab88de0'),
    ('web_order_sync(text)', '69dcb1b15f20f7343c1976efa8318b44'),
    ('event_guest_list(uuid)', 'cbe2f3ef06fe97e59fc2e3b19fd35cac'),
    ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '403: public.% is missing or not the version read on 8 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- No other function takes these names (the API picks an overload by name).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('web_order_names', 'web_orders_list')
              and p.oid::regprocedure::text not in ('web_order_names(jsonb)', 'web_orders_list(uuid)')) then
    raise exception '403: another overload of web_order_names or web_orders_list exists'; end if;
  select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text) into v_acl
    from pg_proc p where p.oid in ('public.web_order_names(jsonb)'::regprocedure, 'public.web_orders_list(uuid)'::regprocedure);

  -- ── Install ─────────────────────────────────────────────────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('web_order_names(jsonb)', c_names_after),
    ('web_orders_list(uuid)', c_list_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '403: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The grants they had: the website's message is the service role's alone;
  -- the list is staff's (it checks the role itself); neither is callable
  -- signed out.
  if (select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p where p.oid in ('public.web_order_names(jsonb)'::regprocedure, 'public.web_orders_list(uuid)'::regprocedure))
     is distinct from v_acl then
    raise exception '403: the grants of web_order_names or web_orders_list changed'; end if;
  if has_function_privilege('anon', 'public.web_order_names(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.web_order_names(jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.web_order_names(jsonb)', 'execute') then
    raise exception '403: public.web_order_names(jsonb) is not the service role''s alone'; end if;
  if has_function_privilege('anon', 'public.web_orders_list(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.web_orders_list(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.web_orders_list(uuid)', 'execute') then
    raise exception '403: public.web_orders_list(uuid) is not staff''s and the service role''s alone'; end if;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
