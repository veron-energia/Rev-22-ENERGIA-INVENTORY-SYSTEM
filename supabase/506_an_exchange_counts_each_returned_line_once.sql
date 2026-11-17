-- 506_an_exchange_counts_each_returned_line_once.sql
--
-- AN EXCHANGE COUNTS EACH RETURNED LINE ONCE
--
--   From the security audit of 17 Nov 2026 (finding H5).
--   The BEFORE md5s below were compared with production on 17 Nov 2026 (head 502) and match.
--   If production's text differs when this is applied, it refuses and changes nothing.
--   (The number 506 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   create_exchange_with_details still accepts the kind 'product' (the Exchanges page sends
--   'items' and 'bundle' only) and passes it to create_product_exchange. That function tests
--   "already exchanged" on each returned line by reading exchanged_at, and adds the line's
--   value to the credit, in one loop; it only sets exchanged_at in a later loop. So the same
--   purchased line listed three times passed the test three times: three times its value
--   toward the new goods with no top-up, and three times its stock put back. Any active
--   member of staff could send it. The guard against a repeated line was added to the newer
--   create_items_exchange only (455).
--
-- WHAT THIS DOES
--
--   create_product_exchange refuses a returned list that names the same purchased line more
--   than once, before the first loop: "The same purchased item is listed more than once in
--   this exchange." The ids are compared as uuids, so the same id written in capitals or in
--   braces counts as the same line. A missing id is left to the loop's own message.
--
-- WHAT THIS LEAVES ALONE
--
--   * The kinds themselves. 'product' and 'bundle_component' have no page any more; whether
--     to retire them is the Owner's (report, R11).
--   * create_bundle_exchange and create_bundle_component_exchange: each takes one line, not
--     a list.
--   * Past exchanges. To look for one that used a line twice, read-only:
--       select exchange_id, original_invoice_item_id, count(*) from public.product_exchange_items
--        where direction = 'returned' group by 1, 2 having count(*) > 1;
--
-- UNDO
--
--   Run this block with c_before and c_after swapped and c_anchor and c_new swapped; it then
--   refuses unless the function is 506's version. A later migration changing
--   create_product_exchange must pin 506's AFTER md5.
--
-- NO SELF-TEST INSIDE: it needs a paid invoice, which uses up an invoice number. The suite
-- is scripts/exchanges/tests/returned-line-once-506.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function(s) this patches: BEFORE (the rebuilt copy of production) and AFTER md5s
  c_sig constant text[] := array[
    'create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)'];
  c_before constant text[] := array[
    '48679d09a214c9dcf8850be51110d8bc'];
  c_after constant text[] := array[
    '116b779dde65d974c0b4db8a8a658e12'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO swaps them back.
  c_fn constant int[] := array[1];
  c_anchor constant text[] := array[
$a$  -- ---- Returned side: validate items, determine product type, credit ----
  for v_line in select * from jsonb_array_elements(p_returned)$a$];
  c_new constant text[] := array[
$n$  -- ---- Returned side: validate items, determine product type, credit ----
  -- 506: each purchased line once. The "already exchanged" test below reads
  -- exchanged_at, which is only set in the last loop, so a line listed twice
  -- passed it twice and its value was credited twice.
  -- Compared as uuids, so the same id in capitals or braces is the same line.
  if exists (select 1 from jsonb_array_elements(p_returned) e
              where nullif(e->>'invoice_item_id', '') is not null
              group by (e->>'invoice_item_id')::uuid having count(*) > 1) then
    raise exception 'The same purchased item is listed more than once in this exchange.'; end if;
  for v_line in select * from jsonb_array_elements(p_returned)$n$];
  -- Relied on, not changed
  c_relied constant text[] := array[
    'create_exchange_with_details(text,jsonb)'];
  c_relied_md5 constant text[] := array[
    '82cdd84bf325a4ea5a49ea665f2d3404'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '506: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The function(s) it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '506: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '506: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '506: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '506: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '506: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '506: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '506: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
