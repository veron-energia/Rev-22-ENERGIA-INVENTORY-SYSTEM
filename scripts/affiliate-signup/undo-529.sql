-- UNDO of 529 (with the user's go-ahead). It puts affiliate_referral_signup back to its text
-- before 529 (md5 2942e3d4…), drops referral_signup_events.sender_key (with its check
-- and its index) and the index for all links, and drops public.referral_sender_salt (the salt is
-- gone for good: a later 529 makes a new one, and keys recorded under the old one match no one): the referral page has no limit per sender and
-- none across all links again, a number on file is answered "already registered" before the
-- phone's limit again (442's "never limited"), and names and emails are taken as typed (the
-- security audit's M3 open again). The function's grants stay as they are; the table's row
-- level security, policy and grants are not touched. The event rows written while 529 was in
-- stay, without their sender, with their outcomes ('sender_limit', 'invalid', 'phone_limit',
-- 'all_links_limit'); the old function's phone limit counts a 'phone_limit' row from the last
-- 10 minutes as a try.
--
-- The page needs no undo first: it checks the same name and email rules before calling
-- (src/lib/referral/signupInput.mjs), which only stops what 529 would refuse; after this undo
-- it keeps refusing those names and emails on the page alone.
--
-- It refuses, with nothing changed, unless affiliate_referral_signup is exactly 529's version
-- and the two tables are as 529 left them (so a later version is never overwritten). One transaction,
-- all or nothing; it waits at most 5 seconds for a lock. The 529 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row (found
-- by its name, 529_the_referral_page_limits_each_sender_and_all_links) or record this UNDO
-- beside it.
--
-- The patch texts below are 529's, the other way round: each 529 text is found exactly once
-- and put back as it was.
do $undo$
declare
  c_sig constant text[] := array[
    'affiliate_referral_signup(text,text,text,text,text,text)'];
  c_529 constant text[] := array[
    '00d528c6f4cc9240b2cf2f82ea2bd487'];
  c_before_529 constant text[] := array[
    '2942e3d4d0e8c76600c3e0ad5e15cc2b'];
  c_cols_before constant text :=
    'id uuid NO,referral_code text YES,referrer_customer_id uuid YES,new_customer_id uuid YES,normalized_phone text YES,outcome text NO,created_at timestamp with time zone NO';
  c_cols_529 constant text := c_cols_before || ',sender_key text YES';
  c_idx_before constant text[] := array[
    'CREATE INDEX idx_referral_events_code_time ON public.referral_signup_events USING btree (referral_code, created_at)',
    'CREATE INDEX idx_referral_events_phone_time ON public.referral_signup_events USING btree (normalized_phone, created_at)',
    'CREATE UNIQUE INDEX referral_signup_events_pkey ON public.referral_signup_events USING btree (id)'];
  c_idx_529 constant text[] := array[
    'CREATE INDEX idx_referral_events_all_links_time ON public.referral_signup_events USING btree (created_at) WHERE (outcome = ANY (ARRAY[''created''::text, ''phone_shared''::text, ''self''::text]))',
    'CREATE INDEX idx_referral_events_code_time ON public.referral_signup_events USING btree (referral_code, created_at)',
    'CREATE INDEX idx_referral_events_phone_time ON public.referral_signup_events USING btree (normalized_phone, created_at)',
    'CREATE INDEX idx_referral_events_sender_time ON public.referral_signup_events USING btree (sender_key, created_at) WHERE (sender_key IS NOT NULL)',
    'CREATE UNIQUE INDEX referral_signup_events_pkey ON public.referral_signup_events USING btree (id)'];
  c_con_before constant text[] := array[
    'referral_signup_events_pkey PRIMARY KEY (id)'];
  c_con_529 constant text[] := array[
    'referral_signup_events_pkey PRIMARY KEY (id)',
    'referral_signup_events_sender_key_is_a_hash CHECK (((sender_key IS NULL) OR (sender_key ~ ''^[0-9a-f]{64}$''::text)))'];
  c_fn constant int[] := array[1, 1, 1, 1, 1, 1, 1];
  c_anchor constant text[] := array[
-- 1 the start: the sender, the sender's limit, the honeypot, the input, the link, the phone's limit, several records
$a$  v_by_email boolean := false;  -- 469: those on file were found by the phone and the email
begin
  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, outcome) values (btrim(p_code), 'honeypot');
    return jsonb_build_object('ok', true, 'outcome', 'registered');
  end if;

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_norm  := public.normalize_customer_phone(p_phone);
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  if v_name = '' then raise exception 'Please enter your name'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm,0));


  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, outcome) values (btrim(p_code), v_norm, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  perform public.require_resolved_customer_identity(v_norm,v_name);
  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  if cardinality(v_matches) > 1 then raise exception 'AMBIGUOUS_CUSTOMER_MATCH'; end if;
$a$,
-- 2 the 442 comment on a try as herself
$a$  -- hers, up to where a customer would be made: on details already on file,
  -- "already registered", never limited (below: an event 'self_known' in
  -- place of 'duplicate'); else the phone's 3 customers, the phone's limit
  -- and the link's limit, as for a new customer; then, in place of the
$a$,
-- 3 details already on file: the comment and the event
$a$  -- 442: a try as herself on details already on file (her record, or
  -- someone on file typed with her login's name, phone or email) is
  -- answered as anyone on file is, and never limited either; it is recorded
  -- as 'self_known' in place of 'duplicate' (the phone's limit counts both,
  -- the link's neither), with the Audit Log entry.
  if cardinality(v_matches) >= 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, case when cardinality(v_self) > 0 then 'self_known' else 'duplicate' end);
$a$,
-- 4 a phone 3 customers have is answered and recorded; the phone's limit is no longer here (it moved up, above)
$a$  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
    raise exception 'CUSTOMER_PHONE_LIMIT: This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.';
  end if;
  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone=v_norm and created_at > now()-interval '10 minutes';
  if v_recent >= 3 then
    return jsonb_build_object('ok',false,'message','Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.');
  end if;
  -- 425: at most 20 new customers through one link in an hour, counted by
$a$,
-- 5 the link's limit records the sender; then the limit for all links
$a$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'link_limit');
    return jsonb_build_object('ok', false, 'message',
      'This referral link has had many registrations in the last hour. Please try again later or contact Energia.');
  end if;
$a$,
-- 6 a try as herself records the sender
$a$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'self');
$a$,
-- 7 a new customer records the sender
$a$  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, outcome)
    values (btrim(p_code), v_ref_cust, v_new, v_norm, case when cardinality(v_holders) > 0 then 'phone_shared' else 'created' end);
$a$];
  c_new constant text[] := array[
-- 1 the start: the sender, the sender's limit, the honeypot, the input, the link, the phone's limit, several records
$n$  v_by_email boolean := false;  -- 469: those on file were found by the phone and the email
  -- 529: who is trying (a salted one-way hash of the sender's address, or null), what is wrong
  -- with the name or the email typed, if anything, whether the phone and name match several
  -- records, and the code as the events keep it (at most 64 characters of what was typed).
  v_ip inet; v_sender text; v_bad text; v_salt text; v_ambiguous boolean := false;
  v_code text := left(btrim(p_code), 64);
begin
  -- 529 (security audit of 17 Nov 2026, M3; the user, 19 Nov 2026: "Per sender + overall",
  -- "Yes, count every try", "Refuse odd input"): every try that is answered is recorded with
  -- its sender, and limited. First the sender's limit, 10 tries an hour whatever the answer;
  -- then the phone's, 3 tries in 10 minutes, before anything is matched, so a number on file
  -- and one that is not get the same answer from it; then, after the link's limit, at most 30
  -- new customers an hour through all links together. This replaces 442's "never limited" for
  -- tries on details already on file: they are answered "already registered" as before, but
  -- only inside the sender's and the phone's limits.
  --
  -- The sender: the address Cloudflare, in front of Supabase, puts in cf-connecting-ip (never
  -- x-forwarded-for, whose first entry the sender writes). An IPv4 address is one sender; an
  -- IPv6 address, its /64. Only a one-way hash is kept (referral_signup_events.sender_key),
  -- never the address: sha256 of a secret salt and the address, the salt made when 529 ran and
  -- kept in public.referral_sender_salt, which no API role can read (never in a file), so the
  -- hash cannot be turned back into an address by trying every one. No salt: this refuses,
  -- rather than count nobody. No such header, or one that is not a single address (a call from
  -- inside the database, a suite): null, the try is recorded without a sender, and the sender's
  -- limit does not apply.
  select s.salt into v_salt from public.referral_sender_salt s where s.id;
  if v_salt is null or v_salt !~ '^[0-9a-f]{64}$' then
    raise exception '529: the sender salt (public.referral_sender_salt) is missing, so no sender can be counted. Run 529 again.';
  end if;
  begin
    v_ip := nullif(btrim(current_setting('request.headers', true)::jsonb ->> 'cf-connecting-ip'), '')::inet;
    if family(v_ip) = 6 and v_ip <<= '::ffff:0.0.0.0/96'::inet then
      v_ip := regexp_replace(host(v_ip), '^::ffff:', '', 'i')::inet;
    end if;
    if masklen(v_ip) <> (case family(v_ip) when 4 then 32 else 128 end) then v_ip := null; end if;
  exception when others then v_ip := null;
  end;
  v_sender := case family(v_ip)
    when 4 then encode(sha256(convert_to(v_salt || '|' || host(v_ip), 'UTF8')), 'hex')
    when 6 then encode(sha256(convert_to(v_salt || '|' || host(network(set_masklen(v_ip, 64))) || '/64', 'UTF8')), 'hex')
  end;

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_norm  := public.normalize_customer_phone(p_phone);
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  -- 529: the phone's lock first (the page's call, affiliate_referral_signup_with_notice, takes
  -- it before it calls this), then the sender's, so two calls never wait for each other's
  -- locks the other way round. Two tries from one sender wait for each other, so the sender's
  -- count is exact.
  if v_norm is not null then
    perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm,0));
  end if;
  if v_sender is not null then
    perform pg_advisory_xact_lock(hashtextextended('referral-sender:' || v_sender, 0));
    -- 529: at most 10 tries an hour from one sender, whatever each was answered (the
    -- refusals of this limit itself are not counted). Past it, the refusal is recorded at most
    -- once an hour for the sender, so trying again and again adds nothing.
    if (select count(*) from public.referral_signup_events e
         where e.sender_key = v_sender and e.outcome <> 'sender_limit'
           and e.created_at > now() - interval '1 hour') >= 10 then
      if not exists (select 1 from public.referral_signup_events e
                      where e.sender_key = v_sender and e.outcome = 'sender_limit'
                        and e.created_at > now() - interval '1 hour') then
        insert into public.referral_signup_events(referral_code, sender_key, outcome)
          values (v_code, v_sender, 'sender_limit');
      end if;
      return jsonb_build_object('ok', false, 'message',
        'Too many registration attempts from this connection. Please try again in an hour, or contact Energia.');
    end if;
  end if;

  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, sender_key, outcome) values (v_code, v_sender, 'honeypot');
    return jsonb_build_object('ok', true, 'outcome', 'registered');
  end if;

  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  if v_name = '' then raise exception 'Please enter your name'; end if;
  -- 529 ("Refuse odd input"; the page checks the same before it calls,
  -- src/lib/referral/signupInput.mjs): the name (first and last together, trimmed) at most 100
  -- characters, with no web address ('://' or 'www.'), no '<' or '>' and no control
  -- characters; the email may be left out, but one typed is at most 254 characters and looks
  -- like name@domain.tld. Refused with a message that says what to fix, and recorded (the
  -- sender's limit counts it).
  v_bad := case
    when char_length(v_name) > 100 then
      'Please shorten your name: your first and last name together can be at most 100 characters.'
    when strpos(v_name, '://') > 0 or strpos(lower(v_name), 'www.') > 0 then
      'Please enter just your name, without a web address.'
    when v_name ~ '[<>\u0001-\u001f\u007f-\u009f]' then
      'Please enter your name without the characters < and > or other special characters.'
    when char_length(btrim(p_email)) > 254 then
      'Please enter an email address of at most 254 characters, or leave the email blank.'
    when v_email !~ '^[^@ <>\u0001-\u001f\u007f-\u009f]+@[^@ .<>\u0001-\u001f\u007f-\u009f]+(\.[^@ .<>\u0001-\u001f\u007f-\u009f]+)*\.[^@ .<>\u0001-\u001f\u007f-\u009f]{2,}$' then
      'Please check your email address: it should look like name@example.com. Or leave the email blank.'
  end;
  if v_bad is not null then
    insert into public.referral_signup_events(referral_code, sender_key, outcome) values (v_code, v_sender, 'invalid');
    return jsonb_build_object('ok', false, 'message', v_bad);
  end if;

  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, sender_key, outcome) values (v_code, v_norm, v_sender, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  -- 529 ("Yes, count every try"): the phone's limit, 3 tries on the phone in 10 minutes, now
  -- before anything is matched (it came after "already registered" and the phone's 3
  -- customers): a number on file and one that is not get the same answer here. Its own
  -- refusals ('phone_limit') are recorded, for the sender's count and for staff, but not
  -- counted here, so trying again does not keep the number shut.
  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone=v_norm and created_at > now()-interval '10 minutes' and outcome <> 'phone_limit';
  if v_recent >= 3 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'phone_limit');
    return jsonb_build_object('ok',false,'message','Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.');
  end if;

  -- 529 ("Yes, count every try"): a phone and name that match several records
  -- (AMBIGUOUS_CUSTOMER_MATCH, from require_resolved_customer_identity or from the match itself)
  -- is answered, in the words the page showed for that error, and recorded ('ambiguous', with
  -- the phone and the sender), so both limits count it. It was raised, which rolled its event
  -- back with it, so such tries were never counted. Any other error is raised as before.
  begin
    perform public.require_resolved_customer_identity(v_norm,v_name);
  exception when raise_exception then
    if sqlerrm is distinct from 'AMBIGUOUS_CUSTOMER_MATCH' then raise; end if;
    v_ambiguous := true;
  end;
  if not v_ambiguous then
    v_matches := public.customer_phone_name_matches(v_norm,v_name);
    v_ambiguous := cardinality(v_matches) > 1;
  end if;
  if v_ambiguous then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'ambiguous');
    return jsonb_build_object('ok', false, 'message',
      'More than one customer has this phone number and name. Ask staff to verify and select the correct customer record.');
  end if;
$n$,
-- 2 the 442 comment on a try as herself
$n$  -- hers, up to where a customer would be made: on details already on file,
  -- "already registered" (below: an event 'self_known' in place of
  -- 'duplicate'; 529 replaced 442's "never limited" here: the sender's and
  -- the phone's limits, above, come first); else the phone's 3 customers,
  -- the link's limit and 529's limit for all links, as for a new customer;
  -- then, in place of the
$n$,
-- 3 details already on file: the comment and the event
$n$  -- 442: a try as herself on details already on file (her record, or
  -- someone on file typed with her login's name, phone or email) is
  -- answered as anyone on file is; it is recorded as 'self_known' in place
  -- of 'duplicate' (the phone's limit counts both, the link's neither), with
  -- the Audit Log entry. 529 (the user, 19 Nov 2026, "Yes, count every
  -- try"): neither is "never limited" any more: the sender's and the
  -- phone's limits (above) come before this answer, and both count it.
  if cardinality(v_matches) >= 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, case when cardinality(v_self) > 0 then 'self_known' else 'duplicate' end);
$n$,
-- 4 a phone 3 customers have is answered and recorded; the phone's limit is no longer here (it moved up, above)
$n$  -- 529 ("Yes, count every try"): a phone 3 customers have already (CUSTOMER_PHONE_LIMIT) is
  -- answered, in the words the page showed for that error, and recorded ('phone_full', with the
  -- phone and the sender), so both limits count it. It was raised and so never counted: once a
  -- number was full, names could be tried on it without end (a wrong name gets this answer, the
  -- right one "already registered").
  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'phone_full');
    return jsonb_build_object('ok', false, 'message',
      'This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.');
  end if;
  -- 529: the phone's limit is above, before anything is matched.
  -- 425: at most 20 new customers through one link in an hour, counted by
$n$,
-- 5 the link's limit records the sender; then the limit for all links
$n$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'link_limit');
    return jsonb_build_object('ok', false, 'message',
      'This referral link has had many registrations in the last hour. Please try again later or contact Energia.');
  end if;
  -- 529 ("Per sender + overall"): at most 30 new customers an hour through all links together
  -- (created, phone_shared and self, as the link's limit counts them; the event website's
  -- referrals are counted too, as there). Past it: refused, and recorded ('all_links_limit').
  -- One lock for all links, taken last (after the phone's and the link's), so two sign-ups
  -- cannot both take the 30th place.
  perform pg_advisory_xact_lock(hashtextextended('referral-all-links', 0));
  if (select count(*) from public.referral_signup_events e
       where e.outcome in ('created', 'phone_shared', 'self')
         and e.created_at > now() - interval '1 hour') >= 30 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'all_links_limit');
    return jsonb_build_object('ok', false, 'message',
      'Registrations are very busy right now. Please try again in an hour, or contact Energia.');
  end if;
$n$,
-- 6 a try as herself records the sender
$n$    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, sender_key, outcome)
      values (v_code, v_ref_cust, v_norm, v_sender, 'self');
$n$,
-- 7 a new customer records the sender
$n$  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, sender_key, outcome)
    values (v_code, v_ref_cust, v_new, v_norm, v_sender, case when cardinality(v_holders) > 0 then 'phone_shared' else 'created' end);
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception 'UNDO 529: public.% is missing', c_sig[i]; end if;
    v_def[i] := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(v_def[i]) <> c_529[i] then
      raise exception 'UNDO 529: public.% is not 529''s version (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
  end loop;
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'referral_signup_events') is distinct from c_cols_529
     or (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
           from pg_index x where x.indrelid = 'public.referral_signup_events'::regclass) is distinct from c_idx_529
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.referral_signup_events'::regclass) is distinct from c_con_529 then
    raise exception 'UNDO 529: public.referral_signup_events is not as 529 left it. Nothing changed.'; end if;
  if to_regclass('public.referral_sender_salt') is null
     or (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'referral_sender_salt')
        is distinct from 'id boolean NO,salt text NO,created_at timestamp with time zone NO' then
    raise exception 'UNDO 529: public.referral_sender_salt is missing or not as 529 made it. Nothing changed.'; end if;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 529: patch % does not find 529''s text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before_529[i] then
      raise exception 'UNDO 529: the text put back for public.% is not the one before 529 (md5 %). Nothing changed.', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Put the function back (it no longer reads sender_key), then drop the index for all links
  --    and the column (its check and its index go with it), and the salt table
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  drop index public.idx_referral_events_all_links_time;
  alter table public.referral_signup_events drop column sender_key;
  drop table public.referral_sender_salt;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_before_529[i] then
      raise exception 'UNDO 529: public.% was put back with an md5 other than the one before 529', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception 'UNDO 529: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'referral_signup_events') is distinct from c_cols_before
     or (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
           from pg_index x where x.indrelid = 'public.referral_signup_events'::regclass) is distinct from c_idx_before
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.referral_signup_events'::regclass) is distinct from c_con_before then
    raise exception 'UNDO 529: public.referral_signup_events is not as before 529 after the undo'; end if;
  if to_regclass('public.referral_sender_salt') is not null then
    raise exception 'UNDO 529: public.referral_sender_salt is still there'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
