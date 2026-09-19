begin;
-- =====================================================================
-- INVOICE CHANGES ARE PUBLISHED TO REALTIME
--
-- The invoice list refreshes itself when another user or tab changes an
-- invoice. It hears about the change through Supabase Realtime, which relays
-- row changes from the tables in the `supabase_realtime` publication. Nothing
-- had ever been added to that publication, so no change was ever relayed.
--
-- What this does NOT do:
--   * grant anyone anything. Realtime evaluates each subscriber's row-level
--     security with their own JWT, so a staff member only hears about
--     invoices in stores they can already read ("read accessible invoices",
--     08). The browser treats every event as a signal only — it re-runs the
--     same access-checked list query and never reads row data from an event.
--   * change replica identity. UPDATE and DELETE events therefore carry only
--     the primary key in `old`, which is all the browser uses. Invoices are
--     soft-deleted (deleted_at, 49), so a deletion arrives as an UPDATE.
--
-- Idempotent. On a plain Postgres without Supabase (the local test clusters)
-- the publication is created first so the same file applies everywhere.
-- =====================================================================
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['invoices', 'invoice_payments'] loop
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Both tables keep row-level security on; the policies below are the ones
-- Realtime applies per subscriber. Refuse to commit if either has gone.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoices' and cmd = 'SELECT') then
    raise exception '338: public.invoices has no SELECT policy; realtime would relay nothing, and the list would be wrong to rely on it';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoice_payments' and cmd = 'SELECT') then
    raise exception '338: public.invoice_payments has no SELECT policy';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.invoices'::regclass) then
    raise exception '338: row-level security is off on public.invoices';
  end if;
end $$;
commit;
