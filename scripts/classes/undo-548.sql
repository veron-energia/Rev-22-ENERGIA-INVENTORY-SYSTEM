-- UNDO of 548 (with the Owner's go-ahead): the Class page's tables and functions go, the four class
-- vouchers get their old names back and show on the Vouchers page again (it lists every voucher once
-- the class table is gone; the pages of 548 cope with a missing class_vouchers).
--
-- It refuses, with nothing changed, unless 548 is in as it was made (every function it added is exactly
-- 548's, so it runs BEFORE any older UNDO), and while staff recorded the date a seat chose or ticked a
-- seat as attending: undoing would lose those records. A test file that runs it inside its own rolled-back
-- transaction sets energia.undo548_test_only to on (session-local) first; then those rows go with the
-- tables and the flag is cleared again. A real undo never sets it. Dates and class details an Owner or
-- Manager edited go with the tables (decide with the Owner what to keep first).
--
-- What it does:
--   * the vouchers 548 renamed get their old names back where they still carry 548's (a name changed
--     since is left, with a notice); each change is in the Audit Log as every voucher change is;
--   * the invoice lines whose printed name 548 froze (the ids are in the Audit Log entries
--     class_lines_name_frozen) go back to having none, where the name is still the one it froze;
--   * drops the two invoice_items triggers (class_line_voucher_changed, class_line_removed), the capacity trigger,
--     the four tables and the ten functions.
-- Afterwards the functions are production's after 549 exactly (fingerprint
-- da952c4a3e002f6fc20da3260b1cff95/1471). The 548 row in supabase_migrations.schema_migrations stays; with
-- the Owner's OK, remove that one row or record this UNDO beside it. Audit Log rows are append-only and
-- stay (548's, and this undo's own voucher changes). Pages: revert the page commit too, or leave it (it
-- reads a missing class_vouchers as "no classes").
set lock_timeout = '5s';
do $undo$
declare
  c_fp_before constant text := 'da952c4a3e002f6fc20da3260b1cff95/1471';
  c_new constant text[][] := array[
    ['class_line_units(uuid)', '7b1a847e37dd57acff2e0ecafda42db5'],
    ['class_live_seats(uuid)', '1e1723f97d880bd3308c94b92502e490'],
    ['trg_class_seat_date_capacity()', '31219f6139047f835e32418052fc74de'],
    ['class_page_data()', '5727df5de4fe1d7b7ecbad7b07a85532'],
    ['class_choose_date(uuid,integer,uuid)', 'cc03742856ee4229893c6018ee06ed1c'],
    ['class_set_attendance(uuid,uuid,integer,boolean)', '50837bc66f6696841751c19df6681fed'],
    ['class_save_session(uuid,uuid,jsonb)', 'e0c6455dd0ba1edf5804659b42f6a6a2'],
    ['class_remove_session(uuid)', '5585fda03ea601809138c5193671e872'],
    ['class_save_details(uuid,jsonb)', '60e826b227ab3ccc98e24d5c684b7a25'],
    ['trg_class_line_changed()', '68bb63c4cf5a0dc44a7f7890898d7ec6']
  ];
  c_names constant text[][] := array[
    ['EmiLymphatic', 'Emi Foundation Lymphatic Zoom Class', 'Lymphatic Foundation Workshop 2027'],
    ['AdvancedZoom', 'Emi Advanced Lymphatic Zoom Class', 'Lymphatic Advanced Workshop 2027'],
    ['KPopClass', 'K Pop Facial Class', 'Korea No.1 Skin Care Workshop']];
  v_path text := current_setting('search_path');
  v_test boolean := coalesce(current_setting('energia.undo548_test_only', true), '') = 'on';
  v_fp text; k integer; v_md5 text; v_id uuid; r record; v_n integer;
begin
  perform set_config('search_path', 'public', true);
  if (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'
         and relname in ('class_vouchers', 'class_sessions', 'class_seat_dates', 'class_attendance')) <> 4 then
    raise exception 'UNDO 548: 548 is not in on this database (its four tables are not all there). Nothing was changed.'; end if;
  for k in 1 .. array_length(c_new, 1) loop
    if to_regprocedure('public.' || c_new[k][1]) is null then
      raise exception 'UNDO 548: public.% is missing. Nothing was changed.', c_new[k][1]; end if;
    v_md5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_new[k][1])));
    if v_md5 <> c_new[k][2] then
      raise exception 'UNDO 548: public.% is not 548''s (md5 %). Nothing was changed.', c_new[k][1], v_md5; end if;
  end loop;
  if (select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass
         and t.tgname in ('class_line_voucher_changed', 'class_line_removed')) <> 2 then
    raise exception 'UNDO 548: the two invoice_items triggers are not both there. Nothing was changed.'; end if;
  if not v_test and (exists (select 1 from public.class_seat_dates) or exists (select 1 from public.class_attendance)) then
    raise exception 'UNDO 548: staff recorded dates or attendance on the Class page, and undoing would lose them. Decide with the Owner what to keep. Nothing was changed.'; end if;

  -- Names back, and the frozen snapshots taken back.
  for k in 1 .. array_length(c_names, 1) loop
    select id into v_id from public.vouchers where code = c_names[k][1] and deleted_at is null;
    if v_id is null then
      raise exception 'UNDO 548: the voucher % is not there. Nothing was changed.', c_names[k][1]; end if;
    for r in select a.new_data->'invoice_item_ids' as ids from public.audit_logs a
              where a.table_name = 'vouchers' and a.record_id = v_id and a.action = 'class_lines_name_frozen' loop
      update public.invoice_items set item_name_snapshot = null
       where id in (select (x)::uuid from jsonb_array_elements_text(r.ids) x) and item_name_snapshot = c_names[k][2];
    end loop;
    if (select name from public.vouchers where id = v_id) = c_names[k][3] then
      update public.vouchers set name = c_names[k][2] where id = v_id;
    else
      raise notice 'UNDO 548: voucher % is named "%" now, not 548''s name; left as it is.', c_names[k][1], (select name from public.vouchers where id = v_id);
    end if;
  end loop;

  if v_test then
    delete from public.class_attendance;
    delete from public.class_seat_dates;
  end if;
  drop trigger class_line_voucher_changed on public.invoice_items;
  drop trigger class_line_removed on public.invoice_items;
  drop trigger class_seat_date_capacity on public.class_seat_dates;
  drop table public.class_attendance, public.class_seat_dates, public.class_sessions, public.class_vouchers;
  drop function public.class_page_data(), public.class_choose_date(uuid, integer, uuid),
    public.class_set_attendance(uuid, uuid, integer, boolean), public.class_save_session(uuid, uuid, jsonb),
    public.class_remove_session(uuid), public.class_save_details(uuid, jsonb), public.class_live_seats(uuid),
    public.class_line_units(uuid), public.trg_class_seat_date_capacity(), public.trg_class_line_changed();

  select md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*) into v_fp
    from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f';
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and t.tgname like 'class\_%') then
    raise exception 'UNDO 548: a class trigger is left on invoice_items'; end if;
  if v_fp <> c_fp_before then
    raise exception 'UNDO 548: the functions after are not production''s after 549 (fingerprint %)', v_fp; end if;
  if v_test then perform set_config('energia.undo548_test_only', 'off', true); end if;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
