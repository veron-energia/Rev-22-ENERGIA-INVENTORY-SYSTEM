begin;
-- =====================================================================
-- THE FIVE-DAY RULE RESTS ON created_at, SO created_at IS NOW PROTECTED
--
-- 295 measures the refund window from invoices.created_at, and the
-- documentation claimed the window could not be restarted "because the column
-- cannot be moved". That was not true. Checked directly:
--
--   triggers protecting invoices.created_at        0
--   functions writing invoices.created_at          0
--   RLS update policies on invoices                none
--   a plain UPDATE moving it                       succeeded
--
-- What WAS true is the weaker, useful half: no application code writes it, so
-- correcting an invoice, backdating or recovering its business date, and
-- reopening it all leave it alone. The claim of immutability was not earned.
--
-- This earns it for every route the application can take. Changing created_at
-- is refused for ordinary database roles -- which is all the application ever
-- uses -- while a superuser connection (a DBA at the console, and the test
-- fixtures that must age an invoice to exercise the boundary) may still do it,
-- deliberately and visibly.
--
-- Requires 295. Idempotent.
-- =====================================================================
create or replace function public.guard_invoice_created_at()
returns trigger language plpgsql as $$
begin
 if new.created_at is distinct from old.created_at then
  -- A superuser is a person at the database, not the application. Everything
  -- the app does runs as authenticated/anon/service_role and is refused.
  if current_setting('is_superuser')<>'on' then
   raise exception 'An invoice''s creation time cannot be changed: the refund and cancellation window is measured from it. Correct the invoice''s business date instead, which does not move the window.';
  end if;
 end if;
 return new;
end $$;

drop trigger if exists invoice_created_at_immutable on public.invoices;
create trigger invoice_created_at_immutable
  before update of created_at on public.invoices
  for each row execute function public.guard_invoice_created_at();

notify pgrst,'reload schema';
commit;
