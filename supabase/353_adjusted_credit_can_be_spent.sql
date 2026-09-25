-- 353_adjusted_credit_can_be_spent.sql
--
-- WHAT WAS WRONG
--
-- Credit added with the customer's "Adjust" button appeared in the customer
-- View but could not be spent. Paying with it failed with
--
--     Only 0 of the requested 60.00 could be funded by eligible credit
--
-- while credit added as an "Opening balance" spent normally.
--
-- adjust_customer_credit was never the problem: it inserts the lot with
-- remaining_amount = original_amount, exactly as it should. The problem is the
-- spending policy. Migration 242 made every lot declare, by its source, what it
-- may pay for, and credit_lot_policy() lists by hand the sources that are
-- unrestricted ('open'). That list has 'adjustment' in it — but the Adjust
-- button stamps its lots 'manual_adjustment'. An unrecognised source falls
-- through to 'needs_review' on purpose, so that nothing unknown is ever treated
-- as unrestricted; the side effect was that every manual adjustment ever made
-- was refused at the till. Opening balance stamps 'manual_legacy', which IS on
-- the list, which is why it worked.
--
-- The customer View and the payment dropdown read customer_credit_balances,
-- which sums balances without asking the policy, so staff saw the money and
-- were told nothing about why it would not pay.
--
-- WHAT STAFF HAD TO DO ABOUT IT
--
-- On 23 Sep 2026 a manager adjusted a customer up by $1,000 and $636, found it
-- would not spend, re-issued the same $1,636 as an opening balance, spent that,
-- and then adjusted the first two back down so the customer was not credited
-- twice. Those two lots are at 0.00 on purpose and this migration does NOT
-- restore them: restoring them would hand the customer $1,636 a manager removed.
--
-- Production had $0 sitting in this state when this was written, so nothing is
-- unstuck by it retroactively — it stops the next adjustment going the same way.
--
-- ALSO FIXED HERE: A SILENT LEDGER MISMATCH ON DECREASE
--
-- A decrease checks the available balance, writes the ledger entry for the full
-- amount, and only then locks the lots and draws from them. If a sale spends the
-- same credit in between, the draw comes up short but the ledger entry still
-- says the full amount, and nothing complains. It now raises, so the whole
-- adjustment rolls back and can simply be retried.
--
-- ALSO FIXED HERE: THE CUSTOMER VIEW'S RUNNING BALANCE
--
-- Once adjusted credit can be spent it can also be refunded, and the View's
-- statement then went wrong: it subtracted every 'reverse' ledger entry, but a
-- refund, a payment correction, a reopened invoice and a special-sale or rental
-- refund write 'reverse' when credit goes BACK to the customer. Adjust +100,
-- spend 60, refund the invoice: the lot and the header said 100.00 while the
-- statement's running balance read -20.00. Opening-balance credit had the same
-- problem since the refund ledger was added. Those entries now show as credit
-- returned; a real reversal (reverse_credit_lot, the 328 provenance repair)
-- still subtracts, and so does any source not named here.
--
-- DELIBERATELY NOT CHANGED
--
-- Which credit a decrease removes first. Today it draws oldest-first across all
-- credit of that category, so a decrease meant to undo an adjustment can eat a
-- customer's purchased package credit first. Changing that is a business choice,
-- not a bug fix, and is left for the owner.

-- Plain SQL: applies through the Supabase migration tool or the SQL editor as one
-- transaction. From psql, run with -v ON_ERROR_STOP=1.
set lock_timeout = '5s';

-- ── 1. manual adjustments are spendable, exactly like opening balances ───────
do $mig$
declare
  fn  regprocedure := 'public.credit_lot_policy(text,text,boolean)'::regprocedure;
  def text; n int;
  c_anchor constant text := $a$when p_source_type in ('manual','manual_legacy','manual_use','exchange',$a$;
  c_repl   constant text := $a$when p_source_type in ('manual','manual_legacy','manual_adjustment','manual_use','exchange',$a$;
begin
  def := pg_get_functiondef(fn);
  if position($a$'manual_adjustment'$a$ in def) > 0 then
    raise notice '353: credit_lot_policy already recognises manual_adjustment; left alone.';
  else
    n := (length(def) - length(replace(def, c_anchor, ''))) / length(c_anchor);
    if n <> 1 then
      raise exception '353: credit_lot_policy anchor found % times, expected 1', n; end if;
    execute replace(def, c_anchor, c_repl);
  end if;

  -- Behavioural post-conditions: what every source resolves to afterwards.
  -- Asserting on behaviour rather than text, because a text check once passed
  -- here while a refund-breaking bug went through.
  if public.credit_lot_policy('manual_adjustment','paid',false)  <> 'open'
  or public.credit_lot_policy('manual_adjustment','bonus',false) <> 'open' then
    raise exception '353: manual_adjustment is still not spendable'; end if;
  if public.credit_lot_policy('manual_legacy','legacy',false)          <> 'open'
  or public.credit_lot_policy('credit_package','paid',false)           <> 'needs_review'
  or public.credit_lot_policy('premium_bundle','paid',false)           <> 'needs_review'
  or public.credit_lot_policy('credit_package','paid',true)            <> 'package_paid'
  or public.credit_lot_policy('credit_package','bonus',true)           <> 'package_bonus'
  or public.credit_lot_policy('premium_bundle','bonus',true)           <> 'bundle_any'
  or public.credit_lot_policy('credit_package_progress','paid',true)   <> 'needs_review'
  or public.credit_lot_policy('invoice_benefit_transfer','paid',true)  <> 'needs_review'
  or public.credit_lot_policy('something_unheard_of','paid',true)      <> 'needs_review' then
    raise exception '353: the change moved the policy of some other source'; end if;
  -- An unrecognised source must still never become unrestricted.
  if (select provolatile from pg_proc where oid = fn) <> 'i' then
    raise exception '353: credit_lot_policy is no longer immutable'; end if;
end $mig$;

-- ── 2. a decrease that comes up short rolls back instead of lying ────────────
do $mig$
declare
  fn  regprocedure := 'public.adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid)'::regprocedure;
  def text; n int;
  c_anchor constant text := $a$    end loop;
  end if;

  insert into public.customer_credit_adjustments ($a$;
  c_repl constant text := $a$    end loop;
    -- 353: the balance was checked before the lots were locked. If a sale spent
    -- some of it in between, the ledger entry above already records the full
    -- amount, so stop rather than leave the ledger and the lots disagreeing.
    if v_take > 0 then
      raise exception 'The % credit balance changed while it was being adjusted; nothing was changed. Please try again.', p_category;
    end if;
  end if;

  insert into public.customer_credit_adjustments ($a$;
begin
  def := pg_get_functiondef(fn);
  if position('changed while it was being adjusted' in def) > 0 then
    raise notice '353: adjust_customer_credit already guards its decrease; left alone.'; return;
  end if;
  n := (length(def) - length(replace(def, c_anchor, ''))) / length(c_anchor);
  if n <> 1 then
    raise exception '353: adjust_customer_credit anchor found % times, expected 1', n; end if;
  execute replace(def, c_anchor, c_repl);
end $mig$;

-- ── 3. the statement shows returned credit as returned ──────────────────────
do $mig$
declare v_md5 text;
begin
  v_md5 := md5(pg_get_functiondef('public.customer_credit_statement(uuid,date,date)'::regprocedure));
  if position('353:' in pg_get_functiondef('public.customer_credit_statement(uuid,date,date)'::regprocedure)) > 0 then
    raise notice '353: customer_credit_statement already shows returned credit; left alone.'; return; end if;
  if v_md5 <> '9b0ff0710aa80bfc1e366cdac44f75fc' then
    raise exception '353: customer_credit_statement is not the version this was tested against (md5 %)', v_md5; end if;
  execute $f$
create or replace function public.customer_credit_statement(p_customer_id uuid, p_from date default null, p_to date default null)
returns table(entry_seq bigint, entry_date date, created_at timestamp with time zone, description text, source text,
              category text, credit_added numeric, credit_used numeric, credit_reversed numeric, lot_remaining numeric,
              wallet_balance numeric, reference_no text, note text)
language plpgsql stable security definer set search_path to 'public' as $body$
#variable_conflict use_column
-- 353: a 'reverse' entry that puts credit back (refund, payment correction,
-- reopen, special-sale/rental refund) adds to the balance; a real reversal subtracts.
declare v_run numeric := 0; v_e record; v_returned boolean;
begin
  if not public.can_view_customer_credit() then
    raise exception 'You do not have access to customer credit';
  end if;
  for v_e in
    select e.*,
           case e.entry_type
             when 'grant' then 'Credit added'
             when 'adjust_increase' then 'Adjustment — increase'
             when 'use' then 'Credit used'
             when 'adjust_decrease' then 'Adjustment — decrease'
             when 'reverse' then case when e.source_type in ('invoice_payment_refund','payment_correction','invoice_reopen','special_sale','rental')
                                      then 'Credit returned' else 'Credit reversed' end
           end as descr
      from public.customer_credit_ledger e
     where e.customer_id = p_customer_id
       and (p_from is null or e.effective_date >= p_from)
       and (p_to is null or e.effective_date <= p_to)
     order by e.effective_date, e.entry_seq
  loop
    v_returned := v_e.entry_type = 'reverse'
      and v_e.source_type in ('invoice_payment_refund','payment_correction','invoice_reopen','special_sale','rental');
    if v_e.entry_type in ('grant','adjust_increase') or v_returned then
      v_run := v_run + v_e.amount;
    else
      v_run := v_run - v_e.amount;
    end if;
    return query select
      v_e.entry_seq, v_e.effective_date, v_e.created_at,
      v_e.descr || coalesce(' — ' || v_e.reason, ''),
      v_e.source_type, v_e.category,
      case when v_e.entry_type in ('grant','adjust_increase') or v_returned then v_e.amount else null end,
      case when v_e.entry_type in ('use','adjust_decrease') then v_e.amount else null end,
      case when v_e.entry_type = 'reverse' and not v_returned then v_e.amount else null end,
      (select l.remaining_amount from public.customer_credit_lots l where l.id = v_e.lot_id),
      round(v_run,2), v_e.reference_no, v_e.note;
  end loop;
end $body$;
$f$;
end $mig$;

notify pgrst, 'reload schema';
