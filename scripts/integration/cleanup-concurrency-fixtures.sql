-- Remove what the concurrency suites committed.
--
-- Those suites cannot roll back: real row locks need real independent sessions,
-- so their fixtures are committed. Every other SQL suite here rolls back and is
-- entitled to assume the shared fixture is as the bootstrap left it — one of
-- them counts the locations a report offers and expects exactly four. Left
-- behind, a single committed store makes that suite fail for no real reason.
--
-- The guard triggers that protect genuine settled invoices would refuse this
-- teardown, so they are suspended for it. That also stops cascades firing,
-- which is why the orphan sweep at the end is not optional.
--
-- Disposable fixture only. Nothing here is scoped to anything but the
-- 'CX '/'SC ' fixture names the concurrency suites use.
set session_replication_role = replica;

do $$
declare ids uuid[]; invs uuid[]; t record; n int; changed boolean; guard int;
begin
  select array_agg(id) into ids from public.stores where name like 'CX %' or name like 'SC %';

  if ids is not null then
    select array_agg(id) into invs from public.invoices where store_id = any(ids);

    if invs is not null then
      changed := true; guard := 0;
      while changed and guard < 10 loop
        changed := false; guard := guard + 1;
        for t in select c.relname tbl, a.attname col
                 from pg_constraint k
                 join pg_class c on c.oid=k.conrelid and c.relkind='r'
                 join pg_attribute a on a.attrelid=k.conrelid and a.attnum=any(k.conkey)
                 join pg_class f on f.oid=k.confrelid
                 where k.contype='f' and f.relname='invoices' and k.confdeltype<>'c'
        loop
          begin
            execute format('delete from public.%I where %I = any($1)', t.tbl, t.col) using invs;
            get diagnostics n = row_count; if n > 0 then changed := true; end if;
          exception when others then null; end;
        end loop;
      end loop;
      delete from public.invoices where id = any(invs);
    end if;

    changed := true; guard := 0;
    while changed and guard < 10 loop
      changed := false; guard := guard + 1;
      for t in select c.relname tbl, a.attname col
               from pg_constraint k
               join pg_class c on c.oid=k.conrelid and c.relkind='r'
               join pg_attribute a on a.attrelid=k.conrelid and a.attnum=any(k.conkey)
               join pg_class f on f.oid=k.confrelid
               where k.contype='f' and f.relname='stores'
      loop
        begin
          execute format('delete from public.%I where %I = any($1)', t.tbl, t.col) using ids;
          get diagnostics n = row_count; if n > 0 then changed := true; end if;
        exception when others then null; end;
      end loop;
    end loop;

    delete from public.stores where id = any(ids);
  end if;

  delete from public.products       where name like 'CX %' or name like 'SC %';
  delete from public.customers      where full_name like 'CX %' or full_name like 'SC %';
  delete from public.payment_methods where name like 'CX %' or name like 'SC %';
  delete from public.profiles       where email like 'cx-%@tests.invalid' or email like 'sc-%@tests.invalid';
  delete from auth.users            where email like 'cx-%@tests.invalid' or email like 'sc-%@tests.invalid';

  -- Cascades did not fire above; sweep whatever the deleted invoices left.
  for t in select c.relname tbl, a.attname col
           from pg_constraint k
           join pg_class c on c.oid=k.conrelid and c.relkind='r'
           join pg_attribute a on a.attrelid=k.conrelid and a.attnum=any(k.conkey)
           join pg_class f on f.oid=k.confrelid
           where k.contype='f' and f.relname='invoices'
  loop
    begin
      execute format('delete from public.%I t where t.%I is not null'
                     ' and not exists (select 1 from public.invoices i where i.id = t.%I)',
                     t.tbl, t.col, t.col);
    exception when others then null; end;
  end loop;

  raise notice 'concurrency fixtures cleaned (% store(s))', coalesce(array_length(ids,1),0);
end $$;

set session_replication_role = origin;
