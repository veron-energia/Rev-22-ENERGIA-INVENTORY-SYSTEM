-- UNDO of 549 (with the user's go-ahead): the referral page can no longer ask whether somebody
-- already registered has an upcoming booking.
--
-- It drops public.referral_booking_lookup(text,text,text) and then the table
-- public.referral_booking_lookups, with every lookup recorded in it (they are gone for good; the
-- limits start from nothing if 549 is applied again). Nothing else: 529's salt and events, the
-- cal.com bookings and every other function are as they are.
--
-- It refuses, with nothing changed, unless the function is exactly 549's (md5
-- 8385a3401954768048e293fb0fac7dbf, its grants and settings as 549 made them) and the table is as
-- 549 made it (its columns, constraints, indexes, grants, row level security on and no policy, and
-- nothing else depending on it); a second undo refuses (549 is not in). Run it BEFORE any older
-- UNDO. Afterwards the function fingerprint is the one before 549 (production after 547:
-- 73d175b2e8d324bb524127497fe3d02b/1470, if nothing else changed since). Pages: the page falls back
-- to the booking button when the function is not found; revert the page commit too if wanted. One
-- transaction; waits at most 5 seconds for a lock. The 549 row in
-- supabase_migrations.schema_migrations stays; with the user's OK, remove that one row or record
-- this UNDO beside it.
do $undo$
declare
  c_sig constant text := 'referral_booking_lookup(text,text,text)';
  c_md5 constant text := '8385a3401954768048e293fb0fac7dbf';
  c_acl constant text := 'anon=X/postgres,authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  c_cols constant text := 'id bigint NO,created_at timestamp with time zone NO,sender_key text YES,phone_key text YES,outcome text NO';
  c_con constant text := 'referral_booking_lookups_outcome_check CHECK ((outcome = ANY (ARRAY[''none''::text, ''needs_email''::text, ''booked''::text, ''try_later''::text, ''invalid''::text]))),referral_booking_lookups_pkey PRIMARY KEY (id),referral_booking_lookups_sender_key_is_a_hash CHECK (((sender_key IS NULL) OR (sender_key ~ ''^[0-9a-f]{64}$''::text)))';
  c_idx constant text := 'CREATE INDEX referral_booking_lookups_phone_time ON public.referral_booking_lookups USING btree (phone_key, created_at),CREATE INDEX referral_booking_lookups_sender_time ON public.referral_booking_lookups USING btree (sender_key, created_at) WHERE (sender_key IS NOT NULL),CREATE UNIQUE INDEX referral_booking_lookups_pkey ON public.referral_booking_lookups USING btree (id)';
  c_tab_acl constant text := '{postgres=arwdDxtm/postgres}';
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_fn regprocedure; v_tab regclass;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);
  v_fn := to_regprocedure('public.' || c_sig);
  v_tab := to_regclass('public.referral_booking_lookups');
  if v_fn is null and v_tab is null
     and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'referral_booking_lookup') then
    raise exception 'undo 549: 549 is not in on this database (no referral_booking_lookup, no referral_booking_lookups); nothing was changed.'; end if;
  if v_fn is null or v_tab is null then
    raise exception 'undo 549: only part of 549 is there (function %, table %); re-read them first. Nothing was changed.',
      coalesce(v_fn::text, 'missing'), coalesce(v_tab::text, 'missing'); end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'referral_booking_lookup') <> 1 then
    raise exception 'undo 549: another function named referral_booking_lookup is there; re-read it first. Nothing was changed.'; end if;
  if md5(pg_get_functiondef(v_fn)) <> c_md5
     or (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x where p.oid = v_fn) is distinct from c_acl
     or (select p.proconfig from pg_proc p where p.oid = v_fn) is distinct from array['search_path=public, pg_temp']
     or not (select p.prosecdef from pg_proc p where p.oid = v_fn) then
    raise exception 'undo 549: public.% is not 549''s (md5 %); a later change must be undone first. Nothing was changed.', c_sig, md5(pg_get_functiondef(v_fn)); end if;
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'referral_booking_lookups') is distinct from c_cols
     or (select string_agg(conname || ' ' || pg_get_constraintdef(oid), ',' order by conname) from pg_constraint where conrelid = v_tab) is distinct from c_con
     or (select string_agg(pg_get_indexdef(indexrelid), ',' order by pg_get_indexdef(indexrelid)) from pg_index where indrelid = v_tab) is distinct from c_idx
     or (select c.relacl::text from pg_class c where c.oid = v_tab) is distinct from c_tab_acl
     or not (select c.relrowsecurity from pg_class c where c.oid = v_tab)
     or exists (select 1 from pg_policy p where p.polrelid = v_tab)
     or exists (select 1 from pg_trigger t where t.tgrelid = v_tab)
     or exists (select 1 from pg_constraint k where k.confrelid = v_tab)
     or exists (select 1 from pg_depend d join pg_rewrite w on w.oid = d.objid where d.refobjid = v_tab and w.ev_class <> v_tab) then
    raise exception 'undo 549: public.referral_booking_lookups is not as 549 made it (or something depends on it); re-read it first. Nothing was changed.'; end if;

  execute format('drop function public.%s', c_sig);
  drop table public.referral_booking_lookups;

  if to_regclass('public.referral_booking_lookups') is not null or to_regclass('public.referral_booking_lookups_id_seq') is not null
     or exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'referral_booking_lookup') then
    raise exception 'undo 549: something of 549 is still there after dropping it'; end if;
  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
