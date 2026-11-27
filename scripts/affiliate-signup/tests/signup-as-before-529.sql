-- For the suites written before 529 that run their own migration files again, on a database where 529 is in.
--
-- 529 (19 Nov 2026; security audit of 17 Nov 2026, M3) patches affiliate_referral_signup (the referral page's
-- sign-up: the limit per sender and for all links, the phone's limit before "already registered", odd names and
-- emails refused). A migration file written before it that pins that function as relied on (484, as its G1 and its
-- runs again in G6-G8) refuses to run where 529 is in. So, for their run, which is rolled back, the function is put
-- back to its text before 529 (469's, md5 2942e3d4...), as scripts/affiliate-signup/undo-529.sql does (each of
-- 529's patches, reversed). The column referral_signup_events.sender_key, its indexes and the table
-- referral_sender_salt stay (the text before 529 does not name them). Anywhere else (529 not in) this changes nothing. What 529 changes is checked by
-- scripts/affiliate-signup/tests/referral-limits-529.sql.
--
-- Included by scripts/referrals/tests/affiliate-network-phone-484.sql (before its section G; the sign-ups before
-- that run on whatever the database has). Never run it on its own against a real database: it is only for a
-- rolled-back test.
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first, as this file pins
-- md5s of functions it changes (only their search path); this run only, rolled back with the rest.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
do $as529$
declare
  v_path text := current_setting('search_path');
  c_sig constant text := 'affiliate_referral_signup(text,text,text,text,text,text)';
  c_529 constant text := '00d528c6f4cc9240b2cf2f82ea2bd487';
  c_before constant text := '2942e3d4d0e8c76600c3e0ad5e15cc2b';
  -- 529's c_new (found now) and c_anchor (put back), as in supabase/529_the_referral_page_limits_each_sender_and_all_links.sql
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
  v_def text; i int;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.' || c_sig) is null then raise exception 'as before 529: public.% is missing', c_sig; end if;
  v_def := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(v_def) = c_529 then
    for i in 1 .. cardinality(c_new) loop
      if (length(v_def) - length(replace(v_def, c_new[i], ''))) / length(c_new[i]) <> 1 then
        raise exception 'as before 529: patch % does not find 529''s text exactly once', i; end if;
      v_def := replace(v_def, c_new[i], c_anchor[i]);
    end loop;
    if md5(v_def) <> c_before then raise exception 'as before 529: the text put back is not the one before 529 (md5 %)', md5(v_def); end if;
    execute v_def;
    raise notice 'as before 529: public.% is put back to its text before 529 for this run', c_sig;
  elsif position('-- 529 (security audit' in v_def) > 0 then
    raise exception 'as before 529: public.% has 529''s marker but not its AFTER md5 (%); update this file', c_sig, md5(v_def);
  end if;
  perform set_config('search_path', v_path, true);
end $as529$;
