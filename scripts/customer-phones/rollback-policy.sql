-- Maintenance-window rollback only. Back up the DB first. This does not undo
-- reviewed phone corrections or erase new customers/history. Prefer roll-forward
-- once shared numbers are in use. Any failing guard rolls back this whole file.
begin;
lock table public.customers in access exclusive mode;
do $rollback$
declare f record;
begin
  if exists(select 1 from public.customers group by phone having count(*)>1) then
    raise exception 'Rollback blocked: shared raw phone numbers exist (including deleted records). Do not delete or merge customers to force rollback.';
  end if;
  if exists(select 1 from public.customers where deleted_at is null and public.normalize_customer_phone(phone) is not null
    group by public.normalize_customer_phone(phone) having count(*)>1) then
    raise exception 'Rollback blocked: legacy phone-only identification would be ambiguous. Keep the policy and roll forward.';
  end if;
  if (select count(*) from public.customer_phone_policy_backup)<7 then
    raise exception 'Incomplete pre-policy function backup. Do not roll back automatically.';
  end if;
  drop trigger zz_normalize_current_customer_phone on public.customers;
  drop trigger zz_customer_phone_policy on public.customers;
  drop trigger customer_phone_audit on public.customers;
  drop index public.idx_customers_phone_norm;
  for f in select definition from public.customer_phone_policy_backup order by signature loop execute f.definition; end loop;
  alter table public.customers add constraint customers_phone_key unique(phone);
  create index idx_customers_phone_norm on public.customers(public.normalize_customer_phone(phone));
end $rollback$;
-- Retain private audit/mapping/backup tables for traceability. Disable new
-- operational entry points until the matching application version is deployed.
revoke execute on function public.restore_customer_with_phone(uuid,text,text),public.apply_customer_phone_review(jsonb),
  public.list_deleted_customers(text,integer),public.customer_phone_review_report() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
