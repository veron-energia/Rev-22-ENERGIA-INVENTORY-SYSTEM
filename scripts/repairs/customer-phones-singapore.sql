-- CUSTOMERS-17 repair: give +65 to the eight-digit numbers that are clearly
-- Singapore mobiles (the Owner, 9 Oct 2026, Q8 A, part d).
--
-- On 9 Oct 2026, 72 live customers still had a bare eight-digit number. The
-- phone review of July (customer_phone_migration_map) marked 26 of them
-- 'ready': valid only as Singapore numbers, so normalised to +65 and the same
-- eight digits. They were never converted. The other 46 could be Singapore or
-- Malaysia and wait for the Owner's answers, with the 80 '+' numbers of the
-- wrong length and the 1 six-digit number (the review list of 127,
-- scripts/repairs/customer-phone-review-list.sql). This converts the 26 only.
--
-- What it does, in one statement (atomic):
--   * refuses unless the numbers to convert are exactly the 26 read that day
--     (or none, when it has already run): live customers, 'ready', not
--     applied, the number unchanged since the review, eight digits, and
--     normalised to +65 and those digits;
--   * converts them through apply_customer_phone_review(jsonb), as the
--     approving Owner: the review's own checks (stale number, valid number,
--     at most three customers on a number), the old number into the phone
--     history with the reason, and the review map marked applied;
--   * writes one audit row per customer, 'customer_phone_reviewed', with the
--     old and the new number;
--   * prints counts only.
--
-- Run it once, after 418, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres), with c_owner set below to the
-- profile id of the Owner who approved it. A second run changes nothing.
-- Expected on production (9 Oct 2026): 26 converted.
--
-- The 127 other numbers: when the Owner has answered, build the same rows
-- (customer_id, original_phone, normalized_phone, reason) from the answers
-- and pass them to apply_customer_phone_review the same way.
--
-- To check afterwards (counts only):
--   select count(*) from public.customers c join public.customer_phone_migration_map m on m.customer_id = c.id
--    where c.deleted_at is null and c.phone ~ '^[0-9]{8}$' and m.inspection->>'status' = 'ready';   -- 0

do $repair$
declare
  c_owner constant uuid := null;   -- the approving Owner's profile id: fill in before running
  c_expected constant int := 26;
  c_reason constant text := 'Singapore mobile given +65 (the Owner, 9 Oct 2026, Q8 d)';
  c_review_md5 constant text := 'd6d2779e1d43a47850adbee074088a5f';  -- apply_customer_phone_review(jsonb), 9 Oct 2026
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_rows jsonb; n int; n_done int; r record;
begin
  perform set_config('search_path', 'public', true);
  if c_owner is null or not exists (select 1 from public.profiles p where p.id = c_owner and p.role = 'owner'
                                       and p.is_active and p.deleted_at is null) then
    raise exception 'phones repair: set c_owner to the approving Owner''s profile id (an active Owner); nothing was changed'; end if;
  if to_regprocedure('public.apply_customer_phone_review(jsonb)') is null
     or md5(pg_get_functiondef('public.apply_customer_phone_review(jsonb)'::regprocedure)) <> c_review_md5 then
    raise exception 'phones repair: apply_customer_phone_review is not the version read on 9 Oct 2026; re-read it before running'; end if;

  drop table if exists pg_temp.phones_to_convert;
  create temp table phones_to_convert on commit drop as
  select c.id, c.phone as old_phone, m.inspection->>'normalized' as new_phone
    from public.customers c
    join public.customer_phone_migration_map m on m.customer_id = c.id
   where c.deleted_at is null and c.phone ~ '^[0-9]{8}$'
     and m.inspection->>'status' = 'ready' and m.applied_at is null;
  select count(*) into n from phones_to_convert;
  if n = 0 then
    raise notice 'phones repair: no ready eight-digit number is left; nothing to do';
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if n <> c_expected then
    raise exception 'phones repair: % ready eight-digit numbers, not the % read on 9 Oct 2026. Re-read them before running; nothing was changed', n, c_expected; end if;
  if exists (select 1 from phones_to_convert t
              left join public.customer_phone_migration_map m on m.customer_id = t.id
             where t.new_phone is distinct from '+65' || t.old_phone
                or m.original_phone is distinct from t.old_phone
                or public.normalize_customer_phone(t.old_phone) is distinct from t.new_phone
                or not public.valid_customer_e164(t.new_phone)) then
    raise exception 'phones repair: a number is not a plain Singapore mobile as reviewed; nothing was changed'; end if;

  select jsonb_agg(jsonb_build_object('customer_id', t.id, 'original_phone', t.old_phone,
                                      'normalized_phone', t.new_phone, 'reason', c_reason) order by t.id)
    into v_rows from phones_to_convert t;
  perform set_config('request.jwt.claims', json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  n_done := public.apply_customer_phone_review(v_rows);
  for r in select * from phones_to_convert order by id loop
    perform public.write_audit_ex('customers', r.id, 'customer_phone_reviewed',
      jsonb_build_object('phone', r.old_phone), jsonb_build_object('phone', r.new_phone),
      'customers', c_reason, null::uuid);
  end loop;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  if n_done <> c_expected
     or exists (select 1 from phones_to_convert t join public.customers c on c.id = t.id where c.phone is distinct from t.new_phone)
     or (select count(*) from public.customer_phone_history h join phones_to_convert t on t.id = h.customer_id
          where h.phone = t.old_phone and h.reason = c_reason) <> c_expected then
    raise exception 'phones repair: the numbers are not as expected afterwards; nothing was changed'; end if;
  raise notice 'phones repair: % numbers given +65, each in the phone history and the audit log', n_done;
  perform set_config('search_path', v_path, true);
end $repair$;
