-- For the 480, 482 and 484 suites on a database where 492 is in (included by each right after its begin).
--
-- 492 (3 Nov 2026) shows every Tier 1 number on My Network. Those suites check the versions before it (480's
-- bookings, 482's visits, 484's numbers for referrals told at sign-up), so for their run, which is rolled back, My
-- Network is put back to 484's text (md5 070d1b48...), as 492's UNDO does. 492's own suite
-- (affiliate-network-phone-492.sql, N5) checks that every key but 'phone', every value and the order are what 484's
-- text answers. Anywhere else (492 not in) this changes nothing.
do $as484$
declare v_path text := current_setting('search_path');
begin
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) = '5506f7291146534551a25e52a1e7820b' then
    execute $n484$CREATE OR REPLACE FUNCTION public.affiliate_portal_network()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_t1 jsonb; v_t2 jsonb;
  -- 480 (the Owner, 29 Oct 2026): each one's cal.com booking, its moment and
  -- state only (calcom_customer_bookings, as the staff Downline reads it).
  v_book jsonb;
  -- 484 (the Owner, 31 Oct 2026, answers 1 and 2): whether this login is
  -- shown any Tier 1 number at all: the affiliate is active (not suspended,
  -- not removed) and the login's link to its record is proven
  -- (affiliate_login_link_proof, read for the login itself: auth.uid()).
  v_phones boolean;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  v_phones := public.affiliate_is_active(v_me) and public.affiliate_login_link_proof(auth.uid(), v_me) is not null;

  select coalesce(jsonb_object_agg(b.customer_id, jsonb_build_object('at', b.booking_at, 'state', b.booking_state)), '{}'::jsonb)
    into v_book
    from public.calcom_customer_bookings(array(
           select c.id from public.customers c where c.referred_by = v_me and c.deleted_at is null
           union
           select c.id from public.customers c join public.customers p on p.id = c.referred_by
            where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null)) b;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier1',
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id
                                  and cm.status in ('earned','paid')),
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none'),
           -- 484 (the Owner, 31 Oct and 1 Nov 2026): the stored number, trimmed,
           -- only when v_phones and the referral signed up through the /r/ page
           -- while it said this referrer would see their number (a mark in
           -- referral_phone_notices naming this referrer), the record still holds
           -- the number typed then, and they have not asked to hide it (no
           -- withdrawn mark). Otherwise null (a dash on the page). Tier 2: no
           -- phone key at all.
           'phone', case when v_phones and btrim(c.phone) ~ '[0-9]' and btrim(c.phone) !~* '^(AFF-.{8}|LEGACY-.*)$'
                          and exists (select 1 from public.referral_phone_notices n
                                       where n.customer_id = c.id and n.referrer_customer_id = v_me and n.withdrawn_at is null
                                         and n.phone = public.normalize_customer_phone(c.phone))
                          and not exists (select 1 from public.referral_phone_notices w
                                           where w.customer_id = c.id and w.withdrawn_at is not null)
                         then btrim(c.phone) end
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t1
    from public.customers c where c.referred_by = v_me and c.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
           'customer_name', c.full_name, 'tier', 'tier2',
           'parent_name', p.full_name,
           'referral_date', c.referred_at, 'joined_at', c.created_at,
           'purchases', (select count(*) from public.invoices i where i.customer_id = c.id and i.deleted_at is null and i.status in ('paid','completed_foc','partially_paid')),
           'total_spent', public._aff_settled_spend(c.id),
           'your_commission', (select coalesce(sum(cm.commission_amount),0) from public.commissions cm
                                where cm.referrer_customer_id = v_me and cm.buyer_customer_id = c.id and cm.status in ('earned','paid')),
           'booking_at', v_book -> c.id::text -> 'at', 'booking_state', coalesce(v_book -> c.id::text ->> 'state', 'none')
         ) order by c.created_at desc), '[]'::jsonb)
    into v_t2
    from public.customers c
    join public.customers p on p.id = c.referred_by
   where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null;

  return jsonb_build_object('tier1', v_t1, 'tier2', v_t2);
end $function$
$n484$;
    if md5(pg_get_functiondef('public.affiliate_portal_network()'::regprocedure)) <> '070d1b485d32cec99fa627b816a91b4a' then
      raise exception 'my-network-as-484: My Network is not 484''s after putting it back';
    end if;
    raise notice '492 is in: My Network is 484''s for this run (rolled back at the end)';
  end if;
  perform set_config('search_path', v_path, true);
end $as484$;
