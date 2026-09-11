begin;
lock table public.commissions,public.commission_payouts in share row exclusive mode;

create function public.affiliate_payout_access(p_write boolean default false) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_active and deleted_at is null
  and (role in ('owner','manager') or (not p_write and role='admin')))
$$;
create function public.affiliate_payout_lock() returns void language sql volatile security definer set search_path=public as $$
 select pg_advisory_xact_lock(728041903110::bigint)
$$;
create function public.affiliate_commission_write_lock() returns trigger language plpgsql security definer set search_path=public as $$
begin perform public.affiliate_payout_lock();return null;end $$;
-- The same lock covers invoice-driven adjustments and every payout operation.
-- Payouts never lock invoices, avoiding an invoice/ledger lock-order inversion.
create trigger affiliate_commission_serialization before insert or update or delete on public.commissions
 for each statement execute function public.affiliate_commission_write_lock();

alter table public.commission_payouts add column payment_date date;
alter table public.commission_payouts add column payment_method_name text;
alter table public.commission_payouts add column version integer not null default 1;
alter table public.commission_payouts add column allocation_state text not null default 'verified' check(allocation_state in ('verified','review'));
alter table public.commission_payouts add column allocation_review_reason text;
alter table public.commission_payouts add column original_record jsonb;
update public.commission_payouts set original_record=to_jsonb(commission_payouts)-array['original_record','allocation_state','allocation_review_reason','version','payment_date','payment_method_name'],
 payment_date=(paid_at at time zone 'Asia/Singapore')::date;
update public.commission_payouts p set payment_method_name=m.name from public.payment_methods m where m.id=p.payment_method_id;
alter table public.commission_payouts alter column payment_date set not null;
alter table public.commission_payouts alter column payment_date set default public.sg_today();

create table public.commission_payout_allocations(
 id uuid primary key default gen_random_uuid(),payout_id uuid not null references public.commission_payouts(id),
 commission_id uuid not null references public.commissions(id),amount numeric(12,2) not null check(amount<>0),
 operation_id uuid not null,created_at timestamptz not null default clock_timestamp(),legacy boolean not null default false,
 unique(payout_id,commission_id,operation_id));
create index commission_payout_adjustment_entry on public.commissions(adjusts_commission_id) where adjusts_commission_id is not null;
create index commission_allocation_entry on public.commission_payout_allocations(commission_id);
create table public.commission_payout_operations(
 request_id uuid primary key,payload jsonb not null,result jsonb not null,actor_id uuid not null references public.profiles(id),created_at timestamptz not null default clock_timestamp());
create table public.commission_payout_changes(
 id uuid primary key default gen_random_uuid(),payout_id uuid not null references public.commission_payouts(id),version integer not null,
 reason text not null,actor_id uuid references public.profiles(id),created_at timestamptz not null default clock_timestamp(),
 old_record jsonb,new_record jsonb not null,old_allocations jsonb,new_allocations jsonb not null,request_id uuid not null,
 unique(payout_id,version));
alter table public.commission_payout_allocations enable row level security;
alter table public.commission_payout_operations enable row level security;
alter table public.commission_payout_changes enable row level security;
revoke all on public.commission_payout_allocations,public.commission_payout_operations,public.commission_payout_changes from public,anon,authenticated;
revoke insert,update,delete on public.commissions,public.commission_payouts from public,anon,authenticated;

-- Backfill only explicit payout links whose affiliate/month, tiers and totals
-- exactly reconcile. Never allocate by guessed customer names or timestamps.
update public.commission_payouts p set allocation_state='review',allocation_review_reason=
 'Historical payout links, month, status or tier totals do not reconcile. Resolve the original records before changing amounts or recording another payout for this month.'
where p.status<>'paid' or p.total_amount<=0 or p.payout_month<>date_trunc('month',p.payout_month)::date
 or not exists(select 1 from public.commissions c where c.payout_id=p.id)
 or exists(select 1 from public.commissions c where c.payout_id=p.id and (c.referrer_customer_id<>p.referrer_customer_id
  or c.invoice_paid_date is null or date_trunc('month',c.invoice_paid_date)::date<>p.payout_month or c.status<>'paid'))
 or (select coalesce(sum(commission_amount),0) from public.commissions where payout_id=p.id)<>p.total_amount
 or (select coalesce(sum(commission_amount) filter(where tier='tier1'),0) from public.commissions where payout_id=p.id)<>p.total_tier1
 or (select coalesce(sum(commission_amount) filter(where tier='tier2'),0) from public.commissions where payout_id=p.id)<>p.total_tier2;
insert into public.commission_payout_allocations(payout_id,commission_id,amount,operation_id,legacy)
 select p.id,c.id,c.commission_amount,p.id,true from public.commission_payouts p join public.commissions c on c.payout_id=p.id
 where p.allocation_state='verified' and c.commission_amount<>0;

create function public.affiliate_payout_review(p_referrer uuid,p_month date) returns text language sql stable security definer set search_path=public as $$
 select case when exists(select 1 from public.commission_payouts where referrer_customer_id=p_referrer and payout_month=p_month and (allocation_state='review' or (status='paid' and total_amount<>(select coalesce(sum(amount),0) from public.commission_payout_allocations a where a.payout_id=commission_payouts.id))))
  then 'Historical payout allocations need review for this affiliate and month. Existing records are preserved.'
 when exists(select 1 from public.commissions c where c.referrer_customer_id=p_referrer and date_trunc('month',c.invoice_paid_date)::date=p_month
  and (c.status='paid' or c.payout_id is not null) and (c.payout_id is null or not exists(select 1 from public.commission_payouts p where p.id=c.payout_id and p.status='paid' and p.allocation_state='verified' and p.referrer_customer_id=c.referrer_customer_id and p.payout_month=date_trunc('month',c.invoice_paid_date)::date)))
  then 'A paid commission has no matching active payout. Review its historical payment evidence first.' end
$$;
create function public.affiliate_month_balances() returns table(referrer uuid,month date,earned numeric,adjustments numeric,paid numeric,balance numeric,tier1 numeric,tier2 numeric,review_reason text)
language sql stable security definer set search_path=public as $$
 with c as(select referrer_customer_id referrer,date_trunc('month',invoice_paid_date)::date as month,
  coalesce(sum(commission_amount) filter(where commission_amount>=0),0) earned,
  coalesce(sum(commission_amount) filter(where commission_amount<0),0) adjustments,
  coalesce(sum(commission_amount) filter(where tier='tier1'),0) tier1,coalesce(sum(commission_amount) filter(where tier='tier2'),0) tier2
  from public.commissions where status in ('earned','paid') group by 1,2),
 p as(select referrer_customer_id referrer,payout_month as month,sum(total_amount) paid from public.commission_payouts where status='paid' group by 1,2)
 select coalesce(c.referrer,p.referrer),coalesce(c.month,p.month),coalesce(c.earned,0),coalesce(c.adjustments,0),coalesce(p.paid,0),
  coalesce(c.earned,0)+coalesce(c.adjustments,0)-coalesce(p.paid,0),coalesce(c.tier1,0),coalesce(c.tier2,0),
  case when coalesce(c.month,p.month) is null then 'Commission date is missing. Review the original invoice before recording a payout.' else public.affiliate_payout_review(coalesce(c.referrer,p.referrer),coalesce(c.month,p.month)) end
 from c full join p using(referrer,month)
$$;
-- Compatibility projection for aggregate read reports. Raw commission rows
-- stay intact; an anchored paid flag is never used as the partial balance.
create function public.commission_reporting_rows() returns setof public.commissions language sql stable security definer set search_path=public as $$
 with c as(select c.*,coalesce((select sum(a.amount) from public.commission_payout_allocations a where a.commission_id=c.id),
  case when c.status='paid' then c.commission_amount else 0 end) paid_amount from public.commissions c),
 parts as(select c,to_jsonb(c)-'paid_amount' base,v.amount,v.status from c cross join lateral(
  select c.paid_amount amount,'paid'::text status where c.status in ('paid','earned') and c.paid_amount<>0
  union all select c.commission_amount-c.paid_amount,'earned' where c.status in ('paid','earned') and c.commission_amount<>c.paid_amount
  union all select c.commission_amount,c.status::text where c.status not in ('paid','earned')) v)
 select (jsonb_populate_record(null::public.commissions,base||jsonb_build_object('commission_amount',amount,'status',status,
  'payout_id',case when status='paid' then base->>'payout_id' end))).* from parts
$$;
revoke all on function public.affiliate_payout_access(boolean),public.affiliate_payout_lock(),public.affiliate_commission_write_lock(),
 public.affiliate_payout_review(uuid,date),public.affiliate_month_balances(),public.commission_reporting_rows() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
