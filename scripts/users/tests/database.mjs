// Migrations 230 and 231 against the isolated local database.
//
//   scripts/auth-email/bootstrap-local.sh start
//   npm run test:users:db
//
// The permission matrix is only worth having if it cannot be walked around, so
// most of this file tries to walk around it.

import { execFileSync } from 'node:child_process';

process.env.PGHOST ??= '/tmp'; process.env.PGPORT ??= '55442';
process.env.PGUSER ??= 'postgres'; process.env.PGDATABASE ??= 'energia_auth_email_test';
if (process.env.PGDATABASE !== 'energia_auth_email_test' || process.env.PGPORT !== '55442') {
  throw new Error('Refusing to run outside the disposable database on port 55442.');
}
const args = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'];
const sql = s => execFileSync('psql', [...args, '-c', s], { encoding: 'utf8' }).trim();
// Each psql invocation is its own session, so "who am I" has to travel with the
// query. This is how a test becomes a particular signed-in user.
const asUser = (userId, s) =>
  execFileSync('psql', [...args,
    '-c', `select set_config('test.user_id', '${userId ?? ''}', false);`,
    '-c', s], { encoding: 'utf8' }).trim().split('\n').filter(Boolean).pop();
const jsonAs = (userId, s) => JSON.parse(asUser(userId, s));
const failsAs = (userId, s) => {
  try { asUser(userId, s); return null; }
  catch (e) { return String(e.stderr ?? e.message); }
};

let pass = 0;
const ok = (label, cond, detail = '') => {
  console.log(`${cond ? 'PASS' : 'FAIL'}: ${label}${detail ? ` — ${detail}` : ''}`);
  if (!cond) process.exitCode = 1; else pass++;
};

const apply = f => execFileSync('psql', [...args, '-f', f], { encoding: 'utf8' });
apply('scripts/users/tests/prior-state.sql');
for (const f of ['230_user_invitations', '231_profile_role_change_guard']) {
  apply(`supabase/${f}.sql`);
  apply(`supabase/${f}.sql`);
}
ok('migrations 230-231 apply over the pre-230 schema, and apply again, cleanly', true);

// --- people and stores ------------------------------------------------------
// This database is shared with the other suites' fixtures, so the cleanup is
// scoped to rows this file owns rather than truncating tables other tests and
// their foreign keys depend on.
sql(`delete from public.user_invitations;
     delete from public.audit_logs where table_name = 'user_invitations';
     delete from public.affiliate_accounts where email like '%@energia.test';
     delete from public.user_store_assignments
      where user_id in (select id from public.profiles where email like '%@energia.test');
     delete from public.profiles where email like '%@energia.test';
     delete from public.stores where name like 'usertest-%';`);

const store = n => sql(`insert into public.stores (name) values ('usertest-${n}') returning id;`);
const STORE_A = store('Orchard'), STORE_B = store('Jurong');

const person = (name, email, role, active = true) =>
  sql(`insert into public.profiles (full_name, email, role, is_active, invitation_status)
       values ('${name}','${email}','${role}',${active},'accepted') returning id;`);

const OWNER    = person('Olivia Owner', 'owner@energia.test', 'owner');
const MANAGER  = person('Mahesh Manager', 'manager@energia.test', 'manager');
const STAFF    = person('Sam Staff', 'staff@energia.test', 'staff');
const INACTIVE = person('Ivan Inactive', 'inactive@energia.test', 'owner', false);
sql(`insert into public.user_store_assignments (user_id, store_id) values ('${MANAGER}','${STORE_A}');`);

const invite = (actor, reqId, email, name, role, stores = [], extra = {}) => {
  const arr = stores.length ? `array['${stores.join("','")}']::uuid[]` : `'{}'::uuid[]`;
  const q = (v) => v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
  // `in`, not `??`: a test passing null means "send nothing", and ?? would
  // helpfully substitute the default and test the opposite of what it says.
  const pick = (k, dflt) => (k in extra ? extra[k] : dflt);
  return jsonAs(actor, `select public.invite_user_begin('${reqId}','${email}','${name}','${role}',
      ${q(pick('work', '+6591110000'))}, ${q(pick('personal', '+6591110001'))},
      ${q(pick('pemail', 'personal@example.test'))}, ${arr});`);
};

// =============================================================================
// Who may create what
// =============================================================================
{
  const roles = ['owner', 'admin', 'manager', 'inventory_manager', 'staff'];
  const bad = [];
  for (const r of roles) {
    const res = invite(OWNER, `own-${r}`, `${r}.new@energia.test`, `New ${r}`, r, [STORE_A]);
    if (res.outcome !== 'created') bad.push(`${r}: ${res.outcome} ${res.message ?? ''}`);
  }
  ok('an Owner can invite every role', bad.length === 0, bad.join('; '));

  const roleList = jsonAs(OWNER, `select to_jsonb(public.assignable_roles());`);
  ok('and assignable_roles() says so', roleList.length === 5, roleList.join(','));
}

{
  const okRoles = ['staff', 'inventory_manager'];
  const bad = [];
  for (const r of okRoles) {
    const res = invite(MANAGER, `mgr-${r}`, `${r}.mgr@energia.test`, `Mgr ${r}`, r, [STORE_A]);
    if (res.outcome !== 'created') bad.push(`${r}: ${res.outcome} ${res.message ?? ''}`);
  }
  ok('a Manager can invite Staff and Inventory Managers', bad.length === 0, bad.join('; '));

  const blocked = [];
  for (const r of ['owner', 'admin', 'manager']) {
    const res = invite(MANAGER, `mgr-bad-${r}`, `${r}.bad@energia.test`, `Bad ${r}`, r, [STORE_A]);
    if (res.outcome !== 'forbidden') blocked.push(`${r} was allowed: ${res.outcome}`);
  }
  ok('a Manager cannot invite an Owner, Admin or Manager', blocked.length === 0, blocked.join('; '));

  const roleList = jsonAs(MANAGER, `select to_jsonb(public.assignable_roles());`);
  ok('and assignable_roles() offers a Manager only the two',
     roleList.length === 2 && roleList.includes('staff') && roleList.includes('inventory_manager'),
     roleList.join(','));
}

{
  const res = invite(MANAGER, 'mgr-store', 'wrongstore@energia.test', 'Wrong Store', 'staff', [STORE_B]);
  ok('a Manager cannot assign a store they do not manage',
     res.outcome === 'forbidden' && res.field === 'store_ids', `${res.outcome} ${res.message ?? ''}`);

  const allowed = jsonAs(MANAGER, `select to_jsonb(public.assignable_store_ids());`);
  ok('assignable_store_ids() offers a Manager only their own stores',
     allowed.length === 1 && allowed[0] === STORE_A, JSON.stringify(allowed));

  const ownerStores = jsonAs(OWNER, `select to_jsonb(public.assignable_store_ids());`);
  const allStores = Number(sql(`select count(*) from public.stores;`));
  ok('and an Owner every store', ownerStores.length === allStores,
     `${ownerStores.length} of ${allStores}`);
}

{
  const anon = invite(null, 'anon-1', 'anon@energia.test', 'Anon', 'staff');
  ok('an unauthenticated caller is refused', anon.outcome === 'forbidden', anon.outcome);

  const asStaff = invite(STAFF, 'staff-1', 'bystaff@energia.test', 'By Staff', 'staff');
  ok('a Staff member is refused', asStaff.outcome === 'forbidden', asStaff.outcome);

  const asInactive = invite(INACTIVE, 'inactive-1', 'byinactive@energia.test', 'By Inactive', 'staff');
  ok('a deactivated Owner is refused — is_active is checked, not just the role',
     asInactive.outcome === 'forbidden', asInactive.outcome);
}

// =============================================================================
// The escalation the edit form left open
// =============================================================================
{
  const target = person('Target Staff', 'target@energia.test', 'staff');

  // First, evidence that the guard is load-bearing. Inside a transaction that
  // is rolled back, with the trigger off, the promotion succeeds — which is the
  // state this database is in today, before migration 231.
  // Separate -c flags, not one: psql returns only the last result set of a
  // multi-statement -c, and the answer is in the middle. They share one session,
  // so the transaction still spans them and the rollback still undoes it all.
  const withoutGuard = execFileSync('psql', [...args,
    '-c', 'begin',
    '-c', `select set_config('test.user_id', '${MANAGER}', false)`,
    '-c', 'alter table public.profiles disable trigger guard_profile_privileges',
    '-c', `update public.profiles set role = 'owner' where id = '${target}'`,
    '-c', `select 'manager promoted staff to ' || role from public.profiles where id = '${target}'`,
    '-c', 'rollback'], { encoding: 'utf8' }).trim();
  ok('without the guard a Manager CAN promote a Staff member to Owner — the hole this closes',
     /manager promoted staff to owner/.test(withoutGuard), withoutGuard.split('\n').pop());
  ok('and the rollback left the role alone',
     sql(`select role from public.profiles where id = '${target}';`) === 'staff');

  const promote = failsAs(MANAGER,
    `update public.profiles set role = 'owner' where id = '${target}';`);
  ok('a Manager cannot promote a Staff member to Owner through a direct profile update',
     promote !== null && /Manager may only assign/.test(promote),
     (promote ?? 'THE UPDATE SUCCEEDED').split('\n')[0]);
  ok('and the role is unchanged',
     sql(`select role from public.profiles where id = '${target}';`) === 'staff');

  const selfPromote = failsAs(MANAGER,
    `update public.profiles set role = 'owner' where id = '${MANAGER}';`);
  ok('a Manager cannot promote themselves',
     selfPromote !== null && /your own role/i.test(selfPromote),
     (selfPromote ?? 'THE UPDATE SUCCEEDED').split('\n')[0]);

  const staffSelf = failsAs(STAFF,
    `update public.profiles set role = 'owner' where id = '${STAFF}';`);
  ok('a Staff member cannot promote themselves — the "id = auth.uid()" policy branch is closed',
     staffSelf !== null, (staffSelf ?? 'THE UPDATE SUCCEEDED').split('\n')[0]);

  const demoteOwner = failsAs(MANAGER,
    `update public.profiles set role = 'staff' where id = '${OWNER}';`);
  ok('a Manager cannot demote an Owner either', demoteOwner !== null,
     (demoteOwner ?? 'THE UPDATE SUCCEEDED').split('\n')[0]);

  const deactivateOwner = failsAs(MANAGER,
    `update public.profiles set is_active = false where id = '${OWNER}';`);
  ok('nor deactivate one', deactivateOwner !== null,
     (deactivateOwner ?? 'THE UPDATE SUCCEEDED').split('\n')[0]);

  const allowedMove = failsAs(MANAGER,
    `update public.profiles set role = 'inventory_manager' where id = '${target}';`);
  ok('but a Manager can still move Staff to Inventory Manager, which they are allowed to do',
     allowedMove === null, allowedMove ?? '');

  const ownerPromote = failsAs(OWNER, `update public.profiles set role = 'admin' where id = '${target}';`);
  ok('an Owner can set any role', ownerPromote === null, ownerPromote ?? '');

  // Renaming somebody this Manager may manage. Deliberately not the Owner: a
  // test that quietly renames a person another assertion reads is a test that
  // breaks its neighbours.
  const rename = failsAs(MANAGER,
    `update public.profiles set full_name = 'Renamed Target', work_phone = '+6590000000'
      where id = '${target}';`);
  ok('and an ordinary edit — a name, a phone — is not affected by the guard',
     rename === null, rename ?? '');
  ok('the edit actually went through',
     sql(`select full_name from public.profiles where id = '${target}';`) === 'Renamed Target');
}

// =============================================================================
// The contact rules the edit form already applies
// =============================================================================
{
  const missing = invite(OWNER, 'contact-1', 'nocontact@energia.test', 'No Contact', 'staff', [STORE_A],
                         { work: null, personal: null, pemail: null });
  ok('a Staff invitation without contact details is refused, as the edit form refuses it',
     missing.outcome === 'invalid' && missing.field === 'work_phone',
     `${missing.outcome}/${missing.field ?? ''}`);

  const admin = invite(OWNER, 'contact-2', 'adminnc@energia.test', 'Admin No Contact', 'admin', [STORE_A],
                       { work: null, personal: null, pemail: null });
  ok('and an Admin invitation without them is accepted, because the form does not require them either',
     admin.outcome === 'created', `${admin.outcome}/${admin.field ?? ''}`);

  const noName = invite(OWNER, 'contact-3', 'noname@energia.test', '   ', 'staff', [STORE_A]);
  ok('a blank name is refused', noName.outcome === 'invalid' && noName.field === 'full_name');

  const badEmail = invite(OWNER, 'contact-4', 'not-an-email', 'Bad Email', 'staff', [STORE_A]);
  ok('an invalid login email is refused', badEmail.outcome === 'invalid' && badEmail.field === 'email');
}

// =============================================================================
// Addresses already in use
// =============================================================================
{
  const dup = invite(OWNER, 'dup-1', 'STAFF@energia.test', 'Duplicate', 'staff');
  ok('an address already belonging to a user is refused, case-insensitively',
     dup.outcome === 'email_in_use' && dup.scope === 'staff', `${dup.outcome}/${dup.scope}`);
  ok('and nothing about that account changed',
     sql(`select role || '|' || is_active from public.profiles where id = '${STAFF}';`) === 'staff|true');

  sql(`insert into public.affiliate_accounts (email, full_name) values ('aff@energia.test','An Affiliate');`);
  const aff = invite(OWNER, 'dup-2', 'aff@energia.test', 'Affiliate Person', 'staff');
  ok('an address belonging to an affiliate is refused, and says why',
     aff.outcome === 'email_in_use' && aff.scope === 'affiliate', `${aff.outcome}/${aff.scope}`);
  ok('and no profile was created for it',
     sql(`select count(*) from public.profiles where lower(email) = 'aff@energia.test';`) === '0');
}

// =============================================================================
// Idempotence and duplicates
// =============================================================================
{
  const first  = invite(OWNER, 'idem-1', 'idem@energia.test', 'Idem Person', 'staff');
  const second = invite(OWNER, 'idem-1', 'idem@energia.test', 'Idem Person', 'staff');
  ok('the same request id returns the same invitation instead of creating a second',
     first.outcome === 'created' && second.outcome === 'existing_request'
       && second.invitation_id === first.invitation_id,
     `${first.outcome} then ${second.outcome}`);
  ok('and there is exactly one row for that address',
     sql(`select count(*) from public.user_invitations where email_normalized = 'idem@energia.test';`) === '1');

  const again = invite(OWNER, 'idem-2', 'idem@energia.test', 'Idem Person', 'staff');
  ok('a different request id for a pending address is directed to the existing invitation',
     again.outcome === 'existing_pending' && again.invitation_id === first.invitation_id,
     again.outcome);
}

// =============================================================================
// Pending access, acceptance, cancellation
// =============================================================================
{
  const created = invite(OWNER, 'life-1', 'life@energia.test', 'Life Cycle', 'staff', [STORE_A]);
  const invId = created.invitation_id;
  const authId = sql(`select gen_random_uuid();`);

  sql(`select public.invite_user_provisioned('${invId}','${authId}');`);
  ok('provisioning creates the profile inactive and pending — it grants nothing',
     sql(`select is_active::text || '|' || invitation_status from public.profiles where id = '${authId}';`) === 'false|pending');
  ok('with the role and stores the administrator chose, ready but inert',
     sql(`select role from public.profiles where id = '${authId}';`) === 'staff'
       && sql(`select count(*) from public.user_store_assignments where user_id = '${authId}';`) === '1');
  ok('and the pending user is not a user administrator',
     asUser(authId, `select coalesce(public.user_admin_role()::text, 'none');`) === 'none');

  const wrong = jsonAs(null, `select public.invite_user_accept('${authId}','someone.else@energia.test');`);
  ok('accepting with a different address is refused',
     wrong.activated === false && wrong.reason === 'wrong_account', wrong.reason);

  const accepted = jsonAs(null, `select public.invite_user_accept('${authId}','life@energia.test');`);
  ok('accepting activates the account with the intended role',
     accepted.activated === true && accepted.role === 'staff', JSON.stringify(accepted));
  ok('and the profile is now active and accepted',
     sql(`select is_active::text || '|' || invitation_status from public.profiles where id = '${authId}';`) === 'true|accepted');

  const twice = jsonAs(null, `select public.invite_user_accept('${authId}','life@energia.test');`);
  ok('a second acceptance is refused rather than re-running',
     twice.activated === false && twice.reason === 'already_accepted', twice.reason);

  const resendAccepted = jsonAs(OWNER, `select public.invite_user_prepare_resend('${invId}');`);
  ok('an accepted invitation cannot be resent as a back-door password reset',
     resendAccepted.outcome === 'not_pending' && /Forgot Password/.test(resendAccepted.message),
     resendAccepted.outcome);
}

{
  const created = invite(OWNER, 'cancel-1', 'cancel@energia.test', 'To Cancel', 'staff', [STORE_A]);
  const invId = created.invitation_id;
  const authId = sql(`select gen_random_uuid();`);
  sql(`select public.invite_user_provisioned('${invId}','${authId}');`);

  const cancelled = jsonAs(OWNER, `select public.invite_user_cancel('${invId}','Hired someone else');`);
  ok('an invitation can be cancelled', cancelled.outcome === 'cancelled', cancelled.outcome);
  ok('and the profile is left inactive and marked cancelled',
     sql(`select is_active::text || '|' || invitation_status from public.profiles where id = '${authId}';`) === 'false|cancelled');

  // The link that was emailed still works as far as Supabase is concerned —
  // provider tokens cannot be revoked one by one — so the refusal has to happen here.
  const afterCancel = jsonAs(null, `select public.invite_user_accept('${authId}','cancel@energia.test');`);
  ok('a session obtained from the old link still cannot gain access',
     afterCancel.activated === false && afterCancel.reason === 'cancelled', afterCancel.reason);
  ok('and the account is still inactive afterwards',
     sql(`select is_active from public.profiles where id = '${authId}';`) === 'f');

  const recancel = jsonAs(OWNER, `select public.invite_user_cancel('${invId}','again');`);
  ok('cancelling twice is reported, not repeated', recancel.outcome === 'already_cancelled');

  ok('the cancellation is on the record with who and when',
     sql(`select count(*) from public.audit_logs
           where action = 'user_invitation_cancelled' and record_id = '${invId}'
             and changed_by = '${OWNER}';`) === '1');
}

{
  const created = invite(OWNER, 'perm-1', 'permcheck@energia.test', 'Perm Check', 'manager', [STORE_A]);
  const asManager = jsonAs(MANAGER, `select public.invite_user_prepare_resend('${created.invitation_id}');`);
  ok('a Manager cannot resend an invitation for a role they may not create',
     asManager.outcome === 'forbidden', asManager.outcome);
  const cancelAsManager = jsonAs(MANAGER, `select public.invite_user_cancel('${created.invitation_id}','no');`);
  ok('nor cancel one', cancelAsManager.outcome === 'forbidden', cancelAsManager.outcome);
}

// =============================================================================
// Resend rate limiting
// =============================================================================
{
  const created = invite(OWNER, 'rate-1', 'rate@energia.test', 'Rate Limited', 'staff', [STORE_A]);
  const invId = created.invitation_id;
  const first = jsonAs(OWNER, `select public.invite_user_prepare_resend('${invId}');`);
  ok('the first resend is allowed', first.outcome === 'ok', first.outcome);

  sql(`select public.invite_user_record_delivery('${invId}','accepted_by_provider','webhook 200', true);`);
  const second = jsonAs(OWNER, `select public.invite_user_prepare_resend('${invId}');`);
  ok('an immediate second resend is rate limited, with a retry time',
     second.outcome === 'rate_limited' && second.retry_after_seconds > 0,
     `${second.outcome} ${second.retry_after_seconds ?? ''}`);

  sql(`update public.user_invitations set last_resend_at = now() - interval '5 minutes',
         resend_count = 10 where id = '${invId}';`);
  const capped = jsonAs(OWNER, `select public.invite_user_prepare_resend('${invId}');`);
  ok('and there is a ceiling on how many times one invitation can be resent',
     capped.outcome === 'rate_limited', capped.outcome);
}

// =============================================================================
// What the page reads
// =============================================================================
{
  // A pending profile has to exist at this point or the list test proves
  // nothing about the pending state.
  const created = invite(OWNER, 'list-pending', 'listpending@energia.test', 'Still Pending', 'staff', [STORE_A]);
  const authId = sql(`select gen_random_uuid();`);
  sql(`select public.invite_user_provisioned('${created.invitation_id}','${authId}');`);
  sql(`select public.invite_user_record_delivery('${created.invitation_id}','accepted_by_provider','webhook 200', false);`);
}

{
  const rows = JSON.parse(asUser(OWNER,
    `select coalesce(jsonb_agg(to_jsonb(u)), '[]') from public.user_admin_list() u
      where u.email like '%@energia.test';`));
  const states = [...new Set(rows.map(r => r.state))].sort();
  ok('the list reports invitation state separately from active/inactive',
     states.includes('pending_invitation') && states.includes('cancelled_invitation')
       && states.includes('active'), states.join(','));

  const pending = rows.find(r => r.state === 'pending_invitation');
  ok('a pending row carries who invited them and when',
     pending && pending.invited_by_name === 'Olivia Owner' && !!pending.invited_at,
     pending ? `${pending.invited_by_name} at ${pending.invited_at}` : 'no pending row');

  ok('the delivery status is reported as the provider reported it, not as "delivered"',
     rows.some(r => r.last_email_status === 'accepted_by_provider' || r.last_email_status === 'not_attempted'));

  const leaked = JSON.stringify(rows).toLowerCase();
  ok('and no link, token or secret is anywhere in it',
     !/action_link|access_token|refresh_token|service_role|password/.test(leaked));

  const staffRows = asUser(STAFF, `select count(*) from public.user_admin_list();`);
  ok('a Staff member reads nothing from the list', staffRows === '0', `${staffRows} rows`);

  const mgrRows = JSON.parse(asUser(MANAGER,
    `select coalesce(jsonb_agg(to_jsonb(u)), '[]') from public.user_admin_list() u
      where u.email like '%@energia.test';`));
  ok('a Manager sees Owners in the list but cannot act on them',
     mgrRows.some(r => r.role === 'owner' && r.can_manage === false)
       && mgrRows.some(r => r.role === 'staff' && r.can_manage === true));
}

console.log(`\n${pass} checks passed.`);
