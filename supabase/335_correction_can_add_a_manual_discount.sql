  begin;
  -- =====================================================================
  -- A CORRECTION THAT ADDS A MANUAL DISCOUNT COULD NOT GIVE ITS REASON
  --
  -- 331 keeps the reason on the invoice row and lets a trigger refuse a positive
  -- manual discount that arrives without one. correct_invoice writes the reason
  -- in its first update, before the amount changes. On an invoice that had no
  -- discount, the trigger's "no discount, no reason to keep" branch clears it
  -- right there; the second update, the one inside update_invoice_internal that
  -- actually changes the amount, then finds no reason and refuses. Raising an
  -- existing discount worked, which is what 331's test covered. Adding one to an
  -- invoice that had none did not.
  --
  -- The fix follows 331's own convention for inserts: correct_invoice hands the
  -- reason over for the transaction, and the trigger's update branch accepts
  -- that hand-off exactly as its insert branch already does. The hand-off is
  -- cleared again straight after, so nothing later in the same transaction can
  -- inherit it.
  -- =====================================================================

  -- ---------------------------------------------------------------------
  -- 1. The trigger: on update, a missing reason may come from the hand-off.
  -- ---------------------------------------------------------------------
  create or replace function public.trg_invoice_manual_discount_reason()
  returns trigger language plpgsql as $$
  begin
    -- Whitespace is not a reason.
    new.manual_discount_reason := nullif(btrim(coalesce(new.manual_discount_reason, '')), '');

    if tg_op = 'INSERT' then
      -- create_invoice does not know the column; create_invoice_with_details
      -- hands the reason over for the same transaction. A caller that reaches
      -- the insert any other way has no reason to offer, and is refused.
      if new.manual_discount_reason is null then
        new.manual_discount_reason := nullif(btrim(coalesce(current_setting('invoice.manual_discount_reason', true), '')), '');
      end if;
      if coalesce(new.manual_discount, 0) > 0 and new.manual_discount_reason is null then
        raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.';
      end if;
      return new;
    end if;

    -- A correction that changes the amount to something positive needs a reason.
    -- One that leaves the amount alone does not, so history is never asked for.
    -- The reason may already be on the row, or be handed over by the correction
    -- that is changing the amount (335).
    if coalesce(new.manual_discount, 0) > 0
      and new.manual_discount is distinct from old.manual_discount
      and new.manual_discount_reason is null then
      new.manual_discount_reason := nullif(btrim(coalesce(current_setting('invoice.manual_discount_reason', true), '')), '');
      if new.manual_discount_reason is null then
        raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.';
      end if;
    end if;
    -- No discount, no reason to keep on the row. The audit has the old pair.
    if coalesce(new.manual_discount, 0) <= 0 then new.manual_discount_reason := null; end if;
    return new;
  end $$;

  -- ---------------------------------------------------------------------
  -- 2. correct_invoice: hand the reason over around the update that changes
  --    the amount. Anchored on the installed body; refuses to guess.
  -- ---------------------------------------------------------------------
  do $$
  declare f text; anchor text; v_old text; v_new text;
  begin
    select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
    if position('invoice.manual_discount_reason' in f) > 0 then return; end if;  -- already done
    anchor := '  perform public.update_invoice_internal(i.id,n.customer_id,n.affiliate_id,p_items,n.manual_discount,';
    if position(anchor in f) = 0 then
      raise exception '335: correct_invoice does not contain the expected update_invoice_internal call';
    end if;
    -- The call spans lines; wrap from its first line to the end of the statement.
    v_old := substr(f, position(anchor in f));
    v_old := substr(v_old, 1, position(');' in v_old) + 1);
    v_new := '  perform set_config(''invoice.manual_discount_reason'',coalesce(n.manual_discount_reason,''''),true);' || chr(10)
          || v_old || chr(10)
          || '  perform set_config(''invoice.manual_discount_reason'','''',true);';
    execute replace(f, v_old, v_new);
  end $$;

  do $$
  declare f text;
  begin
    select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
    if position('set_config(''invoice.manual_discount_reason'',coalesce(n.manual_discount_reason' in f) = 0 then
      raise exception '335: the hand-off did not land in correct_invoice';
    end if;
  end $$;

  notify pgrst, 'reload schema';
  commit;
