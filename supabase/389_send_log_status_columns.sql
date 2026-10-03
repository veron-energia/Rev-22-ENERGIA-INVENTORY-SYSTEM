-- 389_send_log_status_columns.sql
--
-- WHAT WAS WRONG (found 3 Oct 2026, beside 388)
--
--   The send log, public.document_sends (93), has never held a row, although
--   staff send invoices: 28 customer copies were uploaded to the invoice-pdfs
--   bucket between 5 Aug and 30 Sep 2026. There are two causes, one each side:
--
--   1. The application never made the call. logSend in src/lib/sendDoc.ts
--      fired it with "void supabase.rpc(...)", and the client only sends a
--      request once something calls then() on it. The API logs show the
--      upload and the signed link of a send, and no /rpc/record_document_send.
--      Fixed in sendDoc.ts beside this migration.
--
--   2. Had the call been made, it would have failed. Production's
--      document_sends was created by an earlier form of 93, before the send
--      log gained a status and an error; when 93 was run again, "create table
--      if not exists" kept the old table. So it has no status and no
--      error_text column, while the live
--      record_document_send(text,text,text,uuid,uuid,text,text,text,text)
--      writes both, and every call would end in 42703 ("column does not
--      exist"). A database built from 93 as it stands has both columns, which
--      is why the local one works.
--
-- WHAT THIS CHANGES
--
--   document_sends gains the two columns exactly as 93 declares them:
--     status      text not null default 'sent', checked to be 'sent' or
--                 'failed' (constraint document_sends_status_check, the name
--                 PostgreSQL gives 93's inline check);
--     error_text  text, nullable.
--   Production's table is empty, so nothing is back-filled; were there rows,
--   the default would mark them 'sent', which is what the old table meant.
--
-- NOT CHANGED
--
--   record_document_send and its grants, the table's other columns, its index,
--   its row-level security and its read policy. No data is touched. 388
--   (applied 3 Oct 2026) dropped the leftover 7-argument record_document_send;
--   nothing here depends on that.
--
-- SAFETY
--
-- Apart from the lock timeout set first (which installs nothing), the whole
-- migration is ONE statement (a single DO block), so it is atomic whatever
-- runs it. Each column and the check are added only if missing. Afterwards
-- both columns must have 93's type, nullability and default, and the check
-- 93's definition, whether this run added them or found them: a column of the
-- same name but another shape stops the migration rather than being kept.
-- Run again, or on a database built from 93 as it stands, it changes nothing.
--
-- Rollback, if ever needed (only while the table holds no row that needs
-- them):
--   alter table public.document_sends drop constraint document_sends_status_check,
--     drop column status, drop column error_text;
-- after which every call to the 9-argument record_document_send fails again.
--
-- AFTER (once applied, for later guards):
--   document_sends.status      text not null default 'sent'::text
--   document_sends.error_text  text, nullable, no default
--   document_sends_status_check
--     CHECK ((status = ANY (ARRAY['sent'::text, 'failed'::text])))
--   record_document_send(text,text,text,uuid,uuid,text,text,text,text) unchanged
--     (production md5(prosrc) 0a7b7f0068f4dd59a76ffdece443bcb9, 3 Oct 2026)

set lock_timeout = '5s';

do $mig$
declare
  v_tbl regclass := to_regclass('public.document_sends');
  v text;
begin
  -- ── 0. Guard ─────────────────────────────────────────────────────────────
  if v_tbl is null then
    raise exception '389: public.document_sends is missing (93 has not been applied)'; end if;

  -- ── 1. The columns and the check, each only if missing ───────────────────
  alter table public.document_sends
    add column if not exists status text not null default 'sent',
    add column if not exists error_text text;

  if not exists (select 1 from pg_constraint
                  where conrelid = v_tbl and conname = 'document_sends_status_check') then
    alter table public.document_sends
      add constraint document_sends_status_check check (status in ('sent', 'failed'));
  end if;

  -- ── 2. Whatever was there before, it must now be 93's shape ──────────────
  select format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
         || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '')
    into v
    from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = v_tbl and a.attname = 'status' and not a.attisdropped;
  if v is distinct from 'text not null default ''sent''::text' then
    raise exception '389: document_sends.status is "%", not 93''s "text not null default ''sent''::text"', v; end if;

  select format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
         || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '')
    into v
    from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = v_tbl and a.attname = 'error_text' and not a.attisdropped;
  if v is distinct from 'text' then
    raise exception '389: document_sends.error_text is "%", not 93''s "text"', v; end if;

  select pg_get_constraintdef(oid) into v from pg_constraint
   where conrelid = v_tbl and conname = 'document_sends_status_check';
  if v is distinct from 'CHECK ((status = ANY (ARRAY[''sent''::text, ''failed''::text])))' then
    raise exception '389: document_sends_status_check is "%", not 93''s check on status', v; end if;

  -- The API server caches each table's columns; ask it to read them again.
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
