begin;
-- Requires 184, 186, 190, 241 and 245. A replacement is a continuation of
-- recorded rights, not a new purchase at today's catalogue terms.
alter table public.therapy_voucher_issues
  add column source_issue_id uuid references public.therapy_voucher_issues(id);
create index therapy_voucher_issues_source on public.therapy_voucher_issues(source_issue_id);

alter function public.snapshot_therapy_voucher_issue(uuid,boolean)
  rename to snapshot_therapy_voucher_issue_current_catalogue;
revoke all on function public.snapshot_therapy_voucher_issue_current_catalogue(uuid,boolean) from public,anon,authenticated;

create function public.snapshot_therapy_voucher_issue(p_reward_voucher_id uuid,p_retrospective boolean default false)
returns uuid language plpgsql security definer set search_path=public as $$
declare rv public.customer_reward_vouchers%rowtype; original public.therapy_voucher_issues%rowtype;
 source_voucher uuid; issue_id uuid; source_reason text;
begin
 select * into rv from public.customer_reward_vouchers where id=p_reward_voucher_id for update;
 if not found then return null; end if;
 select id into issue_id from public.therapy_voucher_issues where reward_voucher_id=rv.id;
 if issue_id is not null then return issue_id; end if;
 if rv.source_type='invoice_benefit_transfer' then
  select b.reward_voucher_id,t.reason into source_voucher,source_reason
   from public.invoice_benefit_transfers t join public.invoice_benefit_values b on b.id=t.source_benefit_id
   where t.id=rv.source_id;
 elsif rv.source_type='invoice_reopen' then
  select b.reward_voucher_id,rv.notes into source_voucher,source_reason
   from public.invoice_reopen_vouchers q join public.invoice_benefit_values b on b.id=q.benefit_id
   where q.id=rv.source_id;
 else
  return public.snapshot_therapy_voucher_issue_current_catalogue(rv.id,p_retrospective);
 end if;
 if source_voucher is null or source_voucher=rv.id then
  raise exception 'The replacement voucher has no traceable original allocation. Review its source before recording therapy rights.';
 end if;
 select * into original from public.therapy_voucher_issues where reward_voucher_id=source_voucher for share;
 -- A legacy grant with no frozen rights stays unrecorded. Reviewing the
 -- original first, then the replacement, remains possible through the existing
 -- Manager review action. Today's definition must never fill this gap silently.
 if not found then return null; end if;
 if original.voucher_id<>rv.voucher_id or rv.quantity>original.units then
  raise exception 'Replacement voucher units do not match their original recorded rights';
 end if;
 insert into public.therapy_voucher_issues(
  reward_voucher_id,voucher_id,customer_id,definition_version,definition_snapshot,summary_text,
  units,sessions_per_unit,sessions_total,sessions_used,issued_at,valid_until,
  applied_retrospectively,applied_by,source_issue_id)
 values(rv.id,rv.voucher_id,rv.customer_id,original.definition_version,original.definition_snapshot,original.summary_text,
  rv.quantity,original.sessions_per_unit,rv.quantity*original.sessions_per_unit,0,original.issued_at,original.valid_until,
  original.applied_retrospectively,original.applied_by,original.id)
 returning id into issue_id;
 perform public.write_audit_ex('customer_reward_vouchers',rv.id,'therapy_rights_carried_from_original',
  to_jsonb(original),(select to_jsonb(t) from public.therapy_voucher_issues t where t.id=issue_id),
  'invoices',coalesce(source_reason,'Recorded original voucher rights preserved'),rv.store_id);
 return issue_id;
end $$;
revoke all on function public.snapshot_therapy_voucher_issue(uuid,boolean) from public,anon,authenticated;
create or replace function public.trg_snapshot_therapy_voucher_issue()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 perform public.snapshot_therapy_voucher_issue(new.id,false);
 return null;
end $$;
revoke all on function public.trg_snapshot_therapy_voucher_issue() from public,anon,authenticated;

-- The source issue remains immutable evidence of what was granted. Changes to
-- current units are separate records; a partial refund never rewrites its
-- original quantity, service definition, expiry or consumed-session history.
create table public.therapy_voucher_unit_changes(
 id uuid primary key default gen_random_uuid(),
 reward_voucher_id uuid not null references public.customer_reward_vouchers(id),
 issue_id uuid not null references public.therapy_voucher_issues(id),
 previous_units integer not null,new_units integer not null,
 previous_status text not null,new_status text not null,
 previous_available_sessions integer not null,new_available_sessions integer not null,
 reason text not null,created_by uuid references public.profiles(id),created_at timestamptz not null default now()
);
alter table public.therapy_voucher_unit_changes enable row level security;
create policy therapy_voucher_unit_changes_read on public.therapy_voucher_unit_changes for select to authenticated using(
 exists(select 1 from public.customer_reward_vouchers v where v.id=reward_voucher_id and public.user_has_store_access(v.store_id)));
grant select on public.therapy_voucher_unit_changes to authenticated;

create function public.record_therapy_voucher_unit_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare issue public.therapy_voucher_issues%rowtype; old_units integer; new_units integer;
begin
 if (old.quantity,old.status) is not distinct from (new.quantity,new.status) then return new; end if;
 select * into issue from public.therapy_voucher_issues where reward_voucher_id=old.id for update;
 if not found then return new; end if;
 if issue.sessions_used>0 and old.status='held'
  and (new.quantity<old.quantity or new.status='revoked') then
  raise exception 'This voucher has recorded session usage. Review unit-level consumption before refunding, cancelling or transferring its remaining units.';
 end if;
 old_units:=case when old.status='held' then least(old.quantity,issue.units) else 0 end;
 new_units:=case when new.status='held' then least(new.quantity,issue.units) else 0 end;
 insert into public.therapy_voucher_unit_changes(reward_voucher_id,issue_id,previous_units,new_units,
  previous_status,new_status,previous_available_sessions,new_available_sessions,reason,created_by)
 values(old.id,issue.id,old_units,new_units,old.status,new.status,
  greatest(old_units*issue.sessions_per_unit-issue.sessions_used,0),
  greatest(new_units*issue.sessions_per_unit-issue.sessions_used,0),
  coalesce(nullif(new.notes,''),'Voucher quantity or status changed'),auth.uid());
 return new;
end $$;
revoke all on function public.record_therapy_voucher_unit_change() from public,anon,authenticated;
create trigger therapy_voucher_unit_change before update of quantity,status on public.customer_reward_vouchers
 for each row execute function public.record_therapy_voucher_unit_change();

-- Keep the existing RPC signature and original sessions_total. Remaining
-- rights come from units still held multiplied by the original per-unit rights.
-- This also reads pre-migration partial refunds correctly without a backfill.
create or replace function public.customer_therapy_voucher_rights(p_customer_id uuid,p_as_of date default null)
returns table(reward_voucher_id uuid,voucher_id uuid,voucher_name text,status text,units integer,
 sessions_total integer,sessions_used integer,sessions_remaining integer,issued_at timestamptz,valid_until date,
 is_expired boolean,is_usable boolean,rights_recorded boolean,applied_retrospectively boolean,
 summary_text text,definition_snapshot jsonb)
language sql stable set search_path=public as $$
 select rv.id,rv.voucher_id,v.name,rv.status,
  case when rv.status='held' then least(rv.quantity,coalesce(i.units,rv.quantity)) else 0 end,
  coalesce(i.sessions_total,0),coalesce(i.sessions_used,0),rights.remaining,
  coalesce(i.issued_at,rv.issued_at),i.valid_until,
  (i.valid_until is not null and i.valid_until<coalesce(p_as_of,public.sg_today())),
  (rv.status='held' and i.id is not null and rights.remaining>0
   and (i.valid_until is null or i.valid_until>=coalesce(p_as_of,public.sg_today()))),
  i.id is not null,coalesce(i.applied_retrospectively,false),
  case when i.id is null then 'No therapy-service rights recorded for this voucher.' else i.summary_text end,
  i.definition_snapshot
 from public.customer_reward_vouchers rv join public.vouchers v on v.id=rv.voucher_id
 left join public.therapy_voucher_issues i on i.reward_voucher_id=rv.id
 cross join lateral(select case when rv.status<>'held' then 0 else greatest(
  least(coalesce(i.units,0),rv.quantity)*coalesce(i.sessions_per_unit,0)-coalesce(i.sessions_used,0),0) end remaining) rights
 where rv.customer_id=p_customer_id order by rv.issued_at desc,rv.id
$$;
revoke all on function public.customer_therapy_voucher_rights(uuid,date) from public,anon;
grant execute on function public.customer_therapy_voucher_rights(uuid,date) to authenticated;
notify pgrst,'reload schema';
commit;
