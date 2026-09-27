import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

test('323 repairs undeclared legacy invoice locals and can be rerun', () => {
  const migration = readFileSync(new URL('../../../supabase/323_bundle_vouchers_may_be_deferred.sql', import.meta.url), 'utf8')
    .replace(/^begin;\s*/, '').replace(/commit;\s*$/, '');
  // The local helper allows only disposable database names. All function
  // replacements (including migration 323 itself) roll back after this test.
  const fixture = `
begin;
set local check_function_bodies = off;
-- Reproduce the legacy overload: package statements were stored without
-- declarations, while the modern eight-argument overload already has them.
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid, p_items jsonb,
  p_discount_total numeric, p_notes text, p_discount_voucher_id uuid)
returns uuid language plpgsql as $fixture$
declare
  v_price numeric := 10; v_qty integer := 1;
begin
  v_gross := v_price * v_qty;
  v_sel := p_items;
  -- Models the result from validate_bundle_voucher_selection.
  v_pj := v_sel->0;
  if not (v_pj->>'complete')::boolean then
    raise exception 'Select exactly % reward voucher(s) for "%" — % chosen',
      v_pj->>'required_qty', 'Legacy bundle', v_pj->>'selected_qty';
  end if;
  return p_store_id;
end $fixture$;
set local check_function_bodies = on;
do $test$
begin
  begin
    execute pg_get_functiondef('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)'::regprocedure);
    raise exception 'Expected the legacy compilation error';
  exception when syntax_error then
    if sqlerrm <> '"v_gross" is not a known variable' then raise; end if;
    raise notice 'Reproduced: %', sqlerrm;
  end;
end $test$;
`;
  const checks = `
-- Give the legacy overload a test-only callable name: the modern overload's
-- default eighth parameter otherwise makes a seven-argument call ambiguous.
do $copy$
begin
  execute replace(pg_get_functiondef('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid)'::regprocedure),
    'FUNCTION public.create_invoice(', 'FUNCTION public.test_323_legacy_invoice(');
end $copy$;
do $test$
declare result uuid; qty integer; message text;
begin
  foreach qty in array array[0,4,10] loop
    result := public.test_323_legacy_invoice('00000000-0000-0000-0000-000000000323'::uuid,
      null::uuid,null::uuid,
      jsonb_build_array(jsonb_build_object('complete',qty=10,'required_qty',10,'selected_qty',qty)),
      0::numeric,null::text,null::uuid);
    if result is distinct from '00000000-0000-0000-0000-000000000323'::uuid then
      raise exception 'Legacy overload rejected quantity %', qty;
    end if;
  end loop;
  begin
    perform public.test_323_legacy_invoice(null::uuid,null::uuid,null::uuid,
      '[{"complete":false,"required_qty":10,"selected_qty":11}]'::jsonb,
      0::numeric,null::text,null::uuid);
    raise exception 'Over-selection was accepted';
  exception when raise_exception then
    message := sqlerrm;
    if message <> 'That is more reward voucher(s) than the allowance of 10 for "Legacy bundle" — 11 chosen' then
      raise exception 'Unexpected over-selection message: %', message;
    end if;
  end;
end $test$;
create temporary table migration_323_definitions on commit drop as
select oid, pg_get_functiondef(oid) as definition from pg_proc
where pronamespace='public'::regnamespace and prokind='f';
`;
  const verification = `
do $test$
begin
  if exists(select 1 from migration_323_definitions d
    where d.definition is distinct from pg_get_functiondef(d.oid)) then
    raise exception 'Rerunning migration 323 changed a function again';
  end if;
  raise notice 'PASS: missing locals repaired, partial selections accepted, excess refused, rerun unchanged';
end $test$;
rollback;
`;
  const result = spawnSync('sh', ['scripts/invoices/local-sql.sh'], {
    cwd: new URL('../../../', import.meta.url),
    env: { ...process.env, ENERGIA_INVOICE_DB: 'energia_integration_test' },
    input: fixture + migration + checks + migration + verification,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  assert.match(result.stderr, /PASS: missing locals repaired/);
});
