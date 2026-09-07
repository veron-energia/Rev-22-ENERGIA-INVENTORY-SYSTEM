// Minimal integration schema composed from the repository's real table/function
// definitions. No application RPC under test is mocked. Auth plumbing is local.
import { readFileSync, writeFileSync } from 'node:fs';
const read = n => readFileSync(`supabase/${n}.sql`, 'utf8');
const table = (source, name) => {
  const found=source.match(new RegExp(`create table (?:if not exists )?public\\.${name} \\([\\s\\S]*?\\n\\);`));
  if(!found) throw new Error(name); return found[0];
};
const fn = (source,name) => {
  const start=source.indexOf('create or replace function public.'+name+'(');
  if(start<0) throw new Error(name);
  const body=source.slice(start); const delimiter=body.match(/\bas (\$[a-zA-Z_]*\$)/i)[1];
  const end=body.indexOf(delimiter+';',body.indexOf(delimiter)+delimiter.length);
  return body.slice(0,end+delimiter.length+1);
};
const base=read('01_schema'), survey=read('39_specphase5a_health_survey'), portal=read('155_affiliate_self_service_portal');
const statements=[`create schema auth;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
create type user_role as enum ('owner','manager','admin','staff','inventory_manager');
create type customer_gender as enum ('male','female','other');
create type customer_affiliate_status as enum ('active','inactive');
`];
statements.push(base.match(/create type invoice_status as enum \([\s\S]*?\);/)[0]);
for(const name of ['profiles','customers','stores','affiliates','invoices','audit_logs']) statements.push(table(base,name));
statements.push(`alter table public.customers add column first_name text,add column last_name text,add column date_of_birth date,
  add column gender customer_gender,add column gender_other text,add column occupation text,add column updated_at timestamptz default now(),
  add column referred_by uuid references public.customers(id),add column referred_at timestamptz,add column referral_source text,add column referral_code_used text;
alter table public.audit_logs add column actor_role text,add column module text,add column store_id uuid,add column ip_address text,add column device_info text,add column reason text;
`);
statements.push(table(read('32_specphase2b_phone_history'),'customer_phone_history'));
statements.push(table(read('63_phase14_survey_customer_source'),'customer_source_options'));
for(const name of ['survey_links','health_symptom_options','health_surveys','health_survey_symptoms']) statements.push(table(survey,name));
statements.push(table(read('40_specphase5b_survey_review_pdf'),'health_survey_pdfs'));
for(const name of ['customers','health_surveys']) statements.push(`alter table public.${name} add column source_option_id uuid references public.customer_source_options(id),add column source_label text,add column source_details text;`);
statements.push('alter table public.customers add column source_updated_at timestamptz; alter table public.health_surveys add column first_name text,add column last_name text;');
let aff=table(read('51_membership_affiliates'),'customer_affiliates');
statements.push(aff);
statements.push('alter table public.customer_affiliates add column referral_code text unique;');
for(const name of ['affiliate_accounts','affiliate_account_claims','referral_signup_events']) statements.push(table(portal,name));
statements.push(`create unique index on public.affiliate_account_claims(auth_user_id) where status='pending';`);
statements.push(fn(read('31_specphase1_foundation'),'sg_today'));
statements.push(fn(read('02_rls_policies'),'current_user_role'));
statements.push(fn(read('02_rls_policies'),'is_owner_or_manager'));
statements.push(fn(read('31_specphase1_foundation'),'write_audit_ex'));
statements.push(fn(portal,'generate_affiliate_referral_code'));
statements.push(fn(read('92_names_whatsapp_policy'),'split_person_name'));
statements.push(fn(read('92_names_whatsapp_policy'),'join_person_name'));
statements.push(fn(read('147_stop_resplitting_names'),'trg_sync_person_name'));
statements.push(fn(read('146_ensure_name_sync_both_ways'),'trg_sync_customer_to_surveys'));
statements.push(`create trigger sync_customer_name before insert or update on public.customers for each row execute function public.trg_sync_person_name();
create trigger sync_survey_name before insert or update on public.health_surveys for each row execute function public.trg_sync_person_name();
create trigger sync_customer_to_surveys after insert or update on public.customers for each row execute function public.trg_sync_customer_to_surveys();`);
for(const name of ['normalize_customer_phone','customer_phone_collisions','submit_health_survey','affiliate_referral_signup']) statements.push(fn(read('157_health_survey_existing_customer_phone_match'),name));
statements.push(fn(read('158_fix_customer_affiliate_health_survey_errors'),'complete_affiliate_onboarding'));
statements.push(fn(read('32_specphase2b_phone_history'),'change_customer_phone'));
statements.push(fn(read('139_delete_customer_rpc'),'restore_customer'));
statements.push(fn(portal,'affiliate_pending_claims'));
// Reproduce the state before the phone-policy migration, including bad legacy
// formats and an overfull normalized group that must not abort deployment.
statements.push(fn(read('157_health_survey_existing_customer_phone_match'),'normalize_customer_phone'));
statements.push(`insert into public.customers(full_name,phone,is_active) values
('Legacy One','91230001',true),('Legacy Two','6591230001',true),
('Legacy Three','+65 9123 0001',false),('Legacy Four','+6591230001',true),
('Legacy Ambiguous','93234567',true),('Legacy Invalid','not-a-number',true);
insert into auth.users values('00000000-0000-4000-8000-000000000001','owner@test.invalid',now());
insert into public.profiles(id,full_name,email,role) values('00000000-0000-4000-8000-000000000001','Test Owner','owner@test.invalid','owner');
`);
writeFileSync(process.argv[2],statements.join('\n'));
