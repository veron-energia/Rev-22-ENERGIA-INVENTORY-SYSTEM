-- 362_merge_leaves_phone_capture_with_retired_record.sql
--
-- WHAT WAS WRONG
--
-- merge_customer_records repoints every row that references the duplicate,
-- found from the catalogue. customer_phone_migration_map holds one row per
-- customer (primary key customer_id): the phone each imported record had when
-- the phone review was captured. When both records had such a row — two legacy
-- imports of the same person — the repoint hit the primary key and the whole
-- merge failed; preview_customer_merge did not warn. Three of the four "Alaric
-- Ong" records (26 Sep 2026), and the third "Moh Leng" record (25 Sep), could
-- not be merged for this reason.
--
-- WHAT THIS CHANGES
--
-- The capture stays with the record it describes. It records what THAT
-- record's phone was; moved onto the kept record it would describe a phone the
-- kept record never had, and the phone-review report would show a change that
-- never happened. The retired record keeps it, as it keeps its credit ledger.
--
-- NOT CHANGED: everything else the merge does, its refusals, and its grants.
--
-- SAFETY: guarded by the md5 of the production version (318; 26 Sep 2026) and
-- an anchor that must occur once; a function already carrying "362:" is left
-- alone.

set lock_timeout = '5s';

do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.merge_customer_records(uuid,uuid,text,uuid)'::regprocedure);
  if position('362:' in d) > 0 then raise notice '362: merge_customer_records already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'd62df8c6ed73f753450b5461a7f06868' then
    raise exception '362: merge_customer_records is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$       and not (c.relname = 'customer_affiliates' and a.attname = 'customer_id')
     order by c.relname, a.attname$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '362: merge_customer_records anchor found % times', n; end if;
  execute replace(d, a, $r$       and not (c.relname = 'customer_affiliates' and a.attname = 'customer_id')
       -- 362: a phone-review capture describes its own record's phone (one row
       -- per customer); it stays with the retired record.
       and not (c.relname = 'customer_phone_migration_map')
     order by c.relname, a.attname$r$);
end $mig$;
