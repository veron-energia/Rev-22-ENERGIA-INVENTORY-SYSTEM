-- UNDO of 497 (with the user's go-ahead; the suite runs it). It puts the four patched
-- functions back to their BEFORE texts and drops the function 497 added. It refuses unless
-- each function is exactly 497's version, so a later version is never overwritten. What a
-- correction has already moved stays moved: its sales stay cancelled and its stock stays
-- back. The word 'line corrected' stays allowed on special_sale_returns while any such row
-- exists. Undo 497 before 496. One transaction, all or nothing.
do $undo$
declare
  c_sig constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'preview_invoice_correction(uuid,jsonb)',
    'return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)',
    'restore_released_special_stock(uuid,text,uuid)'];
  c_before constant text[] := array[
    '04d647e13e9424a9375942e5812e91a2',
    'f26752231c100461e11caddc03c98a33',
    '71c22eb51b75650836e09a95b827c0fe',
    '5f1b3d1d0c78a0c49d7fc2171301f5d1'];
  c_after constant text[] := array[
    '9aac5395dd18fd8349727d6c8aa0c633',
    '13b0925c29bd8ca14d8d8b7bd961fef8',
    '13c9f26bd2c3c275dcee559a22caa8e0',
    'b89207a71e25bd62821c5b61c696eeba'];
  c_fn constant int[] := array[1, 1, 1, 1, 2, 3, 3, 4];
  c_anchor constant text[] := array[
$a$ v458_rentals jsonb := '[]'::jsonb;  -- 458: what this correction did to the invoice's rentals$a$,
$a$ v458_rentals := public.invoice_rentals_follow_lines(i.id,v_snapshot->'items',p_reason);$a$,
$a$detail = (select jsonb_build_object('rentals', v458_rentals,  -- 458$a$,
$a$'rentals',v458_rentals)  -- 458: what the correction did to the invoice's rentals, for the page to say$a$,
$a$                    from jsonb_array_elements(v416_dry->'rentals') e)));
    end if;$a$,
$a$-- afresh, as a waiting one cancelled by a refund is (393). p_why is 'refunded' or
-- 'invoice cancelled'. Internal: refund_invoice_recorded, record_invoice_stock_return
-- and restore_released_special_stock call it, in the invoice's own transaction.$a$,
$a$  if p_why is null or p_why not in ('refunded', 'invoice cancelled') then
    raise exception '496: stock comes back for a refund or a cancellation, not "%"', p_why; end if;$a$,
$a$  -- (invoice_action_plan): a unit whose line a correction removed or lowered stays as
  -- it was, never moved without being shown. Returns how many units' sales it settled.
  -- Internal: cancel_invoice_recorded calls it, and not a correction
  -- (restore_invoice_stock is also that), which must never take a released unit back.$a$];
  c_new constant text[] := array[
$n$ v458_rentals jsonb := '[]'::jsonb;  -- 458: what this correction did to the invoice's rentals
 v497_special jsonb := '[]'::jsonb;  -- 497: what this correction did to the invoice's special sales$n$,
$n$ v458_rentals := public.invoice_rentals_follow_lines(i.id,v_snapshot->'items',p_reason);
 -- 497 (the user, 7 Nov 2026): and its special sales follow the corrected lines, here too
 -- so the correction summary says what they become before anyone saves.
 if not same_lines then
   v497_special := public.invoice_special_sales_follow_lines(i.id,v_snapshot->'items',p_reason,p_request_id);
 end if;$n$,
$n$detail = (select jsonb_build_object('rentals', v458_rentals,  -- 458
                        'special', v497_special,  -- 497$n$,
$n$'rentals',v458_rentals,  -- 458: what the correction did to the invoice's rentals, for the page to say
     'special',v497_special)  -- 497: and to its special sales$n$,
$n$                    from jsonb_array_elements(v416_dry->'rentals') e)));
    end if;
    -- 497 (the user, 7 Nov 2026): the special sales that follow the corrected lines,
    -- as the correction answers them.
    if jsonb_array_length(coalesce(v416_dry->'special', '[]'::jsonb)) > 0 then
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(
        'area', 'special_sales', 'change', 'changed',
        'detail', 'Saving does what is listed here.' || case when exists (select 1 from jsonb_array_elements(v416_dry->'special') e where e->>'state' = 'back')
                    then ' A machine going back is added to that stock without anyone being asked, so make sure it really came back; if it did not, correct the count with a stock adjustment.' else '' end,
        'items', (select jsonb_agg(jsonb_build_object('kind', 'special_sale', 'what', e.value->>'what') order by e.ordinality)
                    from jsonb_array_elements(v416_dry->'special') with ordinality e)));
    end if;$n$,
$n$-- afresh, as a waiting one cancelled by a refund is (393). p_why is 'refunded',
-- 'invoice cancelled' or (497) 'line corrected'. Internal: refund_invoice_recorded,
-- record_invoice_stock_return, restore_released_special_stock and
-- invoice_special_sales_follow_lines call it, in the invoice's own transaction.$n$,
$n$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected') then  -- 497
    raise exception '496: stock comes back for a refund, a cancellation or a corrected line, not "%"', p_why; end if;$n$,
$n$  -- (invoice_action_plan). A correction settles the units it takes off a line itself
  -- (497, invoice_special_sales_follow_lines), so its summary shows them first; a unit
  -- above its line's quantity from before that stays as it was, never moved without
  -- being shown. Returns how many units' sales it settled.
  -- Internal: cancel_invoice_recorded calls it; a correction does not.$n$];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[4]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. cardinality(c_sig) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception 'UNDO 497: public.% is not 497''s version (md5 %); nothing changed', c_sig[i], md5(d); end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 497: patch % is not found exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'UNDO 497: the text worked back for public.% is not the BEFORE one (md5 %)', c_sig[i], md5(v_def[i]); end if;
    execute v_def[i];
  end loop;
  drop function public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid);
  if not exists (select 1 from public.special_sale_returns where why = 'line corrected') then
    alter table public.special_sale_returns drop constraint special_sale_returns_why_check;
    alter table public.special_sale_returns add constraint special_sale_returns_why_check
      check (why = any (array['refunded'::text, 'invoice cancelled'::text]));
  end if;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
