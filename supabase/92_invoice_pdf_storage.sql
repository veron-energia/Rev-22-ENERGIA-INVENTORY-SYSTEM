-- =====================================================================
-- ENERGIA — STORAGE FOR SENT INVOICE / RECEIPT PDFs
--
-- Sending a customer their invoice as a PDF needs somewhere to put the file.
-- A browser cannot attach a file to a WhatsApp or mailto link, so the PDF is
-- uploaded here and the customer is sent a link to it.
--
-- The bucket is PRIVATE. Customers open a long-lived signed URL, so nothing is
-- readable without the exact link — an invoice contains a name, a phone number
-- and what somebody bought, which should not sit on a public URL that can be
-- enumerated.
--
-- Additive and idempotent. Run AFTER 91.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The bucket.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('invoice-pdfs', 'invoice-pdfs', false)
on conflict (id) do update set public = false;

-- ---------------------------------------------------------------------
-- 2. Staff may upload and replace; nobody reads without a signed URL.
--    The first path segment is the store id, matching the convention used by
--    survey attachments, so access can be store-scoped later if needed.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_policies
                  where schemaname = 'storage' and tablename = 'objects'
                    and policyname = 'invoice pdfs insert') then
    create policy "invoice pdfs insert" on storage.objects
      for insert to authenticated
      with check (bucket_id = 'invoice-pdfs');
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'storage' and tablename = 'objects'
                    and policyname = 'invoice pdfs update') then
    create policy "invoice pdfs update" on storage.objects
      for update to authenticated
      using (bucket_id = 'invoice-pdfs')
      with check (bucket_id = 'invoice-pdfs');
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'storage' and tablename = 'objects'
                    and policyname = 'invoice pdfs read') then
    create policy "invoice pdfs read" on storage.objects
      for select to authenticated
      using (bucket_id = 'invoice-pdfs');
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname = 'storage' and tablename = 'objects'
                    and policyname = 'invoice pdfs delete') then
    create policy "invoice pdfs delete" on storage.objects
      for delete to authenticated
      using (bucket_id = 'invoice-pdfs' and public.is_owner_or_manager());
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. A record of what was sent, to whom and how — so "did the customer ever
--    get their invoice?" is answerable.
-- ---------------------------------------------------------------------
create table if not exists public.document_sends (
  id uuid primary key default gen_random_uuid(),
  doc_kind text not null check (doc_kind in ('invoice','special_sale','rental')),
  doc_id uuid,
  doc_no text not null,
  customer_id uuid references public.customers(id),
  channel text not null check (channel in ('whatsapp','email','download')),
  sent_to text,
  pdf_path text,
  sent_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_document_sends_doc on public.document_sends (doc_kind, doc_id, created_at desc);
alter table public.document_sends enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='document_sends' and policyname='read document sends') then
    create policy "read document sends" on public.document_sends
      for select to authenticated using (true);
  end if;
end $$;

create or replace function public.record_document_send(
  p_doc_kind text, p_doc_no text, p_channel text,
  p_doc_id uuid default null, p_customer_id uuid default null,
  p_sent_to text default null, p_pdf_path text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid;
begin
  insert into public.document_sends (doc_kind, doc_id, doc_no, customer_id, channel, sent_to, pdf_path, sent_by)
  values (p_doc_kind, p_doc_id, p_doc_no, p_customer_id, p_channel, p_sent_to, p_pdf_path, auth.uid())
  returning id into v_id;
  return v_id;
end $function$;

notify pgrst, 'reload schema';
