-- AFTER migration 290. Requires an approved connection able to act as the
-- supplied, active Owner/Manager profile. This file cannot write persistent data.
-- psql -X -qAt -v ON_ERROR_STOP=1 -v actor=OWNER_PROFILE_UUID -f ... > preview.json
begin isolation level repeatable read read only;
set local timezone='UTC';
select set_config('request.jwt.claim.sub', :'actor',true) as ignored \gset
set local role authenticated;
with review as materialized(select x row from public.preview_invoice_date_recovery() x)
select jsonb_build_object('generated_at',clock_timestamp(),'actor',auth.uid(),
 'basis','Actual eligible received amounts by recovered invoice business date. Existing refunds stay on refund dates; collections stay on payment dates. No new financial events.',
 'counts',jsonb_build_object('already_valid',count(*) filter(where row->>'classification'='already_valid'),
   'eligible',count(*) filter(where row->>'classification'='eligible'),'manual_review',count(*) filter(where row->>'classification'='manual_review')),
 'expected_sales_added',coalesce(sum((row->>'sales_to_add')::numeric),0),
 'expected_sales_by_date',coalesce((select jsonb_agg(d order by d.proposed_date) from (
   select row->>'proposed_date' proposed_date,sum((row->>'sales_to_add')::numeric) received_amount,count(*) invoices
   from review where row->>'classification'='eligible' group by 1) d),'[]'),
 'rows',coalesce(jsonb_agg(row order by row->>'invoice_id'),'[]'),
 'uncertain',coalesce(jsonb_agg(row order by row->>'invoice_id') filter(where row->>'classification'='manual_review'),'[]'))
from review;
commit;
