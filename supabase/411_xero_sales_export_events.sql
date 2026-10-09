-- 411_xero_sales_export_events.sql
--
-- WHAT WAS WRONG (audit finding REPORTS-1, confirmed 8 Oct 2026)
--
--   The invoice page's Xero Export (Export recognized sales for Xero) is built
--   from invoice_sales_ledger(), the Sales report's ledger. That ledger
--   deliberately leaves out every payment and refund of an invoice that is
--   now cancelled or refunded, so that Sales shows only money kept. For an
--   accounting export that is wrong:
--
--   * a period's file depends on what happened LATER. An invoice paid in one
--     period and refunded or cancelled in a later one loses its receipt from
--     the first period, and its refund never appears in any period. Whoever
--     imported the first period keeps the receipt in Xero and never gets a
--     credit note. INV-2026-0304 received S$10,000 on 24 Sep and was refunded
--     on 30 Sep: an export run before 30 Sep held the receipt, every export
--     after it holds neither the receipt nor a refund;
--   * the ledger has never given a single refund: all 12 refund records are on
--     invoices that are now cancelled or refunded;
--   * money still held on a cancelled invoice is in no export at all
--     (INV-2026-0317, S$1,000), although the dialog promised "Money still held
--     on cancelled invoices remains included";
--   * a payment correction's reversal carries the corrected payment's date,
--     so a correction made after a period was exported changes that period
--     (INV-2026-0072: corrected on 7 Oct, its reversal dated 30 Sep);
--   * the dialog also said payments are dated by the invoice's business date
--     (they are dated by the payment's own date), and nothing recorded what
--     was downloaded, so nothing could warn that a period already exported
--     had changed.
--
-- THE RULES (the Owner approved fixing REPORTS-1, 9 Oct 2026; the export only)
--
--   1. The Xero sales export has its own list of money events. Once an event
--      is written, its document, date and amount never change, so a period
--      that was exported never changes later:
--      * every payment received (not wallet credit) on its own date, the date
--        the Sales report gives it (payment_sales_date), whatever happens to
--        the invoice later;
--      * every refund against a payment, as a credit note for the money that
--        went back (the amount less any credit returned to the wallet), on
--        the Singapore day it was recorded. A refund made when an invoice is
--        cancelled is one of these. A cancellation itself moves no money
--        (cancel_invoice_recorded keeps the payments: "Record any actual
--        refund separately"), so money still held on a cancelled invoice
--        stays as received until its refund is recorded;
--      * a payment correction (correct_invoice_payment, remove_invoice_payment)
--        on the day it was made: the later of the date the row carries and
--        the Singapore day it was recorded. A reversal carries the corrected
--        payment's date, which may be in a period already exported.
--   2. Wallet credit is not new money: payments with it, and refunds wholly
--      back to the wallet, are not listed (as before).
--   3. Deleted invoices are not listed (as before): delete_invoice refuses an
--      invoice with a payment, so none can disappear this way any more.
--   4. Kept out until the Owner decides (as the export always left them),
--      and shown on the page: the payments of the 9 invoices refunded before
--      refunds were recorded (status refunded and no refund row: INV-2026-0028,
--      0047, 0110, 0132, 0140, 0160, 0174, 0184, 0202; S$8,054.47). With no
--      refund record to set against them, exporting their receipts would show
--      S$8,054.47 as kept.
--   5. A refund recorded without its payment (none on production) cannot be
--      told apart from a wallet one: the page refuses a period that has one.
--   6. The Xero document numbers stay what the page has always written
--      (<invoice>-PAY|ADJ|REV|REF-<event id without dashes>), so a document
--      downloaded before keeps its number.
--   7. Every download is recorded (dates, stores, who, and each document's
--      number, date and amount), so the next export can say which documents
--      were already downloaded, which ones are new in a period already
--      downloaded (entered late), and which downloaded ones the app no longer
--      lists. A document is known as downloaded whatever store it was
--      downloaded for, so moving a paid invoice to another store (an Owner or
--      Manager can, correct_invoice; 2 paid invoices on production so far)
--      does not make it new again. A document already downloaded goes into
--      another file only when the person asks for it again; a download that
--      would repeat one unasked (two exports at the same time, or a review
--      left open while someone else downloads) is refused. Downloads made
--      before this were not recorded: the page asks the person to check Xero
--      before downloading dates from before the first recorded download.
--   The Sales report, the dashboard and every other figure keep
--   invoice_sales_ledger's rule (money kept). TikTok's own Xero export (374,
--   375) is not touched.
--
--   Production, 9 Oct 2026 (read-only, the rule run inline), against the
--   source the export used until now:
--     August     144 documents, S$60,027.70: the same documents either way
--                (the 6 payments of the old-way refunds, S$5,186.00, stay out);
--     September  177 documents, S$82,773.60 (until now 159, S$80,773.60):
--                the payments and refunds of INV-2026-0256, 0268, 0281, 0304,
--                0314 and 0315 (net nil), INV-2026-0317's S$1,000 still held,
--                INV-2026-0282's correction on 24 Sep (was 23 Sep) and
--                INV-2026-0072's 30 Sep correction kept in September;
--     October    33 documents, S$16,244.30 (until now 32, S$17,244.30):
--                INV-2026-0072's 7 Oct reversal dated 7 Oct (was 30 Sep).
--   22 documents in all differ from what the export gave until now; no
--   refund without a payment source and no refund wholly to the wallet.
--
-- WHAT THIS DOES
--
--   * Tables xero_sales_exports (one row per download: request ID, when, who,
--     From and To, the store asked for, the stores it covered, the number of
--     documents and their net total) and xero_sales_export_documents (each
--     document of a download: kind, event, invoice, store, number, date,
--     amount). RLS on with no policy, closed to anon and authenticated; only
--     the functions below read or write them.
--   * xero_sales_event_rows(from, to) (new; internal, the service role's
--     alone, 339): rule 1 to 6, the one place it is written. One row per
--     money event dated between the two dates: its kind (receipt,
--     correction_reversal, correction_replacement, refund; or, never to be
--     exported, legacy_refund_left_out and refund_unsourced), event, invoice,
--     invoice number, store, customer, Xero document number, date, signed
--     amount and when it was recorded.
--   * xero_sales_events(from, to, store) (new; Owner/Manager): those rows for
--     the stores the caller can see (or the one asked for), with the
--     customer's name, email and address as the contact (a deleted customer
--     keeps their name, so the export no longer stops on one; REPORTS-M1).
--   * xero_sales_export_review(from, to, store) (new; Owner/Manager): what
--     was downloaded before for those dates and stores: the overlapping
--     downloads (with only these stores' part of their count and total, so a
--     Manager sees no other store's takings), each document's latest
--     download whatever store it was downloaded for, the downloaded
--     documents the app no longer lists between the dates for these stores
--     (gone, re-dated, or moved to another store's invoice), and documents
--     outside the dates entered after their own period was downloaded.
--   * record_xero_sales_export(from, to, store, documents, request) (new;
--     Owner/Manager): records a download, one at a time (a transaction
--     lock). Every document must be one xero_sales_event_rows lists now, for
--     the stores covered, with the same number, date and amount, and must
--     not be in an earlier download unless marked "redownload", else nothing
--     is recorded. The same request again returns the same record.
--
-- NOT CHANGED
--
--   * invoice_sales_ledger, the Sales report, the dashboard, every payment,
--     refund, cancellation and correction function, and their data. No row
--     is written by this migration.
--   * No existing function is patched, so nothing here conflicts with the
--     staff guard 406/407 add to existing functions; the four new ones check
--     the caller themselves (an active, accepted, not deleted Owner or
--     Manager).
--   * TikTok's Xero export (tiktok_xero_payouts, tiktok_bank_payouts).
--   * The 9 legacy refunds stay unrecorded (owner question): if refund rows
--     are ever backfilled for them, their receipts and refunds become normal
--     events, and the next export's review lists them as new in a period
--     already downloaded.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block),
-- so it is atomic however it is run. Every guard is checked and every text
-- built before anything is created. The two tables must be missing or exactly
-- this shape (column signature md5); the four functions must be missing or
-- already this migration's version (AFTER), which is left alone, so a re-run
-- changes nothing; any other text refuses. The functions they call must be
-- the production versions read on 9 Oct 2026, payments may only be of the
-- three kinds read that day, and no other function may take the four names
-- (the API picks an overload by name). The internal function is revoked from
-- public, anon and authenticated and granted to the service role (339); the
-- three the page calls are granted to authenticated and the service role
-- only. After installing, each function must have its AFTER md5 and these
-- grants, and both tables RLS on and no privilege for anon or authenticated.
-- No data changes. The definitions are read and compared with the search
-- path set to public.
--
-- The rule relies on payments and refunds not being edited after they are
-- written: on 9 Oct 2026 nothing updates or deletes a refund, and the only
-- updates to a payment are its method (non-wallet to non-wallet:
-- correct_invoice_payment_methods; the export does not show the method), the
-- lock time and the request ID. If a later change ever alters or removes a
-- downloaded document, xero_sales_export_review lists it. An invoice's store
-- can change (correct_invoice), which moves no document's number, date or
-- amount; the review follows the document to its store now.
-- record_xero_sales_export takes a transaction-level advisory lock on
-- hashtextextended('xero-sales-export', 0), a key no other function uses.
--
-- BEFORE (production, 9 Oct 2026, md5 of pg_get_functiondef):
--   xero_sales_event_rows(date,date)                                      (missing)
--   xero_sales_events(date,date,uuid)                                     (missing)
--   xero_sales_export_review(date,date,uuid)                              (missing)
--   record_xero_sales_export(date,date,uuid,jsonb,uuid)                   (missing)
--   tables xero_sales_exports, xero_sales_export_documents                (missing)
--   (relied on, not changed)
--   payment_sales_date(timestamp with time zone,timestamp with time zone) 3e5161e4830f5f6fdc8f34a24266fdc9
--   user_has_store_access(uuid)                                           8c82c6bcb64f496c5a05a2b8dafa95f8
-- AFTER (for later guards):
--   xero_sales_event_rows(date,date)                                      18858e023c44d06814e617299456084b
--   xero_sales_events(date,date,uuid)                                     0e74090dce71966dfd9542c2c4a46fb2
--   xero_sales_export_review(date,date,uuid)                              2a89b9c2fbd81ec05bb0315eccbc80dc
--   record_xero_sales_export(date,date,uuid,jsonb,uuid)                   1979c940c92255e15e9490395d044063
--   xero_sales_exports columns                                            274075a74ecbc3aa34b286b0b7a37419
--   xero_sales_export_documents columns                                   4b4150b80cad616d17b35bb6c15ea2e7
--
-- DEPLOY ORDER: this, then the page. The page live now keeps calling
-- invoice_sales_ledger (unchanged) until it is replaced; the new page against
-- a database without this fails with "function not found" and downloads
-- nothing.
--
-- Test: scripts/xero/tests/sales-events.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The tables ─────────────────────────────────────────────────────────────
  c_exports_ddl constant text := $ddl$
create table public.xero_sales_exports (
  id                uuid primary key,
  request_id        uuid not null unique,
  request_hash      text not null,
  exported_at       timestamptz not null default now(),
  exported_by       uuid not null,
  from_date         date not null,
  to_date           date not null,
  store_id          uuid,
  covered_store_ids uuid[] not null,
  document_count    integer not null,
  net_total         numeric(14,2) not null,
  constraint xero_sales_exports_dates check (to_date >= from_date),
  constraint xero_sales_exports_documents check (document_count > 0)
)
$ddl$;
  c_docs_ddl constant text := $ddl$
create table public.xero_sales_export_documents (
  export_id       uuid not null references public.xero_sales_exports(id) on delete cascade,
  event_kind      text not null,
  event_id        uuid not null,
  invoice_id      uuid not null,
  store_id        uuid not null,
  document_number text not null,
  document_date   date not null,
  amount          numeric(14,2) not null,
  primary key (export_id, event_kind, event_id)
)
$ddl$;

  -- ── The rule ───────────────────────────────────────────────────────────────
  c_rows_def constant text := $def$
create or replace function public.xero_sales_event_rows(p_from date, p_to date)
returns table(event_kind text, event_id uuid, invoice_id uuid, invoice_no text, store_id uuid, customer_id uuid,
              document_number text, document_date date, amount numeric, recorded_at timestamptz)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 411: THE rule for what the Xero sales export holds (REPORTS-1, approved by
  -- the Owner on 9 Oct 2026). An append-only list of money events dated by
  -- what never changes once written, so a period that was exported never
  -- changes later:
  --   receipt                 a payment received with a method that is not
  --                           wallet credit, whatever the invoice's status is
  --                           now, on its own date (payment_sales_date, as the
  --                           Sales report dates it);
  --   correction_reversal,    a payment correction, on the day it was made: the
  --   correction_replacement  later of the date the row carries and the
  --                           Singapore day it was recorded (a reversal carries
  --                           the corrected payment's date);
  --   refund                  a refund against a payment: a credit note for the
  --                           money that went back (less credit returned to the
  --                           wallet), on the Singapore day it was recorded.
  --                           Refunds made on a cancellation are these. A
  --                           cancellation itself moves no money, so money
  --                           still held on a cancelled invoice stays received.
  -- Wallet credit (not new money) and refunds wholly to the wallet are not
  -- listed, nor are deleted invoices (delete_invoice refuses one with a
  -- payment). Two kinds are listed to be explained, never exported:
  --   legacy_refund_left_out  a payment of an invoice refunded before refunds
  --                           were recorded (status refunded, no refund row):
  --                           with no refund to set against it, it stays out,
  --                           as the export always left it (Owner to decide);
  --   refund_unsourced        a refund recorded without its payment: whether
  --                           money went back cannot be told.
  -- document_number is the Xero number the page has always written.
  with inv as (
    select i.id, i.invoice_no, i.store_id, i.customer_id,
           i.status = 'refunded'
             and not exists (select 1 from public.invoice_refunds r where r.invoice_id = i.id) as legacy_refunded
      from public.invoices i
     where i.deleted_at is null
  ),
  ev as (
    select case when v.legacy_refunded then 'legacy_refund_left_out' else p.entry_kind end as event_kind,
           p.id as event_id, v.id as invoice_id, v.invoice_no, v.store_id, v.customer_id,
           case when p.entry_kind = 'receipt' then public.payment_sales_date(p.effective_at, p.created_at)
                else greatest(public.payment_sales_date(p.effective_at, p.created_at),
                              (p.created_at at time zone 'Asia/Singapore')::date) end as document_date,
           case when p.entry_kind = 'correction_reversal' then -p.amount else p.amount end as amount,
           p.created_at as recorded_at
      from public.invoice_payments p
      join inv v on v.id = p.invoice_id
      join public.payment_methods m on m.id = p.payment_method_id
     where not coalesce(m.is_wallet_credit, false)
    union all
    select case when r.payment_id is null then 'refund_unsourced' else 'refund' end,
           r.id, v.id, v.invoice_no, v.store_id, v.customer_id,
           (r.created_at at time zone 'Asia/Singapore')::date,
           -(r.amount - coalesce(r.credit_returned, 0)),
           r.created_at
      from public.invoice_refunds r
      join inv v on v.id = r.invoice_id
  )
  select e.event_kind, e.event_id, e.invoice_id, e.invoice_no, e.store_id, e.customer_id,
         e.invoice_no || '-'
           || case e.event_kind when 'receipt' then 'PAY' when 'correction_replacement' then 'ADJ'
                                when 'correction_reversal' then 'REV' when 'refund' then 'REF' end
           || '-' || replace(e.event_id::text, '-', ''),
         e.document_date, round(e.amount, 2), e.recorded_at
    from ev e
   where e.document_date between p_from and p_to
     and round(e.amount, 2) <> 0
$fn$
$def$;

  -- ── What the page reads ────────────────────────────────────────────────────
  c_events_def constant text := $def$
create or replace function public.xero_sales_events(p_from date, p_to date, p_store_id uuid default null)
returns table(event_kind text, event_id uuid, invoice_id uuid, invoice_no text, store_id uuid,
              document_number text, document_date date, amount numeric, recorded_at timestamptz,
              customer_id uuid, contact_name text, contact_email text, contact_address text)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  -- 411: the Xero sales export's documents dated between two days (both
  -- included), for an Owner or Manager: the stores they can see, or the one
  -- asked for. The rule is xero_sales_event_rows. The contact is the
  -- invoice's customer as the customer record has it now (a deleted
  -- customer keeps their name); none for a walk-in sale.
  if not exists (select 1 from public.profiles pr
                  where pr.id = auth.uid() and pr.is_active and pr.deleted_at is null
                    and coalesce(pr.invitation_status, 'accepted') = 'accepted'
                    and pr.role in ('owner', 'manager')) then
    raise exception 'Only an Owner or Manager can export sales for Xero' using errcode = '42501'; end if;
  if p_from is null or p_to is null then raise exception 'Choose a start and an end date'; end if;
  if p_to < p_from then raise exception 'The end date cannot be before the start date'; end if;
  return query
    select e.event_kind, e.event_id, e.invoice_id, e.invoice_no, e.store_id,
           e.document_number, e.document_date, e.amount, e.recorded_at,
           e.customer_id, c.full_name, c.email, c.address
      from public.xero_sales_event_rows(p_from, p_to) e
      left join public.customers c on c.id = e.customer_id
     where public.user_has_store_access(e.store_id)
       and (p_store_id is null or e.store_id = p_store_id)
     order by e.document_date, e.event_id, e.event_kind;
end $fn$
$def$;

  c_review_def constant text := $def$
create or replace function public.xero_sales_export_review(p_from date, p_to date, p_store_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare v_scope uuid[];
begin
  -- 411: what was downloaded before, for the dates and stores of an export
  -- about to be made (Owner or Manager). A downloaded document counts for
  -- these stores when it was recorded under one of them, or when its event is
  -- one of theirs now, whatever store it was recorded under (an Owner or
  -- Manager can move a paid invoice to another store, correct_invoice):
  --   recorded_since  the first download recorded, or null;
  --   exports         the downloads whose dates overlap these and that covered
  --                   one of these stores or hold one of their documents, with
  --                   only these stores' part: covered_store_ids, and the
  --                   number and net total of the documents counted here;
  --   downloads       each document dated between these days counted here:
  --                   its latest download (number, date and amount then) and
  --                   how many downloads held it;
  --   vanished        of those, the ones the export no longer lists between
  --                   these days for these stores: gone, dated elsewhere now,
  --                   or moved (its invoice is another store's now; now_store_id
  --                   when the caller can see that store). Xero holds them;
  --   missed          documents of these stores dated outside these days that
  --                   were never downloaded although a download covered their
  --                   day and store (they were entered after it), with what
  --                   the page needs to add them to the file.
  -- The page compares the rest: already downloaded, changed, and new in a
  -- period already downloaded.
  if not exists (select 1 from public.profiles pr
                  where pr.id = auth.uid() and pr.is_active and pr.deleted_at is null
                    and coalesce(pr.invitation_status, 'accepted') = 'accepted'
                    and pr.role in ('owner', 'manager')) then
    raise exception 'Only an Owner or Manager can export sales for Xero' using errcode = '42501'; end if;
  if p_from is null or p_to is null then raise exception 'Choose a start and an end date'; end if;
  if p_to < p_from then raise exception 'The end date cannot be before the start date'; end if;
  select coalesce(array_agg(s.id order by s.id), '{}'::uuid[]) into v_scope
    from public.stores s
   where public.user_has_store_access(s.id) and (p_store_id is null or s.id = p_store_id);
  if p_store_id is not null and not (p_store_id = any(v_scope)) then
    raise exception 'That store is not accessible'; end if;
  return (
    with allev as materialized (
      select r.* from public.xero_sales_event_rows('-infinity'::date, 'infinity'::date) r
    ),
    cur as (
      select a.* from allev a where a.store_id = any(v_scope)
    ),
    ex as (
      select x.* from public.xero_sales_exports x where x.covered_store_ids && v_scope
    ),
    dl as materialized (
      select d.*, x.exported_at
        from public.xero_sales_export_documents d
        join public.xero_sales_exports x on x.id = d.export_id
       where d.store_id = any(v_scope)
          or exists (select 1 from cur c where c.event_kind = d.event_kind and c.event_id = d.event_id)
    ),
    latest as (
      select distinct on (dl.event_kind, dl.event_id) dl.*,
             count(*) over (partition by dl.event_kind, dl.event_id) as times
        from dl
       order by dl.event_kind, dl.event_id, dl.exported_at desc
    )
    select jsonb_build_object(
      'recorded_since', (select min(x.exported_at) from public.xero_sales_exports x),
      'exports', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'exported_at', x.exported_at, 'exported_by', coalesce(pr.full_name, 'someone'),
                 'from_date', x.from_date, 'to_date', x.to_date, 'store_id', x.store_id,
                 'covered_store_ids', to_jsonb(array(select s from unnest(x.covered_store_ids) s
                                                      where s = any(v_scope) order by s)),
                 'document_count', (select count(*) from dl where dl.export_id = x.id),
                 'net_total', (select coalesce(sum(dl.amount), 0) from dl where dl.export_id = x.id))
                 order by x.exported_at, x.id)
          from public.xero_sales_exports x left join public.profiles pr on pr.id = x.exported_by
         where x.from_date <= p_to and x.to_date >= p_from
           and (x.covered_store_ids && v_scope or exists (select 1 from dl where dl.export_id = x.id))), '[]'::jsonb),
      'downloads', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'event_kind', l.event_kind, 'event_id', l.event_id, 'document_number', l.document_number,
                 'document_date', l.document_date, 'amount', l.amount, 'exported_at', l.exported_at,
                 'times', l.times) order by l.document_date, l.event_id, l.event_kind)
          from latest l
         where l.document_date between p_from and p_to), '[]'::jsonb),
      'vanished', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'event_kind', l.event_kind, 'event_id', l.event_id, 'document_number', l.document_number,
                 'document_date', l.document_date, 'amount', l.amount, 'exported_at', l.exported_at,
                 'now_date', a.document_date, 'now_amount', a.amount,
                 'moved', a.event_id is not null and not (a.store_id = any(v_scope)),
                 'now_store_id', case when a.event_id is not null and not (a.store_id = any(v_scope))
                                       and public.user_has_store_access(a.store_id) then a.store_id end)
                 order by l.document_date, l.event_id, l.event_kind)
          from latest l
          left join cur c on c.event_kind = l.event_kind and c.event_id = l.event_id
          left join allev a on a.event_kind = l.event_kind and a.event_id = l.event_id
         where l.document_date between p_from and p_to
           and (c.event_id is null or c.document_date not between p_from and p_to)), '[]'::jsonb),
      'missed', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'event_kind', c.event_kind, 'event_id', c.event_id, 'invoice_id', c.invoice_id,
                 'invoice_no', c.invoice_no, 'store_id', c.store_id, 'document_number', c.document_number,
                 'document_date', c.document_date, 'amount', c.amount, 'recorded_at', c.recorded_at,
                 'customer_id', c.customer_id, 'contact_name', cu.full_name, 'contact_email', cu.email,
                 'contact_address', cu.address) order by c.document_date, c.event_id, c.event_kind)
          from cur c
          left join public.customers cu on cu.id = c.customer_id
         where c.document_date not between p_from and p_to
           and c.event_kind in ('receipt', 'correction_replacement', 'correction_reversal', 'refund')
           and not exists (select 1 from dl where dl.event_kind = c.event_kind and dl.event_id = c.event_id)
           and exists (select 1 from ex x
                        where c.document_date between x.from_date and x.to_date
                          and c.store_id = any(x.covered_store_ids))), '[]'::jsonb)));
end $fn$
$def$;

  c_record_def constant text := $def$
create or replace function public.record_xero_sales_export(p_from date, p_to date, p_store_id uuid,
                                                          p_documents jsonb, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_scope uuid[]; v_hash text; v_prev public.xero_sales_exports%rowtype; v_id uuid := gen_random_uuid();
        v_count int; v_keys int; v_blank int; v_lo date; v_hi date; v_bad int; v_first text; v_total numeric;
        v_at timestamptz := now(); v_n int; v_by text; v_when timestamptz;
begin
  -- 411: records what a download held, so the next export can say what is
  -- already in Xero (Owner or Manager). Each document must be one the export
  -- lists now (xero_sales_event_rows) for the stores the download covered,
  -- with the same number, date and amount, or nothing is recorded. A
  -- document dated outside From and To is one entered after its own period
  -- was downloaded and added to this file. A document any earlier download
  -- already holds (for any store) is refused unless the page marks it
  -- "redownload": true, which it does only when the person chose to download
  -- documents already downloaded again: so two exports of the same dates at
  -- the same time, a review left open while someone else downloads, or a
  -- document downloaded for one store before its invoice moved to another,
  -- cannot put the same document in two files unnoticed. Downloads are
  -- recorded one at a time (a transaction lock), so that check and the record
  -- cannot interleave. The same request again returns the same record.
  if not exists (select 1 from public.profiles pr
                  where pr.id = auth.uid() and pr.is_active and pr.deleted_at is null
                    and coalesce(pr.invitation_status, 'accepted') = 'accepted'
                    and pr.role in ('owner', 'manager')) then
    raise exception 'Only an Owner or Manager can export sales for Xero' using errcode = '42501'; end if;
  if p_from is null or p_to is null then raise exception 'Choose a start and an end date'; end if;
  if p_to < p_from then raise exception 'The end date cannot be before the start date'; end if;
  if p_request_id is null then raise exception 'A request ID is required'; end if;
  if jsonb_typeof(p_documents) is distinct from 'array' or jsonb_array_length(p_documents) = 0 then
    raise exception 'A download records at least one document'; end if;
  perform pg_advisory_xact_lock(hashtextextended('xero-sales-export', 0));
  v_hash := md5(jsonb_build_object('from', p_from, 'to', p_to, 'store', p_store_id, 'documents', p_documents)::text);
  select * into v_prev from public.xero_sales_exports where request_id = p_request_id;
  if found then
    if v_prev.request_hash <> v_hash or v_prev.exported_by is distinct from auth.uid() then
      raise exception 'This request ID was already used for a different download'; end if;
    return jsonb_build_object('export_id', v_prev.id, 'exported_at', v_prev.exported_at,
      'document_count', v_prev.document_count, 'net_total', v_prev.net_total, 'replayed', true);
  end if;
  select coalesce(array_agg(s.id order by s.id), '{}'::uuid[]) into v_scope
    from public.stores s
   where public.user_has_store_access(s.id) and (p_store_id is null or s.id = p_store_id);
  if p_store_id is not null and not (p_store_id = any(v_scope)) then
    raise exception 'That store is not accessible'; end if;

  select count(*), count(distinct (d.event_kind, d.event_id)),
         count(*) filter (where d.event_kind is null or d.event_id is null or d.document_number is null
                            or d.document_date is null or d.amount is null),
         least(min(d.document_date), p_from), greatest(max(d.document_date), p_to)
    into v_count, v_keys, v_blank, v_lo, v_hi
    from jsonb_to_recordset(p_documents)
         as d(event_kind text, event_id uuid, document_number text, document_date date, amount numeric);
  if v_blank > 0 then raise exception 'Every document needs its kind, event, number, date and amount'; end if;
  if v_keys <> v_count then raise exception 'A document is listed twice'; end if;

  with d as (
    select * from jsonb_to_recordset(p_documents)
           as d(event_kind text, event_id uuid, document_number text, document_date date, amount numeric)
  ),
  r as materialized (
    select * from public.xero_sales_event_rows(v_lo, v_hi) r
     where r.event_kind in ('receipt', 'correction_replacement', 'correction_reversal', 'refund')
       and r.store_id = any(v_scope)
  )
  select count(*), min(d.document_number) into v_bad, v_first
    from d
   where not exists (select 1 from r
                      where r.event_kind = d.event_kind and r.event_id = d.event_id
                        and r.document_number = d.document_number and r.document_date = d.document_date
                        and r.amount = d.amount);
  if v_bad > 0 then
    raise exception '% document(s) are not what the export lists now (the first: %). Export again.', v_bad, v_first; end if;
  select count(*) into v_bad
    from jsonb_to_recordset(p_documents) as d(event_kind text, event_id uuid, redownload boolean)
   where not coalesce(d.redownload, false)
     and exists (select 1 from public.xero_sales_export_documents x
                  where x.event_kind = d.event_kind and x.event_id = d.event_id);
  if v_bad > 0 then
    select d.document_number, coalesce(pr.full_name, 'someone'), x.exported_at into v_first, v_by, v_when
      from jsonb_to_recordset(p_documents) as d(event_kind text, event_id uuid, document_number text, redownload boolean)
      join public.xero_sales_export_documents xd on xd.event_kind = d.event_kind and xd.event_id = d.event_id
      join public.xero_sales_exports x on x.id = xd.export_id
      left join public.profiles pr on pr.id = x.exported_by
     where not coalesce(d.redownload, false)
     order by x.exported_at desc, d.document_number
     limit 1;
    raise exception '% document(s) in this file were downloaded already (the latest: %, by % on %). Nothing was recorded or downloaded. Export again to see what is new.',
      v_bad, v_first, v_by, to_char(v_when at time zone 'Asia/Singapore', 'FMDD Mon YYYY, HH24:MI'); end if;

  insert into public.xero_sales_exports(id, request_id, request_hash, exported_at, exported_by, from_date, to_date,
                                        store_id, covered_store_ids, document_count, net_total)
  values (v_id, p_request_id, v_hash, v_at, auth.uid(), p_from, p_to, p_store_id, v_scope, v_count, 0);
  insert into public.xero_sales_export_documents(export_id, event_kind, event_id, invoice_id, store_id,
                                                 document_number, document_date, amount)
  select v_id, r.event_kind, r.event_id, r.invoice_id, r.store_id, r.document_number, r.document_date, r.amount
    from jsonb_to_recordset(p_documents) as d(event_kind text, event_id uuid)
    join public.xero_sales_event_rows(v_lo, v_hi) r on r.event_kind = d.event_kind and r.event_id = d.event_id;
  get diagnostics v_n = row_count;
  if v_n <> v_count then raise exception 'The download could not be recorded exactly (% of % documents)', v_n, v_count; end if;
  select sum(amount) into v_total from public.xero_sales_export_documents where export_id = v_id;
  update public.xero_sales_exports set net_total = v_total where id = v_id;
  return jsonb_build_object('export_id', v_id, 'exported_at', v_at, 'document_count', v_count, 'net_total', v_total);
end $fn$
$def$;

  c_rows_after constant text := '18858e023c44d06814e617299456084b';
  c_events_after constant text := '0e74090dce71966dfd9542c2c4a46fb2';
  c_review_after constant text := '2a89b9c2fbd81ec05bb0315eccbc80dc';
  c_record_after constant text := '1979c940c92255e15e9490395d044063';
  c_exports_shape constant text := '274075a74ecbc3aa34b286b0b7a37419';
  c_docs_shape constant text := '4b4150b80cad616d17b35bb6c15ea2e7';

  v_path text := current_setting('search_path');
  r record; v text; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}';
  v_new_exports boolean := false; v_new_docs boolean := false;
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing is created unless all pass ─────────────────────────────
  -- The tables: missing, or exactly this shape (a re-run leaves them alone).
  for r in select * from (values ('xero_sales_exports', c_exports_shape), ('xero_sales_export_documents', c_docs_shape)) x(t, shape)
  loop
    if to_regclass('public.' || r.t) is null then
      if r.t = 'xero_sales_exports' then v_new_exports := true; else v_new_docs := true; end if;
      continue;
    end if;
    select md5(string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull::text, ',' order by a.attnum))
      into v from pg_attribute a where a.attrelid = ('public.' || r.t)::regclass and a.attnum > 0 and not a.attisdropped;
    if v <> r.shape then
      raise exception '411: public.% already exists with another shape (md5 %)', r.t, v; end if;
  end loop;
  if v_new_exports <> v_new_docs then
    raise exception '411: only one of xero_sales_exports and xero_sales_export_documents exists'; end if;
  -- The functions: missing, or already this version.
  for r in select * from (values
    ('xero_sales_event_rows(date,date)', c_rows_after, c_rows_def),
    ('xero_sales_events(date,date,uuid)', c_events_after, c_events_def),
    ('xero_sales_export_review(date,date,uuid)', c_review_after, c_review_def),
    ('record_xero_sales_export(date,date,uuid,jsonb,uuid)', c_record_after, c_record_def)
  ) x(fn, after_md5, whole)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      v_fns := v_fns || r.fn;
      v_defs := v_defs || r.whole;
      continue;
    end if;
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v = r.after_md5 then
      raise notice '411: public.% is already this version; left alone', r.fn;
      continue;
    end if;
    raise exception '411: public.% already exists with another text (md5 %). Re-read it and re-test before applying.', r.fn, v;
  end loop;
  -- Relied on, not changed: the versions read on 9 Oct 2026 (the payment's
  -- date, as the Sales report gives it; who sees which store).
  for r in select * from (values
    ('payment_sales_date(timestamp with time zone,timestamp with time zone)', '3e5161e4830f5f6fdc8f34a24266fdc9'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '411: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- Payments are of the three kinds read on 9 Oct 2026; a new kind needs a
  -- rule for its date and sign.
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.invoice_payments'::regclass and c.conname = 'invoice_payments_entry_kind_check')
     is distinct from 'CHECK ((entry_kind = ANY (ARRAY[''receipt''::text, ''correction_reversal''::text, ''correction_replacement''::text])))' then
    raise exception '411: invoice_payments.entry_kind is not limited to the three kinds read on 9 Oct 2026'; end if;
  -- No other function takes these names (the API picks an overload by name).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('xero_sales_event_rows', 'xero_sales_events', 'xero_sales_export_review', 'record_xero_sales_export')
              and p.oid::regprocedure::text not in ('xero_sales_event_rows(date,date)', 'xero_sales_events(date,date,uuid)',
                                                    'xero_sales_export_review(date,date,uuid)',
                                                    'record_xero_sales_export(date,date,uuid,jsonb,uuid)')) then
    raise exception '411: another overload of xero_sales_event_rows, xero_sales_events, xero_sales_export_review or record_xero_sales_export exists'; end if;

  -- ── Create: the tables, then the rule, then what reads it ─────────────────
  if v_new_exports then
    execute c_exports_ddl;
    execute c_docs_ddl;
    create index xero_sales_export_documents_event_idx on public.xero_sales_export_documents(event_kind, event_id);
    create index xero_sales_export_documents_date_idx on public.xero_sales_export_documents(document_date);
    alter table public.xero_sales_exports enable row level security;
    alter table public.xero_sales_export_documents enable row level security;
    revoke all on table public.xero_sales_exports, public.xero_sales_export_documents from public, anon, authenticated;
    grant all on table public.xero_sales_exports, public.xero_sales_export_documents to service_role;
    comment on table public.xero_sales_exports is
      '411: one row per Xero sales export download (record_xero_sales_export). Closed to clients.';
    comment on table public.xero_sales_export_documents is
      '411: the documents each Xero sales export download held. Closed to clients.';
  end if;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
    if v_fns[i] = 'xero_sales_event_rows(date,date)' then
      revoke all on function public.xero_sales_event_rows(date, date) from public, anon, authenticated;
      grant execute on function public.xero_sales_event_rows(date, date) to service_role;
    else
      execute format('revoke all on function public.%s from public, anon', v_fns[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', v_fns[i]);
    end if;
  end loop;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('xero_sales_event_rows(date,date)', c_rows_after),
    ('xero_sales_events(date,date,uuid)', c_events_after),
    ('xero_sales_export_review(date,date,uuid)', c_review_after),
    ('record_xero_sales_export(date,date,uuid,jsonb,uuid)', c_record_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  for r in select * from (values ('xero_sales_exports', c_exports_shape), ('xero_sales_export_documents', c_docs_shape)) x(t, shape)
  loop
    select md5(string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull::text, ',' order by a.attnum))
      into v from pg_attribute a where a.attrelid = ('public.' || r.t)::regclass and a.attnum > 0 and not a.attisdropped;
    if v <> r.shape then
      v_bad := concat_ws('; ', v_bad, r.t || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '411: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The grants: the rule is the service role's alone; the three the page
  -- calls are signed-in logins' (each checks who is asking) and the service
  -- role's; none is callable signed out or by PUBLIC.
  if has_function_privilege('anon', 'public.xero_sales_event_rows(date,date)', 'execute')
     or has_function_privilege('authenticated', 'public.xero_sales_event_rows(date,date)', 'execute')
     or not has_function_privilege('service_role', 'public.xero_sales_event_rows(date,date)', 'execute') then
    raise exception '411: public.xero_sales_event_rows(date,date) is not the service role''s alone'; end if;
  foreach v in array array['xero_sales_events(date,date,uuid)', 'xero_sales_export_review(date,date,uuid)',
                           'record_xero_sales_export(date,date,uuid,jsonb,uuid)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '411: public.% is not signed-in logins'' and the service role''s alone', v; end if;
  end loop;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
              where p.pronamespace = 'public'::regnamespace and a.grantee = 0
                and p.proname in ('xero_sales_event_rows', 'xero_sales_events', 'xero_sales_export_review', 'record_xero_sales_export')) then
    raise exception '411: a new function is granted to PUBLIC'; end if;
  -- The tables: RLS on, nothing for anon or authenticated.
  foreach v in array array['xero_sales_exports', 'xero_sales_export_documents'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || v)::regclass)
       or has_table_privilege('anon', 'public.' || v, 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege('authenticated', 'public.' || v, 'select,insert,update,delete,truncate,references,trigger') then
      raise exception '411: public.% is not closed to clients', v; end if;
  end loop;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
