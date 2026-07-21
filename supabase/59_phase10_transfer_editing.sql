-- =====================================================================
-- ENERGIA — PHASE 10: PENDING STOCK-TRANSFER EDITING
--
-- Only PENDING transfers can be edited. Adds a mandatory edit reason, source-
-- stock + destination-price revalidation, optimistic version checking, a
-- revision-history table, an "edited" marker, and full audit logging. Any other
-- status (approved / partially_approved / rejected / cancelled — and the
-- Phase-11 in-transit/received/completed statuses when they exist) stays locked.
--
-- Additive + idempotent. Run AFTER 58.
-- =====================================================================

set check_function_bodies = off;

-- ── Optimistic-concurrency version + edited marker on the request ──
alter table public.transfer_requests add column if not exists version integer not null default 1;
alter table public.transfer_requests add column if not exists edited_at timestamptz;
alter table public.transfer_requests add column if not exists edited_by uuid references public.profiles(id);
alter table public.transfer_requests add column if not exists edit_count integer not null default 0;

-- ── Revision history — one row per edit, snapshotting the prior state ──
create table if not exists public.transfer_request_revisions (
  id uuid primary key default gen_random_uuid(),
  transfer_request_id uuid not null references public.transfer_requests(id) on delete cascade,
  version integer not null,                    -- the version BEFORE this edit
  reason text not null,
  changed_summary jsonb,                       -- {field: {from, to}} + line diff
  snapshot jsonb,                              -- full prior header+lines snapshot
  edited_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_tr_revisions_req on public.transfer_request_revisions(transfer_request_id, version);

alter table public.transfer_request_revisions enable row level security;
drop policy if exists "read transfer revisions" on public.transfer_request_revisions;
create policy "read transfer revisions" on public.transfer_request_revisions
  for select to authenticated using (true);

-- =====================================================================
-- Permission helper: who may edit a given pending transfer.
--   Owner/Manager: any pending transfer.
--   Original requester (incl. Staff/Admin/Inventory Manager): their own.
--   Staff additionally cannot change source or destination (enforced below).
-- =====================================================================
create or replace function public.can_edit_transfer(p_transfer_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_req public.transfer_requests%rowtype;
begin
  select * into v_req from public.transfer_requests where id = p_transfer_id;
  if not found then return false; end if;
  if v_req.status <> 'pending' then return false; end if;
  if public.is_owner_or_manager() then return true; end if;
  -- everyone else may edit only their own request
  return v_req.requested_by = auth.uid();
end $$;

-- =====================================================================
-- Edit a pending transfer. Optimistic: caller passes the version it read;
-- if it no longer matches, the edit is rejected (no silent overwrite).
-- =====================================================================
create or replace function public.edit_transfer_request(
  p_transfer_id uuid,
  p_expected_version integer,
  p_reason text,
  p_source_type location_type default null,
  p_source_id uuid default null,
  p_dest_type location_type default null,
  p_dest_id uuid default null,
  p_lines jsonb default null,                  -- null = keep existing lines
  p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.transfer_requests%rowtype; v_role user_role;
  v_new_source_type location_type; v_new_source_id uuid;
  v_new_dest_type location_type; v_new_dest_id uuid;
  v_line jsonb; v_product_id uuid; v_qty integer; v_available integer;
  v_prod_ids uuid[] := '{}'; v_snapshot jsonb; v_summary jsonb := '{}'::jsonb;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile found for current user'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'An edit reason is required'; end if;

  -- Lock the row for the duration (serialises concurrent edits).
  select * into v_req from public.transfer_requests where id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found'; end if;

  -- Only PENDING is editable; everything else is locked.
  if v_req.status <> 'pending' then
    raise exception 'Only pending transfers can be edited (this one is %)', v_req.status; end if;

  -- Optimistic concurrency: the version must match what the editor last saw.
  if p_expected_version is not null and p_expected_version <> v_req.version then
    raise exception 'This transfer was changed by someone else (expected version %, current %). Please reload and try again.',
      p_expected_version, v_req.version; end if;

  -- Permission: Owner/Manager any pending; otherwise only own request.
  if not public.is_owner_or_manager() and v_req.requested_by <> auth.uid() then
    raise exception 'You can only edit your own pending transfer requests'; end if;

  -- Resolve the new header values (null = unchanged).
  v_new_source_type := coalesce(p_source_type, v_req.source_type);
  v_new_source_id   := coalesce(p_source_id, v_req.source_id);
  v_new_dest_type   := coalesce(p_dest_type, v_req.dest_type);
  v_new_dest_id     := coalesce(p_dest_id, v_req.dest_id);

  -- Staff (and non-owner/manager) cannot change source or destination.
  if not public.is_owner_or_manager() then
    if v_new_source_type <> v_req.source_type or v_new_source_id <> v_req.source_id
       or v_new_dest_type <> v_req.dest_type or v_new_dest_id <> v_req.dest_id then
      raise exception 'Only an Owner or Manager can change the source or destination of a transfer'; end if;
  end if;

  if v_new_source_type = v_new_dest_type and v_new_source_id = v_new_dest_id then
    raise exception 'Source and destination must be different'; end if;

  -- Staff store-scope check when an Owner/Manager is NOT the editor.
  if v_role = 'staff' then
    if v_new_source_type = 'store' and not public.user_has_store_access(v_new_source_id) then
      raise exception 'Staff can only transfer from their assigned store'; end if;
  end if;

  -- Snapshot the PRIOR state for revision history.
  v_snapshot := jsonb_build_object(
    'source_type', v_req.source_type, 'source_id', v_req.source_id,
    'dest_type', v_req.dest_type, 'dest_id', v_req.dest_id,
    'note', v_req.note,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('product_id', l.product_id, 'quantity', l.quantity))
                        from public.transfer_request_lines l where l.transfer_request_id = p_transfer_id), '[]'::jsonb));

  -- Build a light change summary for the header.
  if v_new_source_id <> v_req.source_id or v_new_source_type <> v_req.source_type then
    v_summary := v_summary || jsonb_build_object('source', jsonb_build_object('from', v_req.source_id, 'to', v_new_source_id)); end if;
  if v_new_dest_id <> v_req.dest_id or v_new_dest_type <> v_req.dest_type then
    v_summary := v_summary || jsonb_build_object('dest', jsonb_build_object('from', v_req.dest_id, 'to', v_new_dest_id)); end if;
  if coalesce(p_note, v_req.note) is distinct from v_req.note then
    v_summary := v_summary || jsonb_build_object('note', jsonb_build_object('from', v_req.note, 'to', p_note)); end if;

  -- If new lines were provided, validate + replace them.
  if p_lines is not null then
    if jsonb_array_length(p_lines) = 0 then raise exception 'At least one product line is required'; end if;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      v_product_id := (v_line->>'product_id')::uuid;
      v_qty := (v_line->>'quantity')::integer;
      if v_product_id is null then raise exception 'Each line needs a product'; end if;
      if v_qty is null or v_qty <= 0 then raise exception 'Each line quantity must be greater than zero'; end if;
      -- Source-stock validation at the (possibly new) source.
      if v_new_source_type = 'warehouse' then
        select current_qty into v_available from public.warehouse_inventory
          where warehouse_id = v_new_source_id and product_id = v_product_id;
      else
        select current_qty into v_available from public.store_inventory
          where store_id = v_new_source_id and product_id = v_product_id;
      end if;
      if coalesce(v_available,0) < v_qty then
        raise exception 'Insufficient stock at source for a product (have %, need %)', coalesce(v_available,0), v_qty; end if;
      v_prod_ids := array_append(v_prod_ids, v_product_id);
    end loop;

    -- Destination-price validation when the destination is a store.
    if v_new_dest_type = 'store' then
      perform public.assert_transfer_prices_ok(v_new_dest_id, v_prod_ids);
    end if;

    v_summary := v_summary || jsonb_build_object('lines_changed', true);
    delete from public.transfer_request_lines where transfer_request_id = p_transfer_id;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      insert into public.transfer_request_lines (transfer_request_id, product_id, quantity)
      values (p_transfer_id, (v_line->>'product_id')::uuid, (v_line->>'quantity')::integer);
    end loop;
  end if;

  -- Write the revision row (version BEFORE the edit) then bump the version.
  insert into public.transfer_request_revisions (transfer_request_id, version, reason, changed_summary, snapshot, edited_by)
  values (p_transfer_id, v_req.version, p_reason, v_summary, v_snapshot, auth.uid());

  update public.transfer_requests
     set source_type = v_new_source_type, source_id = v_new_source_id,
         dest_type = v_new_dest_type, dest_id = v_new_dest_id,
         note = coalesce(p_note, note),
         version = version + 1, edit_count = edit_count + 1,
         edited_at = now(), edited_by = auth.uid()
   where id = p_transfer_id;

  perform public.write_audit_ex('transfer_requests', p_transfer_id, 'transfer_edited',
    v_snapshot, v_summary, 'transfers', p_reason, null);

  return jsonb_build_object('id', p_transfer_id, 'new_version', v_req.version + 1, 'edit_count', v_req.edit_count + 1);
end $$;

-- List the revision history for a transfer (newest first).
create or replace function public.transfer_revisions(p_transfer_id uuid)
returns table (
  version integer, reason text, changed_summary jsonb, snapshot jsonb,
  editor text, created_at timestamptz
) language sql stable security definer set search_path = public as $$
  select r.version, r.reason, r.changed_summary, r.snapshot, pr.full_name, r.created_at
  from public.transfer_request_revisions r
  left join public.profiles pr on pr.id = r.edited_by
  where r.transfer_request_id = p_transfer_id
  order by r.version desc;
$$;

notify pgrst, 'reload schema';
