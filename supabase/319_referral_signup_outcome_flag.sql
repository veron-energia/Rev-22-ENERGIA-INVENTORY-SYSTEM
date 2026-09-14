begin;
-- =====================================================================
-- A REFERRAL REGISTRATION SAYS WHICH OUTCOME IT WAS
--
-- affiliate_referral_signup answers an existing customer with ok=true and a
-- message explaining that they are already registered. The page had nothing but
-- that message to go on, so it rendered the reply under "Registration
-- Successful" -- telling somebody who already existed, and for whom nothing was
-- created, that they had just registered. On a page reached from an affiliate's
-- link, that reads as "you are now signed up", which is not true in either
-- sense: no customer was created and no affiliate account exists.
--
-- The outcome is now named in the reply, so the screen can say what actually
-- happened. Referral ownership is still never changed from an anonymous form,
-- and nothing about who is registered changes here.
-- =====================================================================
do $do$
declare f text;
begin
  select pg_get_functiondef('public.affiliate_referral_signup(text,text,text,text,text,text)'::regprocedure) into f;
  if position('''outcome''' in f) = 0 then
    -- the existing-customer reply
    f := replace(f,
      '    return jsonb_build_object(''ok'', true,
      ''message'', ''This customer is already registered with Energia. Please contact us if you need help with your referral registration.'');',
      '    return jsonb_build_object(''ok'', true, ''outcome'', ''already_registered'',
      ''message'', ''This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.'');');
    -- the genuine registration reply
    f := replace(f,
      '    return jsonb_build_object(''ok'', true);',
      '    return jsonb_build_object(''ok'', true, ''outcome'', ''registered'');');
    if position('''outcome''' in f) = 0 then
      raise exception 'affiliate_referral_signup does not match what 319 expects — align it by hand'; end if;
    execute f;
    raise notice 'affiliate_referral_signup now names its outcome';
  end if;
end $do$;

notify pgrst,'reload schema';
commit;
