-- 439_event_website_follows_merges_and_login_self_check.sql
--
-- THE EVENT WEBSITE (436) AFTER A CUSTOMER MERGE, AND THE AFFILIATE LOGIN'S
-- OWN DETAILS IN THE NO-SELF-REFERRAL RULE (the owner's answers, 21 Oct
-- 2026, 08:40)
--
-- WHAT WAS WRONG / WHY
--
--   The review of 436 with 437 and 438 (21 Oct 2026) found two ways round
--   436's referral rules.
--   * A merge left To match behind. A held website registration keeps the
--     customers it was held for (candidate_customer_ids, a uuid[]), and
--     merge_customer_records moves only foreign keys, so a candidate retired
--     by a merge (437's Link on the Affiliates page merges a fresh affiliate
--     record into an older one, by default without its phone) vanished from
--     the panel; attaching to it said "Customer not found."; the note still
--     said "Their phone is on another customer's record" when no record had
--     it; and "make a new customer" found nobody holding the phone, so the
--     person was referred AT ONCE: the affiliate's own phone (the owner's A)
--     and another customer's (Q19) skipped the Owner's or Manager's check,
--     and the affiliate held under her own name (affiliate_name) whose
--     record had been merged into one with another name was made her own
--     referral, tier-1 commission on her own VIP.
--   * 436 knew "the affiliate" only by her customer record's name, phone and
--     email. 437's rule 7 joins a login to a family member's record by its
--     phone alone, so Rachel, whose login sits on her mother's record,
--     registering herself on her own mobile with her login email became a
--     new customer referred by that record (tier-1 on her own VIP), or, on
--     the household phone, went through a check that was literally correct
--     on the data and then earned the same.
--
-- THE RULES (binding)
--
--   The owner's answers, 21 Oct 2026, 08:40:
--   * 1. To match follows a customer Link or merge. When a waiting (held)
--     website registration's candidate customer was retired by a merge
--     (merge_customer_records; its audit row customers_merged; chains A -> B
--     -> C are possible):
--     - the waiting registration shows the KEPT customer as its candidate;
--     - attaching to the retired id attaches to the kept record (no
--       "Customer not found");
--     - event_web_new_customer counts the kept record as the holder of that
--       phone or email, so the self-referral and A/Q19 checks still apply as
--       before (no referral or commission bypass);
--     - event_web_referral_note stops claiming the phone is on another
--       customer's record when that is no longer true (it says what is true
--       now).
--   * 2. The no-self-referral check (event_web_check_self_referral and
--     event_web_affiliate_contact, and anything else that decides "self")
--     also compares the affiliate LOGIN's own name, phone and email:
--     affiliate_accounts -> auth.users.email, and the sign-up name and phone
--     in raw_user_meta_data, not only the referrer customer record's. A
--     family member's record joined to her login by phone only (437's rule 7)
--     must no longer let her earn on herself.
--   * The existing normalize and match helpers are used (the ten pinned
--     432-family helpers are not redefined).
--   Every earlier answer in 436's THE RULES stands as written there.
--   How they read (this file, 21 Oct 2026):
--   * "Retired by a merge" is a customer record with deleted_at whose id a
--     customers_merged audit row names in merged_from; the record that kept
--     it is that row's record_id, followed while it was retired too (A
--     merged into B, then B into C: C). A record deleted any other way is
--     still gone (not listed; attaching to it is "Customer not found.").
--   * The kept record "holds" what the retired one had: its phone (as 425
--     reads a phone, an old 8-digit number included) or its email inbox
--     (432's customer_email_match_key), as read from the retired record,
--     which merge_customer_records keeps. So made a customer, someone held on
--     that phone or inbox waits for the check, sharing it with the kept
--     record, whether or not the kept record took the phone (437's ticked or
--     unticked Link).
--   * "As before" for the affiliate: the records merged into hers (along a
--     chain) are hers too: their names make a person her (B), their phones
--     and email inboxes are her phone and inbox (A). So someone else on her
--     merged record's phone waits for the check, and she, under that
--     record's name, is herself, also when she registers after the merge.
--     A merged record is hers only while it is still retired and still kept
--     by her record (event_web_kept_customer): one restored since
--     (restore_customer_with_phone) is its own customer again, and so is
--     whatever was merged into it later.
--   * Her login: the affiliate_accounts row of her record (or of a record
--     merged into it, as above), its auth.users email, and its
--     raw_user_meta_data first_name and last_name (else full_name) and
--     phone, as the sign-up page stores them. Its name is her name (B:
--     herself, not referred); its email inbox and phone are hers (A: someone
--     else on them waits for the check; with her name or record they say how
--     else she was recognised).
--     A login signed up with a phone no customer has: someone else on it is
--     made a customer at once (nobody to link) and waits for the check.
--   * The notes say what is true now: a held person's phone (or inbox) on
--     no customer's record any more names the record it was on and the one
--     that record was merged into ("(listed)": the kept record is the
--     candidate), or, with no merge, says it is on no record now and that a
--     new customer is referred at once (436's rule, unchanged: nobody holds
--     it); waiting for a check, the same. When her login signed up under a
--     name that is not her record's (the rule-7 family case), her notes name
--     both ("Siew Lan Testmum (or Rachel Testmum, whose affiliate login is on
--     her record)"); her own row adds "(her record's affiliate login was
--     signed up as ...)". With no login, or a login under her record's own
--     name, every note is 436's, word for word.
--   * Attaching to a retired id while another merge retires the record it
--     stands for (B merged into C while the attach waits for B's lock): the
--     attach looks again after each lock and follows the record that kept it,
--     so it lands on the live record (C), never on a retired one; only a
--     record deleted another way is "Customer not found.".
--
-- WHAT THIS DOES
--
--   1. event_web_kept_customer(customer) (new, the service role's alone): the
--      record that stands for a customer now: itself while not deleted; the
--      record a merge (or a chain of merges) kept; null otherwise. The
--      retired record's note ("Merged into <name> (<id>)") gives the kept id,
--      checked against its customers_merged row (found by record_id,
--      indexed); only when the note was changed is the audit log searched by
--      merged_from.
--   2. event_web_guest_extras (page): each To match candidate is listed as
--      the record that stands for it now (merged ones under merged_from:
--      their id, name, phone, email and whether the phone, read as 425 reads
--      a phone, and the email matched); the guest list and everything else
--      as 436.
--   3. event_registration_attach (page): a retired id attaches to the kept
--      record (the audit row adds asked_customer_id and merged_into;
--      suggested_customer is true for a candidate's kept record), looked up
--      again when it was merged while the attach waited for its lock; a
--      record deleted otherwise is still "Customer not found.".
--   4. event_web_new_customer: the kept records of the person's retired
--      candidates are holders of their phone or email inbox (above), so the
--      A, Q19 and R6-1 checks wait as before the merge (the audit row adds
--      merged_holders and says the phone or inbox was on a record since
--      merged).
--   5. event_web_affiliate_contact: her phone and inbox are her record's,
--      her merged records' (still retired and kept by hers), and her login's
--      (email; sign-up phone).
--   6. event_web_check_self_referral: her name is also her merged records'
--      (the same) and her login's sign-up name (the audit row adds name_from
--      merged_record or login when that is how she was recognised).
--   7. event_web_referral_note: the wording above.
--   Every caller of these (event_web_register, event_web_apply_referral,
--   event_registration_create_customer, the test key, the Website tab's test
--   registrations, the export) follows them unchanged.
--
-- NOT CHANGED
--
--   436's tables and every other 436 function (event_web_register,
--   event_web_apply_referral, event_registration_create_customer,
--   event_web_match_customer, event_web_phone_holders,
--   trg_event_web_referral_check_decided, the VIP and planning functions);
--   the stored candidate_customer_ids (read through the kept record, never
--   rewritten: 437's count of holds waiting on a fresh record still reads
--   them); merge_customer_records and the ten pinned 432-family helpers
--   (used as they are); 425's /r/<code> sign-up and its self check; 437 and
--   438 (not pinned, not patched: this file works with or without them);
--   every grant (the two page functions stay signed-in staff's, the four
--   others the service role's).
--
-- NOT COVERED (told to the owner)
--
--   * A registration made AFTER a merge on a phone or email inbox only the
--     retired record had (the kept record did not take it: 437's unticked
--     Link) is not held: nobody has it, so it is a new customer, referred at
--     once, as 437's Link box warns staff when the phone is not taken (a
--     later registration on it will not find the kept record). The
--     affiliate's own merged records' phones and inboxes, and her login's,
--     are the exception (a check). Owner's decision, open: whether the
--     phones and inboxes of records retired by a merge should count as held
--     by the kept record (event_web_phone_holders, event_web_match_customer;
--     a later migration with its own review).
--   * The login is read as the sign-up page stores it (raw_user_meta_data's
--     first_name, last_name and phone). A login whose details were given
--     only as complete_affiliate_onboarding's arguments, or changed since,
--     is compared as its metadata says. The login's sign-up name and phone
--     are her own user metadata: she can change them herself at any time
--     (auth.updateUser), so they recognise her only while she leaves them
--     as signed up. Her login email changes only after she confirms the new
--     address. (Owner's question, open: should 437 keep its own copy of the
--     sign-up name and phone on the server for this check?) A name typed
--     differently from both her record's and her login's (an honorific, a
--     typo) is still not recognised (as 436's NOT COVERED says).
--   * Rachel's own separate customer record, already referred by her
--     mother's record before (a referral that exists), is an existing
--     customer through the link: not her (436's D), so her purchases keep
--     paying that record. Only staff (reassign_customer_referrer) change it.
--   * Someone already waiting for a check when the login or a merge later
--     makes them recognisable as the affiliate: the check decides as before
--     (436's trigger does not decide "self" again).
--   * In a household where the login holder's name is not her record's, a
--     person with the RECORD's name is the affiliate (436's B) and a person
--     with the LOGIN's name is too: both are not referred.
--   * The notes name her merged records only for a held person's phone or
--     inbox; "the same name as <her record>" is said also when the name
--     matched one of her merged records' names.
--   * 425's /r/<code> page still compares only the record (R6-2 follow-up).
--
-- DEPLOY ORDER (each step with the owner's go-ahead)
--
--   After 436 (production then 0e7e9dee71d0559fb447bab0f4ddec3d, 1353
--   functions, with nothing else changed after it). Independent of 437 and
--   438: either may come before or after this file (it pins none of their
--   functions and changes none). Checked on copies, 21 Oct 2026, with 437
--   (file md5 92bec8f7...) and 438 (eb8df158...): 437, 438, 439; 439, 437,
--   438; and 437, 439, 438 all end at 41618db239b4b192c90631ea847a412d
--   (1364 functions); a later 437 moves that figure, not this file's.
--   1. Dry run on a copy of production as it is then: apply this file twice.
--      The first run ends with the fingerprint below (436 + 439 alone); the
--      second says "already this version; left alone" for each function and
--      changes nothing. A refusal names the function that moved since 436.
--   2. Apply this file (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself (every AFTER md5, the grants, its
--      self-test, which leaves no row).
--   3. The Event page needs nothing (a candidate's merged_from is new and
--      optional; the page ignores it until its small follow-up shows
--      "Merged from <name>, who had this phone" under the candidate).
--
-- SAFETY
--
--   ONE statement (a single DO block), atomic whatever runs it; every check
--   before anything is created:
--   * every function it relies on and does not change is as 436 left it
--     (below); the columns it reads are as read; 436's tables are there.
--   * event_web_kept_customer missing, or this version (left alone); no
--     other function takes its name.
--   * each of the six 436 functions it changes is 436's AFTER (patched, each
--     anchor found once, the text built has the tested md5) or already this
--     file's AFTER (left alone); anything else is refused.
--   * afterwards every md5 is the AFTER one; the helper is the service
--     role's alone; the six keep their grants (their ACLs unchanged).
--   * a self-test, in a block that is always undone (it ends by raising
--     P0439, so it leaves no row): a made-up Owner, store, event, live key,
--     an affiliate whose login signed up under another name, a phone holder
--     and a record to keep; one form through her link: two people on the
--     holder's phone are held for it, the login's own name on a new phone
--     and email is held as herself (no customer made); the holder merged
--     into the kept record: the kept record is the candidate, attaching to
--     the retired id attaches to it, and the other person made a customer
--     waits for the check, shared with the kept record. A second run changes
--     nothing.
--
-- BEFORE (436 as applied: its AFTER md5s, pg_get_functiondef with search_path public):
--   changed
--   event_web_affiliate_contact(uuid)                              2e36126ac19182665357e2a934252db6
--   event_web_check_self_referral(uuid,uuid)                       7c13dd04c230ddedf201db59244bdaff
--   event_web_referral_note(uuid)                                  13a3b322968826b76f1b6b6065d5ebd9
--   event_web_new_customer(uuid)                                   230f80aa30a13468cf5545398f393889
--   event_web_guest_extras(uuid)                                   0be416f652d2d6615818e434028f2437  (page)
--   event_registration_attach(uuid,uuid,text)                      c512d35fe6e1f58fbc8379c1a3a81972  (page)
--   relied on, not changed
--   customer_names_match(text,text)                                ef1af52e4888cefb6037a2291f4e011d
--   customer_email_match_key(text)                                 be468815c9626fff1728e2cfcd484b66
--   normalize_customer_match_name(text)                            0572764712e179dc606c66f9f3dbaa03
--   normalize_customer_phone(text)                                 b2bfac910e0c9eff402ba44e19750bee
--   inspect_customer_phone(text,text)                              6672c4d1963996f3b601896f4a55916e
--   merge_customer_records(uuid,uuid,text,uuid)                    099ecf3aae30b5faaf8fb36bc15ce888
--   write_audit(text,uuid,text,jsonb,jsonb)                        b194f839993670c5b5dd28e934c2a829
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   require_active_staff(text[])                                   877b3aa74cea559881979bb161c450e2
--   event_can_run(uuid)                                            dac12d0086533bb528e847eb828809df
--   user_has_store_access(uuid)                                    708992afaa6c3951f6329239b742987c
--   create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid) 9ff9031d3b40029a19c729a512e99798
--   event_web_phone_holders(text)                                  614602e9cbc483d79bdef7d60aaf6a33
--   event_web_match_customer(text,text,text)                       16ec3e9f65d619b3f3feeef712bfd132
--   event_web_fill_customer(uuid,uuid)                             89488f15e0b030b9ed14c3c31049a71e
--   event_web_apply_referral(uuid,uuid)                            b034075f9882cb4221e3a554e6453317
--   event_web_register(uuid,jsonb)                                 e3efd309e81d17c97f7984f7ecbaafff
--   event_registration_create_customer(uuid,text)                  23bc6941cd4b4db0fae101965292a324
--   event_vip_retry_after_match(uuid)                              06dafbb11f5b034dde31ef8fb9ffeedf
--   event_vip_holders(uuid)                                        f8e1f118a88d311bbdbcd86d14a5046d
--   event_web_person_vip_state(uuid)                               fc0a3c9ce094fe72e69cff7f420837b6
--   trg_event_web_referral_check_decided()                         9dea4cead38c8c990ad46f435d787520
--   event_web_call(text,uuid,text,jsonb)                           e114ba39de4923cc52ed426e27d9bfde
--   public function fingerprint (after 430 + 436)                    0e7e9dee71d0559fb447bab0f4ddec3d (1353 functions)
-- AFTER (for later guards):
--   event_web_kept_customer(uuid)                                  cb0720c1088df9209da45e46b91601f4  (new)
--   event_web_affiliate_contact(uuid)                              e4adbd007d847daee24e8d5d28b96b75
--   event_web_check_self_referral(uuid,uuid)                       11475114504d5bab79981ed8bb8c12b0
--   event_web_referral_note(uuid)                                  d68893db63938cc774b157708bd341f1
--   event_web_new_customer(uuid)                                   a253f76a9db721212a9c110bc41ff483
--   event_web_guest_extras(uuid)                                   18b56a28bb4965b2188cd73dde056209  (page)
--   event_registration_attach(uuid,uuid,text)                      b31be4d82d20000df026e7cfa9b24095  (page)
--   public function fingerprint (after 430 + 436 + 439)              d6d042abe6ccbbae2ad0674439cc984a (1354 functions)
--
-- Test: scripts/event-website/tests/event-website-439.sql (begin ... rollback; it installs
-- 436 when missing and this file twice, or -v skip_install=1 where it is installed); 436's own
-- event-website.sql with -v skip_install=1 and event-website-separate-tx.sql pass with it.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The new helper, as pg_get_functiondef gives it back (search_path public) ──
  c_new_sig constant text := 'event_web_kept_customer(uuid)';
  c_new_md5 constant text := 'cb0720c1088df9209da45e46b91601f4';
  c_new_def constant text := $def$CREATE OR REPLACE FUNCTION public.event_web_kept_customer(p_customer_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 439 (the owner, 21 Oct 2026, answer 1): the customer record that stands
  -- for p_customer_id now: itself while it is not deleted; when a merge
  -- retired it (merge_customer_records: the kept record's audit row
  -- customers_merged names it in merged_from), the record that kept it,
  -- followed along a chain (A merged into B, then B into C: C); null when it,
  -- or the end of its chain, was deleted some other way. The retired record's
  -- note names the record that kept it ("Merged into <name> (<id>)"), so the
  -- audit row is looked up by that record's id (indexed) and must name this
  -- one; only when the note no longer says so is the log searched for it.
  with recursive k(id, n) as (
    select p_customer_id, 0
    union all
    select m.kept, k.n + 1
      from k
      join public.customers c on c.id = k.id and c.deleted_at is not null
      cross join lateral (
        select coalesce(
          (select l.record_id from public.audit_logs l
            where l.record_id in (select (x[1])::uuid
                                    from regexp_matches(coalesce(c.notes, ''),
                                           '\(([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)', 'g') x)
              and l.action = 'customers_merged' and l.new_data->>'merged_from' = k.id::text
            order by l.created_at desc limit 1),
          (select l.record_id from public.audit_logs l
            where l.action = 'customers_merged' and l.new_data->>'merged_from' = k.id::text
            order by l.created_at desc limit 1)) as kept) m
     where k.n < 20 and m.kept is not null)
  select k.id from k join public.customers c on c.id = k.id and c.deleted_at is null
   order by k.n desc limit 1
$function$
$def$;

  -- ── The six 436 functions it changes: BEFORE (436's AFTER) and AFTER ──
  c_sigs constant text[] := array['event_web_affiliate_contact(uuid)', 'event_web_check_self_referral(uuid,uuid)', 'event_web_referral_note(uuid)', 'event_web_new_customer(uuid)', 'event_web_guest_extras(uuid)', 'event_registration_attach(uuid,uuid,text)'];
  c_page constant boolean[] := array[false, false, false, false, true, true];
  c_before constant text[] := array['2e36126ac19182665357e2a934252db6', '7c13dd04c230ddedf201db59244bdaff', '13a3b322968826b76f1b6b6065d5ebd9', '230f80aa30a13468cf5545398f393889', '0be416f652d2d6615818e434028f2437', 'c512d35fe6e1f58fbc8379c1a3a81972'];
  c_after constant text[] := array['e4adbd007d847daee24e8d5d28b96b75', '11475114504d5bab79981ed8bb8c12b0', 'd68893db63938cc774b157708bd341f1', 'a253f76a9db721212a9c110bc41ff483', '18b56a28bb4965b2188cd73dde056209', 'b31be4d82d20000df026e7cfa9b24095'];
  -- each anchor (found once in its function's BEFORE text) and its patch, in order
  c_fn constant int[] := array[1, 1, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6];
  c_anchor constant text[] := array[
$a01$  -- only once an Owner or Manager checks them (event_web_new_customer).
  select nullif(array_remove(array[
           case when public.normalize_customer_phone(a.phone) = p.phone_norm
                  or (public.normalize_customer_phone(a.phone) is null and a.phone ~ '^[\s().0-9-]+$'
                      and (public.inspect_customer_phone(a.phone)->'candidates') ? p.phone_norm) then 'phone' end,
           case when public.customer_email_match_key(a.email) = public.customer_email_match_key(p.email) then 'email' end],
           null), '{}'::text[])
$a01$,
$a02$    join public.customers a on a.id = r.referrer_customer_id
   where p.id = p_person_id and r.referral_state = 'valid'
$a02$,
$a03$declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype; a public.customers%rowtype;
  v_by text[] := '{}';
begin
$a03$,
$a04$    if nullif(public.normalize_customer_match_name(a.full_name), '') = public.normalize_customer_match_name(p.full_name)
       or public.customer_names_match(a.full_name, p.full_name) then v_by := v_by || 'name'::text; end if;
    -- The owner, 20 Oct 2026, ~20:15: her phone or email inbox alone does not
$a04$,
$a05$        jsonb_build_object('registration_id', r.registration_id, 'referral_code', r.referral_code,
                           'referrer_customer_id', r.referrer_customer_id, 'self_by', to_jsonb(v_by), 'customer_id', p_customer_id),
        'affiliate', public.event_web_referral_note(p.id),
$a05$,
$a06$  -- notes, the link named as switched off.
  select case
    when 'customer' = any (p.referral_self_by) then
      format('Not referred: this is %s, the affiliate whose link (%s) was used. She earns no commission from it.',
             coalesce(a.full_name, 'the affiliate'), y.link)
    when p.referral_self_by is not null and p.customer_id is not null then
$a06$,
$a07$             || 'customer (someone else), so no referral or commission comes from this link.',
             y.self_how, coalesce(a.full_name, 'the affiliate'), y.link)
    when p.referral_self_by is not null then
$a07$,
$a08$             || 'through this link either.',
             y.self_how, coalesce(a.full_name, 'the affiliate'), y.link, coalesce(a.full_name, 'the affiliate'))
    when r.referral_state <> 'valid' then null
$a08$,
$a09$             || 'as a different person (Affiliates page), and no commission comes before that.',
             x.how, coalesce(a.full_name, 'the affiliate'), r.referral_code, coalesce(a.full_name, 'the affiliate'),
             coalesce(a.full_name, 'the affiliate'))
$a09$,
$a10$             in ('phone_in_use', 'phone_and_email_in_use', 'several_name_matches', 'legacy_ambiguous') then
      format('Their phone is on another customer''s record. If this is that customer, link their record: an existing customer '
$a10$,
$a11$             r.referral_code, coalesce(a.full_name, 'the affiliate'))
    when x.how is null and ((p.match = 'held' and p.referral_outcome = 'held')
                            or (p.is_test and p.test_outcome->>'referral' = 'held'))
         and coalesce(p.hold_reason, p.test_outcome->>'hold_reason') = 'email_in_use' then
      format('Their email inbox is on another customer''s record. If this is that customer, link their record: an existing '
$a11$,
$a12$             || 'before that.', r.referral_code, coalesce(a.full_name, 'the affiliate'))
    when p.referral_outcome = 'check_waiting'
$a12$,
$a13$    when p.referral_outcome = 'check_waiting' and x.how is null then
      format('Waiting for a check: %s on another customer''s record. They become %s''s referral (link %s) '
             || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
             case when p.hold_reason = 'email_in_use' then 'their email inbox is' else 'their phone is' end,
             coalesce(a.full_name, 'the affiliate'), r.referral_code)
$a13$,
$a14$             || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
             x.how, coalesce(a.full_name, 'the affiliate'), r.referral_code,
             coalesce(a.full_name, 'the affiliate'))
$a14$,
$a15$                                   ', ([^,]*)$', ' and \1'), '') as how) x
    cross join lateral (
$a15$,
$a16$                            ', ([^,]*)$', ' and \1') as self_how,
             r.referral_code || case when r.referral_state = 'link_off' then ', switched off' else '' end as link) y
   where p.id = p_person_id
$a16$,
$a17$  v_wait boolean := false; v_shares uuid[]; v_mail_holders uuid[] := '{}';
begin
$a17$,
$a18$  end if;
  if r.referral_state = 'valid' and public.event_web_check_self_referral(p.id, null) then
$a18$,
$a19$                         'registration_id', r.registration_id, 'shares', to_jsonb(public.event_web_affiliate_contact(p.id)),
                         'phone_shared_with', to_jsonb(v_shares)),
      'affiliate', case when public.event_web_affiliate_contact(p.id) is not null
                        then 'Shares the affiliate''s own phone or email: referred once an Owner or Manager checks them as a different person'
                        when cardinality(v_holders) > 0
                        then 'Their phone is on another customer''s record: referred once an Owner or Manager checks them as a different person'
                        else 'Their email inbox is on another customer''s record: referred once an Owner or Manager checks them as a different person' end,
      null);
$a19$,
$a20$    -- holders, old numbers included, read once at registration), and whoever
    -- has their phone or their email's inbox now (as 433's list).
    'holds', coalesce((
$a20$,
$a21$                                             where h.customer_id = c.id) gv))
                          order by c.created_at)
$a21$,
$a22$                   -- scan of every customer per held person.
                   from (select unnest(p.candidate_customer_ids) as id
                         union
$a22$,
$a23$declare p public.event_registration_people%rowtype; c public.customers%rowtype; r public.event_registrations%rowtype;
  v_outcome text; v_retry jsonb;
begin
$a23$,
$a24$  select * into c from public.customers where id = p_customer_id for update;
  if not found or c.deleted_at is not null then raise exception 'Customer not found.'; end if;
  select * into r from public.event_registrations where id = p.registration_ref;
$a24$,
$a25$    jsonb_build_object('customer_id', c.id, 'hold_reason', p.hold_reason, 'registration_id', r.registration_id,
                       'suggested_customer', c.id = any (p.candidate_customer_ids), 'referral_outcome', v_outcome),
    'events', btrim(p_note), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
$a25$];
  c_patch constant text[] := array[
$p01$  -- only once an Owner or Manager checks them (event_web_new_customer).
  -- 439 (the owner, 21 Oct 2026, answers 1 and 2): hers are her record's, those
  -- of the records merged into it (merge_customer_records' customers_merged
  -- rows, along a chain), and her affiliate login's: its email (auth.users)
  -- and the phone it signed up with (raw_user_meta_data).
  select nullif(array_remove(array[
           case when exists (select 1 from unnest(h.phones) x(ph)
                              where public.normalize_customer_phone(x.ph) = p.phone_norm
                                 or (public.normalize_customer_phone(x.ph) is null and x.ph ~ '^[\s().0-9-]+$'
                                     and (public.inspect_customer_phone(x.ph)->'candidates') ? p.phone_norm)) then 'phone' end,
           case when exists (select 1 from unnest(h.emails) x(em)
                              where public.customer_email_match_key(x.em) = public.customer_email_match_key(p.email)) then 'email' end],
           null), '{}'::text[])
$p01$,
$p02$    join public.customers a on a.id = r.referrer_customer_id
    cross join lateral (
      with recursive her(id, n) as (
        select a.id, 0
        union all
        select (l.new_data->>'merged_from')::uuid, her.n + 1
          from her join public.audit_logs l on l.record_id = her.id and l.action = 'customers_merged'
         where her.n < 20
           and l.new_data->>'merged_from' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
      -- hers: her record, and each record merged into it that is still retired and still kept by hers (one
      -- restored since is its own again, and so is whatever was merged into it later)
      mine(id, phone, email) as (
        select c.id, c.phone, c.email from her join public.customers c on c.id = her.id
         where her.n = 0
            or (c.deleted_at is not null
                and public.event_web_kept_customer(c.id) = coalesce(public.event_web_kept_customer(a.id), a.id)))
      select array_agg(x.phone) as phones, array_agg(x.email) as emails
        from (select mine.phone, mine.email from mine
              union all
              select u.raw_user_meta_data->>'phone', u.email
                from public.affiliate_accounts aa join auth.users u on u.id = aa.auth_user_id
               where aa.customer_id in (select mine.id from mine)) x) h
   where p.id = p_person_id and r.referral_state = 'valid'
$p02$,
$p03$declare p public.event_registration_people%rowtype; r public.event_registrations%rowtype; a public.customers%rowtype;
  v_by text[] := '{}'; v_name_from text;
begin
$p03$,
$p04$    if nullif(public.normalize_customer_match_name(a.full_name), '') = public.normalize_customer_match_name(p.full_name)
       or public.customer_names_match(a.full_name, p.full_name) then v_by := v_by || 'name'::text; v_name_from := 'record'; end if;
    -- 439 (the owner, 21 Oct 2026, answers 1 and 2): her name is also that of a
    -- record merged into hers (merge_customer_records' customers_merged rows,
    -- along a chain) and the name her affiliate login signed up with
    -- (raw_user_meta_data's first and last name): a family member's record
    -- joined to her login by its phone alone (437's rule 7) no longer lets her
    -- earn on herself.
    if v_name_from is null then
      select x.src into v_name_from
        from (with recursive her(id, n) as (
                select a.id, 0
                union all
                select (l.new_data->>'merged_from')::uuid, her.n + 1
                  from her join public.audit_logs l on l.record_id = her.id and l.action = 'customers_merged'
                 where her.n < 20
                   and l.new_data->>'merged_from' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
              -- hers: her record, and each record merged into it that is still retired and still kept by hers
              -- (one restored since is its own again, and so is whatever was merged into it later)
              mine(id, n, name) as (
                select c.id, her.n, c.full_name from her join public.customers c on c.id = her.id
                 where her.n = 0
                    or (c.deleted_at is not null
                        and public.event_web_kept_customer(c.id) = coalesce(public.event_web_kept_customer(a.id), a.id)))
              select 'merged_record'::text as src, mine.name, 1 as o from mine where mine.n > 0
              union all
              select 'login', coalesce(nullif(btrim(coalesce(u.raw_user_meta_data->>'first_name', '') || ' '
                                                   || coalesce(u.raw_user_meta_data->>'last_name', '')), ''),
                                       nullif(btrim(coalesce(u.raw_user_meta_data->>'full_name', '')), '')), 2
                from public.affiliate_accounts aa join auth.users u on u.id = aa.auth_user_id
               where aa.customer_id in (select mine.id from mine)) x
       where nullif(public.normalize_customer_match_name(x.name), '') = public.normalize_customer_match_name(p.full_name)
          or public.customer_names_match(x.name, p.full_name)
       order by x.o limit 1;
      if v_name_from is not null then v_by := v_by || 'name'::text; end if;
    end if;
    -- The owner, 20 Oct 2026, ~20:15: her phone or email inbox alone does not
$p04$,
$p05$        jsonb_build_object('registration_id', r.registration_id, 'referral_code', r.referral_code,
                           'referrer_customer_id', r.referrer_customer_id, 'self_by', to_jsonb(v_by), 'customer_id', p_customer_id)
        || case when v_name_from in ('merged_record', 'login') then jsonb_build_object('name_from', v_name_from) else '{}'::jsonb end,
        'affiliate', public.event_web_referral_note(p.id),
$p05$,
$p06$  -- notes, the link named as switched off.
  -- 439 (the owner, 21 Oct 2026): when her record's affiliate login signed up
  -- under another name (437's rule 7 joins a login to a family member's record
  -- by its phone alone), the notes name the login too (answer 2); a held
  -- person's phone or email inbox no longer on any customer's record says what
  -- is true now: on a record since merged into another (that record named),
  -- or on none (answer 1).
  select case
    when 'customer' = any (p.referral_self_by) then
      format('Not referred: this is %s, the affiliate whose link (%s) was used%s. She earns no commission from it.',
             coalesce(a.full_name, 'the affiliate'), y.link,
             case when lg.other is not null then format(' (her record''s affiliate login was signed up as %s)', lg.other) else '' end)
    when p.referral_self_by is not null and p.customer_id is not null then
$p06$,
$p07$             || 'customer (someone else), so no referral or commission comes from this link.',
             y.self_how, y.who, y.link)
    when p.referral_self_by is not null then
$p07$,
$p08$             || 'through this link either.',
             y.self_how, y.who, y.link, y.who)
    when r.referral_state <> 'valid' then null
$p08$,
$p09$             || 'as a different person (Affiliates page), and no commission comes before that.',
             x.how, y.who, r.referral_code, coalesce(a.full_name, 'the affiliate'),
             coalesce(a.full_name, 'the affiliate'))
$p09$,
$p10$             in ('phone_in_use', 'phone_and_email_in_use', 'several_name_matches', 'legacy_ambiguous') then
      case when mg.phone_now is distinct from false then
      format('Their phone is on another customer''s record. If this is that customer, link their record: an existing customer '
$p10$,
$p11$             r.referral_code, coalesce(a.full_name, 'the affiliate'))
           when mg.phone_merged is not null then
      format('Their phone was on %s (listed). If this is that customer, link that record: an existing customer is not referred '
             || 'through this link (%s). If it is someone else, make a new customer: they become %s''s referral once an Owner or '
             || 'Manager checks them as a different person (Affiliates page), and no commission comes before that.',
             mg.phone_merged, r.referral_code, coalesce(a.full_name, 'the affiliate'))
           when coalesce(mg.mail_now, false) then
      format('Their email inbox is on another customer''s record. If this is that customer, link their record: an existing '
$p11$,
$p12$             || 'before that.', r.referral_code, coalesce(a.full_name, 'the affiliate'))
           when mg.mail_merged is not null then
      format('Their email inbox was on %s (listed). If this is that customer, link that record: an existing customer is not '
             || 'referred through this link (%s). If it is someone else, make a new customer: they become %s''s referral once an '
             || 'Owner or Manager checks them as a different person (Affiliates page), and no commission comes before that.',
             mg.mail_merged, r.referral_code, coalesce(a.full_name, 'the affiliate'))
           else
      format('Their phone was on another customer''s record when they registered, but is on no customer''s record now. If this '
             || 'is an existing customer, link their record: an existing customer is not referred through this link (%s). If it is '
             || 'someone else, make a new customer: they become %s''s referral at once.',
             r.referral_code, coalesce(a.full_name, 'the affiliate')) end
    when x.how is null and ((p.match = 'held' and p.referral_outcome = 'held')
                            or (p.is_test and p.test_outcome->>'referral' = 'held'))
         and coalesce(p.hold_reason, p.test_outcome->>'hold_reason') = 'email_in_use' then
      case when mg.mail_now is distinct from false then
      format('Their email inbox is on another customer''s record. If this is that customer, link their record: an existing '
             || 'customer is not referred through this link (%s). If it is someone else, make a new customer: they become %s''s '
             || 'referral once an Owner or Manager checks them as a different person (Affiliates page), and no commission comes '
             || 'before that.', r.referral_code, coalesce(a.full_name, 'the affiliate'))
           when mg.mail_merged is not null then
      format('Their email inbox was on %s (listed). If this is that customer, link that record: an existing customer is not '
             || 'referred through this link (%s). If it is someone else, make a new customer: they become %s''s referral once an '
             || 'Owner or Manager checks them as a different person (Affiliates page), and no commission comes before that.',
             mg.mail_merged, r.referral_code, coalesce(a.full_name, 'the affiliate'))
           else
      format('Their email inbox was on another customer''s record when they registered, but is on no customer''s record now. '
             || 'If this is an existing customer, link their record: an existing customer is not referred through this link (%s). '
             || 'If it is someone else, make a new customer: they become %s''s referral at once.',
             r.referral_code, coalesce(a.full_name, 'the affiliate')) end
    when p.referral_outcome = 'check_waiting'
$p12$,
$p13$    when p.referral_outcome = 'check_waiting' and x.how is null then
      format('Waiting for a check: %s. They become %s''s referral (link %s) '
             || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
             case when p.hold_reason = 'email_in_use' then
                    case when mg.mail_now is distinct from false then 'their email inbox is on another customer''s record'
                         when mg.mail_merged is not null then 'their email inbox was on ' || mg.mail_merged
                         else 'their email inbox was on another customer''s record when they were made a customer' end
                  else
                    case when mg.phone_now is distinct from false then 'their phone is on another customer''s record'
                         when mg.phone_merged is not null then 'their phone was on ' || mg.phone_merged
                         when coalesce(mg.mail_now, false) then 'their email inbox is on another customer''s record'
                         when mg.mail_merged is not null then 'their email inbox was on ' || mg.mail_merged
                         else 'their phone was on another customer''s record when they were made a customer' end end,
             coalesce(a.full_name, 'the affiliate'), r.referral_code)
$p13$,
$p14$             || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
             x.how, y.who, r.referral_code,
             coalesce(a.full_name, 'the affiliate'))
$p14$,
$p15$                                   ', ([^,]*)$', ' and \1'), '') as how) x
    -- 439: the name her record's affiliate login signed up with, when it is not her record's name (answer 2).
    left join lateral (
      select string_agg(distinct z.name, ' or ') as other
        from (select coalesce(nullif(btrim(coalesce(u.raw_user_meta_data->>'first_name', '') || ' '
                                           || coalesce(u.raw_user_meta_data->>'last_name', '')), ''),
                              nullif(btrim(coalesce(u.raw_user_meta_data->>'full_name', '')), '')) as name
                from public.affiliate_accounts aa join auth.users u on u.id = aa.auth_user_id
               where aa.customer_id = a.id) z
       where z.name is not null
         and not (coalesce(nullif(public.normalize_customer_match_name(a.full_name), '') = public.normalize_customer_match_name(z.name), false)
                  or public.customer_names_match(a.full_name, z.name))) lg on true
    cross join lateral (
$p15$,
$p16$                            ', ([^,]*)$', ' and \1') as self_how,
             r.referral_code || case when r.referral_state = 'link_off' then ', switched off' else '' end as link,
             case when lg.other is null then coalesce(a.full_name, 'the affiliate')
                  else format('%s (or %s, whose affiliate login is on her record)', coalesce(a.full_name, 'the affiliate'), lg.other)
             end as who) y
    -- 439: for someone held (or waiting for a check) through a valid link on another customer's phone or email
    -- inbox (answer 1): whether a customer other than their own record has it now, and the records since retired
    -- by a merge that had it (event_web_kept_customer names the record that kept each). Read only for them
    -- (each value under g, so the guest list does not read it for everyone).
    cross join lateral (
      select (p.match = 'held' or p.referral_outcome = 'check_waiting') and not p.is_test
             and p.referral_self_by is null and r.referral_state = 'valid' as ask) g
    cross join lateral (
      select case when g.ask then
               exists (select 1 from unnest(public.event_web_phone_holders(p.phone_norm)) h(id) where h.id is distinct from p.customer_id) end
               as phone_now,
             case when g.ask and p.hold_reason in ('email_in_use', 'phone_and_email_in_use') then
               exists (select 1 from public.customers c2
                        where c2.deleted_at is null and c2.id is distinct from p.customer_id
                          and public.customer_email_match_key(c2.email) = public.customer_email_match_key(p.email)) end as mail_now,
             case when g.ask then
               (select string_agg(format('%s''s record, since merged into %s''s', m.full_name, k.full_name), '; ' order by m.created_at, m.id)
                  from public.customers m join public.customers k on k.id = public.event_web_kept_customer(m.id)
                 where m.id = any (p.candidate_customer_ids) and m.deleted_at is not null
                   and (public.normalize_customer_phone(m.phone) = p.phone_norm
                        or (public.normalize_customer_phone(m.phone) is null and m.phone ~ '^[\s().0-9-]+$'
                            and (public.inspect_customer_phone(m.phone)->'candidates') ? p.phone_norm))) end as phone_merged,
             case when g.ask then
               (select string_agg(format('%s''s record, since merged into %s''s', m.full_name, k.full_name), '; ' order by m.created_at, m.id)
                  from public.customers m join public.customers k on k.id = public.event_web_kept_customer(m.id)
                 where m.id = any (p.candidate_customer_ids) and m.deleted_at is not null
                   and public.customer_email_match_key(m.email) = public.customer_email_match_key(p.email)) end as mail_merged) mg
   where p.id = p_person_id
$p16$,
$p17$  v_wait boolean := false; v_shares uuid[]; v_mail_holders uuid[] := '{}';
  v_kept_phone uuid[] := '{}'; v_kept_mail uuid[] := '{}'; v_live_phone int; v_live_mail int;
begin
$p17$,
$p18$  end if;
  -- 439 (the owner, 21 Oct 2026, answer 1): a customer they were held for whom
  -- a merge has since retired stands for the record that kept it
  -- (event_web_kept_customer, along a chain): that record holds the phone, or
  -- the email inbox, the retired one had, so the affiliate's and Q19's checks
  -- apply as they did before the merge (no referral at once).
  v_live_phone := cardinality(v_holders);
  v_live_mail := cardinality(v_mail_holders);
  select coalesce(array_agg(distinct x.kept) filter (where x.by_phone), '{}'::uuid[]),
         coalesce(array_agg(distinct x.kept) filter (where x.by_mail), '{}'::uuid[])
    into v_kept_phone, v_kept_mail
    from (select public.event_web_kept_customer(m.id) as kept,
                 coalesce(public.normalize_customer_phone(m.phone) = p.phone_norm
                          or (public.normalize_customer_phone(m.phone) is null and m.phone ~ '^[\s().0-9-]+$'
                              and (public.inspect_customer_phone(m.phone)->'candidates') ? p.phone_norm), false) as by_phone,
                 coalesce(public.customer_email_match_key(m.email) = public.customer_email_match_key(p.email), false) as by_mail
            from public.customers m
           where m.id = any (p.candidate_customer_ids) and m.deleted_at is not null) x
   where x.kept is not null;
  v_holders := v_holders || array(select k from unnest(v_kept_phone) k where not (k = any (v_holders)));
  v_mail_holders := v_mail_holders || array(select k from unnest(v_kept_mail) k where not (k = any (v_mail_holders)));
  if r.referral_state = 'valid' and public.event_web_check_self_referral(p.id, null) then
$p18$,
$p19$                         'registration_id', r.registration_id, 'shares', to_jsonb(public.event_web_affiliate_contact(p.id)),
                         'phone_shared_with', to_jsonb(v_shares))
      || case when cardinality(v_kept_phone) + cardinality(v_kept_mail) > 0
              then jsonb_build_object('merged_holders', to_jsonb(array(select k from unnest(v_kept_phone || v_kept_mail) k))) else '{}'::jsonb end,
      'affiliate', case when public.event_web_affiliate_contact(p.id) is not null
                        then 'Shares the affiliate''s own phone or email: referred once an Owner or Manager checks them as a different person'
                        when v_live_phone > 0
                        then 'Their phone is on another customer''s record: referred once an Owner or Manager checks them as a different person'
                        when cardinality(v_holders) > 0
                        then 'Their phone was on a customer''s record since merged into another: referred once an Owner or Manager checks them as a different person'
                        when v_live_mail > 0
                        then 'Their email inbox is on another customer''s record: referred once an Owner or Manager checks them as a different person'
                        else 'Their email inbox was on a customer''s record since merged into another: referred once an Owner or Manager checks them as a different person' end,
      null);
$p19$,
$p20$    -- holders, old numbers included, read once at registration), and whoever
    -- has their phone or their email's inbox now (as 433's list). 439 (the
    -- owner, 21 Oct 2026, answer 1): one a merge has since retired is listed
    -- as the record that kept it (event_web_kept_customer, along a chain),
    -- with the retired record it stands for (merged_from).
    'holds', coalesce((
$p20$,
$p21$                                             where h.customer_id = c.id) gv))
                          || coalesce((select jsonb_build_object('merged_from', jsonb_agg(jsonb_build_object(
                                                 'customer_id', mf.id, 'full_name', mf.full_name, 'phone', mf.phone, 'email', mf.email,
                                                 'phone_matches', coalesce(public.normalize_customer_phone(mf.phone) = p.phone_norm
                                                                           or (public.normalize_customer_phone(mf.phone) is null and mf.phone ~ '^[\s().0-9-]+$'
                                                                               and (public.inspect_customer_phone(mf.phone)->'candidates') ? p.phone_norm), false),
                                                 'email_matches', coalesce(public.customer_email_match_key(mf.email)
                                                                           = public.customer_email_match_key(p.email), false))
                                               order by mf.created_at, mf.id))
                                         from public.customers mf
                                        where mf.id = any (p.candidate_customer_ids) and mf.deleted_at is not null
                                          and public.event_web_kept_customer(mf.id) = c.id
                                       having count(*) > 0), '{}'::jsonb)
                          order by c.created_at)
$p21$,
$p22$                   -- scan of every customer per held person.
                   from (select public.event_web_kept_customer(u.id) as id from unnest(p.candidate_customer_ids) u(id)
                         union
$p22$,
$p23$declare p public.event_registration_people%rowtype; c public.customers%rowtype; r public.event_registrations%rowtype;
  v_outcome text; v_retry jsonb; v_kept uuid;
begin
$p23$,
$p24$  select * into c from public.customers where id = p_customer_id for update;
  if not found then raise exception 'Customer not found.'; end if;
  -- 439 (the owner, 21 Oct 2026, answer 1): a record a merge has retired (the
  -- page listed it before the merge) is the record that kept it, along a chain.
  if c.deleted_at is not null then
    -- each pass takes a fresh look: a record merged while this one waited for its lock is followed again
    for i in 1 .. 20 loop
      v_kept := public.event_web_kept_customer(c.id);
      if v_kept is null then raise exception 'Customer not found.'; end if;
      select * into c from public.customers where id = v_kept for update;
      if not found then raise exception 'Customer not found.'; end if;
      exit when c.deleted_at is null;
    end loop;
    if c.deleted_at is not null then raise exception 'Customer not found.'; end if;
  end if;
  select * into r from public.event_registrations where id = p.registration_ref;
$p24$,
$p25$    jsonb_build_object('customer_id', c.id, 'hold_reason', p.hold_reason, 'registration_id', r.registration_id,
                       'suggested_customer', c.id = any (p.candidate_customer_ids)
                                             or exists (select 1 from public.customers m
                                                         where m.id = any (p.candidate_customer_ids) and m.deleted_at is not null
                                                           and public.event_web_kept_customer(m.id) = c.id),
                       'referral_outcome', v_outcome)
    || case when v_kept is not null then jsonb_build_object('asked_customer_id', p_customer_id, 'merged_into', v_kept) else '{}'::jsonb end,
    'events', btrim(p_note), (select s.store_id from public.event_web_settings s where s.event_id = p.event_id));
$p25$];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int;
  v_texts text[] := array[null, null, null, null, null, null]::text[];
  v_acls text[] := array[null, null, null, null, null, null]::text[];
  v_new boolean := false;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_event uuid; t_live text; t_hash text;
  t_aff uuid; t_affid uuid; t_login uuid; t_hold uuid; t_keep uuid; t_ans jsonb; t_p1 uuid; t_p2 uuid; t_p3 uuid; t_c2 uuid;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 21 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing is installed unless all pass ─────────────────────
  -- What it relies on and does not change: as 436 left it (21 Oct 2026).
  for r in select * from (values
      ('customer_names_match(text,text)', 'ef1af52e4888cefb6037a2291f4e011d'),
      ('customer_email_match_key(text)', 'be468815c9626fff1728e2cfcd484b66'),
      ('normalize_customer_match_name(text)', '0572764712e179dc606c66f9f3dbaa03'),
      ('normalize_customer_phone(text)', 'b2bfac910e0c9eff402ba44e19750bee'),
      ('inspect_customer_phone(text,text)', '6672c4d1963996f3b601896f4a55916e'),
      ('merge_customer_records(uuid,uuid,text,uuid)', '099ecf3aae30b5faaf8fb36bc15ce888'),
      ('write_audit(text,uuid,text,jsonb,jsonb)', 'b194f839993670c5b5dd28e934c2a829'),
      ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
      ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
      ('event_can_run(uuid)', 'dac12d0086533bb528e847eb828809df'),
      ('user_has_store_access(uuid)', '708992afaa6c3951f6329239b742987c'),
      ('create_customer_quick(text,text,text,text,date,text,text,text,text,uuid,uuid)', '9ff9031d3b40029a19c729a512e99798'),
      ('event_web_phone_holders(text)', '614602e9cbc483d79bdef7d60aaf6a33'),
      ('event_web_match_customer(text,text,text)', '16ec3e9f65d619b3f3feeef712bfd132'),
      ('event_web_fill_customer(uuid,uuid)', '89488f15e0b030b9ed14c3c31049a71e'),
      ('event_web_apply_referral(uuid,uuid)', 'b034075f9882cb4221e3a554e6453317'),
      ('event_web_register(uuid,jsonb)', 'e3efd309e81d17c97f7984f7ecbaafff'),
      ('event_registration_create_customer(uuid,text)', '23bc6941cd4b4db0fae101965292a324'),
      ('event_vip_retry_after_match(uuid)', '06dafbb11f5b034dde31ef8fb9ffeedf'),
      ('event_vip_holders(uuid)', 'f8e1f118a88d311bbdbcd86d14a5046d'),
      ('event_web_person_vip_state(uuid)', 'fc0a3c9ce094fe72e69cff7f420837b6'),
      ('trg_event_web_referral_check_decided()', '9dea4cead38c8c990ad46f435d787520'),
      ('event_web_call(text,uuid,text,jsonb)', 'e114ba39de4923cc52ed426e27d9bfde')) t(fn, ok)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.ok then
      raise exception '439: public.% is missing or not the version this was tested against (436 as applied). Re-read it and re-test before applying.', r.fn;
    end if;
  end loop;

  -- The columns 439 reads, as read on 21 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('public.customers', 'id uuid'), ('public.customers', 'full_name text'), ('public.customers', 'phone text'),
      ('public.customers', 'email text'), ('public.customers', 'notes text'), ('public.customers', 'created_at timestamp with time zone'),
      ('public.customers', 'deleted_at timestamp with time zone'),
      ('public.audit_logs', 'record_id uuid'), ('public.audit_logs', 'action text'), ('public.audit_logs', 'new_data jsonb'),
      ('public.audit_logs', 'created_at timestamp with time zone'), ('public.audit_logs', 'reason text'),
      ('public.affiliate_accounts', 'auth_user_id uuid'), ('public.affiliate_accounts', 'customer_id uuid'),
      ('auth.users', 'id uuid'), ('auth.users', 'email character varying(255)'), ('auth.users', 'raw_user_meta_data jsonb'),
      ('public.event_registration_people', 'candidate_customer_ids uuid[]'), ('public.event_registration_people', 'hold_reason text'),
      ('public.event_registration_people', 'match text'), ('public.event_registration_people', 'referral_self_by text[]'),
      ('public.event_registration_people', 'referral_outcome text'), ('public.event_registration_people', 'phone_norm text'),
      ('public.event_registration_people', 'email text'), ('public.event_registration_people', 'customer_id uuid'),
      ('public.event_registration_people', 'is_test boolean'),
      ('public.event_registrations', 'referrer_customer_id uuid'), ('public.event_registrations', 'referral_state text')) x(t, c)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass(x.t) and a.attnum > 0 and not a.attisdropped
                        and a.attname || ' ' || format_type(a.atttypid, a.atttypmod) = x.c);
  if v is not null then
    raise exception '439: these columns are missing or not as read on 21 Oct 2026 (is 436 applied?): %', v; end if;

  -- The helper: missing, or already this version (left alone); no other function takes its name.
  if md5(c_new_def) <> c_new_md5 then
    raise exception '439: the text of public.% is not the tested one (md5 %)', c_new_sig, md5(c_new_def); end if;
  if to_regprocedure('public.' || c_new_sig) is null then
    v_new := true;
  elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig))) <> c_new_md5 then
    raise exception '439: public.% exists and is not this migration''s version', c_new_sig;
  else
    raise notice '439: % is already this version; left alone', c_new_sig;
  end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = split_part(c_new_sig, '(', 1)
     and p.oid::regprocedure::text <> c_new_sig;
  if v is not null then raise exception '439: another function takes its helper''s name: %', v; end if;

  -- The six: BEFORE (patched, each anchor once) or AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    d := pg_get_functiondef(('public.' || c_sigs[k])::regprocedure);
    v_acls[k] := (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure);
    if md5(d) = c_after[k] then
      raise notice '439: public.% is already this version; left alone', c_sigs[k];
    elsif md5(d) <> c_before[k] then
      raise exception '439: public.% is not 436''s version (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d);
    else
      for i in 1 .. cardinality(c_fn) loop
        continue when c_fn[i] <> k;
        n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
        if n <> 1 then raise exception '439: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
        d := replace(d, c_anchor[i], c_patch[i]);
      end loop;
      if md5(d) <> c_after[k] then
        raise exception '439: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
      v_texts[k] := d;
    end if;
  end loop;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_new then
    execute c_new_def;
    execute format('revoke all on function public.%s from public, anon, authenticated', c_new_sig);
    execute format('grant execute on function public.%s to service_role', c_new_sig);
  end if;
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if md5(pg_get_functiondef(('public.' || c_new_sig)::regprocedure)) <> c_new_md5 then
    raise exception '439: public.% was installed with an md5 other than the tested one', c_new_sig; end if;
  if has_function_privilege('anon', 'public.' || c_new_sig, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_new_sig, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_new_sig, 'execute') then
    raise exception '439: the grants of public.% are not as tested (the service role''s alone)', c_new_sig; end if;
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(('public.' || c_sigs[k])::regprocedure)) <> c_after[k] then
      raise exception '439: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = ('public.' || c_sigs[k])::regprocedure) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute') is distinct from c_page[k]
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '439: the grants of public.% changed', c_sigs[k]; end if;
  end loop;

  -- ── 4. Behaviour, in a block that is always undone ──────────────────────
  -- Made-up records only ("439 check", @example.invalid, fictional phones);
  -- it ends by raising P0439, which undoes all it wrote.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    t_sfx := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    select array_agg(x order by x) into t_phones
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(8000, 8999) g
             where not exists (select 1 from public.customers c
                                where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(g::text, 4, '0'))
             limit 4) y;
    insert into auth.users (id, email) values (gen_random_uuid(), '439-check-' || lower(t_sfx) || '@example.invalid')
      returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '439 check', u.email, 'owner', true from auth.users u where u.id = t_owner;
    insert into public.stores (name, code, country_code) values ('439 check ' || t_sfx, '439-' || t_sfx, 'SG') returning id into t_store;
    insert into public.events (name, daily_start, daily_end, is_active) values ('439 check ' || t_sfx, '09:00', '19:00', true)
      returning id into t_event;
    insert into public.event_days (event_id, day) values (t_event, public.sg_today() + 30);
    insert into public.event_stores (event_id, store_id) values (t_event, t_store);
    insert into public.event_web_settings (event_id, code, mode, store_id, acting_profile_id)
    values (t_event, 'CHECK439-' || t_sfx, 'live', t_store, t_owner);
    t_live := 'evk_live_' || rpad(t_sfx, 43, 'L');
    t_hash := encode(extensions.digest(t_live, 'sha256'), 'hex');
    insert into public.event_web_keys (event_id, kind, key_hash, key_hint, created_by)
    values (t_event, 'live', t_hash, '439 check', t_owner);
    -- The affiliate's record, its login signed up under another name (a
    -- family member's record joined by its phone alone), a phone holder and
    -- the record it will be merged into.
    insert into public.customers (full_name, phone) values ('Check Recordname', t_phones[1]) returning id into t_aff;
    insert into public.customer_affiliates (customer_id, status, referral_code) values (t_aff, 'active', 'CHK439' || t_sfx)
      returning id into t_affid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), '439-login-' || lower(t_sfx) || '@example.invalid',
            jsonb_build_object('first_name', 'Check', 'last_name', 'Loginname', 'phone', t_phones[1]))
      returning id into t_login;
    insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (t_login, t_aff, t_affid, 'claimed');
    insert into public.customers (full_name, phone) values ('Check Holder', t_phones[2]) returning id into t_hold;
    insert into public.customers (full_name, phone) values ('Check Kept', t_phones[3]) returning id into t_keep;
    -- One form through her link: two other people on the holder's phone, and the login's own name on a new phone and email.
    t_ans := public.event_web_call(t_hash, gen_random_uuid(), 'register',
      jsonb_build_object('type', 'register', 'event', 'CHECK439-' || t_sfx, 'registration', jsonb_build_object(
        'registration_id', 'REG-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || t_sfx, 'submitted_at', now(),
        'referral_code', 'CHK439' || t_sfx, 'people', jsonb_build_array(
          jsonb_build_object('position', 1, 'first_name', 'Other', 'last_name', 'Person', 'phone', t_phones[2],
                             'email', 'other-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false),
          jsonb_build_object('position', 2, 'first_name', 'Third', 'last_name', 'Person', 'phone', t_phones[2],
                             'email', 'third-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false),
          jsonb_build_object('position', 3, 'first_name', 'Check', 'last_name', 'Loginname', 'phone', t_phones[4],
                             'email', 'self-' || lower(t_sfx) || '@example.invalid', 'days', jsonb_build_array(public.sg_today() + 30), 'vip', false)))));
    t_p1 := (t_ans->'people'->0->>'person_id')::uuid;
    t_p2 := (t_ans->'people'->1->>'person_id')::uuid;
    t_p3 := (t_ans->'people'->2->>'person_id')::uuid;
    if t_ans->>'status' <> 'registered'
       or (select count(*) from public.event_registration_people p
            where p.id in (t_p1, t_p2) and p.match = 'held' and p.hold_reason = 'phone_in_use'
              and p.candidate_customer_ids = array[t_hold] and p.referral_outcome = 'held') <> 2
       or (select (p.match, p.hold_reason, p.candidate_customer_ids, p.referral_outcome, p.referral_self_by)
                  is distinct from ('held'::text, 'affiliate_name'::text, array[t_aff], 'self'::text, array['name'])
             from public.event_registration_people p where p.id = t_p3)
       or exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = t_phones[4]) then
      raise exception '439: the self-test''s registration is not as tested (the login''s own name held as herself): %', t_ans; end if;
    -- The holder merged into the kept record (an Owner): the kept record is the
    -- candidate, the retired id attaches to it, and the other person made a
    -- customer waits for the check, shared with the kept record.
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform public.merge_customer_records(t_keep, t_hold, '439 check', gen_random_uuid());
    t_ans := public.event_web_guest_extras(t_event);
    if (select jsonb_agg(c->>'customer_id') from jsonb_array_elements(t_ans->'holds') h, jsonb_array_elements(h->'candidates') c
         where (h->>'person_id')::uuid = t_p1) is distinct from jsonb_build_array(t_keep::text)
       or (select c->'merged_from'->0->>'customer_id' from jsonb_array_elements(t_ans->'holds') h, jsonb_array_elements(h->'candidates') c
            where (h->>'person_id')::uuid = t_p1) is distinct from t_hold::text then
      raise exception '439: the self-test''s To match does not show the kept record: %', t_ans->'holds'; end if;
    perform public.event_registration_attach(t_p1, t_hold, '439 check');
    perform public.event_registration_create_customer(t_p2, '439 check');
    select p.customer_id into t_c2 from public.event_registration_people p where p.id = t_p2;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    if (select (p.customer_id, p.match, p.referral_outcome) is distinct from (t_keep, 'staff_attached'::text, 'already_customer'::text)
          from public.event_registration_people p where p.id = t_p1)
       or (select p.referral_outcome from public.event_registration_people p where p.id = t_p2) is distinct from 'check_waiting'
       or (select c.referred_by from public.customers c where c.id = t_c2) is not null
       or not exists (select 1 from public.referral_signup_checks k
                       where k.customer_id = t_c2 and k.status = 'pending' and k.referrer_customer_id = t_aff
                         and k.phone_shared_with = array[t_keep])
       or public.event_web_kept_customer(t_hold) is distinct from t_keep then
      raise exception '439: the self-test''s attach to the retired id, or the check after the merge, is not as tested'; end if;
    raise exception using errcode = 'P0439', message = '439: self-test done, undone';
  exception when sqlstate 'P0439' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
