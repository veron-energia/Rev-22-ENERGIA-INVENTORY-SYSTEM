-- 369_an_event_ticket_is_an_invoice_line.sql
--
-- Events (29 Sep 2026): a ticket to an event is bought on an invoice, as its
-- own kind of line. This adds the kind and nothing else. Postgres will not use
-- a new enum value in the transaction that adds it, so everything that reads
-- or writes event_ticket lines comes in 370, applied after this commits.
--
-- Additive and idempotent.

do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  join pg_namespace n on n.oid = t.typnamespace
                  where n.nspname = 'public' and t.typname = 'invoice_line_kind'
                    and e.enumlabel = 'event_ticket') then
    alter type public.invoice_line_kind add value 'event_ticket';
  end if;
end $$;
