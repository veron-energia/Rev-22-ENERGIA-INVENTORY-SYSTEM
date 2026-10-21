-- 441_event_website_holds_merged_records_phones.sql
--
-- THE EVENT WEBSITE HOLDS A REGISTRATION ON A PHONE OR EMAIL INBOX THAT ONLY
-- A MERGED-AWAY RECORD HAD (the owner's answer, 21 Oct 2026, ~11:40, to 439's
-- open question: "Yes, in a later update")
--
-- WHAT WAS WRONG / WHY
--
--   439 made To match follow a merge for registrations held BEFORE it. A
--   registration made AFTER a merge was not covered (439's NOT COVERED): when
--   two customer records are merged (merge_customer_records; its audit row
--   customers_merged), the retired record keeps its phone and email, and the
--   kept record takes them only when staff tick the box on 437's Link (by
--   default it does not). A later registration on that phone or inbox found
--   nobody holding it (event_web_match_customer looks at live records only),
--   so the person was made a new customer at once and, through an affiliate's
--   link, became her referral at once: no Owner's or Manager's check, and
--   commission on their VIP straight away, although the phone or inbox
--   belongs to a customer the app still has (under the record that kept it).
--
-- THE RULES (binding)
--
--   The owner's answer, 21 Oct 2026, ~11:40 (439's open decision: whether
--   the phones and email inboxes of records retired by a merge count as held
--   by the kept record, in event_web_phone_holders / event_web_match_customer):
--   "Yes, in a later update."
--   So: someone who registers on such a phone or inbox is HELD under To match
--   and waits for the same staff check as anyone on another customer's phone
--   or inbox: no commission until an Owner or Manager confirms a different
--   person; earned once after (dated the confirm day, as 436's trigger does);
--   none if the same person.
--   Every earlier answer in 436's and 439's THE RULES stands as written there.
--   How it reads (this file, 21 Oct 2026):
--   * "Retired by a merge" is 439's: a deleted record that a customers_merged
--     row names in merged_from, followed along a chain to the live record that
--     kept it (event_web_kept_customer). A record deleted any other way, or
--     whose chain ends in one, holds nothing (as before).
--   * What it holds is what 439 reads: its phone as 425 reads a phone (an old
--     8-digit number included) and its email inbox (432's
--     customer_email_match_key), from the retired record, which
--     merge_customer_records leaves as it was.
--   * At registration (event_web_match_customer, the one decision point:
--     event_web_register stores what it says), when no live customer's phone
--     and name link them (432, unchanged: a retired record's phone never links
--     anyone, even under its own name or the kept record's), the retired
--     record counts like another customer holding the phone (phone_in_use),
--     the inbox (email_in_use) or both (phone_and_email_in_use). The retired
--     record is their candidate, as a merge after the hold leaves it (439):
--     To match lists the record that kept it (merged_from: the retired one,
--     its phone and email, which matched), attaching to it attaches to the
--     kept record (an existing customer: not referred), making a new customer
--     counts the kept record as the holder (439's event_web_new_customer), so
--     through a valid link they wait for the check (phone_shared_with: the
--     kept record), and the note says "Their phone was on <retired>'s record,
--     since merged into <kept>'s (listed)" (439's wording).
--   * Through any link or none, as 436's To match rule (only the phone or
--     only the email inbox belongs to someone: held for staff). Without a
--     link nobody is referred whatever staff do (as 436).
--   * When the kept record holds the phone (or the inbox) itself (437's
--     ticked Link, or the same number on both), the retired record adds
--     nothing for it: the hold is 436's, word for word (the same candidates,
--     reason and note). When another live customer has the phone too, the
--     retired record is listed beside them (To match shows the kept record
--     with it, and a check shares with both): the phone is held by both. The
--     reason, the note and what staff can do are 436's.
--   * The affiliate's own merged record (merged into hers): someone on its
--     phone or inbox is held like someone on her live phone (her record the
--     one listed, 439's "shares the phone of ..." note), and made a customer
--     waits for the check. 439 made them a customer at once, waiting for the
--     check; now staff see them under To match first, as for her live phone.
--     She herself, under that record's name, is held as herself (self), as
--     before.
--
-- WHAT THIS DOES
--
--   1. event_web_match_customer (the service role's): after the live phone
--      and inbox holders (436), the records retired by a merge whose phone or
--      inbox it is, kept by a live record that does not hold it itself, are
--      holders too (their ids the candidates, beside the live holders). The
--      retired records are read first (a few dozen, materialized), and only
--      those whose phone or inbox matches are followed to the record that
--      kept them (event_web_kept_customer), so a registration costs no audit
--      log search for the others.
--   Every caller of it (event_web_register for the live and the test key; its
--   test outcome) follows it unchanged; 439's functions (To match, attach,
--   make a customer, the notes) already read a retired candidate.
--
-- NOT CHANGED
--
--   Every other function, table and grant: 436's (event_web_register,
--   event_web_phone_holders: "on a customer's record now" stays live records
--   only, as 439's notes read it), 439's (event_web_kept_customer,
--   event_web_new_customer, event_web_referral_note, event_web_guest_extras,
--   event_registration_attach), event_web_affiliate_contact and
--   event_web_check_self_referral (440 patched them; not pinned: this file
--   works with 439's or 440's), 437's and 438's functions, invoice_action_plan,
--   cancelled_invoice_used_value, merge_customer_records and the 432-family
--   helpers (used as they are). event_web_match_customer keeps its grant (the
--   service role's alone).
--
-- NOT COVERED (to tell the owner)
--
--   * Only the event website. 425's /r/<code> referral sign-up, 433's QR
--     survey and 432's affiliate sign-up still look at live records only: a
--     referral-page sign-up on a phone only a merged-away record had is still
--     referred at once (a later migration, each with its own review).
--   * 437's Link box (AffiliatesPage.tsx, "phone-outcome") still says a later
--     website or referral-page registration on the sign-up phone will not find
--     the kept record. After 441 that is true of the referral page only (a
--     wording follow-up on the page, 437's).
--   * Attaching a held person to the kept record does not put the phone on
--     it: the next registration on that phone is held again (staff can add
--     the number on the Customers page; up to 3 customers share a phone).
--   * The note's "Their phone was on X's record, since merged into Y's" is
--     439's wording for a merge after the hold; it is said also when the
--     merge came before the registration (both true). Test registrations get
--     436's note ("Their phone is on another customer's record"), as 439
--     leaves test rows.
--   * Someone made a customer and referred at once before 441 (on such a
--     phone or inbox) stays referred; nothing is re-checked.
--   * Several retired records with the phone (a chain, or two merged into the
--     same record) are each a candidate; To match shows the record that kept
--     them once, with each under merged_from (439).
--   * A record merged into another, then restored (restore_customer_with_phone)
--     and later deleted some other way (delete_customer), is still read as
--     retired by its merge (439's event_web_kept_customer follows the merge
--     row and does not look for a later restore): someone on its phone or
--     inbox (a phone given at the restore too) is held for the record it was
--     once merged into, and the note says it was merged into it. The safe
--     side (held for staff, never referred at once); found by the review of
--     21 Oct 2026, left for a later look at 439's helper.
--
-- DEPLOY ORDER (each step with the owner's go-ahead)
--
--   After 439, 440, 442 and 443 (all live: 440 = 20261021042352, file md5
--   0a8cf44a...; 442 = 20261021055615, a9ef5f2f...; 443 = 20261021100717,
--   c73ae7d7...; production then 1fbce365ba02d5ccf3956045a7982ac0, 1370
--   functions: 436, 438, 437, 439, 440, 442, 443 applied), the order agreed
--   with their session. It pins none of the functions 440, 442 and 443
--   changed (event_web_affiliate_contact, event_web_check_self_referral,
--   complete_affiliate_onboarding, affiliate_referral_signup; 443's payment
--   and credit functions) and they pin none of the one it changes. Checked
--   on copies, 21 Oct 2026: production as it is (1fbce365) -> 441 ends at
--   d8bfc0b83af95d114f2d9f8f2489d3e0 (1370), and a second run changes
--   nothing; this file's suite, 436's, 439's, 440's (login-identity-440.sql),
--   442's (referral-self-442.sql) and 443's (credit-sources-443.sql, each
--   -v nomig=1), and main's function-grants.sql and staff-only-functions.sql
--   pass after it. Earlier stages, for reference: 439 -> 441 e3c1f966...
--   (1364); 440 -> 441 a1532db9... (1366); 442 -> 441 12bce291... (1366).
--   1. Dry run on a copy of production as it is then: apply this file twice.
--      The first run ends with the fingerprint below; the second says
--      "already this version; left alone" and changes nothing. A refusal
--      names the function that moved since 439.
--   2. Apply this file (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself (the AFTER md5, the grant, its self-test,
--      which leaves no row).
--   3. Nothing else: the Event page already lists a retired candidate as the
--      record that kept it (439).
--
-- SAFETY
--
--   ONE statement (a single DO block), atomic whatever runs it; every check
--   before anything is changed:
--   * every function it relies on and does not change is as 439 left it
--     (below); the columns it reads are as read.
--   * event_web_match_customer is 436's AFTER (patched, each anchor found
--     once, the text built has the tested md5) or already this file's AFTER
--     (left alone); anything else is refused.
--   * afterwards its md5 is the AFTER one and its grant is unchanged (the
--     service role's alone).
--   * a self-test, in a block that is always undone (it ends by raising
--     P0441, so it leaves no row): a made-up Owner, store, event, live key,
--     an affiliate, a record merged into another that did not take its phone
--     or email; one form through her link: someone on the merged-away phone
--     and someone on its inbox are held for it (no customer made), someone on
--     a new phone and inbox is referred at once; made a customer, the first
--     waits for the check, shared with the kept record; the second attached to
--     the retired id lands on the kept record, already a customer.
--
-- BEFORE (production after 443, pg_get_functiondef with search_path public):
--   changed
--   event_web_match_customer(text,text,text)                       16ec3e9f65d619b3f3feeef712bfd132  (436's AFTER)
--   relied on, not changed
--   event_web_kept_customer(uuid)                                  cb0720c1088df9209da45e46b91601f4  (439)
--   event_web_new_customer(uuid)                                   a253f76a9db721212a9c110bc41ff483  (439)
--   event_web_referral_note(uuid)                                  d68893db63938cc774b157708bd341f1  (439)
--   event_web_guest_extras(uuid)                                   18b56a28bb4965b2188cd73dde056209  (439, page)
--   event_registration_attach(uuid,uuid,text)                      b31be4d82d20000df026e7cfa9b24095  (439, page)
--   event_registration_create_customer(uuid,text)                  23bc6941cd4b4db0fae101965292a324
--   event_web_register(uuid,jsonb)                                 e3efd309e81d17c97f7984f7ecbaafff
--   event_web_apply_referral(uuid,uuid)                            b034075f9882cb4221e3a554e6453317
--   event_web_phone_holders(text)                                  614602e9cbc483d79bdef7d60aaf6a33
--   event_web_call(text,uuid,text,jsonb)                           e114ba39de4923cc52ed426e27d9bfde
--   trg_event_web_referral_check_decided()                         9dea4cead38c8c990ad46f435d787520
--   customer_phone_name_matches(text,text)                         1bdf8322972b6671b7cbb08bc8211f8a
--   require_resolved_customer_identity(text,text)                  5bde1a418363442ec27e2944442f5874
--   normalize_customer_phone(text)                                 b2bfac910e0c9eff402ba44e19750bee
--   inspect_customer_phone(text,text)                              6672c4d1963996f3b601896f4a55916e
--   customer_email_match_key(text)                                 be468815c9626fff1728e2cfcd484b66
--   customer_names_match(text,text)                                ef1af52e4888cefb6037a2291f4e011d
--   normalize_customer_match_name(text)                            0572764712e179dc606c66f9f3dbaa03
--   merge_customer_records(uuid,uuid,text,uuid)                    099ecf3aae30b5faaf8fb36bc15ce888
--   public function fingerprint (production after 443)             1fbce365ba02d5ccf3956045a7982ac0 (1370 functions)
-- AFTER (for later guards):
--   event_web_match_customer(text,text,text)                       9da726006d8055983491b5ec1da1679b
--   public function fingerprint (production after 443, then 441)   d8bfc0b83af95d114f2d9f8f2489d3e0 (1370 functions)
--   ... on a copy after 442, no 443                                12bce2915a6566e4e5da73f1c69a0306 (1366 functions)
--   ... on a copy after 440, no 442                                a1532db9c4183a65501b9010c0b83361 (1366 functions)
--   ... on a copy with 439, no 440                                 e3c1f9665eb6fed29c4ce35603610660 (1364 functions)
--
-- Test: scripts/event-website/tests/event-website-441.sql (begin ... rollback; it installs
-- this file twice, or -v skip_install=1 where it is installed); 436's event-website.sql and
-- event-website-separate-tx.sql, 439's event-website-439.sql (each with -v skip_install=1) and
-- scripts/permissions/tests/function-grants.sql pass with it. 439's suite checks 441's outcome
-- in the four cases 441 changes (MD2, MD3, MR1, MR3: held first) where 441 is installed.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The function it changes: BEFORE (436's AFTER) and AFTER ──
  c_sig constant text := 'event_web_match_customer(text,text,text)';
  c_before constant text := '16ec3e9f65d619b3f3feeef712bfd132';
  c_after constant text := '9da726006d8055983491b5ec1da1679b';
  -- each anchor (found once in the BEFORE text) and its patch, in order
  c_anchor constant text[] := array[
$a01$declare v_matches uuid[]; v_kind text; v_holders uuid[]; v_email_key text; v_email_holders uuid[]; v_legacy uuid[];
begin
$a01$,
$a02$   where v_email_key is not null and c.deleted_at is null and public.customer_email_match_key(c.email) = v_email_key;
  if cardinality(v_holders) > 0 or cardinality(v_email_holders) > 0 then
    return jsonb_build_object('kind', 'held',
      'hold_reason', case when cardinality(v_holders) > 0 and cardinality(v_email_holders) > 0 then 'phone_and_email_in_use'
                          when cardinality(v_holders) > 0 then 'phone_in_use' else 'email_in_use' end,
      'candidates', (select coalesce(jsonb_agg(distinct x), '[]'::jsonb) from unnest(v_holders || v_email_holders) x));
  end if;
$a02$];
  c_patch constant text[] := array[
$p01$declare v_matches uuid[]; v_kind text; v_holders uuid[]; v_email_key text; v_email_holders uuid[]; v_legacy uuid[];
  v_merged_phone uuid[]; v_merged_mail uuid[];
begin
$p01$,
$p02$   where v_email_key is not null and c.deleted_at is null and public.customer_email_match_key(c.email) = v_email_key;
  -- 441 (the owner, 21 Oct 2026, ~11:40): a record a merge retired
  -- (merge_customer_records; its customers_merged row) holds its phone (as 425
  -- reads a phone, an old number included) and email inbox for the live record
  -- that kept it (event_web_kept_customer, along a chain), when that record
  -- does not hold them itself (437's unticked Link): someone else on them is
  -- held for staff like anyone on another customer's phone or inbox, the
  -- retired record their candidate (439 lists it as the kept record, attaches
  -- to that, and makes them wait for the check when made a customer). It never
  -- links anyone: only a live record's own phone and name do (above). The
  -- retired records are read first, and only those that match are followed.
  with m as materialized (
    select c.id,
           coalesce(public.normalize_customer_phone(c.phone) = p_phone_norm
                    or (public.normalize_customer_phone(c.phone) is null and c.phone ~ '^[\s().0-9-]+$'
                        and (public.inspect_customer_phone(c.phone)->'candidates') ? p_phone_norm), false) as by_phone,
           coalesce(public.customer_email_match_key(c.email) = v_email_key, false) as by_mail
      from public.customers c
     where c.deleted_at is not null),
  k as materialized (
    select m.id, m.by_phone, m.by_mail, public.event_web_kept_customer(m.id) as kept
      from m where m.by_phone or m.by_mail)
  select coalesce(array_agg(k.id order by k.id) filter (where k.by_phone and not (k.kept = any (v_holders))), '{}'::uuid[]),
         coalesce(array_agg(k.id order by k.id) filter (where k.by_mail and not (k.kept = any (v_email_holders))), '{}'::uuid[])
    into v_merged_phone, v_merged_mail
    from k
   where k.kept is not null;
  if cardinality(v_holders) + cardinality(v_merged_phone) > 0 or cardinality(v_email_holders) + cardinality(v_merged_mail) > 0 then
    return jsonb_build_object('kind', 'held',
      'hold_reason', case when cardinality(v_holders) + cardinality(v_merged_phone) > 0
                               and cardinality(v_email_holders) + cardinality(v_merged_mail) > 0 then 'phone_and_email_in_use'
                          when cardinality(v_holders) + cardinality(v_merged_phone) > 0 then 'phone_in_use' else 'email_in_use' end,
      'candidates', (select coalesce(jsonb_agg(distinct x), '[]'::jsonb)
                       from unnest(v_holders || v_email_holders || v_merged_phone || v_merged_mail) x));
  end if;
$p02$];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; i int; v_text text; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_event uuid; t_live text; t_hash text;
  t_aff uuid; t_gone uuid; t_keep uuid; t_ans jsonb; t_p1 uuid; t_p2 uuid; t_p3 uuid; t_c1 uuid; t_c3 uuid;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 21 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is changed unless all pass ──────────────────────
  -- What it relies on and does not change: as 439 left it (21 Oct 2026).
  for r in select * from (values
      ('event_web_kept_customer(uuid)', 'cb0720c1088df9209da45e46b91601f4'),
      ('event_web_new_customer(uuid)', 'a253f76a9db721212a9c110bc41ff483'),
      ('event_web_referral_note(uuid)', 'd68893db63938cc774b157708bd341f1'),
      ('event_web_guest_extras(uuid)', '18b56a28bb4965b2188cd73dde056209'),
      ('event_registration_attach(uuid,uuid,text)', 'b31be4d82d20000df026e7cfa9b24095'),
      ('event_registration_create_customer(uuid,text)', '23bc6941cd4b4db0fae101965292a324'),
      ('event_web_register(uuid,jsonb)', 'e3efd309e81d17c97f7984f7ecbaafff'),
      ('event_web_apply_referral(uuid,uuid)', 'b034075f9882cb4221e3a554e6453317'),
      ('event_web_phone_holders(text)', '614602e9cbc483d79bdef7d60aaf6a33'),
      ('event_web_call(text,uuid,text,jsonb)', 'e114ba39de4923cc52ed426e27d9bfde'),
      ('trg_event_web_referral_check_decided()', '9dea4cead38c8c990ad46f435d787520'),
      ('customer_phone_name_matches(text,text)', '1bdf8322972b6671b7cbb08bc8211f8a'),
      ('require_resolved_customer_identity(text,text)', '5bde1a418363442ec27e2944442f5874'),
      ('normalize_customer_phone(text)', 'b2bfac910e0c9eff402ba44e19750bee'),
      ('inspect_customer_phone(text,text)', '6672c4d1963996f3b601896f4a55916e'),
      ('customer_email_match_key(text)', 'be468815c9626fff1728e2cfcd484b66'),
      ('customer_names_match(text,text)', 'ef1af52e4888cefb6037a2291f4e011d'),
      ('normalize_customer_match_name(text)', '0572764712e179dc606c66f9f3dbaa03'),
      ('merge_customer_records(uuid,uuid,text,uuid)', '099ecf3aae30b5faaf8fb36bc15ce888')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '441: public.% is missing or not the version this was tested against (439 as applied). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns 441 reads, as read on 21 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('public.customers', 'id uuid'), ('public.customers', 'phone text'), ('public.customers', 'email text'),
      ('public.customers', 'deleted_at timestamp with time zone'),
      ('public.event_registration_people', 'candidate_customer_ids uuid[]'), ('public.event_registration_people', 'hold_reason text'),
      ('public.event_registration_people', 'match text'), ('public.event_registration_people', 'referral_outcome text')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '441: these columns are missing or not as read on 21 Oct 2026: %', v; end if;

  -- The function: BEFORE (patched, each anchor once) or AFTER (left alone).
  if to_regprocedure('public.' || c_sig) is null then
    raise exception '441: public.% is missing (is 436 applied?)', c_sig; end if;
  d := pg_get_functiondef(('public.' || c_sig)::regprocedure);
  v_acl := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sig)::regprocedure);
  if md5(d) = c_after then
    raise notice '441: public.% is already this version; left alone', c_sig;
  elsif md5(d) <> c_before then
    raise exception '441: public.% is not 436''s version (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  else
    for i in 1 .. cardinality(c_anchor) loop
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then raise exception '441: anchor % of public.% was found % times, not once', i, c_sig, n; end if;
      d := replace(d, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_after then
      raise exception '441: the text built for public.% is not the tested one (md5 %)', c_sig, md5(d); end if;
    v_text := d;
  end if;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_text is not null then execute v_text; end if;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if md5(pg_get_functiondef(('public.' || c_sig)::regprocedure)) <> c_after then
    raise exception '441: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sig)::regprocedure) is distinct from v_acl
     or has_function_privilege('anon', 'public.' || c_sig, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_sig, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_sig, 'execute') then
    raise exception '441: the grants of public.% changed (it is the service role''s alone)', c_sig; end if;

  -- ── 4. Behaviour, in a block that is always undone ──────────────────────
  -- Made-up records only ("441 check", @example.invalid, fictional phones);
  -- it ends by raising P0441, which undoes all it wrote.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_sfx := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(7000, 7999) g
             where not exists (select 1 from public.customers c
                                where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(g::text, 4, '0'))
             limit 5) y;
    insert into auth.users (id, email) values (gen_random_uuid(), '441-check-' || lower(t_sfx) || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '441 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into public.stores (name, code, country_code) values ('441 check ' || t_sfx, '441-' || t_sfx, 'SG') returning id into t_store;
    insert into public.events (name, daily_start, daily_end, is_active) values ('441 check ' || t_sfx, '09:00', '19:00', true)
      returning id into t_event;
    insert into public.event_days (event_id, day) values (t_event, public.sg_today() + 30);
    insert into public.event_stores (event_id, store_id) values (t_event, t_store);
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id)
    values (t_event, 'CHECK441-' || t_sfx, 'live', t_store, t_owner);
    t_live := 'evk_live_' || rpad(t_sfx, 43, 'L');
    t_hash := encode(extensions.digest(t_live, 'sha256'), 'hex');
    insert into public.event_web_keys (event_id, kind, key_hash, key_hint, created_by)
    values (t_event, 'live', t_hash, '441 check', t_owner);
    -- The affiliate, a record merged into another that did not take its phone or email.
    insert into public.customers (full_name, phone) values ('Check Affiliate', t_phones[1]) returning id into t_aff;
    insert into public.customer_affiliates (customer_id, status, referral_code) values (t_aff, 'active', 'CHK441' || t_sfx);
    insert into public.customers (full_name, phone, email)
    values ('Check Gone', t_phones[2], '441-gone-' || lower(t_sfx) || '@example.invalid') returning id into t_gone;
    insert into public.customers (full_name, phone) values ('Check Kept', t_phones[3]) returning id into t_keep;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.merge_customer_records(t_keep, t_gone, '441 check', gen_random_uuid());
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    -- One form through her link: someone on the merged-away phone, someone on
    -- its inbox (a new phone), someone on a new phone and inbox.
    t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK441-' || t_sfx, 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || t_sfx, 'submitted_at', now(),
        'referral_code', 'CHK441' || t_sfx, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Other', 'last_name', 'Person', 'phone', t_phones[2],
                             'email', 'other-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false),
          jsonb_build_object('position', 2, 'first_name', 'Mail', 'last_name', 'Person', 'phone', t_phones[4],
                             'email', '441-gone-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false),
          jsonb_build_object('position', 3, 'first_name', 'Plain', 'last_name', 'Person', 'phone', t_phones[5],
                             'email', 'plain-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    t_p1 := (t_ans->'people'->0->>'person_id')::uuid;
    t_p2 := (t_ans->'people'->1->>'person_id')::uuid;
    t_p3 := (t_ans->'people'->2->>'person_id')::uuid;
    select p.customer_id into t_c3 from public.event_registration_people p where p.id = t_p3;
    if t_ans->>'status' <> 'registered' or public.event_web_kept_customer(t_gone) is distinct from t_keep
       or (select (p.match, p.hold_reason, p.candidate_customer_ids, p.referral_outcome, p.customer_id)
                  is distinct from ('held'::text, 'phone_in_use'::text, array[t_gone], 'held'::text, null::uuid)
             from public.event_registration_people p where p.id = t_p1)
       or (select (p.match, p.hold_reason, p.candidate_customer_ids, p.referral_outcome, p.customer_id)
                  is distinct from ('held'::text, 'email_in_use'::text, array[t_gone], 'held'::text, null::uuid)
             from public.event_registration_people p where p.id = t_p2)
       or (select (p.match, p.referral_outcome) is distinct from ('new_customer'::text, 'created'::text)
             from public.event_registration_people p where p.id = t_p3)
       or (select c.referred_by from public.customers c where c.id = t_c3) is distinct from t_aff
       or (select count(*) from public.customers c
            where c.deleted_at is null and public.normalize_customer_phone(c.phone) in (t_phones[2], t_phones[4])) <> 0 then
      raise exception '441: the self-test''s registration is not as tested (the merged-away phone and inbox held): %', t_ans; end if;
    -- Made a customer, the first waits for the check, shared with the kept
    -- record; the second, attached to the retired id, is the kept record.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.event_registration_create_customer(t_p1, '441 check');
    perform public.event_registration_attach(t_p2, t_gone, '441 check');
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    select p.customer_id into t_c1 from public.event_registration_people p where p.id = t_p1;
    if (select p.referral_outcome from public.event_registration_people p where p.id = t_p1) is distinct from 'check_waiting'
       or (select c.referred_by from public.customers c where c.id = t_c1) is not null
       or not exists (select 1 from public.referral_signup_checks k
                       where k.customer_id = t_c1 and k.status = 'pending' and k.referrer_customer_id = t_aff
                         and k.phone_shared_with = array[t_keep])
       or (select (p.customer_id, p.match, p.referral_outcome) is distinct from (t_keep, 'staff_attached'::text, 'already_customer'::text)
             from public.event_registration_people p where p.id = t_p2) then
      raise exception '441: the self-test''s check after the hold, or the attach to the retired id, is not as tested'; end if;
    raise exception using errcode = 'P0441', message = '441: self-test done, undone';
  exception when sqlstate 'P0441' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
