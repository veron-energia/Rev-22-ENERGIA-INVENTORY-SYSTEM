-- 486_merge_guard_keeps_the_affiliate_record.sql
--
-- A MERGE NO LONGER RETIRES THE RECORD THAT HOLDS THE PORTAL LOGIN OR THE
-- AFFILIATE RECORD INTO A RECORD THAT HAS NEITHER: THE MERGE PREVIEW REFUSES
-- IT, AND STAFF KEEP THE AFFILIATE'S RECORD INSTEAD (the Owner, 2 Nov 2026),
-- BUT FOR THE MERGE INSIDE LINK TO THIS CUSTOMER, WHICH STAYS ALLOWED (the
-- Owner, 2 Nov 2026: see THE RULE)
--
-- WHY
--   484 shows an affiliate the phone numbers of the direct referrals the /r/
--   page told, and only when the affiliate's portal login is proven to be its
--   record's. One proof is (d), verified_email: the login's email is verified
--   and is the record's email (customer_email_match_key: the same inbox).
--   485 stopped the forms (the QR health form, the event website's
--   registration, and staff attaching or linking a held one) from putting an
--   email on a record that has a portal login or an affiliate record. 485's
--   final check found the way round it that was already there: a merge.
--   There is no merge screen; the developer runs merge_customer_records
--   through the MCP, as an Owner, on the Owner's word. A merge that KEEPS a
--   record whose email a form typed while it had neither a portal login nor
--   an affiliate record, and RETIRES the record that holds the portal login,
--   the affiliate record or /r/ marks, moves them onto that email (the merge
--   moves the affiliate record when the record kept has none, and the login
--   and the marks along their foreign keys). The login then verifies that
--   inbox and is proven (d), and the moved marks' numbers show. A merge
--   decides that two records are one person, not whose login it is.
--   Reach on 2 Nov 2026: none. No merge since 484 (18 in all, 25 Sep to 27
--   Oct; 2 of them moved a portal login: one inside the 24 Oct Link to this
--   customer, one by hand). That one by hand (26 Sep) kept a record with
--   neither, which held the invoices and had credit allocations (wallet
--   credit spent or taken off), and retired the affiliate's record with its
--   portal login, affiliate record and referrals: the direction this file
--   refuses; because of those allocations a pair like that cannot be merged
--   the other way either (NOT COVERED). 87 customers in use hold a portal
--   login or an affiliate record (86 logins, 87 affiliate records, none
--   deleted), every login on a record with an affiliate record; no retired
--   record holds either; 1 mark, and its referrer has an affiliate record.
--   The Owner (2 Nov 2026): "Build a merge guard next". Until it is in,
--   staff check before merging an affiliate's record.
--
-- THE RULE (the Owner, 2 Nov 2026)
--   The merge preview refuses to retire the record that holds the portal
--   login or the affiliate record when the record kept has neither; staff
--   simply keep the other record. Exactly: a new blocking issue,
--   'duplicate_has_affiliate_account', when the duplicate (p_merge) has
--   (a) a portal login: an affiliate_accounts row for it (claimed or
--       disabled), or
--   (b) an affiliate record: a customer_affiliates row for it, in any status
--       (active, suspended, inactive, deleted), or
--   (c) /r/ marks naming it as referrer: referral_phone_notices rows whose
--       referrer_customer_id is it (withdrawn ones too),
--   and the record to keep (p_keep) has neither a portal login nor an
--   affiliate record (in any status, deleted included; on this side that
--   lets more merges through, not fewer: NOT COVERED). Its detail names what
--   the duplicate holds (the portal login, the affiliate record, "<n> /r/
--   phone-notice mark(s) naming it as referrer", joined as "a", "a and b" or
--   "a, b and c") and says what to do, for example: "The duplicate holds the
--   portal login and the affiliate record; the record to keep has neither a
--   portal login nor an affiliate record. A merge decides that two records
--   are one person, not whose login it is: keep the affiliate's record and
--   merge the other one into it." merge_customer_records then refuses as for
--   any blocking issue ("This merge needs review first: <details>") before
--   it changes anything. Marks that name the duplicate as the referral
--   (customer_id) are not this rule's: they follow the record as before
--   (484's NOT COVERED).
--   NOT refused (the Owner, 2 Nov 2026: "Yes, keep Link allowed"): the
--   merge inside 437's "Link to this customer" on the Affiliates page.
--   link_affiliate_signup keeps the customer already there and retires the
--   fresh sign-up record, with its portal login and affiliate record,
--   through merge_customer_records; for a customer with no affiliate record
--   of their own that is exactly the direction refused above, and the Link
--   cannot keep the other record. It is an Owner's or a Manager's decision
--   about whose login it is (484 counts it as proof: same_person, 'linked';
--   485's NOT COVERED names it as a way to prove a login). Refusing it would
--   refuse every Link to a customer with no affiliate record. The preview
--   tells that merge apart by its call stack (GET DIAGNOSTICS PG_CONTEXT:
--   called by merge_customer_records(uuid,uuid,text,uuid), itself called by
--   link_affiliate_signup(uuid,uuid,text,uuid,boolean)), frames that only
--   PL/pgSQL functions of those exact names and argument types print; any
--   other caller is refused (NOT COVERED: a look-alike). Production, 2 Nov
--   2026: one Link ever (24 Oct, to a customer with an affiliate record of
--   their own, which the rule does not refuse); no sign-up open to be linked.
--
-- WHAT THIS DOES
--   Replaces ONE function, public.preview_customer_merge(uuid,uuid)
--   (production's: 318's text of 15 Sep 2026, which 445 and 462 pin
--   unchanged; 339 later narrowed its grants to the owner and the service
--   role), with its tested text, made from production's own text by ONE
--   insertion: a block between the last blocking check (a commission between
--   the two) and the return. Every other line is unchanged: who may run it
--   and its three errors, what the duplicate holds ('moving'), the four
--   blocking issues before (duplicate_already_deleted, keeper_deleted,
--   two_affiliate_records, commission_between_the_two: their words and their
--   order), the wallets and the answer's shape. The new issue comes after
--   them. The marks are read with dynamic SQL, and only while
--   referral_phone_notices is there (to_regclass): 484's UNDO level 2 drops
--   that table, and a body that read it unguarded would then fail every
--   merge. (c) is a safeguard: a mark is made only through an affiliate's
--   referral code, and an affiliate record is deleted outright only by the
--   Link, for a fresh record with no referral; on 2 Nov 2026 no mark names a
--   referrer without an affiliate record. CREATE OR REPLACE keeps the
--   function's grants (the owner's and the service role's; no client role;
--   checked again as a set).
--
-- NOT CHANGED
--   * merge_customer_records (462's): it runs the preview first and refuses
--     on any blocking issue, as before; what it moves, and how, is as before.
--   * link_affiliate_signup (437's) and the Affiliates page; every other
--     function, table, index, column and grant.
--   * A merge that keeps the record with the portal login or the affiliate
--     record, whatever the duplicate holds: as before (the refusal of two
--     affiliate records in use included).
--
-- NOT COVERED (told to the Owner)
--   * A record kept that has an affiliate record but no portal login takes
--     the duplicate's login (and a record kept with a login takes the
--     duplicate's affiliate record): the rule asks only that the record kept
--     have one of the two. Since 485 no form puts an email on such a record;
--     one typed before 485 stays (485's one-off check of 2 Nov found none
--     from a form on a referrer's or an affiliate's record).
--   * Both records with a portal login: the merge still stops on the logins'
--     unique key (a raw error, 318's limit).
--   * A record kept whose only affiliate record is deleted (deleted_at set)
--     counts as having one, so the duplicate's portal login, affiliate
--     record and /r/ marks may still be retired into it, as before. The
--     merge moves the login and the marks onto the record kept and leaves
--     the duplicate's affiliate record on the retired record (it moves one
--     only to a record with none): the login then names an affiliate record
--     on a retired customer, and the record kept is not an active affiliate
--     (no numbers in My Network; tier-1 commission is written blocked). If
--     the record kept's email is the login's and the login has verified it
--     (a form may have typed it while the record was ordinary), the login is
--     proven at once (verified_email), and once staff re-activate the record
--     kept's affiliate record (activate_affiliate clears deleted_at) the
--     moved referrals' numbers show. 437's Link refuses this shape ("This
--     customer's affiliate record was removed ..."). Nothing in the app
--     marks an affiliate record deleted (no function sets deleted_at, and
--     clients may only read the table), and production has none on 2 Nov
--     2026; should one ever be, keep the live affiliate's record.
--   * Link to this customer is told apart by its call stack: a later change
--     that renames link_affiliate_signup or merge_customer_records, or
--     changes how the Link calls the merge (through another function, or
--     with a query in the call's arguments, which adds a frame), makes the
--     preview refuse the Link to a customer with no affiliate record (the
--     safe direction: the Affiliates page shows "This merge needs review
--     first: ..." and nothing changes; 437's suite and this file's L checks
--     show it). So does a Link made later in a transaction in which an error
--     thrown through the Link's call to the merge, or through the merge's
--     call to the preview, was caught (PL/pgSQL then makes that call another
--     way, which adds a frame); the Affiliates page runs each Link in its
--     own transaction. The stack is read in English (production's
--     lc_messages is en_US.UTF-8, a superuser setting).
--   * A look-alike passes: a PL/pgSQL function with the Link's exact name
--     and argument types in another schema prints the same frame when it is
--     visible by name at its first call in a session (its schema ahead of
--     public on the search path then in force, public absent, or its own SET
--     search_path naming its schema), and a merge it makes is let through,
--     as is one made by a look-alike that renames or drops itself first; no
--     check in the preview can rule it out. One in pg_temp, or hidden behind
--     public's Link at that first call, prints its schema and is refused
--     (this file's suite tries pg_temp). Only a role that can create
--     functions can make one: on 2 Nov 2026, postgres and the platform's
--     superuser, which can change the preview or the rows anyway. The guard
--     is against keeping the wrong record by mistake, not against them.
--   * Keeping the affiliate's record keeps its referrer and its details: the
--     merge copies no field and never the duplicate's referrer
--     (customer-merge-how-to). When the two referrers differ, the Owner says
--     which stays; if it is the other record's, it is set in the merge's own
--     block (reassign_customer_referrer, as Correct Referrer does). That
--     moves tier 1 on the person's later purchases, tier 2 on their
--     referrals' later purchases (the record kept is an affiliate's) and a
--     moved part-paid invoice's part-payment commission at its next payment,
--     and it dates the referral today, which a referral promotion counts by.
--     Details (DOB, legacy notes, a name) are copied after the merge, as
--     before, but never the retired record's email onto a record kept that
--     has a portal login or an affiliate record: that is a decision about
--     the email itself (485), made in Edit customer only when staff know it
--     is the person's own inbox. Copied, a form-typed email that is the
--     login's proves the login once verified (verified_email), and its /r/
--     referrals' numbers show.
--   * Since 445 the merge carries the other record's unspent credit with its
--     origin, so keeping the affiliate's record no longer costs a package's
--     release chain. Spent credit does not move: a record that has ever
--     spent wallet credit, or had credit taken off by staff
--     (customer_credit_allocations rows), cannot be the duplicate ("Credit
--     allocations cannot be changed once recorded": 445's NOT COVERED 1, as
--     since 318). So when that record is the one with neither a portal login
--     nor an affiliate record, the pair cannot be merged either way: this
--     file refuses keeping it, and keeping the affiliate's record fails on
--     the allocations (nothing changes either way). Only Link to this
--     customer, for a listed sign-up, still merges that shape. On 2 Nov
--     2026, 1 of the 23 possible pairs of an affiliate's record and a record
--     with neither (the same phone, email or name) has it, not known to be
--     one person; the 26 Sep merge had it. Outside a listed sign-up, such a
--     pair stays as two records (the Owner, 2 Nov 2026: "Leave them as two
--     records"): nothing is built for it, and a real case goes to the Owner.
--   * Merges made before this file stay as they are.
--
-- SAFETY
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * preview_customer_merge(uuid,uuid) is production's of 2 Nov 2026
--     (BEFORE: replaced) or this file's (AFTER: "already this version; left
--     alone", nothing changed); anything else is refused; no other function
--     takes its name; its grants, compared as a set, are the owner's and the
--     service role's;
--   * the functions it relies on are as read on 2 Nov 2026:
--     merge_customer_records (it runs the preview and obeys it; the
--     self-test calls it), link_affiliate_signup (the call stack names it)
--     and is_owner_or_manager;
--   * the columns the new lines read are there, of the types read (the
--     marks' only while their table is there).
--   Afterwards: the function has its AFTER md5 and its grants as before.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0486, so it leaves no row and takes no number from any sequence): a
--   made-up active Owner (a login and a profile) signed in for the block, and
--   made-up customers ("486 Check ...", fictional phones +61 2 5550 nnnn that
--   no customer, in use or deleted, holds): an affiliate's (an affiliate
--   record, no login), a portal login's (no affiliate record; its
--   welcome-WhatsApp trigger off for that one insert) and a plain one.
--   Keeping the plain record and retiring the affiliate's, or the login's:
--   the preview answers the new issue alone, in its words, with can_merge
--   false, and merge_customer_records refuses with "This merge needs review
--   first: ..." before it changes anything. The other way round (keeping the
--   affiliate's record, or the login's, and retiring the plain one): no
--   blocking issue. No merge is made. A second run changes nothing
--   ("already this version; left alone"; its self-test runs and is undone
--   again).
--   The self-test proves the refusal only, not the exemption of Link to this
--   customer, which rests on the call stack's wording: 437's, 440's and this
--   file's suites prove it on a production-equal copy (PostgreSQL 17.6 with
--   the same lc_messages and preloaded libraries as production, 2 Nov 2026).
--   Were production's stack ever to read otherwise, the Link would be
--   refused and change nothing (NOT COVERED).
--   Locks: the lock timeout is 2 s. Replacing a function locks its
--   catalogue row only (a merge already running keeps the old version to its
--   end). The self-test locks only its own rows.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--   1. Dry run on a copy of production as it is then (rc480_live plus
--      production's two store codes, 480's history row, and 483, 482, 484
--      and 485 applied from their files with their history rows; its public
--      fingerprint and grant list must equal production's): apply this file
--      wrapped, then again. The first run ends at the AFTER fingerprint
--      below; the second says "already this version; left alone" and
--      changes nothing.
--   2. Apply wrapped: begin; this file; insert into
--      supabase_migrations.schema_migrations (version, name, statements)
--      values (<version>, '486_merge_guard_keeps_the_affiliate_record',
--      array[<this file>]); commit. Build the wrapper with the file embedded
--      as a literal (Python), never with $(cat ...) or a psql backtick
--      variable, which drop the final newline. Run it as postgres (the
--      Supabase CLI's db query --linked does): the self-test inserts made-up
--      logins into auth.users and sets session_replication_role.
--      Read the row back at once, and before any retry:
--        select md5(array_to_string(statements, '')), cardinality(statements)
--          from supabase_migrations.schema_migrations
--         where name = '486_merge_guard_keeps_the_affiliate_record';
--      It must give this file's md5 and 1 (a row means the apply committed:
--      never apply again). Checks: the AFTER md5 and grants below; the
--      fingerprint and the grant list (AFTER); no "486 Check" customer.
--   3. Five suites merged an affiliate's record into a record with neither,
--      which this file refuses:
--      scripts/customer-merge/tests/merge-duplicates.sql (the duplicate's
--      affiliate record carried across) and merge-credit-origin-445.sql
--      (Mike, the affiliate, into Kilo);
--      scripts/referrals/tests/affiliate-network-phone-484.sql (R8, A's own
--      record into an older one);
--      scripts/event-website/tests/event-website-439.sql (MB1 to MB4, MD3,
--      MD4) and event-website-441.sql (F, A1 to A3, P1). They were rebuilt
--      in the same change so that they keep their coverage. Where a check is
--      about an affiliate's own record retired into an older record (a shape
--      the Link still creates; production has it from the 26 Sep merge by
--      hand, whose retired record also held a portal login), that shape is
--      built through link_affiliate_signup, or by a merge run inside the
--      test's transaction with production's preview text of 2 Nov 2026
--      swapped in (486's block cut out by position, md5 f66c9d63 asserted),
--      and a check is added that a merge by hand in that direction is
--      refused. Where a check is about the merge itself, the record kept is
--      given a claimed portal login with no affiliate record (a shape only
--      the tests make; it relies on NOT COVERED's first item).
--      Checks changed (none removed; every other label as it was):
--      * merge-duplicates.sql: new "486: a duplicate that holds the
--        affiliate record is not merged into a record with neither ...";
--        the main check (same label) keeps a record given a portal login;
--        its fixture phones are now fictional (+61 2 5550 nnnn).
--      * merge-credit-origin-445.sql: new G1 (Mike is not merged into Kilo
--        while Kilo has neither); Kilo has a portal login from G on.
--      * affiliate-network-phone-484.sql: R8 (same label, now ending with
--        the swap's md5s) merges with the 2 Nov preview swapped in; new R8a
--        (the merge by hand is refused) and R8b (the same shape through the
--        Link, after asking the preview about the merge by hand).
--      * event-website-439.sql: MB1 to MB5 run after a Link (Bea's sign-up
--        record joined to her older record); new MB6 (by hand refused)
--        and MB7 (production's login shape, through 437's own sign-up
--        and listing); Cora's merge in MD (behind MD3 and MD4) runs with the
--        2 Nov preview swapped in; new MD0 (that merge ran) and MD5 (by hand
--        refused).
--      * event-website-441.sql: F, A1 to A3 and P1 run after a Link (Gia's
--        sign-up record); new A4 (by hand refused) and A5 (production's
--        login shape); P1 now counts 12 retired records.
--      Commit and push, in one push, this file, its suite
--      (scripts/customer-merge/tests/merge-guard-486.sql) and those five
--      suites. Update the merge notes (customer-merge-how-to): keep the
--      affiliate's record; compare the two referrers first and ask the Owner
--      when they differ; copy no email onto it as a detail; when the other
--      record has ever spent wallet credit or had credit taken off, the pair
--      cannot be merged and stays as two records (the Owner, 2 Nov 2026; a
--      real case goes to the Owner: NOT COVERED). 485's merge route for a
--      login joined on the phone alone (a merge into a record whose email
--      staff know is the login's) is refused by this file when that record
--      has neither a portal login nor an affiliate record. 485's other
--      routes stay: Edit customer, when staff know the inbox is the
--      person's own; Same person (437's
--      confirm_affiliate_signup_same_person, not a merge, untouched by this
--      file); or the Owner's Unlink then Link to this customer (its merge
--      stays allowed: the Owner, 2 Nov 2026). There are no pages.
--   479 and 481 (another session's refund and stock fixes) touch no merge
--   function and may go before or after 486; whichever goes second restates
--   its fingerprint.
--   445's and 462's files pin this function's BEFORE md5: neither runs again
--   over this file (by design: nothing to re-run).
--
-- BEFORE (production, 2 Nov 2026, head 20261102033119 (485); md5 of
-- pg_get_functiondef with search_path public)
--   preview_customer_merge(uuid,uuid)                    f66c9d63369ef3b831ca74906a99b587  (318's; 339 narrowed its grants)
--     grants, as a set: {postgres=X/postgres,service_role=X/postgres}
--   relied on, not changed
--   merge_customer_records(uuid,uuid,text,uuid)          ba05c2b1fb4c0e14d369c01d06a635b0  (462's)
--   link_affiliate_signup(uuid,uuid,text,uuid,boolean)   198780b31301695db55c4a39ba9618f8  (437's)
--   is_owner_or_manager()                                a98e50f1b6d3fa1e6c62cf52a8073cc8
--   public function fingerprint                          d5bcc0cef63fe73c19cf2c9a949b05d5 (1398 functions)
--   grant list                                           e68aa1abc012f3e4539dd315b96a1ea1
-- AFTER (for later guards)
--   preview_customer_merge(uuid,uuid)                    b98004c9a2522d7e564d34f10ca4e574
--     grants, as a set: {postgres=X/postgres,service_role=X/postgres}
--   public function fingerprint                          987d9ea60beaec88fb6146d3db6f9441 (1398, worked out on a
--                                                        production-equal copy, 2 Nov 2026)
--   grant list                                           e68aa1abc012f3e4539dd315b96a1ea1 (unchanged)
--
-- UNDO (with the Owner's go-ahead). Run the lines between the two markers
-- below with their leading "--   " removed, after putting this file's md5
-- as applied (its history row's) in place of <M>. It stops unless the
-- function is this file's; rebuilds production's text of 2 Nov 2026 by
-- taking 486's block out again, and runs it only if its md5 is the BEFORE
-- one; and deletes every 486 history row holding the file. The 486 suite's
-- U section runs it as written.
--   ---- UNDO 486 begins ----
--   begin;
--   set local lock_timeout = '2s';
--   do $undo$
--   declare
--     c_sig constant text := 'preview_customer_merge(uuid,uuid)';
--     c_before constant text := 'f66c9d63369ef3b831ca74906a99b587';
--     c_after constant text := 'b98004c9a2522d7e564d34f10ca4e574';
--     -- this file's md5 as applied (its history row's): fill in before running
--     c_m constant text := '<M>';
--     v_def text; v_path text := current_setting('search_path'); n int;
--   begin
--     perform set_config('search_path', 'public', true);
--     if to_regprocedure('public.' || c_sig) is null
--        or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) is distinct from c_after then
--       raise exception 'UNDO 486: public.% is not 486''s version; nothing changed', c_sig; end if;
--     -- 486's block out again: production's text of 2 Nov 2026 (318's).
--     v_def := replace(pg_get_functiondef(to_regprocedure('public.' || c_sig)), E'\n\n' ||
--   $b486$  -- 486 (the Owner, 2 Nov 2026): a merge decides that two records are one
--     -- person, not whose login it is. It moves the duplicate's portal login,
--     -- affiliate record and the /r/ marks naming it as referrer onto the record
--     -- kept, whose email a form may have typed while it was an ordinary record;
--     -- a login that then verifies that inbox is proven (484's verified_email).
--     -- So the duplicate may not be the record that holds them while the record
--     -- to keep has neither a portal login nor an affiliate record (any status):
--     -- keep the affiliate's record and merge the other one into it. Not refused:
--     -- the merge that 437's Link to this customer runs (link_affiliate_signup
--     -- calls merge_customer_records, which calls this), a staff decision about
--     -- whose login it is, which 484 counts as proof; it is read from the call
--     -- stack, which a client cannot set (a look-alike function made by a role
--     -- that can create functions can: NOT COVERED). The marks are read only
--     -- while their table is there (484's UNDO level 2 drops it).
--     declare
--       v_login boolean := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_merge);
--       v_aff boolean := exists (select 1 from public.customer_affiliates f where f.customer_id = p_merge);
--       v_marks bigint := 0;
--       v_ctx text;
--       v_held text[];
--     begin
--       if to_regclass('public.referral_phone_notices') is not null then
--         execute 'select count(*) from public.referral_phone_notices where referrer_customer_id = $1'
--           into v_marks using p_merge;
--       end if;
--       get diagnostics v_ctx = pg_context;
--       if (v_login or v_aff or v_marks > 0)
--          and not exists (select 1 from public.affiliate_accounts a where a.customer_id = p_keep)
--          and not exists (select 1 from public.customer_affiliates f where f.customer_id = p_keep)
--          and not coalesce(split_part(split_part(v_ctx, chr(10), 2), ' line ', 1)
--                             in ('PL/pgSQL function merge_customer_records(uuid,uuid,text,uuid)',
--                                 'PL/pgSQL function public.merge_customer_records(uuid,uuid,text,uuid)')
--                           and split_part(split_part(v_ctx, chr(10), 3), ' line ', 1)
--                             in ('PL/pgSQL function link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
--                                 'PL/pgSQL function public.link_affiliate_signup(uuid,uuid,text,uuid,boolean)'), false) then
--         -- What the duplicate holds, joined as "a", "a and b" or "a, b and c".
--         v_held := array_remove(array[
--             case when v_login then 'the portal login' end,
--             case when v_aff then 'the affiliate record' end,
--             case when v_marks > 0 then v_marks || ' /r/ phone-notice mark(s) naming it as referrer' end], null);
--         v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','duplicate_has_affiliate_account',
--           'detail','The duplicate holds '
--             || case when cardinality(v_held) = 1 then v_held[1]
--                     else array_to_string(v_held[1:cardinality(v_held) - 1], ', ') || ' and ' || v_held[cardinality(v_held)] end
--             || '; the record to keep has neither a portal login nor an affiliate record. A merge decides that two records are one person, not whose login it is: keep the affiliate''s record and merge the other one into it.'));
--       end if;
--     end;$b486$, '');
--     if md5(v_def) <> c_before then
--       raise exception 'UNDO 486: the rebuilt public.% is not production''s of 2 Nov 2026 (md5 %); nothing changed', c_sig, md5(v_def); end if;
--     execute v_def;
--     if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_before then
--       raise exception 'UNDO 486: public.% did not go back to its version before 486', c_sig; end if;
--     -- Every 486 history row holding this file's text.
--     delete from supabase_migrations.schema_migrations
--      where name = '486_merge_guard_keeps_the_affiliate_record' and md5(array_to_string(statements, '')) = c_m;
--     get diagnostics n = row_count;
--     if n < 1 then raise exception 'UNDO 486: no 486 history row holds the text with md5 %; nothing changed', c_m; end if;
--     raise notice 'UNDO 486: public.% is back to its version before 486; % history row(s) deleted', c_sig, n;
--     perform set_config('search_path', v_path, true);
--   end $undo$;
--   commit;
--   ---- UNDO 486 ends ----
--
-- Test: scripts/customer-merge/tests/merge-guard-486.sql (begin ... rollback;
-- it installs this file twice where it is not in, or with -v skip_install=1
-- where it is). Every suite that merges or pins these functions was run on
-- copies of production with and without this file: the same results but for
-- the five DEPLOY ORDER 3 names (437's Link suites included).

set lock_timeout = '2s';

do $mig$
declare
  -- ── The one function this changes: production's (BEFORE, 2 Nov 2026) -> this file's (AFTER) ──
  c_sig constant text := 'preview_customer_merge(uuid,uuid)';
  c_before constant text := 'f66c9d63369ef3b831ca74906a99b587';
  c_after constant text := 'b98004c9a2522d7e564d34f10ca4e574';
  -- Its grants, kept (compared as a set, sorted): the owner's and the service role's; no client role.
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- Relied on, not changed: the merge runs the preview first and refuses on any blocking issue (the self-test calls
  -- it); 437's Link to this customer runs the merge (the call stack names both); the Owner-or-Manager check.
  c_dep_sig constant text[] := array['merge_customer_records(uuid,uuid,text,uuid)', 'link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
                                     'is_owner_or_manager()'];
  c_dep_md5 constant text[] := array['ba05c2b1fb4c0e14d369c01d06a635b0', '198780b31301695db55c4a39ba9618f8', 'a98e50f1b6d3fa1e6c62cf52a8073cc8'];
  c_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.preview_customer_merge(p_keep uuid, p_merge uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.customers%rowtype; m public.customers%rowtype;
        v_counts jsonb := '{}'::jsonb; v_blocks jsonb := '[]'::jsonb; n bigint;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can review a customer merge' using errcode='42501'; end if;
  if p_keep = p_merge then raise exception 'Those are the same record'; end if;
  select * into k from public.customers where id = p_keep;
  if not found then raise exception 'The record to keep was not found'; end if;
  select * into m from public.customers where id = p_merge;
  if not found then raise exception 'The duplicate record was not found'; end if;

  -- What the duplicate actually holds.
  select jsonb_build_object(
    'invoices',        (select count(*) from public.invoices where customer_id = p_merge and deleted_at is null),
    'credit_lots',     (select count(*) from public.customer_credit_lots where customer_id = p_merge),
    'credit_remaining',(select coalesce(sum(remaining_amount),0) from public.customer_credit_lots
                         where customer_id = p_merge and status = 'active'),
    'vouchers',        (select coalesce(sum(quantity),0) from public.customer_reward_vouchers
                         where customer_id = p_merge and status = 'held'),
    'therapy_units',   (select count(*) from public.purchased_therapy_entitlements where customer_id = p_merge),
    'entitlements',    (select count(*) from public.therapy_entitlements where customer_id = p_merge),
    'sessions',        (select count(*) from public.customer_therapy_sessions where customer_id = p_merge),
    'commissions_as_buyer',   (select count(*) from public.commissions where buyer_customer_id = p_merge),
    'commissions_as_referrer',(select count(*) from public.commissions where referrer_customer_id = p_merge),
    'referred_customers',     (select count(*) from public.customers where referred_by = p_merge and deleted_at is null),
    'surveys',         (select count(*) from public.health_surveys where customer_id = p_merge))
  into v_counts;

  -- Things a script must not decide.
  if m.deleted_at is not null then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','duplicate_already_deleted',
      'detail','The duplicate is already deleted; nothing would move.')); end if;
  if k.deleted_at is not null then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','keeper_deleted',
      'detail','The record to keep is deleted. Restore it first.')); end if;

  if exists (select 1 from public.customer_affiliates where customer_id = p_keep and deleted_at is null)
     and exists (select 1 from public.customer_affiliates where customer_id = p_merge and deleted_at is null) then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','two_affiliate_records',
      'detail','Both records are affiliates. Which referral code and payout history survives is a decision about real money — resolve the affiliate records first, then merge.')); end if;

  -- A referral between the two would become a person referring themselves.
  select count(*) into n from public.commissions
   where (buyer_customer_id = p_keep and referrer_customer_id = p_merge)
      or (buyer_customer_id = p_merge and referrer_customer_id = p_keep);
  if n > 0 then
    v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','commission_between_the_two',
      'detail', n || ' commission row(s) have one of these records as buyer and the other as referrer. Merging would make the person their own referrer. Review those rows first.')); end if;

  -- 486 (the Owner, 2 Nov 2026): a merge decides that two records are one
  -- person, not whose login it is. It moves the duplicate's portal login,
  -- affiliate record and the /r/ marks naming it as referrer onto the record
  -- kept, whose email a form may have typed while it was an ordinary record;
  -- a login that then verifies that inbox is proven (484's verified_email).
  -- So the duplicate may not be the record that holds them while the record
  -- to keep has neither a portal login nor an affiliate record (any status):
  -- keep the affiliate's record and merge the other one into it. Not refused:
  -- the merge that 437's Link to this customer runs (link_affiliate_signup
  -- calls merge_customer_records, which calls this), a staff decision about
  -- whose login it is, which 484 counts as proof; it is read from the call
  -- stack, which a client cannot set (a look-alike function made by a role
  -- that can create functions can: NOT COVERED). The marks are read only
  -- while their table is there (484's UNDO level 2 drops it).
  declare
    v_login boolean := exists (select 1 from public.affiliate_accounts a where a.customer_id = p_merge);
    v_aff boolean := exists (select 1 from public.customer_affiliates f where f.customer_id = p_merge);
    v_marks bigint := 0;
    v_ctx text;
    v_held text[];
  begin
    if to_regclass('public.referral_phone_notices') is not null then
      execute 'select count(*) from public.referral_phone_notices where referrer_customer_id = $1'
        into v_marks using p_merge;
    end if;
    get diagnostics v_ctx = pg_context;
    if (v_login or v_aff or v_marks > 0)
       and not exists (select 1 from public.affiliate_accounts a where a.customer_id = p_keep)
       and not exists (select 1 from public.customer_affiliates f where f.customer_id = p_keep)
       and not coalesce(split_part(split_part(v_ctx, chr(10), 2), ' line ', 1)
                          in ('PL/pgSQL function merge_customer_records(uuid,uuid,text,uuid)',
                              'PL/pgSQL function public.merge_customer_records(uuid,uuid,text,uuid)')
                        and split_part(split_part(v_ctx, chr(10), 3), ' line ', 1)
                          in ('PL/pgSQL function link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
                              'PL/pgSQL function public.link_affiliate_signup(uuid,uuid,text,uuid,boolean)'), false) then
      -- What the duplicate holds, joined as "a", "a and b" or "a, b and c".
      v_held := array_remove(array[
          case when v_login then 'the portal login' end,
          case when v_aff then 'the affiliate record' end,
          case when v_marks > 0 then v_marks || ' /r/ phone-notice mark(s) naming it as referrer' end], null);
      v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('issue','duplicate_has_affiliate_account',
        'detail','The duplicate holds '
          || case when cardinality(v_held) = 1 then v_held[1]
                  else array_to_string(v_held[1:cardinality(v_held) - 1], ', ') || ' and ' || v_held[cardinality(v_held)] end
          || '; the record to keep has neither a portal login nor an affiliate record. A merge decides that two records are one person, not whose login it is: keep the affiliate''s record and merge the other one into it.'));
    end if;
  end;

  return jsonb_build_object(
    'keep', jsonb_build_object('id',k.id,'name',k.full_name,'phone',k.phone,'email',k.email,
                               'created_at',k.created_at,'referred_by',k.referred_by),
    'merge', jsonb_build_object('id',m.id,'name',m.full_name,'phone',m.phone,'email',m.email,
                                'created_at',m.created_at,'referred_by',m.referred_by),
    'moving', v_counts,
    'wallets', jsonb_build_object(
      'keep_has',  exists(select 1 from public.customer_credit_wallets where customer_id = p_keep),
      'merge_has', exists(select 1 from public.customer_credit_wallets where customer_id = p_merge)),
    'blocking', v_blocks,
    'can_merge', jsonb_array_length(v_blocks) = 0);
end $function$
$d1$;
  -- The self-test's expected words (the detail after "The duplicate holds ...").
  c_tail constant text := '; the record to keep has neither a portal login nor an affiliate record. A merge decides that two records are one person, not whose login it is: keep the affiliate''s record and merge the other one into it.';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; v_md5 text; v_oid regprocedure; v_state text;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_ph text[]; t_owner uuid; t_uid uuid; t_srr text; t_aff uuid; t_login uuid; t_plain uuid;
  t_p jsonb; t_err text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──
  if md5(c_def) <> c_after then
    raise exception '486: the text is not the tested one (md5 %)', md5(c_def); end if;
  v_oid := to_regprocedure('public.' || c_sig);
  if v_oid is null then raise exception '486: public.% is missing', c_sig; end if;
  v_md5 := md5(pg_get_functiondef(v_oid));
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'preview_customer_merge' and p.oid <> v_oid;
  if v is not null then raise exception '486: another function takes the name of public.%: %', c_sig, v; end if;
  if (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid)
     is distinct from c_acl then
    raise exception '486: the grants of public.% are not as read on 2 Nov 2026', c_sig; end if;
  -- BEFORE (replace it) or AFTER ("already this version"); anything else is refused.
  v_state := case v_md5 when c_before then 'before' when c_after then 'after' end;
  if v_state is null then
    raise exception '486: public.% (md5 %) is neither production''s version of 2 Nov 2026 nor this file''s. Re-read it and re-test before applying.',
      c_sig, v_md5; end if;
  for i in 1 .. 3 loop
    if to_regprocedure('public.' || c_dep_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_dep_sig[i]))) is distinct from c_dep_md5[i] then
      raise exception '486: public.% is missing or not as read on 2 Nov 2026 (md5 %). Re-read it and re-test before applying.',
        c_dep_sig[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_dep_sig[i]))); end if;
  end loop;
  -- The columns the new lines read (the marks' only while their table is there).
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('affiliate_accounts', 'customer_id', 'uuid'), ('customer_affiliates', 'customer_id', 'uuid'),
                 ('referral_phone_notices', 'referrer_customer_id', 'uuid')) x(t, c, ty)
   where (x.t <> 'referral_phone_notices' or to_regclass('public.referral_phone_notices') is not null)
     and not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '486: these columns are missing or not as read on 2 Nov 2026: %', v; end if;

  -- ── Change ──
  if v_state = 'before' then
    execute c_def;
    raise notice '486: public.% replaced (the merge preview refuses to retire the record that holds the portal login or the affiliate record into one that has neither)',
      c_sig;
  else
    raise notice '486: public.% is already this version; left alone', c_sig;
  end if;

  -- ── Afterwards ──
  v_oid := to_regprocedure('public.' || c_sig);
  if v_oid is null or md5(pg_get_functiondef(v_oid)) <> c_after then
    raise exception '486: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = v_oid)
     is distinct from c_acl then
    raise exception '486: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ──
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- Three fictional phones in a row (+61 2 5550 nnnn) that no customer, in use or deleted, holds: range scans of
    -- the partial phone indexes, as 482's and 485's.
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '486: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 2) n);
    -- A made-up active Owner, signed in for this block: the preview and the merge are an Owner's or a Manager's.
    insert into auth.users (id, email) values (gen_random_uuid(), '486chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '486 Check Owner', '486chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    -- Three records: an affiliate's (an affiliate record, no login), a portal login's (no affiliate record) and a
    -- plain one.
    insert into public.customers (full_name, phone) values ('486 Check Affiliate', t_ph[1]) returning id into t_aff;
    insert into public.customer_affiliates (customer_id) values (t_aff);
    insert into public.customers (full_name, phone) values ('486 Check Login', t_ph[2]) returning id into t_login;
    insert into auth.users (id, email) values (gen_random_uuid(), '486chk-login-' || t_sfx || '@example.invalid') returning id into t_uid;
    -- The portal account with triggers off for this statement only (its trigger would queue a welcome WhatsApp and
    -- take a number from the outbox's sequence, which an undone block does not give back).
    t_srr := current_setting('session_replication_role');
    set local session_replication_role = replica;
    insert into public.affiliate_accounts (auth_user_id, customer_id) values (t_uid, t_login);
    execute format('set local session_replication_role = %L', t_srr);
    insert into public.customers (full_name, phone) values ('486 Check Plain', t_ph[3]) returning id into t_plain;

    -- Keeping the plain record and retiring the affiliate's, or the portal login's: the preview refuses, and so does
    -- the merge, before it changes anything.
    t_p := public.preview_customer_merge(t_plain, t_aff);
    if (t_p ->> 'can_merge')::boolean is distinct from false
       or t_p -> 'blocking' is distinct from jsonb_build_array(jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                                                                                  'detail', 'The duplicate holds the affiliate record' || c_tail)) then
      raise exception '486: the self-test''s preview (keep the plain record, retire the affiliate''s) answered %', t_p -> 'blocking'; end if;
    t_p := public.preview_customer_merge(t_plain, t_login);
    if (t_p ->> 'can_merge')::boolean is distinct from false
       or t_p -> 'blocking' is distinct from jsonb_build_array(jsonb_build_object('issue', 'duplicate_has_affiliate_account',
                                                                                  'detail', 'The duplicate holds the portal login' || c_tail)) then
      raise exception '486: the self-test''s preview (keep the plain record, retire the login''s) answered %', t_p -> 'blocking'; end if;
    t_err := null;
    begin
      perform public.merge_customer_records(t_plain, t_aff, '486 check', gen_random_uuid());
    exception when others then t_err := sqlerrm;
    end;
    if t_err is distinct from 'This merge needs review first: The duplicate holds the affiliate record' || c_tail then
      raise exception '486: the self-test''s merge (keep the plain record, retire the affiliate''s) answered %', coalesce(t_err, 'nothing: it merged'); end if;
    t_err := null;
    begin
      perform public.merge_customer_records(t_plain, t_login, '486 check', gen_random_uuid());
    exception when others then t_err := sqlerrm;
    end;
    if t_err is distinct from 'This merge needs review first: The duplicate holds the portal login' || c_tail then
      raise exception '486: the self-test''s merge (keep the plain record, retire the login''s) answered %', coalesce(t_err, 'nothing: it merged'); end if;
    if (select count(*) from public.customers c where c.id in (t_aff, t_login, t_plain) and c.deleted_at is null) <> 3
       or not exists (select 1 from public.customer_affiliates f where f.customer_id = t_aff)
       or not exists (select 1 from public.affiliate_accounts a where a.customer_id = t_login and a.auth_user_id = t_uid) then
      raise exception '486: the self-test''s refused merges changed something'; end if;
    -- The other way round: keeping the affiliate's record, or the login's, and retiring the plain one: no new issue.
    t_p := public.preview_customer_merge(t_aff, t_plain);
    if (t_p ->> 'can_merge')::boolean is distinct from true or t_p -> 'blocking' is distinct from '[]'::jsonb then
      raise exception '486: the self-test''s preview (keep the affiliate''s record, retire the plain one) answered %', t_p -> 'blocking'; end if;
    t_p := public.preview_customer_merge(t_login, t_plain);
    if (t_p ->> 'can_merge')::boolean is distinct from true or t_p -> 'blocking' is distinct from '[]'::jsonb then
      raise exception '486: the self-test''s preview (keep the login''s record, retire the plain one) answered %', t_p -> 'blocking'; end if;

    raise exception using errcode = 'P0486', message = '486: self-test done, undone';
  exception when sqlstate 'P0486' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
end $mig$;
