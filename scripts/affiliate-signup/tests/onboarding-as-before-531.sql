-- For suites that run the sign-up as it was before 531 (included right after their begin, or by
-- scripts/affiliate-claims/tests/sign-up-before-437.sql). Where 531 is in, complete_affiliate_onboarding is
-- put back to 508's text (0dd12d4c...) for the run, which is rolled back: 531's one replacement there
-- (a new account verified only from the server's date on the login, never from a link or from
-- Supabase's confirmation), reversed. Those suites test the older migrations and the sign-up's other
-- rules, and re-run files that pin 508's text; what 531 changes in the sign-up is checked by
-- scripts/affiliate-signup/tests/signup-limits-and-email-codes-531.sql (O). Anywhere else this changes
-- nothing. (From the security audit of 17 Nov 2026, finding M6.)
do $onb531$
declare v_path text := current_setting('search_path'); d text;
begin
  perform set_config('search_path', 'public', true);
  d := pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure);
  if md5(d) = '15f677725266f658f552051ae61e6d71' then  -- 531's AFTER
    if (length(d) - length(replace(d, $n531$  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "Code on the Account
  -- page"): a new account's "email verified" comes only from the date the server keeps on the
  -- login (app_metadata affiliate_email_verified_at, which the server alone writes: when the
  -- login verified with a code, or kept from an account an Owner unlinked, 378). Neither
  -- Supabase Auth's own confirmation (email_confirmed_at) nor a session opened from an emailed
  -- link (a reset link, a magic link) verifies it any more; 437 (2) took both. A login the
  -- sign-up made with someone's email and left without an account would otherwise become
  -- verified when that person opened a reset link. Every other new account starts unverified
  -- and verifies with the code from the verify email (confirm_affiliate_email_code).
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
  end;
$n531$, ''))) / length($n531$  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "Code on the Account
  -- page"): a new account's "email verified" comes only from the date the server keeps on the
  -- login (app_metadata affiliate_email_verified_at, which the server alone writes: when the
  -- login verified with a code, or kept from an account an Owner unlinked, 378). Neither
  -- Supabase Auth's own confirmation (email_confirmed_at) nor a session opened from an emailed
  -- link (a reset link, a magic link) verifies it any more; 437 (2) took both. A login the
  -- sign-up made with someone's email and left without an account would otherwise become
  -- verified when that person opened a reset link. Every other new account starts unverified
  -- and verifies with the code from the verify email (confirm_affiliate_email_code).
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
  end;
$n531$) <> 1 then
      raise exception 'onboarding-as-before-531: 531''s text is not found once in the sign-up';
    end if;
    execute replace(d, $n531$  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "Code on the Account
  -- page"): a new account's "email verified" comes only from the date the server keeps on the
  -- login (app_metadata affiliate_email_verified_at, which the server alone writes: when the
  -- login verified with a code, or kept from an account an Owner unlinked, 378). Neither
  -- Supabase Auth's own confirmation (email_confirmed_at) nor a session opened from an emailed
  -- link (a reset link, a magic link) verifies it any more; 437 (2) took both. A login the
  -- sign-up made with someone's email and left without an account would otherwise become
  -- verified when that person opened a reset link. Every other new account starts unverified
  -- and verifies with the code from the verify email (confirm_affiliate_email_code).
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
  end;
$n531$, $a531$
  -- 437 (2): the app's own "email verified". Yes, from that day, when the
  -- login says it was verified before (app_metadata
  -- affiliate_email_verified_at: an account an Owner unlinked, 378); yes
  -- when Supabase Auth confirmed the login through its email link (every
  -- login before 437); no when the sign-up function or the 437 repair
  -- confirmed it (app_metadata.affiliate_email_unverified; the server alone
  -- sets either); yes now when this session was opened from an emailed link,
  -- which the login then keeps too.
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
    when coalesce(v_app->>'affiliate_email_unverified', '') = 'true' then null
    else v_confirmed end;
  if v_verified is null and public.affiliate_session_from_email_link() then
    v_verified := now();
    update auth.users
       set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                               || jsonb_build_object('affiliate_email_verified_at', v_verified)
     where id = v_uid;
  end if;
$a531$);
    if md5(pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure)) <> '0dd12d4c9cef8b86bb1bcc02a5344927' then
      raise exception 'onboarding-as-before-531: the sign-up is not 508''s after putting it back';
    end if;
    raise notice '531 is in: the sign-up is 508''s for this run (rolled back at the end)';
  end if;
  perform set_config('search_path', v_path, true);
end $onb531$;
