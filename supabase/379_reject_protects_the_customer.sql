-- 379_reject_protects_the_customer.sql
--
-- AN OWNER'S OR MANAGER'S REJECT PROTECTS THE SUGGESTED CUSTOMER, AS UNLINK
-- DOES (the owner's decision, 2 Oct 2026: "Yes, make Reject protect the
-- customer too")
--
--   378 let staff settle affiliate account claims, and made an Owner's Unlink
--   protect the customer it unlinked: afterwards staff cannot link any login
--   to them, and sign-up no longer links one to them by itself. A Reject did
--   less. It held back the one login whose claim was rejected, which is told
--   "Account verification was unsuccessful" while the rejected claim is kept.
--   A new login suggesting the same customer could still be linked by staff,
--   with no flag (378, WHAT THIS DOES NOT COVER, last point).
--
--   Now, once an Owner or a Manager rejects a claim, the customer that claim
--   suggested (its candidate_customer_id) is protected the way an Owner's
--   Unlink protects a customer:
--   1. Staff cannot link any login to that customer: not the rejected
--      claim's login (once that claim is deleted and the person signs in
--      again), nor any other, whatever customer its claim suggests and
--      whatever phone it entered. affiliate_claim_link_check (so the Resolve
--      window, and resolve_affiliate_account_claim) refuses them, after the
--      two unlink refusals and before the phone rules: "An Owner or Manager
--      rejected a claim for this customer. Only an Owner or Manager can link a
--      login to them." It also answers customer_previously_rejected, and
--      customer_rejected_at (the latest such rejection). An Owner or Manager
--      may still link them.
--   2. Pending Account Claims flag a claim whose suggested customer is
--      protected this way (suggested_customer_rejected). So do Rejected
--      Account Claims (affiliate_rejected_claims), beside 378's
--      rejected_by_staff; the page reads either flag as "379 is here".
--   3. Sign-up (complete_affiliate_onboarding) no longer links a login by
--      itself to that customer. Where its verified email, phone and name all
--      match them, which used to link straight away, it now parks a pending
--      claim suggesting them. For a login with a rejected claim still kept,
--      it answers "Account verification was unsuccessful", as it does for any
--      claim it cannot settle. This is what 378 does for a customer an Owner
--      unlinked a login from. For every other customer sign-up is unchanged.
--   4. Resolve's audit row also records customer_previously_rejected.
--   5. An Owner or Manager can take over a rejection a member of staff made
--      (reject_affiliate_account_claim on a claim already rejected by staff).
--      Before, they were told "already rejected" and had no way to protect
--      the customer. Now the rejection becomes theirs: rejected_by and
--      rejected_at are theirs, and the same protecting audit row is written
--      (its old_data keeps who rejected it before, when and why). A reason is
--      still required, as for every rejection. The staff member's reason is
--      kept, and the new one is added on a line of its own ("Confirmed by an
--      Owner: ..." / "Confirmed by a Manager: ...") unless it says the same.
--      Staff can then no longer delete it (378: only a staff member's
--      rejection is theirs to delete). Staff cannot take over anyone's
--      rejection, and an Owner's or Manager's rejection still answers
--      "already rejected" to everyone.
--   6. Reject locks the suggested customer's row before it writes, as Unlink
--      and Resolve do, so a staff Resolve for that customer waits for the
--      rejection and then sees it.
--   7. A customer's id (customers.id) cannot be changed by anyone signed in
--      (trigger trg_customers_id_fixed): "A customer's id cannot be changed."
--      RLS let any staff member update any column of a customer, id included,
--      and every foreign key to customers is ON UPDATE NO ACTION, so a
--      customer nothing referenced (once the rejected claim was deleted) could
--      be given a new id, and with it shed the protection, which is keyed on
--      the id. Nothing in the app changes an id: no function does
--      (merge_customer_records retires the duplicate and repoints the rows
--      that reference it; it never changes customers.id), and the Customers
--      page updates by id without sending one. The service role, migrations
--      and server jobs (no signed-in user, auth.uid() is null) are not
--      affected. This also keeps 378's Unlink protection, and every other
--      customer-keyed rule, on the customer.
--
--   What counts is the audit row reject_affiliate_account_claim writes:
--   'affiliate_claim_rejected', on affiliate_account_claims, with the claim's
--   candidate_customer_id in new_data. It counts only when it was written for
--   an Owner or a Manager, and through write_audit_ex:
--     - actor_role must be 'owner' or 'manager'. write_audit_ex takes it from
--       the writer's own profile (current_user_role), never from the caller.
--     - module must be 'affiliate'. Only write_audit_ex sets a module, and
--       signed-in users cannot call it (339). write_audit, which they can
--       call, leaves module empty, so a row anyone writes through it does not
--       count.
--     - table_name must be 'affiliate_account_claims'.
--   The audit row is read, not the claim, so deleting the rejected claim
--   later does not lift the protection. Signed-in users cannot write, change
--   or delete audit rows themselves (audit_logs has only a read policy).
--
--   Not protected:
--     - the customer of a claim a member of staff rejected (until an Owner or
--       Manager takes that rejection over);
--     - anyone, by a rejected claim that suggested no one.
--   A claim marked rejected with no such audit row protects no one either.
--
-- Everything else stays as 378 left it. Staff still Reject and Delete claims,
-- and delete only rejections a staff member made. What an Owner or Manager
-- may do is unchanged, apart from 5.
--
-- WHAT THIS DOES NOT COVER (reported to the owner)
--
--   - The protection has no end. Nothing lifts it: not deleting the rejected
--     claim, and not an Owner or Manager later linking a login to the
--     customer. Only an Owner or Manager can link a login to that customer
--     from then on. One exception: merging the protected customer into
--     another record (merge_customer_records, Owner or Manager only) moves
--     the claim to the kept customer but not the protection, which still
--     names the retired one. 378's Unlink protection behaves the same way.
--     Before merging a protected customer, check whether the kept record
--     needs protecting too.
--   - It protects the customer the claim suggested when it was rejected,
--     and only them. A claim that suggested no one protects no one; one that
--     suggested the wrong customer protects that customer, not the one the
--     Owner or Manager had in mind. The Reject window names the customer.
--   - Rejections an Owner or Manager made before 379, through the app, count
--     too (their audit rows have the same shape). Production had no
--     rejections on 2 Oct 2026.
--   - Rows in audit_logs are scanned (no index on action); fine at today's
--     size. A sign-up within moments of an Owner's or Manager's rejection is
--     not locked against it (sign-up takes no lock on the customer row).
--   - As in 378: for every customer not protected, staff who edit a
--     customer's email, name or phone can still steer which customer a
--     sign-up is linked to automatically.
--   - Reject, like Resolve, locks the claim before the customer, and a
--     customer merge (service role) locks the customers before it repoints
--     their claims. A Reject and a merge of that same customer at the same
--     moment can deadlock; PostgreSQL then stops one of them, which can be
--     run again. Nothing is half-written.
--
-- DEPLOY ORDER: apply this first, then push the page, so its new parts show
-- at once. Either order is safe: every new sentence, flag and button on the
-- page is shown only when the server's answer carries a 379 field (the
-- pending or rejected rows' suggested_customer_rejected, the Resolve check's
-- customer_previously_rejected), so before this is applied the page promises
-- nothing about protection.
--
-- SAFETY
--
-- Each patched function is guarded by the md5 of its prosrc after 378 (2 Oct
-- 2026): affiliate_claim_link_check, affiliate_pending_claims,
-- complete_affiliate_onboarding, resolve_affiliate_account_claim and
-- reject_affiliate_account_claim (production's post-378 values), and
-- affiliate_rejected_claims (378's header value: check it in production before
-- applying). So are the five it relies on:
--   - write_audit_ex and write_audit, and current_user_role, under both;
--   - is_owner_or_manager and affiliate_claim_staff, who may reject
--     (affiliate_claim_staff's value is from 378's header: check it in
--     production before applying).
-- Each patch's anchors must each occur exactly once. The trigger function
-- public.tg_customers_id_fixed() and the trigger trg_customers_id_fixed on
-- customers must not exist already, unless they are this migration's (the
-- function carries "379:"; the trigger is BEFORE UPDATE, FOR EACH ROW, WHEN
-- the id changes, enabled, and calls it). The whole migration is ONE
-- statement (a single DO block), and its first part makes every check before
-- anything is created. So a failed check stops the run with nothing
-- installed, whatever runs it: in a transaction or under autocommit, with or
-- without psql's ON_ERROR_STOP. A function already carrying "379:" is left
-- alone, so a second run changes nothing. Each patched function keeps its
-- grants. The new trigger function is executable by no client role (revoked
-- from public, anon and authenticated, as every trigger function here is).
-- Creating the trigger briefly locks customers against writes; lock_timeout
-- (5s) makes the run fail rather than queue behind a long write. One trigger
-- is added to customers; no column, row or existing grant is changed.
--
-- AFTER (md5(prosrc) once applied, for later guards; checked on a local copy
-- whose guarded functions match production, 2 Oct 2026):
--   affiliate_claim_link_check(uuid,uuid)            c63ee37234356165996e2090d03f0c16
--   affiliate_pending_claims()                       138a3f7aa793b608a95a7408c3b6aeb2
--   complete_affiliate_onboarding(text,text,text,boolean)  e08b8ce361b6c9ba9ccbb5e3c70e7e86
--   resolve_affiliate_account_claim(uuid,uuid,text)  90c216165aeeddd3d336dcba0e19f7bb
--   reject_affiliate_account_claim(uuid,text)        a063c2dedec5ff1245e85624329a2347
--   affiliate_rejected_claims()                      93f87dd1dca37de8116e302180bdd8ee
--   tg_customers_id_fixed()  (new)                   b1aac1e0b9876230b1622fb660087445
-- The five relied on are unchanged (see 0. below).

set lock_timeout = '5s';

-- The whole migration is ONE statement (a single DO block), so it is atomic
-- whatever runs it: in a transaction or under autocommit, with or without
-- psql's ON_ERROR_STOP. Every check comes first; nothing is created unless
-- all of them pass.
do $mig$
declare
  v record; d text; n int; k int;
  v_install text[] := '{}';
  v_trg_fn oid; v_trg_fn_379 boolean := false; v_trg_379 boolean := false;
begin
  -- ── 0. The versions this was tested against ──────────────────────────────
  -- Patched: production's bodies after 378.
  for v in select * from (values
      ('public.affiliate_claim_link_check(uuid,uuid)',            'ee5c2dd66f00355615ac6457190910f5'),
      ('public.affiliate_pending_claims()',                       '9e7f4adb02eab927a3f24c8388e0553d'),
      ('public.complete_affiliate_onboarding(text,text,text,boolean)', 'fe715c05db05ba2b34655ac9a519d0a4'),
      ('public.resolve_affiliate_account_claim(uuid,uuid,text)',  '2bf645318e225825a76a6a1ad1ff7446'),
      ('public.reject_affiliate_account_claim(uuid,text)',        '433ef3304aeb8c929da82eebda461224'),
      ('public.affiliate_rejected_claims()',                      'b9b1536edf619a632393497cb83c5304')) t(fn, ok)
  loop
    if to_regprocedure(v.fn) is null then raise exception '379: % is missing', v.fn; end if;
    if position('379:' in (select prosrc from pg_proc where oid = to_regprocedure(v.fn))) = 0
       and (select md5(prosrc) from pg_proc where oid = to_regprocedure(v.fn)) <> v.ok then
      raise exception '379: % is not the version this was tested against', v.fn; end if;
  end loop;
  -- Relied on, not patched: the two audit writers and the role they record
  -- (current_user_role, from the writer's own profile; write_audit_ex alone
  -- sets a module, and signed-in users cannot call it); and who may reject
  -- at all (is_owner_or_manager: an active Owner or Manager;
  -- affiliate_claim_staff: active staff).
  for v in select * from (values
      ('public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', '711fa18ef5da361a191e12db3db313a5'),
      ('public.write_audit(text,uuid,text,jsonb,jsonb)',  'b900ae6a263830edc721406da7c396c3'),
      ('public.current_user_role()',                      '38683d3be39913aba404fa202d77f1c8'),
      ('public.is_owner_or_manager()',                    '7f888d6df058283917622c3ad03ddd91'),
      ('public.affiliate_claim_staff()',                  '83b6916b704814ec818093b5b5c0247b')) t(fn, ok)
  loop
    if coalesce((select md5(prosrc) from pg_proc where oid = to_regprocedure(v.fn)), 'missing') <> v.ok then
      raise exception '379: % is not the version this was tested against', v.fn; end if;
  end loop;
  -- The customers.id trigger: its function and the trigger must be new, or
  -- this migration's own (then left alone).
  if to_regclass('public.customers') is null
     or not exists (select 1 from pg_attribute where attrelid = 'public.customers'::regclass
                       and attname = 'id' and not attisdropped) then
    raise exception '379: public.customers(id) is missing'; end if;
  if to_regprocedure('auth.uid()') is null then raise exception '379: auth.uid() is missing'; end if;
  v_trg_fn := to_regprocedure('public.tg_customers_id_fixed()');
  if v_trg_fn is not null then
    if position('379:' in (select prosrc from pg_proc where oid = v_trg_fn)) = 0 then
      raise exception '379: public.tg_customers_id_fixed() already exists and is not this migration''s'; end if;
    v_trg_fn_379 := true;
  end if;
  select t.tgfoid, t.tgtype, t.tgenabled, pg_get_triggerdef(t.oid) as def into v
    from pg_trigger t where t.tgrelid = 'public.customers'::regclass and t.tgname = 'trg_customers_id_fixed';
  if found then
    -- 19 = FOR EACH ROW, BEFORE, UPDATE.
    if v.tgfoid is distinct from v_trg_fn or v.tgtype <> 19 or v.tgenabled <> 'O'
       or position('WHEN ((new.id IS DISTINCT FROM old.id))' in v.def) = 0 then
      raise exception '379: trigger trg_customers_id_fixed on public.customers already exists and is not this migration''s'; end if;
    v_trg_379 := true;
  end if;

  -- ── 1. The patches: each is worked out, and its anchors checked (each must
  -- occur exactly once), before anything is created. A function already
  -- carrying "379:" is left alone.
  for v in select * from (values
    ('public.affiliate_claim_link_check(uuid,uuid)',
  array[
    $a$  v_unlinked_at timestamptz; v_cust_unlinked_at timestamptz; v_since timestamptz;$a$,
    $a$  select max(l.created_at) into v_cust_unlinked_at from public.audit_logs l
   where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
     and l.actor_role = 'owner' and l.module = 'affiliate'
     and l.old_data->>'customer_id' = c.id::text;$a$,
    $a$    when v_cust_unlinked_at is not null then
      'An Owner unlinked a login from this customer before. Only an Owner or Manager can link a login to them.'$a$,
    $a$    'customer_previously_unlinked', v_cust_unlinked_at is not null, 'customer_unlinked_at', v_cust_unlinked_at,$a$],
  array[
    $r$  v_unlinked_at timestamptz; v_cust_unlinked_at timestamptz; v_since timestamptz;
  v_cust_rejected_at timestamptz;$r$,
    $r$  select max(l.created_at) into v_cust_unlinked_at from public.audit_logs l
   where l.table_name = 'affiliate_accounts' and l.action = 'affiliate_login_unlinked'
     and l.actor_role = 'owner' and l.module = 'affiliate'
     and l.old_data->>'customer_id' = c.id::text;
  -- 379: an Owner or Manager rejected a claim that suggested this customer:
  -- for staff, no login is linked to them, as after an Owner's unlink. The
  -- rejection's audit row (reject_affiliate_account_claim), not the claim, so
  -- deleting the rejected claim does not lift it. Only a row written for an
  -- Owner or Manager counts: actor_role is the writer's own role
  -- (current_user_role), and module 'affiliate' is set only through
  -- write_audit_ex, which signed-in users cannot call. A staff member's
  -- rejection, and a row anyone writes through write_audit, do not count.
  select max(l.created_at) into v_cust_rejected_at from public.audit_logs l
   where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
     and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
     and l.new_data->>'candidate_customer_id' = c.id::text;$r$,
    $r$    when v_cust_unlinked_at is not null then
      'An Owner unlinked a login from this customer before. Only an Owner or Manager can link a login to them.'
    -- 379: an Owner or Manager rejected a claim for this customer.
    when v_cust_rejected_at is not null then
      'An Owner or Manager rejected a claim for this customer. Only an Owner or Manager can link a login to them.'$r$,
    $r$    'customer_previously_unlinked', v_cust_unlinked_at is not null, 'customer_unlinked_at', v_cust_unlinked_at,
    -- 379: an Owner or Manager rejected a claim for the chosen customer, and when (the latest).
    'customer_previously_rejected', v_cust_rejected_at is not null, 'customer_rejected_at', v_cust_rejected_at,$r$]),
    ('public.affiliate_pending_claims()',
  array[
    $a$    'suggested_customer_unlinked', uc378.customer_id is not null
    ) order by cl.created_at), '[]'::jsonb) into v_rows$a$,
    $a$         on uc378.customer_id = cl.candidate_customer_id::text
  where cl.status = 'pending';$a$],
  array[
    $r$    'suggested_customer_unlinked', uc378.customer_id is not null,
    -- 379: whether an Owner or Manager rejected a claim that suggested the
    -- likely customer (staff cannot link a login to them).
    'suggested_customer_rejected', rc379.customer_id is not null
    ) order by cl.created_at), '[]'::jsonb) into v_rows$r$,
    $r$         on uc378.customer_id = cl.candidate_customer_id::text
  -- 379: the customers an Owner or Manager rejected a claim for (the
  -- rejections' audit rows, counted as affiliate_claim_link_check counts
  -- them), read once for the whole list.
  left join (select distinct l.new_data->>'candidate_customer_id' as customer_id
               from public.audit_logs l
              where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
                and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
                and l.new_data->>'candidate_customer_id' is not null) rc379
         on rc379.customer_id = cl.candidate_customer_id::text
  where cl.status = 'pending';$r$]),
    ('public.complete_affiliate_onboarding(text,text,text,boolean)',
  array[
    $a$                           and l.old_data->>'customer_id' = v_phone_cust::text) then$a$],
  array[
    $r$                           and l.old_data->>'customer_id' = v_phone_cust::text)
        -- 379: nor to a customer an Owner or Manager rejected a claim for (the
        -- rejection's audit row, as affiliate_claim_link_check reads it). That
        -- sign-up is parked as a pending claim suggesting them too, or, for a
        -- login with a rejected claim, told it was unsuccessful.
        and not exists (select 1 from public.audit_logs l
                         where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
                           and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
                           and l.new_data->>'candidate_customer_id' = v_phone_cust::text) then$r$]),
    ('public.resolve_affiliate_account_claim(uuid,uuid,text)',
  array[
    $a$      'customer_previously_unlinked', (v378->>'customer_previously_unlinked')::boolean,$a$],
  array[
    $r$      'customer_previously_unlinked', (v378->>'customer_previously_unlinked')::boolean,
      -- 379: whether an Owner or Manager had rejected a claim for this customer.
      'customer_previously_rejected', (v378->>'customer_previously_rejected')::boolean,$r$]),
    ('public.reject_affiliate_account_claim(uuid,text)',
  array[
    $a$  if v_claim.status = 'rejected' then
    return jsonb_build_object('ok', false, 'already', true, 'message', 'This claim has already been rejected.');
  end if;$a$,
    $a$     set status = 'rejected', rejected_by = auth.uid(), rejected_at = now(), rejection_reason = p_reason$a$,
    $a$  perform public.write_audit_ex('affiliate_account_claims', p_claim_id, 'affiliate_claim_rejected', null,$a$,
    $a$  return jsonb_build_object('ok', true);$a$],
  array[
    $r$  if v_claim.status = 'rejected' then
    -- 379: an Owner or Manager takes over a rejection a member of staff
    -- made, so that it protects the suggested customer (a staff member's
    -- rejection does not). Anything else already rejected stays as it is:
    -- staff take over no one's, and an Owner's or Manager's rejection is
    -- already theirs.
    if not (public.is_owner_or_manager()
            and exists (select 1 from public.profiles p where p.id = v_claim.rejected_by and p.role = 'staff')) then
      return jsonb_build_object('ok', false, 'already', true, 'message', 'This claim has already been rejected.');
    end if;
  end if;

  -- 379: the suggested customer's row first, as Unlink and Resolve lock it:
  -- a staff Resolve for that customer waits for this rejection, then sees it.
  perform 1 from public.customers where id = v_claim.candidate_customer_id for update;$r$,
    $r$     set status = 'rejected', rejected_by = auth.uid(), rejected_at = now(),
         -- 379: taking over keeps the staff member's reason and adds this
         -- one on a line of its own, unless it says the same.
         rejection_reason = case
           when v_claim.status <> 'rejected' then p_reason
           when btrim(coalesce(v_claim.rejection_reason, '')) = btrim(p_reason) then v_claim.rejection_reason
           else concat_ws(E'\n', nullif(btrim(coalesce(v_claim.rejection_reason, '')), ''),
                  'Confirmed by ' || case public.current_user_role() when 'owner' then 'an Owner' else 'a Manager' end
                  || ': ' || btrim(p_reason))
         end$r$,
    $r$  -- 379: this row is what protects the suggested customer when it is
  -- written for an Owner or Manager. Taking over a staff member's rejection
  -- writes it too, and keeps who rejected it before, when and why.
  perform public.write_audit_ex('affiliate_account_claims', p_claim_id, 'affiliate_claim_rejected',
    case when v_claim.status = 'rejected' then
      jsonb_build_object('status', v_claim.status, 'rejected_by', v_claim.rejected_by, 'rejected_by_staff', true,
                         'rejected_at', v_claim.rejected_at, 'rejection_reason', v_claim.rejection_reason) end,$r$,
    $r$  return jsonb_build_object('ok', true)
    -- 379: whether this took over a staff member's rejection.
    || case when v_claim.status = 'rejected' then jsonb_build_object('taken_over', true) else '{}'::jsonb end;$r$]),
    ('public.affiliate_rejected_claims()',
  array[
    $a$    'rejected_by_staff', exists (select 1 from public.profiles p where p.id = cl.rejected_by and p.role = 'staff')
    ) order by cl.rejected_at desc nulls last, cl.created_at desc), '[]'::jsonb) into v_rows
  from public.affiliate_account_claims cl where cl.status = 'rejected';$a$],
  array[
    $r$    'rejected_by_staff', exists (select 1 from public.profiles p where p.id = cl.rejected_by and p.role = 'staff'),
    -- 379: whether an Owner or Manager rejected a claim (this one or another)
    -- that suggested the likely customer, so staff cannot link a login to
    -- them; counted as affiliate_claim_link_check counts it.
    'suggested_customer_rejected', rc379.customer_id is not null
    ) order by cl.rejected_at desc nulls last, cl.created_at desc), '[]'::jsonb) into v_rows
  from public.affiliate_account_claims cl
  left join (select distinct l.new_data->>'candidate_customer_id' as customer_id
               from public.audit_logs l
              where l.table_name = 'affiliate_account_claims' and l.action = 'affiliate_claim_rejected'
                and l.actor_role in ('owner', 'manager') and l.module = 'affiliate'
                and l.new_data->>'candidate_customer_id' is not null) rc379
         on rc379.customer_id = cl.candidate_customer_id::text
  where cl.status = 'rejected';$r$])
  ) t(fn, f, r)
  loop
    d := pg_get_functiondef(to_regprocedure(v.fn));
    if position('379:' in d) > 0 then raise notice '379: % already patched; left alone.', v.fn; continue; end if;
    for k in 1 .. cardinality(v.f) loop
      n := (length(d) - length(replace(d, v.f[k], ''))) / length(v.f[k]);
      if n <> 1 then raise exception '379: % anchor % found % times', v.fn, k, n; end if;
    end loop;
    for k in 1 .. cardinality(v.f) loop
      d := replace(d, v.f[k], v.r[k]);
    end loop;
    v_install := v_install || d;
  end loop;

  -- Every check has passed. From here on, the functions are created. Each
  -- patched function keeps its owner, its grants and its signature.

  -- ── 2. Install the patched functions ─────────────────────────────────────
  foreach d in array v_install loop
    execute d;
  end loop;

  -- ── 3. A customer's id is fixed for anyone signed in ─────────────────────
  if v_trg_fn_379 then
    raise notice '379: public.tg_customers_id_fixed() already there; left alone.';
  else
    execute $ddl$
create function public.tg_customers_id_fixed() returns trigger
language plpgsql
set search_path = public
as $fn$
begin
  -- 379: a customer's id never changes for anyone signed in. Protections are
  -- keyed on it (an Owner's or Manager's rejection, an Owner's unlink), and
  -- RLS lets staff update any column of a customer. Nothing in the app
  -- changes an id; the service role, migrations and server jobs (no
  -- signed-in user) are not affected.
  if new.id is distinct from old.id and auth.uid() is not null then
    raise exception 'A customer''s id cannot be changed.' using errcode = '42501';
  end if;
  return new;
end
$fn$
$ddl$;
    -- A trigger function is no endpoint (339): as for every other one here.
    execute 'revoke all on function public.tg_customers_id_fixed() from public, anon, authenticated';
  end if;
  if v_trg_379 then
    raise notice '379: trigger trg_customers_id_fixed already there; left alone.';
  else
    execute 'create trigger trg_customers_id_fixed before update on public.customers for each row '
         || 'when (new.id is distinct from old.id) execute function public.tg_customers_id_fixed()';
  end if;
end $mig$;

notify pgrst, 'reload schema';
