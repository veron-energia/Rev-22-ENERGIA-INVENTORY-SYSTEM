-- Read-only. Expected: all six RPC signatures present, auth can execute,
-- anon cannot; zero allocation mismatches in the post-install review report.
select p.oid::regprocedure signature,p.proargnames,pg_get_userbyid(p.proowner) owner,p.prosecdef security_definer,
 has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,has_function_privilege('anon',p.oid,'EXECUTE') anonymous_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
 ('commission_referrer_names','record_affiliate_payout','correct_affiliate_payout','create_commission_payout','affiliate_payout_overview','affiliate_payout_history')
order by p.proname;
select has_table_privilege('authenticated','public.commission_payouts','INSERT,UPDATE,DELETE') direct_payout_write,
 has_table_privilege('authenticated','public.commission_payout_allocations','INSERT,UPDATE,DELETE') direct_allocation_write,
 has_function_privilege('authenticated','public.affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)','EXECUTE') private_writer_execute;
select tgname,tgenabled from pg_trigger where tgrelid='public.commissions'::regclass and tgname='affiliate_commission_serialization';
