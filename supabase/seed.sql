-- Données FICTIVES pour le Supabase LOCAL (rejouées par « supabase start » et « supabase db reset »).
-- Tout est préfixé « TEST », numéros fictifs +999, position de test 15.56 / -16.21.
-- Aucun mot de passe, aucun secret : l'administrateur choisit son mot de passe via « mot de passe oublié »
-- (e-mail visible dans Mailpit http://127.0.0.1:54324) ; les autres comptes se connectent par SMS (code 123456).

-- 1. Refus absolu hors d'une base marquée TEST (la migration 20261011000500 pose le marqueur).
do $$ begin
 if to_regclass('koki_private.test_environment') is null then raise exception 'Base non marquée « KOKI TEST » : données fictives refusées.';end if;
 if not exists(select 1 from koki_private.test_environment where label='KOKI TEST') then raise exception 'Base non marquée « KOKI TEST » : données fictives refusées.';end if;
end $$;

-- 2. SMS en mode test : les codes ne sont jamais envoyés, ils sont enregistrés ici (Studio → koki_local.sms_codes).
create schema if not exists koki_local;
revoke all on schema koki_local from public;
create table if not exists koki_local.sms_codes(id bigint generated always as identity primary key,phone text not null,code text not null,created_at timestamptz not null default now());
alter table koki_local.sms_codes enable row level security;
revoke all on koki_local.sms_codes from public;
create or replace function koki_local.send_sms(event jsonb) returns jsonb language plpgsql set search_path='' as $$
begin
 insert into koki_local.sms_codes(phone,code) values(coalesce(event->'user'->>'phone',''),coalesce(event->'sms'->>'otp',''));
 return '{}'::jsonb;
end $$;
revoke all on function koki_local.send_sms(jsonb) from public;
do $$ begin
 if exists(select 1 from pg_roles where rolname='anon') then execute 'revoke all on schema koki_local from anon, authenticated';execute 'revoke all on function koki_local.send_sms(jsonb) from anon, authenticated';end if;
 if exists(select 1 from pg_roles where rolname='supabase_auth_admin') then
  execute 'grant usage on schema koki_local to supabase_auth_admin';
  execute 'grant select, insert on koki_local.sms_codes to supabase_auth_admin';
  execute 'grant usage on all sequences in schema koki_local to supabase_auth_admin';
  execute 'grant execute on function koki_local.send_sms(jsonb) to supabase_auth_admin';
  execute 'create policy sms_codes_auth on koki_local.sms_codes for all to supabase_auth_admin using (true) with check (true)';
 end if;
end $$;

-- 3. Comptes fictifs (Supabase Auth). Mots de passe vides : aucun secret dans ce fichier.
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change) values
 ('00000000-0000-0000-0000-000000000000','11111111-1111-4111-8111-111111111111','authenticated','authenticated','koki-test-admin@example.test',null,now(),null,null,'{"provider":"email","providers":["email"]}','{"nom":"TEST Administrateur"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','22222222-2222-4222-8222-222222222222','authenticated','authenticated',null,null,null,'999000000001',now(),'{"provider":"phone","providers":["phone"]}','{"nom":"TEST Client"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','44444444-4444-4444-8444-444444444444','authenticated','authenticated',null,null,null,'999000000002',now(),'{"provider":"phone","providers":["phone"]}','{"nom":"TEST Chauffeur"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','55555555-5555-4555-8555-555555555555','authenticated','authenticated',null,null,null,'999000000003',now(),'{"provider":"phone","providers":["phone"]}','{"nom":"TEST Commerçant"}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','66666666-6666-4666-8666-666666666666','authenticated','authenticated',null,null,null,'999000000004',now(),'{"provider":"phone","providers":["phone"]}','{"nom":"TEST Prestataire"}',now(),now(),'','','','');
insert into auth.identities(provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at) values
 ('11111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111','{"sub":"11111111-1111-4111-8111-111111111111","email":"koki-test-admin@example.test","email_verified":true}','email',now(),now(),now()),
 ('22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222222','{"sub":"22222222-2222-4222-8222-222222222222","phone":"999000000001","phone_verified":true}','phone',now(),now(),now()),
 ('44444444-4444-4444-8444-444444444444','44444444-4444-4444-8444-444444444444','{"sub":"44444444-4444-4444-8444-444444444444","phone":"999000000002","phone_verified":true}','phone',now(),now(),now()),
 ('55555555-5555-4555-8555-555555555555','55555555-5555-4555-8555-555555555555','{"sub":"55555555-5555-4555-8555-555555555555","phone":"999000000003","phone_verified":true}','phone',now(),now(),now()),
 ('66666666-6666-4666-8666-666666666666','66666666-6666-4666-8666-666666666666','{"sub":"66666666-6666-4666-8666-666666666666","phone":"999000000004","phone_verified":true}','phone',now(),now(),now());
insert into public.koki_admin_members(user_id,role) values('11111111-1111-4111-8111-111111111111','superadmin');

-- 4. Commerces, services et transport : créés par les commandes métier sécurisées (mêmes contrôles que l'application).
create function pg_temp.koki_as(actor uuid,aal text,command text,input jsonb) returns jsonb language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','aal',aal)::text,true);
 return public.koki_business(command,input||jsonb_build_object('request_id',gen_random_uuid()));
end $$;
do $$
declare
 admin constant uuid:='11111111-1111-4111-8111-111111111111';
 driver constant uuid:='44444444-4444-4444-8444-444444444444';
 merchant constant uuid:='55555555-5555-4555-8555-555555555555';
 provider constant uuid:='66666666-6666-4666-8666-666666666666';
 d jsonb;v jsonb;m jsonb;p jsonb;shop jsonb;rate record;item jsonb;
begin
 d:=pg_temp.koki_as(driver,'aal1','register_driver','{"name":"TEST Chauffeur","phone":"+999000000002"}');
 v:=pg_temp.koki_as(driver,'aal1','save_vehicle',jsonb_build_object('parent_id',d->>'id','name','TEST Taxi','category','Taxi','registration','TEST-001'));
 m:=pg_temp.koki_as(merchant,'aal1','register_professional','{"name":"TEST Boutique","phone":"+999000000003","profile":"Commerçant"}');
 p:=pg_temp.koki_as(provider,'aal1','register_professional','{"name":"TEST Prestataire","phone":"+999000000004","profile":"Prestataire de services"}');
 foreach item in array array[d,v,m,p] loop
  perform pg_temp.koki_as(admin,'aal2','admin_review',jsonb_build_object('id',item->>'id','decision','approve'));
 end loop;
 for rate in select * from (values('Moto',200,100),('Taxi',500,250),('Voiture',700,300),('Minicar',1000,400)) t(category,base,km) loop
  perform pg_temp.koki_as(admin,'aal2','set_rate',jsonb_build_object('category',rate.category,'base_fcfa',rate.base,'per_km_fcfa',rate.km,'active',true));
 end loop;
 perform pg_temp.koki_as(driver,'aal1','driver_position','{"position":{"latitude":15.56,"longitude":-16.21},"available":true}');
 shop:=pg_temp.koki_as(merchant,'aal1','save_shop',jsonb_build_object('parent_id',m->>'id','name','TEST Boutique Koki','address','TEST Koki centre'));
 perform pg_temp.koki_as(merchant,'aal1','save_product',jsonb_build_object('parent_id',shop->>'id','name','TEST Riz 1 kg','price',500,'stock',20));
 perform pg_temp.koki_as(merchant,'aal1','save_product',jsonb_build_object('parent_id',shop->>'id','name','TEST Huile 1 L','price',1200,'stock',10));
 perform pg_temp.koki_as(provider,'aal1','save_service',jsonb_build_object('parent_id',p->>'id','name','TEST Plomberie','category','Plomberie','price',null));
 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','',true);
end $$;

-- 5. Contenus fictifs du site public (toutes les rubriques reliées à l'administration).
insert into public.koki_contents(type,titre,resume,texte,categorie,statut,publication,source,lieu,evenement,une,actif,emplacement,fin) values
 ('Actualités','TEST — Bienvenue sur Koki Connect (local)','Contenu fictif publié depuis la base locale.','Texte fictif pour vérifier l’affichage.','Actualité générale','publié',now()-interval '1 hour','TEST rédaction','',null,true,true,'Carte sponsorisée',null),
 ('Actualités','TEST — Brouillon non visible','Ce brouillon ne doit pas apparaître sur le site public.','','Communiqué','brouillon',now()-interval '1 hour','TEST rédaction','',null,false,true,'Carte sponsorisée',null),
 ('Annonces','TEST — Objet trouvé','Annonce fictive.','','Objet perdu/trouvé','publié',now()-interval '2 hours','TEST','',null,false,true,'Carte sponsorisée',null),
 ('Événements','TEST — Tournoi de quartier','Événement fictif.','','Vie communautaire','publié',now()-interval '3 hours','TEST','TEST Terrain municipal',now()+interval '7 days',false,true,'Carte sponsorisée',null),
 ('Sports & ASC','TEST — ASC Koki contre ASC Test','Match fictif.','','Match à venir','publié',now()-interval '4 hours','TEST','TEST Stade',now()+interval '3 days',false,true,'Carte sponsorisée',null),
 ('Opportunités','TEST — Offre d’emploi fictive','Emploi fictif pour tester la rubrique.','','Emploi','publié',now()-interval '5 hours','TEST','',null,false,true,'Carte sponsorisée',null),
 ('Opportunités','TEST — Bourse fictive','Bourse fictive pour tester la rubrique.','','Bourse','publié',now()-interval '6 hours','TEST','',null,false,true,'Carte sponsorisée',null),
 ('Publicités','TEST — Publicité fictive','Promotion fictive active 30 jours.','','Économie','publié',now()-interval '1 hour','TEST annonceur','',null,false,true,'Carte sponsorisée',now()+interval '30 days'),
 ('Informations utiles','TEST Lycée fictif de Koki','Établissement fictif.',jsonb_build_object('schema','koki.education.school','version',1,'niveau','Secondaire','secteur','Public','telephone','+999 00 000 00 05','horaires','Lundi–vendredi 8 h–17 h','description','Établissement fictif pour les tests.','archive',false)::text,'Éducation','publié',now()-interval '1 day','TEST','TEST Koki',null,false,true,'Carte sponsorisée',null);
-- Numéros d'urgence publics (mêmes valeurs et même source que assets/portail/numeros-utiles.json) + un numéro fictif.
insert into public.koki_contents(type,titre,resume,texte,categorie,statut,publication,source)
select 'Informations utiles',n.titre,n.resume,jsonb_build_object('schema','koki.numero.utile','version',1,'groupe',n.groupe,'telephone',n.tel,'description',n.resume,'verifie_le',n.verifie,'archive',false)::text,'Numéros utiles',n.statut,now()-interval '1 day',n.source
from (values
 ('Police secours','Appel gratuit, urgences de police.','17','Urgences nationales','2026-10-10','publié','Senego.com, liste « Numéros d''urgence au Sénégal » (consultée le 2026-10-10)'),
 ('Sapeurs-pompiers','Incendies, accidents, secours.','18','Urgences nationales','2026-10-10','publié','Senego.com, liste « Numéros d''urgence au Sénégal » (consultée le 2026-10-10)'),
 ('SAMU national','Urgences médicales.','1515','Urgences nationales','2026-10-10','publié','Senego.com, liste « Numéros d''urgence au Sénégal » (consultée le 2026-10-10)'),
 ('Numéro vert violences basées sur le genre','Gratuit et confidentiel.','800 00 20 20','Urgences nationales','2026-10-10','publié','Senego.com, liste « Numéros d''urgence au Sénégal » (consultée le 2026-10-10)'),
 ('TEST Mairie fictive','Numéro fictif pour tester la rubrique.','+999 00 000 00 06','Administration','','publié','TEST')
) n(titre,resume,tel,groupe,verifie,statut,source);
