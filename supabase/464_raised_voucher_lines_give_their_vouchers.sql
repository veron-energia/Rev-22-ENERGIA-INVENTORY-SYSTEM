-- 464_raised_voucher_lines_give_their_vouchers.sql
--
-- A VOUCHER LINE RAISED OR ADDED BY A CORRECTION ON A PAID INVOICE GIVES ITS
-- EXTRA VOUCHERS, ONCE (457's NOT COVERED: "on an invoice already paid, a
-- voucher line raised by a correction takes the extra unit ... but gives no
-- extra voucher")
--
-- WHAT WAS WRONG / WHY
--
--   Vouchers sold on an invoice are given when it is paid in full (or
--   completed FOC): trg_issue_sold_vouchers_on_paid runs when the invoice's
--   status turns paid (or completed FOC) from anything else, and calls
--   issue_sold_vouchers_for_invoice, which gives each voucher line its
--   vouchers once: it skips a line that has given a voucher before (a sale
--   voucher, source 'invoice_voucher_sale', names the line). A unique index
--   (customer_reward_vouchers_issued_once, 344) holds one sale voucher per
--   line and voucher. So a correction on an invoice already paid:
--   * that raises a voucher line and leaves the invoice paid (the total still
--     covered, say a lower price) gives nothing: the status does not change,
--     so the trigger does not run. With a product on the invoice, the save
--     puts its stock back and takes it again (restore_invoice_stock,
--     deduct_invoice_stock), which takes the extra voucher units: out of
--     stock, never given. A voucher-only invoice takes nothing and gives
--     nothing;
--   * that adds a voucher line and leaves the invoice paid: the same (its
--     units out with a product on the invoice, no voucher);
--   * that raises a voucher line and leaves the invoice part-paid (the total
--     up): 457 keeps no voucher stock for it until the payment; the payment
--     that settles it takes the extra units and the trigger runs, but the
--     issuer skips the raised line. Out of stock, never given. (A line added
--     in such a save is given at that payment: it gave nothing before.)
--   The same holds for a line raised while a refund or cancellation request
--   waits on the invoice (the invoice is paid again when the request is
--   rejected) and for one raised on a cancelled invoice that is reopened and
--   paid (the reopening gives again only what the cancel took back).
--   Reproduced on a copy of production (made-up records, 24 Oct 2026): a
--   voucher-only invoice, S$90 for one voucher, paid, raised to two (S$180,
--   part paid), paid in full: two units out, one voucher held; socks and a
--   voucher, paid S$190, the voucher raised to two at S$45 (still paid): the
--   extra unit taken at the save, one voucher held; then a free voucher line
--   added (still paid): its unit taken, no voucher. A cancel gives back what
--   is out (both units), as 457 found.
--
-- PRODUCTION (read only, 24 Oct 2026): no invoice has been hit. Every voucher
--   line that has given vouchers holds no more units than it gave, and no
--   voucher line's quantity has changed in any correction. (Eight paid voucher
--   lines never gave a voucher: all from 1 Aug to 2 Sep 2026, before sold
--   vouchers were first given on 14 Sep 2026, unlimited vouchers, none on an
--   invoice changed since its payment; untouched here.) No promotion line has
--   ever held a voucher pick. Nothing to back-fill.
--
-- THE RULES (as the app already gives vouchers; 457's NOT COVERED, to raise
-- with the Owner)
--
--   * A voucher line gives as many vouchers as its quantity, when the invoice
--     is paid in full (or completed FOC). Units a correction adds to a line,
--     or a line it adds, after the invoice's vouchers were given, are given
--     too: at the save when it leaves the invoice paid, else at the payment
--     that settles it again. Their stock is taken once.
--   * Nothing is given twice. What a line has given counts however each
--     voucher ended: used, refunded, moved to another customer or store,
--     taken back by a cancel (and given again by its reopening) or by taking
--     an FOC off (and given again at the payment, 416). So a later payment, a
--     reopening, a cancel, a refund or a customer change gives nothing more.
--   * Each unit of a voucher line is worth its share of what the line
--     charges (what a refund of it can pay back): the units given here, and,
--     when units are added, the line's earlier vouchers still held whole. A
--     correction that raises a line and keeps the invoice paid lowers the
--     price (or the other lines), so the earlier vouchers' value, recorded
--     when they were given, would be more than their share: a refund of one
--     of them could pay back the whole line while the customer kept the one
--     given here. (Before 464 the line held one voucher, so it did not
--     matter.) This is a choice for the Owner to confirm.
--   * Kept: a correction that keeps an invoice completed FOC gives no more
--     vouchers (416).
--
-- WHAT THIS DOES
--
--   1. customer_reward_vouchers gets a column issue_no (integer, not null,
--      default 1, at least 1): which of a line's sales of its voucher this
--      is. Every voucher there is now, and every one the app gives, is 1;
--      this file's function gives 2, 3, ... The unique index
--      customer_reward_vouchers_issued_once becomes (source_type, source_id,
--      voucher_id, issue_no), same name, same condition: still one sale per
--      line, voucher and issue, so the issuers still cannot give a line twice
--      (their own check and the index), and a line can be given more.
--   2. New: give_raised_voucher_units(p_invoice_id, p_lines, p_take_stock,
--      p_reason) (the server's alone). For each voucher line of the invoice
--      (or those named): what it lacks is its units less what it has given,
--      counted along each of its vouchers' chains as cancel_invoice_recorded
--      counts what an invoice issued (granted, less what a reopening gave
--      again in its place or a transfer moved on), any voucher of the line,
--      whatever its status. What it lacks is given as one more sale of the
--      line ('invoice_voucher_sale', the line's id, the next issue_no), held
--      by the invoice's customer at its store, worth that share of what the
--      line now charges ('Issued for units added to the line after its
--      vouchers were given'); a therapy voucher gets its rights recorded as
--      any new sale's. With p_take_stock, a limited voucher's units the
--      invoice's movement rows do not hold yet (invoice_stock_to_deduct,
--      net) are taken from the invoice's store, never more than it gives,
--      with a row ('Voucher units added after the vouchers were given: ...');
--      a store short refuses in words ('Not enough stock of the voucher "..."
--      in this store: 0 left, 1 needed.', 416's words). The line's earlier
--      vouchers still held whole (held, none of their units refunded, given
--      again or moved) are valued at their share of what the line now
--      charges (invoice_benefit_values.paid_value; a voucher with a unit
--      refunded, given again or moved keeps its value). One audit row,
--      'voucher_units_added_given', lists what was given and each value
--      changed (from, to).
--   3. correct_invoice(uuid,jsonb,jsonb,text,uuid) (458's text): a save that
--      changes the lines and leaves an invoice paid that was paid (or
--      completed FOC) before it gives the voucher lines it raised or added
--      what they lack, taking their stock where no row holds it (the
--      voucher-only invoice). Two anchors (the declare section; before 416's
--      FOC take-back, after 416's settling block).
--   4. trg_issue_sold_vouchers_on_paid(): when an invoice is settled, after
--      the issuers and 416's giving again, every voucher line gives what it
--      still lacks (so the raised line, once); settled as paid, it takes the
--      stock no row holds (none after a payment, which took it; an invoice
--      paid again when a request is rejected may lack it); completed as FOC,
--      what settled it took the stock with no row, so it takes none. One
--      anchor.
--
-- NOT CHANGED
--
--   * issue_sold_vouchers_for_invoice and issue_promotion_vouchers_for_
--     invoice (they still give a line once, skip a line that gave before,
--     and give issue 1), cancel_invoice_recorded (its count of what an
--     invoice issued already counts every voucher of a line, so a cancel
--     gives back exactly the units out), refund_invoice_recorded, reopen_
--     invoice, apply_reopened_invoice_vouchers, invoice_own_voucher_ids (a
--     voucher this file gives names the line, so a customer change that
--     takes the benefits moves it with the others), invoice_voucher_stock_
--     unrecorded (it counts it as first given), deduct_invoice_stock,
--     invoice_stock_to_deduct, record_invoice_payment, update_invoice_
--     internal, preview_invoice_correction, every other function, every other
--     table, column, index, policy and grant; customer_reward_vouchers keeps
--     its grants and policies. No row is changed by the apply (every voucher
--     there is gets issue_no 1); the function changes a line's earlier
--     voucher values only when it gives that line more units.
--   * Everything else correct_invoice and the trigger do, word for word.
--
-- NOT COVERED (to tell the owner)
--
--   * Lowering a voucher line on a paid invoice still takes nothing back:
--     the customer keeps the vouchers given and their stock stays out (as
--     before; refund or cancel them). Raising it again later gives nothing
--     until the line holds more units than it has given.
--   * Changing a line's voucher (A to B) on a paid invoice at the same
--     quantity still gives no B (the customer keeps A; as before). Raised in
--     the same save, the extra units are given as B.
--   * A promotion's voucher picks raised or added on a paid invoice are still
--     not given (issue_promotion_vouchers_for_invoice gives a pick once).
--     Production has never had one.
--   * A correction that makes a paid invoice completed FOC and raises a
--     voucher line gives nothing more for it (rare; 416's FOC rules).
--   * A line whose vouchers the FOC removal took back in a save that also
--     lowered it counts those units as given: raised again on the paid
--     invoice, it gives only above the old count.
--   * A voucher of the line with a unit refunded, given again or moved keeps
--     the value recorded when it was given; and a correction that changes a
--     voucher line's price and adds no units changes no voucher's value (as
--     before: the line's refund total is still capped at what it charges).
--   * The correction summary (Preview) does not list the vouchers a save will
--     give, nor check the voucher stock it takes on a voucher-only paid
--     invoice: a store short of it refuses at Save, in words.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (460, 461, 456, 457, 458 in: ebee207bfe916c8b32d71cf366ca30a4,
--   1378 functions) -> 464 (this file).
--   * Another session holds 462 and 463 (cancel_invoice_recorded's credit
--     take-back, refund options, 448's invoice_benefit_unused_elsewhere /
--     cancelled_invoice_used_value, merge and move-benefit functions). This
--     file changes none of those. It pins cancel_invoice_recorded,
--     invoice_own_voucher_ids and apply_reopened_invoice_vouchers as relied
--     on: if 462 or 463 goes first and changes one, this file refuses, naming
--     it, and changes nothing: re-read it, re-check that it still counts a
--     line's vouchers as this file does (cancel), recognises a voucher by its
--     line (own ids) and gives again only what was taken back (reopen),
--     re-pin, re-test. If either changes correct_invoice or
--     trg_issue_sold_vouchers_on_paid, the same for this file's BEFORE (and
--     the anchors). If this file goes first, they take its AFTERs.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("already this version; left alone" for the three functions,
--      "the table is already this version").
--   2. Apply (the MCP's apply_migration with this text verbatim, or the CLI).
--      It checks itself and runs its self-test.
--   3. No page change: the Invoices page already sends what a correction
--      needs and shows the vouchers a customer holds.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production now (24 Oct
--     2026, on a copy of it), and the two triggers: issue_sold_vouchers_on_
--     paid (after update, each row) and invoice_reopen_vouchers_settled
--     (after update of status), which fires first (by name), so a reopening
--     has given again what it gives before the trigger counts what a line
--     lacks; the columns it reads and writes are there with these types;
--   * customer_reward_vouchers is as read (no issue_no column, the index as
--     344 made it) or this file's (left alone); nothing in between;
--   * each patched function is its BEFORE (patched; each anchor found once;
--     the text built has the tested AFTER md5) or its AFTER (left alone); the
--     new function is not there (made) or this version (left alone); no other
--     function takes their names;
--   * afterwards: the md5s are the AFTER ones; correct_invoice and the
--     trigger function keep their grants (compared as sets), correct_invoice
--     stays callable by signed-in staff and the service role, never anon, and
--     still reads the invoice for update and checks store access first; the
--     new function is the server's alone (service role, never signed-in staff
--     or anon); the table keeps its grants and policies, every voucher has
--     issue_no 1, and the index is the new one, unique;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0464, so it leaves no row): a made-up Owner, store, payment method,
--     buyer (an ACMA fictional phone no customer has) and S$90 limited
--     voucher, five in stock, no product (so no stock-history row and no
--     sequence is used; invoice numbers are counted, not drawn from a
--     sequence). One voucher, paid: one held, 4 left. Raised to two at S$45
--     (still paid): two held (issue 1 and 2, each worth S$45, the first was
--     S$90), 3 left. A note changed: nothing more. Raised to three (S$135,
--     part paid): still two, 3 left. Paid in full: three held (S$45 each),
--     2 left. Cancelled: none held, 5.
--   Locks: customer_reward_vouchers (access exclusive, for the column and the
--   index, to the end of the apply: giving or reading vouchers waits that
--   long), the three functions' catalogue rows, and the self-test's own rows.
--   The whole apply took 0.28 s on a copy of production with no business rows
--   (24 Oct 2026); production holds a few dozen vouchers.
--   A correction or payment running at that moment finishes first or waits
--   (the lock timeout gives up after 5 s and changes nothing).
--
-- BEFORE (production now, read on a copy of it, 24 Oct 2026; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    af9451fa15c2cf790edd70f799bae336  (458's AFTER)
--   trg_issue_sold_vouchers_on_paid()                              c840d0d2754e7a8e889848ea8269a293  (as at 416)
--   customer_reward_vouchers_issued_once: (source_type, source_id, voucher_id), 344
--   relied on, not changed
--   issue_sold_vouchers_for_invoice(uuid)                          0dbb4bc74411b6d4f0535f661a8c09ee
--   issue_promotion_vouchers_for_invoice(uuid)                     e47e5f623b1fa3f6eafe83086f0c9776
--   cancel_invoice_recorded(uuid,text,uuid)                        de52d9dbaef8ab15163bef35cb9d733d
--   apply_reopened_invoice_vouchers()                              28d3b7a69b91ddebcdb200559d96a0ef
--   invoice_own_voucher_ids(uuid)                                  9340840f1ce4e031ec3613198688ba2e
--   invoice_voucher_stock_unrecorded(uuid,boolean)                 91c8f0fa69ef6337f323b7ac467a8c2b
--   invoice_stock_to_deduct(uuid)                                  6356494ccb8545d46c56b788f8f85f54
--   invoice_required_stock(uuid)                                   c91dc1eb4f2b7b465de5fe4a8fb2ca0c
--   deduct_invoice_stock(uuid,text)                                32183fe9e7c15ed0b11307c48289831a
--   invoice_discounted_line_value(uuid)                            ead4a430c3abd1e3f953912867ca4fe6
--   snapshot_therapy_voucher_issue(uuid,boolean)                   12ba32611ad001781862d82b1ae13c8e
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) 1f034561a461bdb46a1e6274e0d04606
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   invoice_record_payments_internal(uuid,jsonb)                   21890d84bcb0b9c00a2bc98aff313d0b
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)             770ee0129b0e9fe909259ad7ea95b8d0  (the self-test)
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   public function fingerprint, production now                    ebee207bfe916c8b32d71cf366ca30a4 (1378 functions)
-- AFTER (for later guards)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    04d647e13e9424a9375942e5812e91a2
--   trg_issue_sold_vouchers_on_paid()                              cf0b5610b77edfea2683751d5c25ca1d
--   give_raised_voucher_units(uuid,uuid[],boolean,text)            84d4c7bbd39a754d61cbe4f778777a33  (new)
--   customer_reward_vouchers_issued_once: (source_type, source_id, voucher_id, issue_no)
--   public function fingerprint, worked out on a copy of production (24 Oct 2026):
--     production now -> 464 (a second run the same)                432fcb994b57ee8144e8d7e608114a72 (1379 functions: one added)
--
-- Test: scripts/invoices/tests/raised-voucher-lines-464.sql (begin ...
-- rollback; it installs this file twice, or -v skip_install=1 where it is
-- installed). Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The two patched functions: BEFORE (production now) and AFTER md5s ══
  c_sigs constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'trg_issue_sold_vouchers_on_paid()'];
  c_before constant text[] := array[
    'af9451fa15c2cf790edd70f799bae336',
    'c840d0d2754e7a8e889848ea8269a293'];
  c_after constant text[] := array[
    '04d647e13e9424a9375942e5812e91a2',
    'cf0b5610b77edfea2683751d5c25ca1d'];
  -- each anchor (found once in its function's BEFORE text), the function it
  -- is in (an index into c_sigs) and its patch, in order
  c_fn constant int[] := array[1, 1, 2];
  c_anchor constant text[] := array[
$a1$ v458_rentals jsonb := '[]'::jsonb;  -- 458: what this correction did to the invoice's rentals
$a1$,
$a2$ -- 416: a correction that takes the FOC off a completed FOC invoice (it is
$a2$,
$a3$      jsonb_build_object('records', n, 'invoice_no', new.invoice_no), 'invoices', null, new.store_id);
   end if;
  end if;
 end if;
 return null;
$a3$];
  c_patch constant text[] := array[
$p1$ v458_rentals jsonb := '[]'::jsonb;  -- 458: what this correction did to the invoice's rentals
 v464_lines uuid[];  -- 464: the voucher lines this save raised or added
$p1$,
$p2$ -- 464: a save that changes the lines and leaves the invoice paid, as it
 -- was (or completed FOC before), gives the voucher lines it raised or added
 -- the vouchers they now lack, as the payment that settles an invoice gives a
 -- line's vouchers. The status does not turn paid here, so
 -- trg_issue_sold_vouchers_on_paid does not run: before 464 the extra units
 -- were taken from stock (with a product on the invoice, above) and never
 -- given, and a voucher-only invoice took nothing and gave nothing. Their
 -- stock is taken where the invoice's rows do not hold it yet (the
 -- voucher-only invoice), from the invoice's store, with a row. A save that
 -- leaves the invoice part-paid gives them at the payment that settles it
 -- (464, in that trigger); one that keeps it completed FOC gives nothing more
 -- (416).
 if v_status = 'paid' and i.status in ('paid','completed_foc') and not same_lines then
   v464_lines := array(select it.id from public.invoice_items it
                        where it.invoice_id = i.id and it.line_kind = 'voucher' and it.voucher_id is not null
                          and greatest(coalesce(it.quantity, 1), 1) > coalesce((
                                select greatest(coalesce((x->>'quantity')::int, 1), 1)
                                  from jsonb_array_elements(v_snapshot->'items') x
                                 where (x->>'id')::uuid = it.id), 0));
   if cardinality(v464_lines) > 0 then
     perform public.give_raised_voucher_units(i.id, v464_lines, true, p_reason); end if;
 end if;
 -- 416: a correction that takes the FOC off a completed FOC invoice (it is
$p2$,
$p3$      jsonb_build_object('records', n, 'invoice_no', new.invoice_no), 'invoices', null, new.store_id);
   end if;
  end if;
  -- 464: and each voucher line gives the units it still lacks: a line a
  -- correction raised after its vouchers were given (the issuers above skip
  -- a line that gave vouchers before) is given the rest now, once. Settled as
  -- paid, it also takes their stock where the invoice's rows do not hold it
  -- yet (none after a payment, which took it; an invoice paid again when a
  -- refund or cancellation request is rejected may lack it); completed as
  -- FOC, what settled it took the stock with no row, so it takes none.
  perform public.give_raised_voucher_units(new.id, null, new.status::text = 'paid',
    'Invoice ' || coalesce(new.invoice_no, '(no number)') || ' settled');
 end if;
 return null;
$p3$];

  -- ══ The function this adds (the server's alone) ═════════════════════════
  c_new constant text := 'give_raised_voucher_units(uuid,uuid[],boolean,text)';
  c_new_after constant text := '84d4c7bbd39a754d61cbe4f778777a33';
  c_internal_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_new_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.give_raised_voucher_units(p_invoice_id uuid, p_lines uuid[], p_take_stock boolean, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 464: a settled invoice's voucher lines give the vouchers they now lack. A
-- voucher line raised by a correction after its vouchers were given (more
-- vouchers), or added to an invoice already paid, gave nothing more before:
-- issue_sold_vouchers_for_invoice gives a line's vouchers once (it skips a
-- line that gave any) when the invoice becomes settled, so a save that kept
-- the invoice paid gave nothing, and the payment that settled it again
-- skipped the raised line, though the extra units were taken from stock.
-- What a line has given is counted along each of its vouchers' own chains,
-- as cancel_invoice_recorded counts what an invoice issued: what each voucher
-- it gave, gave again or moved was granted, less what a reopening gave again
-- in its place or a transfer moved on. A voucher given counts however it
-- ended (used, refunded, moved, taken back), and so does one of another
-- voucher (a line whose voucher was swapped), so a line never gives more
-- than its units, and nothing is given twice. A sale voucher of the line
-- with no value row (there is none: the issuers write both) counts by its
-- quantity.
-- What a line lacks is given as one more sale of it (source
-- 'invoice_voucher_sale', the line's id, the next issue_no), held by the
-- invoice's customer at its store, worth that share of what the line now
-- charges: a cancel, refund, reopening or customer change treats it as the
-- line's other vouchers. The line's earlier vouchers still held whole are
-- valued at their share too (below).
-- p_lines: the lines to look at (null: every voucher line of the invoice).
-- p_take_stock: also take the units of a limited voucher that the invoice's
-- voucher movement rows do not hold yet (invoice_stock_to_deduct, net),
-- never more than this gives, from the invoice's store, with a row; refused
-- in words if the store is short. Off where the units were taken with no
-- row (a completed FOC invoice).
declare i public.invoices%rowtype; l record; rb record; rv uuid; n integer := 0; v_have integer; v_take integer;
  v_line numeric; v_benefit uuid; v_given jsonb := '[]'::jsonb; v_revalued jsonb := '[]'::jsonb;
begin
  select * into i from public.invoices where id = p_invoice_id;
  if not found or i.customer_id is null then return 0; end if;
  for l in
    select it.id, it.voucher_id, vo.name, vo.qty_type::text as qty_type,
           greatest(coalesce(it.quantity, 1), 1)::integer as units,
           (greatest(coalesce(it.quantity, 1), 1) - coalesce((
              select sum(greatest(b.granted_value
                       - coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                                    where q.benefit_id = b.id and q.applied_at is not null), 0)
                       - coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                                    where t.source_benefit_id = b.id and t.replacement_benefit_id is not null), 0), 0))
                from public.invoice_benefit_values b
                join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
               where b.invoice_id = i.id and b.invoice_item_id = it.id
                 and v.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')), 0)
              - coalesce((select sum(v.quantity) from public.customer_reward_vouchers v
                           where v.source_type = 'invoice_voucher_sale' and v.source_id = it.id
                             and not exists (select 1 from public.invoice_benefit_values b where b.reward_voucher_id = v.id)), 0))::integer as owed
      from public.invoice_items it
      join public.vouchers vo on vo.id = it.voucher_id
     where it.invoice_id = i.id and it.line_kind = 'voucher' and it.voucher_id is not null
       and (p_lines is null or it.id = any (p_lines))
     order by it.id
  loop
    continue when l.owed <= 0;
    v_take := 0;
    if p_take_stock and l.qty_type = 'limited' then
      v_take := least(l.owed, coalesce((select sum(t.quantity) from public.invoice_stock_to_deduct(i.id) t
                                         where t.kind <> 'product' and t.item_id = l.voucher_id), 0))::integer;
      if v_take > 0 then
        select s.current_qty into v_have from public.voucher_store_stock s
         where s.store_id = i.store_id and s.voucher_id = l.voucher_id for update;
        if coalesce(v_have, 0) < v_take then
          raise exception 'Not enough stock of the voucher "%" in this store: % left, % needed.', l.name, coalesce(v_have, 0), v_take; end if;
        update public.voucher_store_stock set current_qty = current_qty - v_take, updated_at = now()
         where store_id = i.store_id and voucher_id = l.voucher_id;
        insert into public.invoice_voucher_movements(invoice_id, voucher_id, store_id, quantity, reason, created_by)
        values (i.id, l.voucher_id, i.store_id, v_take,
                'Voucher units added after the vouchers were given: ' || coalesce(p_reason, 'invoice settled'), auth.uid());
      end if;
    end if;
    insert into public.customer_reward_vouchers
      (customer_id, voucher_id, store_id, quantity, status, issued_by, source_type, source_id, notes, issue_no)
    values (i.customer_id, l.voucher_id, i.store_id, l.owed, 'held', auth.uid(), 'invoice_voucher_sale', l.id,
            'Sold on invoice ' || coalesce(i.invoice_no, '(no number)')
            || case when l.owed = l.units then ': a line added after it was paid'
                    else ': units added to the line after its vouchers were given' end,
            1 + coalesce((select max(c.issue_no) from public.customer_reward_vouchers c
                           where c.source_type = 'invoice_voucher_sale' and c.source_id = l.id and c.voucher_id = l.voucher_id), 0))
    returning id into rv;
    v_line := coalesce(public.invoice_discounted_line_value(l.id), 0);
    insert into public.invoice_benefit_values
      (invoice_id, invoice_item_id, reward_voucher_id, paid_value, granted_value, evidence, created_by)
    values (i.id, l.id, rv, round(v_line * l.owed / l.units, 2),
            l.owed, 'Issued for units added to the line after its vouchers were given', auth.uid())
    returning id into v_benefit;
    -- The line's earlier vouchers still held whole (none of their units
    -- refunded, given again or moved) are worth their share of what the line
    -- now charges too: a price lowered in the same save left them at what they
    -- were given at, so a refund of one of them could pay back the whole line
    -- while the customer kept the one given here.
    for rb in select bv.id, bv.paid_value, round(v_line * bv.granted_value / l.units, 2) as share
               from public.invoice_benefit_values bv
               join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id
              where bv.invoice_id = i.id and bv.invoice_item_id = l.id and bv.id <> v_benefit
                and v.status = 'held' and v.quantity = bv.granted_value and bv.cancelled_unused_value = 0
                and not exists (select 1 from public.invoice_reopen_vouchers q where q.benefit_id = bv.id)
                and not exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = bv.id)
              order by bv.id
                for update of bv loop
      continue when rb.paid_value = rb.share;
      update public.invoice_benefit_values set paid_value = rb.share where id = rb.id;
      v_revalued := v_revalued || jsonb_build_array(jsonb_build_object('benefit_id', rb.id, 'invoice_item_id', l.id,
                      'from', rb.paid_value, 'to', rb.share));
    end loop;
    v_given := v_given || jsonb_build_array(jsonb_build_object('invoice_item_id', l.id, 'voucher', l.name,
                 'units', l.owed, 'line_units', l.units, 'worth', round(v_line * l.owed / l.units, 2), 'stock_taken', v_take));
    n := n + 1;
  end loop;
  if n > 0 then
    perform public.write_audit_ex('invoices', i.id, 'voucher_units_added_given', null,
      jsonb_build_object('invoice_no', i.invoice_no, 'given', v_given, 'revalued', v_revalued), 'invoices', p_reason, i.store_id);
  end if;
  return n;
end $function$
$d1$;

  -- ══ The table: the index as 344 made it, and as this file makes it ══════
  c_index_before constant text := 'CREATE UNIQUE INDEX customer_reward_vouchers_issued_once ON public.customer_reward_vouchers USING btree (source_type, source_id, voucher_id) WHERE ((source_id IS NOT NULL) AND (source_type = ANY (ARRAY[''invoice_voucher_sale''::text, ''invoice_promotion_voucher''::text])))';
  c_index_after constant text := 'CREATE UNIQUE INDEX customer_reward_vouchers_issued_once ON public.customer_reward_vouchers USING btree (source_type, source_id, voucher_id, issue_no) WHERE ((source_id IS NOT NULL) AND (source_type = ANY (ARRAY[''invoice_voucher_sale''::text, ''invoice_promotion_voucher''::text])))';
  c_check_after constant text := 'CHECK ((issue_no >= 1))';

  -- ══ Relied on, not changed (production now) ═══════════════════════════
  c_relied constant text[] := array[
    'issue_sold_vouchers_for_invoice(uuid)',
    'issue_promotion_vouchers_for_invoice(uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'apply_reopened_invoice_vouchers()',
    'invoice_own_voucher_ids(uuid)',
    'invoice_voucher_stock_unrecorded(uuid,boolean)',
    'invoice_stock_to_deduct(uuid)',
    'invoice_required_stock(uuid)',
    'deduct_invoice_stock(uuid,text)',
    'invoice_discounted_line_value(uuid)',
    'snapshot_therapy_voucher_issue(uuid,boolean)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    'record_invoice_payment(uuid,jsonb,uuid)',
    'invoice_record_payments_internal(uuid,jsonb)',
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_relied_md5 constant text[] := array[
    '0dbb4bc74411b6d4f0535f661a8c09ee',
    'e47e5f623b1fa3f6eafe83086f0c9776',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '28d3b7a69b91ddebcdb200559d96a0ef',
    '9340840f1ce4e031ec3613198688ba2e',
    '91c8f0fa69ef6337f323b7ac467a8c2b',
    '6356494ccb8545d46c56b788f8f85f54',
    'c91dc1eb4f2b7b465de5fe4a8fb2ca0c',
    '32183fe9e7c15ed0b11307c48289831a',
    'ead4a430c3abd1e3f953912867ca4fe6',
    '12ba32611ad001781862d82b1ae13c8e',
    '1f034561a461bdb46a1e6274e0d04606',
    '9c70097ed4da614fb9dcc66fdfcdb7d6',
    '21890d84bcb0b9c00a2bc98aff313d0b',
    '770ee0129b0e9fe909259ad7ea95b8d0',
    'c705c733e213a27f0dc32d54322cc855'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; k int;
  v_texts text[] := array[null, null]::text[]; v_acls text[] := array[null, null]::text[];
  v_make boolean := false; v_table boolean := false; v_tacl text; v_pols text;
  -- the self-test's made-up records
  t_sfx text; t_phone text; t_owner uuid; t_store uuid; t_cash uuid; t_vch uuid; t_buyer uuid; t_item uuid; t_inv uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──────────────
  -- What it relies on and does not change: as read on production, 24 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '464: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  -- The trigger that gives sold vouchers (after update, each row), and the
  -- one that gives a reopening's vouchers again (after update of status),
  -- which fires before it (after triggers fire in name order).
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'issue_sold_vouchers_on_paid'
                   and t.tgfoid = 'public.trg_issue_sold_vouchers_on_paid()'::regprocedure and t.tgenabled = 'O'
                   and pg_get_triggerdef(t.oid) = 'CREATE TRIGGER issue_sold_vouchers_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_issue_sold_vouchers_on_paid()')
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'invoice_reopen_vouchers_settled'
                   and t.tgfoid = 'public.apply_reopened_invoice_vouchers()'::regprocedure and t.tgenabled = 'O'
                   and pg_get_triggerdef(t.oid) = 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()') then
    raise exception '464: the triggers issue_sold_vouchers_on_paid and invoice_reopen_vouchers_settled on invoices are missing or not as read on 24 Oct 2026'; end if;

  -- The columns it reads and writes, with these types.
  select string_agg(x.t || '.' || x.c || ' ' || x.ty, ', ') into v
    from (values ('invoices', 'id', 'uuid'), ('invoices', 'status', 'invoice_status'), ('invoices', 'customer_id', 'uuid'),
                 ('invoices', 'store_id', 'uuid'), ('invoices', 'invoice_no', 'text'),
                 ('invoice_items', 'id', 'uuid'), ('invoice_items', 'invoice_id', 'uuid'), ('invoice_items', 'line_kind', 'invoice_line_kind'),
                 ('invoice_items', 'voucher_id', 'uuid'), ('invoice_items', 'quantity', 'integer'),
                 ('customer_reward_vouchers', 'id', 'uuid'), ('customer_reward_vouchers', 'customer_id', 'uuid'),
                 ('customer_reward_vouchers', 'voucher_id', 'uuid'), ('customer_reward_vouchers', 'store_id', 'uuid'),
                 ('customer_reward_vouchers', 'quantity', 'integer'), ('customer_reward_vouchers', 'status', 'text'),
                 ('customer_reward_vouchers', 'issued_by', 'uuid'), ('customer_reward_vouchers', 'source_type', 'text'),
                 ('customer_reward_vouchers', 'source_id', 'uuid'), ('customer_reward_vouchers', 'notes', 'text'),
                 ('invoice_benefit_values', 'invoice_id', 'uuid'), ('invoice_benefit_values', 'invoice_item_id', 'uuid'),
                 ('invoice_benefit_values', 'reward_voucher_id', 'uuid'), ('invoice_benefit_values', 'paid_value', 'numeric(12,2)'),
                 ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'), ('invoice_benefit_values', 'evidence', 'text'),
                 ('invoice_benefit_values', 'created_by', 'uuid'),
                 ('invoice_reopen_vouchers', 'benefit_id', 'uuid'), ('invoice_reopen_vouchers', 'quantity', 'integer'),
                 ('invoice_reopen_vouchers', 'applied_at', 'timestamp with time zone'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'), ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'transferred_value', 'numeric(12,2)'),
                 ('voucher_store_stock', 'voucher_id', 'uuid'), ('voucher_store_stock', 'store_id', 'uuid'),
                 ('voucher_store_stock', 'current_qty', 'integer'), ('voucher_store_stock', 'updated_at', 'timestamp with time zone'),
                 ('invoice_voucher_movements', 'invoice_id', 'uuid'), ('invoice_voucher_movements', 'voucher_id', 'uuid'),
                 ('invoice_voucher_movements', 'store_id', 'uuid'), ('invoice_voucher_movements', 'quantity', 'integer'),
                 ('invoice_voucher_movements', 'reason', 'text'), ('invoice_voucher_movements', 'created_by', 'uuid'),
                 ('vouchers', 'id', 'uuid'), ('vouchers', 'name', 'text'), ('vouchers', 'qty_type', 'voucher_qty_type')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '464: these columns are missing or not as read on 24 Oct 2026: %', v; end if;

  -- customer_reward_vouchers: as 344 left it (changed here) or as this file
  -- leaves it (left alone); nothing in between.
  if not exists (select 1 from pg_attribute a where a.attrelid = 'public.customer_reward_vouchers'::regclass
                   and a.attname = 'issue_no' and a.attnum > 0 and not a.attisdropped) then
    if to_regclass('public.customer_reward_vouchers_issued_once') is null
       or pg_get_indexdef('public.customer_reward_vouchers_issued_once'::regclass) <> c_index_before
       or exists (select 1 from pg_constraint c where c.conrelid = 'public.customer_reward_vouchers'::regclass
                    and c.conname = 'customer_reward_vouchers_issue_no_check')
       or to_regclass('public.customer_reward_vouchers_issued_once_464') is not null then
      raise exception '464: customer_reward_vouchers is not as read on 24 Oct 2026 (its index customer_reward_vouchers_issued_once: %)',
        coalesce(pg_get_indexdef(to_regclass('public.customer_reward_vouchers_issued_once')), 'missing'); end if;
    v_table := true;
  elsif not exists (select 1 from pg_attribute a where a.attrelid = 'public.customer_reward_vouchers'::regclass
                      and a.attname = 'issue_no' and a.attnum > 0 and not a.attisdropped and a.attnotnull
                      and format_type(a.atttypid, a.atttypmod) = 'integer'
                      and pg_get_expr((select ad.adbin from pg_attrdef ad where ad.adrelid = a.attrelid and ad.adnum = a.attnum), a.attrelid) = '1')
        or to_regclass('public.customer_reward_vouchers_issued_once') is null
        or pg_get_indexdef('public.customer_reward_vouchers_issued_once'::regclass) <> c_index_after
        or not exists (select 1 from pg_constraint c where c.conrelid = 'public.customer_reward_vouchers'::regclass
                         and c.conname = 'customer_reward_vouchers_issue_no_check' and c.contype = 'c'
                         and pg_get_constraintdef(c.oid) = c_check_after) then
    raise exception '464: customer_reward_vouchers has an issue_no column but is not as this file leaves it. Nothing was changed.';
  else
    raise notice '464: the table customer_reward_vouchers is already this version; left alone';
  end if;
  -- its grants and policies, to compare after (as sets)
  v_tacl := (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_class c, unnest(c.relacl) x
              where c.oid = 'public.customer_reward_vouchers'::regclass);
  v_pols := (select coalesce(string_agg(p.policyname || ' ' || p.cmd || ' ' || array_to_string(p.roles, '/') || ' '
                                        || coalesce(p.qual, '') || ' ' || coalesce(p.with_check, ''), '; ' order by p.policyname), '')
               from pg_policies p where p.schemaname = 'public' and p.tablename = 'customer_reward_vouchers');

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('correct_invoice', 'trg_issue_sold_vouchers_on_paid', 'give_raised_voucher_units')
     and p.oid::regprocedure::text <> all (c_sigs || c_new);
  if v is not null then raise exception '464: another function takes the name of one this changes: %', v; end if;

  -- The new function: its text is the tested one; not there yet (made), or
  -- this version (left alone).
  if md5(c_new_def) <> c_new_after then
    raise exception '464: the text of public.% is not the tested one (md5 %)', c_new, md5(c_new_def); end if;
  if to_regprocedure('public.' || c_new) is null then
    v_make := true;
  elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new))) <> c_new_after then
    raise exception '464: public.% is there but not this version (md5 %). Nothing was changed.',
      c_new, md5(pg_get_functiondef(to_regprocedure('public.' || c_new)));
  end if;

  -- Each patched function: its BEFORE (patched; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[k]) is null then raise exception '464: public.% is missing', c_sigs[k]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]));
    -- its grants, to compare after (as sets: production lists them in
    -- another order than a local copy does)
    v_acls[k] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                    from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k]));
    if md5(d) = c_after[k] then
      raise notice '464: public.% is already this version; left alone', c_sigs[k];
      continue;
    end if;
    if md5(d) <> c_before[k] then
      raise exception '464: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d); end if;
    for i in 1 .. cardinality(c_anchor) loop
      continue when c_fn[i] <> k;
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then raise exception '464: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
      d := replace(d, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_after[k] then
      raise exception '464: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
    v_texts[k] := d;
  end loop;

  -- ── 2. Install: the table, then the new function (the patched ones call
  -- it), then the patched functions ─────────────────────────────────────
  if v_table then
    execute 'alter table public.customer_reward_vouchers add column issue_no integer not null default 1';
    execute 'alter table public.customer_reward_vouchers add constraint customer_reward_vouchers_issue_no_check check (issue_no >= 1)';
    execute $c$comment on column public.customer_reward_vouchers.issue_no is
      '464: which sale of its line and voucher this is: 1 for the vouchers a line gives when its invoice is settled (every voucher before 464), 2 and on for units a correction added to the line after its vouchers were given (give_raised_voucher_units). customer_reward_vouchers_issued_once keeps one per line, voucher and issue.'$c$;
    -- Built under another name, then swapped in, so a voucher is never
    -- unguarded; nothing else writes the table meanwhile (the alter above
    -- holds it).
    execute 'create unique index customer_reward_vouchers_issued_once_464 on public.customer_reward_vouchers (source_type, source_id, voucher_id, issue_no)'
         || ' where source_id is not null and source_type = any (array[''invoice_voucher_sale''::text, ''invoice_promotion_voucher''::text])';
    execute 'drop index public.customer_reward_vouchers_issued_once';
    execute 'alter index public.customer_reward_vouchers_issued_once_464 rename to customer_reward_vouchers_issued_once';
  end if;
  if v_make then
    execute c_new_def;
    execute format('revoke all on function public.%s from public, anon, authenticated', c_new);
    execute format('grant execute on function public.%s to service_role', c_new);
  else
    raise notice '464: public.% is already this version; left alone', c_new;
  end if;
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_new))) <> c_new_after then
    raise exception '464: public.% was installed with an md5 other than the tested one', c_new; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_internal_acl::aclitem[]) x)
     or has_function_privilege('anon', 'public.' || c_new, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_new, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_new, 'execute') then
    raise exception '464: public.% is not the server''s alone', c_new; end if;
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]))) <> c_after[k] then
      raise exception '464: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k])) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '464: the grants of public.% changed', c_sigs[k]; end if;
  end loop;
  -- correct_invoice: signed-in staff may call it; the trigger function and
  -- the new one: never.
  if not has_function_privilege('authenticated', 'public.' || c_sigs[1], 'execute')
     or has_function_privilege('authenticated', 'public.' || c_sigs[2], 'execute') then
    raise exception '464: correct_invoice must be callable by signed-in staff and its trigger function must not be'; end if;
  -- correct_invoice still reads the invoice for update and checks store
  -- access before anything else.
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[1]));
  if position(E'\nbegin\n select * into i from public.invoices where id=p_invoice_id for update;\n'
              || E' if not found or i.deleted_at is not null then raise exception ''Invoice not found''; end if;\n'
              || E' if not public.user_has_store_access(i.store_id) then raise exception ''No access to this invoice''; end if;\n' in d) = 0 then
    raise exception '464: public.% no longer checks store access first', c_sigs[1]; end if;
  -- The table: the column, its check and the index as made here; its grants
  -- and policies as before; every voucher there is issue 1.
  if pg_get_indexdef('public.customer_reward_vouchers_issued_once'::regclass) <> c_index_after
     or not (select indisunique and indisvalid from pg_index where indexrelid = 'public.customer_reward_vouchers_issued_once'::regclass)
     or to_regclass('public.customer_reward_vouchers_issued_once_464') is not null
     or not exists (select 1 from pg_constraint c where c.conrelid = 'public.customer_reward_vouchers'::regclass
                      and c.conname = 'customer_reward_vouchers_issue_no_check' and pg_get_constraintdef(c.oid) = c_check_after)
     or (select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_class c, unnest(c.relacl) x
          where c.oid = 'public.customer_reward_vouchers'::regclass) is distinct from v_tacl
     or (select coalesce(string_agg(p.policyname || ' ' || p.cmd || ' ' || array_to_string(p.roles, '/') || ' '
                                    || coalesce(p.qual, '') || ' ' || coalesce(p.with_check, ''), '; ' order by p.policyname), '')
           from pg_policies p where p.schemaname = 'public' and p.tablename = 'customer_reward_vouchers') is distinct from v_pols then
    raise exception '464: customer_reward_vouchers is not as this file leaves it, or its grants or policies changed'; end if;
  if v_table and exists (select 1 from public.customer_reward_vouchers where issue_no <> 1) then
    raise exception '464: a voucher there was before this file is not issue 1'; end if;

  -- ── 4. Self-test, in a block that is always undone ─────────────────────
  -- Made-up records only ("464 check", @example.com, a fictional ACMA
  -- phone no customer uses), vouchers only (no product, so no stock history
  -- row and no sequence); it ends by raising P0464, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select x into t_phone
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4640, 4679) g) y
     where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = y.x)
     order by x limit 1;
    if t_phone is null then raise exception '464: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '464-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '464 check', '464-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('464 check ' || t_sfx, '464-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('464 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('464 Check Customer ' || t_sfx, t_phone) returning id into t_buyer;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('464 check ' || t_sfx, '464-' || t_sfx, 'normal', 90, 'limited', true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 90, true);
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty) values (t_vch, t_store, 5);

    -- One voucher, paid: one held, 4 left.
    t_inv := public.create_invoice_with_details(t_store, t_buyer,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 1)),
      jsonb_build_object('business_date', public.sg_today()));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 90)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    if (select status::text from public.invoices where id = t_inv) <> 'paid'
       or (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v where v.source_id = t_item and v.status = 'held') <> 1
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 4 then
      raise exception '464: the self-test''s invoice is not paid with one voucher given from stock'; end if;

    -- Raised to two at S$45 (still paid): two held, issue 1 and 2, each worth
    -- S$45 (the first was S$90); 3 left.
    perform public.correct_invoice(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'kind', 'voucher',
      'voucher_id', t_vch, 'quantity', 2, 'unit_price', 45)), jsonb_build_object('expected_edit_count', 0), '464 check: two', gen_random_uuid());
    if (select (status::text, total_amount) is distinct from ('paid'::text, 90::numeric) from public.invoices where id = t_inv)
       or (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v where v.source_id = t_item and v.status = 'held') <> 2
       or (select array_agg(v.issue_no order by v.issue_no) from public.customer_reward_vouchers v where v.source_id = t_item) <> array[1, 2]
       or (select array_agg(b.paid_value order by v.issue_no) from public.invoice_benefit_values b
             join public.customer_reward_vouchers v on v.id = b.reward_voucher_id where b.invoice_item_id = t_item) <> array[45, 45]::numeric[]
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 3 then
      raise exception '464: raised to two on the paid invoice, it did not give the second voucher from stock (%)',
        (select jsonb_build_object('status', status, 'total', total_amount,
                  'held', (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v where v.source_id = t_item and v.status = 'held'),
                  'stock', (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch))
           from public.invoices where id = t_inv); end if;

    -- A note changed: nothing more.
    perform public.correct_invoice(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'kind', 'voucher',
      'voucher_id', t_vch, 'quantity', 2, 'unit_price', 45)), jsonb_build_object('expected_edit_count', 1, 'notes', '464 check'),
      '464 check: a note', gen_random_uuid());
    if (select count(*) from public.customer_reward_vouchers v where v.source_id = t_item) <> 2
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 3 then
      raise exception '464: a note changed on the paid invoice gave or took vouchers'; end if;

    -- Raised to three (S$135, part paid): nothing given before the payment;
    -- paid in full: the third given, once, each worth S$45; 2 left.
    perform public.correct_invoice(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'kind', 'voucher',
      'voucher_id', t_vch, 'quantity', 3, 'unit_price', 45)), jsonb_build_object('expected_edit_count', 2), '464 check: three', gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) <> 'partially_paid'
       or (select count(*) from public.customer_reward_vouchers v where v.source_id = t_item) <> 2
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 3 then
      raise exception '464: raised to three, part paid, it gave or took vouchers before the payment'; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 45)), gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) <> 'paid'
       or (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v where v.source_id = t_item and v.status = 'held') <> 3
       or (select array_agg(v.issue_no order by v.issue_no) from public.customer_reward_vouchers v where v.source_id = t_item) <> array[1, 2, 3]
       or (select array_agg(b.paid_value order by v.issue_no) from public.invoice_benefit_values b
             join public.customer_reward_vouchers v on v.id = b.reward_voucher_id where b.invoice_item_id = t_item) <> array[45, 45, 45]::numeric[]
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 2 then
      raise exception '464: paid in full after the raise to three, it did not give the third voucher once from stock'; end if;

    -- Cancelled: every voucher taken back, every unit back in stock.
    perform public.cancel_invoice_recorded(t_inv, '464 check: cancel', gen_random_uuid());
    if (select count(*) from public.customer_reward_vouchers v where v.source_id = t_item and v.status = 'held') <> 0
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 5 then
      raise exception '464: the cancel did not take back the three vouchers and return their stock'; end if;

    raise exception using errcode = 'P0464', message = '464: self-test done, undone';
  exception when sqlstate 'P0464' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
