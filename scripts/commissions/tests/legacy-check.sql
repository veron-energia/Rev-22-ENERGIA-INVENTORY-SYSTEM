begin;
do $$
declare p public.commission_payouts; bad public.commission_payouts; n integer; result jsonb; method uuid;
begin
 select * into p from commission_payouts where reference='Verified legacy';
 select * into bad from commission_payouts where reference='Ambiguous legacy';
 perform set_config('request.jwt.claim.sub',p.paid_by::text,true);
 if p.total_amount<>280 or p.allocation_state<>'verified' or p.payment_date<>'2020-02-02' or p.payment_method_name<>'Legacy Cheque' then raise exception 'Verified original/date/method changed';end if;
 if (select count(*) from commission_payout_allocations where payout_id=p.id)<>3 or (select sum(amount) from commission_payout_allocations where payout_id=p.id)<>280 then raise exception 'Verified signed legacy allocations missing';end if;
 if (p.original_record->>'total_amount')::numeric<>280 then raise exception 'Original snapshot missing';end if;
 if bad.total_amount<>200 or bad.allocation_state<>'review' or exists(select 1 from commission_payout_allocations where payout_id=bad.id) then raise exception 'Ambiguous allocation fabricated or original lost';end if;
 if affiliate_payout_review(bad.referrer_customer_id,'2020-03-01') is null or affiliate_payout_review(bad.referrer_customer_id,'2020-04-01') is null then raise exception 'Orphan/mismatched month was not blocked';end if;
 begin perform correct_affiliate_payout(bad.id,1,180,bad.payment_method_id,sg_today(),bad.reference,null,'Unproven amount',gen_random_uuid());raise exception 'Unreviewed amount allowed';exception when others then if sqlerrm not like '%review%' then raise;end if;end;
 perform correct_affiliate_payout(bad.id,1,bad.total_amount,bad.payment_method_id,sg_today(),bad.reference,'Review pending','Clarify evidence status',gen_random_uuid());
 if (select total_amount from commission_payouts where id=bad.id)<>200 then raise exception 'Metadata changed historical cash';end if;
 if (select balance from affiliate_month_balances() where referrer=p.referrer_customer_id and month='2020-01-01')<>0 then raise exception 'Full legacy payout no longer settled';end if;
 if (select unpaid_earned from referrer_list() where customer_id=p.referrer_customer_id)<>(select sum(balance) from affiliate_month_balances() where referrer=p.referrer_customer_id) then raise exception 'Ambiguous totals inconsistent';end if;
 raise notice 'PASS: reliable signed backfill, SG legacy date, inactive method, orphan/wrong month review, metadata allowed, amount edits blocked, historical totals retained';
end$$;
rollback;
