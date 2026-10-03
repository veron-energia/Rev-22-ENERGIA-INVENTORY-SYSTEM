-- 388_drop_legacy_record_document_send_overload.sql
--
-- WHAT WAS WRONG (found 3 Oct 2026, beside 386)
--
--   Production holds two functions named record_document_send:
--
--     record_document_send(text,text,text,uuid,uuid,text,text,text,text)  9 args
--       the one migration 93 defines and src/lib/sendDoc.ts (logSend) names:
--       it sends all nine arguments by name, p_status and p_error included.
--
--     record_document_send(text,text,text,uuid,uuid,text,text)            7 args
--       an older form of 93's function, from before it took a status and an
--       error. Re-running 93 with the longer argument list made a second
--       function instead of replacing this one. It is SECURITY DEFINER and
--       callable by authenticated: 339 granted every function of that name
--       to staff, this one included.
--
--   Nothing calls it, and as things stand nothing can: the 9-argument one
--   gives every argument after the third a default, so any call with seven
--   arguments or fewer, by position or by name, matches both and PostgreSQL
--   refuses it as ambiguous ("function public.record_document_send(...) is
--   not unique"); the API server refuses the same call before that, because
--   two functions match the names sent. Checked read-only on 3 Oct 2026:
--     * no function in any schema calls it, nothing depends on it
--       (pg_depend), and no cron job names it;
--     * src/ calls the name once, with nine named arguments; scripts/ and
--       supabase/functions/ never name it;
--     * the API logs of the last seven days show no call to either form.
--   So it is not a working hole today, but should the 9-argument function
--   ever lose a default, a signed-in user's seven-argument call would land
--   here; and while it exists, a patch to "the" record_document_send by name
--   can patch it instead of the live one (the 302 pattern, see 386).
--
--   Found on the way, NOT changed here: the send log has never held a row.
--   logSend fires its call with "void supabase.rpc(...)", and the client only
--   sends a request once it is awaited, so the call is never made. Were it
--   made, it would fail too: production's document_sends was created before
--   93 gained the status and error_text columns ("create table if not
--   exists" then kept the old table), and the 9-argument function writes
--   both. Making the log work needs those two columns added and logSend to
--   send its request; this migration neither helps nor hinders that.
--
-- WHAT THIS CHANGES
--
--   The 7-argument record_document_send is dropped.
--
--   A call with three to seven arguments, which today fails as ambiguous,
--   reaches the 9-argument function afterwards, with its default status
--   ('sent') and no error. Nothing makes such a call.
--
-- NOT CHANGED
--
--   The 9-argument record_document_send and its grants, the document_sends
--   table, and logSend. No data is touched.
--
-- SAFETY
--
-- Apart from the lock timeout set first (which installs nothing), the whole
-- migration is ONE statement (a single DO block), so it is atomic whatever
-- runs it. Before dropping anything it checks that the function is the
-- version read from production (md5(prosrc), 3 Oct 2026), and that the
-- 9-argument function is there, with the same first seven parameter names and
-- defaults for its last six, so every call the old one could have answered,
-- by position or by name, has somewhere to go. The drop is RESTRICT: it fails
-- if anything has come to depend on the function. Afterwards exactly one
-- record_document_send must remain. Run again once the function is gone, it
-- changes nothing.
--
-- Rollback, if ever needed: production's definition and grants are
-- reproduced byte for byte by this migration's local test,
-- scripts/invoices/tests/legacy-record-document-send-dropped.sql.
--
-- AFTER (once applied, for later guards):
--   record_document_send(text,text,text,uuid,uuid,text,text)            absent
--   record_document_send(text,text,text,uuid,uuid,text,text,text,text)  unchanged
--     (production md5(prosrc) 0a7b7f0068f4dd59a76ffdece443bcb9, 3 Oct 2026)

set lock_timeout = '5s';

do $mig$
declare
  v_old  regprocedure := to_regprocedure('public.record_document_send(text,text,text,uuid,uuid,text,text)');
  v_live regprocedure := to_regprocedure('public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)');
  v text; n int;
begin
  -- ── 0. Guards: nothing is dropped unless all of these pass ───────────────
  if v_live is null then
    raise exception '388: record_document_send(text,text,text,uuid,uuid,text,text,text,text) is missing'; end if;
  select pronargdefaults into n from pg_proc where oid = v_live;
  if n <> 6 then
    raise exception '388: the 9-argument record_document_send has % defaults, not 6 (p_doc_id through p_error)', n; end if;
  select array_to_string(proargnames[1:7], ',') into v from pg_proc where oid = v_live;
  if v is distinct from 'p_doc_kind,p_doc_no,p_channel,p_doc_id,p_customer_id,p_sent_to,p_pdf_path' then
    raise exception '388: the 9-argument record_document_send does not start with the 7-argument one''s parameter names (%)', v; end if;

  if v_old is null then
    raise notice '388: the 7-argument record_document_send is already gone; nothing to do.';
  else
    select md5(prosrc) into v from pg_proc where oid = v_old;
    if v <> 'f6807793ccb4f40fe53956bf1e95f36e' then
      raise exception '388: record_document_send(text,text,text,uuid,uuid,text,text) is not the version this was tested against (md5 %)', v; end if;

    -- ── 1. Drop it (RESTRICT: refused if anything depends on it) ───────────
    drop function public.record_document_send(text, text, text, uuid, uuid, text, text) restrict;
  end if;

  select count(*) into n from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'record_document_send';
  if n <> 1 then
    raise exception '388: expected exactly one record_document_send afterwards, found %', n; end if;

  -- The API server reloads its schema on a drop by itself (pgrst_drop_watch);
  -- asking again is harmless.
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
