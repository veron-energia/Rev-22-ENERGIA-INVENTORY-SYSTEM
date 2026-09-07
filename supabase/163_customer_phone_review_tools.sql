-- Apply after 162. These functions do not run cleanup automatically.
begin;
set local check_function_bodies=on;

create or replace function public.customer_phone_review_report()
returns jsonb language plpgsql stable security definer set search_path=public as $fn$
declare result jsonb;
begin
  if not coalesce(public.is_owner_or_manager(),false) then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('customer_id',c.id,'full_name',c.full_name,
    'original_phone',m.original_phone,'current_phone',c.phone,'deleted_at',c.deleted_at,
    'inspection',public.inspect_customer_phone(c.phone),'non_deleted_count',coalesce(cap.used,0),
    'over_capacity',coalesce(cap.used,0)>3,'applied_at',m.applied_at) order by c.id),'[]')
  into result from public.customers c left join public.customer_phone_migration_map m on m.customer_id=c.id
  left join public.customer_phone_capacity cap on cap.phone=public.normalize_customer_phone(c.phone);
  return result;
end $fn$;

create or replace function public.customer_phone_collisions()
returns jsonb language plpgsql stable security definer set search_path=public as $fn$
declare result jsonb;
begin
  if not coalesce(public.is_owner_or_manager(),false) then raise exception 'Owner or Manager only'; end if;
  select coalesce(jsonb_agg(x),'[]') into result from (
    select public.normalize_customer_phone(phone) as canonical_phone,count(*) as count,
      jsonb_agg(jsonb_build_object('id',id,'name',full_name,'phone',phone) order by id) as customers
    from public.customers where deleted_at is null and public.normalize_customer_phone(phone) is not null
    group by public.normalize_customer_phone(phone) having count(*)>3
  ) x;
  return result;
end $fn$;

-- Reviewed plan: [{customer_id, original_phone, normalized_phone, reason}].
-- Requires every input to be the current value and every target to be E.164.
-- No implicit normalization/guessing here. One stale/invalid/overfull row rolls
-- back the ENTIRE call, including audit/map updates.
create or replace function public.apply_customer_phone_review(p_rows jsonb)
returns integer language plpgsql security definer set search_path=public as $fn$
declare row jsonb; c public.customers%rowtype; done integer:=0; norm text;
begin
  if not coalesce(public.is_owner_or_manager(),false) then raise exception 'Owner or Manager only'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'A reviewed array is required'; end if;
  if exists(select 1 from jsonb_array_elements(p_rows) r group by r->>'customer_id' having count(*)>1) then
    raise exception 'Each customer may appear only once in a reviewed plan'; end if;
  -- Prevent concurrent imports/edits while checking and applying a reviewed batch.
  lock table public.customers in share row exclusive mode;
  for row in select value from jsonb_array_elements(p_rows) order by value->>'customer_id' loop
    select * into c from public.customers where id=(row->>'customer_id')::uuid for update;
    if not found then raise exception 'Customer in review plan no longer exists'; end if;
    if c.phone is distinct from row->>'original_phone' then raise exception 'Stale phone review for customer %; export a new report',c.id; end if;
    norm:=row->>'normalized_phone';
    if not public.valid_customer_e164(norm) or nullif(btrim(row->>'reason'),'') is null then
      raise exception 'A validated E.164 number and review reason are required for %',c.id; end if;
    -- Existing overfull groups remain untouched until records are corrected.
    if c.deleted_at is null and public.normalize_customer_phone(c.phone)=norm
       and (select used from public.customer_phone_capacity where phone=norm)>3 then
      raise exception 'Unresolved group over the three-customer limit for %',c.id; end if;
    insert into public.customer_phone_migration_map(customer_id,full_name,original_phone,deleted_at,inspection)
    values(c.id,c.full_name,c.phone,c.deleted_at,public.inspect_customer_phone(c.phone)) on conflict do nothing;
    perform set_config('energia.phone_change_reason',row->>'reason',true);
    update public.customers set phone=norm where id=c.id;
    update public.customer_phone_migration_map set applied_phone=norm,applied_at=now(),applied_by=auth.uid(),review_reason=row->>'reason'
      where customer_id=c.id;
    done:=done+1;
  end loop;
  return done;
end $fn$;

create or replace function public.list_deleted_customers(p_query text default null,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $fn$
declare result jsonb;
begin
  if not coalesce(public.is_owner_or_manager(),false) then raise exception 'Owner or Manager only'; end if;
  select jsonb_build_object('rows',coalesce(jsonb_agg(r),'[]')) into result from (
    select id,full_name,phone,deleted_at,count(*) over() as total_count from public.customers
    where deleted_at is not null and (nullif(btrim(p_query),'') is null or full_name ilike '%'||btrim(p_query)||'%'
      or phone ilike '%'||btrim(p_query)||'%' or id::text=btrim(p_query))
    order by deleted_at desc,id limit 50 offset greatest(coalesce(p_offset,0),0)
  ) r;
  return result;
end $fn$;
revoke all on function public.customer_phone_review_report() from public,anon;
revoke all on function public.apply_customer_phone_review(jsonb) from public,anon;
revoke all on function public.list_deleted_customers(text,integer) from public,anon;
grant execute on function public.customer_phone_review_report(),public.apply_customer_phone_review(jsonb),public.list_deleted_customers(text,integer) to authenticated;
notify pgrst,'reload schema';
commit;
