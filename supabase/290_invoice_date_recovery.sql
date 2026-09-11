-- Historical invoice dates: install review/recovery tools, without backfilling data.
-- Requires the current combined schema through 282. Apply this file atomically.
begin;

alter table public.invoices add column business_date_version bigint not null default 0;
-- Detect date changes through every existing correction route, including A→B→A.
create function public.track_invoice_business_date_version() returns trigger
language plpgsql set search_path=public as $$
begin
 new.business_date_version := old.business_date_version +
   case when new.business_date is distinct from old.business_date then 1 else 0 end;
 return new;
end $$;
create trigger invoice_date_version before update on public.invoices
for each row execute function public.track_invoice_business_date_version();

create table public.invoice_date_recovery_batches (
 id uuid primary key, operation text not null check(operation in ('recover','reverse')),
 reverses_batch_id uuid references public.invoice_date_recovery_batches(id),
 reviewed_rows jsonb not null, reason text not null check(length(trim(reason))>0),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default clock_timestamp(),
 result jsonb
);
create table public.invoice_date_recovery_events (
 id uuid primary key default gen_random_uuid(),
 batch_id uuid not null references public.invoice_date_recovery_batches(id),
 invoice_id uuid not null references public.invoices(id),
 old_date date, new_date date, date_version bigint not null,
 source text not null, evidence_hash text not null, evidence jsonb not null,
 reason text not null, created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default clock_timestamp(),
 reverses_event_id uuid unique references public.invoice_date_recovery_events(id),
 unique(batch_id,invoice_id)
);
alter table public.invoice_date_recovery_batches enable row level security;
alter table public.invoice_date_recovery_events enable row level security;

create function public.invoice_date_recovery_access() returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role in ('owner','manager')
  and is_active and deleted_at is null)
$$;
create policy invoice_date_event_read on public.invoice_date_recovery_events for select to authenticated
using(public.invoice_date_recovery_access() and exists(select 1 from public.invoices i
 where i.id=invoice_id and public.user_has_store_access(i.store_id)));
-- Batches contain the operator's reviewed set; avoid exposing another store's payload.
create policy invoice_date_batch_read on public.invoice_date_recovery_batches for select to authenticated
using(public.invoice_date_recovery_access() and created_by=auth.uid());
revoke all on public.invoice_date_recovery_batches,public.invoice_date_recovery_events from anon,authenticated;
grant select on public.invoice_date_recovery_batches,public.invoice_date_recovery_events to authenticated;

create function public.invoice_date_parse(p text) returns date
language plpgsql immutable set search_path=public as $$
declare d date;
begin
 if p is null or p !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return null; end if;
 d:=p::date;
 if not isfinite(d) or to_char(d,'YYYY-MM-DD')<>p then return null; end if;
 return d;
exception when others then return null;
end $$;
create function public.invoice_timestamp_parse(p text) returns timestamptz
language plpgsql immutable set search_path=public as $$
declare d timestamptz;
begin
 -- A timestamp without a zone is not reliable evidence. Date-only values have
 -- their own parser and must never acquire a timezone.
 if p is null or p !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then return null; end if;
 d:=p::timestamptz;
 if not isfinite(d) then return null; end if;
 return d;
exception when others then return null;
end $$;

-- Private source collector. Scalar aggregates prevent payments/revisions from
-- multiplying invoice rows. Include complete evidence in the staleness token.
create function public.invoice_date_evidence(p_id uuid) returns jsonb
language sql stable security definer set search_path=public set timezone='UTC' as $$
 select jsonb_build_object('invoice',to_jsonb(i),'history',coalesce((
   select jsonb_agg(h.data order by h.at,h.seq,h.key) from (
    select r.edited_at at,r.revision_no seq,'revision:'||r.id key,
     jsonb_build_object('key','revision:'||r.id,'at',r.edited_at,'sequence',r.revision_no,'kind','revision',
      'reason',r.edit_reason,'before',r.snapshot->'invoice','after',r.after_snapshot->'invoice') data
    from public.invoice_revisions r where r.invoice_id=i.id
    union all
    select coalesce(matched.at,a.created_at),matched.seq,'audit:'||a.id,
     jsonb_build_object('key','audit:'||a.id,'at',coalesce(matched.at,a.created_at),'recorded_at',a.created_at,'sequence',matched.seq,'kind',a.action,
      'reason',concat_ws(' ',a.module,a.reason),
      'before',case when jsonb_typeof(a.old_data->'invoice')='object' then a.old_data->'invoice' else a.old_data end,
      'after',case when jsonb_typeof(a.new_data->'invoice')='object' then a.new_data->'invoice' else a.new_data end)
    from public.audit_logs a
    left join lateral (
     -- A full audit copied from exactly one revision shares that revision's
     -- ordering. Do not invent an order for unrelated or partial audit records.
     select case when count(*)=1 then min(r.revision_no) else 0 end seq,
       case when count(*)=1 then min(r.edited_at) end at
     from public.invoice_revisions r where r.invoice_id=i.id
      and a.old_data->'invoice'->>'id'=i.id::text
      and a.old_data->'invoice'=r.snapshot->'invoice'
      and a.new_data->'invoice'=r.after_snapshot->'invoice'
    ) matched on true
    where a.table_name='invoices' and a.record_id=i.id
   ) h),'[]'::jsonb),
   'exchange',case when i.exchange_id is not null then (select to_jsonb(e) from public.product_exchanges e where e.id=i.exchange_id) end,
   'payments',coalesce((select jsonb_agg(jsonb_build_object('payment',to_jsonb(p),'wallet',m.is_wallet_credit) order by p.id)
    from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id where p.invoice_id=i.id),'[]'::jsonb))
 from public.invoices i where i.id=p_id
$$;

-- Serialize invoice history writers with recovery. An audit/revision committed
-- while apply waits is visible to its fresh evidence read; evidence cannot be
-- inserted between that read and the date update. Other modules are untouched.
create function public.lock_invoice_date_history() returns trigger
language plpgsql security definer set search_path=public as $$
declare old_id uuid; new_id uuid;
begin
 if tg_table_name='invoice_revisions' then
  if tg_op<>'INSERT' then old_id:=old.invoice_id; end if;
  if tg_op<>'DELETE' then new_id:=new.invoice_id; end if;
 else
  if tg_op<>'INSERT' and old.table_name='invoices' then old_id:=old.record_id; end if;
  if tg_op<>'DELETE' and new.table_name='invoices' then new_id:=new.record_id; end if;
 end if;
 perform 1 from public.invoices where id in (old_id,new_id) order by id for update;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
create trigger invoice_date_revision_lock before insert or update or delete on public.invoice_revisions
for each row execute function public.lock_invoice_date_history();
create trigger invoice_date_audit_lock before insert or update or delete on public.audit_logs
for each row execute function public.lock_invoice_date_history();

-- Pure, conservative planner. Only business_date is a known authoritative
-- date-only invoice field in this schema. Unknown legacy formats require review.
create function public.plan_invoice_date_recovery(e jsonb) returns jsonb
language plpgsql immutable set search_path=public as $$
declare i jsonb:=e->'invoice'; h jsonb; part jsonb;
 created timestamptz; observed_created timestamptz; created_day date;
 candidate date; observed date; latest_change jsonb; change_at timestamptz;
 event_at timestamptz; bad text[]:=array[]::text[]; provenance text[]:=array[]::text[];
 dates text[]:=array[]::text[]; source text; explanation text; classification text;
 amount numeric; old_part jsonb; new_part jsonb;
begin
 created:=public.invoice_timestamp_parse(i->>'created_at');
 created_day:=(created at time zone 'Asia/Singapore')::date;
 select coalesce(sum(case when p->'payment'->>'entry_kind'='correction_reversal'
  then -(p->'payment'->>'amount')::numeric else (p->'payment'->>'amount')::numeric end),0)
 into amount from jsonb_array_elements(coalesce(e->'payments','[]')) p
 where not coalesce((p->>'wallet')::boolean,false);
 if i->>'business_date' is not null then
  classification:='already_valid';candidate:=public.invoice_date_parse(i->>'business_date');
  source:='stored_business_date';explanation:='Preserve the existing business date, including intentional backdating.';
 else
  if created is null then provenance:=array_append(provenance,'Missing or invalid original creation timestamp.'); end if;
  if i ?| array['imported_at','import_batch_id','original_invoice_date','original_created_at','invoice_date'] or concat_ws(' ',i->>'notes',i->>'source',i->>'origin',i->>'imported_at',i->>'import_batch_id') ~* '(import|backdat|back.dat|migrat|original.date|original.invoice)' then
   provenance:=array_append(provenance,'Invoice contains import/backdating provenance that does not establish an original creation date.');
  end if;
  -- Explicit correction events provide an ordering; unrelated snapshots do not
  -- authorize replacing one historical date with another.
  for h in select value from jsonb_array_elements(coalesce(e->'history','[]')) loop
   old_part:=h->'before';new_part:=h->'after';
   event_at:=public.invoice_timestamp_parse(h->>'at');
   if event_at is null then bad:=array_append(bad,'History has an invalid event timestamp: '||(h->>'key')); end if;
   if concat_ws(' ',h->>'kind',h->>'reason') ~* '(import|backdat|back.dat|migrat|original.date|original.invoice)' then
    provenance:=array_append(provenance,'History contains import/backdating provenance: '||(h->>'key'));
   end if;
   foreach part in array array[old_part,new_part] loop
    if part ?| array['imported_at','import_batch_id','original_invoice_date','original_created_at','invoice_date'] or
       concat_ws(' ',part->>'notes',part->>'source',part->>'origin') ~* '(import|backdat|back.dat|migrat|original.date|original.invoice)' then
     provenance:=array_append(provenance,'History contains unsupported original-date or import metadata: '||(h->>'key'));
    end if;
    if part->>'created_at' is not null then
     observed_created:=public.invoice_timestamp_parse(part->>'created_at');
     if observed_created is null or observed_created is distinct from created then
      provenance:=array_append(provenance,'Recorded creation timestamps disagree or are invalid: '||(h->>'key'));
     end if;
    end if;
    if part->>'business_date' is not null then
     observed:=public.invoice_date_parse(part->>'business_date');
     if observed is null then bad:=array_append(bad,'Invalid historical business date: '||(h->>'key'));
     elsif not (observed::text=any(dates)) then dates:=array_append(dates,observed::text); end if;
    end if;
   end loop;
   if new_part ? 'business_date' and old_part ? 'business_date'
      and new_part->'business_date' is distinct from old_part->'business_date' then
    if latest_change is null or event_at>change_at or
       (event_at=change_at and coalesce((h->>'sequence')::int,0)>0 and coalesce((latest_change->>'sequence')::int,0)>0
        and (h->>'sequence')::int>(latest_change->>'sequence')::int) then
     latest_change:=h;change_at:=event_at;
    elsif event_at=change_at and new_part->'business_date' is distinct from latest_change->'after'->'business_date'
      and not(coalesce((h->>'sequence')::int,0)>0 and coalesce((latest_change->>'sequence')::int,0)>0
        and (h->>'sequence')::int<>(latest_change->>'sequence')::int) then
     bad:=array_append(bad,'Conflicting date corrections with indistinguishable ordering.');
    end if;
   end if;
  end loop;
  if latest_change is not null then
   candidate:=public.invoice_date_parse(latest_change->'after'->>'business_date');
   source:='intentional_correction:'||(latest_change->>'key');
   if candidate is null then bad:=array_append(bad,'The latest recorded date correction cleared the date or saved an invalid date.'); end if;
   for h in select value from jsonb_array_elements(coalesce(e->'history','[]')) loop
    event_at:=public.invoice_timestamp_parse(h->>'at');
    -- Revisions have an authoritative per-invoice sequence even when now() is
    -- identical. Audit entries with equal timestamps cannot break a tie.
    if event_at>change_at or (event_at=change_at and h->>'key'<>latest_change->>'key'
      and not(coalesce((h->>'sequence')::int,0)>0 and coalesce((latest_change->>'sequence')::int,0)>0
              and (h->>'sequence')::int<(latest_change->>'sequence')::int)) then
     if h->'before' ? 'business_date' and not coalesce(h->'after' ? 'business_date',false) then
      bad:=array_append(bad,'A later pre-edit snapshot has no recorded resulting date: '||(h->>'key'));
     end if;
     if h->'after' ? 'business_date' and h->'after'->>'business_date' is distinct from candidate::text then
      bad:=array_append(bad,'A later or unordered snapshot disagrees with the proposed corrected date: '||(h->>'key'));
     end if;
    end if;
   end loop;
   explanation:='Use the latest unambiguous intentional date correction; earlier dates are superseded.';
  elsif cardinality(dates)=1 then
   candidate:=public.invoice_date_parse(dates[1]);source:='original_audit_business_date';
   -- A before-only edit snapshot cannot establish what that edit saved.
   if not exists(select 1 from jsonb_array_elements(coalesce(e->'history','[]')) x
      where x->'after'->>'business_date'=candidate::text) then
    bad:=array_append(bad,'Only a pre-edit date survives; the resulting date is unknown.');
   end if;
   select max(public.invoice_timestamp_parse(x->>'at')) into change_at
    from jsonb_array_elements(coalesce(e->'history','[]')) x where x->'after'->>'business_date'=candidate::text;
   if exists(select 1 from jsonb_array_elements(coalesce(e->'history','[]')) x
     where public.invoice_timestamp_parse(x->>'at')>=change_at and
      ((x->'after' ? 'business_date' and x->'after'->>'business_date' is null) or
       (x->'before' ? 'business_date' and not coalesce(x->'after' ? 'business_date',false)))) then
    bad:=array_append(bad,'Later or unordered evidence cleared the date or lacks the resulting date.');
   end if;
   explanation:='Consistent explicit business date recorded in invoice audit history.';
  elsif cardinality(dates)>1 then
   bad:=array_append(bad,'Historical business dates disagree without a reliably ordered intentional correction.');
  else
   candidate:=created_day;source:='original_created_at_asia_singapore';
   bad:=bad||provenance;
   if coalesce((i->>'is_exchange')::boolean,false) then
    if public.invoice_timestamp_parse(e->'exchange'->>'created_at') is distinct from created or e->'exchange'->>'created_at' is null then
     bad:=array_append(bad,'Exchange conversion lacks a matching original exchange creation timestamp.');
    end if;
   end if;
   explanation:='Original creation timestamp converted to the Asia/Singapore calendar date; no import, backdating or conflicting date evidence found. Payment timing is not used.';
  end if;
  if candidate is null and cardinality(bad)=0 then bad:=array_append(bad,'No usable original invoice date evidence.'); end if;
  classification:=case when cardinality(bad)=0 then 'eligible' else 'manual_review' end;
  if classification='manual_review' then explanation:='Do not recover automatically. Review the recorded evidence using Correct Invoice.'; end if;
 end if;
 return jsonb_build_object('invoice_id',i->>'id','invoice_no',i->>'invoice_no','status',i->>'status','store_id',i->>'store_id',
  'existing_business_date',i->>'business_date','original_created_at',i->>'created_at','singapore_creation_date',created_day,
  'proposed_date',case when classification='eligible' then candidate end,'suggested_date',candidate,
  'source',source,'explanation',explanation,'classification',classification,'issues',to_jsonb(bad),'provenance_notes',to_jsonb(provenance),
  'recorded_business_dates',to_jsonb(dates),'evidence_hash',md5(e::text),'eligible_received_amount',amount,
  'sales_to_add',case when classification='eligible' and i->>'deleted_at' is null then amount else 0 end,
  'deleted_at',i->>'deleted_at');
end $$;

create function public.preview_invoice_date_recovery(p_ids uuid[] default null) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.invoice_date_recovery_access() then raise exception 'Only active Owners and Managers may review invoice date recovery.' using errcode='42501';end if;
 return query select public.plan_invoice_date_recovery(public.invoice_date_evidence(i.id))||jsonb_build_object('store',s.name)
 from public.invoices i left join public.stores s on s.id=i.store_id
 where (p_ids is null or i.id=any(p_ids)) and public.user_has_store_access(i.store_id) order by i.id;
end $$;

-- Internal writer: deliberately no UPDATE of status/paid_amount/line allocations
-- and no operational RPCs. Inspected effective triggers are transition-guarded
-- or UPDATE OF status. Tests snapshot every non-audit table around this path.
create function public.write_recovered_invoice_date(p_invoice uuid,p_date date,p_batch uuid,p_plan jsonb,p_evidence jsonb,p_reason text,p_reverses uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare before_row public.invoices%rowtype; after_row public.invoices%rowtype; rev uuid; event uuid; n int; stamp timestamptz:=clock_timestamp();
begin
 select * into strict before_row from public.invoices where id=p_invoice for update;
 select coalesce(max(revision_no),0)+1 into n from public.invoice_revisions where invoice_id=p_invoice;
 update public.invoices set business_date=p_date,edit_count=coalesce(edit_count,0)+1,edited_by=auth.uid(),edited_at=stamp
 where id=p_invoice returning * into after_row;
 insert into public.invoice_date_recovery_events(batch_id,invoice_id,old_date,new_date,date_version,source,evidence_hash,evidence,reason,created_by,reverses_event_id,created_at)
 values(p_batch,p_invoice,before_row.business_date,after_row.business_date,after_row.business_date_version,p_plan->>'source',p_plan->>'evidence_hash',p_evidence,p_reason,auth.uid(),p_reverses,stamp) returning id into event;
 insert into public.invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edited_at,edit_reason,request_id)
 values(p_invoice,n,jsonb_build_object('invoice',to_jsonb(before_row),'date_recovery_event',event),
 jsonb_build_object('invoice',to_jsonb(after_row),'date_recovery_event',event),auth.uid(),stamp,p_reason,p_batch) returning id into rev;
 perform public.write_audit_ex('invoices',p_invoice,case when p_reverses is null then 'invoice_date_recovered' else 'invoice_date_recovery_reversed' end,
  jsonb_build_object('invoice',to_jsonb(before_row)),jsonb_build_object('invoice',to_jsonb(after_row),'batch_id',p_batch,'event_id',event,'revision_id',rev),
  'invoices',p_reason,before_row.store_id);
 return event;
end $$;

create function public.apply_invoice_date_recovery(p_batch uuid,p_rows jsonb,p_reason text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare batch public.invoice_date_recovery_batches%rowtype; row jsonb; i public.invoices%rowtype; e jsonb; plan jsonb;
 results jsonb:='[]'; reason text; event uuid; invoice_id uuid;
begin
 if not public.invoice_date_recovery_access() then raise exception 'Only active Owners and Managers may recover invoice dates.' using errcode='42501';end if;
 if p_batch is null or nullif(trim(p_reason),'') is null or jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Supply a batch ID, reviewed rows and a recovery reason.';end if;
 if jsonb_array_length(p_rows)=0 or jsonb_array_length(p_rows)>500 then raise exception 'Review 1 to 500 invoices per recovery batch.';end if;
 if (select count(distinct x->>'invoice_id') from jsonb_array_elements(p_rows) x)<>jsonb_array_length(p_rows) then raise exception 'Each invoice must appear exactly once.';end if;
 insert into public.invoice_date_recovery_batches(id,operation,reviewed_rows,reason,created_by) values(p_batch,'recover',p_rows,p_reason,auth.uid()) on conflict(id) do nothing;
 select * into strict batch from public.invoice_date_recovery_batches where id=p_batch for update;
 if batch.operation<>'recover' or batch.reviewed_rows<>p_rows or batch.reason<>p_reason or batch.created_by<>auth.uid() then raise exception 'Batch ID already belongs to a different reviewed request.';end if;
 if batch.result is not null then return batch.result;end if;
 for row in select value from jsonb_array_elements(p_rows) order by value->>'invoice_id' loop
  invoice_id:=(row->>'invoice_id')::uuid;
  select * into i from public.invoices where id=invoice_id for update;
  if not found then raise exception 'Invoice not found.';end if;
  if not public.user_has_store_access(i.store_id) then raise exception 'No access to invoice store.' using errcode='42501';end if;
  reason:=null;event:=null;
  if i.business_date is not null then reason:='already_has_date';
  else
   e:=public.invoice_date_evidence(i.id);plan:=public.plan_invoice_date_recovery(e);
   if plan->>'evidence_hash' is distinct from row->>'evidence_hash' then reason:='evidence_changed';
   elsif plan->>'classification'<>'eligible' then reason:='requires_manual_review';
   elsif plan->>'proposed_date' is distinct from row->>'proposed_date' then reason:='proposal_changed';
   else event:=public.write_recovered_invoice_date(i.id,(plan->>'proposed_date')::date,p_batch,plan,e,p_reason);end if;
  end if;
  results:=results||jsonb_build_array(jsonb_build_object('invoice_id',i.id,'outcome',coalesce(reason,'recovered'),'event_id',event));
 end loop;
 update public.invoice_date_recovery_batches set result=results where id=p_batch;
 return results;
end $$;

create function public.reverse_invoice_date_recovery(p_original_batch uuid,p_batch uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare batch public.invoice_date_recovery_batches%rowtype; r public.invoice_date_recovery_events%rowtype;
 i public.invoices%rowtype; reason text; results jsonb:='[]'; e jsonb; event uuid;
begin
 if not public.invoice_date_recovery_access() then raise exception 'Only active Owners and Managers may reverse date recovery.' using errcode='42501';end if;
 if p_batch is null or nullif(trim(p_reason),'') is null then raise exception 'Supply a new batch ID and reversal reason.';end if;
 if not exists(select 1 from public.invoice_date_recovery_batches where id=p_original_batch and operation='recover') then raise exception 'Original recovery batch not found.';end if;
 insert into public.invoice_date_recovery_batches(id,operation,reverses_batch_id,reviewed_rows,reason,created_by)
 values(p_batch,'reverse',p_original_batch,'[]',p_reason,auth.uid()) on conflict(id) do nothing;
 select * into strict batch from public.invoice_date_recovery_batches where id=p_batch for update;
 if batch.operation<>'reverse' or batch.reverses_batch_id<>p_original_batch or batch.reason<>p_reason or batch.created_by<>auth.uid() then raise exception 'Batch ID already belongs to a different request.';end if;
 if batch.result is not null then return batch.result;end if;
 for r in select * from public.invoice_date_recovery_events where batch_id=p_original_batch order by invoice_id loop
  select * into strict i from public.invoices where id=r.invoice_id for update;
  if not public.user_has_store_access(i.store_id) then raise exception 'No access to invoice store.' using errcode='42501';end if;
  reason:=null;event:=null;
  if exists(select 1 from public.invoice_date_recovery_events where reverses_event_id=r.id) then reason:='already_reversed';
  elsif i.business_date is distinct from r.new_date or i.business_date_version<>r.date_version then reason:='date_changed_since_recovery';
  else
   e:=public.invoice_date_evidence(i.id);
   event:=public.write_recovered_invoice_date(i.id,r.old_date,p_batch,
    jsonb_build_object('source','reversal:'||r.id,'evidence_hash',md5(e::text)),e,p_reason,r.id);
  end if;
  results:=results||jsonb_build_array(jsonb_build_object('invoice_id',i.id,'outcome',coalesce(reason,'reversed'),'event_id',event));
 end loop;
 update public.invoice_date_recovery_batches set result=results where id=p_batch;
 return results;
end $$;

revoke all on function public.track_invoice_business_date_version(),public.lock_invoice_date_history(),public.invoice_date_parse(text),public.invoice_timestamp_parse(text),
 public.invoice_date_evidence(uuid),public.plan_invoice_date_recovery(jsonb),
 public.write_recovered_invoice_date(uuid,date,uuid,jsonb,jsonb,text,uuid) from public,anon,authenticated;
revoke all on function public.invoice_date_recovery_access(),public.preview_invoice_date_recovery(uuid[]),
 public.apply_invoice_date_recovery(uuid,jsonb,text),public.reverse_invoice_date_recovery(uuid,uuid,text) from public,anon;
grant execute on function public.invoice_date_recovery_access(),public.preview_invoice_date_recovery(uuid[]),
 public.apply_invoice_date_recovery(uuid,jsonb,text),public.reverse_invoice_date_recovery(uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
