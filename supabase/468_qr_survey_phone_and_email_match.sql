-- 468_qr_survey_phone_and_email_match.sql
--
-- THE QR HEALTH SURVEY ATTACHES A FORM WHOSE PHONE AND EMAIL ARE ONE
-- CUSTOMER'S AT ONCE, AND STAFF NO LONGER HAVE TO MATCH IT; ONE FOR A
-- CUSTOMER WHO ALREADY HAS A SURVEY WAITS QUIETLY FOR STAFF (the Owner,
-- 24 Oct 2026)
--
-- WHAT WAS WRONG
--
--   The public QR form (submit_health_survey) attaches a form by itself only
--   when the phone and the name match a customer (433). A form whose phone
--   AND email are a customer's, under a name written another way, waits
--   under Health Surveys > To match for staff to attach by hand. Production,
--   16 to 24 Oct 2026: 4 forms waited; staff attached all 4, 3 of them to
--   the one customer with both the phone and the email.
--
-- THE RULES (the Owner, 24 Oct 2026)
--
--   The request, exactly: "For 'to match', if the customer phone number and
--   the email is the same match them at once should not ask to match. If
--   more than one customer, ask to attach and there should be a delete
--   option if more than one customer has the same phone number and email.
--   If the customer has only the same phone number, it should be ask. If the
--   customer has only the same email, it should be asked."
--   The Owner's answers, the same day (S1 to S5), and later the same day
--   (A to D, which change S1 and S5):
--   S1. When exactly ONE customer in use has both the phone
--       (normalize_customer_phone) and the email (customer_email_match_key:
--       Gmail dots, +tags and googlemail.com read as one inbox, as 433
--       compares emails), the form is attached to that customer at once,
--       even when the name typed differs. The customer keeps their own name
--       parts (as 433's rule 4 for a form staff attach); the form keeps the
--       phone and email typed.
--   B.  Such a form (found by the phone and the email, the name picked no
--       one) fills NONE of the customer's empty details: date of birth, sex,
--       occupation, email, how they heard about us. The form keeps what was
--       typed. A form found by the phone and the name fills them, as today.
--   S2. Phone + name (exact, or the same words) stays attached at once, as
--       today, whatever the email. A phone and name match comes first: when
--       it finds one customer, that customer it is; then phone + email.
--   D.  Two or more customers on the phone with the name typed, and one
--       customer of ANOTHER name with the phone and the email: the form
--       waits for staff (several_name_matches, for the namesakes).
--   S3. More than one customer in use with both the phone and the email
--       (and the name picked none of them): the form waits under To match, as
--       today, with them as the customers it may belong to; staff attach it
--       to one. An Owner or Manager also gets Delete on each of them, through
--       the app's own delete_customer (Owner or Manager, the name typed to
--       confirm, refused while the customer holds credit, therapies, unpaid
--       invoices and so on): no new delete rule. That is the Surveys page's;
--       this file changes no delete.
--   S4. Only the phone, or only the email, a customer's: waits, as today.
--       Neither: a new customer, as today.
--   A.  (replaces S5's refusal) A customer found ONLY by the phone and the
--       email who already has a survey: the form is NOT refused. It waits
--       quietly under To match (reason phone_and_email_customer_has_survey,
--       with that customer); the person gets the same thank-you as any form,
--       and nothing tells them a survey exists. Staff decide there. A
--       customer found by the phone and the name who already has a survey:
--       refused as today (HEALTH_SURVEY_ALREADY_EXISTS). A consultant's
--       record the customer has not signed takes the form (419's rule 1),
--       as for a phone and name match.
--   C.  The public page's words for that refusal say "for these details",
--       not "for this phone number and name" (src/lib/survey/form.mjs; not
--       this file).
--   Only the QR health survey (and its To match tab); not the seminar
--   websites, the affiliate sign-up or the referral page.
--
-- HOW IT READS (this file)
--
--   * The name first, as today: one customer on the phone with the name as
--     typed, or else with the same words (433), and the form is theirs.
--   * When the name matched none of the customers on the phone: the
--     customers in use with this phone and this email's inbox. Just one: the
--     form is theirs (Audit Log name_match 'phone_and_email'), with the same
--     checks as a name match, but:
--       - it fills none of their empty details (B);
--       - when they already have a survey (or an old survey with no customer
--         has this phone and the name typed, as the name match checks), the
--         form is kept with no customer and waits under To match with them
--         (A), instead of being refused. Attach is not offered for a customer
--         who has a survey (one survey per customer; attach_held_health_
--         survey refuses it): staff make a new customer from the form (a
--         family member) or an Owner or Manager closes it (the same person);
--       - 433's check for a form sent before (this phone and name, waiting or
--         a customer's) passes over a form that waits for reason A: else a
--         second form under the same name would be refused only when the
--         customer had a survey before the first (the first then waited) and
--         not when they had none (the first was attached at once), and two
--         forms would tell a survey exists. A form sent before that waits or
--         was attached for any other reason still refuses the same phone and
--         name, as 433 has it (also when the phone and the email now find
--         the customer: the person sent this form before).
--       - a consultant's record they have not signed takes it, as 419 does
--         for a name match; that fills none of the customer's details either
--         (health_survey_sign_into_record changes only the record).
--   * When the name matched several customers on the phone (433 holds such a
--     form), the customers with the phone and the email are looked at among
--     ALL customers in use, not only the namesakes:
--       - just one, and it is one of the namesakes: the form is theirs, as a
--         name match (their details filled; refused if they have a survey);
--       - just one, of another name: the form waits for the namesakes, as
--         today (D);
--       - several: the form waits (S3), with the namesakes and every customer
--         with both, so an Owner or Manager gets Delete on those with both.
--         It keeps today's reason, several_name_matches.
--   * Otherwise the form waits as today, with today's reasons: several with
--     both the phone and the email and no name match is phone_and_email_in_use
--     (the Surveys page tells it apart by the match flags health_survey_
--     holds_list already gives per customer, and offers Delete there).
--   * An old record whose phone cannot be read as one number does not count
--     as having the phone, here as in 433: with the same email, the form
--     waits (email_in_use).
--   * The submission's Audit Log row says how many customers in use had both
--     the phone and the email when they were looked at
--     (phone_and_email_customers), and name_match 'phone_and_email' when
--     they, not the name, found the customer (also on a form that waits for
--     reason A: customer_matched false, hold_reason as stored).
--
-- WHAT THIS DOES
--
--   * health_survey_holds: its reason check takes one more reason,
--     phone_and_email_customer_has_survey (the four of 433 stay).
--   * submit_health_survey (419's, patched in six places): one variable and
--     the 468 lookup after the name match; 433's check for a form sent before
--     passes over forms waiting for reason A; the name match's "already has
--     a survey" refusal holds a form found by the phone and the email
--     instead; the fill of the customer's empty details only for a name
--     match; the Audit Log field. No other function, grant or table changes.
--
-- NOT CHANGED
--
--   * The success reply (success, survey_no, survey_id), who may send a form,
--     every grant. The refusal HEALTH_SURVEY_ALREADY_EXISTS still answers a
--     phone and a name (S2, and 433's form sent before under that name and
--     held for another reason), never a phone and an email alone.
--   * health_survey_holds' other columns and its functions (list, attach,
--     make, close), the TikTok no-show run, delete_customer,
--     require_resolved_customer_identity (a name beside an old unreadable
--     phone that could be this one is still refused), 419's consultant-record
--     rule and health_survey_sign_into_record, the survey's own trigger (a
--     form attached at once shows the customer's details where the person
--     left a question blank, as every attached form does).
--   * Forms already waiting stay waiting (production on 24 Oct 2026: none).
--
-- NOT COVERED (to be put to the Owner before the go-ahead)
--
--   * The email is not verified (433: "it never attaches a form by itself";
--     468 reverses that, as S1 asks). Anyone who knows a customer's phone and
--     email can send the QR form, under any name, from any link. When the
--     customer has no survey it becomes their one survey at once: their
--     medical answers, signature and marketing consents; it counts as their
--     visit (and so their TikTok attendance or October-promo first visit);
--     if they have a consultant's record they have not signed, it is signed
--     and filled with these answers (419). It no longer fills the customer's
--     empty details (B). When the real customer later sends their own form,
--     by their name, it is refused ("A health survey has already been
--     completed for these details", C). Before 468 all this needed the
--     phone and the customer's name. The only traces are the Audit Log row
--     (name_match 'phone_and_email', with the name as typed) and the stored
--     signed PDF, which shows the typed name while the survey row shows the
--     customer's.
--   * What the replies tell (433's rule: the reply says nothing about
--     customers). One form never tells whether the customer has a survey
--     (A). But two forms with the same phone, email AND name do tell whether
--     the phone and the email together are exactly one customer's: then the
--     second waits (A) like the first; otherwise it is refused (a phone
--     nobody had: the first made a customer of that name, whom the name now
--     matches; a phone or an email of someone else's, or of several
--     customers: the first waited under that name, 433's form sent before).
--     Not whether that customer has a survey. Before 468 two such forms told
--     nothing. Closing it would mean keeping the name
--     typed on a form attached by the phone and the email where 433's check
--     reads it, or changing 433's rule for everyone: the Owner's call.
--   * A relative or household member who is not a customer but shares a
--     customer's phone and email inbox: when that customer has no survey,
--     their form is filed as that customer's survey (it takes the customer's
--     name; the name typed stays only in the Audit Log; it fills none of the
--     customer's details, B). When the customer has a survey, it waits (A)
--     and staff make a new customer from it. Production on 24 Oct 2026
--     (counts only): 6 of the 7 pairs of customers sharing a phone and an
--     email inbox have different names.
--   * Forms that wait for reason A are never refused, so one person sending
--     the form again and again leaves a form for staff each time (as a form
--     under a new name does today); an Owner or Manager closes the extra
--     ones.
--   * An old survey with no customer (none in production on 24 Oct 2026),
--     with this phone and the name typed, also makes a form found by the
--     phone and the email wait (reason A), where a name match is refused.
--   * Production on 24 Oct 2026 (counts only): 7 pairs of customers in use
--     share a phone and an email inbox (14 customers, none in a group of 3
--     or more); a form from one of them under another name waits (S3) for
--     staff, with Delete for an Owner or Manager.
--   * A customer's phone or email changed after a form was held does not
--     re-run the match; staff attach it as today.
--   * The other public forms (469, built the same day in another worktree)
--     read "the name matched several" as 468 did before D: one of the
--     namesakes with the email takes it even when a customer of another name
--     also has both. 468 holds that form (S3). A and B are answers for the
--     QR form only; 469 should follow D before both go live, or the Owner
--     chooses one reading for all.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * submit_health_survey is the version read on 24 Oct 2026 (BEFORE,
--     patched) or already this one (AFTER, left alone); each of the six
--     anchors is found exactly once; the text built has the tested md5;
--   * health_survey_holds' reason check is 433's (BEFORE, widened) or already
--     this one (AFTER, left alone);
--   * the functions it relies on and does not change are as read on
--     24 Oct 2026 (again after 462 and 463), and so are the columns of
--     customers its lookup reads and of health_survey_holds 433's check for
--     a form sent before reads.
--   Afterwards: the AFTER md5 and reason check; the grants as before
--   (compared as sets: anon and signed-in users may send the form). Then a
--   self-test, in a block that is always undone (it ends by raising P0468,
--   so it leaves no row): on a made-up store, link and source, with
--   fictional phones no customer or survey uses (@example.invalid emails), a
--   form under another name from a made-up customer's phone and email (typed
--   in another form, in capitals) is theirs at once, carries their name,
--   keeps the phone typed and fills none of their empty details; sending it
--   again (twice, under one name) is not refused: each waits (reason A) with
--   no customer and the same reply; a form from two made-up customers'
--   shared phone and email waits (phone_and_email_in_use) for both; one of
--   the two by their own name is given the form at once and their empty
--   details are filled (S2); no customer is made by the forms; the Audit Log
--   rows say how the customer was found. It leaves nothing behind (on a copy
--   of production: every table's row count and every sequence as before). A
--   second run changes nothing ("already this version; left alone") and
--   runs no self-test. Locks: health_survey_holds briefly (the reason check
--   is replaced; the table is small), the function's own replacement and the
--   self-test's new rows.
--
-- DEPLOY ORDER (each with the Owner's go-ahead)
--
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second says "already
--      this version; left alone" and changes nothing.
--   2. Apply 468 (the CLI, or the MCP's apply_migration with this text
--      verbatim).
--   3. Then the pages (Vercel): Health Surveys > To match (the reasons in
--      plain words, A's included; Delete for an Owner or Manager), Edit
--      Customer (the referrer's name, read only) and the public QR page's
--      refusal words (C). Pages first works too: a page that knows reason A
--      before the server sends it shows nothing new; but a form held for
--      reason A before the To match page knows it shows the general words
--      ("It could not be matched to one customer by itself"), so pages first
--      or together is better.
--   No data repair: no form waits now, and the forms already attached stay.
--
-- BEFORE (production, 24 Oct 2026: head 20261024102018, 463; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   submit_health_survey(text,jsonb,jsonb,text)                      ad2a66909b663026911dff137ab12185  (419's AFTER)
--   health_survey_holds_reason_check (md5 of pg_get_constraintdef)   2ea7d96e802e7d5240c712b56f391346  (433's)
--   relied on, not changed (unchanged by 462 and 463)
--   normalize_customer_phone(text)                                   b2bfac910e0c9eff402ba44e19750bee
--   customer_email_match_key(text)                                   be468815c9626fff1728e2cfcd484b66  (432's)
--   customer_names_match(text,text)                                  ef1af52e4888cefb6037a2291f4e011d  (432's)
--   customer_phone_name_matches(text,text)                           1bdf8322972b6671b7cbb08bc8211f8a
--   normalize_customer_match_name(text)                              0572764712e179dc606c66f9f3dbaa03
--   require_resolved_customer_identity(text,text)                    5bde1a418363442ec27e2944442f5874
--   health_survey_sign_into_record(uuid,health_surveys,jsonb,text)   ac2bbd3742f3b4364b289ddd29715215  (419's)
--   trg_survey_inherit_customer()                                    5b145a044ea35d3a2237f0ff4e65b600
--   trg_sync_person_name()                                           bdfc01a20c6d82672a24c694a0ea917b
--   join_person_name(text,text)                                      50b6cd36ab0fd14be3acd549fec5edb8
--   health_survey_holds_list()                                       0487502f033b56452140c81e108a8ebc  (419's; the page reads its flags)
--   attach_held_health_survey(uuid,uuid,text)                        53aabcdd564da445131633c41bef8249  (419's; refuses a customer with a survey)
--   create_customer_from_held_survey(uuid,text)                      733db65d708db7c64b5c4de03493d409  (433's; any reason)
--   close_held_health_survey(uuid,text)                              ee4789b1d716e4fbf498a5f38e722735  (433's; any reason)
--   delete_customer(uuid,text,text)                                  5b407735574fc3cacd8067c4dc8213f4  (418's; the page's Delete)
--   public function fingerprint, production now                      6d96407cdeb903712a2d7be7016aa9a6 (1387 functions)
-- AFTER (for later guards)
--   submit_health_survey(text,jsonb,jsonb,text)                      014a970de2e5dee64e4027459cac5280
--   health_survey_holds_reason_check (md5 of pg_get_constraintdef)   378c1861f7ffacb38d2e6e8c69e45cc8
--   public function fingerprint, worked out on a copy of production   19ffebc4f568664254cf025cc43bb792 (1387)
--   (on the chain before 462 and 463, 41a2fcab90c95090a71c688d7f0a17cd (1381): 8c53a468cf1fc0dc6c36a322ac08feb0 (1381))
--
-- Test: scripts/survey/tests/to-match-468.sql (begin ... rollback; it
-- installs this file twice, or with -v skip_install=1 where it is in).
-- Pages: scripts/survey/tests/survey-holds-panel.test.mjs (reasons, Delete),
-- scripts/customers/tests/customers-page.test.mjs (the referrer),
-- scripts/survey/tests/public-survey-page.test.mjs and form.test.mjs (C).

set lock_timeout = '5s';

do $mig$
declare
  c_fn constant text := 'public.submit_health_survey(text,jsonb,jsonb,text)';
  c_before constant text := 'ad2a66909b663026911dff137ab12185';
  c_after constant text := '014a970de2e5dee64e4027459cac5280';

  -- ── health_survey_holds: the reasons a form may wait for ────────────────
  c_con constant text := 'health_survey_holds_reason_check';
  c_con_before constant text := 'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, '
    || '''phone_and_email_in_use''::text, ''several_name_matches''::text])))';
  c_con_after constant text := 'CHECK ((reason = ANY (ARRAY[''phone_in_use''::text, ''email_in_use''::text, '
    || '''phone_and_email_in_use''::text, ''several_name_matches''::text, ''phone_and_email_customer_has_survey''::text])))';

  -- ── submit_health_survey: each anchor becomes its patch ─────────────────
  c_anchors constant text[] := array[
    $a$  v_first text; v_last text; v_into uuid; v_form public.health_surveys%rowtype; v_signed jsonb;
$a$,
    $a$  v_match_count := cardinality(v_matches);
$a$,
    $a$              where h.typed_phone = v_norm
$a$,
    $a$                                      where h.survey_id = health_surveys.id)) then
      raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
    end if;
$a$,
    $a$     where id = v_cust_id;
$a$,
    $a$                             'name_match', v_name_match, 'typed_name', v_name,
$a$];
  c_patches constant text[] := array[
    $r$  v_first text; v_last text; v_into uuid; v_form public.health_surveys%rowtype; v_signed jsonb;
  -- 468: the customers in use with both this phone and this email's inbox.
  v_both uuid[];
$r$,
    $r$  v_match_count := cardinality(v_matches);
  -- 468 (the Owner, 24 Oct 2026): the phone and the email's inbox
  -- (customer_email_match_key, as 433 compares emails) both belong to just
  -- one customer in use: the form is theirs, as a phone and name match is,
  -- whatever name was typed. It takes their name parts, as a form staff
  -- attach does; the phone and email typed stay on it. Below: it fills none
  -- of their details, and when they already have a survey it waits for
  -- staff instead of being refused. The name comes first: one customer with
  -- it is the one. When it matched several, that one customer with both
  -- must be one of them (then it is a name match); one of another name does
  -- not take a form whose name points at others (it waits, as today).
  -- Several with both and no name match (a duplicate record): the form
  -- waits for staff, as below; with several namesakes, those with both wait
  -- beside them. An Owner or Manager may delete a duplicate from To match.
  -- An old record whose phone cannot be read does not have the phone, as in
  -- 433.
  if v_match_count <> 1 then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_both
      from public.customers c
     where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_norm
       and public.customer_email_match_key(c.email) = public.customer_email_match_key(v_email);
    if cardinality(v_both) = 1 and (v_match_count = 0 or v_both[1] = any (v_matches)) then
      if v_match_count = 0 then v_name_match := 'phone_and_email'; end if;
      v_matches := v_both;
      v_match_count := 1;
    elsif cardinality(v_both) > 1 and v_match_count > 1 then
      select array_agg(distinct x order by x) into v_matches from unnest(v_matches || v_both) x;
      v_match_count := cardinality(v_matches);
    end if;
  end if;
$r$,
    $r$              where h.typed_phone = v_norm
                -- 468 (the Owner, 24 Oct 2026): not a form that waits because
                -- the one customer with its phone and email already had a
                -- survey (below; such a form is never refused). Counting it
                -- would refuse a second form under the same name only when
                -- the customer had a survey before the first, and so tell.
                and h.reason <> 'phone_and_email_customer_has_survey'
$r$,
    $r$                                      where h.survey_id = health_surveys.id)) then
      if v_name_match is distinct from 'phone_and_email' then
        raise exception 'HEALTH_SURVEY_ALREADY_EXISTS';
      end if;
      -- 468 (the Owner, 24 Oct 2026): found by the phone and the email alone
      -- (the name picked no one), the form is not refused: it is kept with no
      -- customer and waits quietly under To match with them; the reply is
      -- the same as for any form, so it tells no one a survey exists. Staff
      -- decide (a new customer from it, or an Owner or Manager closes it).
      v_hold := 'phone_and_email_customer_has_survey';
      v_candidates := array[v_cust_id];
      v_cust_id := null; v_matched := false; v_into := null;
    end if;
$r$,
    $r$     where id = v_cust_id
       -- 468 (the Owner, 24 Oct 2026): only when the name found them. A form
       -- found by the phone and the email alone fills none of the customer's
       -- details; the form keeps what was typed.
       and v_name_match is distinct from 'phone_and_email';
$r$,
    $r$                             'name_match', v_name_match, 'typed_name', v_name,
                             -- 468: how many customers in use had both the
                             -- phone and the email, when looked at (the name
                             -- matched none, or several).
                             'phone_and_email_customers', cardinality(v_both),
$r$];

  -- ── Relied on, not changed (production, 24 Oct 2026, after 463) ─────────
  c_relied constant text[] := array['normalize_customer_phone(text)', 'customer_email_match_key(text)',
    'customer_names_match(text,text)', 'customer_phone_name_matches(text,text)', 'normalize_customer_match_name(text)',
    'require_resolved_customer_identity(text,text)', 'health_survey_sign_into_record(uuid,health_surveys,jsonb,text)',
    'trg_survey_inherit_customer()', 'trg_sync_person_name()', 'join_person_name(text,text)',
    'health_survey_holds_list()', 'attach_held_health_survey(uuid,uuid,text)',
    'create_customer_from_held_survey(uuid,text)', 'close_held_health_survey(uuid,text)', 'delete_customer(uuid,text,text)'];
  c_relied_md5 constant text[] := array['b2bfac910e0c9eff402ba44e19750bee', 'be468815c9626fff1728e2cfcd484b66',
    'ef1af52e4888cefb6037a2291f4e011d', '1bdf8322972b6671b7cbb08bc8211f8a', '0572764712e179dc606c66f9f3dbaa03',
    '5bde1a418363442ec27e2944442f5874', 'ac2bbd3742f3b4364b289ddd29715215',
    '5b145a044ea35d3a2237f0ff4e65b600', 'bdfc01a20c6d82672a24c694a0ea917b', '50b6cd36ab0fd14be3acd549fec5edb8',
    '0487502f033b56452140c81e108a8ebc', '53aabcdd564da445131633c41bef8249',
    '733db65d708db7c64b5c4de03493d409', 'ee4789b1d716e4fbf498a5f38e722735', '5b407735574fc3cacd8067c4dc8213f4'];

  v_path text := current_setting('search_path');
  d text; v text; n int; v_patch boolean := false; v_con boolean := false; v_acl text[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_store uuid; t_src uuid; t_one uuid; t_two uuid; t_three uuid;
  t_ans jsonb; t_custs int; t_s public.health_surveys%rowtype; t_h public.health_survey_holds%rowtype;
  t_c public.customers%rowtype; t_err text; t_held uuid[] := '{}';
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '468: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The columns of customers the lookup reads.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.customers'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('id', 'phone', 'email', 'deleted_at');
  if v is distinct from 'deleted_at timestamp with time zone|email text|id uuid|phone text' then
    raise exception '468: public.customers is not shaped as read on 24 Oct 2026 (%)', v; end if;
  -- The held form's columns the check for a form sent before reads, and the
  -- reason the new one is stored in.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.health_survey_holds'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('reason', 'typed_email', 'typed_full_name', 'typed_phone');
  if v is distinct from 'reason text|typed_email text|typed_full_name text|typed_phone text' then
    raise exception '468: public.health_survey_holds is not shaped as read on 24 Oct 2026 (%)', v; end if;

  -- health_survey_holds' reason check: 433's (widened) or already this one.
  select string_agg(pg_get_constraintdef(c.oid), ' ;; ') into v
    from pg_constraint c where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = c_con;
  if v = c_con_after then
    raise notice '468: % is already this version; left alone', c_con;
  elsif v is distinct from c_con_before then
    raise exception '468: % is not the version this was tested against (%). Re-read it from production and re-test before applying.', c_con, v;
  else
    v_con := true;
  end if;

  -- submit_health_survey: BEFORE (patched) or AFTER (left alone).
  if to_regprocedure(c_fn) is null then raise exception '468: % is missing', c_fn; end if;
  d := pg_get_functiondef(c_fn::regprocedure);
  if md5(d) = c_after then
    raise notice '468: % is already this version; left alone', c_fn;
  elsif md5(d) <> c_before then
    raise exception '468: % is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_fn, md5(d);
  else
    for k in 1 .. cardinality(c_anchors) loop
      n := (length(d) - length(replace(d, c_anchors[k], ''))) / length(c_anchors[k]);
      if n <> 1 then
        raise exception '468: anchor % of % was found % times, not once', k, c_fn, n; end if;
      d := replace(d, c_anchors[k], c_patches[k]);
    end loop;
    if md5(d) <> c_after then
      raise exception '468: the text built for % is not the tested one (md5 %)', c_fn, md5(d); end if;
    v_patch := true;
  end if;
  select coalesce(array_agg(x::text order by x::text), '{}') into v_acl
    from pg_proc p, unnest(coalesce(p.proacl, '{}'::aclitem[])) x where p.oid = c_fn::regprocedure;

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_con then
    execute format('alter table public.health_survey_holds drop constraint %I, add constraint %I %s',
                   c_con, c_con, c_con_after);
  end if;
  if v_patch then
    execute d;
  end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  if (select string_agg(pg_get_constraintdef(c.oid) || ' validated=' || c.convalidated, ' ;; ')
        from pg_constraint c where c.conrelid = 'public.health_survey_holds'::regclass and c.conname = c_con)
     is distinct from c_con_after || ' validated=true' then
    raise exception '468: % was not installed as tested', c_con; end if;
  if md5(pg_get_functiondef(c_fn::regprocedure)) <> c_after then
    raise exception '468: % was installed with an md5 other than the tested one', c_fn; end if;
  if (select coalesce(array_agg(x::text order by x::text), '{}') from pg_proc p, unnest(coalesce(p.proacl, '{}'::aclitem[])) x
       where p.oid = c_fn::regprocedure) is distinct from v_acl then
    raise exception '468: the grants of % changed', c_fn; end if;
  if not has_function_privilege('anon', c_fn, 'execute') or not has_function_privilege('authenticated', c_fn, 'execute') then
    raise exception '468: % is no longer callable by the public form', c_fn; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Only when this run changed something. Made-up records only ("468
  -- Check", @example.invalid, fictional phones no customer or survey uses);
  -- it ends by raising P0468, which undoes all it wrote.
  if v_patch or v_con then
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select p as x from unnest(array['+61491570680', '+61491570681', '+61491570682', '+61491570683',
                                            '+61491570684', '+61491570685', '+61491570686', '+61491570687']) p
             where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
               and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) is null
                                  and c.phone ~ '^[\s().0-9-]+$'
                                  and (public.inspect_customer_phone(c.phone) -> 'candidates') ? p)
               and not exists (select 1 from public.health_surveys s where public.normalize_customer_phone(s.phone) = p)
               and not exists (select 1 from public.health_survey_holds h where h.typed_phone = p)
             limit 2) y;
    if cardinality(t_phones) is distinct from 2 then
      raise exception '468: the self-test found no unused fictional phones'; end if;
    insert into public.stores (name, code) values ('468 Check ' || t_sfx, 'Z468' || upper(t_sfx)) returning id into t_store;
    insert into public.customer_source_options (label) values ('468 Check ' || t_sfx) returning id into t_src;
    insert into public.survey_links (token, store_id) values ('z468-check-' || t_sfx, t_store);
    insert into public.customers (full_name, phone, email)
    values ('468 Check One ' || t_sfx, t_phones[1], 'z468-one-' || t_sfx || '@example.invalid') returning id into t_one;
    insert into public.customers (full_name, phone, email)
    values ('468 Check Two ' || t_sfx, t_phones[2], 'z468-two-' || t_sfx || '@example.invalid') returning id into t_two;
    insert into public.customers (full_name, phone, email)
    values ('468 Check Twin ' || t_sfx, t_phones[2], 'z468-two-' || t_sfx || '@example.invalid') returning id into t_three;
    select count(*) into t_custs from public.customers;

    -- S1 and B: another name, her phone with spaces, her email in capitals,
    -- with an occupation and a date of birth: hers at once, none filled in.
    t_ans := public.submit_health_survey('z468-check-' || t_sfx,
      jsonb_build_object('first_name', 'Someone', 'last_name', 'Else ' || t_sfx,
                         'phone', '+61 ' || substr(t_phones[1], 4, 3) || ' ' || substr(t_phones[1], 7, 3) || ' ' || substr(t_phones[1], 10),
                         'email', upper('z468-one-' || t_sfx || '@example.invalid'),
                         'occupation', 'Checker', 'date_of_birth', '1980-02-03', 'sex', 'female',
                         'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', t_src), null, null);
    select * into t_s from public.health_surveys where id = (t_ans ->> 'survey_id')::uuid;
    select * into t_c from public.customers where id = t_one;
    if t_s.customer_id is distinct from t_one or t_s.full_name is distinct from '468 Check One ' || t_sfx
       or t_s.phone is distinct from t_phones[1] or t_s.email is distinct from upper('z468-one-' || t_sfx || '@example.invalid')
       or t_s.occupation is distinct from 'Checker'
       or exists (select 1 from public.health_survey_holds h where h.survey_id = t_s.id)
       or (t_ans - 'survey_no' - 'survey_id') is distinct from '{"success": true}'::jsonb then
      raise exception '468: the self-test''s phone and email form was not attached as tested: %', t_ans; end if;
    if t_c.occupation is not null or t_c.date_of_birth is not null or t_c.gender is not null
       or t_c.source_option_id is not null or t_c.email is distinct from 'z468-one-' || t_sfx || '@example.invalid' then
      raise exception '468: the self-test''s phone and email form filled the customer''s details'; end if;
    -- A: the same phone and email again, twice under one other name: she has
    -- a survey now, so each waits quietly, with her, and no customer; the
    -- reply is as any other.
    for i in 1 .. 2 loop
      begin
        t_ans := public.submit_health_survey('z468-check-' || t_sfx,
          jsonb_build_object('first_name', 'Another', 'last_name', 'Name ' || t_sfx, 'phone', t_phones[1],
                             'email', 'z468-one-' || t_sfx || '@example.invalid',
                             'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', t_src), null, null);
      exception when others then t_ans := jsonb_build_object('refused', sqlerrm);
      end;
      select * into t_h from public.health_survey_holds where survey_id = (t_ans ->> 'survey_id')::uuid;
      if t_h.reason is distinct from 'phone_and_email_customer_has_survey'
         or t_h.candidate_customer_ids is distinct from array[t_one]
         or (t_ans - 'survey_no' - 'survey_id') is distinct from '{"success": true}'::jsonb
         or (select customer_id is not null or full_name is distinct from 'Another Name ' || t_sfx
               from public.health_surveys where id = t_h.survey_id) then
        raise exception '468: the self-test''s form for a customer with a survey did not wait as tested (%): %', i, t_ans; end if;
      t_held := t_held || t_h.survey_id;
    end loop;
    -- S3: two customers with the phone and the email: it waits for both.
    t_ans := public.submit_health_survey('z468-check-' || t_sfx,
      jsonb_build_object('first_name', 'Someone', 'last_name', 'Twin ' || t_sfx, 'phone', t_phones[2],
                         'email', 'z468-two-' || t_sfx || '@example.invalid',
                         'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', t_src), null, null);
    select * into t_h from public.health_survey_holds where survey_id = (t_ans ->> 'survey_id')::uuid;
    if t_h.reason is distinct from 'phone_and_email_in_use'
       or (select array_agg(x order by x) from unnest(t_h.candidate_customer_ids) x)
          is distinct from (select array_agg(x order by x) from unnest(array[t_two, t_three]) x)
       or (select customer_id from public.health_surveys where id = t_h.survey_id) is not null then
      raise exception '468: the self-test''s shared phone and email form did not wait as tested: %', t_ans; end if;
    -- S2 kept: one of the two by their own name, the same phone and email:
    -- theirs at once, the waiting form notwithstanding; their empty
    -- occupation is filled (a name match fills, as today).
    begin
      t_ans := public.submit_health_survey('z468-check-' || t_sfx,
        jsonb_build_object('first_name', '468 Check', 'last_name', 'Twin ' || t_sfx, 'phone', t_phones[2],
                           'email', 'z468-two-' || t_sfx || '@example.invalid', 'occupation', 'Checker',
                           'signature_data', 'data:image/png;base64,AAAA', 'source_option_id', t_src), null, null);
    exception when others then t_ans := jsonb_build_object('refused', sqlerrm);
    end;
    if (select customer_id from public.health_surveys where id = (t_ans ->> 'survey_id')::uuid) is distinct from t_three
       or (select occupation from public.customers where id = t_three) is distinct from 'Checker' then
      raise exception '468: the self-test''s form by name and phone was not given to its customer as tested: %', t_ans; end if;
    if (select count(*) from public.customers) <> t_custs then
      raise exception '468: the self-test''s forms made a customer'; end if;
    if (select (new_data ->> 'name_match') = 'phone_and_email' and (new_data ->> 'phone_and_email_customers')::int = 1
               and (new_data ->> 'customer_matched')::boolean and not (new_data ->> 'held_for_staff')::boolean
          from public.audit_logs where action = 'health_survey_submitted' and record_id = t_s.id) is distinct from true
       or (select bool_and((new_data ->> 'name_match') = 'phone_and_email'
                           and (new_data ->> 'hold_reason') = 'phone_and_email_customer_has_survey'
                           and not (new_data ->> 'customer_matched')::boolean and (new_data ->> 'customer_id') is null)
             from public.audit_logs where action = 'health_survey_submitted' and record_id = any (t_held)) is distinct from true then
      raise exception '468: the self-test''s Audit Log rows do not say how the customer was found'; end if;
    raise exception using errcode = 'P0468', message = '468: self-test done, undone';
  exception when sqlstate 'P0468' then null;
  end;
  end if;

  perform set_config('search_path', v_path, true);
end $mig$;
