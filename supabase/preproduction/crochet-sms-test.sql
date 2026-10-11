-- KOKI CONNECT — CROCHET « Send SMS » DU PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay
-- À exécuter APRÈS la poursuite (marqueur « KOKI TEST » requis), puis à choisir dans
-- Authentication → Hooks → Send SMS → Postgres → schéma koki_test, fonction send_sms.
-- Effet : AUCUN SMS n'est jamais envoyé, aucun fournisseur payant n'est utilisé.
--  * numéros de test +999000000001 à +999000000009 : le code est enregistré dans koki_test.sms_codes (lecture : administrateur du projet) ;
--  * tout autre numéro : refus explicite (aucun envoi, aucun coût), donc aucun vrai numéro ne peut s'inscrire sur TEST.
-- Retrait : supabase/preproduction/crochet-sms-test-retrait.sql (puis désactiver le crochet dans le tableau de bord).
begin;
do $$ begin
 if to_regclass('koki_private.test_environment') is null then raise exception 'GARDE : base non marquée « KOKI TEST » : crochet refusé';end if;
 if not exists(select 1 from koki_private.test_environment where label='KOKI TEST') then raise exception 'GARDE : base non marquée « KOKI TEST » : crochet refusé';end if;
 if to_regnamespace('koki_test') is not null then raise exception 'GARDE : crochet déjà installé';end if;
end $$;
create schema koki_test;
revoke all on schema koki_test from public, anon, authenticated;
create table koki_test.sms_codes(
 id bigint generated always as identity primary key,
 phone text not null check(phone ~ '^99900000000[1-9]$'),
 code text not null check(code ~ '^[0-9]{6,10}$'),
 created_at timestamptz not null default now()
);
alter table koki_test.sms_codes enable row level security;
revoke all on koki_test.sms_codes from public, anon, authenticated;
create function koki_test.send_sms(event jsonb) returns jsonb language plpgsql set search_path='' as $$
declare phone text:=regexp_replace(coalesce(event->'user'->>'phone',''),'^\+','');code text:=coalesce(event->'sms'->>'otp','');
begin
 if phone !~ '^99900000000[1-9]$' then
  return jsonb_build_object('error',jsonb_build_object('http_code',400,'message','Préproduction : seuls les numéros de test +999000000001 à +999000000009 sont acceptés'));end if;
 if code !~ '^[0-9]{6,10}$' then return jsonb_build_object('error',jsonb_build_object('http_code',400,'message','Code de test invalide'));end if;
 insert into koki_test.sms_codes(phone,code) values(phone,code);
 return '{}'::jsonb;
end $$;
revoke all on function koki_test.send_sms(jsonb) from public, anon, authenticated;
-- Droits minimaux du service Auth (rôle supabase_auth_admin), comme le recommande la documentation des crochets.
grant usage on schema koki_test to supabase_auth_admin;
grant insert on koki_test.sms_codes to supabase_auth_admin;
create policy sms_codes_auth_insert on koki_test.sms_codes for insert to supabase_auth_admin with check (phone ~ '^99900000000[1-9]$');
grant execute on function koki_test.send_sms(jsonb) to supabase_auth_admin;
commit;
