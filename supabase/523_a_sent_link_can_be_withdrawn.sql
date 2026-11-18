-- 523_a_sent_link_can_be_withdrawn.sql
--
-- AN OWNER OR MANAGER CAN WITHDRAW A LINK SENT TO A CUSTOMER
--
--   From the security audit of 17 Nov 2026 (finding L7).
--   The relied-on md5s below were compared with production on 18 Nov 2026 (head 522) and
--   match. If production differs when this is applied, it refuses and changes nothing.
--   (The number 523 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone, and in the suite's name.)
--
-- WHAT WAS WRONG
--
--   An invoice, special sale or rental sent by WhatsApp or email reaches the customer as a
--   link to a PDF copy in the private store invoice-pdfs. The link was signed for a year,
--   and there was no way to stop one link (sent to a wrong number, say) short of the Supabase
--   dashboard. No page showed which links had been sent.
--
-- THE RULES (the user, 18 Nov 2026)
--
--   * New links work 30 days (the page, src/lib/sendDoc.ts); a later request gets a new send.
--     New copies are stored with caching off, so a deleted copy is not served from a cache.
--   * Owners and Managers can withdraw a link that was sent: the invoice, special sale and
--     rental pages list the links sent, each with Withdraw. Withdrawing deletes that send's
--     copy, so its link no longer opens it (a PDF the customer already opened or saved stays
--     with them), and the send log records who withdrew it and when.
--   * Links already sent are left alone: nothing is deleted by this.
--   * A copy stored again under a withdrawn name (below) is shown, not blocked.
--
-- WHAT THIS DOES
--
--   * document_sends gains withdrawn_at and withdrawn_by.
--   * document_links(kind, document): for an Owner or Manager, the links sent for one invoice,
--     special sale or rental, newest first: each copy whose name carries the document's own
--     number (as sendDoc.ts names copies), with the document's sends in the send log that
--     name it (when, how, to whom, by whom), or alone when none does (sent before the log was
--     kept, 389), and whether the copy is still stored. The send log alone never makes a copy
--     a document's: any staff login writes it (record_document_send), so a send naming another
--     document's copy is not listed. A document's number is taken as fixed once it was sent.
--   * withdraw_document_link(kind, document, copy): records the withdrawal of a copy the page
--     has just deleted (the storage rules already let an Owner or Manager delete one), for a
--     copy whose name carries the document's number only. It refuses while the copy is still
--     stored, so the log never calls a link withdrawn that still opens; it marks the
--     document's sends of that copy withdrawn, by whom and when (a send keeps its first
--     withdrawal), and writes an Audit Log entry (document_link_withdrawn) under the
--     document's module each time it records one ('again' when one was recorded before). A
--     copy sent before the send log has the entries alone.
--   * document_link_name_re(kind, number): the names a document's copies are stored under,
--     as sendDoc.ts makes them; for the two functions above only (no login calls it).
--   Both functions are for an active Owner or Manager, as the storage rule that deletes a
--   copy is (is_owner_or_manager): any other staff login is told "Your role cannot do this.",
--   and a login that is not active staff "Only active Energia staff can do this."
--
-- WHAT THIS LEAVES ALONE
--
--   * The copies and links already sent (31 copies on 18 Nov 2026, 3 of them in the send
--     log), and who may read the send log.
--   * The storage rules. A login that may upload in a store's folder may store a copy under a
--     withdrawn name again (the pages never do: since 407 each send has a new name); the old
--     link would then open the new copy until it expires. The list shows such a copy as
--     stored again, with Withdraw (the user, 18 Nov 2026: show it, do not block it).
--   * The 30 days is the page's: a login that may read a copy can have a longer link signed.
--     Withdrawing is what stops a link.
--   * One stored copy (18 Nov 2026) has a name that fits no document's number; no page lists it.
--   * Sending: record_document_send and the pages' send buttons are as they were.
--
-- UNDO
--
--   drop function public.withdraw_document_link(text,uuid,text), public.document_links(text,uuid),
--   public.document_link_name_re(text,text); alter table public.document_sends drop column
--   withdrawn_by, drop column withdrawn_at (the withdrawals recorded are lost; the Audit Log
--   entries stay). A withdrawn copy is gone for good; a new send makes a new link.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/document-links-withdraw-523.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions this relies on, as tested.
  c_relied constant text[] := array[
    'require_active_staff(text[])',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'is_owner_or_manager()'];
  c_relied_md5 constant text[] := array[
    '877b3aa74cea559881979bb161c450e2',
    'c705c733e213a27f0dc32d54322cc855',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8'];
  -- The send log's columns as they end up (name, type, nullable), in order.
  c_cols_before constant text :=
    'id uuid NO,doc_kind text NO,doc_id uuid YES,doc_no text NO,customer_id uuid YES,channel text NO,sent_to text YES,pdf_path text YES,sent_by uuid YES,created_at timestamp with time zone NO,status text NO,error_text text YES';
  c_cols_after constant text :=
    'id uuid NO,doc_kind text NO,doc_id uuid YES,doc_no text NO,customer_id uuid YES,channel text NO,sent_to text YES,pdf_path text YES,sent_by uuid YES,created_at timestamp with time zone NO,status text NO,error_text text YES,withdrawn_at timestamp with time zone YES,withdrawn_by uuid YES';
  c_new_sig constant text[] := array[
    'document_link_name_re(text,text)',
    'document_links(text,uuid)',
    'withdraw_document_link(text,uuid,text)'];
  c_new_md5 constant text[] := array[
    '398b65c5cf3ba45de47e9ee7c2949116',
    '27a3c98cf91a74c8cefba02d253b2e6a',
    'eacf6fd4498dcb0ca60d62f32a24bf82'];
  c_new_grantees constant text[] := array[
    'service_role',
    'authenticated, service_role',
    'authenticated, service_role'];
  c_new_acl constant text[] := array[
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_new_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.document_link_name_re(p_doc_kind text, p_doc_no text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  -- 523: the names a document's PDF copies are stored under in invoice-pdfs, as a pattern,
  -- as src/lib/sendDoc.ts (documentPdfPath) makes them: the store (or no-store), the kind,
  -- the number with every character but A-Z a-z 0-9 . _ - made a dash, then nothing (a copy
  -- sent before 407, replaced on each send of the document) or a dash and a unique part
  -- (407: each send its own copy; a uuid, or, where a browser has none, the time and up to
  -- ten random characters in base 36), then .pdf.
  select '^[^/]+/' || p_doc_kind || '/'
         || replace(regexp_replace(p_doc_no, '[^A-Za-z0-9._-]', '-', 'g'), '.', '\.')
         || '(-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|-[0-9a-z]{6,}-[0-9a-z]{1,10})?\.pdf$'
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.document_links(p_doc_kind text, p_doc_id uuid)
 RETURNS TABLE(send_id uuid, pdf_path text, sent_at timestamp with time zone, channel text, sent_to text, sent_by_name text, status text, copy_present boolean, withdrawn_at timestamp with time zone, withdrawn_by_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 523: the links sent to the customer for one invoice, special sale or rental, newest
  -- first, for an Owner or Manager, who may withdraw them (security audit of 17 Nov 2026,
  -- L7; the user, 18 Nov 2026). A copy is the document's when its name carries the
  -- document's own number; the send log, which any staff login writes, only says how and to
  -- whom it was sent. Each of the document's sends of such a copy, and each stored copy with
  -- none (sent before the log was kept, 389). copy_present: the copy is still stored, so its
  -- link opens until it expires (after a withdrawal: stored again under that name).
  select public.require_active_staff('{owner,manager}');
  with doc as (
    select i.invoice_no as doc_no from public.invoices i where p_doc_kind = 'invoice' and i.id = p_doc_id
    union all
    select s.sale_no from public.special_sales s where p_doc_kind = 'special_sale' and s.id = p_doc_id
    union all
    select r.rental_no from public.rentals r where p_doc_kind = 'rental' and r.id = p_doc_id
  )
  select x.* from (
    select ds.id, ds.pdf_path, ds.created_at, ds.channel, ds.sent_to, sb.full_name, ds.status,
           exists (select 1 from storage.objects o where o.bucket_id = 'invoice-pdfs' and o.name = ds.pdf_path),
           ds.withdrawn_at, wb.full_name
      from public.document_sends ds
      join doc d on ds.pdf_path ~ public.document_link_name_re(p_doc_kind, d.doc_no)
      left join public.profiles sb on sb.id = ds.sent_by
      left join public.profiles wb on wb.id = ds.withdrawn_by
     where ds.doc_kind = p_doc_kind
       and (ds.doc_id = p_doc_id or (ds.doc_id is null and ds.doc_no = d.doc_no))
    union all
    select null::uuid, o.name, coalesce(o.updated_at, o.created_at), null::text, null::text, null::text, 'sent'::text,
           true, null::timestamptz, null::text
      from storage.objects o
      join doc d on o.name ~ public.document_link_name_re(p_doc_kind, d.doc_no)
     where o.bucket_id = 'invoice-pdfs'
       and not exists (select 1 from public.document_sends ds
                        where ds.pdf_path = o.name and ds.doc_kind = p_doc_kind
                          and (ds.doc_id = p_doc_id or (ds.doc_id is null and ds.doc_no = d.doc_no)))
  ) x (send_id, pdf_path, sent_at, channel, sent_to, sent_by_name, status, copy_present, withdrawn_at, withdrawn_by_name)
  order by 3 desc, 2
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.withdraw_document_link(p_doc_kind text, p_doc_id uuid, p_pdf_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 523: an Owner or Manager withdraws one link sent to a customer (security audit of 17 Nov
-- 2026, L7; the user, 18 Nov 2026). The page first deletes the copy (the storage rules let
-- an Owner or Manager do that); this records it, for a copy whose name carries the
-- document's own number only (the send log, which any staff login writes, never makes a
-- copy a document's). It refuses while the copy is still stored, so a link that still opens
-- is never recorded as withdrawn. The document's sends of that copy are marked withdrawn, by
-- whom and when (a send keeps its first withdrawal), and an Audit Log entry is written under
-- the document's module each time ('again' when one was written before: a copy stored again
-- under the name and withdrawn again, or the same withdrawal asked twice).
declare v_store uuid; v_no text; v_table text; v_n int; v_again boolean;
begin
  perform public.require_active_staff('{owner,manager}');
  if p_doc_kind = 'invoice' then
    select i.store_id, i.invoice_no into v_store, v_no from public.invoices i where i.id = p_doc_id;
    v_table := 'invoices';
  elsif p_doc_kind = 'special_sale' then
    select s.store_id, s.sale_no into v_store, v_no from public.special_sales s where s.id = p_doc_id;
    v_table := 'special_sales';
  elsif p_doc_kind = 'rental' then
    select r.store_id, r.rental_no into v_store, v_no from public.rentals r where r.id = p_doc_id;
    v_table := 'rentals';
  end if;
  if v_no is null then
    raise exception 'This document was not found.';
  end if;
  if p_pdf_path is null or p_pdf_path !~ public.document_link_name_re(p_doc_kind, v_no) then
    raise exception 'This link is not one sent for this document.';
  end if;
  -- One withdrawal of a copy at a time.
  perform pg_advisory_xact_lock(hashtextextended('document-link:' || p_pdf_path, 0));
  if exists (select 1 from storage.objects o where o.bucket_id = 'invoice-pdfs' and o.name = p_pdf_path) then
    raise exception 'The PDF copy is still there, so its link still opens. Try Withdraw again.';
  end if;
  v_again := exists (select 1 from public.audit_logs a
                      where a.table_name = v_table and a.record_id = p_doc_id and a.action = 'document_link_withdrawn'
                        and a.new_data ->> 'pdf_path' = p_pdf_path);
  update public.document_sends ds set withdrawn_at = now(), withdrawn_by = auth.uid()
   where ds.pdf_path = p_pdf_path and ds.doc_kind = p_doc_kind
     and (ds.doc_id = p_doc_id or (ds.doc_id is null and ds.doc_no = v_no))
     and ds.withdrawn_at is null;
  get diagnostics v_n = row_count;
  perform public.write_audit_ex(v_table, p_doc_id, 'document_link_withdrawn', null,
    jsonb_build_object('doc_kind', p_doc_kind, 'doc_no', v_no, 'pdf_path', p_pdf_path, 'sends_marked', v_n, 'again', v_again),
    null, null, v_store);
  return jsonb_build_object('success', true, 'sends', v_n, 'again', v_again);
end
$function$
$def$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_cols text;
  v_add_cols boolean := false;
  v_make boolean[] := array_fill(false, array[3]);
  i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '523: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regclass('storage.objects') is null then
    raise exception '523: storage.objects is missing'; end if;

  -- The send log's columns: as before (two added), or 523's already (left alone).
  v_cols := (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
               from information_schema.columns where table_schema = 'public' and table_name = 'document_sends');
  if v_cols = c_cols_before then
    v_add_cols := true;
  elsif v_cols = c_cols_after then
    raise notice '523: public.document_sends already has withdrawn_at and withdrawn_by; left alone';
  else
    raise exception '523: public.document_sends is not as tested (%). Re-read it before applying.', coalesce(v_cols, 'missing');
  end if;

  -- The new functions: missing (made), or 523's already with its rights (left alone).
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null then
      v_make[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) = c_new_md5[i]
          and (select coalesce(string_agg(x::text, ',' order by x::text), '')
                 from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) = c_new_acl[i] then
      raise notice '523: public.% is already there; left alone', c_new_sig[i];
    else
      raise exception '523: a function public.% is there, but not 523''s. Re-read it before applying.', c_new_sig[i];
    end if;
  end loop;

  -- 2. Install
  if v_add_cols then
    alter table public.document_sends
      add column withdrawn_at timestamp with time zone,
      add column withdrawn_by uuid references public.profiles(id);
  end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if v_make[i] then
      execute c_new_def[i];
      execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
      execute format('grant execute on function public.%s to %s', c_new_sig[i], c_new_grantees[i]);
    end if;
  end loop;

  -- 3. Checks after installing
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'document_sends') is distinct from c_cols_after then
    raise exception '523: public.document_sends is not as tested after adding its columns'; end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '523: public.% was installed with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i] then
      raise exception '523: the rights on public.% are not the tested ones', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '523: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
