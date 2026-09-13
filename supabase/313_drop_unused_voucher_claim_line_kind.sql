begin;
-- =====================================================================
-- THE VOUCHER_CLAIM LINE KIND WAS NEVER USED
--
-- 310 added it to invoice_line_kind on the assumption that a Voucher Claim
-- document would carry a line. It does not: the claim records a hand-over of
-- something already paid for, so it has no items at all, and the label has sat
-- there unused ever since. A value in an enum is a claim about what the system
-- can do, and this one is false.
--
-- Postgres cannot drop an enum label, so the type is rebuilt without it. That
-- is safe here only because nothing depends on it, which this migration checks
-- rather than assumes: no row uses the label, no view, index, check constraint
-- or function signature refers to the type. If any of that stops being true the
-- migration refuses instead of destroying something.
--
-- plpgsql bodies are not dependency-tracked -- they resolve the type by name at
-- runtime -- so the 70-odd functions that mention line_kind need no change, and
-- the rebuilt type keeps the same name.
-- =====================================================================

do $$
declare v_bad int; v_label_missing boolean;
begin
  select not exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
                      where t.typname='invoice_line_kind' and e.enumlabel='voucher_claim')
    into v_label_missing;
  if v_label_missing then
    raise notice 'voucher_claim is not present; nothing to do';
    return;
  end if;

  -- Nothing may be using it.
  select count(*) into v_bad from public.invoice_items where line_kind::text = 'voucher_claim';
  if v_bad > 0 then
    raise exception 'Refusing: % invoice line(s) use voucher_claim', v_bad; end if;

  -- Nothing may depend on the type in a way the rebuild would break.
  select count(*) into v_bad from pg_proc p
   where p.proargtypes::oid[] @> array[(select oid from pg_type where typname='invoice_line_kind')]
      or p.prorettype = (select oid from pg_type where typname='invoice_line_kind');
  if v_bad > 0 then
    raise exception 'Refusing: % function signature(s) use invoice_line_kind', v_bad; end if;

  select count(*) into v_bad
    from pg_depend d join pg_rewrite r on r.oid=d.objid
    join pg_class c on c.oid=r.ev_class
    join pg_attribute a on a.attrelid=d.refobjid and a.attnum=d.refobjsubid
   where d.refobjid='public.invoice_items'::regclass and a.attname='line_kind'
     and c.relkind in ('v','m');
  if v_bad > 0 then
    raise exception 'Refusing: % view(s) select invoice_items.line_kind', v_bad; end if;

  select count(*) into v_bad from pg_index i
    join pg_attribute a on a.attrelid=i.indrelid and a.attnum = any(i.indkey)
    join pg_type t on t.oid=a.atttypid where t.typname='invoice_line_kind';
  if v_bad > 0 then raise exception 'Refusing: % index(es) on the column', v_bad; end if;

  select count(*) into v_bad from pg_constraint
   where conrelid='public.invoice_items'::regclass and contype='c'
     and pg_get_constraintdef(oid) like '%line_kind%';
  if v_bad > 0 then raise exception 'Refusing: % check constraint(s) on line_kind', v_bad; end if;

  -- Rebuild without the label, keeping the order of the real ones.
  execute 'create type public.invoice_line_kind_rebuilt as enum
           (''product'',''voucher'',''promotion'',''therapy'',''credit_package'',
            ''premium_bundle'',''special_product'',''rental'')';
  execute 'alter table public.invoice_items alter column line_kind drop default';
  execute 'alter table public.invoice_items alter column line_kind type public.invoice_line_kind_rebuilt
           using line_kind::text::public.invoice_line_kind_rebuilt';
  execute 'drop type public.invoice_line_kind';
  execute 'alter type public.invoice_line_kind_rebuilt rename to invoice_line_kind';
  execute 'alter table public.invoice_items alter column line_kind set default ''product''::public.invoice_line_kind';

  raise notice 'invoice_line_kind rebuilt without voucher_claim';
end $$;

notify pgrst,'reload schema';
commit;
