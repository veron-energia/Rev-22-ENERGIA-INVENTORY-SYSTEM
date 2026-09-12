begin;
-- =====================================================================
-- A FULL REVERSAL LEFT A CENT OF CREDIT BEHIND
--
-- Benefit refunds are computed in money and applied in granted units, and the
-- round trip is lossy at two decimals. A premium bundle granting 100.00 of
-- paid credit for 77.78 of the price:
--
--   refundable now      round(77.78 * 80.00 / 100.00, 2) = 62.22
--   credit to revoke    round(62.22 * 100.00 / 77.78, 2) = 79.99
--   left with customer  80.00 - 79.99                    =  0.01
--
-- So a customer refunded for ALL of their remaining credit kept a cent of it.
-- Small, but it is credit that was paid back and should be gone, and it
-- accumulates across every bundle and package reversal.
--
-- Fixed where the cause is: when the refund takes the whole refundable value
-- of a benefit, the whole remaining balance goes, rather than a figure derived
-- back through a second rounding. Partial refunds are untouched and still
-- convert proportionally.
--
-- Found by scripts/invoice-actions/tests/premium-bundle.sql.
-- Requires 296. Idempotent.
-- =====================================================================
do $do$
declare f text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 if position('whole refundable value' in f)>0 then
  raise notice 'benefit reversal already clears the balance exactly'; return; end if;

 v_old:='           v_revoke:=least(l.remaining_amount+b.cancelled_unused_value,round(v_grant*b.granted_value/b.paid_value,2));';
 v_new:=
'           -- Taking the whole refundable value clears the balance exactly;'||E'\n'||
'           -- deriving it back through a second rounding leaves a crumb.'||E'\n'||
'           if v_grant>=round(b.paid_value*(l.remaining_amount+b.cancelled_unused_value)/b.granted_value,2) then'||E'\n'||
'             v_revoke:=l.remaining_amount+b.cancelled_unused_value;'||E'\n'||
'           else'||E'\n'||
'             v_revoke:=least(l.remaining_amount+b.cancelled_unused_value,round(v_grant*b.granted_value/b.paid_value,2));'||E'\n'||
'           end if;';
 if position(v_old in f)=0 then
  raise exception 'The credit-revocation line of refund_invoice_recorded does not match what 299 expects — align it by hand'; end if;
 execute replace(f,v_old,v_new);
 raise notice 'a full benefit reversal now clears the balance exactly';
end $do$;

notify pgrst,'reload schema';
commit;
