-- 432_affiliate_signup_no_duplicate_customers.sql
--
-- AFFILIATE SIGN-UP FINDS THE CUSTOMER ALREADY THERE, AND PARKS A CLAIM
-- RATHER THAN MAKE A SECOND RECORD (the owner's decision, 16 Oct 2026: "C:
-- both"; a family member's own record stays with an Owner or Manager, "as
-- today"; and "Yes" to saving sign-up's audit-log entry)
--
-- WHY
--
--   complete_affiliate_onboarding links a new portal login to a customer. It
--   links one by itself only when the login's verified email and the phone +
--   name both point at the same single customer (and that customer is not
--   protected: 378, 379). It creates a new customer only when both find
--   nothing, and parks a pending claim for staff in every other case.
--
--   "Both find nothing" ignored the phone on its own. Up to 3 customers may
--   share a phone, so the phone alone never links anyone; but it did not stop
--   a second record either. And the name had to be written exactly as on the
--   record, word for word and in the same order, a note in brackets included,
--   and the email exactly as written. So a person who typed their name in
--   another order ("Koh Ann Lee" for "Ann Lee Koh"), joined their given names,
--   or whose old record has a note in brackets, or the same Gmail inbox
--   written with dots, got a second customer: their history on one, their
--   affiliate code and referrals on the other, until someone merged them.
--   Production, 3 Sep to 16 Oct 2026: 52 portal sign-ups; 12 created a
--   customer, 6 of them beside an older record on the same phone (3 merged
--   since, 2 suspected pairs left with the owner, 1 staff test login); 5
--   linked by themselves; 35 went through a claim.
--
-- WHAT THIS DOES (complete_affiliate_onboarding only)
--
--   1. Same words. When no customer with the phone has the name exactly as
--      typed, one whose name has the same words matches too: in any order,
--      with neighbouring words written together or apart ("Meiling" and "Mei
--      Ling", but never "Anna Koh" and "Ann Akoh"), whatever the case and
--      punctuation, leaving out a note in brackets. With a patronymic in
--      either name (bin, binte, binti, bte, bt, b., ibn, ibni, ibnu, bint,
--      anak, s/o, d/o, a/l, a/p, son of, daughter of) the order counts:
--      "Kumar s/o Rajan" is not "Rajan s/o Kumar", who may be his father.
--      Letters of any script stay whole. Names of more than 6 words
--      are compared word for word; only a name's first 200 characters count.
--      An exact match still comes first. (New: customer_name_words,
--      customer_names_match.)
--   2. Same inbox. An email is compared as the inbox it reaches: a Gmail
--      address with or without dots or a +tag, or at googlemail.com, is one
--      address. Any other address is compared as written (trimmed, lower
--      case). (New: customer_email_match_key.)
--      With 1 and 2, a sign-up whose email, phone and same-words name all
--      point at one customer is linked by itself, as an exact match was.
--      Replayed on the 32 past claims that kept the name typed, 12 more would
--      have linked without staff. Two are never linked by themselves: a
--      login whose claim was rejected is told verification was unsuccessful,
--      as before, whatever its details match now; and a customer who already
--      has a portal login gets a parked claim for the new one (a second login
--      for the same Gmail inbox used to fail with a raw duplicate-key error).
--   3. The phone is taken. A new customer is created only when no customer
--      in use has the phone either. When one has it, and neither the name
--      nor the email matched, the sign-up is parked as a pending claim, and
--      the person is told "We found an existing Energia customer record that
--      needs identity verification", as for any claim. When one customer has
--      the phone, the claim suggests them, and staff link it to them when it
--      is the same person. When several share it, the claim suggests no one
--      (378 lets staff link only the suggested customer on a shared phone, so
--      the phone alone never lets them choose): an Owner or Manager links it.
--      A family member sharing the phone needs a record of their own: anyone
--      adds them on the Customers page, and an Owner or Manager resolves the
--      claim to it (the phone is shared from then on). A sign-up on a phone 3
--      customers already share, which failed with CUSTOMER_PHONE_LIMIT, is
--      parked the same way.
--   4. The Audit Log. Sign-up's own entry ('affiliate_portal_claimed') was
--      never saved: write_audit_ex records the caller as changed_by, which
--      must be a staff profile, a portal login has none, and the error was
--      swallowed. It is now written straight into audit_logs, with no one
--      signed in recorded and the login in new_data, and it says how the
--      customer was found: new_customer, name_match ('exact' or
--      'same_words') and email_match ('exact' or 'same_inbox'). A parked
--      claim is recorded too ('affiliate_claim_parked'), with its reason:
--      phone_in_use, email_not_on_record, email_on_another_record,
--      email_on_several_records, email_only, several_name_matches,
--      customer_has_login or protected_customer. Neither can stop a sign-up;
--      a failure is a warning in the database log.
--
-- WHAT STAYS
--
--   * 378/379. Sign-up still never links by itself a customer an Owner
--     unlinked a login from, or one an Owner or Manager rejected a claim for:
--     with a same-words name it parks a claim suggesting them, as it does
--     with an exact one. A login with a rejected claim is still told
--     "Account verification was unsuccessful", and nothing is parked.
--     Resolve, Reject, Delete, Unlink and their checks are not changed. The
--     new audit rows have actions of their own, and no actor_role or
--     changed_by, so they count as neither an unlink nor a rejection.
--   * customer_phone_name_matches is not changed: the QR health survey, the
--     referral sign-up and the staff "same phone" list match as before.
--   * What the person sees (the page already shows a pending claim), every
--     grant, and every customer and claim already there.
--
-- NOT COVERED (reported to the owner)
--
--   * A name that is shorter or different, not just reordered ("Ann Koh"
--     for "Ann Lee Koh", or an English name for a Chinese one), still does
--     not match. When the phone is taken the sign-up is parked (3); on a
--     phone no one has, it creates a customer, as before.
--   * A Chinese name with the syllable Bin, or an initial B, reads as having
--     a patronymic, so it matches only in the same order: "Tan Bin Hui"
--     typed as "Bin Hui Tan" is parked rather than linked.
--   * A customer whose phone could not be read as one number (pending
--     review) does not count as having the phone.
--   * As before 432, a login whose claim was rejected still gets a new
--     customer and a portal login if it signs up with a phone and an email
--     no customer has. Making a rejection final there too is the owner's
--     decision.
--   * 379 still protects whomever a claim suggested when an Owner or Manager
--     rejects it, and a claim may now suggest the one customer who has the
--     phone without a name match. For a family member, resolve the claim to
--     their own record, as the owner decided: rejecting it would protect the
--     customer whose phone they share.
--   * Whether a sign-up is parked or gets an account now also tells the
--     person whether the phone they typed belongs to a customer. A login can
--     try one phone after another until one is free (it is then linked).
--   * The email is compared by reading every customer's address (no index):
--     about 50 ms at today's 13,000 customers.
--   * The two suspected pairs and the staff test login of 3 Sep to 16 Oct
--     are left as they are; merging is the owner's decision.
--
-- DEPLOY: the database only; no page changes. Independent of 417-431 (431
-- lists complete_affiliate_onboarding in its header but does not guard it).
-- A later change to sign-up or to the claim checks (B11, 425) builds on this.
--
-- SAFETY
--
--   ONE statement (a single DO block), so it is atomic whatever runs it, and
--   every check comes before anything is created:
--   * complete_affiliate_onboarding must be the version read on 16 Oct 2026
--     (BEFORE), or already this one (AFTER, left alone). Each of its 5
--     anchors must occur exactly once, and the text built must have the
--     tested md5 before it is installed.
--   * The functions it relies on and does not change must be as read on 16
--     Oct 2026, and so must the audit_logs columns it writes and the one
--     pending claim per login index (uq_affiliate_claims_one_pending).
--   * The 3 new functions must be missing, or already this version (left
--     alone), and no other function may take their names.
--   * Afterwards all 4 have their AFTER md5s, complete_affiliate_onboarding
--     keeps its grants, and the new functions are callable by the service
--     role only (revoked from public, anon and authenticated): sign-up runs
--     as their owner. A second run changes nothing.
--
-- BEFORE (production, 16 Oct 2026, after 416; md5 of pg_get_functiondef with
-- search_path public):
--   changed
--   complete_affiliate_onboarding(text,text,text,boolean)   9ff0fd280f4a46eddb2446523d500233
--   relied on, not changed
--   customer_phone_name_matches(text,text)                  1bdf8322972b6671b7cbb08bc8211f8a
--   normalize_customer_phone(text)                          b2bfac910e0c9eff402ba44e19750bee
--   inspect_customer_phone(text,text)                       6672c4d1963996f3b601896f4a55916e
--   normalize_customer_match_name(text)                     0572764712e179dc606c66f9f3dbaa03
--   require_resolved_customer_identity(text,text)           5bde1a418363442ec27e2944442f5874
--   affiliate_claim_link_check(uuid,uuid)                   251b1bd9f7175301750d65be4dd01b0e
--   public function fingerprint (production after 416)      2d8adfa50cb541fe5582f4e6f9bbe9f3
-- AFTER (for later guards):
--   complete_affiliate_onboarding(text,text,text,boolean)   ff59dd1f8a6ca7397efea5880c6a87a7
--   customer_name_words(text)                (new)          a7507abf0f15abd923dff59508b269c1
--   customer_names_match(text,text)          (new)          ef1af52e4888cefb6037a2291f4e011d
--   customer_email_match_key(text)           (new)          be468815c9626fff1728e2cfcd484b66
--   public function fingerprint (after 416 + 432)           b6757ec2f685e9756e59fa4014aa9a44
--
-- Test: scripts/affiliate-signup/tests/no-duplicate-customers.sql
-- (begin ... rollback; it installs this file itself, twice).

set lock_timeout = '5s';

do $mig$
declare
  c_fn constant text := 'public.complete_affiliate_onboarding(text,text,text,boolean)';
  c_before constant text := '9ff0fd280f4a46eddb2446523d500233';
  c_after constant text := 'ff59dd1f8a6ca7397efea5880c6a87a7';

  -- ── The new functions, as pg_get_functiondef gives them back ────────────
  c_words_def constant text := $def$CREATE OR REPLACE FUNCTION public.customer_name_words(p_name text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  -- 432: the words of a customer's name as sign-up compares them, in the
  -- order written: lower case, with a note in brackets left out (legacy
  -- records keep a referrer or a place there, "Ann Lee (Orchard) Koh"), and
  -- spaces and punctuation read as one space. Letters of any script stay
  -- whole, with their accents and vowel signs. Only the first 200
  -- characters count, so a name pasted in at length costs nothing.
  select coalesce(array_agg(w.word order by w.n), '{}'::text[])
    from regexp_split_to_table(
           btrim(regexp_replace(regexp_replace(lower(left(coalesce(p_name, ''), 200)), '\([^)]*\)', ' ', 'g'),
                                '[[:space:][:punct:]$+<=>^`|~]+', ' ', 'g')),
           ' ') with ordinality as w(word, n)
   where w.word <> ''
$function$
$def$;
  c_match_def constant text := $def$CREATE OR REPLACE FUNCTION public.customer_names_match(p_a text, p_b text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  -- 432: whether two customer names have the same words (customer_name_words)
  -- in any order, with neighbouring words written together or apart
  -- ("Meiling" and "Mei Ling"), but no word cut elsewhere ("Anna Koh" is not
  -- "Ann Akoh"). With a patronymic in either name (bin, binte, binti, bte,
  -- bt, b., ibn, ibni, ibnu, bint, anak, s/o, d/o, a/l, a/p, son of,
  -- daughter of) the order counts: "Kumar s/o Rajan" is not "Rajan s/o
  -- Kumar". Names of more than 6 words are compared word for word. A name
  -- with no words matches none.
  with recursive
  a as (select public.customer_name_words(p_a) as w),
  b as (select public.customer_name_words(p_b) as w),
  -- Whether either name has a patronymic, so that the order counts.
  o as (select (a.w || b.w) && array['bin', 'binte', 'binti', 'bte', 'bt', 'b', 'ibn', 'ibni', 'ibnu', 'bint', 'anak']
               or array_to_string(a.w, ' ') ~ '(^| )([sd] [o0]|a [lp]|son of|daughter of)( |$)'
               or array_to_string(b.w, ' ') ~ '(^| )([sd] [o0]|a [lp]|son of|daughter of)( |$)' as ordered
          from a, b),
  -- Each name's words written together, in every order (only as written
  -- when the order counts), with where each word ends.
  pa(used, s, ends) as (
    select '{}'::int[], ''::text, '{}'::int[]
    union all
    select pa.used || i, pa.s || a.w[i], pa.ends || (length(pa.s) + length(a.w[i]))
      from pa, a, o, generate_subscripts(a.w, 1) as i
     where i <> all (pa.used) and cardinality(a.w) <= 6
       and (not o.ordered or i = cardinality(pa.used) + 1)),
  pb(used, s, ends) as (
    select '{}'::int[], ''::text, '{}'::int[]
    union all
    select pb.used || i, pb.s || b.w[i], pb.ends || (length(pb.s) + length(b.w[i]))
      from pb, b, o, generate_subscripts(b.w, 1) as i
     where i <> all (pb.used) and cardinality(b.w) <= 6
       and (not o.ordered or i = cardinality(pb.used) + 1)),
  -- The orders with every word in.
  fa(s, ends) as (select pa.s, pa.ends from pa, a where cardinality(pa.used) = cardinality(a.w)),
  fb(s, ends) as (select pb.s, pb.ends from pb, b where cardinality(pb.used) = cardinality(b.w))
  select case
    when cardinality(a.w) = 0 or cardinality(b.w) = 0 then false
    -- Written together, the two must be as long, with the same letters.
    when length(array_to_string(a.w, '')) <> length(array_to_string(b.w, '')) then false
    when o.ordered and a.w = b.w then true
    when not o.ordered and (select array_agg(x order by x) from unnest(a.w) as x)
                         = (select array_agg(x order by x) from unnest(b.w) as x) then true
    when cardinality(a.w) > 6 or cardinality(b.w) > 6 then false
    when (select string_agg(x, '' order by x) from regexp_split_to_table(array_to_string(a.w, ''), '') as x)
      <> (select string_agg(x, '' order by x) from regexp_split_to_table(array_to_string(b.w, ''), '') as x) then false
    -- One name's words end where the other's do, or where a word of the
    -- other is only written apart.
    else exists (select 1 from fa join fb using (s)
                  where fa.ends <@ fb.ends or fb.ends <@ fa.ends)
  end
  from a, b, o
$function$
$def$;
  c_email_def constant text := $def$CREATE OR REPLACE FUNCTION public.customer_email_match_key(p_email text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  -- 432: an email address as sign-up compares it: trimmed and in lower case.
  -- A Gmail address is also read without the dots and any +tag before the @,
  -- and googlemail.com as gmail.com: Gmail delivers all of these to one
  -- inbox. Other addresses are compared as written. An empty address is null.
  select case
    when split_part(lower(btrim(p_email)), '@', 2) in ('gmail.com', 'googlemail.com')
     and replace(split_part(split_part(lower(btrim(p_email)), '@', 1), '+', 1), '.', '') <> ''
      then replace(split_part(split_part(lower(btrim(p_email)), '@', 1), '+', 1), '.', '') || '@gmail.com'
    else nullif(lower(btrim(p_email)), '')
  end
$function$
$def$;
  c_words_after constant text := 'a7507abf0f15abd923dff59508b269c1';
  c_match_after constant text := 'ef1af52e4888cefb6037a2291f4e011d';
  c_email_after constant text := 'be468815c9626fff1728e2cfcd484b66';

  -- ── complete_affiliate_onboarding: each anchor becomes its patch ────────
  c_anchors constant text[] := array[
    $a$  v_matches uuid[]; v_email_matches int; v_phone_cust uuid; v_phone_email text; v_code text; v_suspended boolean := false;
$a$,
    $a$  v_matches := public.customer_phone_name_matches(v_phone,v_name);
  select count(*) into v_email_matches from public.customers
   where lower(btrim(email))=v_email and deleted_at is null;
  if cardinality(v_matches)=1 then
    v_phone_cust := v_matches[1];
    select lower(btrim(email)) into v_phone_email from public.customers where id=v_phone_cust;
  end if;
$a$,
    $a$  if v_email_matches = 0 and cardinality(v_matches) = 0 then
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, v_phone, v_email, true)
      returning id into v_cust;
  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email
$a$,
    $a$    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
      values (v_uid, v_phone, v_email, v_phone_cust, v_name)
      on conflict do nothing;                         -- one-pending index (mig 156)
$a$,
    $a$  begin
    perform public.write_audit_ex('affiliate_accounts', v_acct.id, 'affiliate_portal_claimed', null,
      jsonb_build_object('customer_id', v_cust, 'affiliate_id', v_aff.id, 'auth_user_id', v_uid,
        'new_customer', (v_email_matches = 0 and v_phone_cust is null)), 'affiliate', null, null);
  exception when others then null; end;
$a$];
  c_patches constant text[] := array[
    $r$  v_matches uuid[]; v_email_matches int; v_phone_cust uuid; v_phone_email text; v_code text; v_suspended boolean := false;
  -- 432: the email as compared, how the name matched, how many customers in
  -- use have the phone, whom a parked claim suggests, the claim parked, and
  -- whether a customer was created.
  v_email_key text; v_name_match text; v_holders int; v_suggest uuid; v_claim uuid; v_created boolean := false;
$r$,
    $r$  v_matches := public.customer_phone_name_matches(v_phone,v_name);
  -- 432: when no customer with this phone has the name exactly as typed, one
  -- whose name has the same words counts too (customer_names_match): in any
  -- order (as written, with a patronymic such as bin or s/o), with
  -- neighbouring words together or apart, whatever the case and punctuation,
  -- and leaving out a note in brackets. "Koh Ann Lee" is "Ann Lee Koh", and
  -- "Ong Meiling" is "Mei Ling (Orchard) Ong".
  if cardinality(v_matches) = 0 then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_matches
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_phone
       and public.customer_names_match(c.full_name, v_name);
    if cardinality(v_matches) > 0 then v_name_match := 'same_words'; end if;
  else
    v_name_match := 'exact';
  end if;
  -- 432: an email is compared as the inbox it reaches
  -- (customer_email_match_key): a Gmail address with or without dots or a
  -- +tag, or at googlemail.com, is one address. Others are compared as written.
  v_email_key := public.customer_email_match_key(v_email);
  select count(*) into v_email_matches from public.customers
   where public.customer_email_match_key(email)=v_email_key and deleted_at is null;
  if cardinality(v_matches)=1 then
    v_phone_cust := v_matches[1];
    select public.customer_email_match_key(email) into v_phone_email from public.customers where id=v_phone_cust;
  end if;
  -- 432: how many customers in use have this phone.
  select count(*) into v_holders from public.customers
   where deleted_at is null and public.normalize_customer_phone(phone) = v_phone;
$r$,
    $r$  -- 432: a new customer only when no customer in use has this phone either.
  -- When one has it, but neither the name nor the email matched, the sign-up
  -- is parked below as a pending claim: staff check whether it is the same
  -- person under another spelling, or someone sharing the phone (whose own
  -- record an Owner or Manager then links, as before). Up to 3 customers may
  -- share a phone, so the phone alone links no one.
  if v_email_matches = 0 and cardinality(v_matches) = 0 and v_holders = 0 then
    insert into public.customers (full_name, phone, email, is_active)
      values (v_name, v_phone, v_email, true)
      returning id into v_cust;
    v_created := true;
  elsif v_email_matches = 1 and v_phone_cust is not null and v_phone_email = v_email_key
        -- 432: never for a login whose claim was rejected: below, it is told
        -- verification was unsuccessful, whatever its details match now. Nor
        -- to a customer who already has a portal login (one each): that
        -- sign-up is parked below, for staff to sort out.
        and not exists (select 1 from public.affiliate_account_claims
                         where auth_user_id = v_uid and status = 'rejected')
        and not exists (select 1 from public.affiliate_accounts a where a.customer_id = v_phone_cust)
$r$,
    $r$    -- 432: whom the claim suggests: the one customer matched by phone and
    -- name; failing that, when the email matched no one either, the one
    -- customer who has this phone. A phone several share suggests no one
    -- without a name match: staff may link only the suggested customer on a
    -- shared phone (378), so the phone alone never lets them choose.
    v_suggest := v_phone_cust;
    if v_suggest is null and v_email_matches = 0 and cardinality(v_matches) = 0 and v_holders = 1 then
      select c.id into v_suggest from public.customers c
       where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_phone;
    end if;
    insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
      values (v_uid, v_phone, v_email, v_suggest, v_name)
      on conflict do nothing                          -- one-pending index (mig 156)
      returning id into v_claim;
    -- 432: the Audit Log keeps the claim parked and why (nothing when this
    -- login's pending claim was there already). Written straight into
    -- audit_logs, with no one signed in recorded (write_audit_ex records the
    -- caller, who must be staff); it cannot stop the sign-up.
    if v_claim is not null then
      begin
        insert into public.audit_logs (table_name, record_id, action, new_data, module)
        values ('affiliate_account_claims', v_claim, 'affiliate_claim_parked',
          jsonb_build_object('auth_user_id', v_uid, 'candidate_customer_id', v_suggest,
            'reason', case
              when cardinality(v_matches) > 1 then 'several_name_matches'
              when v_phone_cust is not null and v_email_matches = 1 and v_phone_email = v_email_key
                   and exists (select 1 from public.affiliate_accounts a where a.customer_id = v_phone_cust)
                then 'customer_has_login'
              when v_phone_cust is not null and v_email_matches = 1 and v_phone_email = v_email_key then 'protected_customer'
              when v_phone_cust is not null and v_email_matches = 0 then 'email_not_on_record'
              when v_phone_cust is not null and v_email_matches > 1 then 'email_on_several_records'
              when v_phone_cust is not null then 'email_on_another_record'
              when v_email_matches > 0 then 'email_only'
              else 'phone_in_use' end,
            'name_match', v_name_match, 'email_matches', v_email_matches, 'phone_holders', v_holders),
          'affiliate');
      exception when others then
        raise warning '432: the sign-up audit row was not saved: %', sqlerrm;
      end;
    end if;
$r$,
    $r$  -- 432: written straight into audit_logs, with no one signed in recorded.
  -- Through write_audit_ex it was never saved: that records the caller as
  -- changed_by, which must be a staff profile, a portal login has none, and
  -- the error was swallowed. It still cannot stop the sign-up. It says how
  -- the customer was found: created, or by the name exactly or by the same
  -- words, and by the email exactly or as the same inbox.
  begin
    insert into public.audit_logs (table_name, record_id, action, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_portal_claimed',
      jsonb_build_object('customer_id', v_cust, 'affiliate_id', v_aff.id, 'auth_user_id', v_uid,
        'new_customer', v_created, 'name_match', v_name_match,
        'email_match', case when v_created then null
                            when (select lower(btrim(c.email)) from public.customers c where c.id = v_cust) = v_email then 'exact'
                            else 'same_inbox' end),
      'affiliate');
  exception when others then
    raise warning '432: the sign-up audit row was not saved: %', sqlerrm;
  end;
$r$];

  -- The audit_logs columns sign-up writes, as read on 16 Oct 2026.
  c_cols constant text := 'action text not null|actor_role text|changed_by uuid|module text|new_data jsonb|record_id uuid|table_name text not null';

  v_path text := current_setting('search_path');
  r record; d text; n int; k int; v text;
  v_new text[] := '{}'; v_defs text[] := '{}';
  v_patch boolean := false; v_acl text;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 16 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is installed unless all pass ─────────────────────
  -- Relied on, not changed: the exact phone + name match, the phone and
  -- name rules under it, the check that refuses an unresolved phone, and the
  -- Resolve check a parked claim goes through (378/379).
  for r in select * from (values
      ('customer_phone_name_matches(text,text)',        '1bdf8322972b6671b7cbb08bc8211f8a'),
      ('normalize_customer_phone(text)',                'b2bfac910e0c9eff402ba44e19750bee'),
      ('inspect_customer_phone(text,text)',             '6672c4d1963996f3b601896f4a55916e'),
      ('normalize_customer_match_name(text)',           '0572764712e179dc606c66f9f3dbaa03'),
      ('require_resolved_customer_identity(text,text)', '5bde1a418363442ec27e2944442f5874'),
      ('affiliate_claim_link_check(uuid,uuid)',         '251b1bd9f7175301750d65be4dd01b0e')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '432: public.% is missing or not the version this was tested against. Re-read it from production and re-test before applying.', r.fn;
    end if;
  end loop;

  -- audit_logs, as read on 16 Oct 2026.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                    '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.audit_logs'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('table_name', 'record_id', 'action', 'new_data', 'changed_by', 'actor_role', 'module');
  if v is distinct from c_cols then
    raise exception '432: public.audit_logs is not shaped as read on 16 Oct 2026 (%)', v; end if;

  -- One pending claim per login: the parked claim's "on conflict do nothing".
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'affiliate_account_claims'
                    and indexname = 'uq_affiliate_claims_one_pending'
                    and indexdef = 'CREATE UNIQUE INDEX uq_affiliate_claims_one_pending ON public.affiliate_account_claims USING btree (auth_user_id) WHERE (status = ''pending''::text)') then
    raise exception '432: the index uq_affiliate_claims_one_pending is missing or not as read on 16 Oct 2026'; end if;

  -- The new functions: missing, or already this version (left alone).
  for r in select * from (values
      (1, 'customer_name_words(text)',       c_words_def, c_words_after),
      (2, 'customer_names_match(text,text)', c_match_def, c_match_after),
      (3, 'customer_email_match_key(text)',  c_email_def, c_email_after)) x(i, fn, def, after_md5)
    order by x.i
  loop
    if md5(r.def) <> r.after_md5 then
      raise exception '432: the text of public.% is not the tested one (md5 %)', r.fn, md5(r.def); end if;
    if to_regprocedure('public.' || r.fn) is null then
      v_new := v_new || r.fn; v_defs := v_defs || r.def;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '432: public.% exists and is not this migration''s version', r.fn;
    else
      raise notice '432: public.% is already this version; left alone', r.fn;
    end if;
  end loop;
  -- No other function takes one of these names (a caller could reach it instead).
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('customer_name_words', 'customer_names_match', 'customer_email_match_key')
     and p.oid::regprocedure::text not in ('customer_name_words(text)', 'customer_names_match(text,text)',
                                           'customer_email_match_key(text)');
  if v is not null then
    raise exception '432: another function takes one of these names: %', v; end if;

  -- complete_affiliate_onboarding: BEFORE (patched) or AFTER (left alone).
  if to_regprocedure(c_fn) is null then raise exception '432: % is missing', c_fn; end if;
  d := pg_get_functiondef(c_fn::regprocedure);
  if md5(d) = c_after then
    raise notice '432: % is already this version; left alone', c_fn;
  elsif md5(d) <> c_before then
    raise exception '432: % is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_fn, md5(d);
  else
    for k in 1 .. cardinality(c_anchors) loop
      n := (length(d) - length(replace(d, c_anchors[k], ''))) / length(c_anchors[k]);
      if n <> 1 then
        raise exception '432: anchor % of % was found % times, not once', k, c_fn, n; end if;
      d := replace(d, c_anchors[k], c_patches[k]);
    end loop;
    if md5(d) <> c_after then
      raise exception '432: the text built for % is not the tested one (md5 %)', c_fn, md5(d); end if;
    v_patch := true;
  end if;
  select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = c_fn::regprocedure;

  -- ── 2. Install: the new functions first, as sign-up calls them ──────────
  for k in 1 .. coalesce(cardinality(v_new), 0) loop
    execute v_defs[k];
    execute format('revoke all on function public.%s from public, anon, authenticated', v_new[k]);
    execute format('grant execute on function public.%s to service_role', v_new[k]);
  end loop;
  if v_patch then
    execute d;
  end if;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for r in select * from (values
      ('complete_affiliate_onboarding(text,text,text,boolean)', c_after),
      ('customer_name_words(text)',       c_words_after),
      ('customer_names_match(text,text)', c_match_after),
      ('customer_email_match_key(text)',  c_email_after)) x(fn, after_md5)
  loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '432: public.% was installed with an md5 other than the tested one', r.fn; end if;
  end loop;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = c_fn::regprocedure) is distinct from v_acl then
    raise exception '432: the grants of % changed', c_fn; end if;
  if not has_function_privilege('authenticated', c_fn, 'execute')
     or has_function_privilege('anon', c_fn, 'execute') then
    raise exception '432: % is not callable by signed-in logins alone', c_fn; end if;
  for r in select unnest(array['customer_name_words(text)', 'customer_names_match(text,text)',
                               'customer_email_match_key(text)']) as fn
  loop
    if has_function_privilege('anon', 'public.' || r.fn, 'execute')
       or has_function_privilege('authenticated', 'public.' || r.fn, 'execute')
       or not has_function_privilege('service_role', 'public.' || r.fn, 'execute') then
      raise exception '432: public.% is not the service role''s alone', r.fn; end if;
  end loop;

  perform set_config('search_path', v_path, true);
end $mig$;
