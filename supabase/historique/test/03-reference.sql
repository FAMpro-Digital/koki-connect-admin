-- KOKI CONNECT TEST — RÉFÉRENCE DU 18/11/2026 (37 fichiers). GÉNÉRÉ par outils/assembler-test.sh, ne pas modifier.
-- NÉCESSITE UNE AUTORISATION EXPLICITE. Base TEST nettoyée uniquement (01-nettoyage.sql), jamais la production.
do $$ begin if exists(select 1 from auth.users limit 1) then raise exception 'GARDE : base non vide, référence refusée'; end if; end $$;

-- ===== 1/37 : supabase/schema.sql · sha256 74ee30fc44d5a1fe
-- Bootstrap à appliquer sur un projet Koki Connect dédié et vide.
begin;
create schema if not exists koki_private;
revoke all on schema koki_private from public;
grant usage on schema koki_private to authenticated;
create table public.koki_admin_members(user_id uuid primary key references auth.users(id) on delete cascade,role text not null check(role in ('superadmin','manager','editor','analyst')),enabled boolean not null default true,created_at timestamptz not null default now());
alter table public.koki_admin_members enable row level security;
revoke all on public.koki_admin_members from anon,authenticated;
grant select on public.koki_admin_members to authenticated;
create policy membership_self on public.koki_admin_members for select to authenticated using(user_id=(select auth.uid()));
-- Cette fonction ne lit que l'autorisation du compte identifié ; jamais user_metadata.
create function koki_private.allowed(permission text) returns boolean language sql stable security definer set search_path='' as $$
select coalesce((select auth.jwt()->>'aal')='aal2' and exists(select 1 from public.koki_admin_members m where m.user_id=(select auth.uid()) and m.enabled and (m.role='superadmin' or (permission='read' and m.role in ('manager','editor','analyst')) or (permission='content' and m.role='editor') or (permission in ('commerce','transport') and m.role='manager'))),false)
$$;
revoke all on function koki_private.allowed(text) from public;
grant execute on function koki_private.allowed(text) to authenticated;
create table public.koki_contents(
 id uuid primary key default gen_random_uuid(),type text not null check(type in ('Actualités','Annonces','Publicités','Événements','Sports & ASC','Opportunités','Informations utiles')),
 titre text not null check(length(trim(titre)) between 1 and 180),resume text not null check(length(trim(resume)) between 1 and 2000),texte text not null default '' check(length(texte)<=30000),categorie text not null default '',statut text not null default 'brouillon' check(statut in ('brouillon','publié')),publication timestamptz not null,source text not null default '',lieu text not null default '',evenement timestamptz,image_path text,une boolean not null default false,actif boolean not null default true,emplacement text not null default 'Carte sponsorisée',fin timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),revision integer not null default 1,
 check(fin is null or fin>publication),check(type<>'Événements' or (evenement is not null and length(trim(lieu))>0)),check(image_path is null or image_path ~ '^[a-f0-9-]+/[a-f0-9-]+\.(jpg|png|webp)$')
);
create index koki_contents_feed on public.koki_contents(statut,publication desc);
create table public.koki_records(id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('professionnels','boutiques','produits','services','chauffeurs','vehicules','commandes','demandes_services','courses')),statut text not null,payload jsonb not null check(jsonb_typeof(payload)='object' and coalesce(length(trim(payload->>'nom')),0)>0),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),revision integer not null default 1);
alter table public.koki_records add constraint koki_record_status check(
(kind='professionnels' and statut in ('À valider','Actif','Suspendu')) or
(kind='boutiques' and statut in ('À valider','Actif','Fermé')) or
(kind='produits' and statut in ('Disponible','Épuisé','Masqué')) or
(kind='services' and statut in ('Disponible','Indisponible','Masqué')) or
(kind='chauffeurs' and statut in ('À valider','Disponible','Indisponible','Suspendu')) or
(kind='vehicules' and statut in ('Actif','Indisponible')) or
(kind='commandes' and statut in ('Commande reçue','Confirmée','Préparation','En livraison','Livrée','Annulée')) or
(kind='demandes_services' and statut in ('Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé','Annulée')) or
(kind='courses' and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours','Terminée','Annulée')));
-- Contrôles serveur des nombres ; les identifiants de références restent à normaliser
-- avant de brancher de vraies transactions commerciales.
alter table public.koki_records add constraint koki_record_numbers check(
(not payload ? 'stock' or payload->'stock'='null'::jsonb or (jsonb_typeof(payload->'stock')='number' and (payload->>'stock')::numeric between 0 and 1000000 and trunc((payload->>'stock')::numeric)=(payload->>'stock')::numeric)) and
(not payload ? 'prix' or payload->'prix'='null'::jsonb or (jsonb_typeof(payload->'prix')='number' and (payload->>'prix')::numeric between 0 and 1000000000)) and
(not payload ? 'latitude' or payload->'latitude'='null'::jsonb or (jsonb_typeof(payload->'latitude')='number' and (payload->>'latitude')::numeric between -90 and 90)) and
(not payload ? 'longitude' or payload->'longitude'='null'::jsonb or (jsonb_typeof(payload->'longitude')='number' and (payload->>'longitude')::numeric between -180 and 180)));
create index koki_records_kind on public.koki_records(kind,updated_at desc);
create table public.koki_users(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create function koki_private.register_user() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.koki_users(user_id) values(new.id);return new;end $$;
revoke all on function koki_private.register_user() from public;
create trigger koki_register_user after insert on auth.users for each row execute function koki_private.register_user();
insert into public.koki_users(user_id,created_at) select id,created_at from auth.users;
create table public.koki_audit(id bigint generated always as identity primary key,actor_id uuid,operation text not null,table_name text not null,record_id uuid not null,details jsonb not null,created_at timestamptz not null default now());
create index koki_audit_date on public.koki_audit(created_at desc);
alter table public.koki_contents enable row level security;
alter table public.koki_records enable row level security;
alter table public.koki_users enable row level security;
alter table public.koki_audit enable row level security;
revoke all on public.koki_contents,public.koki_records,public.koki_users,public.koki_audit from anon,authenticated;
grant select on public.koki_contents to anon;
grant select,insert,update,delete on public.koki_contents,public.koki_records to authenticated;
grant select on public.koki_users,public.koki_audit to authenticated;
create policy contents_public on public.koki_contents for select to anon,authenticated using(statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now()))));
create policy contents_admin_read on public.koki_contents for select to authenticated using((select koki_private.allowed('read')));
create policy contents_insert on public.koki_contents for insert to authenticated with check((select koki_private.allowed('content')));
create policy contents_update on public.koki_contents for update to authenticated using((select koki_private.allowed('content'))) with check((select koki_private.allowed('content')));
create policy contents_delete on public.koki_contents for delete to authenticated using((select koki_private.allowed('content')));
create policy records_read on public.koki_records for select to authenticated using((select koki_private.allowed('read')));
create policy records_insert on public.koki_records for insert to authenticated with check(koki_private.allowed(case when kind in ('chauffeurs','vehicules','courses') then 'transport' else 'commerce' end));
create policy records_update on public.koki_records for update to authenticated using(koki_private.allowed(case when kind in ('chauffeurs','vehicules','courses') then 'transport' else 'commerce' end)) with check(koki_private.allowed(case when kind in ('chauffeurs','vehicules','courses') then 'transport' else 'commerce' end));
create policy records_delete on public.koki_records for delete to authenticated using(koki_private.allowed(case when kind in ('chauffeurs','vehicules','courses') then 'transport' else 'commerce' end));
create policy users_read on public.koki_users for select to authenticated using((select koki_private.allowed('read')));
create policy audit_read on public.koki_audit for select to authenticated using((select koki_private.allowed('audit')));
-- Révisions et champs système ne peuvent pas être forcés par le navigateur.
create function koki_private.stamp() returns trigger language plpgsql set search_path='' as $$ begin
if TG_OP='INSERT' then new.created_at=now();new.revision=1;else new.id=old.id;new.created_at=old.created_at;new.revision=old.revision+1;end if;new.updated_at=clock_timestamp();return new;end $$;
revoke all on function koki_private.stamp() from public;
create trigger contents_stamp before insert or update on public.koki_contents for each row execute function koki_private.stamp();
create trigger records_stamp before insert or update on public.koki_records for each row execute function koki_private.stamp();
-- Journal atomique minimal : pas de mots de passe, pas de copie de coordonnées clients.
create function koki_private.audit() returns trigger language plpgsql security definer set search_path='' as $$ declare r record;begin
if TG_OP='DELETE' then r=old;else r=new;end if;
insert into public.koki_audit(actor_id,operation,table_name,record_id,details) values(auth.uid(),TG_OP,TG_TABLE_NAME,r.id,jsonb_build_object('revision',r.revision,'statut',r.statut));return r;end $$;
revoke all on function koki_private.audit() from public;
create trigger contents_audit after insert or update or delete on public.koki_contents for each row execute function koki_private.audit();
create trigger records_audit after insert or update or delete on public.koki_records for each row execute function koki_private.audit();
-- Statistiques via RLS ; aucune donnée fictive, aucune opération de paiement simulée.
create function public.koki_statistics() returns jsonb language plpgsql security invoker set search_path='' as $$ begin
if not koki_private.allowed('read') then raise exception 'Administration et MFA requises' using errcode='42501';end if;
return jsonb_build_object('Utilisateurs inscrits',(select count(*) from public.koki_users),'Utilisateurs actifs',null,'Actualités publiées',(select count(*) from public.koki_contents where type='Actualités' and statut='publié' and publication<=now()),'Annonces publiées',(select count(*) from public.koki_contents where type='Annonces' and statut='publié' and publication<=now()),'Publicités actives',(select count(*) from public.koki_contents where type='Publicités' and statut='publié' and actif and publication<=now() and (fin is null or fin>now())),'Commerces et prestataires',(select count(*) from public.koki_records where kind='professionnels'),'Chauffeurs',(select count(*) from public.koki_records where kind='chauffeurs'),'Courses',(select count(*) from public.koki_records where kind='courses'),'Commandes',(select count(*) from public.koki_records where kind='commandes'),'Demandes de services',(select count(*) from public.koki_records where kind='demandes_services'),'Revenus FCFA',null,'Impressions publicitaires',null,'Clics publicitaires',null,'mesure_le',now());end $$;
revoke all on function public.koki_statistics() from public;
grant execute on function public.koki_statistics() to authenticated;
-- Flux de synchronisation compatible avec le portail public ; à brancher après validation.
create function public.koki_public_feed() returns jsonb language sql stable security invoker set search_path='' as $$
select jsonb_build_object('version',1,'contenus',coalesce(jsonb_agg(jsonb_build_object('id',id,'type',type,'titre',titre,'resume',resume,'texte',texte,'categorie',categorie,'statut',statut,'publication',publication,'source',source,'lieu',lieu,'evenement',evenement,'image_path',image_path,'une',une,'actif',actif,'emplacement',emplacement,'fin',fin) order by publication desc),'[]'::jsonb)) from public.koki_contents where statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))
$$;
revoke all on function public.koki_public_feed() from public;
grant execute on function public.koki_public_feed() to anon,authenticated;
-- Images privées : une image n’est accessible au public que si son contenu est publié.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('koki-media','koki-media',false,1048576,array['image/jpeg','image/png','image/webp']);
create policy koki_media_insert on storage.objects for insert to authenticated with check(bucket_id='koki-media' and (storage.foldername(name))[1]=(select auth.uid())::text and (koki_private.allowed('content') or koki_private.allowed('commerce') or koki_private.allowed('transport')));
create policy koki_media_published on storage.objects for select to anon,authenticated using(bucket_id='koki-media' and exists(select 1 from public.koki_contents c where c.image_path=name and c.statut='publié' and c.publication<=now() and (c.type<>'Publicités' or (c.actif and (c.fin is null or c.fin>now())))));
create policy koki_media_read on storage.objects for select to authenticated using(bucket_id='koki-media' and koki_private.allowed('read'));
create policy koki_media_delete on storage.objects for delete to authenticated using(bucket_id='koki-media' and (koki_private.allowed('content') or koki_private.allowed('commerce') or koki_private.allowed('transport')) and (storage.foldername(name))[1]=(select auth.uid())::text);
commit;


-- ===== 2/37 : supabase/hardening.sql · sha256 2bd514410e064069
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
grant select on storage.objects to anon;


-- ===== 3/37 : supabase/proposals/education-bibliotheque.sql · sha256 1b657821cb117e98
-- Éducation · Bibliothèque : fichiers des livres (PDF, EPUB, audio MP3/M4A).
-- Proposition relue, à appliquer d'abord sur Supabase LOCAL puis préproduction, jamais directement en production.
-- Bucket privé « koki-livres », séparé de « koki-media » (photos 1 Mo).
-- 50 Mo maximum par fichier : limite d'envoi du forfait Supabase Free.
-- Le public ne peut lire QUE le fichier d'un livre GRATUIT, publié, non archivé et visible à la date courante.
-- Un livre payant n'a jamais de fichier publié (contrat koki.education.book) : rien n'est lisible par le public.
begin;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('koki-livres','koki-livres',false,52428800,array['application/pdf','application/epub+zip','audio/mpeg','audio/mp4','audio/x-m4a']);

-- Vrai si « path » est le fichier d'un livre gratuit publié. Les textes non JSON sont ignorés sans erreur.
create function koki_private.livre_gratuit_publie(path text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare r record;v jsonb;
begin
 if path is null or path !~ '^[a-f0-9-]+/[a-f0-9-]+\.(pdf|epub|mp3|m4a)$' then return false;end if;
 for r in select c.texte from public.koki_contents c
   where c.type='Informations utiles' and c.categorie='Éducation' and c.statut='publié' and c.publication<=now() and strpos(c.texte,path)>0
 loop
  begin v:=r.texte::jsonb;exception when others then continue;end;
  if v->>'schema'='koki.education.book' and v->>'acces'='Gratuit' and coalesce(v->>'archive','false')='false' and v->>'fichier'=path then return true;end if;
 end loop;
 return false;
end $$;
revoke all on function koki_private.livre_gratuit_publie(text) from public;
grant execute on function koki_private.livre_gratuit_publie(text) to anon,authenticated;

-- Éditeurs (MFA exigée par koki_private.allowed) : envoi dans leur propre dossier.
create policy livres_insert on storage.objects for insert to authenticated
 with check(bucket_id='koki-livres' and (storage.foldername(name))[1]=(select auth.uid())::text and koki_private.allowed('content'));
-- Administration : lecture pour vérifier les fichiers.
create policy livres_admin_read on storage.objects for select to authenticated
 using(bucket_id='koki-livres' and koki_private.allowed('read'));
-- Public : uniquement les livres gratuits publiés.
create policy livres_public_read on storage.objects for select to anon,authenticated
 using(bucket_id='koki-livres' and koki_private.livre_gratuit_publie(name));
-- Suppression : par son auteur, seulement si plus aucune fiche ne référence le fichier.
create policy livres_delete on storage.objects for delete to authenticated
 using(bucket_id='koki-livres' and koki_private.allowed('content') and (storage.foldername(name))[1]=(select auth.uid())::text
  and not exists(select 1 from public.koki_contents c where strpos(c.texte,name)>0));

commit;


-- ===== 4/37 : supabase/production/koki-production-phases-2-6.sql · sha256 78dd7ecf54232512
-- KOKI CONNECT — MISE À JOUR DE LA PRODUCTION qsbmzzbiztfqysstepxm : phases 2 à 6 (Commerces, Transport, espace professionnel).
-- GÉNÉRÉ par scripts/prepare-production-phases.mjs — NE PAS MODIFIER À LA MAIN.
-- Une seule transaction : en cas d'erreur, rien n'est modifié. Aucune donnée fictive, aucun marqueur TEST.
begin;
-- GARDE : n'accepte que l'état vérifié de la production (schéma initial + Bibliothèque, aucune phase 2 à 6).
do $$ begin
 if current_setting('server_version_num')::integer<170000 then raise exception 'GARDE : PostgreSQL 17 requis';end if;
 if to_regclass('koki_private.test_environment') is not null then raise exception 'GARDE : base de TEST, paquet réservé à la production';end if;
 if to_regprocedure('public.koki_business(text,jsonb)') is not null or to_regclass('public.koki_order_items') is not null then raise exception 'GARDE : phases déjà installées';end if;
 if to_regclass('public.koki_records') is null or to_regprocedure('koki_private.allowed(text)') is null then raise exception 'GARDE : schéma initial absent';end if;
 if to_regprocedure('koki_private.livre_gratuit_publie(text)') is null then raise exception 'GARDE : Bibliothèque non installée';end if;
 if exists(select 1 from public.koki_records where id<>'b381d81b-2fc8-4559-b0b4-5251813daffa') then raise exception 'GARDE : fiches métier inattendues, rapprochement nécessaire';end if;
end $$;
-- Archive privée des éléments retirés par une migration (lecture réservée au propriétaire de la base).
create table koki_private.migration_archive(id uuid primary key default gen_random_uuid(),archived_at timestamptz not null default now(),reason text not null,source_table text not null,data jsonb not null);
alter table koki_private.migration_archive enable row level security;
revoke all on koki_private.migration_archive from public,anon,authenticated;
insert into koki_private.migration_archive(reason,source_table,data)
 select 'Fiche d''essai sans compte supprimée avant les phases 2 à 6 (décision du propriétaire, 13/10/2026)','public.koki_records',to_jsonb(r)
 from public.koki_records r where r.id='b381d81b-2fc8-4559-b0b4-5251813daffa';
delete from public.koki_records where id='b381d81b-2fc8-4559-b0b4-5251813daffa';

-- SOURCE : supabase/proposals/commerce-transport-foundation.sql · sha256 d76658e96fddde506e4b087fb8f0be68ac321eff4c73666ceada552606d46d5c
-- PROPOSITION A REVOIR : jamais exécutée sur le projet Supabase réel.
-- Fondation uniquement. Les écritures publiques restent interdites jusqu'aux RPC métier.
-- Réutilise koki_records, koki_admin_members, koki_private.allowed et le journal existants.

alter table public.koki_records
 add column owner_id uuid references auth.users(id) on delete restrict,
 add column client_id uuid references auth.users(id) on delete restrict,
 add column parent_id uuid references public.koki_records(id) on delete restrict,
 add column provider_id uuid references public.koki_records(id) on delete restrict,
 add column driver_id uuid references public.koki_records(id) on delete restrict,
 add column source_id uuid references public.koki_records(id) on delete restrict;
-- Pas de backfill implicite depuis les chaînes JSON : validation des propriétaires requise.
create index koki_records_owner on public.koki_records(owner_id,kind,updated_at desc);
create index koki_records_client on public.koki_records(client_id,kind,updated_at desc);
create index koki_records_parent on public.koki_records(parent_id);
create index koki_records_provider on public.koki_records(provider_id);
create index koki_records_driver on public.koki_records(driver_id);
create index koki_records_source on public.koki_records(source_id);

-- Booléen limité au propriétaire courant ; aucune identité tierce retournée.
create function koki_private.owns_business(record_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records r where r.id=record_id
   and r.owner_id=(select auth.uid())
   and ((r.kind='professionnels' and r.statut='Actif')
     or (r.kind='chauffeurs' and r.statut in ('Disponible','Indisponible'))))
$$;
revoke all on function koki_private.owns_business(uuid) from public,anon;
grant execute on function koki_private.owns_business(uuid) to authenticated;
create policy records_participants_read on public.koki_records for select to authenticated using(
 (owner_id=(select auth.uid()) and kind in ('professionnels','boutiques','produits','services','chauffeurs','vehicules'))
 or (client_id=(select auth.uid()) and kind in ('commandes','demandes_services','courses'))
 or (kind in ('commandes','demandes_services') and koki_private.owns_business(provider_id))
 or (kind='courses' and koki_private.owns_business(driver_id))
);
-- Aucun INSERT/UPDATE/DELETE pour clients ou professionnels. RPC contrôlées à ajouter.

create table public.koki_order_items(
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.koki_records(id) on delete restrict,
 product_id uuid not null references public.koki_records(id) on delete restrict,
 quantity integer not null check(quantity between 1 and 10000),
 unit_price bigint not null check(unit_price between 0 and 1000000000),
 product_name text not null check(length(trim(product_name)) between 1 and 180),
 unique(order_id,product_id)
);
create index koki_order_items_product on public.koki_order_items(product_id);
alter table public.koki_order_items enable row level security;
revoke all on public.koki_order_items from anon,authenticated;
grant select on public.koki_order_items to authenticated;
create policy order_items_participant_read on public.koki_order_items for select to authenticated using(
 exists(select 1 from public.koki_records r where r.id=order_id and r.kind='commandes')
);
-- Les tarifs ne contiennent aucune donnée personnelle et sont publiables après validation.
create table public.koki_transport_rates(
 category text primary key check(category in ('Moto','Taxi','Voiture','Minicar')),
 base_fcfa integer not null check(base_fcfa between 0 and 1000000),
 per_km_fcfa integer not null check(per_km_fcfa between 0 and 1000000),
 active boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.koki_transport_rates enable row level security;
revoke all on public.koki_transport_rates from anon,authenticated;
grant select on public.koki_transport_rates to anon,authenticated;
grant insert,update,delete on public.koki_transport_rates to authenticated;
create policy rates_public_read on public.koki_transport_rates for select to anon,authenticated using(active);
create policy rates_admin_read on public.koki_transport_rates for select to authenticated using(koki_private.allowed('read'));
create policy rates_admin_insert on public.koki_transport_rates for insert to authenticated with check(koki_private.allowed('transport'));
create policy rates_admin_update on public.koki_transport_rates for update to authenticated using(koki_private.allowed('transport')) with check(koki_private.allowed('transport'));
create policy rates_admin_delete on public.koki_transport_rates for delete to authenticated using(koki_private.allowed('transport'));
-- Aucun tarif fictif inséré. L'absence de tarif actif bloque les futures réservations réelles.

-- SOURCE : supabase/proposals/phase2-transactions.sql · sha256 9141a7e0f10654d9eb3dbb1019fce5a431994007af76c5f4ec5c2e8c481c23fb
-- PHASE 2 — A REVOIR AVANT APPLICATION. Aucune donnée réelle à importer.
-- Prérequis : schema.sql déjà appliqué, puis commerce-transport-foundation.sql.
-- Les anciens formulaires métier doivent être raccordés aux RPC avant activation.

-- Aucun propriétaire n'est inventé à partir d'une chaîne JSON ancienne.
do $$ begin
 if exists(select 1 from public.koki_records where owner_id is null and client_id is null) then
   raise exception 'Préflight : les anciens éléments métier doivent être rapprochés de leurs propriétaires avant migration';
 end if;
end $$;
create unique index koki_driver_account on public.koki_records(owner_id) where kind='chauffeurs';
create unique index koki_professional_account on public.koki_records(owner_id) where kind='professionnels';
create unique index koki_driver_one_active_ride on public.koki_records(driver_id)
 where public.koki_records.kind='courses' and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours');
create unique index koki_client_one_active_ride on public.koki_records(client_id)
 where public.koki_records.kind='courses' and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours');
alter table public.koki_records add constraint koki_business_owner check(
 (kind in ('professionnels','boutiques','produits','services','chauffeurs','vehicules') and owner_id is not null and client_id is null)
 or (kind in ('commandes','demandes_services','courses') and owner_id is null and client_id is not null));
alter table public.koki_records drop constraint koki_record_status;
alter table public.koki_records add constraint koki_record_status check(
(kind='professionnels' and statut in ('À valider','Actif','Suspendu')) or
(kind='boutiques' and statut in ('À valider','Actif','Fermé')) or
(kind='produits' and statut in ('Disponible','Épuisé','Masqué')) or
(kind='services' and statut in ('Disponible','Indisponible','Masqué')) or
(kind='chauffeurs' and statut in ('À valider','Disponible','Indisponible','Suspendu')) or
(kind='vehicules' and statut in ('Actif','Indisponible')) or
(kind='commandes' and statut in ('Commande reçue','Confirmée','Préparation','En livraison','Livrée','Prête au retrait','Retirée','Annulée')) or
(kind='demandes_services' and statut in ('Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé','Annulée')) or
(kind='courses' and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours','Terminée','Annulée')));
create policy users_self_read on public.koki_users for select to authenticated using(user_id=(select auth.uid()));
alter table public.koki_records add constraint business_required_links check(
 (kind in ('professionnels','chauffeurs') and parent_id is null and provider_id is null and driver_id is null)
 or (kind in ('boutiques','produits','services','vehicules') and parent_id is not null and provider_id is null and driver_id is null)
 or (kind in ('commandes','demandes_services') and parent_id is not null and provider_id is not null and driver_id is null)
 or (kind='courses' and parent_id is not null and driver_id is not null and provider_id is null));
alter table public.koki_records add constraint business_source_reserved check(source_id is null);
-- Valider les anciennes relations sans UPDATE, sans audit ou backfill implicite.
do $$ begin
 if exists(select 1 from public.koki_records r where r.parent_id is not null and not exists(select 1 from public.koki_records p where p.id=r.parent_id
 and p.kind=case r.kind when 'boutiques' then 'professionnels' when 'services' then 'professionnels' when 'produits' then 'boutiques' when 'vehicules' then 'chauffeurs' when 'commandes' then 'boutiques' when 'demandes_services' then 'services' when 'courses' then 'vehicules' end
 and (r.owner_id is null or r.owner_id=p.owner_id)))
 or exists(select 1 from public.koki_records r join public.koki_records p on p.id=r.parent_id where r.kind in ('commandes','demandes_services') and not exists(select 1 from public.koki_records pro where pro.id=r.provider_id and pro.kind='professionnels' and pro.owner_id=p.owner_id))
 or exists(select 1 from public.koki_records r join public.koki_records v on v.id=r.parent_id where r.kind='courses' and not exists(select 1 from public.koki_records d where d.id=r.driver_id and d.kind='chauffeurs' and v.parent_id=d.id)) then raise exception 'Préflight : relations métier incohérentes à rapprocher';end if;
end $$;
-- Les transactions et leurs acteurs restent consultables ; aucune suppression directe.
revoke insert,update,delete on public.koki_records from authenticated;
drop policy records_read on public.koki_records;
create policy records_admin_business_read on public.koki_records for select to authenticated using(koki_private.allowed(case when kind in ('chauffeurs','vehicules','courses') then 'transport' else 'commerce' end));
revoke insert,update,delete on public.koki_transport_rates from authenticated;

create table koki_private.ride_quotes(
 id uuid primary key default gen_random_uuid(),client_id uuid not null references auth.users(id),
 category text not null references public.koki_transport_rates(category),
 start_point jsonb not null,end_point jsonb not null,distance_km numeric not null,fare_fcfa bigint not null,
 expires_at timestamptz not null default now()+interval '5 minutes',
 ride_id uuid references public.koki_records(id)
);
revoke all on koki_private.ride_quotes from public,anon,authenticated;
-- Recherche de chauffeurs limitée par compte : empêche de retrouver une position par appels répétés.
create table koki_private.nearby_lookups(actor_id uuid not null,created_at timestamptz not null default now());
create index koki_nearby_lookups_actor on koki_private.nearby_lookups(actor_id,created_at desc);
alter table koki_private.nearby_lookups enable row level security;
revoke all on koki_private.nearby_lookups from public,anon,authenticated;
create index ride_quotes_expiry on koki_private.ride_quotes(expires_at);
create table koki_private.business_keys(
 actor_id uuid not null references auth.users(id) on delete restrict,
 request_id uuid not null,
 command text not null,
 input jsonb not null,
 output jsonb not null,
 created_at timestamptz not null default now(),
 primary key(actor_id,request_id)
);
revoke all on koki_private.business_keys from public,anon,authenticated;

-- Types et propriétaires des relations vérifiés même pour les écritures privilégiées.
create function koki_private.business_relations() returns trigger
language plpgsql set search_path='' as $$
declare p public.koki_records;d public.koki_records;
begin
 if new.kind in ('boutiques','services','produits','vehicules','commandes','demandes_services','courses') then
   select * into p from public.koki_records where id=new.parent_id;
   if p.id is null then raise exception 'Relation parente obligatoire';end if;
   if (new.kind in ('boutiques','services') and p.kind<>'professionnels')
     or (new.kind='produits' and p.kind<>'boutiques')
     or (new.kind='vehicules' and p.kind<>'chauffeurs')
     or (new.kind='commandes' and p.kind<>'boutiques')
     or (new.kind='demandes_services' and p.kind<>'services')
     or (new.kind='courses' and p.kind<>'vehicules') then raise exception 'Type de relation invalide';end if;
   if new.owner_id is not null and new.owner_id is distinct from p.owner_id then raise exception 'Propriétaires incompatibles';end if;
 end if;
 if new.kind='courses' then
   select * into d from public.koki_records where id=new.driver_id;
   if d.kind is distinct from 'chauffeurs' or p.parent_id is distinct from d.id then raise exception 'Véhicule et chauffeur incompatibles';end if;
 elsif new.kind in ('commandes','demandes_services') then
   select * into d from public.koki_records where id=new.provider_id;
   if d.kind is distinct from 'professionnels' or d.owner_id is distinct from p.owner_id then raise exception 'Professionnel incompatible';end if;
 end if;
 if new.source_id is not null then raise exception 'Liaison livraison réservée à une évolution contrôlée';end if;
 if TG_OP='UPDATE' and (new.kind is distinct from old.kind or new.owner_id is distinct from old.owner_id or new.client_id is distinct from old.client_id or new.parent_id is distinct from old.parent_id or new.provider_id is distinct from old.provider_id or new.driver_id is distinct from old.driver_id) then
   raise exception 'Acteurs et relations immuables';
 end if;
 return new;
end $$;
revoke all on function koki_private.business_relations() from public,anon,authenticated;
create trigger business_relations before insert or update on public.koki_records for each row execute function koki_private.business_relations();

create function koki_private.business_item_relation() returns trigger language plpgsql set search_path='' as $$
declare o public.koki_records;p public.koki_records;
begin
 select * into o from public.koki_records where id=new.order_id;select * into p from public.koki_records where id=new.product_id;
 if o.kind is distinct from 'commandes' or p.kind is distinct from 'produits' or o.parent_id is distinct from p.parent_id then raise exception 'Ligne et boutique incompatibles';end if;
 return new;
end $$;
revoke all on function koki_private.business_item_relation() from public,anon,authenticated;
create trigger business_item_relation before insert or update on public.koki_order_items for each row execute function koki_private.business_item_relation();

create function koki_private.business_keys_allowed(input jsonb,allowed text[]) returns void language plpgsql set search_path='' as $$
begin
 if input is null or jsonb_typeof(input)<>'object' or exists(select 1 from jsonb_object_keys(input) k where not k=any(allowed)) then raise exception 'Champs inconnus ou requête invalide';end if;
end $$;
create function koki_private.business_text(input jsonb,field text,minimum integer,maximum integer) returns text language plpgsql set search_path='' as $$
declare v text:=trim(input->>field);
begin
 if jsonb_typeof(input->field) is distinct from 'string' or length(v) not between minimum and maximum then raise exception 'Champ texte invalide : %',field;end if;return v;
end $$;
create function koki_private.business_point(point jsonb) returns boolean language plpgsql set search_path='' as $$
begin
 return coalesce(jsonb_typeof(point)='object' and jsonb_typeof(point->'latitude')='number' and jsonb_typeof(point->'longitude')='number'
 and (point->>'latitude')::numeric between -90 and 90 and (point->>'longitude')::numeric between -180 and 180,false);
exception when others then return false;
end $$;
create function koki_private.business_distance(a jsonb,b jsonb) returns numeric language plpgsql set search_path='' as $$
declare h double precision;
begin
 if not koki_private.business_point(a) or not koki_private.business_point(b) then raise exception 'Coordonnées invalides';end if;
 h:=power(sin(radians(((b->>'latitude')::double precision-(a->>'latitude')::double precision)/2)),2)
 +cos(radians((a->>'latitude')::double precision))*cos(radians((b->>'latitude')::double precision))*power(sin(radians(((b->>'longitude')::double precision-(a->>'longitude')::double precision)/2)),2);
 return (12742*asin(least(1,sqrt(h))))::numeric;
end $$;
create function koki_private.business_can_read(r public.koki_records) returns boolean language sql stable set search_path='' as $$
 select koki_private.allowed(case when r.kind in ('chauffeurs','vehicules','courses') then 'transport' else 'commerce' end) or r.owner_id=auth.uid() or r.client_id=auth.uid()
 or (r.kind in ('commandes','demandes_services') and koki_private.owns_business(r.provider_id))
 or (r.kind='courses' and koki_private.owns_business(r.driver_id))
$$;
-- Aucun de ces helpers n'est une API directe.
revoke all on function koki_private.business_keys_allowed(jsonb,text[]),koki_private.business_text(jsonb,text,integer,integer),koki_private.business_point(jsonb),koki_private.business_distance(jsonb,jsonb),koki_private.business_can_read(public.koki_records) from public,anon,authenticated;

create function koki_private.business_owned_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select path is null or (path ~ ('^'||auth.uid()::text||'/[a-f0-9-]+\.(jpg|png|webp)$') and exists(select 1 from storage.objects o where o.bucket_id='koki-media' and o.name=path))
$$;
revoke all on function koki_private.business_owned_image(text) from public,anon,authenticated;

-- Autorité métier unique. Chaque branche fait ses contrôles ; aucune clé service_role requise dans le client.
create function koki_private.business(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid();key uuid;cached koki_private.business_keys;outcome jsonb;r public.koki_records;p public.koki_records;d public.koki_records;v public.koki_records;
 rate public.koki_transport_rates;entity_id uuid;entity_kind text;next_status text;profile text;distance numeric;total bigint:=0;qty integer;price bigint;line jsonb;items jsonb;
 steps text[];pos jsonb;phone text;quote koki_private.ride_quotes;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if command='catalog' then
   perform koki_private.business_keys_allowed(input,array[]::text[]);
   return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'parent_id',x.parent_id,'provider_id',x.provider_id,'nom',x.payload->>'nom','description',x.payload->>'description','categorie',x.payload->>'categorie','prix',x.payload->'prix','stock',x.payload->'stock','telephone',case when x.kind='professionnels' then x.payload->>'telephone' end,'adresse',case when x.kind='boutiques' then x.payload->>'adresse' end,'image_path',x.payload->>'image_path') order by x.updated_at desc) from
   (select listing.* from public.koki_records listing where (listing.kind='professionnels' and listing.statut='Actif')
    or (listing.kind='boutiques' and listing.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
    or (listing.kind='services' and listing.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.statut='Actif'))
    or (listing.kind='produits' and listing.statut='Disponible' and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=listing.parent_id and b.statut='Actif' and prof.statut='Actif'))
    order by listing.updated_at desc limit 200) x),'[]'::jsonb);
 end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if command in ('history','get') then
   perform koki_private.business_keys_allowed(input,case when command='history' then array['kind'] else array['id'] end);
   if command='get' then select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
     if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès refusé' using errcode='42501';end if;
     return to_jsonb(r)||jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i)) from public.koki_order_items i where i.order_id=r.id),'[]'::jsonb));
   end if;
   if input->>'kind' is null or input->>'kind' not in ('courses','commandes','demandes_services') then raise exception 'Historique invalide';end if;
   return coalesce((select jsonb_agg(to_jsonb(x)) from (select hist.* from public.koki_records hist where hist.kind=input->>'kind' and coalesce(koki_private.business_can_read(hist),false) order by hist.created_at desc limit 100)x),'[]'::jsonb);
 end if;
 if command='ride_contacts' then
   perform koki_private.business_keys_allowed(input,array['id']);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind is distinct from 'courses' or not coalesce(koki_private.business_can_read(r),false) or r.statut not in ('Acceptée','Chauffeur en route','Course en cours') then raise exception 'Contacts réservés à une course acceptée active' using errcode='42501';end if;
   select * into d from public.koki_records where public.koki_records.id=r.driver_id;
   return jsonb_build_object('name',d.payload->>'nom','phone',d.payload->>'telephone');
 end if;
 if command='quote' then
   perform koki_private.business_keys_allowed(input,array['category','start','end']);
   distance:=koki_private.business_distance(input->'start',input->'end');
   if distance<.05 or distance>200 then raise exception 'Trajet entre 50 mètres et 200 km requis';end if;
   select * into rate from public.koki_transport_rates where category=input->>'category' and active;
   if rate.category is null then raise exception 'Tarif validé indisponible';end if;
   insert into koki_private.ride_quotes(client_id,category,start_point,end_point,distance_km,fare_fcfa)
   values(actor,rate.category,jsonb_build_object('latitude',input->'start'->'latitude','longitude',input->'start'->'longitude'),jsonb_build_object('latitude',input->'end'->'latitude','longitude',input->'end'->'longitude'),distance,ceil((rate.base_fcfa+distance*rate.per_km_fcfa)/50)*50) returning * into quote;
   return jsonb_build_object('quote_id',quote.id,'expires_at',quote.expires_at,'distance_km',round(distance,3),'fare_fcfa',quote.fare_fcfa,'method','À vol d’oiseau','indicative',true);
 end if;
 if command='nearby_drivers' then
   perform koki_private.business_keys_allowed(input,array['category','start']);
   if not koki_private.business_point(input->'start') or input->>'category' is null or input->>'category' not in ('Moto','Taxi','Voiture','Minicar') then raise exception 'Recherche invalide';end if;
   -- 10 recherches par minute et 60 par heure ; distance calculée sur une position arrondie (~500 m),
   -- sinon la frontière des 10 km permettrait de trianguler la position exacte du chauffeur.
   perform pg_advisory_xact_lock(hashtextextended('nearby:'||actor::text,0));
   if (select count(*) from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at>now()-interval '1 minute')>=10
    or (select count(*) from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at>now()-interval '1 hour')>=60 then
     raise exception 'Trop de recherches. Patientez quelques minutes.';end if;
   delete from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at<now()-interval '1 day';
   insert into koki_private.nearby_lookups(actor_id) values(actor);
   return coalesce((select jsonb_agg(jsonb_build_object('driver_id',x.driver_id,'vehicle_id',x.vehicle_id,'name',x.name,'category',x.category,'proximity','À proximité (moins de 10 km)')) from
   (select drv.id driver_id,veh.id vehicle_id,drv.payload->>'nom' name,veh.payload->>'categorie' category from public.koki_records drv join public.koki_records veh on veh.parent_id=drv.id and veh.kind='vehicules' and veh.statut='Actif'
   where drv.kind='chauffeurs' and drv.statut='Disponible' and veh.payload->>'categorie'=input->>'category'
    and (drv.payload->>'position_updated_at')::timestamptz>now()-interval '15 minutes'
    and koki_private.business_point(drv.payload->'position') and koki_private.business_distance(input->'start',jsonb_build_object('latitude',round((drv.payload->'position'->>'latitude')::numeric/0.005)*0.005,'longitude',round((drv.payload->'position'->>'longitude')::numeric/0.005)*0.005))<=10 and drv.owner_id<>actor
    and not exists(select 1 from public.koki_records c where c.kind='courses' and c.driver_id=drv.id and c.statut in ('En attente','Acceptée','Chauffeur en route','Course en cours'))
    order by drv.id,veh.id limit 30)x),'[]'::jsonb);
 end if;
 -- Idempotence acteur/clé ; verrou avant toute mutation pour courses/commandes/reprises réseau.
 key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
 select * into cached from koki_private.business_keys k where k.actor_id=actor and k.request_id=key;
 if found then
  if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;
  if cached.output ? 'id' then
    select * into r from public.koki_records where public.koki_records.id=(cached.output->>'id')::uuid;
    if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès révoqué' using errcode='42501';end if;
  elsif command='set_rate' and not koki_private.allowed('transport') then raise exception 'Administration et MFA requises' using errcode='42501';end if;
  return cached.output;
 end if;
 if command in ('register_driver','register_professional') then
   perform koki_private.business_keys_allowed(input,array['request_id','name','phone','profile','description','zone']);
   phone:=koki_private.business_text(input,'phone',8,16);if phone!~'^\+[1-9][0-9]{7,14}$' then raise exception 'Téléphone international invalide';end if;
   entity_kind:=case when command='register_driver' then 'chauffeurs' else 'professionnels' end;
   if exists(select 1 from public.koki_records where owner_id=actor and public.koki_records.kind=entity_kind) then raise exception 'Profil déjà inscrit';end if;
   profile:=input->>'profile';if entity_kind='professionnels' and (profile is null or profile not in ('Commerçant','Prestataire de services','Les deux')) then raise exception 'Profil professionnel invalide';end if;
   insert into public.koki_records(kind,statut,owner_id,payload) values(entity_kind,'À valider',actor,jsonb_strip_nulls(jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'telephone',phone,'type',case when entity_kind='professionnels' then profile end,'description',left(coalesce(input->>'description',''),2000),'zone',left(coalesce(input->>'zone',''),180)))) returning * into r;
 elsif command='admin_review' then
   perform koki_private.business_keys_allowed(input,array['request_id','id','decision']);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind in ('professionnels','boutiques','produits','services') then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.id is null or r.kind not in ('chauffeurs','professionnels','vehicules','boutiques','produits','services') or not koki_private.allowed(case when r.kind in ('chauffeurs','vehicules') then 'transport' else 'commerce' end) then raise exception 'Administration autorisée et MFA requises' using errcode='42501';end if;
   next_status:=case input->>'decision' when 'approve' then case r.kind when 'chauffeurs' then 'Indisponible' when 'vehicules' then 'Actif' when 'produits' then 'Disponible' when 'services' then 'Disponible' else 'Actif' end when 'suspend' then case r.kind when 'vehicules' then 'Indisponible' when 'boutiques' then 'Fermé' when 'produits' then 'Masqué' when 'services' then 'Masqué' else 'Suspendu' end end;
   if next_status is null then raise exception 'Décision invalide';end if;
   update public.koki_records set statut=next_status where public.koki_records.id=r.id returning * into r;
 elsif command='set_rate' then
   perform koki_private.business_keys_allowed(input,array['request_id','category','base_fcfa','per_km_fcfa','active']);
   if not koki_private.allowed('transport') then raise exception 'Administration Transport et MFA requises' using errcode='42501';end if;
   if jsonb_typeof(input->'base_fcfa') is distinct from 'number' or jsonb_typeof(input->'per_km_fcfa') is distinct from 'number' or jsonb_typeof(input->'active') is distinct from 'boolean' or (input->>'base_fcfa')::numeric<>trunc((input->>'base_fcfa')::numeric) or (input->>'per_km_fcfa')::numeric<>trunc((input->>'per_km_fcfa')::numeric) then raise exception 'Tarif invalide';end if;
   insert into public.koki_transport_rates(category,base_fcfa,per_km_fcfa,active) values(input->>'category',(input->>'base_fcfa')::integer,(input->>'per_km_fcfa')::integer,(input->>'active')::boolean)
   on conflict(category) do update set base_fcfa=excluded.base_fcfa,per_km_fcfa=excluded.per_km_fcfa,active=excluded.active,updated_at=clock_timestamp() returning * into rate;
   insert into public.koki_audit(actor_id,operation,table_name,record_id,details) values(actor,'UPSERT','koki_transport_rates',gen_random_uuid(),jsonb_build_object('category',rate.category));
   outcome:=to_jsonb(rate);
 elsif command in ('save_vehicle','save_shop','save_product','save_service') then
   perform koki_private.business_keys_allowed(input,array['request_id','id','revision','parent_id','name','description','category','price','stock','registration','address','image_path']);
   entity_kind:=case command when 'save_vehicle' then 'vehicules' when 'save_shop' then 'boutiques' when 'save_product' then 'produits' else 'services' end;
   if entity_kind<>'vehicules' then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'parent_id')::uuid for update;
   if p.id is null or p.owner_id is distinct from actor then raise exception 'Propriétaire requis' using errcode='42501';end if;
   if entity_kind='vehicules' and (p.kind<>'chauffeurs' or p.statut not in ('Disponible','Indisponible','À valider')) then raise exception 'Chauffeur indisponible';end if;
   if entity_kind in ('boutiques','services') and (p.kind<>'professionnels' or p.statut<>'Actif' or p.payload->>'type' not in (case when entity_kind='boutiques' then 'Commerçant' else 'Prestataire de services' end,'Les deux')) then raise exception 'Profil professionnel incompatible';end if;
   if entity_kind='produits' then
     select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
     if p.kind<>'boutiques' or p.statut<>'Actif' or d.statut<>'Actif' or d.payload->>'type' not in ('Commerçant','Les deux') then raise exception 'Boutique indisponible';end if;
   end if;
   if entity_kind in ('produits','services') and input ? 'price' and input->'price'<>'null'::jsonb then
     if jsonb_typeof(input->'price') is distinct from 'number' or (input->>'price')::numeric<>trunc((input->>'price')::numeric) or (input->>'price')::numeric not between 0 and 1000000000 then raise exception 'Prix catalogue invalide';end if;
   elsif entity_kind='produits' then raise exception 'Prix produit obligatoire';end if;
   if entity_kind='produits' and (jsonb_typeof(input->'stock') is distinct from 'number' or (input->>'stock')::numeric<>trunc((input->>'stock')::numeric) or (input->>'stock')::numeric not between 0 and 1000000) then raise exception 'Stock invalide';end if;
   if entity_kind='vehicules' and (input->>'category' is null or input->>'category' is null or input->>'category' not in ('Moto','Taxi','Voiture','Minicar')) then raise exception 'Catégorie véhicule invalide';end if;
   if not coalesce(koki_private.business_owned_image(input->>'image_path'),false) then raise exception 'Média propriétaire invalide';end if;
   entity_id:=(input->>'id')::uuid;
   if entity_id is not null then select * into r from public.koki_records where public.koki_records.id=entity_id for update;
     if r.id is null or r.owner_id is distinct from actor or r.kind<>entity_kind or r.parent_id<>p.id then raise exception 'Élément inaccessible' using errcode='42501';end if;
     if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
     if entity_kind='vehicules' and exists(select 1 from public.koki_records active_course where active_course.kind='courses' and active_course.parent_id=r.id and active_course.statut in ('En attente','Acceptée','Chauffeur en route','Course en cours')) then raise exception 'Véhicule lié à une course active';end if;
   end if;
   pos:=jsonb_strip_nulls(jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'description',left(coalesce(input->>'description',''),2000),'categorie',input->>'category','prix',input->'price','stock',case when entity_kind='produits' then input->'stock' end,'immatriculation',input->>'registration','adresse',input->>'address','image_path',input->>'image_path'));
   next_status:=case entity_kind when 'vehicules' then 'Indisponible' when 'boutiques' then 'Actif' else 'Disponible' end;
   if entity_id is null then insert into public.koki_records(kind,statut,owner_id,parent_id,payload) values(entity_kind,next_status,actor,p.id,pos) returning * into r;
   else update public.koki_records set payload=pos,statut=case when entity_kind='vehicules' then 'Indisponible' else statut end where public.koki_records.id=entity_id returning * into r;end if;
 elsif command='driver_position' then
   perform koki_private.business_keys_allowed(input,array['request_id','position','available']);
   if not koki_private.business_point(input->'position') or jsonb_typeof(input->'available') is distinct from 'boolean' then raise exception 'Position/disponibilité invalide';end if;
   select * into r from public.koki_records where owner_id=actor and public.koki_records.kind='chauffeurs' for update;
   if r.id is null or r.statut not in ('Disponible','Indisponible') then raise exception 'Chauffeur validé requis' using errcode='42501';end if;
   update public.koki_records set statut=case when (input->>'available')::boolean then 'Disponible' else 'Indisponible' end,
   payload=payload||jsonb_build_object('position',jsonb_build_object('latitude',input->'position'->'latitude','longitude',input->'position'->'longitude'),'position_updated_at',clock_timestamp()) where public.koki_records.id=r.id returning * into r;
 elsif command='reserve_ride' then
   perform koki_private.business_keys_allowed(input,array['request_id','vehicle_id','quote_id']);
   -- Ordre uniforme : client puis chauffeur, véhicule, grille. L'index unique est une seconde barrière.
   perform pg_advisory_xact_lock(hashtextextended('ride-client:'||actor::text,0));
   select * into quote from koki_private.ride_quotes q where q.id=(input->>'quote_id')::uuid and q.client_id=actor for update;
   if quote.id is null or quote.expires_at<=now() or quote.ride_id is not null then raise exception 'Devis expiré ou indisponible';end if;
   select * into v from public.koki_records where public.koki_records.id=(input->>'vehicle_id')::uuid;
   if v.id is null or v.kind<>'vehicules' then raise exception 'Véhicule indisponible';end if;
   select * into d from public.koki_records where public.koki_records.id=v.parent_id for update;
   select * into v from public.koki_records where public.koki_records.id=v.id for update;
   if d.statut<>'Disponible' or v.statut<>'Actif' or (d.payload->>'position_updated_at')::timestamptz is null or (d.payload->>'position_updated_at')::timestamptz<now()-interval '15 minutes' then raise exception 'Chauffeur indisponible';end if;
   if not koki_private.business_point(d.payload->'position') or koki_private.business_distance(quote.start_point,d.payload->'position')>10 then raise exception 'Chauffeur hors proximité';end if;
   if exists(select 1 from public.koki_records where public.koki_records.kind='courses' and (driver_id=d.id or client_id=actor) and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours')) then raise exception 'Une course est déjà active';end if;
   if v.payload->>'categorie' is distinct from quote.category then raise exception 'Catégorie incompatible avec le devis';end if;
   select * into rate from public.koki_transport_rates where category=quote.category and active for share;
   if rate.category is null then raise exception 'Tarif validé indisponible';end if;
   insert into public.koki_records(kind,statut,client_id,parent_id,driver_id,payload) values('courses','En attente',actor,v.id,d.id,jsonb_build_object('nom','Course','depart',quote.start_point,'destination',quote.end_point,'distance',round(quote.distance_km,3),'tarif',quote.fare_fcfa,'categorie',quote.category,'methode','À vol d’oiseau')) returning * into r;
   update koki_private.ride_quotes set ride_id=r.id where koki_private.ride_quotes.id=quote.id;
 elsif command='create_order' then
   perform koki_private.business_keys_allowed(input,array['request_id','shop_id','items','mode','address']);
   if input->>'mode' is null or input->>'mode' not in ('retrait','livraison') then raise exception 'Réception invalide';end if;
   if input->>'mode'='livraison' then perform koki_private.business_text(input,'address',3,500);end if;
   items:=input->'items';if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 50 then raise exception 'Panier invalide';end if;
   if (select count(*) from jsonb_array_elements(items))<>(select count(distinct value->>'product_id') from jsonb_array_elements(items)) then raise exception 'Produits dupliqués';end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'shop_id')::uuid;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'shop_id')::uuid for update;
   select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
   if p.kind is distinct from 'boutiques' or p.statut<>'Actif' or d.kind is distinct from 'professionnels' or d.statut<>'Actif' or d.payload->>'type' not in ('Commerçant','Les deux') then raise exception 'Boutique indisponible';end if;
   -- Verrouillage déterministe. Toutes les lignes partagent une seule boutique ; panier multi-vendeur à séparer.
   for line in select value from jsonb_array_elements(items) order by value->>'product_id' loop
     perform koki_private.business_keys_allowed(line,array['product_id','quantity']);
     if jsonb_typeof(line->'quantity') is distinct from 'number' or (line->>'quantity')::numeric<>trunc((line->>'quantity')::numeric) or (line->>'quantity')::numeric not between 1 and 10000 then raise exception 'Quantité invalide';end if;qty:=(line->>'quantity')::integer;
     select * into r from public.koki_records where public.koki_records.id=(line->>'product_id')::uuid for update;
     if r.kind is distinct from 'produits' or r.parent_id<>p.id or r.statut<>'Disponible' or (r.payload->>'stock')::integer<qty then raise exception 'Produit indisponible ou stock insuffisant';end if;
     price:=(r.payload->>'prix')::bigint;if price is null or price<0 then raise exception 'Prix catalogue invalide';end if;
     total:=total+price*qty;
   end loop;
   insert into public.koki_records(kind,statut,client_id,parent_id,provider_id,payload) values('commandes','Commande reçue',actor,p.id,d.id,jsonb_build_object('nom','Commande','total',total,'mode',input->>'mode','adresse',case when input->>'mode'='livraison' then input->>'address' else null end,'currency','FCFA')) returning public.koki_records.id into entity_id;
   for line in select value from jsonb_array_elements(items) order by value->>'product_id' loop
     select * into r from public.koki_records where public.koki_records.id=(line->>'product_id')::uuid;qty:=(line->>'quantity')::integer;
     insert into public.koki_order_items(order_id,product_id,quantity,unit_price,product_name) values(entity_id,r.id,qty,(r.payload->>'prix')::bigint,r.payload->>'nom');
     update public.koki_records set payload=jsonb_set(payload,'{stock}',to_jsonb((payload->>'stock')::integer-qty)) where public.koki_records.id=r.id;
   end loop;
   select * into r from public.koki_records where public.koki_records.id=entity_id;
 elsif command='request_service' then
   perform koki_private.business_keys_allowed(input,array['request_id','service_id','need','address','date','image_path']);
   select * into p from public.koki_records where public.koki_records.id=(input->>'service_id')::uuid;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'service_id')::uuid for update;
   select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
   if p.kind is distinct from 'services' or p.statut<>'Disponible' or d.statut<>'Actif' or d.payload->>'type' not in ('Prestataire de services','Les deux') then raise exception 'Prestataire indisponible';end if;
   if not coalesce(koki_private.business_owned_image(input->>'image_path'),false) then raise exception 'Média propriétaire invalide';end if;
   if input->>'date' is null or input->>'date' !~ '^\d{4}-\d{2}-\d{2}$' or (input->>'date')::date is null or (input->>'date')::date<current_date then raise exception 'Date invalide';end if;
   insert into public.koki_records(kind,statut,client_id,parent_id,provider_id,payload) values('demandes_services','Demande envoyée',actor,p.id,d.id,jsonb_build_object('nom','Demande de devis','besoin',koki_private.business_text(input,'need',10,2000),'lieu',koki_private.business_text(input,'address',3,500),'date',(input->>'date')::date,'catalogue_price',p.payload->'prix','image_path',input->>'image_path')) returning * into r;
 elsif command in ('submit_service_quote','accept_service_quote') then
   perform koki_private.business_keys_allowed(input,case when command='submit_service_quote' then array['request_id','id','revision','amount_fcfa','description'] else array['request_id','id','revision'] end);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   select * into p from public.koki_records where public.koki_records.id=r.provider_id;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.kind is distinct from 'demandes_services' or r.statut<>'Demande envoyée' or (input->>'revision')::integer is distinct from r.revision then raise exception 'Demande ou révision indisponible';end if;
   if command='submit_service_quote' then
     if not coalesce(koki_private.owns_business(r.provider_id),false) and not koki_private.allowed('commerce') then raise exception 'Prestataire assigné requis' using errcode='42501';end if;
     if jsonb_typeof(input->'amount_fcfa') is distinct from 'number' or (input->>'amount_fcfa')::numeric not between 0 and 1000000000 or (input->>'amount_fcfa')::numeric<>trunc((input->>'amount_fcfa')::numeric) then raise exception 'Montant de devis invalide';end if;
     update public.koki_records set payload=payload||jsonb_build_object('quote_fcfa',(input->>'amount_fcfa')::bigint,'quote_text',koki_private.business_text(input,'description',1,2000),'quote_expires_at',now()+interval '7 days','quote_client_accepted',false) where public.koki_records.id=r.id returning * into r;
   else
     if r.client_id is distinct from actor then raise exception 'Client propriétaire requis' using errcode='42501';end if;
     if r.payload->>'quote_fcfa' is null or r.payload->>'quote_expires_at' is null or (r.payload->>'quote_expires_at')::timestamptz<=now() or not exists(select 1 from public.koki_records pro where pro.id=r.provider_id and pro.statut='Actif') then raise exception 'Devis expiré ou prestataire indisponible';end if;
     update public.koki_records set statut='Acceptée',payload=payload||jsonb_build_object('quote_client_accepted',true) where public.koki_records.id=r.id returning * into r;
   end if;
 elsif command='transition' then
   perform koki_private.business_keys_allowed(input,array['request_id','id','next','revision']);
   -- Verrouiller boutique/pro avant commande : ordre compatible avec create_order et restitution.
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind in ('commandes','demandes_services') then select * into p from public.koki_records where public.koki_records.id=r.provider_id;perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   if r.kind='commandes' then perform 1 from public.koki_records where public.koki_records.id=r.parent_id for update;perform 1 from public.koki_records where public.koki_records.id=r.provider_id for update;end if;
   if r.kind='courses' then select * into d from public.koki_records where public.koki_records.id=r.driver_id for update;end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.id is null or not coalesce(koki_private.business_can_read(r),false) or r.kind not in ('courses','commandes','demandes_services') then raise exception 'Accès refusé' using errcode='42501';end if;
   if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   next_status:=input->>'next';
   if next_status='Annulée' then
     if r.statut not in ('En attente','Acceptée','Commande reçue','Confirmée','Demande envoyée') then raise exception 'Annulation non autorisée à cette étape';end if;
     if r.client_id is distinct from actor and not coalesce(koki_private.owns_business(r.provider_id),false) and not coalesce(koki_private.owns_business(r.driver_id),false) and not koki_private.allowed(case when r.kind='courses' then 'transport' else 'commerce' end) then raise exception 'Annulation refusée' using errcode='42501';end if;
   else
     if r.kind='courses' then
       if not coalesce(koki_private.owns_business(r.driver_id),false) and not koki_private.allowed('transport') then raise exception 'Chauffeur assigné requis' using errcode='42501';end if;
       if next_status='Acceptée' and (d.statut<>'Disponible' or not exists(select 1 from public.koki_records accepted_vehicle where accepted_vehicle.id=r.parent_id and accepted_vehicle.statut='Actif')) then raise exception 'Chauffeur/véhicule indisponible';end if;
       steps:=array['En attente','Acceptée','Chauffeur en route','Course en cours','Terminée'];
     else
       if not coalesce(koki_private.owns_business(r.provider_id),false) and not koki_private.allowed('commerce') then raise exception 'Professionnel assigné requis' using errcode='42501';end if;
       if r.kind='demandes_services' and next_status='Acceptée' and (r.payload->>'quote_fcfa' is not null or r.payload->>'catalogue_price' is null) and not coalesce((r.payload->>'quote_client_accepted')::boolean,false) then raise exception 'Acceptation du devis par le client requise';end if;
       steps:=case when r.kind='commandes' then case when r.payload->>'mode'='retrait' then array['Commande reçue','Confirmée','Préparation','Prête au retrait','Retirée'] else array['Commande reçue','Confirmée','Préparation','En livraison','Livrée'] end else array['Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé'] end;
     end if;
     if next_status is null or next_status is distinct from steps[array_position(steps,r.statut)+1] then raise exception 'Transition invalide';end if;
   end if;
   if r.kind='commandes' and next_status='Annulée' then
     for line in select to_jsonb(i) from public.koki_order_items i where order_id=r.id order by product_id loop
       update public.koki_records set payload=jsonb_set(payload,'{stock}',to_jsonb((payload->>'stock')::integer+(line->>'quantity')::integer)) where public.koki_records.id=(line->>'product_id')::uuid;
     end loop;
   end if;
   update public.koki_records set statut=next_status where public.koki_records.id=r.id returning * into r;
 else raise exception 'Commande inconnue';
 end if;
 if outcome is null then outcome:=to_jsonb(r);end if;
 insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,outcome);
 return outcome;
end $$;
revoke all on function koki_private.business(text,jsonb) from public;
grant execute on function koki_private.business(text,jsonb) to anon,authenticated;
create function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select koki_private.business(command,input) $$;
revoke all on function public.koki_business(text,jsonb) from public;
grant execute on function public.koki_business(text,jsonb) to anon,authenticated;
-- anon ne possède que l'accès au wrapper : la commande catalog est la seule branche anonyme.
grant usage on schema koki_private to anon;
-- Photos privées de demandes et médias de catalogue vérifiés. Le bucket reste privé.
create function koki_private.business_public_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records media
 where media.payload->>'image_path'=path and (
 (media.kind='boutiques' and media.statut='Actif' and exists(select 1 from public.koki_records pro where pro.id=media.parent_id and pro.statut='Actif'))
 or (media.kind='services' and media.statut='Disponible' and exists(select 1 from public.koki_records pro where pro.id=media.parent_id and pro.statut='Actif'))
 or (media.kind='produits' and media.statut='Disponible' and exists(select 1 from public.koki_records shop join public.koki_records pro on pro.id=shop.parent_id where shop.id=media.parent_id and shop.statut='Actif' and pro.statut='Actif'))))
$$;
create function koki_private.business_participant_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records media where media.payload->>'image_path'=path and coalesce(koki_private.business_can_read(media),false))
$$;
create function koki_private.business_image_unreferenced(path text) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.koki_contents c where c.image_path=path) and not exists(select 1 from public.koki_records r where r.payload->>'image_path'=path)
$$;
revoke all on function koki_private.business_public_image(text),koki_private.business_participant_image(text),koki_private.business_image_unreferenced(text) from public;
grant execute on function koki_private.business_public_image(text) to anon,authenticated;
grant execute on function koki_private.business_participant_image(text),koki_private.business_image_unreferenced(text) to authenticated;
drop policy koki_media_read on storage.objects;
create policy editorial_admin_media_read on storage.objects for select to authenticated using(bucket_id='koki-media' and koki_private.allowed('read') and exists(select 1 from public.koki_contents editorial where editorial.image_path=name));
grant select on storage.objects to anon,authenticated;
create policy business_media_insert on storage.objects for insert to authenticated with check(bucket_id='koki-media' and (storage.foldername(name))[1]=auth.uid()::text and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false));
create policy business_media_owner_read on storage.objects for select to authenticated using(bucket_id='koki-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy business_media_public_read on storage.objects for select to anon,authenticated using(bucket_id='koki-media' and koki_private.business_public_image(name));
create policy business_media_participant_read on storage.objects for select to authenticated using(bucket_id='koki-media' and koki_private.business_participant_image(name));
create policy business_media_owner_delete on storage.objects for delete to authenticated using(bucket_id='koki-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy media_reference_guard on storage.objects as restrictive for delete to authenticated using(bucket_id<>'koki-media' or koki_private.business_image_unreferenced(name));
-- An inaccessible statistic remains unavailable rather than a misleading zero.
create or replace function public.koki_statistics() returns jsonb language plpgsql security invoker set search_path='' as $$ begin
if not koki_private.allowed('read') then raise exception 'Administration et MFA requises' using errcode='42501';end if;
return jsonb_build_object('Utilisateurs inscrits',(select count(*) from public.koki_users),'Utilisateurs actifs',null,'Actualités publiées',(select count(*) from public.koki_contents where type='Actualités' and statut='publié' and publication<=now()),'Annonces publiées',(select count(*) from public.koki_contents where type='Annonces' and statut='publié' and publication<=now()),'Publicités actives',(select count(*) from public.koki_contents where type='Publicités' and statut='publié' and actif and publication<=now() and (fin is null or fin>now())),'Commerces et prestataires',case when koki_private.allowed('commerce') then (select count(*) from public.koki_records where kind='professionnels') else null end,'Chauffeurs',case when koki_private.allowed('transport') then (select count(*) from public.koki_records where kind='chauffeurs') else null end,'Courses',case when koki_private.allowed('transport') then (select count(*) from public.koki_records where kind='courses') else null end,'Commandes',case when koki_private.allowed('commerce') then (select count(*) from public.koki_records where kind='commandes') else null end,'Demandes de services',case when koki_private.allowed('commerce') then (select count(*) from public.koki_records where kind='demandes_services') else null end,'Revenus FCFA',null,'Impressions publicitaires',null,'Clics publicitaires',null,'mesure_le',now());end $$;

-- SOURCE : supabase/proposals/merchant-profiles.sql · sha256 71a3f871af3dac3311a711f351adfd439f8279c4d5991d780654bacef55860d3
-- PROPOSITION LOCALE UNIQUEMENT. Après phase2-transactions.sql ; aucune application distante automatique.

alter table public.koki_records drop constraint koki_record_status;
alter table public.koki_records add constraint koki_record_status check(
(kind='professionnels' and statut in ('À valider','Actif','Suspendu','En attente','Refusé')) or
(kind='boutiques' and statut in ('À valider','Actif','Fermé')) or
(kind='produits' and statut in ('Disponible','Épuisé','Masqué')) or
(kind='services' and statut in ('Disponible','Indisponible','Masqué')) or
(kind='chauffeurs' and statut in ('À valider','Disponible','Indisponible','Suspendu')) or
(kind='vehicules' and statut in ('Actif','Indisponible')) or
(kind='commandes' and statut in ('Commande reçue','Confirmée','Préparation','En livraison','Livrée','Prête au retrait','Retirée','Annulée')) or
(kind='demandes_services' and statut in ('Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé','Annulée')) or
(kind='courses' and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours','Terminée','Annulée')));
create function koki_private.merchant_business(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();key uuid;cached koki_private.business_keys;r public.koki_records;photos jsonb;photo jsonb;phone text;data jsonb;result jsonb;item jsonb;output jsonb:='[]'::jsonb;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if command='catalog' then
   result:=koki_private.business(command,input);
   for item in select value from jsonb_array_elements(result) loop
     select * into r from public.koki_records where id=(item->>'id')::uuid;
     if r.kind='professionnels' then item:=item||jsonb_build_object('horaires',r.payload->>'horaires','localisation',r.payload->'localisation','adresse',r.payload->>'adresse','photos',coalesce(r.payload->'photos','[]'::jsonb),'type',r.payload->>'type');end if;
     output:=output||jsonb_build_array(item);
   end loop;
   return output;
 end if;
 -- L'ancien point d'entrée ne peut pas contourner la validation des nouvelles fiches.
 if command='admin_review' then
   select * into r from public.koki_records where id=(input->>'id')::uuid;
   if coalesce((r.payload->>'merchant_submission')::boolean,false) then command:='review_merchant';end if;
 end if;
 if command not in ('submit_merchant','review_merchant') then return koki_private.business(command,input);end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if command='review_merchant' and not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501';end if;
 perform koki_private.business_keys_allowed(input,case when command='submit_merchant' then array['request_id','id','revision','name','profile','category','phone','address','location','hours','description','photos'] else array['request_id','id','revision','decision'] end);
 key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
 select * into cached from koki_private.business_keys k where actor_id=actor and request_id=key;
 if found then
   if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;
   select * into r from public.koki_records where id=(cached.output->>'id')::uuid;
   if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès révoqué' using errcode='42501';end if;
   return cached.output;
 end if;
 if command='submit_merchant' then
   perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));
   select * into r from public.koki_records where owner_id=actor and kind='professionnels' for update;
   if r.id is not null and ((input->>'id')::uuid is distinct from r.id or (input->>'revision')::integer is distinct from r.revision) then raise exception 'Révision périmée : actualisez';end if;
   if r.id is null and input->>'id' is not null then raise exception 'Fiche inaccessible' using errcode='42501';end if;
   if r.statut='Suspendu' then raise exception 'Contactez l’administration pour votre fiche suspendue' using errcode='42501';end if;
   if input->>'profile' is null or input->>'profile' not in ('Commerçant','Les deux') then raise exception 'Profil commerçant requis';end if;
   if r.id is not null and r.payload->>'type'='Prestataire de services' and input->>'profile'<>'Les deux' then raise exception 'Conservez votre activité de services avec le profil Les deux';end if;
   phone:=koki_private.business_text(input,'phone',8,16);if phone!~'^\+[1-9][0-9]{7,14}$' then raise exception 'Téléphone WhatsApp international invalide';end if;
   if not koki_private.business_point(input->'location') then raise exception 'Localisation GPS invalide';end if;
   photos:=input->'photos';if jsonb_typeof(photos) is distinct from 'array' then raise exception 'Liste de photos requise';end if;
   if jsonb_array_length(photos)>5 then raise exception 'Cinq photos maximum';end if;
   if (select count(*) from jsonb_array_elements(photos))<>(select count(distinct value) from jsonb_array_elements(photos)) then raise exception 'Photos dupliquées';end if;
   for photo in select value from jsonb_array_elements(photos) loop
     if jsonb_typeof(photo)<>'string' or not coalesce(koki_private.business_owned_image(photo#>>'{}'),false) then raise exception 'Photo privée appartenant au commerçant requise';end if;
   end loop;
   data:=jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'type',input->>'profile','categorie',koki_private.business_text(input,'category',1,100),'telephone',phone,'adresse',koki_private.business_text(input,'address',3,500),'horaires',koki_private.business_text(input,'hours',3,500),'description',koki_private.business_text(input,'description',10,2000),'localisation',jsonb_build_object('latitude',input->'location'->'latitude','longitude',input->'location'->'longitude'),'photos',photos,'image_path',photos->>0,'merchant_submission',true);
   if r.id is null then insert into public.koki_records(kind,statut,owner_id,payload) values('professionnels','En attente',actor,data) returning * into r;
   else update public.koki_records set payload=payload||data,statut='En attente' where id=r.id returning * into r;end if;
 else
   select * into r from public.koki_records where id=(input->>'id')::uuid;
   perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));
   select * into r from public.koki_records where id=(input->>'id')::uuid for update;
   if r.kind is distinct from 'professionnels' or not coalesce((r.payload->>'merchant_submission')::boolean,false) then raise exception 'Fiche commerçant requise';end if;
   if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   if input->>'decision'='approve' and r.statut in ('En attente','Refusé','Suspendu') then update public.koki_records set statut='Actif' where id=r.id returning * into r;
   elsif input->>'decision'='reject' and r.statut='En attente' then update public.koki_records set statut='Refusé' where id=r.id returning * into r;
   elsif input->>'decision'='suspend' and r.statut='Actif' then update public.koki_records set statut='Suspendu' where id=r.id returning * into r;
   else raise exception 'Décision ou statut incompatible';end if;
 end if;
 result:=to_jsonb(r);
 insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,result);
 return result;
end $$;
revoke all on function koki_private.merchant_business(text,jsonb) from public;
grant execute on function koki_private.merchant_business(text,jsonb) to anon,authenticated;
-- La fonction historique reste disponible uniquement au routeur privilégié.
revoke execute on function koki_private.business(text,jsonb) from anon,authenticated;
create or replace function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select koki_private.merchant_business(command,input) $$;

create or replace function koki_private.business_public_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records media where (media.payload->>'image_path'=path or coalesce(media.payload->'photos','[]'::jsonb) ? path) and (
 (media.kind='professionnels' and media.statut='Actif')
 or (media.kind='boutiques' and media.statut='Actif' and exists(select 1 from public.koki_records pro where pro.id=media.parent_id and pro.statut='Actif'))
 or (media.kind='services' and media.statut='Disponible' and exists(select 1 from public.koki_records pro where pro.id=media.parent_id and pro.statut='Actif'))
 or (media.kind='produits' and media.statut='Disponible' and exists(select 1 from public.koki_records shop join public.koki_records pro on pro.id=shop.parent_id where shop.id=media.parent_id and shop.statut='Actif' and pro.statut='Actif'))))
$$;
create or replace function koki_private.business_participant_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records media where (media.payload->>'image_path'=path or coalesce(media.payload->'photos','[]'::jsonb) ? path) and coalesce(koki_private.business_can_read(media),false))
$$;
create or replace function koki_private.business_image_unreferenced(path text) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.koki_contents c where c.image_path=path) and not exists(select 1 from public.koki_records r where r.payload->>'image_path'=path or coalesce(r.payload->'photos','[]'::jsonb) ? path)
$$;

-- SOURCE : supabase/proposals/commerce-modernisation.sql · sha256 29a3276ed82dab09818b127bd66b97092aa864578b081ce7eb18ae6c06080173
-- PROPOSITION LOCALE UNIQUEMENT — Commerces & Services, phase 1. Après merchant-profiles.sql.
-- Aucune application distante automatique. Additive : aucune donnée supprimée ni réécrite.
-- Contrat partagé côté navigateur : src/commerce-contract.js (admin) = assets/business/commerce-contract.js (public).

-- 0. Préflight : rien n'est modifié si les données existantes ne sont pas compatibles.
do $$ begin
 if exists(select 1 from public.koki_records where kind in ('boutiques','produits','services') and parent_id is null) then
  raise exception 'Préflight commerce : boutiques, produits ou services sans fiche parente à rapprocher avant migration';
 end if;
 if exists(select 1 from public.koki_records where kind in ('boutiques','produits','services')
   group by parent_id,kind,lower(regexp_replace(btrim(payload->>'nom'),'\s+',' ','g')) having count(*)>1) then
  raise exception 'Préflight commerce : doublons de nom dans une même fiche ou boutique à corriger avant migration (aucune modification effectuée)';
 end if;
end $$;

-- 1. Statuts élargis (sur-ensemble strict des statuts actuels : toutes les lignes existantes restent valides).
alter table public.koki_records drop constraint koki_record_status;
alter table public.koki_records add constraint koki_record_status check(
(kind='professionnels' and statut in ('À valider','Actif','Suspendu','En attente','Refusé','Archivé')) or
(kind='boutiques' and statut in ('À valider','Actif','Fermé','Refusé','Archivé')) or
(kind='produits' and statut in ('Disponible','Épuisé','Masqué','Archivé')) or
(kind='services' and statut in ('Disponible','Indisponible','Masqué','Archivé')) or
(kind='chauffeurs' and statut in ('À valider','Disponible','Indisponible','Suspendu')) or
(kind='vehicules' and statut in ('Actif','Indisponible')) or
(kind='commandes' and statut in ('Commande reçue','Confirmée','Préparation','En livraison','Livrée','Prête au retrait','Retirée','Annulée')) or
(kind='demandes_services' and statut in ('Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé','Annulée')) or
(kind='courses' and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours','Terminée','Annulée')));

-- 2. Anti-doublon : même nom (minuscules, espaces réduits) interdit sous un même parent, hors éléments archivés.
create unique index koki_commerce_unique_name on public.koki_records(parent_id,kind,lower(regexp_replace(btrim(payload->>'nom'),'\s+',' ','g')))
 where kind in ('boutiques','produits','services') and statut<>'Archivé';

-- 3. Villages et quartiers : liste de référence lisible par tous, modifiable par l'administration Commerce.
create table public.koki_localites(
 id uuid primary key default gen_random_uuid(),
 nom text not null unique check(length(btrim(nom)) between 2 and 80),
 type text not null default 'À préciser' check(type in ('Village','Quartier','À préciser')),
 actif boolean not null default true,
 ordre integer not null default 0,
 source text not null default '' check(length(source)<=300),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.koki_localites enable row level security;
revoke all on public.koki_localites from anon,authenticated;
grant select on public.koki_localites to anon,authenticated;
grant insert,update on public.koki_localites to authenticated;
create policy localites_public_read on public.koki_localites for select to anon,authenticated using(actif or koki_private.allowed('read'));
create policy localites_admin_insert on public.koki_localites for insert to authenticated with check(koki_private.allowed('commerce'));
create policy localites_admin_update on public.koki_localites for update to authenticated using(koki_private.allowed('commerce')) with check(koki_private.allowed('commerce'));
-- Pas de suppression : une localité retirée passe à actif=false (les fiches existantes gardent leur texte).
insert into public.koki_localites(nom,ordre,source) values
 ('Bellel Ouolof',1,'OpenStreetMap'),('Coki',2,'OpenStreetMap'),('Kanène Khar',3,'OpenStreetMap'),('Keur Ngoura',4,'OpenStreetMap'),
 ('Loumène',5,'OpenStreetMap'),('Ndare Wakhy',6,'OpenStreetMap'),('Ndiobene Belal',7,'OpenStreetMap'),('Ouarak',8,'OpenStreetMap'),
 ('Pallene',9,'OpenStreetMap'),('Thiourour',10,'OpenStreetMap')
on conflict(nom) do nothing;

-- 4. Contrôles partagés.
create function koki_private.commerce_photos(input jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare photos jsonb;photo jsonb;
begin
 if input ? 'photos' then photos:=input->'photos';
 elsif input->>'image_path' is not null then photos:=jsonb_build_array(input->>'image_path');
 else photos:='[]'::jsonb;end if;
 if jsonb_typeof(photos) is distinct from 'array' then raise exception 'Liste de photos requise';end if;
 if jsonb_array_length(photos)>5 then raise exception 'Cinq photos maximum';end if;
 if (select count(*) from jsonb_array_elements(photos))<>(select count(distinct value) from jsonb_array_elements(photos)) then raise exception 'Photos dupliquées';end if;
 for photo in select value from jsonb_array_elements(photos) loop
  if jsonb_typeof(photo)<>'string' or not coalesce(koki_private.business_owned_image(photo#>>'{}'),false) then raise exception 'Photo privée appartenant au professionnel requise';end if;
 end loop;
 return photos;
end $$;
create function koki_private.commerce_phone(input jsonb,field text) returns text language plpgsql immutable set search_path='' as $$
declare v text:=btrim(input->>field);
begin
 if v is null or v='' then return null;end if;
 if jsonb_typeof(input->field)<>'string' or v!~'^\+[1-9][0-9]{7,14}$' or (v like '+221%' and v!~'^\+221[37][0-9]{8}$') then raise exception 'Numéro % invalide (format international, ex. +221771234567)',case when field='phone' then 'de téléphone' else 'WhatsApp' end;end if;
 return v;
end $$;
create function koki_private.commerce_village(input jsonb) returns text language plpgsql stable security definer set search_path='' as $$
declare v text:=btrim(input->>'village');
begin
 if v is null or v='' then return null;end if;
 if not exists(select 1 from public.koki_localites l where l.nom=v and l.actif) then raise exception 'Village ou quartier inconnu : choisissez-le dans la liste';end if;
 return v;
end $$;
create function koki_private.commerce_int(input jsonb,field text,maximum bigint,message text) returns bigint language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(input->field) is distinct from 'number' or (input->>field)::numeric<>trunc((input->>field)::numeric) or (input->>field)::numeric not between 0 and maximum then raise exception '%',message;end if;
 return (input->>field)::bigint;
end $$;
revoke all on function koki_private.commerce_photos(jsonb),koki_private.commerce_phone(jsonb,text),koki_private.commerce_village(jsonb),koki_private.commerce_int(jsonb,text,bigint,text) from public,anon,authenticated;

-- 5. Catalogue public enrichi (aucun identifiant de propriétaire ni donnée d'administration).
create function koki_private.commerce_catalog() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
  'id',x.id,'kind',x.kind,'parent_id',x.parent_id,'provider_id',x.provider_id,'statut',x.statut,
  'nom',x.payload->>'nom','description',x.payload->>'description','categorie',x.payload->>'categorie',
  'prix',x.payload->'prix','ancien_prix',x.payload->'ancien_prix','stock',x.payload->'stock','tarif',x.payload->>'tarif',
  'telephone',case when x.kind='professionnels' then x.payload->>'telephone' end,
  'whatsapp',case when x.kind in ('professionnels','boutiques') then x.payload->>'whatsapp' end,
  'type',case when x.kind='professionnels' then x.payload->>'type' end,
  'adresse',case when x.kind in ('professionnels','boutiques') then x.payload->>'adresse' end,
  'village',x.payload->>'village','zone',x.payload->>'zone','horaires',x.payload->>'horaires',
  'localisation',case when x.kind in ('professionnels','boutiques') then x.payload->'localisation' end,
  'photos',coalesce(x.payload->'photos',case when x.payload->>'image_path' is not null then jsonb_build_array(x.payload->>'image_path') end),
  'image_path',x.payload->>'image_path')) order by x.updated_at desc),'[]'::jsonb)
 from (select listing.* from public.koki_records listing where (listing.kind='professionnels' and listing.statut='Actif')
  or (listing.kind='boutiques' and listing.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
  or (listing.kind='services' and listing.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.statut='Actif'))
  or (listing.kind='produits' and listing.statut in ('Disponible','Épuisé') and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=listing.parent_id and b.statut='Actif' and prof.statut='Actif'))
  order by listing.updated_at desc limit 500) x
$$;
revoke all on function koki_private.commerce_catalog() from public,anon,authenticated;

-- Photos publiques : mêmes règles que le catalogue (produits épuisés visibles, éléments archivés jamais).
create or replace function koki_private.business_public_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records media where (media.payload->>'image_path'=path or coalesce(media.payload->'photos','[]'::jsonb) ? path) and (
 (media.kind='professionnels' and media.statut='Actif')
 or (media.kind='boutiques' and media.statut='Actif' and exists(select 1 from public.koki_records pro where pro.id=media.parent_id and pro.statut='Actif'))
 or (media.kind='services' and media.statut='Disponible' and exists(select 1 from public.koki_records pro where pro.id=media.parent_id and pro.statut='Actif'))
 or (media.kind='produits' and media.statut in ('Disponible','Épuisé') and exists(select 1 from public.koki_records shop join public.koki_records pro on pro.id=shop.parent_id where shop.id=media.parent_id and shop.statut='Actif' and pro.statut='Actif'))))
$$;


-- 5 bis. Photos : dossier anonyme par compte. Les chemins publiés ne révèlent plus l'identifiant du compte.
-- Les anciens chemins (dossier = identifiant du compte) restent valides.
create table koki_private.media_folders(user_id uuid primary key references auth.users(id) on delete restrict,folder uuid not null unique default gen_random_uuid(),created_at timestamptz not null default now());
alter table koki_private.media_folders enable row level security;
revoke all on koki_private.media_folders from public,anon,authenticated;
create function koki_private.my_media_folder() returns text language sql stable security definer set search_path='' as $$
 select f.folder::text from koki_private.media_folders f where f.user_id=auth.uid()
$$;
revoke all on function koki_private.my_media_folder() from public,anon;
grant execute on function koki_private.my_media_folder() to authenticated;
create policy business_media_alias_insert on storage.objects for insert to authenticated with check(bucket_id='koki-media' and (storage.foldername(name))[1]=koki_private.my_media_folder() and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false));
create policy business_media_alias_read on storage.objects for select to authenticated using(bucket_id='koki-media' and (storage.foldername(name))[1]=koki_private.my_media_folder());
create policy business_media_alias_delete on storage.objects for delete to authenticated using(bucket_id='koki-media' and (storage.foldername(name))[1]=koki_private.my_media_folder());
create or replace function koki_private.business_owned_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select path is null or ((path ~ ('^'||auth.uid()::text||'/[a-f0-9-]+\.(jpg|png|webp)$') or path ~ ('^'||coalesce(koki_private.my_media_folder(),'aucun-dossier')||'/[a-f0-9-]+\.(jpg|png|webp)$'))
  and exists(select 1 from storage.objects o where o.bucket_id='koki-media' and o.name=path))
$$;


-- Champs dont la modification exige une nouvelle validation (nom, activité, numéros, photos).
-- Pendant la revalidation, la version approuvée reste en ligne ; les nouvelles valeurs attendent dans payload.modification.
create function koki_private.commerce_sensibles(payload jsonb) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_strip_nulls(jsonb_build_object('nom',payload->'nom','type',payload->'type','telephone',payload->'telephone','whatsapp',payload->'whatsapp','photos',coalesce(payload->'photos','[]'::jsonb),'image_path',payload->'image_path'))
$$;
revoke all on function koki_private.commerce_sensibles(jsonb) from public,anon,authenticated;
-- Photos d'une modification en attente : visibles du propriétaire et de l'administration, jamais du public ; protégées contre la suppression.
create or replace function koki_private.business_participant_image(path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records media where (media.payload->>'image_path'=path or coalesce(media.payload->'photos','[]'::jsonb) ? path or coalesce(media.payload->'modification'->'photos','[]'::jsonb) ? path) and coalesce(koki_private.business_can_read(media),false))
$$;
create or replace function koki_private.business_image_unreferenced(path text) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.koki_contents c where c.image_path=path) and not exists(select 1 from public.koki_records r where r.payload->>'image_path'=path or coalesce(r.payload->'photos','[]'::jsonb) ? path or coalesce(r.payload->'modification'->'photos','[]'::jsonb) ? path)
$$;

-- 6. Routeur Commerces & Services. Les commandes non listées passent inchangées aux routeurs existants
--    (register_professional, submit_merchant, review_merchant, admin_review, commandes, transport…).
create function koki_private.commerce_business(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();key uuid;cached koki_private.business_keys;r public.koki_records;p public.koki_records;d public.koki_records;
 entity_kind text;entity_id uuid;data jsonb;sensitive jsonb;live jsonb;photos jsonb;result jsonb;next_status text;price bigint;old_price bigint;stock bigint;whatsapp text;decision text;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if command='catalog' then perform koki_private.business_keys_allowed(input,array[]::text[]);return koki_private.commerce_catalog();end if;
 if command='localites' then
  perform koki_private.business_keys_allowed(input,array[]::text[]);
  return coalesce((select jsonb_agg(jsonb_build_object('nom',l.nom,'type',l.type) order by l.ordre,l.nom) from public.koki_localites l where l.actif),'[]'::jsonb);
 end if;
 if command='admin_review' then
  -- Ancienne commande conservée ; pour produits/services, la suspension bloque aussi la remise en ligne par le propriétaire.
  select * into r from public.koki_records where id=(input->>'id')::uuid;
  result:=koki_private.merchant_business(command,input);
  if r.kind in ('produits','services') and input->>'decision' in ('approve','suspend') then
   update public.koki_records set payload=payload||jsonb_build_object('moderation_lock',input->>'decision'='suspend') where id=r.id;
  end if;
  return result;
 end if;
 if command='media_folder' then
  perform koki_private.business_keys_allowed(input,array[]::text[]);
  if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
  insert into koki_private.media_folders(user_id) values(actor) on conflict do nothing;
  return jsonb_build_object('folder',koki_private.my_media_folder());
 end if;
 if command not in ('review_changes','save_profile','save_shop','save_product','save_service','save_profile_details','set_availability','archive','moderate') then
  return koki_private.merchant_business(command,input);
 end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 perform koki_private.business_keys_allowed(input,case command
  when 'save_profile' then array['request_id','id','revision','name','profile','category','phone','whatsapp','village','address','hours','description','zone','location','photos']
  when 'save_shop' then array['request_id','id','revision','parent_id','name','description','address','village','hours','whatsapp','location','photos','image_path','category']
  when 'save_product' then array['request_id','id','revision','parent_id','name','description','category','price','old_price','stock','photos','image_path']
  when 'save_service' then array['request_id','id','revision','parent_id','name','description','category','price','pricing','zone','photos','image_path']
  when 'save_profile_details' then array['request_id','revision','whatsapp','village','zone','hours','location']
  when 'set_availability' then array['request_id','id','revision','status']
  when 'archive' then array['request_id','id','revision']
  when 'review_changes' then array['request_id','id','revision','decision','note']
  else array['request_id','id','revision','decision','note'] end);
 if command in ('moderate','review_changes') and not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501';end if;
 key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
 select * into cached from koki_private.business_keys k where k.actor_id=actor and k.request_id=key;
 if found then
  if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;
  select * into r from public.koki_records where id=(cached.output->>'id')::uuid;
  if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès révoqué' using errcode='42501';end if;
  return cached.output;
 end if;

 if command='save_profile' then
  -- Fiche professionnelle unifiée (commerçant, prestataire ou les deux) ; GPS facultatif.
  -- Les parcours register_professional et submit_merchant restent disponibles.
  perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));
  select * into r from public.koki_records where owner_id=actor and kind='professionnels' for update;
  if r.id is null and input->>'id' is not null then raise exception 'Fiche inaccessible' using errcode='42501';end if;
  if r.id is not null and input->>'id' is null then raise exception 'Fiche déjà créée : modifiez-la';end if;
  if r.id is not null and ((input->>'id')::uuid is distinct from r.id or (input->>'revision')::integer is distinct from r.revision) then raise exception 'Révision périmée : actualisez';end if;
  if r.statut in ('Suspendu','Archivé') then raise exception 'Contactez l’administration pour cette fiche' using errcode='42501';end if;
  if input->>'profile' is null or input->>'profile' not in ('Commerçant','Prestataire de services','Les deux') then raise exception 'Profil professionnel invalide';end if;
  if r.id is not null and input->>'profile'='Prestataire de services' and exists(select 1 from public.koki_records b where b.parent_id=r.id and b.kind='boutiques' and b.statut<>'Archivé') then raise exception 'Archivez vos boutiques avant de retirer l’activité commerce';end if;
  if r.id is not null and input->>'profile'='Commerçant' and exists(select 1 from public.koki_records v where v.parent_id=r.id and v.kind='services' and v.statut<>'Archivé') then raise exception 'Archivez vos services avant de retirer l’activité services';end if;
  if koki_private.commerce_phone(input,'phone') is null then raise exception 'Téléphone obligatoire';end if;
  if koki_private.commerce_village(input) is null then raise exception 'Choisissez votre village ou quartier';end if;
  photos:=koki_private.commerce_photos(input);
  data:=jsonb_strip_nulls(jsonb_build_object('nom',regexp_replace(koki_private.business_text(input,'name',1,180),'\s+',' ','g'),'type',input->>'profile',
   'categorie',koki_private.business_text(input,'category',1,100),'telephone',koki_private.commerce_phone(input,'phone'),'whatsapp',koki_private.commerce_phone(input,'whatsapp'),
   'village',koki_private.commerce_village(input),'adresse',case when input->>'address' is not null then koki_private.business_text(input,'address',3,500) end,
   'horaires',case when input->>'hours' is not null then koki_private.business_text(input,'hours',3,500) end,
   'description',left(coalesce(input->>'description',''),2000),'zone',case when input->>'zone' is not null then koki_private.business_text(input,'zone',2,180) end,
   'photos',photos,'image_path',photos->>0,'fiche_v2',true));
  if input ? 'location' and input->'location'<>'null'::jsonb then
   if not koki_private.business_point(input->'location') then raise exception 'Localisation GPS invalide';end if;
   data:=data||jsonb_build_object('localisation',jsonb_build_object('latitude',input->'location'->'latitude','longitude',input->'location'->'longitude'));
  end if;
  if r.id is null then
   insert into public.koki_records(kind,statut,owner_id,payload) values('professionnels','En attente',actor,data) returning * into r;
  else
   -- Nom, activité, numéros ou photos modifiés sur une fiche approuvée : nouvelle validation. Une fiche refusée corrigée repart en validation.
   sensitive:=koki_private.commerce_sensibles(data);live:=koki_private.commerce_sensibles(r.payload);
   if r.statut='Actif' then
    -- Fiche en ligne : horaires, village, adresse, description, catégorie et GPS appliqués tout de suite ;
    -- nom, activité, numéros et photos attendent la validation, la version approuvée reste affichée.
    update public.koki_records set payload=(payload-'adresse'-'horaires'-'zone'-'localisation'-'description'-'modification')
      ||(data-'nom'-'type'-'telephone'-'whatsapp'-'photos'-'image_path')
      ||case when sensitive<>live then jsonb_build_object('modification',sensitive||jsonb_build_object('soumis_le',clock_timestamp())) else '{}'::jsonb end
     where id=r.id returning * into r;
   else
    -- Fiche pas encore en ligne : tout est remplacé ; une fiche refusée corrigée repart en validation.
    update public.koki_records set payload=(payload-'adresse'-'horaires'-'zone'-'localisation'-'whatsapp'-'description'-'modification')||data,
     statut=case when r.statut='Refusé' then 'En attente' else r.statut end where id=r.id returning * into r;
   end if;
  end if;

 elsif command in ('save_shop','save_product','save_service') then
  entity_kind:=case command when 'save_shop' then 'boutiques' when 'save_product' then 'produits' else 'services' end;
  perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));
  -- Parent déduit du compte : le professionnel ne saisit jamais d'identifiant technique.
  if input->>'parent_id' is not null then select * into p from public.koki_records where id=(input->>'parent_id')::uuid for update;
  elsif entity_kind in ('boutiques','services') then select * into p from public.koki_records where owner_id=actor and kind='professionnels' for update;
  else
   if (select count(*) from public.koki_records b where b.owner_id=actor and b.kind='boutiques' and b.statut<>'Archivé')<>1 then raise exception 'Choisissez la boutique du produit';end if;
   select * into p from public.koki_records b where b.owner_id=actor and b.kind='boutiques' and b.statut<>'Archivé' for update;
  end if;
  if p.id is null or p.owner_id is distinct from actor then raise exception 'Propriétaire requis' using errcode='42501';end if;
  if entity_kind in ('boutiques','services') and (p.kind<>'professionnels' or p.statut<>'Actif' or p.payload->>'type' not in (case when entity_kind='boutiques' then 'Commerçant' else 'Prestataire de services' end,'Les deux')) then raise exception 'Profil professionnel incompatible ou fiche non approuvée';end if;
  if entity_kind='produits' then
   select * into d from public.koki_records where id=p.parent_id for update;
   if p.kind<>'boutiques' or p.statut<>'Actif' or d.statut<>'Actif' or d.payload->>'type' not in ('Commerçant','Les deux') then raise exception 'Boutique indisponible : validation par l’administration requise';end if;
  end if;
  photos:=koki_private.commerce_photos(input);
  data:=jsonb_build_object('nom',regexp_replace(koki_private.business_text(input,'name',1,180),'\s+',' ','g'),'description',left(coalesce(input->>'description',''),2000),'photos',photos,'image_path',photos->>0);
  if input ? 'category' and input->'category'<>'null'::jsonb then data:=data||jsonb_build_object('categorie',koki_private.business_text(input,'category',1,100));end if;
  if entity_kind='boutiques' then
   data:=data||jsonb_strip_nulls(jsonb_build_object('adresse',case when input->>'address' is not null then koki_private.business_text(input,'address',3,500) end,'village',koki_private.commerce_village(input),
    'horaires',case when input->>'hours' is not null then koki_private.business_text(input,'hours',3,500) end,'whatsapp',koki_private.commerce_phone(input,'whatsapp')));
   if input ? 'location' and input->'location'<>'null'::jsonb then
    if not koki_private.business_point(input->'location') then raise exception 'Localisation GPS invalide';end if;
    data:=data||jsonb_build_object('localisation',jsonb_build_object('latitude',input->'location'->'latitude','longitude',input->'location'->'longitude'));
   end if;
  elsif entity_kind='produits' then
   if input->'price' is null or input->'price'='null'::jsonb then raise exception 'Prix produit obligatoire';end if;
   price:=koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide');stock:=koki_private.commerce_int(input,'stock',1000000,'Stock invalide');
   if input ? 'old_price' and input->'old_price'<>'null'::jsonb then old_price:=koki_private.commerce_int(input,'old_price',1000000000,'Ancien prix invalide');
    if old_price<=price then raise exception 'L’ancien prix doit être supérieur au prix actuel';end if;end if;
   data:=data||jsonb_strip_nulls(jsonb_build_object('prix',price,'stock',stock,'ancien_prix',old_price));
  else
   if coalesce(input->>'pricing',case when input->'price' is null or input->'price'='null'::jsonb then 'devis' else 'fixe' end) not in ('fixe','devis') then raise exception 'Tarif fixe ou sur devis requis';end if;
   if coalesce(input->>'pricing',case when input->'price' is null or input->'price'='null'::jsonb then 'devis' else 'fixe' end)='fixe' then
    data:=data||jsonb_build_object('tarif','fixe','prix',koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide'));
   else
    if input->'price' is not null and input->'price'<>'null'::jsonb then raise exception 'Tarif sur devis : pas de prix';end if;
    data:=data||jsonb_build_object('tarif','devis');
   end if;
   if input->>'zone' is not null then data:=data||jsonb_build_object('zone',koki_private.business_text(input,'zone',2,180));end if;
  end if;
  entity_id:=(input->>'id')::uuid;
  if entity_id is null then
   next_status:=case entity_kind when 'boutiques' then 'À valider' when 'produits' then case when stock=0 then 'Épuisé' else 'Disponible' end else 'Disponible' end;
   begin
    insert into public.koki_records(kind,statut,owner_id,parent_id,payload) values(entity_kind,next_status,actor,p.id,data) returning * into r;
   exception when unique_violation then raise exception 'Un élément du même nom existe déjà ici';
   end;
  else
   select * into r from public.koki_records where id=entity_id for update;
   if r.id is null or r.owner_id is distinct from actor or r.kind<>entity_kind or r.parent_id<>p.id then raise exception 'Élément inaccessible' using errcode='42501';end if;
   if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   if r.statut='Archivé' then raise exception 'Élément archivé : non modifiable';end if;
   if r.statut='Fermé' then raise exception 'Boutique suspendue : contactez l’administration' using errcode='42501';end if;
   next_status:=case
    when entity_kind='boutiques' and r.statut='Refusé' then 'À valider'
    when entity_kind='produits' and r.statut='Disponible' and stock=0 then 'Épuisé'
    when entity_kind='produits' and r.statut='Épuisé' and stock>0 then 'Disponible'
    else r.statut end;
   begin
    update public.koki_records set payload=(payload-'ancien_prix'-'zone'-'prix'-'localisation'-'horaires'-'whatsapp')||data,statut=next_status where id=r.id returning * into r;
   exception when unique_violation then raise exception 'Un élément du même nom existe déjà ici';
   end;
  end if;

 elsif command='save_profile_details' then
  perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));
  select * into r from public.koki_records where owner_id=actor and kind='professionnels' for update;
  if r.id is null then raise exception 'Fiche professionnelle requise';end if;
  if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
  if r.statut in ('Suspendu','Archivé') then raise exception 'Contactez l’administration pour cette fiche' using errcode='42501';end if;
  whatsapp:=koki_private.commerce_phone(input,'whatsapp');
  data:=jsonb_strip_nulls(jsonb_build_object('whatsapp',whatsapp,'village',koki_private.commerce_village(input),
   'zone',case when input->>'zone' is not null then koki_private.business_text(input,'zone',2,180) end,
   'horaires',case when input->>'hours' is not null then koki_private.business_text(input,'hours',3,500) end));
  if input ? 'location' and input->'location'<>'null'::jsonb then
   if not koki_private.business_point(input->'location') then raise exception 'Localisation GPS invalide';end if;
   data:=data||jsonb_build_object('localisation',jsonb_build_object('latitude',input->'location'->'latitude','longitude',input->'location'->'longitude'));
  end if;
  if r.statut='Actif' then
   -- Nouveau WhatsApp d'une fiche en ligne : en attente de validation, l'ancien numéro reste affiché.
   live:=koki_private.commerce_sensibles(r.payload);
   sensitive:=(coalesce(r.payload->'modification',live)-'soumis_le'-'whatsapp')||jsonb_strip_nulls(jsonb_build_object('whatsapp',whatsapp));
   update public.koki_records set payload=(payload-'village'-'zone'-'localisation'-'modification')||(data-'whatsapp')
     ||case when sensitive<>live then jsonb_build_object('modification',sensitive||jsonb_build_object('soumis_le',clock_timestamp())) else '{}'::jsonb end
    where id=r.id returning * into r;
  else
   -- Fiche refusée corrigée : nouvelle validation.
   next_status:=case when r.statut='Refusé' then case when coalesce((r.payload->>'merchant_submission')::boolean,false) then 'En attente' else 'À valider' end else r.statut end;
   update public.koki_records set payload=(payload-'whatsapp'-'village'-'zone'-'localisation')||data,statut=next_status where id=r.id returning * into r;
  end if;

 elsif command in ('set_availability','archive') then
  perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));
  select * into r from public.koki_records where id=(input->>'id')::uuid for update;
  if r.id is null or r.owner_id is distinct from actor or r.kind not in ('boutiques','produits','services') or (command='set_availability' and r.kind='boutiques') then raise exception 'Élément inaccessible' using errcode='42501';end if;
  if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
  if r.statut='Archivé' then raise exception 'Élément déjà archivé';end if;
  if command='archive' then update public.koki_records set statut='Archivé' where id=r.id returning * into r;
  else
   if coalesce((r.payload->>'moderation_lock')::boolean,false) then raise exception 'Élément suspendu par l’administration' using errcode='42501';end if;
   if input->>'status' is null or not (input->>'status' = any(case when r.kind='produits' then array['Disponible','Épuisé','Masqué'] else array['Disponible','Indisponible','Masqué'] end)) then raise exception 'Disponibilité invalide';end if;
   update public.koki_records set statut=input->>'status' where id=r.id returning * into r;
  end if;

 elsif command='review_changes' then
  -- Modifications en attente d'une fiche en ligne : appliquées ou écartées ; le statut ne change pas.
  select * into r from public.koki_records where id=(input->>'id')::uuid;
  if r.id is null or r.kind<>'professionnels' or not r.payload ? 'modification' then raise exception 'Aucune modification en attente';end if;
  perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));
  select * into r from public.koki_records where id=r.id for update;
  if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
  if input->>'decision' not in ('approve','reject') then raise exception 'Décision invalide';end if;
  if input->>'note' is not null and (jsonb_typeof(input->'note')<>'string' or length(input->>'note')>500) then raise exception 'Motif trop long (500 caractères maximum)';end if;
  update public.koki_records set payload=case when input->>'decision'='approve'
    then (payload-'nom'-'type'-'telephone'-'whatsapp'-'photos'-'image_path'-'modification')||((payload->'modification')-'soumis_le')
    else payload-'modification' end
   ||jsonb_build_object('moderation',jsonb_strip_nulls(jsonb_build_object('decision',case when input->>'decision'='approve' then 'approve_changes' else 'reject_changes' end,'note',nullif(btrim(input->>'note'),''),'at',clock_timestamp())))
   where id=r.id returning * into r;

 else -- moderate : décision de l'administration, sur une révision précise.
  select * into r from public.koki_records where id=(input->>'id')::uuid;
  if r.id is null or r.kind not in ('professionnels','boutiques','produits','services') then raise exception 'Fiche commerce introuvable';end if;
  perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));
  select * into r from public.koki_records where id=r.id for update;
  if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
  decision:=input->>'decision';
  next_status:=case r.kind
   when 'professionnels' then case
    when decision='approve' and r.statut in ('À valider','En attente','Refusé','Suspendu','Archivé') then 'Actif'
    when decision='reject' and r.statut in ('À valider','En attente') then 'Refusé'
    when decision='suspend' and r.statut='Actif' then 'Suspendu'
    when decision='archive' and r.statut<>'Archivé' then 'Archivé' end
   when 'boutiques' then case
    when decision='approve' and r.statut in ('À valider','Refusé','Fermé','Archivé') then 'Actif'
    when decision='reject' and r.statut='À valider' then 'Refusé'
    when decision='suspend' and r.statut='Actif' then 'Fermé'
    when decision='archive' and r.statut<>'Archivé' then 'Archivé' end
   else case
    when decision='approve' and r.statut in ('Masqué','Archivé') then 'Disponible'
    when decision='suspend' and r.statut<>'Archivé' then 'Masqué'
    when decision='archive' and r.statut<>'Archivé' then 'Archivé' end end;
  if next_status is null then raise exception 'Décision ou statut incompatible';end if;
  if input->>'note' is not null and (jsonb_typeof(input->'note')<>'string' or length(input->>'note')>500) then raise exception 'Motif trop long (500 caractères maximum)';end if;
  begin
   update public.koki_records set statut=next_status,payload=payload||jsonb_build_object('moderation',jsonb_strip_nulls(jsonb_build_object('decision',decision,'note',nullif(btrim(input->>'note'),''),'at',clock_timestamp())))
    ||case when r.kind in ('produits','services') then jsonb_build_object('moderation_lock',decision='suspend') else '{}'::jsonb end
   where id=r.id returning * into r;
  exception when unique_violation then raise exception 'Un élément actif porte déjà ce nom : renommez-le avant de le rétablir';
  end;
 end if;

 result:=to_jsonb(r);
 insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,result);
 return result;
end $$;
revoke all on function koki_private.commerce_business(text,jsonb) from public;
grant execute on function koki_private.commerce_business(text,jsonb) to anon,authenticated;
-- Les routeurs précédents ne restent accessibles qu'au travers de ce routeur.
revoke execute on function koki_private.merchant_business(text,jsonb) from anon,authenticated;
create or replace function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select koki_private.commerce_business(command,input) $$;

-- Défense en profondeur (audit phase 5) : tables internes protégées par RLS (aucune politique : seules les fonctions serveur y accèdent).
alter table koki_private.ride_quotes enable row level security;
alter table koki_private.business_keys enable row level security;

-- 7. Administration Commerces & Services (phase 4) : garde-fous des décisions, historique, statistiques,
--    file de validation, liste et correction des fiches, compatibilité de l'ancien formulaire commerçant.
-- Chaîne parente publiée : aucun élément rattaché à une fiche non approuvée ne peut être rétabli.
create function koki_private.commerce_parent_actif(r public.koki_records) returns boolean language sql stable security definer set search_path='' as $$
 select case r.kind
  when 'boutiques' then exists(select 1 from public.koki_records pro where pro.id=r.parent_id and pro.kind='professionnels' and pro.statut='Actif')
  when 'services' then exists(select 1 from public.koki_records pro where pro.id=r.parent_id and pro.kind='professionnels' and pro.statut='Actif')
  when 'produits' then exists(select 1 from public.koki_records b join public.koki_records pro on pro.id=b.parent_id where b.id=r.parent_id and b.statut='Actif' and pro.statut='Actif')
  else true end
$$;
-- Produit publié = même règle que le catalogue public.
create function koki_private.commerce_publie(r public.koki_records) returns boolean language sql stable security definer set search_path='' as $$
 select case r.kind when 'professionnels' then r.statut='Actif' when 'boutiques' then r.statut='Actif' and koki_private.commerce_parent_actif(r)
  when 'services' then r.statut='Disponible' and koki_private.commerce_parent_actif(r) when 'produits' then r.statut in ('Disponible','Épuisé') and koki_private.commerce_parent_actif(r) else false end
$$;
revoke all on function koki_private.commerce_parent_actif(public.koki_records),koki_private.commerce_publie(public.koki_records) from public,anon,authenticated;
-- Vue d'administration d'une fiche : aucun identifiant de compte ; noms des fiches parentes ; historique des décisions.
create function koki_private.commerce_admin_view(r public.koki_records) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',r.id,'kind',r.kind,'statut',r.statut,'revision',r.revision,'payload',r.payload-'merchant_submission'-'fiche_v2','created_at',r.created_at,'updated_at',r.updated_at,
  'publie',koki_private.commerce_publie(r),'parent_id',r.parent_id,
  'parent',(select jsonb_build_object('nom',p.payload->>'nom','statut',p.statut,'kind',p.kind) from public.koki_records p where p.id=r.parent_id),
  'professionnel',(select jsonb_build_object('nom',pro.payload->>'nom','statut',pro.statut,'telephone',pro.payload->>'telephone') from public.koki_records pro where pro.kind='professionnels' and pro.owner_id=r.owner_id),
  'decisions',coalesce((select jsonb_agg(jsonb_build_object('at',a.created_at,'decision',a.details->>'decision','note',a.details->>'note','avant',a.details->>'avant','apres',a.details->>'apres') order by a.created_at desc) from (select * from public.koki_audit a where a.record_id=r.id and a.operation in ('DECISION','CORRECTION') order by a.created_at desc limit 10) a),'[]'::jsonb))
$$;
revoke all on function koki_private.commerce_admin_view(public.koki_records) from public,anon,authenticated;

create function koki_private.commerce_admin(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();r public.koki_records;p public.koki_records;result jsonb;avant text;key uuid;cached koki_private.business_keys;data jsonb;sensitive jsonb;live jsonb;photos jsonb;phone text;
 changes text[]:='{}';price bigint;old_price bigint;stock bigint;q text;total integer;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse';end if;
 -- Statistiques réelles (comptages seulement), lecture administrative avec double authentification.
 if command='admin_stats' then
  perform koki_private.business_keys_allowed(input,array[]::text[]);
  if not koki_private.allowed('read') then raise exception 'Administration et MFA requises' using errcode='42501';end if;
  return (select jsonb_build_object(
   'professionnels_inscrits',count(*) filter(where x.kind='professionnels'),
   'inscriptions_en_attente',count(*) filter(where x.kind='professionnels' and x.statut in ('À valider','En attente')),
   'boutiques_en_attente',count(*) filter(where x.kind='boutiques' and x.statut='À valider'),
   'modifications_en_attente',count(*) filter(where x.kind='professionnels' and x.payload ? 'modification'),
   'boutiques_actives',count(*) filter(where x.kind='boutiques' and x.statut='Actif'),
   'produits_publies',count(*) filter(where x.kind='produits' and koki_private.commerce_publie(x)),
   'services_disponibles',count(*) filter(where x.kind='services' and koki_private.commerce_publie(x)),
   'suspendus',count(*) filter(where (x.kind in ('professionnels') and x.statut='Suspendu') or (x.kind='boutiques' and x.statut='Fermé') or (x.kind in ('produits','services') and coalesce((x.payload->>'moderation_lock')::boolean,false) and x.statut<>'Archivé')),
   'archives',count(*) filter(where x.statut='Archivé'),
   'mesure_le',now()) from public.koki_records x where x.kind in ('professionnels','boutiques','produits','services'));
 end if;
 if command in ('admin_queue','admin_records','admin_update') and not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501';end if;
 -- File de validation : nouvelles inscriptions, nouvelles boutiques, modifications de fiches en ligne (les plus anciennes d'abord).
 if command='admin_queue' then
  perform koki_private.business_keys_allowed(input,array[]::text[]);
  return coalesce((select jsonb_agg(koki_private.commerce_admin_view(x)||jsonb_build_object('demande',case when x.kind='boutiques' then 'boutique' when x.payload ? 'modification' and x.statut='Actif' then 'modification' else 'inscription' end) order by coalesce((x.payload->'modification'->>'soumis_le')::timestamptz,x.updated_at))
   from public.koki_records x where (x.kind='professionnels' and (x.statut in ('À valider','En attente') or (x.statut='Actif' and x.payload ? 'modification'))) or (x.kind='boutiques' and x.statut='À valider')),'[]'::jsonb);
 end if;
 -- Liste d'une rubrique : recherche (nom, catégorie, village), filtre de statut, 50 par page.
 if command='admin_records' then
  perform koki_private.business_keys_allowed(input,array['kind','statut','query','village','offset','parent_id']);
  if input->>'kind' is null or input->>'kind' not in ('professionnels','boutiques','produits','services') then raise exception 'Rubrique invalide';end if;
  q:='%'||lower(coalesce(btrim(input->>'query'),''))||'%';
  select count(*) into total from public.koki_records x where x.kind=input->>'kind' and (input->>'statut' is null or x.statut=input->>'statut' or (input->>'statut'='Modification en attente' and x.payload ? 'modification'))
   and (input->>'village' is null or x.payload->>'village'=input->>'village') and (input->>'parent_id' is null or x.parent_id=(input->>'parent_id')::uuid) and lower(concat_ws(' ',x.payload->>'nom',x.payload->>'categorie',x.payload->>'village',x.payload->>'zone')) like q;
  return jsonb_build_object('total',total,'rows',coalesce((select jsonb_agg(koki_private.commerce_admin_view(x) order by x.updated_at desc) from (select * from public.koki_records x where x.kind=input->>'kind'
   and (input->>'statut' is null or x.statut=input->>'statut' or (input->>'statut'='Modification en attente' and x.payload ? 'modification'))
   and (input->>'village' is null or x.payload->>'village'=input->>'village') and (input->>'parent_id' is null or x.parent_id=(input->>'parent_id')::uuid) and lower(concat_ws(' ',x.payload->>'nom',x.payload->>'categorie',x.payload->>'village',x.payload->>'zone')) like q
   order by x.updated_at desc limit 50 offset greatest(0,least(coalesce((input->>'offset')::integer,0),100000))) x),'[]'::jsonb));
 end if;
 -- Garde-fous communs aux décisions et corrections.
 if command in ('moderate','review_changes','admin_review','review_merchant','admin_update') then
  if command in ('moderate','review_changes') and not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501';end if;
  select * into r from public.koki_records where id=(input->>'id')::uuid;
  if r.id is not null and r.owner_id=actor then raise exception 'Vous ne pouvez pas valider ni corriger vos propres fiches';end if;
  if r.id is not null and command in ('moderate','admin_review','review_merchant') and input->>'decision'='approve' and not koki_private.commerce_parent_actif(r) then
   raise exception 'Fiche parente non approuvée : validez d’abord la fiche professionnelle et la boutique';end if;
  avant:=r.statut;
 end if;
 -- Correction d'une fiche par l'administration (champs autorisés, parent choisi dans la liste du même professionnel).
 if command='admin_update' then
  perform koki_private.business_keys_allowed(input,array['request_id','id','revision','name','description','category','village','address','hours','zone','price','old_price','stock','pricing','phone','whatsapp','photos']);
  if r.id is null or r.kind not in ('professionnels','boutiques','produits','services') then raise exception 'Fiche commerce introuvable';end if;
  key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
  select * into cached from koki_private.business_keys k where k.actor_id=actor and k.request_id=key;
  if found then if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;return cached.output;end if;
  perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));
  select * into r from public.koki_records where id=r.id for update;
  if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
  data:='{}'::jsonb;
  if input ? 'name' then data:=data||jsonb_build_object('nom',regexp_replace(koki_private.business_text(input,'name',1,180),'\s+',' ','g'));end if;
  if input ? 'description' then data:=data||jsonb_build_object('description',left(coalesce(input->>'description',''),2000));end if;
  if input ? 'category' then data:=data||jsonb_build_object('categorie',koki_private.business_text(input,'category',1,100));end if;
  if input ? 'village' then if r.kind in ('produits','services') then raise exception 'Village : à corriger sur la boutique ou la fiche';end if;data:=data||jsonb_build_object('village',koki_private.commerce_village(input));end if;
  if input ? 'address' then data:=data||jsonb_build_object('adresse',koki_private.business_text(input,'address',3,500));end if;
  if input ? 'hours' then data:=data||jsonb_build_object('horaires',koki_private.business_text(input,'hours',3,500));end if;
  if input ? 'zone' then data:=data||jsonb_build_object('zone',koki_private.business_text(input,'zone',2,180));end if;
  if input ? 'phone' then if r.kind<>'professionnels' then raise exception 'Téléphone : champ de la fiche professionnelle';end if;phone:=koki_private.commerce_phone(input,'phone');if phone is null then raise exception 'Téléphone obligatoire';end if;data:=data||jsonb_build_object('telephone',phone);end if;
  if input ? 'whatsapp' then if r.kind not in ('professionnels','boutiques') then raise exception 'WhatsApp : champ de la fiche ou de la boutique';end if;data:=data||jsonb_build_object('whatsapp',koki_private.commerce_phone(input,'whatsapp'));end if;
  if r.kind='produits' and (input ? 'price' or input ? 'stock' or input ? 'old_price') then
   price:=case when input ? 'price' then koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide') else (r.payload->>'prix')::bigint end;
   stock:=case when input ? 'stock' then koki_private.commerce_int(input,'stock',1000000,'Stock invalide') else (r.payload->>'stock')::bigint end;
   old_price:=case when input ? 'old_price' and input->'old_price'<>'null'::jsonb then koki_private.commerce_int(input,'old_price',1000000000,'Ancien prix invalide') when input ? 'old_price' then null else (r.payload->>'ancien_prix')::bigint end;
   if old_price is not null and old_price<=price then raise exception 'L’ancien prix doit être supérieur au prix actuel';end if;
   data:=data||jsonb_build_object('prix',price,'stock',stock,'ancien_prix',old_price);
  elsif r.kind='services' and (input ? 'pricing' or input ? 'price') then
   if coalesce(input->>'pricing',r.payload->>'tarif','fixe')='devis' then data:=data||jsonb_build_object('tarif','devis','prix',null);
   else data:=data||jsonb_build_object('tarif','fixe','prix',koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide'));end if;
  elsif input ? 'price' or input ? 'stock' or input ? 'old_price' or input ? 'pricing' then raise exception 'Prix et stock : produits et services uniquement';
  end if;
  if input ? 'photos' then
   if jsonb_typeof(input->'photos') is distinct from 'array' or jsonb_array_length(input->'photos')>5 or exists(select 1 from jsonb_array_elements_text(input->'photos') ph where not (coalesce(r.payload->'photos','[]'::jsonb) ? ph or coalesce(r.payload->>'image_path'=ph,false))) then raise exception 'Photos : conserver, retirer ou réordonner uniquement les photos existantes';end if;
   data:=data||jsonb_build_object('photos',input->'photos','image_path',input->'photos'->>0);
  end if;
  -- Le rattachement (boutique, fiche) reste immuable : règle existante business_relations.
  select array_agg(k) into changes from jsonb_object_keys(data) k where data->k is distinct from r.payload->k;
  begin
   update public.koki_records set payload=jsonb_strip_nulls(payload||data),
    statut=case when kind='produits' and statut='Disponible' and coalesce((data->>'stock')::bigint,1)=0 then 'Épuisé' when kind='produits' and statut='Épuisé' and coalesce((data->>'stock')::bigint,0)>0 then 'Disponible' else statut end
    where id=r.id returning * into r;
  exception when unique_violation then raise exception 'Un élément du même nom existe déjà ici';
  end;
  insert into public.koki_audit(actor_id,operation,table_name,record_id,details) values(actor,'CORRECTION','koki_records',r.id,jsonb_build_object('decision','correction','champs',to_jsonb(coalesce(changes,'{}')),'avant',avant,'apres',r.statut));
  result:=koki_private.commerce_admin_view(r);
  insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,result);
  return result;
 end if;
 -- Ancien formulaire commerçant : sur une fiche en ligne, revalidation sans retrait du catalogue (mêmes contrôles qu'avant).
 if command='submit_merchant' and actor is not null and input->>'id' is not null then
  select * into r from public.koki_records where owner_id=actor and kind='professionnels';
  if r.id is not null and r.statut='Actif' then
   perform koki_private.business_keys_allowed(input,array['request_id','id','revision','name','profile','category','phone','address','location','hours','description','photos']);
   key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
   perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
   select * into cached from koki_private.business_keys k where k.actor_id=actor and k.request_id=key;
   if found then if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;return cached.output;end if;
   perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));
   select * into r from public.koki_records where id=r.id for update;
   if (input->>'id')::uuid is distinct from r.id or (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   if input->>'profile' is null or input->>'profile' not in ('Commerçant','Les deux') then raise exception 'Profil commerçant requis';end if;
   if r.payload->>'type'='Prestataire de services' and input->>'profile'<>'Les deux' then raise exception 'Conservez votre activité de services avec le profil Les deux';end if;
   phone:=koki_private.business_text(input,'phone',8,16);if phone!~'^\+[1-9][0-9]{7,14}$' then raise exception 'Téléphone WhatsApp international invalide';end if;
   if not koki_private.business_point(input->'location') then raise exception 'Localisation GPS invalide';end if;
   photos:=koki_private.commerce_photos(jsonb_build_object('photos',input->'photos'));
   data:=jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'type',input->>'profile','categorie',koki_private.business_text(input,'category',1,100),'telephone',phone,'adresse',koki_private.business_text(input,'address',3,500),'horaires',koki_private.business_text(input,'hours',3,500),'description',koki_private.business_text(input,'description',10,2000),'localisation',jsonb_build_object('latitude',input->'location'->'latitude','longitude',input->'location'->'longitude'),'photos',photos,'image_path',photos->>0);
   sensitive:=koki_private.commerce_sensibles(data||jsonb_strip_nulls(jsonb_build_object('whatsapp',r.payload->'whatsapp')));live:=koki_private.commerce_sensibles(r.payload);
   update public.koki_records set payload=(payload-'modification')||(data-'nom'-'type'-'telephone'-'photos'-'image_path')
     ||case when sensitive<>live then jsonb_build_object('modification',sensitive||jsonb_build_object('soumis_le',clock_timestamp())) else '{}'::jsonb end
    where id=r.id returning * into r;
   result:=to_jsonb(r);insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,result);
   return result;
  end if;
 end if;
 result:=koki_private.commerce_business(command,input);
 -- Historique des décisions (journal existant koki_audit) : décision, motif, statut avant et après.
 if command in ('moderate','review_changes','admin_review','review_merchant') and r.id is not null and (result->>'revision')::integer is distinct from r.revision then
  insert into public.koki_audit(actor_id,operation,table_name,record_id,details) values(actor,'DECISION','koki_records',r.id,jsonb_strip_nulls(jsonb_build_object('decision',case when command='review_changes' then input->>'decision'||'_changes' else input->>'decision' end,'note',nullif(btrim(input->>'note'),''),'commande',command,'avant',avant,'apres',result->>'statut')));
 end if;
 return result;
end $$;
revoke all on function koki_private.commerce_admin(text,jsonb) from public;
grant execute on function koki_private.commerce_admin(text,jsonb) to anon,authenticated;
revoke execute on function koki_private.commerce_business(text,jsonb) from anon,authenticated;
create or replace function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select koki_private.commerce_admin(command,input) $$;

-- Durcissement : public.koki_statistics() réservé aux comptes connectés (la fonction refusait déjà en interne).
revoke execute on function public.koki_statistics() from anon;
notify pgrst, 'reload schema';
commit;


-- ===== 5/37 : supabase/production/refus-motive.sql · sha256 11b4c94bd6c7b117
-- PRODUCTION : à lancer UNIQUEMENT après autorisation de Mourtada (éditeur SQL Supabase, une seule fois).
-- Refus motivé obligatoire côté serveur (Commerces & Services).
-- Jusqu'ici, seul l'écran d'administration exigeait un motif ; le serveur acceptait un refus sans motif.
-- Ce garde-fou refuse toute décision « reject » / « reject_changes » sans motif d'au moins 3 caractères.
-- Aucune donnée existante n'est modifiée. Réversible : drop trigger koki_refus_motive on public.koki_records;
create or replace function koki_private.refus_motive() returns trigger language plpgsql set search_path='' as $$
begin
 if new.kind in ('professionnels','boutiques','produits','services')
  and new.payload->'moderation' is distinct from old.payload->'moderation'
  and new.payload->'moderation'->>'decision' in ('reject','reject_changes')
  and length(btrim(coalesce(new.payload->'moderation'->>'note','')))<3
 then raise exception 'Motif de refus obligatoire (3 caractères minimum), visible par le professionnel';end if;
 return new;
end $$;
revoke all on function koki_private.refus_motive() from public,anon,authenticated;
drop trigger if exists koki_refus_motive on public.koki_records;
create trigger koki_refus_motive before update on public.koki_records for each row execute function koki_private.refus_motive();


-- ===== 6/37 : supabase/production/refus-motive-complet.sql · sha256 41784af09cef0c6c
-- PRODUCTION : à lancer UNIQUEMENT après autorisation de Mourtada (éditeur SQL Supabase, une seule fois, traduction automatique du navigateur DÉSACTIVÉE).
-- Garde : s'arrête sans rien modifier si merchant_business a changé depuis l'audit du 14/10/2026.
begin;
do $g$ begin if (select md5(prosrc) from pg_proc where oid='koki_private.merchant_business(text,jsonb)'::regprocedure)<>'525819041eed1710d0dbc44e62721c4d' then raise exception 'merchant_business a changé depuis l''audit : ne rien appliquer, prévenir Claude';end if;end $g$;
-- Refus motivé : compléments après l'audit du 14/10/2026 (fichier de PROPOSITION, rien n'est appliqué en production).
-- Prérequis : refus-motive.sql (déjà appliqué en production le 14/10/2026). Ne recrée pas le déclencheur.
-- 1. koki_private.refus_motive : le garde-fou couvre désormais aussi
--    - tout passage au statut « Refusé » ;
--    - tout passage d'une inscription en attente (« À valider » / « En attente ») à « Suspendu » ou « Fermé » (refus de fait) ;
--    - les chauffeurs ;
--    dans ces cas, la même mise à jour doit écrire payload.moderation avec un motif d'au moins 3 caractères.
--    Les suspensions de fiches déjà en ligne (Actif, Disponible…) ne sont pas concernées.
-- 2. koki_private.merchant_business (copie exacte de la version de production, md5 525819041eed1710d0dbc44e62721c4d, avec les ajouts ci-dessous) :
--    - ancienne décision review_merchant : clé « note » acceptée, motif obligatoire pour « reject », décision enregistrée
--      dans payload.moderation (le professionnel voit le motif, comme avec « moderate ») ;
--    - nouvelle décision admin_review « reject » pour une inscription chauffeur « À valider » : motif obligatoire,
--      droit Transport + double authentification, statut « Suspendu » (aucune modification de la contrainte de statuts),
--      motif enregistré dans payload.moderation ; l'administration peut toujours la valider ensuite (« approve »).
--      Contrôles du refus chauffeur : fiche existante de type chauffeurs au statut « À valider », révision exigée
--      (refus d'une révision périmée), jamais sur sa propre inscription, idempotence par request_id.
--    - toute décision admin_review sur sa propre fiche est refusée dès le routeur (auto-validation et auto-refus).
--    - les garde-fous de commerce_admin (pas d'auto-validation, MFA) s'appliquent toujours en amont, inchangés.
-- Aucune donnée existante n'est modifiée. Droits d'exécution conservés (create or replace).
-- Retour arrière : réappliquer refus-motive.sql et la définition de merchant_business de merchant-profiles.sql.
create or replace function koki_private.refus_motive() returns trigger language plpgsql set search_path='' as $$
declare m jsonb:=new.payload->'moderation';nouvelle boolean:=new.payload->'moderation' is distinct from old.payload->'moderation';
begin
 if new.kind in ('professionnels','boutiques','produits','services','chauffeurs')
  and nouvelle and m->>'decision' in ('reject','reject_changes')
  and length(btrim(coalesce(m->>'note','')))<3
 then raise exception 'Motif de refus obligatoire (3 caractères minimum), visible par le professionnel';end if;
 if new.kind in ('professionnels','boutiques','chauffeurs') and new.statut is distinct from old.statut
  and (new.statut='Refusé' or (old.statut in ('À valider','En attente') and new.statut in ('Suspendu','Fermé')))
  and not (nouvelle and m->>'decision' in ('reject','suspend') and length(btrim(coalesce(m->>'note','')))>=3)
 then raise exception 'Motif de refus obligatoire (3 caractères minimum), visible par le professionnel';end if;
 return new;
end $$;
revoke all on function koki_private.refus_motive() from public,anon,authenticated;

create or replace function koki_private.merchant_business(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();key uuid;cached koki_private.business_keys;r public.koki_records;photos jsonb;photo jsonb;phone text;data jsonb;result jsonb;item jsonb;output jsonb:='[]'::jsonb;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if command='catalog' then
   result:=koki_private.business(command,input);
   for item in select value from jsonb_array_elements(result) loop
     select * into r from public.koki_records where id=(item->>'id')::uuid;
     if r.kind='professionnels' then item:=item||jsonb_build_object('horaires',r.payload->>'horaires','localisation',r.payload->'localisation','adresse',r.payload->>'adresse','photos',coalesce(r.payload->'photos','[]'::jsonb),'type',r.payload->>'type');end if;
     output:=output||jsonb_build_array(item);
   end loop;
   return output;
 end if;
 -- L'ancien point d'entrée ne peut pas contourner la validation des nouvelles fiches.
 if command='admin_review' then
   select * into r from public.koki_records where id=(input->>'id')::uuid;
   if coalesce((r.payload->>'merchant_submission')::boolean,false) then command:='review_merchant';end if;
   -- Aucune décision sur ses propres fiches, quel que soit le chemin (défense en profondeur, en plus de commerce_admin).
   if r.id is not null and actor is not null and r.owner_id=actor then raise exception 'Vous ne pouvez pas valider ni corriger vos propres fiches' using errcode='42501';end if;
   -- Refus motivé d'une inscription chauffeur (motif obligatoire, visible par le chauffeur).
   if r.kind='chauffeurs' and input->>'decision'='reject' then command:='reject_driver';end if;
 end if;
 if command not in ('submit_merchant','review_merchant','reject_driver') then return koki_private.business(command,input);end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if command='review_merchant' and not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501';end if;
 if command='reject_driver' and not koki_private.allowed('transport') then raise exception 'Administration Transport et MFA requises' using errcode='42501';end if;
 perform koki_private.business_keys_allowed(input,case when command='submit_merchant' then array['request_id','id','revision','name','profile','category','phone','address','location','hours','description','photos'] when command='reject_driver' then array['request_id','id','revision','decision','note'] else array['request_id','id','revision','decision','note'] end);
 if input ? 'note' and (jsonb_typeof(input->'note')<>'string' or length(input->>'note')>500) then raise exception 'Motif trop long (500 caractères maximum)';end if;
 if input->>'decision'='reject' and command<>'submit_merchant' and length(btrim(coalesce(input->>'note','')))<3 then raise exception 'Motif de refus obligatoire (3 caractères minimum), visible par le professionnel';end if;
 key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
 select * into cached from koki_private.business_keys k where actor_id=actor and request_id=key;
 if found then
   if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;
   select * into r from public.koki_records where id=(cached.output->>'id')::uuid;
   if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès révoqué' using errcode='42501';end if;
   return cached.output;
 end if;
 if command='submit_merchant' then
   perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));
   select * into r from public.koki_records where owner_id=actor and kind='professionnels' for update;
   if r.id is not null and ((input->>'id')::uuid is distinct from r.id or (input->>'revision')::integer is distinct from r.revision) then raise exception 'Révision périmée : actualisez';end if;
   if r.id is null and input->>'id' is not null then raise exception 'Fiche inaccessible' using errcode='42501';end if;
   if r.statut='Suspendu' then raise exception 'Contactez l’administration pour votre fiche suspendue' using errcode='42501';end if;
   if input->>'profile' is null or input->>'profile' not in ('Commerçant','Les deux') then raise exception 'Profil commerçant requis';end if;
   if r.id is not null and r.payload->>'type'='Prestataire de services' and input->>'profile'<>'Les deux' then raise exception 'Conservez votre activité de services avec le profil Les deux';end if;
   phone:=koki_private.business_text(input,'phone',8,16);if phone!~'^\+[1-9][0-9]{7,14}$' then raise exception 'Téléphone WhatsApp international invalide';end if;
   if not koki_private.business_point(input->'location') then raise exception 'Localisation GPS invalide';end if;
   photos:=input->'photos';if jsonb_typeof(photos) is distinct from 'array' then raise exception 'Liste de photos requise';end if;
   if jsonb_array_length(photos)>5 then raise exception 'Cinq photos maximum';end if;
   if (select count(*) from jsonb_array_elements(photos))<>(select count(distinct value) from jsonb_array_elements(photos)) then raise exception 'Photos dupliquées';end if;
   for photo in select value from jsonb_array_elements(photos) loop
     if jsonb_typeof(photo)<>'string' or not coalesce(koki_private.business_owned_image(photo#>>'{}'),false) then raise exception 'Photo privée appartenant au commerçant requise';end if;
   end loop;
   data:=jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'type',input->>'profile','categorie',koki_private.business_text(input,'category',1,100),'telephone',phone,'adresse',koki_private.business_text(input,'address',3,500),'horaires',koki_private.business_text(input,'hours',3,500),'description',koki_private.business_text(input,'description',10,2000),'localisation',jsonb_build_object('latitude',input->'location'->'latitude','longitude',input->'location'->'longitude'),'photos',photos,'image_path',photos->>0,'merchant_submission',true);
   if r.id is null then insert into public.koki_records(kind,statut,owner_id,payload) values('professionnels','En attente',actor,data) returning * into r;
   else update public.koki_records set payload=payload||data,statut='En attente' where id=r.id returning * into r;end if;
 elsif command='reject_driver' then
   -- Contrôles refaits sous verrou : la fiche a pu changer depuis la lecture du routeur.
   select * into r from public.koki_records where id=(input->>'id')::uuid for update;
   if r.id is null then raise exception 'Fiche chauffeur introuvable';end if;
   if r.kind<>'chauffeurs' then raise exception 'Fiche chauffeur requise';end if;
   if r.owner_id=actor then raise exception 'Vous ne pouvez pas valider ni corriger vos propres fiches' using errcode='42501';end if;
   if input->>'revision' is null or (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   if r.statut<>'À valider' then raise exception 'Décision ou statut incompatible';end if;
   update public.koki_records set statut='Suspendu',payload=payload||jsonb_build_object('moderation',jsonb_build_object('decision','reject','note',btrim(input->>'note'),'at',clock_timestamp())) where id=r.id returning * into r;
 else
   select * into r from public.koki_records where id=(input->>'id')::uuid;
   perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));
   select * into r from public.koki_records where id=(input->>'id')::uuid for update;
   if r.kind is distinct from 'professionnels' or not coalesce((r.payload->>'merchant_submission')::boolean,false) then raise exception 'Fiche commerçant requise';end if;
   if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   data:=jsonb_build_object('moderation',jsonb_strip_nulls(jsonb_build_object('decision',input->>'decision','note',nullif(btrim(input->>'note'),''),'at',clock_timestamp())));
   if input->>'decision'='approve' and r.statut in ('En attente','Refusé','Suspendu') then update public.koki_records set statut='Actif',payload=payload||data where id=r.id returning * into r;
   elsif input->>'decision'='reject' and r.statut='En attente' then update public.koki_records set statut='Refusé',payload=payload||data where id=r.id returning * into r;
   elsif input->>'decision'='suspend' and r.statut='Actif' then update public.koki_records set statut='Suspendu',payload=payload||data where id=r.id returning * into r;
   else raise exception 'Décision ou statut incompatible';end if;
 end if;
 result:=to_jsonb(r);
 insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,result);
 return result;
end $$;

commit;
-- Vérification attendue : 2 lignes, refus_motive et merchant_business, executable_par_public = false.
select p.proname, has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute') as executable_par_public from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_private' and p.proname in ('refus_motive','merchant_business');


-- ===== 7/37 : supabase/production/transport-securite-suivi.sql · sha256 3a378662e8b6f583
-- PRODUCTION : à lancer UNIQUEMENT après autorisation de Mourtada (une seule fois).
-- Garde : s'arrête sans rien modifier si le point d'entrée public.koki_business a changé depuis le 14/10/2026,
-- ou si ces ajouts sont déjà installés.
-- Transport : sécurité et suivi des courses (fichier de PROPOSITION, rien n'est appliqué en production).
-- Ajoute, sans modifier koki_private.business ni les données existantes :
--  1. Code de départ (4 chiffres) créé à chaque réservation, visible par le CLIENT seulement ; le chauffeur doit le
--     saisir pour passer à « Course en cours » (5 essais au plus). Une transition directe sans code est refusée.
--  2. Expiration des demandes : un chauffeur ne peut plus accepter une demande vieille de plus de 2 minutes ;
--     une demande expirée est annulée automatiquement avant une nouvelle réservation (client ou chauffeur libérés).
--  3. Suivi en direct : le client d'une course acceptée voit la dernière position partagée par son chauffeur.
--  4. Note et commentaires : une note (1 à 5), des étiquettes prédéfinies et un commentaire par course terminée ;
--     la moyenne est affichée dans la liste des chauffeurs proches.
--  5. Signalement : le client ou le chauffeur d'une course peut signaler un problème (sécurité, comportement…),
--     consultable par l'administration Transport (droit Transport + double authentification).
--  6. Tableau du jour du chauffeur : courses terminées, montant encaissé, note.
-- Point d'entrée : public.koki_business oriente ces commandes vers koki_private.transport_plus, le reste inchangé
-- vers koki_private.commerce_admin. Retour arrière : en fin de fichier.
begin;
do $g$ begin
 if (select md5(prosrc) from pg_proc where oid='public.koki_business(text,jsonb)'::regprocedure)<>'1cc5c9ca1c67c384fefc9d07810e7455' then raise exception 'public.koki_business a changé : ne rien appliquer, prévenir Claude';end if;
 if to_regclass('koki_private.ride_codes') is not null then raise exception 'Ajouts Transport déjà installés : rien à faire';end if;
end $g$;

create table koki_private.ride_codes(
 ride_id uuid primary key references public.koki_records(id) on delete cascade,
 code text not null check(code ~ '^[0-9]{4}$'),
 attempts integer not null default 0,
 created_at timestamptz not null default now());
create table koki_private.ride_ratings(
 ride_id uuid primary key references public.koki_records(id) on delete cascade,
 client_id uuid not null references auth.users(id),
 driver_id uuid not null references public.koki_records(id),
 rating smallint not null check(rating between 1 and 5),
 tags text[] not null default '{}',
 comment text check(comment is null or length(comment)<=500),
 created_at timestamptz not null default now());
create index koki_ride_ratings_driver on koki_private.ride_ratings(driver_id);
create table koki_private.ride_reports(
 id uuid primary key default gen_random_uuid(),
 ride_id uuid not null references public.koki_records(id) on delete cascade,
 reporter_id uuid not null references auth.users(id),
 role text not null check(role in ('client','chauffeur')),
 motif text not null check(motif in ('Sécurité','Comportement','Itinéraire','Prix','Objet perdu','Autre')),
 details text check(details is null or length(details)<=1000),
 statut text not null default 'Nouveau' check(statut in ('Nouveau','En cours','Traité')),
 created_at timestamptz not null default now());
create index koki_ride_reports_created on koki_private.ride_reports(created_at desc);
alter table koki_private.ride_codes enable row level security;
alter table koki_private.ride_ratings enable row level security;
alter table koki_private.ride_reports enable row level security;
revoke all on koki_private.ride_codes,koki_private.ride_ratings,koki_private.ride_reports from public,anon,authenticated;

-- Code créé avec la course (aucune course existante n'est modifiée ; les courses déjà en cours n'en ont pas besoin).
create function koki_private.ride_code_create() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind='courses' then
  insert into koki_private.ride_codes(ride_id,code) values(new.id,lpad(floor(random()*10000)::integer::text,4,'0')) on conflict do nothing;
 end if;
 return new;
end $$;
revoke all on function koki_private.ride_code_create() from public,anon,authenticated;
create trigger koki_ride_code after insert on public.koki_records for each row execute function koki_private.ride_code_create();

-- Garde-fous des transitions de course : demande expirée, départ sans code.
create function koki_private.ride_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.kind='courses' and new.statut is distinct from old.statut then
  if old.statut='En attente' and new.statut='Acceptée' and old.created_at<now()-interval '2 minutes' then
   raise exception 'Demande expirée : le client doit relancer sa demande';end if;
  if new.statut='Course en cours' and exists(select 1 from koki_private.ride_codes c where c.ride_id=new.id)
   and coalesce(current_setting('koki.depart_valide',true),'')<>new.id::text and not koki_private.allowed('transport') then
   raise exception 'Code de départ requis : demandez-le au client';end if;
 end if;
 return new;
end $$;
revoke all on function koki_private.ride_guard() from public,anon,authenticated;
create trigger koki_ride_guard before update on public.koki_records for each row execute function koki_private.ride_guard();

create function koki_private.transport_plus(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();r public.koki_records;d public.koki_records;c koki_private.ride_codes;res jsonb;item jsonb;out jsonb:='[]'::jsonb;
 tags text[];n integer;v public.koki_records;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>16384 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if command not in ('nearby_drivers','reserve_ride','ride_code','start_ride','ride_tracking','rate_ride','report_ride','driver_stats','admin_ride_reports') then raise exception 'Commande inconnue';end if;
 -- Chauffeurs proches : réponse habituelle complétée par la note moyenne (au moins une note).
 if command='nearby_drivers' then
  res:=koki_private.commerce_admin(command,input);
  for item in select value from jsonb_array_elements(coalesce(res,'[]'::jsonb)) loop
   select count(*) into n from koki_private.ride_ratings where driver_id=(item->>'driver_id')::uuid;
   out:=out||jsonb_build_array(item||case when n>0 then jsonb_build_object('rating',(select round(avg(rating)::numeric,1) from koki_private.ride_ratings where driver_id=(item->>'driver_id')::uuid),'rating_count',n) else '{}'::jsonb end);
  end loop;
  return out;
 end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 -- Réservation : les demandes restées sans réponse plus de 2 minutes (client ou chauffeur visé) sont annulées d'abord.
 if command='reserve_ride' then
  select * into v from public.koki_records where id=(input->>'vehicle_id')::uuid and kind='vehicules';
  update public.koki_records set statut='Annulée',payload=payload||jsonb_build_object('expiree',true)
   where kind='courses' and statut='En attente' and created_at<now()-interval '2 minutes' and (client_id=actor or (v.id is not null and driver_id=v.parent_id));
  return koki_private.commerce_admin(command,input);
 end if;
 if command='admin_ride_reports' then
  perform koki_private.business_keys_allowed(input,array[]::text[]);
  if not koki_private.allowed('transport') then raise exception 'Administration Transport et MFA requises' using errcode='42501';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'ride_id',x.ride_id,'role',x.role,'motif',x.motif,'details',x.details,'statut',x.statut,'created_at',x.created_at,'course_statut',k.statut,'chauffeur',dr.payload->>'nom') order by x.created_at desc)
   from (select * from koki_private.ride_reports order by created_at desc limit 100) x join public.koki_records k on k.id=x.ride_id left join public.koki_records dr on dr.id=k.driver_id),'[]'::jsonb);
 end if;
 if command='driver_stats' then
  perform koki_private.business_keys_allowed(input,array[]::text[]);
  select * into d from public.koki_records where owner_id=actor and kind='chauffeurs';
  if d.id is null then raise exception 'Chauffeur requis' using errcode='42501';end if;
  return jsonb_build_object(
   'courses_jour',(select count(*) from public.koki_records k where k.kind='courses' and k.driver_id=d.id and k.statut='Terminée' and (k.updated_at at time zone 'Africa/Dakar')::date=(now() at time zone 'Africa/Dakar')::date),
   'montant_jour',(select coalesce(sum((k.payload->>'tarif')::bigint),0) from public.koki_records k where k.kind='courses' and k.driver_id=d.id and k.statut='Terminée' and (k.updated_at at time zone 'Africa/Dakar')::date=(now() at time zone 'Africa/Dakar')::date),
   'note',(select round(avg(rating)::numeric,1) from koki_private.ride_ratings where driver_id=d.id),
   'notes',(select count(*) from koki_private.ride_ratings where driver_id=d.id));
 end if;
 select * into r from public.koki_records where id=(input->>'id')::uuid;
 if r.id is null or r.kind<>'courses' then raise exception 'Course introuvable';end if;
 -- Code de départ : le client seul, pendant que le chauffeur arrive.
 if command='ride_code' then
  perform koki_private.business_keys_allowed(input,array['id']);
  if r.client_id is distinct from actor then raise exception 'Code réservé au client de la course' using errcode='42501';end if;
  if r.statut not in ('Acceptée','Chauffeur en route') then return jsonb_build_object('code',null);end if;
  return jsonb_build_object('code',(select code from koki_private.ride_codes where ride_id=r.id));
 end if;
 -- Départ : le chauffeur assigné saisit le code donné par le client (5 essais).
 if command='start_ride' then
  perform koki_private.business_keys_allowed(input,array['request_id','id','revision','code']);
  if not coalesce(koki_private.owns_business(r.driver_id),false) then raise exception 'Chauffeur assigné requis' using errcode='42501';end if;
  if r.statut<>'Chauffeur en route' then raise exception 'Le départ se valide quand vous êtes arrivé au client';end if;
  select * into c from koki_private.ride_codes where ride_id=r.id for update;
  if c.ride_id is null then raise exception 'Code indisponible pour cette course';end if;
  if c.attempts>=5 then raise exception 'Trop d’essais : contactez le client ou l’administration';end if;
  if coalesce(input->>'code','')<>c.code then
   update koki_private.ride_codes set attempts=attempts+1 where ride_id=r.id;
   return jsonb_build_object('error','Code incorrect','essais_restants',4-c.attempts);
  end if;
  perform set_config('koki.depart_valide',r.id::text,true);
  res:=koki_private.commerce_admin('transition',jsonb_build_object('request_id',input->'request_id','id',r.id,'next','Course en cours','revision',input->'revision'));
  perform set_config('koki.depart_valide','',true);
  return res;
 end if;
 -- Suivi en direct : dernière position partagée par le chauffeur, pour le client d'une course acceptée.
 if command='ride_tracking' then
  perform koki_private.business_keys_allowed(input,array['id']);
  if r.client_id is distinct from actor then raise exception 'Suivi réservé au client de la course' using errcode='42501';end if;
  if r.statut not in ('Acceptée','Chauffeur en route','Course en cours') then return jsonb_build_object('statut',r.statut,'position',null);end if;
  select * into d from public.koki_records where id=r.driver_id;
  return jsonb_build_object('statut',r.statut,'position',case when koki_private.business_point(d.payload->'position') then d.payload->'position' end,'position_updated_at',d.payload->>'position_updated_at');
 end if;
 -- Note : une seule fois, par le client, après une course terminée.
 if command='rate_ride' then
  perform koki_private.business_keys_allowed(input,array['id','rating','tags','comment']);
  if r.client_id is distinct from actor then raise exception 'Note réservée au client de la course' using errcode='42501';end if;
  if r.statut<>'Terminée' then raise exception 'La note se donne après la course';end if;
  if jsonb_typeof(input->'rating') is distinct from 'number' or (input->>'rating')::numeric not in (1,2,3,4,5) then raise exception 'Note de 1 à 5 requise';end if;
  if input ? 'tags' then
   if jsonb_typeof(input->'tags')<>'array' or jsonb_array_length(input->'tags')>6 then raise exception 'Étiquettes invalides';end if;
   select array_agg(distinct t) into tags from jsonb_array_elements_text(input->'tags') t;
   if exists(select 1 from unnest(coalesce(tags,'{}')) t where t not in ('Ponctuel','Conduite prudente','Courtois','Casque fourni','Véhicule propre','Prix respecté')) then raise exception 'Étiquette inconnue';end if;
  end if;
  if input ? 'comment' and (jsonb_typeof(input->'comment')<>'string' or length(input->>'comment')>500) then raise exception 'Commentaire trop long (500 caractères maximum)';end if;
  insert into koki_private.ride_ratings(ride_id,client_id,driver_id,rating,tags,comment) values(r.id,actor,r.driver_id,(input->>'rating')::smallint,coalesce(tags,'{}'),nullif(btrim(coalesce(input->>'comment','')),''))
   on conflict (ride_id) do nothing;
  if not found then raise exception 'Course déjà notée';end if;
  return jsonb_build_object('ok',true);
 end if;
 -- Signalement : client ou chauffeur de la course, 5 au plus par jour et par compte.
 if command='report_ride' then
  perform koki_private.business_keys_allowed(input,array['id','motif','details']);
  if r.client_id is distinct from actor and not exists(select 1 from public.koki_records x where x.id=r.driver_id and x.owner_id=actor) then raise exception 'Signalement réservé aux participants de la course' using errcode='42501';end if;
  if input->>'motif' is null or input->>'motif' not in ('Sécurité','Comportement','Itinéraire','Prix','Objet perdu','Autre') then raise exception 'Motif de signalement invalide';end if;
  if input ? 'details' and (jsonb_typeof(input->'details')<>'string' or length(input->>'details')>1000) then raise exception 'Détails trop longs (1 000 caractères maximum)';end if;
  if (select count(*) from koki_private.ride_reports where reporter_id=actor and created_at>now()-interval '1 day')>=5 then raise exception 'Trop de signalements aujourd’hui : appelez l’administration';end if;
  insert into koki_private.ride_reports(ride_id,reporter_id,role,motif,details) values(r.id,actor,case when r.client_id=actor then 'client' else 'chauffeur' end,input->>'motif',nullif(btrim(coalesce(input->>'details','')),''));
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Commande inconnue';
end $$;
revoke all on function koki_private.transport_plus(text,jsonb) from public;
grant execute on function koki_private.transport_plus(text,jsonb) to anon,authenticated;

create or replace function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$
 select case when command in ('nearby_drivers','reserve_ride','ride_code','start_ride','ride_tracking','rate_ride','report_ride','driver_stats','admin_ride_reports')
  then koki_private.transport_plus(command,input) else koki_private.commerce_admin(command,input) end $$;
commit;
-- Retour arrière (dans cet ordre) :
-- create or replace function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$ select koki_private.commerce_admin(command,input) $$;
-- drop trigger koki_ride_guard on public.koki_records; drop trigger koki_ride_code on public.koki_records;
-- drop function koki_private.transport_plus(text,jsonb); drop function koki_private.ride_guard(); drop function koki_private.ride_code_create();
-- drop table koki_private.ride_reports, koki_private.ride_ratings, koki_private.ride_codes;
-- Vérification attendue : transport_plus présent, déclencheurs actifs, tables privées sans accès direct.
select (select count(*) from pg_trigger where tgname in ('koki_ride_code','koki_ride_guard') and tgenabled='O') as declencheurs_actifs,
 has_function_privilege('authenticated','koki_private.transport_plus(text,jsonb)','execute') as fonction_disponible,
 has_table_privilege('authenticated','koki_private.ride_codes','select') as codes_lisibles_directement;


-- ===== 8/37 : supabase/production/signalements-statut.sql · sha256 b1ee202c129640e7
-- PRODUCTION : à lancer UNIQUEMENT après autorisation de Mourtada (une seule fois).
-- Garde : s'arrête sans rien modifier si le point d'entrée public.koki_business a changé depuis le 14/10/2026,
-- ou si ce traitement est déjà installé.
-- Transport · Signalements : traitement par l'administration (fichier de PROPOSITION, rien n'est appliqué en production).
-- Prérequis : transport-securite-suivi.sql (appliqué en production le 14/10/2026).
-- Ajoute, sans modifier koki_private.transport_plus, koki_private.commerce_admin ni les signalements existants :
--  1. Trois colonnes facultatives sur koki_private.ride_reports : note de l'administration (500 caractères au plus),
--     date et auteur du dernier changement de statut. Les signalements existants restent « Nouveau », sans note.
--  2. koki_private.ride_reports_admin :
--     - admin_ride_reports : même liste qu'avant (100 plus récents), complétée par la note et la date de traitement ;
--     - admin_ride_report_status : passe un signalement à « Nouveau », « En cours » ou « Traité », avec une note
--       facultative (obligatoire pour « Traité » : ce qui a été fait). Droit Transport + double authentification.
--       Chaque changement est inscrit au journal des opérations (koki_audit).
--  3. public.koki_business oriente ces deux commandes vers ride_reports_admin ; tout le reste est inchangé.
-- Retour arrière : en fin de fichier.
begin;
do $g$ begin
 if (select md5(prosrc) from pg_proc where oid='public.koki_business(text,jsonb)'::regprocedure)<>'ed14f4a6970cf05f067629a83b15070c' then raise exception 'public.koki_business a changé : ne rien appliquer, prévenir Claude';end if;
 if exists(select 1 from information_schema.columns where table_schema='koki_private' and table_name='ride_reports' and column_name='note_admin') then raise exception 'Traitement des signalements déjà installé : rien à faire';end if;
end $g$;

alter table koki_private.ride_reports
 add column note_admin text check(note_admin is null or length(note_admin) between 3 and 500),
 add column traite_le timestamptz,
 add column traite_par uuid references auth.users(id);

create function koki_private.ride_reports_admin(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();x koki_private.ride_reports;note text;avant text;
begin
 if command not in ('admin_ride_reports','admin_ride_report_status') then raise exception 'Commande inconnue';end if;
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>4096 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if actor is null or not koki_private.allowed('transport') then raise exception 'Administration Transport et MFA requises' using errcode='42501';end if;
 if command='admin_ride_reports' then
  perform koki_private.business_keys_allowed(input,array[]::text[]);
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'ride_id',r.ride_id,'role',r.role,'motif',r.motif,'details',r.details,'statut',r.statut,'created_at',r.created_at,
    'note_admin',r.note_admin,'traite_le',r.traite_le,'course_statut',k.statut,'chauffeur',dr.payload->>'nom') order by r.created_at desc)
   from (select * from koki_private.ride_reports order by created_at desc limit 100) r join public.koki_records k on k.id=r.ride_id left join public.koki_records dr on dr.id=k.driver_id),'[]'::jsonb);
 end if;
 perform koki_private.business_keys_allowed(input,array['request_id','id','statut','note']);
 if input->>'statut' is null or input->>'statut' not in ('Nouveau','En cours','Traité') then raise exception 'Statut de signalement invalide';end if;
 if input ? 'note' and jsonb_typeof(input->'note')<>'string' then raise exception 'Note invalide';end if;
 note:=nullif(btrim(coalesce(input->>'note','')),'');
 if note is not null and length(note) not between 3 and 500 then raise exception 'Note de 3 à 500 caractères';end if;
 if input->>'statut'='Traité' and note is null then raise exception 'Indiquez ce qui a été fait (note obligatoire pour « Traité »)';end if;
 select * into x from koki_private.ride_reports where id=(nullif(input->>'id',''))::uuid for update;
 if x.id is null then raise exception 'Signalement introuvable';end if;
 avant:=x.statut;
 update koki_private.ride_reports set statut=input->>'statut',note_admin=coalesce(note,note_admin),traite_le=now(),traite_par=actor where id=x.id returning * into x;
 insert into public.koki_audit(actor_id,operation,table_name,record_id,details)
  values(actor,'SIGNALEMENT','ride_reports',x.id,jsonb_strip_nulls(jsonb_build_object('avant',avant,'apres',x.statut,'note',note,'course',x.ride_id)));
 return jsonb_build_object('id',x.id,'statut',x.statut,'note_admin',x.note_admin,'traite_le',x.traite_le);
end $$;
revoke all on function koki_private.ride_reports_admin(text,jsonb) from public;
grant execute on function koki_private.ride_reports_admin(text,jsonb) to anon,authenticated;

create or replace function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$
 select case when command in ('admin_ride_reports','admin_ride_report_status') then koki_private.ride_reports_admin(command,input)
  when command in ('nearby_drivers','reserve_ride','ride_code','start_ride','ride_tracking','rate_ride','report_ride','driver_stats')
  then koki_private.transport_plus(command,input) else koki_private.commerce_admin(command,input) end $$;
commit;
-- Retour arrière (dans cet ordre) :
-- create or replace function public.koki_business(command text,input jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$
--  select case when command in ('nearby_drivers','reserve_ride','ride_code','start_ride','ride_tracking','rate_ride','report_ride','driver_stats','admin_ride_reports')
--   then koki_private.transport_plus(command,input) else koki_private.commerce_admin(command,input) end $$;
-- drop function koki_private.ride_reports_admin(text,jsonb);
-- alter table koki_private.ride_reports drop column traite_par, drop column traite_le, drop column note_admin;
-- Vérification attendue : fonction disponible, colonnes présentes, table privée sans accès direct.
select has_function_privilege('authenticated','koki_private.ride_reports_admin(text,jsonb)','execute') as fonction_disponible,
 (select count(*) from information_schema.columns where table_schema='koki_private' and table_name='ride_reports' and column_name in ('note_admin','traite_le','traite_par')) as colonnes_ajoutees,
 has_table_privilege('authenticated','koki_private.ride_reports','select') as signalements_lisibles_directement;


-- ===== 9/37 : supabase/proposals/produits-validation.sql · sha256 efcae795234e308e
-- Proposition : appliquer après commerce-modernisation et refus-motive-complet, après validation.
-- Les produits existants restent inchangés. Les nouveaux produits attendent une décision.
begin;
create or replace function koki_private.product_review_required() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.kind='produits' then
  new.statut:='Masqué';
  new.payload:=new.payload||jsonb_build_object('moderation_lock',true,'moderation',jsonb_build_object('decision','pending_review','at',now()));
 end if;
 return new;
end $$;
revoke all on function koki_private.product_review_required() from public,anon,authenticated;
create trigger koki_product_review_required before insert on public.koki_records
for each row execute function koki_private.product_review_required();

-- Conserver tous les contrôles existants ; enrichir seulement la file et les compteurs.
alter function koki_private.commerce_admin(text,jsonb) rename to commerce_admin_before_product_review;
create function koki_private.commerce_admin(command text,input jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare answer jsonb; pending jsonb; pending_count bigint;
begin
 answer:=koki_private.commerce_admin_before_product_review(command,input);
 if command='admin_queue' then
  select coalesce(jsonb_agg(koki_private.commerce_admin_view(r)||jsonb_build_object('demande','produit') order by r.created_at),'[]'::jsonb)
  into pending from public.koki_records r where r.kind='produits' and r.statut='Masqué' and r.payload->'moderation'->>'decision'='pending_review';
  return answer||pending;
 elsif command='admin_stats' then
  select count(*) into pending_count from public.koki_records r where r.kind='produits' and r.statut='Masqué' and r.payload->'moderation'->>'decision'='pending_review';
  return answer||jsonb_build_object('produits_en_attente',pending_count,'suspendus',greatest(0,(answer->>'suspendus')::bigint-pending_count));
 end if;
 return answer;
end $$;
revoke all on function koki_private.commerce_admin(text,jsonb) from public,anon,authenticated;
revoke all on function koki_private.commerce_admin_before_product_review(text,jsonb) from public,anon,authenticated;
grant execute on function koki_private.commerce_admin(text,jsonb) to anon,authenticated;
commit;


-- ===== 10/37 : supabase/proposals/commerce-avis-statistiques.sql · sha256 22516eedce3d0957
-- PROPOSITION — Commerces & Services : avis des clients, suivi d'activité et statistiques du commerçant.
-- NON APPLIQUÉE : à relire, puis à tester sur Supabase LOCAL (supabase start) avant toute installation distante.
-- Additive : aucune table existante n'est modifiée, aucune donnée n'est supprimée ni réécrite.
-- À installer après commerce-modernisation.sql (elle utilise koki_records et ses statuts publiables).
-- L'application publique (assets/business/client.mjs) détecte l'absence de ces fonctions (PGRST202) et masque simplement
-- les avis et les statistiques tant qu'elles ne sont pas installées : l'ordre de mise en ligne est donc libre.
--
-- Règles :
--  * seules les fiches visibles dans le catalogue public peuvent recevoir un avis ou une activité ;
--  * un client (compte permanent) = un avis par fiche, modifiable ; jamais sur sa propre fiche ; 20 avis par jour maximum ;
--  * un avis masqué par l'administration ne peut pas être republié par son auteur ;
--  * le suivi d'activité est anonyme (compteurs par fiche, type et jour : aucune identité, aucune adresse IP) ;
--  * un commerçant ne voit que les chiffres de ses propres fiches.
begin;

-- 0. Préflight : le socle commerce doit exister.
do $$ begin
 if to_regclass('public.koki_records') is null or to_regprocedure('koki_private.commerce_catalog()') is null then
  raise exception 'Préflight avis : installer d''abord le socle commerce (commerce-modernisation.sql)';
 end if;
end $$;

-- 1. Fiche publique = même règle que koki_private.commerce_catalog().
create function koki_private.is_public_listing(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.koki_records l where l.id=p_id and (
  (l.kind='professionnels' and l.statut='Actif')
  or (l.kind='boutiques' and l.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=l.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
  or (l.kind='services' and l.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=l.parent_id and prof.statut='Actif'))
  or (l.kind='produits' and l.statut in ('Disponible','Épuisé') and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=l.parent_id and b.statut='Actif' and prof.statut='Actif'))))
$$;
revoke all on function koki_private.is_public_listing(uuid) from public,anon,authenticated;

-- 2. Avis.
create table public.koki_reviews(
 id uuid primary key default gen_random_uuid(),
 target_id uuid not null references public.koki_records(id) on delete cascade,
 author_id uuid not null references auth.users(id) on delete cascade,
 rating smallint not null check(rating between 1 and 5),
 comment text check(comment is null or char_length(comment)<=500),
 status text not null default 'publié' check(status in ('publié','masqué')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(target_id,author_id));
create index koki_reviews_target on public.koki_reviews(target_id,status,created_at desc);
create index koki_reviews_author on public.koki_reviews(author_id,updated_at desc);
alter table public.koki_reviews enable row level security;
revoke all on public.koki_reviews from public,anon,authenticated;
-- Aucun accès direct pour le public ni les clients : tout passe par les fonctions ci-dessous.
-- Modération : l'administration (permission « commerce », aal2) lit tous les avis et peut les masquer.
grant select,update(status) on public.koki_reviews to authenticated;
create policy reviews_admin_read on public.koki_reviews for select to authenticated using(koki_private.allowed('commerce'));
create policy reviews_admin_hide on public.koki_reviews for update to authenticated using(koki_private.allowed('commerce')) with check(koki_private.allowed('commerce'));

create function public.koki_reviews_list(p_target uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare moyenne numeric; total integer; liste jsonb;
begin
 if p_target is null or not koki_private.is_public_listing(p_target) then return null;end if;
 select round(avg(rating)::numeric,1),count(*) into moyenne,total from public.koki_reviews where target_id=p_target and status='publié';
 select coalesce(jsonb_agg(jsonb_build_object('note',r.rating,'commentaire',nullif(btrim(r.comment),''),'auteur','Client','date',to_char(r.created_at at time zone 'Africa/Dakar','YYYY-MM-DD')) order by r.created_at desc),'[]'::jsonb)
  into liste from (select * from public.koki_reviews where target_id=p_target and status='publié' order by created_at desc limit 20) r;
 return jsonb_build_object('moyenne',coalesce(moyenne,0),'total',total,'avis',liste);
end $$;
revoke all on function public.koki_reviews_list(uuid) from public;
grant execute on function public.koki_reviews_list(uuid) to anon,authenticated;

create function public.koki_review_save(p_target uuid,p_rating integer,p_comment text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); texte text:=nullif(btrim(coalesce(p_comment,'')),''); existant text; proprio uuid;
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if p_rating is null or p_rating not between 1 and 5 then raise exception 'Choisissez une note de 1 à 5.';end if;
 if texte is not null and char_length(texte)>500 then raise exception 'Le commentaire est limité à 500 caractères.';end if;
 if p_target is null or not koki_private.is_public_listing(p_target) then raise exception 'Cette fiche n''est plus disponible.';end if;
 select owner_id into proprio from public.koki_records where id=p_target;
 if proprio=actor then raise exception 'Vous ne pouvez pas noter votre propre fiche.';end if;
 select status into existant from public.koki_reviews where target_id=p_target and author_id=actor;
 if existant='masqué' then raise exception 'Votre avis a été retiré par l''administration.';end if;
 if existant is null and (select count(*) from public.koki_reviews where author_id=actor and created_at>now()-interval '1 day')>=20 then
  raise exception 'Trop d''avis aujourd''hui. Réessayez demain.';end if;
 insert into public.koki_reviews(target_id,author_id,rating,comment) values(p_target,actor,p_rating,texte)
  on conflict(target_id,author_id) do update set rating=excluded.rating,comment=excluded.comment,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.koki_review_save(uuid,integer,text) from public,anon;
grant execute on function public.koki_review_save(uuid,integer,text) to authenticated;

-- 3. Suivi d'activité anonyme : un compteur par fiche, type d'événement et jour.
create table public.koki_activity(
 target_id uuid not null references public.koki_records(id) on delete cascade,
 kind text not null check(kind in ('vue','appel','whatsapp','commander','partage','panier','devis')),
 day date not null default current_date,
 n integer not null default 0 check(n>=0),
 primary key(target_id,kind,day));
create index koki_activity_day on public.koki_activity(day);
alter table public.koki_activity enable row level security;
revoke all on public.koki_activity from public,anon,authenticated;

create function public.koki_track(p_target uuid,p_kind text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_target is null or p_kind is null or p_kind not in ('vue','appel','whatsapp','commander','partage','panier','devis') then return;end if;
 if not koki_private.is_public_listing(p_target) then return;end if;
 insert into public.koki_activity(target_id,kind,day,n) values(p_target,p_kind,current_date,1)
  on conflict(target_id,kind,day) do update set n=least(public.koki_activity.n+1,1000000);
end $$;
revoke all on function public.koki_track(uuid,text) from public;
grant execute on function public.koki_track(uuid,text) to anon,authenticated;

-- 4. Statistiques du commerçant : uniquement ses propres fiches (propriétaire = compte connecté).
create function public.koki_stats_mine(p_days integer default 30) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); jours integer:=greatest(1,least(coalesce(p_days,30),365)); resultat jsonb;
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 with mine as (select id,kind,payload->>'nom' as nom from public.koki_records
   where owner_id=actor and kind in ('professionnels','boutiques','produits','services') and statut<>'Archivé' order by updated_at desc limit 300),
 agg as (select a.target_id,a.kind,sum(a.n)::integer as n from public.koki_activity a join mine on mine.id=a.target_id
   where a.day>current_date-jours group by a.target_id,a.kind)
 select jsonb_build_object('jours',jours,
  'totaux',coalesce((select jsonb_object_agg(t.kind,t.n) from (select kind,sum(n)::integer as n from agg group by kind) t),'{}'::jsonb),
  'elements',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'kind',m.kind,'nom',m.nom)||coalesce((select jsonb_object_agg(g.kind,g.n) from agg g where g.target_id=m.id),'{}'::jsonb)) from mine m),'[]'::jsonb))
 into resultat;
 return resultat;
end $$;
revoke all on function public.koki_stats_mine(integer) from public,anon;
grant execute on function public.koki_stats_mine(integer) to authenticated;

commit;

-- RETOUR ARRIÈRE (à exécuter seulement après sauvegarde, il supprime les avis et les compteurs) :
-- drop function public.koki_stats_mine(integer),public.koki_track(uuid,text),public.koki_review_save(uuid,integer,text),public.koki_reviews_list(uuid);
-- drop table public.koki_activity,public.koki_reviews;
-- drop function koki_private.is_public_listing(uuid);


-- ===== 11/37 : supabase/proposals/notifications.sql · sha256 a0efcbec774a56e2
-- Notifications transactionnelles. Additif : aucun envoi historique ni changement des parcours existants.
begin;
create table public.koki_notifications (
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id) on delete cascade,
 record_id uuid not null references public.koki_records(id) on delete cascade,
 revision bigint not null, title text not null, body text not null, category text not null,
 created_at timestamptz not null default now(), read_at timestamptz,
 unique(recipient_id,record_id,revision)
);
create index koki_notifications_inbox on public.koki_notifications(recipient_id,created_at desc);
alter table public.koki_notifications enable row level security;
revoke all on public.koki_notifications from public,anon,authenticated;
grant select,update(read_at) on public.koki_notifications to authenticated;
create policy notifications_read on public.koki_notifications for select to authenticated using(recipient_id=(select auth.uid()));
create policy notifications_seen on public.koki_notifications for update to authenticated using(recipient_id=(select auth.uid())) with check(recipient_id=(select auth.uid()));
create table public.koki_notification_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 sms boolean not null default false, updated_at timestamptz not null default now()
);
alter table public.koki_notification_preferences enable row level security;
revoke all on public.koki_notification_preferences from public,anon,authenticated;
grant select,insert,update on public.koki_notification_preferences to authenticated;
create policy notification_preferences_own on public.koki_notification_preferences for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false));
create table public.koki_push_subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text unique not null check(length(endpoint)<2048), p256dh text not null, auth text not null,
 created_at timestamptz not null default now(),
 check(endpoint ~ '^https://(fcm.googleapis.com|updates.push.services.mozilla.com|web.push.apple.com)/[^[:space:]]+$'),
 check(p256dh ~ '^[A-Za-z0-9_-]{87}=?$'), check(auth ~ '^[A-Za-z0-9_-]{22}={0,2}$')
);
alter table public.koki_push_subscriptions enable row level security;
revoke all on public.koki_push_subscriptions from public,anon,authenticated;
grant select,delete on public.koki_push_subscriptions to authenticated;
create policy push_own on public.koki_push_subscriptions for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create function public.koki_push_register(p_endpoint text,p_p256dh text,p_auth text) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Connexion requise' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 if exists(select 1 from public.koki_push_subscriptions where endpoint=p_endpoint and user_id<>actor) then raise exception 'Désactivez puis réactivez les notifications sur cet appareil.';end if;
 if (select count(*) from public.koki_push_subscriptions where user_id=actor)>=5 and not exists(select 1 from public.koki_push_subscriptions where endpoint=p_endpoint and user_id=actor) then raise exception 'Cinq appareils maximum.';end if;
 insert into public.koki_push_subscriptions(user_id,endpoint,p256dh,auth) values(actor,p_endpoint,p_p256dh,p_auth)
 on conflict(endpoint) do update set p256dh=excluded.p256dh,auth=excluded.auth where koki_push_subscriptions.user_id=actor;
end $$;
revoke all on function public.koki_push_register(text,text,text) from public,anon;
grant execute on function public.koki_push_register(text,text,text) to authenticated;

-- Destinataires dérivés exclusivement des données métier, jamais d'un numéro fourni par l'appelant.
create function koki_private.notify_record() returns trigger language plpgsql security definer set search_path='' as $$
declare recipients uuid[]:='{}'; target uuid; label text; text_body text; admin_permission text;
begin
 if tg_op='UPDATE' then
  if new.statut is not distinct from old.statut and new.driver_id is not distinct from old.driver_id then return new;end if;
 end if;
 if new.kind in ('commandes','courses','demandes_services') then
  recipients:=array_append(recipients,new.client_id);
  select owner_id into target from public.koki_records where id=case when new.kind='courses' then new.driver_id else new.provider_id end;
  recipients:=array_append(recipients,target);
  label:=case new.kind when 'courses' then 'Votre course' when 'commandes' then 'Votre commande' else 'Votre demande de service' end;
  text_body:=new.statut||' · Référence '||left(new.id::text,8);
 elsif new.kind in ('professionnels','chauffeurs','boutiques','produits','services','vehicules') then
  recipients:=array_append(recipients,new.owner_id);
  label:='Suivi de votre activité';text_body:=new.statut||' · Consultez votre espace professionnel.';
  if new.statut='À valider' then
   admin_permission:=case when new.kind in ('chauffeurs','vehicules') then 'transport' else 'commerce' end;
   recipients:=recipients||coalesce((select array_agg(user_id) from public.koki_admin_members where enabled and role in ('superadmin','manager')),'{}'::uuid[]);
   label:='Dossier à valider';text_body:='Un dossier professionnel attend une validation.';
  end if;
 else return new;
 end if;
 insert into public.koki_notifications(recipient_id,record_id,revision,title,body,category)
 select distinct u,new.id,new.revision,label,text_body,new.kind from unnest(recipients) u where u is not null
 on conflict(recipient_id,record_id,revision) do nothing;
 return new;
end $$;
revoke all on function koki_private.notify_record() from public,anon,authenticated;
create trigger koki_notify_record after insert or update on public.koki_records for each row execute function koki_private.notify_record();

-- File serveur : aucun accès utilisateur. Une livraison réservée n'est jamais renvoyée automatiquement
-- après une interruption : cela évite les doubles SMS facturés en cas de résultat réseau incertain.
create table public.koki_notification_deliveries (
 id uuid primary key default gen_random_uuid(), notification_id uuid not null references public.koki_notifications(id) on delete cascade,
 channel text not null check(channel in ('push','sms')), destination text not null,
 state text not null default 'pending' check(state in ('pending','processing','sent','failed','skipped')),
 created_at timestamptz not null default now(), completed_at timestamptz, provider_id text,
 unique(notification_id,channel,destination)
);
alter table public.koki_notification_deliveries enable row level security;
revoke all on public.koki_notification_deliveries from public,anon,authenticated;
grant all on public.koki_notifications,public.koki_notification_deliveries,public.koki_push_subscriptions,public.koki_notification_preferences to service_role;
create function public.koki_notification_claim(p_push boolean,p_sms boolean) returns setof public.koki_notification_deliveries language plpgsql security definer set search_path='' as $$
begin
 -- Une invocation globale à la fois, y compris le calcul du plafond SMS.
 perform pg_advisory_xact_lock(hashtextextended('koki_notification_claim',0));
 if p_push then
  insert into public.koki_notification_deliveries(notification_id,channel,destination)
  select n.id,'push',s.id::text from public.koki_notifications n join public.koki_push_subscriptions s on s.user_id=n.recipient_id
  where n.created_at>now()-interval '1 day' and s.created_at<=n.created_at
  on conflict do nothing;
 end if;
 if p_sms then
  insert into public.koki_notification_deliveries(notification_id,channel,destination)
  select n.id,'sms',n.recipient_id::text from public.koki_notifications n join public.koki_notification_preferences p on p.user_id=n.recipient_id
  join auth.users u on u.id=n.recipient_id
  where n.created_at>now()-interval '1 day' and p.sms and p.updated_at<=n.created_at and u.phone_confirmed_at is not null and u.phone is not null
  on conflict do nothing;
 end if;
 -- Maximum 5 SMS/jour/compte. Les erreurs et résultats incertains comptent dans ce plafond.
 update public.koki_notification_deliveries d set state='skipped',completed_at=now()
 where d.id in (select id from (select id,row_number() over(partition by destination order by created_at,id) rank
 from public.koki_notification_deliveries where channel='sms' and created_at>=date_trunc('day',now())) x where rank>5) and d.state='pending';
 return query with batch as (
  select id from public.koki_notification_deliveries where state='pending' and created_at>now()-interval '1 day'
   and ((channel='push' and p_push) or (channel='sms' and p_sms)) order by created_at limit 20 for update skip locked
 ) update public.koki_notification_deliveries d set state='processing' from batch where d.id=batch.id returning d.*;
end $$;
revoke all on function public.koki_notification_claim(boolean,boolean) from public,anon,authenticated;
grant execute on function public.koki_notification_claim(boolean,boolean) to service_role;
commit;


-- ===== 12/37 : supabase/proposals/publication-interactions.sql · sha256 0138303e682b924a
-- Installation additive des interactions ; tables privées, aucun identifiant de compte exposé.
create schema if not exists koki_social_private;
revoke all on schema koki_social_private from public;
grant usage on schema koki_social_private to anon, authenticated;
create table koki_social_private.likes (
 content_id uuid not null references public.koki_contents(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 primary key(content_id,user_id)
);
create table koki_social_private.comments (
 id uuid primary key default gen_random_uuid(),
 content_id uuid not null references public.koki_contents(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default now()
);
create index on koki_social_private.comments(content_id,created_at desc,id);
create index on koki_social_private.comments(user_id,created_at desc);
alter table koki_social_private.likes enable row level security;
alter table koki_social_private.comments enable row level security;
revoke all on all tables in schema koki_social_private from public,anon,authenticated;
create function koki_social_private.interact(p_content uuid,p_action text,p_text text,p_comment uuid,p_liked boolean,p_offset integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if p_action is null or p_action not in ('read','like','comment','delete') then raise exception 'Action invalide'; end if;
 if p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'Page invalide'; end if;
 if not exists(select 1 from public.koki_contents where id=p_content and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))) then raise exception 'Publication indisponible'; end if;
 if p_action<>'read' then
  if uid is null or not exists(select 1 from auth.users where id=uid and not coalesce(is_anonymous,false)) then raise exception 'Connectez-vous pour participer' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,372));
 end if;
 if p_action='like' then
  if p_liked is null then raise exception 'Choix invalide'; end if;
  if p_liked then insert into koki_social_private.likes values(p_content,uid) on conflict do nothing;
  else delete from koki_social_private.likes where content_id=p_content and user_id=uid; end if;
 elsif p_action='comment' then
  if p_text is null or char_length(trim(p_text)) not between 1 and 2000 then raise exception 'Commentaire requis (2 000 caractères maximum)'; end if;
  if (select count(*) from koki_social_private.comments where user_id=uid and created_at>now()-interval '1 minute')>=5 or (select count(*) from koki_social_private.comments where user_id=uid and created_at>now()-interval '1 day')>=30 then raise exception 'Trop de commentaires. Réessayez plus tard.'; end if;
  insert into koki_social_private.comments(content_id,user_id,body) values(p_content,uid,trim(p_text));
 elsif p_action='delete' then
  delete from koki_social_private.comments where id=p_comment and content_id=p_content and user_id=uid;
 end if;
 select jsonb_build_object('likes',(select count(*) from koki_social_private.likes where content_id=p_content),
 'liked',exists(select 1 from koki_social_private.likes where content_id=p_content and user_id=uid),
 'total',(select count(*) from koki_social_private.comments where content_id=p_content),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'created_at',c.created_at,'mine',coalesce(c.user_id=uid,false)) order by c.created_at desc,c.id) from (select * from koki_social_private.comments where content_id=p_content order by created_at desc,id limit 30 offset p_offset)c),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function koki_social_private.interact(uuid,text,text,uuid,boolean,integer) from public;
grant execute on function koki_social_private.interact(uuid,text,text,uuid,boolean,integer) to anon,authenticated;
create function public.koki_content_social(p_content uuid,p_action text default 'read',p_text text default null,p_comment uuid default null,p_liked boolean default null,p_offset integer default 0)
returns jsonb language sql security invoker set search_path='' as $$
 select koki_social_private.interact(p_content,p_action,p_text,p_comment,p_liked,p_offset)
$$;
revoke all on function public.koki_content_social(uuid,text,text,uuid,boolean,integer) from public;
grant execute on function public.koki_content_social(uuid,text,text,uuid,boolean,integer) to anon,authenticated;


-- ===== 13/37 : supabase/proposals/audit-driver-availability.sql · sha256 d2e8f4ee8bd788fd
-- Indisponibilité sans autorisation GPS ; disponibilité avec position valide.
CREATE OR REPLACE FUNCTION koki_private.business(command text, input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 actor uuid:=auth.uid();key uuid;cached koki_private.business_keys;outcome jsonb;r public.koki_records;p public.koki_records;d public.koki_records;v public.koki_records;
 rate public.koki_transport_rates;entity_id uuid;entity_kind text;next_status text;profile text;distance numeric;total bigint:=0;qty integer;price bigint;line jsonb;items jsonb;
 steps text[];pos jsonb;phone text;quote koki_private.ride_quotes;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if command='catalog' then
   perform koki_private.business_keys_allowed(input,array[]::text[]);
   return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'parent_id',x.parent_id,'provider_id',x.provider_id,'nom',x.payload->>'nom','description',x.payload->>'description','categorie',x.payload->>'categorie','prix',x.payload->'prix','stock',x.payload->'stock','telephone',case when x.kind='professionnels' then x.payload->>'telephone' end,'adresse',case when x.kind='boutiques' then x.payload->>'adresse' end,'image_path',x.payload->>'image_path') order by x.updated_at desc) from
   (select listing.* from public.koki_records listing where (listing.kind='professionnels' and listing.statut='Actif')
    or (listing.kind='boutiques' and listing.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
    or (listing.kind='services' and listing.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.statut='Actif'))
    or (listing.kind='produits' and listing.statut='Disponible' and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=listing.parent_id and b.statut='Actif' and prof.statut='Actif'))
    order by listing.updated_at desc limit 200) x),'[]'::jsonb);
 end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if command in ('history','get') then
   perform koki_private.business_keys_allowed(input,case when command='history' then array['kind'] else array['id'] end);
   if command='get' then select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
     if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès refusé' using errcode='42501';end if;
     return to_jsonb(r)||jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i)) from public.koki_order_items i where i.order_id=r.id),'[]'::jsonb));
   end if;
   if input->>'kind' is null or input->>'kind' not in ('courses','commandes','demandes_services') then raise exception 'Historique invalide';end if;
   return coalesce((select jsonb_agg(to_jsonb(x)) from (select hist.* from public.koki_records hist where hist.kind=input->>'kind' and coalesce(koki_private.business_can_read(hist),false) order by hist.created_at desc limit 100)x),'[]'::jsonb);
 end if;
 if command='ride_contacts' then
   perform koki_private.business_keys_allowed(input,array['id']);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind is distinct from 'courses' or not coalesce(koki_private.business_can_read(r),false) or r.statut not in ('Acceptée','Chauffeur en route','Course en cours') then raise exception 'Contacts réservés à une course acceptée active' using errcode='42501';end if;
   select * into d from public.koki_records where public.koki_records.id=r.driver_id;
   return jsonb_build_object('name',d.payload->>'nom','phone',d.payload->>'telephone');
 end if;
 if command='quote' then
   perform koki_private.business_keys_allowed(input,array['category','start','end']);
   distance:=koki_private.business_distance(input->'start',input->'end');
   if distance<.05 or distance>200 then raise exception 'Trajet entre 50 mètres et 200 km requis';end if;
   select * into rate from public.koki_transport_rates where category=input->>'category' and active;
   if rate.category is null then raise exception 'Tarif validé indisponible';end if;
   insert into koki_private.ride_quotes(client_id,category,start_point,end_point,distance_km,fare_fcfa)
   values(actor,rate.category,jsonb_build_object('latitude',input->'start'->'latitude','longitude',input->'start'->'longitude'),jsonb_build_object('latitude',input->'end'->'latitude','longitude',input->'end'->'longitude'),distance,ceil((rate.base_fcfa+distance*rate.per_km_fcfa)/50)*50) returning * into quote;
   return jsonb_build_object('quote_id',quote.id,'expires_at',quote.expires_at,'distance_km',round(distance,3),'fare_fcfa',quote.fare_fcfa,'method','À vol d’oiseau','indicative',true);
 end if;
 if command='nearby_drivers' then
   perform koki_private.business_keys_allowed(input,array['category','start']);
   if not koki_private.business_point(input->'start') or input->>'category' is null or input->>'category' not in ('Moto','Taxi','Voiture','Minicar') then raise exception 'Recherche invalide';end if;
   -- 10 recherches par minute et 60 par heure ; distance calculée sur une position arrondie (~500 m),
   -- sinon la frontière des 10 km permettrait de trianguler la position exacte du chauffeur.
   perform pg_advisory_xact_lock(hashtextextended('nearby:'||actor::text,0));
   if (select count(*) from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at>now()-interval '1 minute')>=10
    or (select count(*) from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at>now()-interval '1 hour')>=60 then
     raise exception 'Trop de recherches. Patientez quelques minutes.';end if;
   delete from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at<now()-interval '1 day';
   insert into koki_private.nearby_lookups(actor_id) values(actor);
   return coalesce((select jsonb_agg(jsonb_build_object('driver_id',x.driver_id,'vehicle_id',x.vehicle_id,'name',x.name,'category',x.category,'proximity','À proximité (moins de 10 km)')) from
   (select drv.id driver_id,veh.id vehicle_id,drv.payload->>'nom' name,veh.payload->>'categorie' category from public.koki_records drv join public.koki_records veh on veh.parent_id=drv.id and veh.kind='vehicules' and veh.statut='Actif'
   where drv.kind='chauffeurs' and drv.statut='Disponible' and veh.payload->>'categorie'=input->>'category'
    and (drv.payload->>'position_updated_at')::timestamptz>now()-interval '15 minutes'
    and koki_private.business_point(drv.payload->'position') and koki_private.business_distance(input->'start',jsonb_build_object('latitude',round((drv.payload->'position'->>'latitude')::numeric/0.005)*0.005,'longitude',round((drv.payload->'position'->>'longitude')::numeric/0.005)*0.005))<=10 and drv.owner_id<>actor
    and not exists(select 1 from public.koki_records c where c.kind='courses' and c.driver_id=drv.id and c.statut in ('En attente','Acceptée','Chauffeur en route','Course en cours'))
    order by drv.id,veh.id limit 30)x),'[]'::jsonb);
 end if;
 -- Idempotence acteur/clé ; verrou avant toute mutation pour courses/commandes/reprises réseau.
 key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
 select * into cached from koki_private.business_keys k where k.actor_id=actor and k.request_id=key;
 if found then
  if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;
  if cached.output ? 'id' then
    select * into r from public.koki_records where public.koki_records.id=(cached.output->>'id')::uuid;
    if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès révoqué' using errcode='42501';end if;
  elsif command='set_rate' and not koki_private.allowed('transport') then raise exception 'Administration et MFA requises' using errcode='42501';end if;
  return cached.output;
 end if;
 if command in ('register_driver','register_professional') then
   perform koki_private.business_keys_allowed(input,array['request_id','name','phone','profile','description','zone']);
   phone:=koki_private.business_text(input,'phone',8,16);if phone!~'^\+[1-9][0-9]{7,14}$' then raise exception 'Téléphone international invalide';end if;
   entity_kind:=case when command='register_driver' then 'chauffeurs' else 'professionnels' end;
   if exists(select 1 from public.koki_records where owner_id=actor and public.koki_records.kind=entity_kind) then raise exception 'Profil déjà inscrit';end if;
   profile:=input->>'profile';if entity_kind='professionnels' and (profile is null or profile not in ('Commerçant','Prestataire de services','Les deux')) then raise exception 'Profil professionnel invalide';end if;
   insert into public.koki_records(kind,statut,owner_id,payload) values(entity_kind,'À valider',actor,jsonb_strip_nulls(jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'telephone',phone,'type',case when entity_kind='professionnels' then profile end,'description',left(coalesce(input->>'description',''),2000),'zone',left(coalesce(input->>'zone',''),180)))) returning * into r;
 elsif command='admin_review' then
   perform koki_private.business_keys_allowed(input,array['request_id','id','decision']);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind in ('professionnels','boutiques','produits','services') then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.id is null or r.kind not in ('chauffeurs','professionnels','vehicules','boutiques','produits','services') or not koki_private.allowed(case when r.kind in ('chauffeurs','vehicules') then 'transport' else 'commerce' end) then raise exception 'Administration autorisée et MFA requises' using errcode='42501';end if;
   next_status:=case input->>'decision' when 'approve' then case r.kind when 'chauffeurs' then 'Indisponible' when 'vehicules' then 'Actif' when 'produits' then 'Disponible' when 'services' then 'Disponible' else 'Actif' end when 'suspend' then case r.kind when 'vehicules' then 'Indisponible' when 'boutiques' then 'Fermé' when 'produits' then 'Masqué' when 'services' then 'Masqué' else 'Suspendu' end end;
   if next_status is null then raise exception 'Décision invalide';end if;
   update public.koki_records set statut=next_status where public.koki_records.id=r.id returning * into r;
 elsif command='set_rate' then
   perform koki_private.business_keys_allowed(input,array['request_id','category','base_fcfa','per_km_fcfa','active']);
   if not koki_private.allowed('transport') then raise exception 'Administration Transport et MFA requises' using errcode='42501';end if;
   if jsonb_typeof(input->'base_fcfa') is distinct from 'number' or jsonb_typeof(input->'per_km_fcfa') is distinct from 'number' or jsonb_typeof(input->'active') is distinct from 'boolean' or (input->>'base_fcfa')::numeric<>trunc((input->>'base_fcfa')::numeric) or (input->>'per_km_fcfa')::numeric<>trunc((input->>'per_km_fcfa')::numeric) then raise exception 'Tarif invalide';end if;
   insert into public.koki_transport_rates(category,base_fcfa,per_km_fcfa,active) values(input->>'category',(input->>'base_fcfa')::integer,(input->>'per_km_fcfa')::integer,(input->>'active')::boolean)
   on conflict(category) do update set base_fcfa=excluded.base_fcfa,per_km_fcfa=excluded.per_km_fcfa,active=excluded.active,updated_at=clock_timestamp() returning * into rate;
   insert into public.koki_audit(actor_id,operation,table_name,record_id,details) values(actor,'UPSERT','koki_transport_rates',gen_random_uuid(),jsonb_build_object('category',rate.category));
   outcome:=to_jsonb(rate);
 elsif command in ('save_vehicle','save_shop','save_product','save_service') then
   perform koki_private.business_keys_allowed(input,array['request_id','id','revision','parent_id','name','description','category','price','stock','registration','address','image_path']);
   entity_kind:=case command when 'save_vehicle' then 'vehicules' when 'save_shop' then 'boutiques' when 'save_product' then 'produits' else 'services' end;
   if entity_kind<>'vehicules' then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'parent_id')::uuid for update;
   if p.id is null or p.owner_id is distinct from actor then raise exception 'Propriétaire requis' using errcode='42501';end if;
   if entity_kind='vehicules' and (p.kind<>'chauffeurs' or p.statut not in ('Disponible','Indisponible','À valider')) then raise exception 'Chauffeur indisponible';end if;
   if entity_kind in ('boutiques','services') and (p.kind<>'professionnels' or p.statut<>'Actif' or p.payload->>'type' not in (case when entity_kind='boutiques' then 'Commerçant' else 'Prestataire de services' end,'Les deux')) then raise exception 'Profil professionnel incompatible';end if;
   if entity_kind='produits' then
     select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
     if p.kind<>'boutiques' or p.statut<>'Actif' or d.statut<>'Actif' or d.payload->>'type' not in ('Commerçant','Les deux') then raise exception 'Boutique indisponible';end if;
   end if;
   if entity_kind in ('produits','services') and input ? 'price' and input->'price'<>'null'::jsonb then
     if jsonb_typeof(input->'price') is distinct from 'number' or (input->>'price')::numeric<>trunc((input->>'price')::numeric) or (input->>'price')::numeric not between 0 and 1000000000 then raise exception 'Prix catalogue invalide';end if;
   elsif entity_kind='produits' then raise exception 'Prix produit obligatoire';end if;
   if entity_kind='produits' and (jsonb_typeof(input->'stock') is distinct from 'number' or (input->>'stock')::numeric<>trunc((input->>'stock')::numeric) or (input->>'stock')::numeric not between 0 and 1000000) then raise exception 'Stock invalide';end if;
   if entity_kind='vehicules' and (input->>'category' is null or input->>'category' is null or input->>'category' not in ('Moto','Taxi','Voiture','Minicar')) then raise exception 'Catégorie véhicule invalide';end if;
   if not coalesce(koki_private.business_owned_image(input->>'image_path'),false) then raise exception 'Média propriétaire invalide';end if;
   entity_id:=(input->>'id')::uuid;
   if entity_id is not null then select * into r from public.koki_records where public.koki_records.id=entity_id for update;
     if r.id is null or r.owner_id is distinct from actor or r.kind<>entity_kind or r.parent_id<>p.id then raise exception 'Élément inaccessible' using errcode='42501';end if;
     if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
     if entity_kind='vehicules' and exists(select 1 from public.koki_records active_course where active_course.kind='courses' and active_course.parent_id=r.id and active_course.statut in ('En attente','Acceptée','Chauffeur en route','Course en cours')) then raise exception 'Véhicule lié à une course active';end if;
   end if;
   pos:=jsonb_strip_nulls(jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'description',left(coalesce(input->>'description',''),2000),'categorie',input->>'category','prix',input->'price','stock',case when entity_kind='produits' then input->'stock' end,'immatriculation',input->>'registration','adresse',input->>'address','image_path',input->>'image_path'));
   next_status:=case entity_kind when 'vehicules' then 'Indisponible' when 'boutiques' then 'Actif' else 'Disponible' end;
   if entity_id is null then insert into public.koki_records(kind,statut,owner_id,parent_id,payload) values(entity_kind,next_status,actor,p.id,pos) returning * into r;
   else update public.koki_records set payload=pos,statut=case when entity_kind='vehicules' then 'Indisponible' else statut end where public.koki_records.id=entity_id returning * into r;end if;
 elsif command='driver_position' then
   perform koki_private.business_keys_allowed(input,array['request_id','position','available']);
   if jsonb_typeof(input->'available') is distinct from 'boolean' or ((input->>'available')::boolean and not koki_private.business_point(input->'position')) then raise exception 'Position/disponibilité invalide';end if;
   select * into r from public.koki_records where owner_id=actor and public.koki_records.kind='chauffeurs' for update;
   if r.id is null or r.statut not in ('Disponible','Indisponible') then raise exception 'Chauffeur validé requis' using errcode='42501';end if;
   update public.koki_records set statut=case when (input->>'available')::boolean then 'Disponible' else 'Indisponible' end,
   payload=payload||case when (input->>'available')::boolean then jsonb_build_object('position',jsonb_build_object('latitude',input->'position'->'latitude','longitude',input->'position'->'longitude'),'position_updated_at',clock_timestamp()) else '{}'::jsonb end where public.koki_records.id=r.id returning * into r;
 elsif command='reserve_ride' then
   perform koki_private.business_keys_allowed(input,array['request_id','vehicle_id','quote_id']);
   -- Ordre uniforme : client puis chauffeur, véhicule, grille. L'index unique est une seconde barrière.
   perform pg_advisory_xact_lock(hashtextextended('ride-client:'||actor::text,0));
   select * into quote from koki_private.ride_quotes q where q.id=(input->>'quote_id')::uuid and q.client_id=actor for update;
   if quote.id is null or quote.expires_at<=now() or quote.ride_id is not null then raise exception 'Devis expiré ou indisponible';end if;
   select * into v from public.koki_records where public.koki_records.id=(input->>'vehicle_id')::uuid;
   if v.id is null or v.kind<>'vehicules' then raise exception 'Véhicule indisponible';end if;
   select * into d from public.koki_records where public.koki_records.id=v.parent_id for update;
   select * into v from public.koki_records where public.koki_records.id=v.id for update;
   if d.statut<>'Disponible' or v.statut<>'Actif' or (d.payload->>'position_updated_at')::timestamptz is null or (d.payload->>'position_updated_at')::timestamptz<now()-interval '15 minutes' then raise exception 'Chauffeur indisponible';end if;
   if not koki_private.business_point(d.payload->'position') or koki_private.business_distance(quote.start_point,d.payload->'position')>10 then raise exception 'Chauffeur hors proximité';end if;
   if exists(select 1 from public.koki_records where public.koki_records.kind='courses' and (driver_id=d.id or client_id=actor) and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours')) then raise exception 'Une course est déjà active';end if;
   if v.payload->>'categorie' is distinct from quote.category then raise exception 'Catégorie incompatible avec le devis';end if;
   select * into rate from public.koki_transport_rates where category=quote.category and active for share;
   if rate.category is null then raise exception 'Tarif validé indisponible';end if;
   insert into public.koki_records(kind,statut,client_id,parent_id,driver_id,payload) values('courses','En attente',actor,v.id,d.id,jsonb_build_object('nom','Course','depart',quote.start_point,'destination',quote.end_point,'distance',round(quote.distance_km,3),'tarif',quote.fare_fcfa,'categorie',quote.category,'methode','À vol d’oiseau')) returning * into r;
   update koki_private.ride_quotes set ride_id=r.id where koki_private.ride_quotes.id=quote.id;
 elsif command='create_order' then
   perform koki_private.business_keys_allowed(input,array['request_id','shop_id','items','mode','address']);
   if input->>'mode' is null or input->>'mode' not in ('retrait','livraison') then raise exception 'Réception invalide';end if;
   if input->>'mode'='livraison' then perform koki_private.business_text(input,'address',3,500);end if;
   items:=input->'items';if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 50 then raise exception 'Panier invalide';end if;
   if (select count(*) from jsonb_array_elements(items))<>(select count(distinct value->>'product_id') from jsonb_array_elements(items)) then raise exception 'Produits dupliqués';end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'shop_id')::uuid;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'shop_id')::uuid for update;
   select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
   if p.kind is distinct from 'boutiques' or p.statut<>'Actif' or d.kind is distinct from 'professionnels' or d.statut<>'Actif' or d.payload->>'type' not in ('Commerçant','Les deux') then raise exception 'Boutique indisponible';end if;
   -- Verrouillage déterministe. Toutes les lignes partagent une seule boutique ; panier multi-vendeur à séparer.
   for line in select value from jsonb_array_elements(items) order by value->>'product_id' loop
     perform koki_private.business_keys_allowed(line,array['product_id','quantity']);
     if jsonb_typeof(line->'quantity') is distinct from 'number' or (line->>'quantity')::numeric<>trunc((line->>'quantity')::numeric) or (line->>'quantity')::numeric not between 1 and 10000 then raise exception 'Quantité invalide';end if;qty:=(line->>'quantity')::integer;
     select * into r from public.koki_records where public.koki_records.id=(line->>'product_id')::uuid for update;
     if r.kind is distinct from 'produits' or r.parent_id<>p.id or r.statut<>'Disponible' or (r.payload->>'stock')::integer<qty then raise exception 'Produit indisponible ou stock insuffisant';end if;
     price:=(r.payload->>'prix')::bigint;if price is null or price<0 then raise exception 'Prix catalogue invalide';end if;
     total:=total+price*qty;
   end loop;
   insert into public.koki_records(kind,statut,client_id,parent_id,provider_id,payload) values('commandes','Commande reçue',actor,p.id,d.id,jsonb_build_object('nom','Commande','total',total,'mode',input->>'mode','adresse',case when input->>'mode'='livraison' then input->>'address' else null end,'currency','FCFA')) returning public.koki_records.id into entity_id;
   for line in select value from jsonb_array_elements(items) order by value->>'product_id' loop
     select * into r from public.koki_records where public.koki_records.id=(line->>'product_id')::uuid;qty:=(line->>'quantity')::integer;
     insert into public.koki_order_items(order_id,product_id,quantity,unit_price,product_name) values(entity_id,r.id,qty,(r.payload->>'prix')::bigint,r.payload->>'nom');
     update public.koki_records set payload=jsonb_set(payload,'{stock}',to_jsonb((payload->>'stock')::integer-qty)) where public.koki_records.id=r.id;
   end loop;
   select * into r from public.koki_records where public.koki_records.id=entity_id;
 elsif command='request_service' then
   perform koki_private.business_keys_allowed(input,array['request_id','service_id','need','address','date','image_path']);
   select * into p from public.koki_records where public.koki_records.id=(input->>'service_id')::uuid;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'service_id')::uuid for update;
   select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
   if p.kind is distinct from 'services' or p.statut<>'Disponible' or d.statut<>'Actif' or d.payload->>'type' not in ('Prestataire de services','Les deux') then raise exception 'Prestataire indisponible';end if;
   if not coalesce(koki_private.business_owned_image(input->>'image_path'),false) then raise exception 'Média propriétaire invalide';end if;
   if input->>'date' is null or input->>'date' !~ '^\d{4}-\d{2}-\d{2}$' or (input->>'date')::date is null or (input->>'date')::date<current_date then raise exception 'Date invalide';end if;
   insert into public.koki_records(kind,statut,client_id,parent_id,provider_id,payload) values('demandes_services','Demande envoyée',actor,p.id,d.id,jsonb_build_object('nom','Demande de devis','besoin',koki_private.business_text(input,'need',10,2000),'lieu',koki_private.business_text(input,'address',3,500),'date',(input->>'date')::date,'catalogue_price',p.payload->'prix','image_path',input->>'image_path')) returning * into r;
 elsif command in ('submit_service_quote','accept_service_quote') then
   perform koki_private.business_keys_allowed(input,case when command='submit_service_quote' then array['request_id','id','revision','amount_fcfa','description'] else array['request_id','id','revision'] end);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   select * into p from public.koki_records where public.koki_records.id=r.provider_id;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.kind is distinct from 'demandes_services' or r.statut<>'Demande envoyée' or (input->>'revision')::integer is distinct from r.revision then raise exception 'Demande ou révision indisponible';end if;
   if command='submit_service_quote' then
     if not coalesce(koki_private.owns_business(r.provider_id),false) and not koki_private.allowed('commerce') then raise exception 'Prestataire assigné requis' using errcode='42501';end if;
     if jsonb_typeof(input->'amount_fcfa') is distinct from 'number' or (input->>'amount_fcfa')::numeric not between 0 and 1000000000 or (input->>'amount_fcfa')::numeric<>trunc((input->>'amount_fcfa')::numeric) then raise exception 'Montant de devis invalide';end if;
     update public.koki_records set payload=payload||jsonb_build_object('quote_fcfa',(input->>'amount_fcfa')::bigint,'quote_text',koki_private.business_text(input,'description',1,2000),'quote_expires_at',now()+interval '7 days','quote_client_accepted',false) where public.koki_records.id=r.id returning * into r;
   else
     if r.client_id is distinct from actor then raise exception 'Client propriétaire requis' using errcode='42501';end if;
     if r.payload->>'quote_fcfa' is null or r.payload->>'quote_expires_at' is null or (r.payload->>'quote_expires_at')::timestamptz<=now() or not exists(select 1 from public.koki_records pro where pro.id=r.provider_id and pro.statut='Actif') then raise exception 'Devis expiré ou prestataire indisponible';end if;
     update public.koki_records set statut='Acceptée',payload=payload||jsonb_build_object('quote_client_accepted',true) where public.koki_records.id=r.id returning * into r;
   end if;
 elsif command='transition' then
   perform koki_private.business_keys_allowed(input,array['request_id','id','next','revision']);
   -- Verrouiller boutique/pro avant commande : ordre compatible avec create_order et restitution.
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind in ('commandes','demandes_services') then select * into p from public.koki_records where public.koki_records.id=r.provider_id;perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   if r.kind='commandes' then perform 1 from public.koki_records where public.koki_records.id=r.parent_id for update;perform 1 from public.koki_records where public.koki_records.id=r.provider_id for update;end if;
   if r.kind='courses' then select * into d from public.koki_records where public.koki_records.id=r.driver_id for update;end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.id is null or not coalesce(koki_private.business_can_read(r),false) or r.kind not in ('courses','commandes','demandes_services') then raise exception 'Accès refusé' using errcode='42501';end if;
   if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   next_status:=input->>'next';
   if next_status='Annulée' then
     if r.statut not in ('En attente','Acceptée','Commande reçue','Confirmée','Demande envoyée') then raise exception 'Annulation non autorisée à cette étape';end if;
     if r.client_id is distinct from actor and not coalesce(koki_private.owns_business(r.provider_id),false) and not coalesce(koki_private.owns_business(r.driver_id),false) and not koki_private.allowed(case when r.kind='courses' then 'transport' else 'commerce' end) then raise exception 'Annulation refusée' using errcode='42501';end if;
   else
     if r.kind='courses' then
       if not coalesce(koki_private.owns_business(r.driver_id),false) and not koki_private.allowed('transport') then raise exception 'Chauffeur assigné requis' using errcode='42501';end if;
       if next_status='Acceptée' and (d.statut<>'Disponible' or not exists(select 1 from public.koki_records accepted_vehicle where accepted_vehicle.id=r.parent_id and accepted_vehicle.statut='Actif')) then raise exception 'Chauffeur/véhicule indisponible';end if;
       steps:=array['En attente','Acceptée','Chauffeur en route','Course en cours','Terminée'];
     else
       if not coalesce(koki_private.owns_business(r.provider_id),false) and not koki_private.allowed('commerce') then raise exception 'Professionnel assigné requis' using errcode='42501';end if;
       if r.kind='demandes_services' and next_status='Acceptée' and (r.payload->>'quote_fcfa' is not null or r.payload->>'catalogue_price' is null) and not coalesce((r.payload->>'quote_client_accepted')::boolean,false) then raise exception 'Acceptation du devis par le client requise';end if;
       steps:=case when r.kind='commandes' then case when r.payload->>'mode'='retrait' then array['Commande reçue','Confirmée','Préparation','Prête au retrait','Retirée'] else array['Commande reçue','Confirmée','Préparation','En livraison','Livrée'] end else array['Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé'] end;
     end if;
     if next_status is null or next_status is distinct from steps[array_position(steps,r.statut)+1] then raise exception 'Transition invalide';end if;
   end if;
   if r.kind='commandes' and next_status='Annulée' then
     for line in select to_jsonb(i) from public.koki_order_items i where order_id=r.id order by product_id loop
       update public.koki_records set payload=jsonb_set(payload,'{stock}',to_jsonb((payload->>'stock')::integer+(line->>'quantity')::integer)) where public.koki_records.id=(line->>'product_id')::uuid;
     end loop;
   end if;
   update public.koki_records set statut=next_status where public.koki_records.id=r.id returning * into r;
 else raise exception 'Commande inconnue';
 end if;
 if outcome is null then outcome:=to_jsonb(r);end if;
 insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,outcome);
 return outcome;
end $function$
;


-- ===== 14/37 : supabase/proposals/audit-indexes-tracking.sql · sha256 ee1e2e193766769b
-- Index des clés étrangères utilisées pour les suppressions et les jointures.
create index if not exists audit_ride_quotes_category on koki_private.ride_quotes(category);
create index if not exists audit_ride_quotes_client on koki_private.ride_quotes(client_id);
create index if not exists audit_ride_quotes_ride on koki_private.ride_quotes(ride_id);
create index if not exists audit_ride_ratings_client on koki_private.ride_ratings(client_id);
create index if not exists audit_ride_reports_reporter on koki_private.ride_reports(reporter_id);
create index if not exists audit_ride_reports_ride on koki_private.ride_reports(ride_id);
create index if not exists audit_ride_reports_moderator on koki_private.ride_reports(traite_par);
create index if not exists audit_social_likes_user on koki_social_private.likes(user_id);
create index if not exists audit_notifications_record on public.koki_notifications(record_id);
create index if not exists audit_push_user on public.koki_push_subscriptions(user_id);
alter table koki_private.nearby_lookups add column id bigint generated always as identity primary key;
-- Compteurs indicatifs : une action par compte/cible/type/jour. Aucun suivi anonyme ni IP.
create table koki_private.activity_dedup(actor_id uuid not null references auth.users(id) on delete cascade,target_id uuid not null references public.koki_records(id) on delete cascade,kind text not null,day date not null,primary key(actor_id,target_id,kind,day));
create index on koki_private.activity_dedup(target_id);
alter table koki_private.activity_dedup enable row level security;
revoke all on koki_private.activity_dedup from public,anon,authenticated;
create function koki_private.track(p_target uuid,p_kind text) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and not coalesce(is_anonymous,false)) then return;end if;
 if p_target is null or p_kind is null or p_kind not in ('vue','appel','whatsapp','commander','partage','panier','devis') or not koki_private.is_public_listing(p_target) then return;end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,916));
 delete from koki_private.activity_dedup where actor_id=uid and day<current_date;
 if (select count(*) from koki_private.activity_dedup where actor_id=uid and day=current_date)>=200 then return;end if;
 insert into koki_private.activity_dedup values(uid,p_target,p_kind,current_date) on conflict do nothing;
 if not found then return;end if;
 insert into public.koki_activity(target_id,kind,day,n) values(p_target,p_kind,current_date,1) on conflict(target_id,kind,day) do update set n=least(public.koki_activity.n+1,1000000);
end $$;
revoke all on function koki_private.track(uuid,text) from public;
grant execute on function koki_private.track(uuid,text) to anon,authenticated;
create or replace function public.koki_track(p_target uuid,p_kind text) returns void language sql security invoker set search_path='' as $$select koki_private.track(p_target,p_kind)$$;


-- ===== 15/37 : supabase/proposals/audit-notification-health.sql · sha256 9e85223521a33f30
-- Aucun renvoi automatique des envois dont le résultat est incertain.
alter table public.koki_notification_deliveries add column processing_started_at timestamptz,add column failure_code text;
update public.koki_notification_deliveries set processing_started_at=now() where state='processing';
CREATE OR REPLACE FUNCTION public.koki_notification_claim(p_push boolean, p_sms boolean)
 RETURNS SETOF koki_notification_deliveries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 -- Une invocation globale à la fois, y compris le calcul du plafond SMS.
 perform pg_advisory_xact_lock(hashtextextended('koki_notification_claim',0));
 update public.koki_notification_deliveries set state='failed',failure_code='delivery_unknown',completed_at=now() where state='processing' and processing_started_at<now()-interval '10 minutes';
 update public.koki_notification_deliveries set state='skipped',failure_code='expired',completed_at=now() where state='pending' and created_at<=now()-interval '1 day';
 if p_push then
  insert into public.koki_notification_deliveries(notification_id,channel,destination)
  select n.id,'push',s.id::text from public.koki_notifications n join public.koki_push_subscriptions s on s.user_id=n.recipient_id
  where n.created_at>now()-interval '1 day' and s.created_at<=n.created_at
  on conflict do nothing;
 end if;
 if p_sms then
  insert into public.koki_notification_deliveries(notification_id,channel,destination)
  select n.id,'sms',n.recipient_id::text from public.koki_notifications n join public.koki_notification_preferences p on p.user_id=n.recipient_id
  join auth.users u on u.id=n.recipient_id
  where n.created_at>now()-interval '1 day' and p.sms and p.updated_at<=n.created_at and u.phone_confirmed_at is not null and u.phone is not null
  on conflict do nothing;
 end if;
 -- Maximum 5 SMS/jour/compte. Les erreurs et résultats incertains comptent dans ce plafond.
 update public.koki_notification_deliveries d set state='skipped',completed_at=now()
 where d.id in (select id from (select id,row_number() over(partition by destination order by created_at,id) rank
 from public.koki_notification_deliveries where channel='sms' and created_at>=date_trunc('day',now())) x where rank>5) and d.state='pending';
 return query with batch as (
  select id from public.koki_notification_deliveries where state='pending' and created_at>now()-interval '1 day'
   and ((channel='push' and p_push) or (channel='sms' and p_sms)) order by created_at limit 20 for update skip locked
 ) update public.koki_notification_deliveries d set state='processing',processing_started_at=now() from batch where d.id=batch.id returning d.*;
end $function$
;

create function koki_private.notification_health() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(koki_private.allowed('audit'),false) then raise exception 'Accès refusé' using errcode='42501';end if;
 return jsonb_build_object('counts',(select coalesce(jsonb_object_agg(state,n),'{}'::jsonb) from (select state,count(*) as n from public.koki_notification_deliveries where created_at>now()-interval '7 days' group by state)x),'oldest_pending',(select min(created_at) from public.koki_notification_deliveries where state='pending'),'recent',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select id,channel,state,created_at,completed_at,failure_code from public.koki_notification_deliveries order by created_at desc limit 50)x));
end $$;
revoke all on function koki_private.notification_health() from public,anon;
grant execute on function koki_private.notification_health() to authenticated;
create function public.koki_notification_health() returns jsonb language sql security invoker set search_path='' as $$select koki_private.notification_health()$$;
revoke all on function public.koki_notification_health() from public,anon;
grant execute on function public.koki_notification_health() to authenticated;


-- ===== 16/37 : supabase/proposals/audit-notification-policy.sql · sha256 8f406212a58efbaa
-- Évaluer les claims une fois par requête, sans modifier les droits.
alter policy notification_preferences_own on public.koki_notification_preferences using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()) and not coalesce(((select auth.jwt())->>'is_anonymous')::boolean,false));


-- ===== 17/37 : supabase/proposals/publication-feed-pages.sql · sha256 9ebf0cbc508e543e
-- Lecture bornée par page ; le texte des fiches structurées reste intact.
create function public.koki_public_feed(p_offset integer) returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'Page invalide';end if;
 return (with page as (select id,type,titre,resume,case when type in ('Actualités','Annonces','Publicités') then null else texte end as texte,type in ('Actualités','Annonces','Publicités') as detail_required,categorie,statut,publication,source,lieu,evenement,image_path,une,actif,emplacement,fin from public.koki_contents where statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now()))) order by publication desc,id desc limit 101 offset p_offset),items as (select * from page order by publication desc,id desc limit 100) select jsonb_build_object('version',1,'more',(select count(*)>100 from page),'contenus',coalesce((select jsonb_agg(to_jsonb(items) order by publication desc,id desc) from items),'[]'::jsonb)));
end $$;
revoke all on function public.koki_public_feed(integer) from public;
grant execute on function public.koki_public_feed(integer) to anon,authenticated;
create function public.koki_public_content(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',id,'texte',texte,'image_path',image_path) from public.koki_contents where id=p_id and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))
$$;
revoke all on function public.koki_public_content(uuid) from public;
grant execute on function public.koki_public_content(uuid) to anon,authenticated;


-- ===== 18/37 : supabase/proposals/professional-driver-registration.sql · sha256 d7b3dde5c18c2da0
-- Indisponibilité sans autorisation GPS ; disponibilité avec position valide.
CREATE OR REPLACE FUNCTION koki_private.business(command text, input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 actor uuid:=auth.uid();key uuid;cached koki_private.business_keys;outcome jsonb;r public.koki_records;p public.koki_records;d public.koki_records;v public.koki_records;
 rate public.koki_transport_rates;entity_id uuid;entity_kind text;next_status text;profile text;distance numeric;total bigint:=0;qty integer;price bigint;line jsonb;items jsonb;
 steps text[];pos jsonb;phone text;quote koki_private.ride_quotes;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse';end if;
 if command='catalog' then
   perform koki_private.business_keys_allowed(input,array[]::text[]);
   return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'parent_id',x.parent_id,'provider_id',x.provider_id,'nom',x.payload->>'nom','description',x.payload->>'description','categorie',x.payload->>'categorie','prix',x.payload->'prix','stock',x.payload->'stock','telephone',case when x.kind='professionnels' then x.payload->>'telephone' end,'adresse',case when x.kind='boutiques' then x.payload->>'adresse' end,'image_path',x.payload->>'image_path') order by x.updated_at desc) from
   (select listing.* from public.koki_records listing where (listing.kind='professionnels' and listing.statut='Actif')
    or (listing.kind='boutiques' and listing.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
    or (listing.kind='services' and listing.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.statut='Actif'))
    or (listing.kind='produits' and listing.statut='Disponible' and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=listing.parent_id and b.statut='Actif' and prof.statut='Actif'))
    order by listing.updated_at desc limit 200) x),'[]'::jsonb);
 end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if command in ('history','get') then
   perform koki_private.business_keys_allowed(input,case when command='history' then array['kind'] else array['id'] end);
   if command='get' then select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
     if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès refusé' using errcode='42501';end if;
     return to_jsonb(r)||jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i)) from public.koki_order_items i where i.order_id=r.id),'[]'::jsonb));
   end if;
   if input->>'kind' is null or input->>'kind' not in ('courses','commandes','demandes_services') then raise exception 'Historique invalide';end if;
   return coalesce((select jsonb_agg(to_jsonb(x)) from (select hist.* from public.koki_records hist where hist.kind=input->>'kind' and coalesce(koki_private.business_can_read(hist),false) order by hist.created_at desc limit 100)x),'[]'::jsonb);
 end if;
 if command='ride_contacts' then
   perform koki_private.business_keys_allowed(input,array['id']);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind is distinct from 'courses' or not coalesce(koki_private.business_can_read(r),false) or r.statut not in ('Acceptée','Chauffeur en route','Course en cours') then raise exception 'Contacts réservés à une course acceptée active' using errcode='42501';end if;
   select * into d from public.koki_records where public.koki_records.id=r.driver_id;
   return jsonb_build_object('name',d.payload->>'nom','phone',d.payload->>'telephone');
 end if;
 if command='quote' then
   perform koki_private.business_keys_allowed(input,array['category','start','end']);
   distance:=koki_private.business_distance(input->'start',input->'end');
   if distance<.05 or distance>200 then raise exception 'Trajet entre 50 mètres et 200 km requis';end if;
   select * into rate from public.koki_transport_rates where category=input->>'category' and active;
   if rate.category is null then raise exception 'Tarif validé indisponible';end if;
   insert into koki_private.ride_quotes(client_id,category,start_point,end_point,distance_km,fare_fcfa)
   values(actor,rate.category,jsonb_build_object('latitude',input->'start'->'latitude','longitude',input->'start'->'longitude'),jsonb_build_object('latitude',input->'end'->'latitude','longitude',input->'end'->'longitude'),distance,ceil((rate.base_fcfa+distance*rate.per_km_fcfa)/50)*50) returning * into quote;
   return jsonb_build_object('quote_id',quote.id,'expires_at',quote.expires_at,'distance_km',round(distance,3),'fare_fcfa',quote.fare_fcfa,'method','À vol d’oiseau','indicative',true);
 end if;
 if command='nearby_drivers' then
   perform koki_private.business_keys_allowed(input,array['category','start']);
   if not koki_private.business_point(input->'start') or input->>'category' is null or input->>'category' not in ('Moto','Taxi','Voiture','Minicar') then raise exception 'Recherche invalide';end if;
   -- 10 recherches par minute et 60 par heure ; distance calculée sur une position arrondie (~500 m),
   -- sinon la frontière des 10 km permettrait de trianguler la position exacte du chauffeur.
   perform pg_advisory_xact_lock(hashtextextended('nearby:'||actor::text,0));
   if (select count(*) from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at>now()-interval '1 minute')>=10
    or (select count(*) from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at>now()-interval '1 hour')>=60 then
     raise exception 'Trop de recherches. Patientez quelques minutes.';end if;
   delete from koki_private.nearby_lookups l where l.actor_id=actor and l.created_at<now()-interval '1 day';
   insert into koki_private.nearby_lookups(actor_id) values(actor);
   return coalesce((select jsonb_agg(jsonb_build_object('driver_id',x.driver_id,'vehicle_id',x.vehicle_id,'name',x.name,'category',x.category,'proximity','À proximité (moins de 10 km)')) from
   (select drv.id driver_id,veh.id vehicle_id,drv.payload->>'nom' name,veh.payload->>'categorie' category from public.koki_records drv join public.koki_records veh on veh.parent_id=drv.id and veh.kind='vehicules' and veh.statut='Actif'
   where drv.kind='chauffeurs' and drv.statut='Disponible' and veh.payload->>'categorie'=input->>'category'
    and (drv.payload->>'position_updated_at')::timestamptz>now()-interval '15 minutes'
    and koki_private.business_point(drv.payload->'position') and koki_private.business_distance(input->'start',jsonb_build_object('latitude',round((drv.payload->'position'->>'latitude')::numeric/0.005)*0.005,'longitude',round((drv.payload->'position'->>'longitude')::numeric/0.005)*0.005))<=10 and drv.owner_id<>actor
    and not exists(select 1 from public.koki_records c where c.kind='courses' and c.driver_id=drv.id and c.statut in ('En attente','Acceptée','Chauffeur en route','Course en cours'))
    order by drv.id,veh.id limit 30)x),'[]'::jsonb);
 end if;
 -- Idempotence acteur/clé ; verrou avant toute mutation pour courses/commandes/reprises réseau.
 key:=(input->>'request_id')::uuid;if key is null then raise exception 'request_id UUID requis';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||key::text,0));
 select * into cached from koki_private.business_keys k where k.actor_id=actor and k.request_id=key;
 if found then
  if cached.command<>command or cached.input<>input then raise exception 'Clé déjà utilisée pour une autre requête';end if;
  if cached.output ? 'id' then
    select * into r from public.koki_records where public.koki_records.id=(cached.output->>'id')::uuid;
    if r.id is null or not coalesce(koki_private.business_can_read(r),false) then raise exception 'Accès révoqué' using errcode='42501';end if;
  elsif command='set_rate' and not koki_private.allowed('transport') then raise exception 'Administration et MFA requises' using errcode='42501';end if;
  return cached.output;
 end if;
 if command in ('register_driver','register_professional') then
   perform koki_private.business_keys_allowed(input,array['request_id','name','phone','profile','description','zone','category','address','image_path']);
   phone:=koki_private.business_text(input,'phone',8,16);if phone!~'^\+[1-9][0-9]{7,14}$' then raise exception 'Téléphone international invalide';end if;
   if input ? 'image_path' and not coalesce(koki_private.business_owned_image(input->>'image_path'),false) then raise exception 'Média propriétaire invalide';end if;
   if input ? 'category' then perform koki_private.business_text(input,'category',1,180);end if;
   if input ? 'address' then perform koki_private.business_text(input,'address',3,500);end if;
   entity_kind:=case when command='register_driver' then 'chauffeurs' else 'professionnels' end;
   if exists(select 1 from public.koki_records where owner_id=actor and public.koki_records.kind=entity_kind) then raise exception 'Profil déjà inscrit';end if;
   profile:=input->>'profile';if entity_kind='professionnels' and (profile is null or profile not in ('Commerçant','Prestataire de services','Les deux')) then raise exception 'Profil professionnel invalide';end if;
   insert into public.koki_records(kind,statut,owner_id,payload) values(entity_kind,'À valider',actor,jsonb_strip_nulls(jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'telephone',phone,'type',case when entity_kind='professionnels' then profile end,'description',left(coalesce(input->>'description',''),2000),'zone',left(coalesce(input->>'zone',''),180),'categorie',input->>'category','adresse',input->>'address','image_path',input->>'image_path'))) returning * into r;
 elsif command='admin_review' then
   perform koki_private.business_keys_allowed(input,array['request_id','id','decision']);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind in ('professionnels','boutiques','produits','services') then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||r.owner_id::text,0));end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.id is null or r.kind not in ('chauffeurs','professionnels','vehicules','boutiques','produits','services') or not koki_private.allowed(case when r.kind in ('chauffeurs','vehicules') then 'transport' else 'commerce' end) then raise exception 'Administration autorisée et MFA requises' using errcode='42501';end if;
   next_status:=case input->>'decision' when 'approve' then case r.kind when 'chauffeurs' then 'Indisponible' when 'vehicules' then 'Actif' when 'produits' then 'Disponible' when 'services' then 'Disponible' else 'Actif' end when 'suspend' then case r.kind when 'vehicules' then 'Indisponible' when 'boutiques' then 'Fermé' when 'produits' then 'Masqué' when 'services' then 'Masqué' else 'Suspendu' end end;
   if next_status is null then raise exception 'Décision invalide';end if;
   update public.koki_records set statut=next_status where public.koki_records.id=r.id returning * into r;
 elsif command='set_rate' then
   perform koki_private.business_keys_allowed(input,array['request_id','category','base_fcfa','per_km_fcfa','active']);
   if not koki_private.allowed('transport') then raise exception 'Administration Transport et MFA requises' using errcode='42501';end if;
   if jsonb_typeof(input->'base_fcfa') is distinct from 'number' or jsonb_typeof(input->'per_km_fcfa') is distinct from 'number' or jsonb_typeof(input->'active') is distinct from 'boolean' or (input->>'base_fcfa')::numeric<>trunc((input->>'base_fcfa')::numeric) or (input->>'per_km_fcfa')::numeric<>trunc((input->>'per_km_fcfa')::numeric) then raise exception 'Tarif invalide';end if;
   insert into public.koki_transport_rates(category,base_fcfa,per_km_fcfa,active) values(input->>'category',(input->>'base_fcfa')::integer,(input->>'per_km_fcfa')::integer,(input->>'active')::boolean)
   on conflict(category) do update set base_fcfa=excluded.base_fcfa,per_km_fcfa=excluded.per_km_fcfa,active=excluded.active,updated_at=clock_timestamp() returning * into rate;
   insert into public.koki_audit(actor_id,operation,table_name,record_id,details) values(actor,'UPSERT','koki_transport_rates',gen_random_uuid(),jsonb_build_object('category',rate.category));
   outcome:=to_jsonb(rate);
 elsif command in ('save_vehicle','save_shop','save_product','save_service') then
   perform koki_private.business_keys_allowed(input,array['request_id','id','revision','parent_id','name','description','category','price','stock','registration','address','image_path']);
   entity_kind:=case command when 'save_vehicle' then 'vehicules' when 'save_shop' then 'boutiques' when 'save_product' then 'produits' else 'services' end;
   if entity_kind<>'vehicules' then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||actor::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'parent_id')::uuid for update;
   if p.id is null or p.owner_id is distinct from actor then raise exception 'Propriétaire requis' using errcode='42501';end if;
   if entity_kind='vehicules' and (p.kind<>'chauffeurs' or p.statut not in ('Disponible','Indisponible','À valider')) then raise exception 'Chauffeur indisponible';end if;
   if entity_kind in ('boutiques','services') and (p.kind<>'professionnels' or p.statut<>'Actif' or p.payload->>'type' not in (case when entity_kind='boutiques' then 'Commerçant' else 'Prestataire de services' end,'Les deux')) then raise exception 'Profil professionnel incompatible';end if;
   if entity_kind='produits' then
     select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
     if p.kind<>'boutiques' or p.statut<>'Actif' or d.statut<>'Actif' or d.payload->>'type' not in ('Commerçant','Les deux') then raise exception 'Boutique indisponible';end if;
   end if;
   if entity_kind in ('produits','services') and input ? 'price' and input->'price'<>'null'::jsonb then
     if jsonb_typeof(input->'price') is distinct from 'number' or (input->>'price')::numeric<>trunc((input->>'price')::numeric) or (input->>'price')::numeric not between 0 and 1000000000 then raise exception 'Prix catalogue invalide';end if;
   elsif entity_kind='produits' then raise exception 'Prix produit obligatoire';end if;
   if entity_kind='produits' and (jsonb_typeof(input->'stock') is distinct from 'number' or (input->>'stock')::numeric<>trunc((input->>'stock')::numeric) or (input->>'stock')::numeric not between 0 and 1000000) then raise exception 'Stock invalide';end if;
   if entity_kind='vehicules' and (input->>'category' is null or input->>'category' is null or input->>'category' not in ('Moto','Taxi','Voiture','Minicar')) then raise exception 'Catégorie véhicule invalide';end if;
   if not coalesce(koki_private.business_owned_image(input->>'image_path'),false) then raise exception 'Média propriétaire invalide';end if;
   entity_id:=(input->>'id')::uuid;
   if entity_id is not null then select * into r from public.koki_records where public.koki_records.id=entity_id for update;
     if r.id is null or r.owner_id is distinct from actor or r.kind<>entity_kind or r.parent_id<>p.id then raise exception 'Élément inaccessible' using errcode='42501';end if;
     if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
     if entity_kind='vehicules' and exists(select 1 from public.koki_records active_course where active_course.kind='courses' and active_course.parent_id=r.id and active_course.statut in ('En attente','Acceptée','Chauffeur en route','Course en cours')) then raise exception 'Véhicule lié à une course active';end if;
   end if;
   pos:=jsonb_strip_nulls(jsonb_build_object('nom',koki_private.business_text(input,'name',1,180),'description',left(coalesce(input->>'description',''),2000),'categorie',input->>'category','prix',input->'price','stock',case when entity_kind='produits' then input->'stock' end,'immatriculation',input->>'registration','adresse',input->>'address','image_path',input->>'image_path'));
   next_status:=case entity_kind when 'vehicules' then 'Indisponible' when 'boutiques' then 'Actif' else 'Disponible' end;
   if entity_id is null then insert into public.koki_records(kind,statut,owner_id,parent_id,payload) values(entity_kind,next_status,actor,p.id,pos) returning * into r;
   else update public.koki_records set payload=pos,statut=case when entity_kind='vehicules' then 'Indisponible' else statut end where public.koki_records.id=entity_id returning * into r;end if;
 elsif command='driver_position' then
   perform koki_private.business_keys_allowed(input,array['request_id','position','available']);
   if jsonb_typeof(input->'available') is distinct from 'boolean' or ((input->>'available')::boolean and not koki_private.business_point(input->'position')) then raise exception 'Position/disponibilité invalide';end if;
   select * into r from public.koki_records where owner_id=actor and public.koki_records.kind='chauffeurs' for update;
   if r.id is null or r.statut not in ('Disponible','Indisponible') then raise exception 'Chauffeur validé requis' using errcode='42501';end if;
   update public.koki_records set statut=case when (input->>'available')::boolean then 'Disponible' else 'Indisponible' end,
   payload=payload||case when (input->>'available')::boolean then jsonb_build_object('position',jsonb_build_object('latitude',input->'position'->'latitude','longitude',input->'position'->'longitude'),'position_updated_at',clock_timestamp()) else '{}'::jsonb end where public.koki_records.id=r.id returning * into r;
 elsif command='reserve_ride' then
   perform koki_private.business_keys_allowed(input,array['request_id','vehicle_id','quote_id']);
   -- Ordre uniforme : client puis chauffeur, véhicule, grille. L'index unique est une seconde barrière.
   perform pg_advisory_xact_lock(hashtextextended('ride-client:'||actor::text,0));
   select * into quote from koki_private.ride_quotes q where q.id=(input->>'quote_id')::uuid and q.client_id=actor for update;
   if quote.id is null or quote.expires_at<=now() or quote.ride_id is not null then raise exception 'Devis expiré ou indisponible';end if;
   select * into v from public.koki_records where public.koki_records.id=(input->>'vehicle_id')::uuid;
   if v.id is null or v.kind<>'vehicules' then raise exception 'Véhicule indisponible';end if;
   select * into d from public.koki_records where public.koki_records.id=v.parent_id for update;
   select * into v from public.koki_records where public.koki_records.id=v.id for update;
   if d.statut<>'Disponible' or v.statut<>'Actif' or (d.payload->>'position_updated_at')::timestamptz is null or (d.payload->>'position_updated_at')::timestamptz<now()-interval '15 minutes' then raise exception 'Chauffeur indisponible';end if;
   if not koki_private.business_point(d.payload->'position') or koki_private.business_distance(quote.start_point,d.payload->'position')>10 then raise exception 'Chauffeur hors proximité';end if;
   if exists(select 1 from public.koki_records where public.koki_records.kind='courses' and (driver_id=d.id or client_id=actor) and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours')) then raise exception 'Une course est déjà active';end if;
   if v.payload->>'categorie' is distinct from quote.category then raise exception 'Catégorie incompatible avec le devis';end if;
   select * into rate from public.koki_transport_rates where category=quote.category and active for share;
   if rate.category is null then raise exception 'Tarif validé indisponible';end if;
   insert into public.koki_records(kind,statut,client_id,parent_id,driver_id,payload) values('courses','En attente',actor,v.id,d.id,jsonb_build_object('nom','Course','depart',quote.start_point,'destination',quote.end_point,'distance',round(quote.distance_km,3),'tarif',quote.fare_fcfa,'categorie',quote.category,'methode','À vol d’oiseau')) returning * into r;
   update koki_private.ride_quotes set ride_id=r.id where koki_private.ride_quotes.id=quote.id;
 elsif command='create_order' then
   perform koki_private.business_keys_allowed(input,array['request_id','shop_id','items','mode','address']);
   if input->>'mode' is null or input->>'mode' not in ('retrait','livraison') then raise exception 'Réception invalide';end if;
   if input->>'mode'='livraison' then perform koki_private.business_text(input,'address',3,500);end if;
   items:=input->'items';if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 50 then raise exception 'Panier invalide';end if;
   if (select count(*) from jsonb_array_elements(items))<>(select count(distinct value->>'product_id') from jsonb_array_elements(items)) then raise exception 'Produits dupliqués';end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'shop_id')::uuid;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'shop_id')::uuid for update;
   select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
   if p.kind is distinct from 'boutiques' or p.statut<>'Actif' or d.kind is distinct from 'professionnels' or d.statut<>'Actif' or d.payload->>'type' not in ('Commerçant','Les deux') then raise exception 'Boutique indisponible';end if;
   -- Verrouillage déterministe. Toutes les lignes partagent une seule boutique ; panier multi-vendeur à séparer.
   for line in select value from jsonb_array_elements(items) order by value->>'product_id' loop
     perform koki_private.business_keys_allowed(line,array['product_id','quantity']);
     if jsonb_typeof(line->'quantity') is distinct from 'number' or (line->>'quantity')::numeric<>trunc((line->>'quantity')::numeric) or (line->>'quantity')::numeric not between 1 and 10000 then raise exception 'Quantité invalide';end if;qty:=(line->>'quantity')::integer;
     select * into r from public.koki_records where public.koki_records.id=(line->>'product_id')::uuid for update;
     if r.kind is distinct from 'produits' or r.parent_id<>p.id or r.statut<>'Disponible' or (r.payload->>'stock')::integer<qty then raise exception 'Produit indisponible ou stock insuffisant';end if;
     price:=(r.payload->>'prix')::bigint;if price is null or price<0 then raise exception 'Prix catalogue invalide';end if;
     total:=total+price*qty;
   end loop;
   insert into public.koki_records(kind,statut,client_id,parent_id,provider_id,payload) values('commandes','Commande reçue',actor,p.id,d.id,jsonb_build_object('nom','Commande','total',total,'mode',input->>'mode','adresse',case when input->>'mode'='livraison' then input->>'address' else null end,'currency','FCFA')) returning public.koki_records.id into entity_id;
   for line in select value from jsonb_array_elements(items) order by value->>'product_id' loop
     select * into r from public.koki_records where public.koki_records.id=(line->>'product_id')::uuid;qty:=(line->>'quantity')::integer;
     insert into public.koki_order_items(order_id,product_id,quantity,unit_price,product_name) values(entity_id,r.id,qty,(r.payload->>'prix')::bigint,r.payload->>'nom');
     update public.koki_records set payload=jsonb_set(payload,'{stock}',to_jsonb((payload->>'stock')::integer-qty)) where public.koki_records.id=r.id;
   end loop;
   select * into r from public.koki_records where public.koki_records.id=entity_id;
 elsif command='request_service' then
   perform koki_private.business_keys_allowed(input,array['request_id','service_id','need','address','date','image_path']);
   select * into p from public.koki_records where public.koki_records.id=(input->>'service_id')::uuid;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into p from public.koki_records where public.koki_records.id=(input->>'service_id')::uuid for update;
   select * into d from public.koki_records where public.koki_records.id=p.parent_id for update;
   if p.kind is distinct from 'services' or p.statut<>'Disponible' or d.statut<>'Actif' or d.payload->>'type' not in ('Prestataire de services','Les deux') then raise exception 'Prestataire indisponible';end if;
   if not coalesce(koki_private.business_owned_image(input->>'image_path'),false) then raise exception 'Média propriétaire invalide';end if;
   if input->>'date' is null or input->>'date' !~ '^\d{4}-\d{2}-\d{2}$' or (input->>'date')::date is null or (input->>'date')::date<current_date then raise exception 'Date invalide';end if;
   insert into public.koki_records(kind,statut,client_id,parent_id,provider_id,payload) values('demandes_services','Demande envoyée',actor,p.id,d.id,jsonb_build_object('nom','Demande de devis','besoin',koki_private.business_text(input,'need',10,2000),'lieu',koki_private.business_text(input,'address',3,500),'date',(input->>'date')::date,'catalogue_price',p.payload->'prix','image_path',input->>'image_path')) returning * into r;
 elsif command in ('submit_service_quote','accept_service_quote') then
   perform koki_private.business_keys_allowed(input,case when command='submit_service_quote' then array['request_id','id','revision','amount_fcfa','description'] else array['request_id','id','revision'] end);
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   select * into p from public.koki_records where public.koki_records.id=r.provider_id;
   if p.owner_id is not null then perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.kind is distinct from 'demandes_services' or r.statut<>'Demande envoyée' or (input->>'revision')::integer is distinct from r.revision then raise exception 'Demande ou révision indisponible';end if;
   if command='submit_service_quote' then
     if not coalesce(koki_private.owns_business(r.provider_id),false) and not koki_private.allowed('commerce') then raise exception 'Prestataire assigné requis' using errcode='42501';end if;
     if jsonb_typeof(input->'amount_fcfa') is distinct from 'number' or (input->>'amount_fcfa')::numeric not between 0 and 1000000000 or (input->>'amount_fcfa')::numeric<>trunc((input->>'amount_fcfa')::numeric) then raise exception 'Montant de devis invalide';end if;
     update public.koki_records set payload=payload||jsonb_build_object('quote_fcfa',(input->>'amount_fcfa')::bigint,'quote_text',koki_private.business_text(input,'description',1,2000),'quote_expires_at',now()+interval '7 days','quote_client_accepted',false) where public.koki_records.id=r.id returning * into r;
   else
     if r.client_id is distinct from actor then raise exception 'Client propriétaire requis' using errcode='42501';end if;
     if r.payload->>'quote_fcfa' is null or r.payload->>'quote_expires_at' is null or (r.payload->>'quote_expires_at')::timestamptz<=now() or not exists(select 1 from public.koki_records pro where pro.id=r.provider_id and pro.statut='Actif') then raise exception 'Devis expiré ou prestataire indisponible';end if;
     update public.koki_records set statut='Acceptée',payload=payload||jsonb_build_object('quote_client_accepted',true) where public.koki_records.id=r.id returning * into r;
   end if;
 elsif command='transition' then
   perform koki_private.business_keys_allowed(input,array['request_id','id','next','revision']);
   -- Verrouiller boutique/pro avant commande : ordre compatible avec create_order et restitution.
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid;
   if r.kind in ('commandes','demandes_services') then select * into p from public.koki_records where public.koki_records.id=r.provider_id;perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));end if;
   if r.kind='commandes' then perform 1 from public.koki_records where public.koki_records.id=r.parent_id for update;perform 1 from public.koki_records where public.koki_records.id=r.provider_id for update;end if;
   if r.kind='courses' then select * into d from public.koki_records where public.koki_records.id=r.driver_id for update;end if;
   select * into r from public.koki_records where public.koki_records.id=(input->>'id')::uuid for update;
   if r.id is null or not coalesce(koki_private.business_can_read(r),false) or r.kind not in ('courses','commandes','demandes_services') then raise exception 'Accès refusé' using errcode='42501';end if;
   if (input->>'revision')::integer is distinct from r.revision then raise exception 'Révision périmée : actualisez';end if;
   next_status:=input->>'next';
   if next_status='Annulée' then
     if r.statut not in ('En attente','Acceptée','Commande reçue','Confirmée','Demande envoyée') then raise exception 'Annulation non autorisée à cette étape';end if;
     if r.client_id is distinct from actor and not coalesce(koki_private.owns_business(r.provider_id),false) and not coalesce(koki_private.owns_business(r.driver_id),false) and not koki_private.allowed(case when r.kind='courses' then 'transport' else 'commerce' end) then raise exception 'Annulation refusée' using errcode='42501';end if;
   else
     if r.kind='courses' then
       if not coalesce(koki_private.owns_business(r.driver_id),false) and not koki_private.allowed('transport') then raise exception 'Chauffeur assigné requis' using errcode='42501';end if;
       if next_status='Acceptée' and (d.statut<>'Disponible' or not exists(select 1 from public.koki_records accepted_vehicle where accepted_vehicle.id=r.parent_id and accepted_vehicle.statut='Actif')) then raise exception 'Chauffeur/véhicule indisponible';end if;
       steps:=array['En attente','Acceptée','Chauffeur en route','Course en cours','Terminée'];
     else
       if not coalesce(koki_private.owns_business(r.provider_id),false) and not koki_private.allowed('commerce') then raise exception 'Professionnel assigné requis' using errcode='42501';end if;
       if r.kind='demandes_services' and next_status='Acceptée' and (r.payload->>'quote_fcfa' is not null or r.payload->>'catalogue_price' is null) and not coalesce((r.payload->>'quote_client_accepted')::boolean,false) then raise exception 'Acceptation du devis par le client requise';end if;
       steps:=case when r.kind='commandes' then case when r.payload->>'mode'='retrait' then array['Commande reçue','Confirmée','Préparation','Prête au retrait','Retirée'] else array['Commande reçue','Confirmée','Préparation','En livraison','Livrée'] end else array['Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé'] end;
     end if;
     if next_status is null or next_status is distinct from steps[array_position(steps,r.statut)+1] then raise exception 'Transition invalide';end if;
   end if;
   if r.kind='commandes' and next_status='Annulée' then
     for line in select to_jsonb(i) from public.koki_order_items i where order_id=r.id order by product_id loop
       update public.koki_records set payload=jsonb_set(payload,'{stock}',to_jsonb((payload->>'stock')::integer+(line->>'quantity')::integer)) where public.koki_records.id=(line->>'product_id')::uuid;
     end loop;
   end if;
   update public.koki_records set statut=next_status where public.koki_records.id=r.id returning * into r;
 else raise exception 'Commande inconnue';
 end if;
 if outcome is null then outcome:=to_jsonb(r);end if;
 insert into koki_private.business_keys(actor_id,request_id,command,input,output) values(actor,key,command,input,outcome);
 return outcome;
end $function$
;


-- ===== 19/37 : supabase/proposals/commerce-desarchiver-proprietaire.sql · sha256 714c1f929741054f
-- PROPOSITION — Commerces & Services : le commerçant peut DÉSARCHIVER ses boutiques, produits et services.
-- NON APPLIQUÉE : à n'installer qu'après accord explicite.
--
-- Aujourd'hui seul l'administration peut rétablir un élément archivé (décision « Approuver »). La commande 'unarchive' est ajoutée
-- à koki_private.commerce_business (même chaîne que 'archive' : koki_business > commerce_admin > commerce_business).
-- Règles :
--  * propriétaire uniquement, révision à jour, l'élément doit être « Archivé » ;
--  * un élément archivé par l'administration (moderation.decision = 'archive') ne peut pas être rétabli par son propriétaire ;
--  * la boutique ou la fiche parente ne doit pas être archivée, suspendue ou refusée ;
--  * retour de l'élément : boutique → « À valider » (nouvelle validation) ; produit / service → « Masqué » avec son verrou de
--    validation inchangé (le commerçant le rend disponible ensuite, sauf s'il attend la validation de l'administration) ;
--  * deux éléments actifs ne peuvent pas porter le même nom : message « renommez-le avant de le rétablir ».
-- Méthode : le texte exact de la fonction en production est relu puis modifié en trois endroits (une occurrence exigée chacun).
-- Essai à blanc (transaction annulée) réalisé le 2026-10-26 sur Koki : 7 cas validés, aucune trace laissée.
begin;

do $$
declare
 src text; t text;
 a1 text:='''set_availability'',''archive'',''moderate'') then';
 b1 text:='''set_availability'',''archive'',''unarchive'',''moderate'') then';
 a2 text:='  when ''archive'' then array[''request_id'',''id'',''revision'']';
 b2 text:=E'  when ''archive'' then array[''request_id'',''id'',''revision'']\n  when ''unarchive'' then array[''request_id'',''id'',''revision'']';
 a3 text:=E'\n elsif command=''review_changes'' then';
 b3 text:=E'\n elsif command=''unarchive'' then
  perform pg_advisory_xact_lock(hashtextextended(''trade-owner:''||actor::text,0));
  select * into r from public.koki_records where id=(input->>''id'')::uuid for update;
  if r.id is null or r.owner_id is distinct from actor or r.kind not in (''boutiques'',''produits'',''services'') then raise exception ''Élément inaccessible'' using errcode=''42501'';end if;
  if (input->>''revision'')::integer is distinct from r.revision then raise exception ''Révision périmée : actualisez'';end if;
  if r.statut<>''Archivé'' then raise exception ''Cet élément n’est pas archivé'';end if;
  if r.payload->''moderation''->>''decision''=''archive'' then raise exception ''Archivé par l’administration : contactez-la pour le rétablir'' using errcode=''42501'';end if;
  if r.parent_id is not null then
   select * into p from public.koki_records where id=r.parent_id for update;
   if p.id is null or p.statut in (''Archivé'',''Suspendu'',''Refusé'') then raise exception ''Désarchivez d’abord la boutique ou la fiche parente'';end if;
  end if;
  begin
   update public.koki_records set statut=case r.kind when ''boutiques'' then ''À valider'' else ''Masqué'' end where id=r.id returning * into r;
  exception when unique_violation then raise exception ''Un élément actif porte déjà ce nom : renommez-le avant de le rétablir'';end;'||E'\n elsif command=''review_changes'' then';
begin
 select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='koki_private' and p.proname='commerce_business' and pg_get_function_identity_arguments(p.oid)='command text, input jsonb';
 if src is null then raise exception 'Préflight : koki_private.commerce_business introuvable';end if;
 if position('''unarchive''' in src)>0 then raise exception 'Préflight : commande unarchive déjà installée — rien n''est changé';end if;
 foreach t in array array[a1,a2,a3] loop
  if position(t in src)=0 then raise exception 'Préflight : texte attendu absent (%) — rien n''est changé',left(t,40);end if;
  if position(t in substr(src,position(t in src)+length(t)))>0 then raise exception 'Préflight : texte présent plusieurs fois (%) — rien n''est changé',left(t,40);end if;
 end loop;
 execute replace(replace(replace(src,a1,b1),a2,b2),a3,b3);
end $$;

commit;

-- RETOUR ARRIÈRE : réexécuter la fonction d'origine (copie enregistrée avant installation) ou inverser les trois remplacements.
-- Les éléments déjà désarchivés restent valides : aucun statut nouveau n'est introduit.


-- ===== 20/37 : supabase/proposals/commerce-boutique-des-envoi-fiche.sql · sha256 48a7595506ab67c1
-- PROPOSITION — Commerces & Services : créer la boutique (ou les services) dès que la fiche est ENVOYÉE (« En attente »),
-- sans attendre sa validation par l'administration.
-- NON APPLIQUÉE : à n'installer qu'après accord explicite.
--
-- Ce qui change : une seule condition de koki_private.commerce_business (commandes save_shop et save_service).
--   Avant : la fiche professionnelle doit être « Actif ».
--   Après : la fiche doit être « En attente » ou « Actif » (une fiche Refusé / Suspendu / Archivé reste bloquée).
-- Ce qui ne change pas :
--   * les produits exigent toujours une boutique « Actif » ET une fiche « Actif » ;
--   * rien n'est public plus tôt : le catalogue exige fiche ET boutique validées (koki_private.commerce_catalog) ;
--   * la validation de la boutique par l'administration reste obligatoire.
--
-- Méthode : le texte exact de la fonction en production est relu puis modifié (une seule occurrence exigée),
-- ce qui évite de recopier à la main 22 000 caractères. Aucune donnée n'est touchée.
-- Essai à blanc (transaction annulée) réalisé le 2026-10-26 sur Koki :
--   avant = refusée ; après = acceptée (statut « À valider ») ; produit refusé ; absente du catalogue public ;
--   fiche « Refusé » = boutique refusée ; aucune trace laissée.
begin;

do $$
declare
 src text;
 ancien text:='p.statut<>''Actif'' or p.payload->>''type'' not in (case when entity_kind=''boutiques''';
 nouveau text:='p.statut not in (''En attente'',''Actif'') or p.payload->>''type'' not in (case when entity_kind=''boutiques''';
begin
 select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='koki_private' and p.proname='commerce_business' and pg_get_function_identity_arguments(p.oid)='command text, input jsonb';
 if src is null then raise exception 'Préflight : koki_private.commerce_business introuvable';end if;
 if position(ancien in src)=0 then raise exception 'Préflight : règle déjà modifiée ou fonction différente — rien n''est changé';end if;
 if position(ancien in substr(src,position(ancien in src)+length(ancien)))>0 then raise exception 'Préflight : texte présent plusieurs fois — rien n''est changé';end if;
 execute replace(src,ancien,nouveau);
end $$;

commit;

-- RETOUR ARRIÈRE (même méthode, texte inversé) :
-- do $$ declare src text; begin
--  select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_private' and p.proname='commerce_business';
--  execute replace(src,'p.statut not in (''En attente'',''Actif'') or p.payload->>''type'' not in (case when entity_kind=''boutiques''','p.statut<>''Actif'' or p.payload->>''type'' not in (case when entity_kind=''boutiques''');
-- end $$;


-- ===== 21/37 : supabase/proposals/commerce-catalogue-sans-coordonnees.sql · sha256 466cca4974629bbe
-- APPLIQUÉ en production le 2026-10-27 (migration commerce_catalogue_sans_coordonnees_professionnelles), après accord de la direction.
-- Catalogue public (visiteurs et autres professionnels) : les produits publiés restent visibles ; la boutique ne montre que
-- nom, description, catégorie, village, photos et WhatsApp (pour commander) ; la fiche du professionnel ne montre plus
-- téléphone, WhatsApp, adresse, position GPS, zone ni horaires lorsqu'il a une boutique active. Un professionnel sans
-- boutique (ex. prestataire) garde son contact visible pour recevoir des demandes de devis.
-- Retour arrière : recréer koki_private.commerce_catalog() avec l'ancienne définition (adresse/localisation/horaires/zone
-- exposés pour 'professionnels' et 'boutiques').
create or replace function koki_private.commerce_catalog() returns jsonb language sql stable security definer set search_path to '' as $b$
 select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
  'id',x.id,'kind',x.kind,'parent_id',x.parent_id,'provider_id',x.provider_id,'statut',x.statut,
  'nom',x.payload->>'nom','description',x.payload->>'description','categorie',x.payload->>'categorie',
  'prix',x.payload->'prix','ancien_prix',x.payload->'ancien_prix','stock',x.payload->'stock','tarif',x.payload->>'tarif',
  'telephone',case when x.kind='professionnels' and not x.avec_boutique then x.payload->>'telephone' end,
  'whatsapp',case when x.kind='boutiques' or (x.kind='professionnels' and not x.avec_boutique) then x.payload->>'whatsapp' end,
  'type',case when x.kind='professionnels' then x.payload->>'type' end,
  'adresse',case when x.kind='professionnels' and not x.avec_boutique then x.payload->>'adresse' end,
  'village',x.payload->>'village',
  'zone',case when x.kind='services' or (x.kind='professionnels' and not x.avec_boutique) then x.payload->>'zone' end,
  'horaires',case when x.kind='professionnels' and not x.avec_boutique then x.payload->>'horaires' end,
  'localisation',case when x.kind='professionnels' and not x.avec_boutique then x.payload->'localisation' end,
  'photos',coalesce(x.payload->'photos',case when x.payload->>'image_path' is not null then jsonb_build_array(x.payload->>'image_path') end),
  'image_path',x.payload->>'image_path')) order by x.updated_at desc),'[]'::jsonb)
 from (select listing.*, exists(select 1 from public.koki_records s where s.parent_id=listing.id and s.kind='boutiques' and s.statut='Actif') as avec_boutique from public.koki_records listing where (listing.kind='professionnels' and listing.statut='Actif')
  or (listing.kind='boutiques' and listing.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
  or (listing.kind='services' and listing.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.statut='Actif'))
  or (listing.kind='produits' and listing.statut in ('Disponible','Épuisé') and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=listing.parent_id and b.statut='Actif' and prof.statut='Actif'))
  order by listing.updated_at desc limit 500) x
$b$;


-- ===== 22/37 : supabase/proposals/direct-professional-shop.sql · sha256 2809acd2fd600fb7
-- Une première boutique issue de la fiche : gestion immédiate, publication liée à la validation du professionnel.
create or replace function koki_private.ensure_initial_shop(p public.koki_records) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p.kind<>'professionnels' or p.owner_id is null or p.statut not in ('Actif','En attente','À valider') or coalesce(p.payload->>'type','') not in ('Commerçant','Les deux') then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('trade-owner:'||p.owner_id::text,0));
 -- Même une boutique archivée compte : ne jamais la recréer après une suppression volontaire.
 if exists(select 1 from public.koki_records b where b.kind='boutiques' and b.parent_id=p.id) then return;end if;
 insert into public.koki_records(kind,statut,owner_id,parent_id,payload)
 values('boutiques','Actif',p.owner_id,p.id,jsonb_strip_nulls(jsonb_build_object(
 'nom',p.payload->>'nom','categorie',p.payload->>'categorie','adresse',p.payload->>'adresse',
 'village',p.payload->>'village','description',p.payload->>'description','horaires',p.payload->>'horaires',
 'whatsapp',p.payload->>'whatsapp','photos',coalesce(p.payload->'photos','[]'::jsonb),
 'image_path',p.payload->>'image_path','localisation',p.payload->'localisation','initial_shop',true)));
end $$;
revoke all on function koki_private.ensure_initial_shop(public.koki_records) from public,anon,authenticated;
create or replace function koki_private.initial_shop_after_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin perform koki_private.ensure_initial_shop(new);return new;end $$;
revoke all on function koki_private.initial_shop_after_profile() from public,anon,authenticated;
create trigger initial_shop_after_profile after insert or update on public.koki_records
for each row when (new.kind='professionnels') execute function koki_private.initial_shop_after_profile();
-- Préparation des offres avant validation, sans modifier les contrôles de publication, de commande ou de propriété.
do $patch$
declare definition text;old_guard text;new_guard text;
begin
 definition:=pg_get_functiondef('koki_private.commerce_business(text,jsonb)'::regprocedure);
 old_guard:='p.kind<>''professionnels'' or p.statut<>''Actif''';
 new_guard:='p.kind<>''professionnels'' or p.statut not in (''Actif'',''En attente'',''À valider'')';
 if position(old_guard in definition)=0 then old_guard:='p.kind<>''professionnels'' or p.statut not in (''En attente'',''Actif'')';end if;
 if position(old_guard in definition)=0 then raise exception 'Garde profil inattendue';end if;
 definition:=replace(definition,old_guard,new_guard);
 old_guard:='p.kind<>''boutiques'' or p.statut<>''Actif'' or d.statut<>''Actif''';
 new_guard:='p.kind<>''boutiques'' or p.statut not in (''Actif'',''À valider'') or d.id is null or d.owner_id is distinct from actor or d.statut not in (''Actif'',''En attente'',''À valider'')';
 if position(old_guard in definition)=0 then raise exception 'Garde produit inattendue';end if;
 definition:=replace(definition,old_guard,new_guard);
 execute definition;
end $patch$;
-- Reprise des comptes existants sans boutique, sans doublon ni changement des boutiques existantes.
select koki_private.ensure_initial_shop(p) from public.koki_records p where p.kind='professionnels';


-- ===== 23/37 : supabase/proposals/publication-moderation.sql · sha256 bc8b67d65011cf7b
-- Quota indépendant de la suppression et modération privée.
alter table koki_social_private.comments add column hidden boolean not null default false;
create table koki_social_private.comment_events(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create index on koki_social_private.comment_events(user_id,created_at);
insert into koki_social_private.comment_events(user_id,created_at) select user_id,created_at from koki_social_private.comments where created_at>now()-interval '1 day';
create table koki_social_private.reports(id uuid primary key default gen_random_uuid(),comment_id uuid not null references koki_social_private.comments(id) on delete cascade,reporter_id uuid not null references auth.users(id) on delete cascade,reason text not null check(char_length(reason) between 3 and 500),created_at timestamptz not null default now(),resolved boolean not null default false,unique(comment_id,reporter_id));
create index on koki_social_private.reports(reporter_id,created_at);
create table koki_social_private.moderation_log(id bigint generated always as identity primary key,comment_id uuid,actor uuid,hidden boolean not null,reason text not null,created_at timestamptz not null default now());
alter table koki_social_private.comment_events enable row level security;
alter table koki_social_private.reports enable row level security;
alter table koki_social_private.moderation_log enable row level security;
revoke all on all tables in schema koki_social_private from public,anon,authenticated;
CREATE OR REPLACE FUNCTION koki_social_private.interact(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if p_action is null or p_action not in ('read','like','comment','delete','report') then raise exception 'Action invalide'; end if;
 if p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'Page invalide'; end if;
 if not exists(select 1 from public.koki_contents where id=p_content and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))) then raise exception 'Publication indisponible'; end if;
 if p_action<>'read' then
  if uid is null or not exists(select 1 from auth.users where id=uid and not coalesce(is_anonymous,false)) then raise exception 'Connectez-vous pour participer' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,372));
 end if;
 if p_action='like' then
  if p_liked is null then raise exception 'Choix invalide'; end if;
  if p_liked then insert into koki_social_private.likes values(p_content,uid) on conflict do nothing;
  else delete from koki_social_private.likes where content_id=p_content and user_id=uid; end if;
 elsif p_action='comment' then
  if p_text is null or char_length(trim(p_text)) not between 1 and 2000 then raise exception 'Commentaire requis (2 000 caractères maximum)'; end if;
  if (select count(*) from koki_social_private.comment_events where user_id=uid and created_at>now()-interval '1 minute')>=5 or (select count(*) from koki_social_private.comment_events where user_id=uid and created_at>now()-interval '1 day')>=30 then raise exception 'Trop de commentaires. Réessayez plus tard.'; end if;
  delete from koki_social_private.comment_events where user_id=uid and created_at<now()-interval '1 day';
  insert into koki_social_private.comment_events(user_id) values(uid);
  insert into koki_social_private.comments(content_id,user_id,body) values(p_content,uid,trim(p_text));
 elsif p_action='report' then
  if not exists(select 1 from koki_social_private.comments where id=p_comment and content_id=p_content and not hidden) then raise exception 'Commentaire indisponible';end if;
  if p_text is null or char_length(trim(p_text)) not between 3 and 500 then raise exception 'Motif requis';end if;
  if (select count(*) from koki_social_private.reports where reporter_id=uid and created_at>now()-interval '1 day')>=20 then raise exception 'Trop de signalements';end if;
  insert into koki_social_private.reports(comment_id,reporter_id,reason) values(p_comment,uid,trim(p_text)) on conflict(comment_id,reporter_id) do nothing;
 elsif p_action='delete' then
  delete from koki_social_private.comments where id=p_comment and content_id=p_content and user_id=uid;
 end if;
 select jsonb_build_object('likes',(select count(*) from koki_social_private.likes where content_id=p_content),
 'liked',exists(select 1 from koki_social_private.likes where content_id=p_content and user_id=uid),
 'total',(select count(*) from koki_social_private.comments where not hidden and content_id=p_content),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'created_at',c.created_at,'mine',coalesce(c.user_id=uid,false)) order by c.created_at desc,c.id) from (select * from koki_social_private.comments where not hidden and content_id=p_content order by created_at desc,id limit 30 offset p_offset)c),'[]'::jsonb)) into result;
 return result;
end $function$
;

create function koki_social_private.moderate(p_comment uuid,p_hidden boolean,p_reason text,p_offset integer) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(koki_private.allowed('content'),false) then raise exception 'Accès refusé' using errcode='42501';end if;
 if p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'Page invalide';end if;
 if p_comment is not null then
  if p_hidden is null or p_reason is null or char_length(trim(p_reason)) not between 3 and 500 then raise exception 'Motif requis (3 à 500 caractères)';end if;
  update koki_social_private.comments set hidden=p_hidden where id=p_comment;
  if not found then raise exception 'Commentaire indisponible';end if;
  insert into koki_social_private.moderation_log(comment_id,actor,hidden,reason) values(p_comment,auth.uid(),p_hidden,trim(p_reason));
  update koki_social_private.reports set resolved=true where comment_id=p_comment;
 end if;
 return coalesce((select jsonb_agg(to_jsonb(c)) from (select c.id,c.content_id,c.body,c.created_at,c.hidden,(select count(*) from koki_social_private.reports r where r.comment_id=c.id and not r.resolved) as reports,(select jsonb_agg(r.reason) from koki_social_private.reports r where r.comment_id=c.id and not r.resolved) as reasons from koki_social_private.comments c order by reports desc,c.created_at desc,c.id limit 50 offset p_offset)c),'[]'::jsonb);
end $$;
revoke all on function koki_social_private.moderate(uuid,boolean,text,integer) from public,anon;
grant execute on function koki_social_private.moderate(uuid,boolean,text,integer) to authenticated;
create function public.koki_comment_moderation(p_comment uuid default null,p_hidden boolean default null,p_reason text default null,p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select koki_social_private.moderate(p_comment,p_hidden,p_reason,p_offset)$$;
revoke all on function public.koki_comment_moderation(uuid,boolean,text,integer) from public,anon;
grant execute on function public.koki_comment_moderation(uuid,boolean,text,integer) to authenticated;
-- Résumé des compteurs par lot, sans charger les commentaires.
create function koki_social_private.summaries(p_ids uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if coalesce(cardinality(p_ids),0)>50 then raise exception 'Lot trop grand';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'likes',(select count(*) from koki_social_private.likes l where l.content_id=c.id),'liked',exists(select 1 from koki_social_private.likes l where l.content_id=c.id and l.user_id=auth.uid()))) from public.koki_contents c where c.id=any(p_ids) and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))),'[]'::jsonb);
end $$;
revoke all on function koki_social_private.summaries(uuid[]) from public;
grant execute on function koki_social_private.summaries(uuid[]) to anon,authenticated;
create function public.koki_social_summaries(p_ids uuid[]) returns jsonb language sql security invoker set search_path='' as $$select koki_social_private.summaries(p_ids)$$;
revoke all on function public.koki_social_summaries(uuid[]) from public;
grant execute on function public.koki_social_summaries(uuid[]) to anon,authenticated;


-- ===== 24/37 : supabase/historique/reference/sources/prod_20261107221756_videos_upload_youtube.sql · sha256 064e14c9b4abefc7
create table public.koki_content_media(
 id uuid primary key default gen_random_uuid(),
 content_id uuid not null references public.koki_contents(id) on delete cascade,
 source text not null check (source in ('upload','youtube')),
 storage_path text,
 youtube_video_id text,
 mime_type text,
 file_size_bytes bigint,
 thumbnail_path text,
 display_order integer not null default 0 check (display_order >= 0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check ((source='upload' and storage_path is not null and youtube_video_id is null) or (source='youtube' and storage_path is null and youtube_video_id ~ '^[A-Za-z0-9_-]{11}$')),
 check (file_size_bytes is null or file_size_bytes between 1 and 31457280)
);
create index koki_content_media_content_order on public.koki_content_media(content_id, display_order);
alter table public.koki_content_media enable row level security;
create policy koki_content_media_public_read on public.koki_content_media for select using (exists(select 1 from public.koki_contents c where c.id=content_id and c.statut='publié' and c.publication<=now()));
create policy koki_content_media_admin_write on public.koki_content_media for all using (exists(select 1 from public.koki_admin_members m where m.user_id=auth.uid() and m.enabled and m.role in ('superadmin','editor'))) with check (exists(select 1 from public.koki_admin_members m where m.user_id=auth.uid() and m.enabled and m.role in ('superadmin','editor')));




-- ===== 25/37 : supabase/historique/reference/sources/prod_20261107221803_videos_storage_bucket.sql · sha256 ca68ab5f91ec3528
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('koki-videos','koki-videos',false,31457280,array['video/mp4','video/webm']) on conflict(id) do nothing;
create policy koki_videos_admin_insert on storage.objects for insert to authenticated with check (bucket_id='koki-videos' and exists(select 1 from public.koki_admin_members m where m.user_id=auth.uid() and m.enabled and m.role in ('superadmin','editor')));
create policy koki_videos_admin_delete on storage.objects for delete to authenticated using (bucket_id='koki-videos' and exists(select 1 from public.koki_admin_members m where m.user_id=auth.uid() and m.enabled and m.role in ('superadmin','editor')));




-- ===== 26/37 : supabase/historique/reference/sources/prod_20261110082048_publication_comment_blocking.sql · sha256 d02958281c5160d5
-- Apply after publication-moderation.sql. Private per-account comment filtering.
begin;
create table if not exists koki_social_private.blocks (
 blocker_id uuid not null references auth.users(id) on delete cascade,
 blocked_id uuid not null references auth.users(id) on delete cascade,
 primary key(blocker_id,blocked_id), check(blocker_id<>blocked_id)
);
alter table koki_social_private.blocks enable row level security;
revoke all on koki_social_private.blocks from public,anon,authenticated;
CREATE OR REPLACE FUNCTION koki_social_private.interact(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if p_action is null or p_action not in ('read','like','comment','delete','report','block','unblock_all') then raise exception 'Action invalide'; end if;
 if p_offset is null or p_offset<0 or p_offset>10000 then raise exception 'Page invalide'; end if;
 if not exists(select 1 from public.koki_contents where id=p_content and statut='publié' and publication<=now() and (type<>'Publicités' or (actif and (fin is null or fin>now())))) then raise exception 'Publication indisponible'; end if;
 if p_action<>'read' then
  if uid is null or not exists(select 1 from auth.users where id=uid and not coalesce(is_anonymous,false)) then raise exception 'Connectez-vous pour participer' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text,372));
 end if;
 if p_action='like' then
  if p_liked is null then raise exception 'Choix invalide'; end if;
  if p_liked then insert into koki_social_private.likes values(p_content,uid) on conflict do nothing;
  else delete from koki_social_private.likes where content_id=p_content and user_id=uid; end if;
 elsif p_action='comment' then
  if p_text is null or char_length(trim(p_text)) not between 1 and 2000 then raise exception 'Commentaire requis (2 000 caractères maximum)'; end if;
  if (select count(*) from koki_social_private.comment_events where user_id=uid and created_at>now()-interval '1 minute')>=5 or (select count(*) from koki_social_private.comment_events where user_id=uid and created_at>now()-interval '1 day')>=30 then raise exception 'Trop de commentaires. Réessayez plus tard.'; end if;
  delete from koki_social_private.comment_events where user_id=uid and created_at<now()-interval '1 day';
  insert into koki_social_private.comment_events(user_id) values(uid);
  insert into koki_social_private.comments(content_id,user_id,body) values(p_content,uid,trim(p_text));
 elsif p_action='report' then
  if not exists(select 1 from koki_social_private.comments where id=p_comment and content_id=p_content and not hidden) then raise exception 'Commentaire indisponible';end if;
  if p_text is null or char_length(trim(p_text)) not between 3 and 500 then raise exception 'Motif requis';end if;
  if (select count(*) from koki_social_private.reports where reporter_id=uid and created_at>now()-interval '1 day')>=20 then raise exception 'Trop de signalements';end if;
  insert into koki_social_private.reports(comment_id,reporter_id,reason) values(p_comment,uid,trim(p_text)) on conflict(comment_id,reporter_id) do nothing;
 elsif p_action='block' then
  if not exists(select 1 from koki_social_private.comments where id=p_comment and content_id=p_content and not hidden and user_id<>uid) then raise exception 'Commentaire indisponible';end if;
  insert into koki_social_private.blocks(blocker_id,blocked_id) select uid,user_id from koki_social_private.comments where id=p_comment and content_id=p_content on conflict do nothing;
 elsif p_action='unblock_all' then
  delete from koki_social_private.blocks where blocker_id=uid;
 elsif p_action='delete' then
  delete from koki_social_private.comments where id=p_comment and content_id=p_content and user_id=uid;
 end if;
 select jsonb_build_object('blocking_available',true,'blocked_count',(select count(*) from koki_social_private.blocks where blocker_id=uid),'likes',(select count(*) from koki_social_private.likes where content_id=p_content),
 'liked',exists(select 1 from koki_social_private.likes where content_id=p_content and user_id=uid),
 'total',(select count(*) from koki_social_private.comments where not hidden and content_id=p_content and not exists(select 1 from koki_social_private.blocks b where b.blocker_id=uid and b.blocked_id=comments.user_id)),
 'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'created_at',c.created_at,'mine',coalesce(c.user_id=uid,false)) order by c.created_at desc,c.id) from (select * from koki_social_private.comments where not hidden and content_id=p_content and not exists(select 1 from koki_social_private.blocks b where b.blocker_id=uid and b.blocked_id=comments.user_id) order by created_at desc,id limit 30 offset p_offset)c),'[]'::jsonb)) into result;
 return result;
end $function$
;

commit;




-- ===== 27/37 : supabase/historique/reference/sources/prod_20261111150715_commerce_localite_saisie_libre.sql · sha256 ab7e0dda4d766cde
do $p$ begin
 if position('koki_localites' in pg_get_functiondef('koki_private.commerce_village(jsonb)'::regprocedure))=0 then raise exception 'Préflight : fonction déjà modifiée'; end if;
end $p$;
create or replace function koki_private.commerce_village(input jsonb) returns text language plpgsql stable security definer set search_path to '' as $f$
declare v text:=btrim(input->>'village');
begin
 if v is null or v='' then return null;end if;
 if char_length(v)>180 then raise exception 'Localité trop longue';end if;
 return v;
end $f$;



-- ===== 28/37 : supabase/historique/reference/sources/prod_20261111224017_videos_publications_lecture_publique.sql · sha256 11a8fe1049d865a3
do $p$ begin
 if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='koki_videos_published') then raise exception 'Préflight : politique déjà présente'; end if;
end $p$;
alter policy koki_content_media_admin_write on public.koki_content_media to authenticated;
create policy koki_videos_published on storage.objects for select to anon, authenticated using (bucket_id='koki-videos' and exists(select 1 from public.koki_content_media m join public.koki_contents c on c.id=m.content_id where m.storage_path=objects.name and c.statut='publié' and c.publication<=now() and (c.type<>'Publicités' or (c.actif and (c.fin is null or c.fin>now())))));



-- ===== 29/37 : supabase/historique/reference/sources/prod_20261111224030_commerce_produit_prix_et_stock_facultatifs.sql · sha256 d0a165ab55514a2a
do $t$
declare d text; pairs text[][]; i int; n int;
begin
 d:=pg_get_functiondef('koki_private.commerce_business'::regproc);
 pairs:=array[
  [$a$if input->'price' is null or input->'price'='null'::jsonb then raise exception 'Prix produit obligatoire';end if;
   price:=koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide');stock:=koki_private.commerce_int(input,'stock',1000000,'Stock invalide');$a$,
   $b$price:=case when input ? 'price' and input->'price'<>'null'::jsonb then koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide') end;stock:=case when input ? 'stock' and input->'stock'<>'null'::jsonb then koki_private.commerce_int(input,'stock',1000000,'Stock invalide') end;$b$],
  [$a$if old_price<=price then raise exception 'L’ancien prix doit être supérieur au prix actuel';end if;end if;
   data:=data||jsonb_strip_nulls(jsonb_build_object('prix',price,'stock',stock,'ancien_prix',old_price));$a$,
   $b$if price is null or old_price<=price then raise exception 'L’ancien prix doit être supérieur au prix actuel';end if;end if;
   data:=data||jsonb_strip_nulls(jsonb_build_object('prix',price,'stock',stock,'ancien_prix',old_price));$b$],
  [$a$when entity_kind='produits' and r.statut='Épuisé' and stock>0 then 'Disponible'$a$,$b$when entity_kind='produits' and r.statut='Épuisé' and coalesce(stock,1)>0 then 'Disponible'$b$],
  [$a$set payload=(payload-'ancien_prix'-'zone'-'prix'-'localisation'-'horaires'-'whatsapp')||data$a$,$b$set payload=(payload-'ancien_prix'-'zone'-'prix'-'localisation'-'horaires'-'whatsapp'-'stock')||data$b$]];
 for i in 1..array_length(pairs,1) loop n:=(length(d)-length(replace(d,pairs[i][1],'')))/length(pairs[i][1]);if n<>1 then raise exception 'Préflight commerce_business % : % occurrence(s)',i,n;end if;d:=replace(d,pairs[i][1],pairs[i][2]);end loop;
 execute d;
 d:=pg_get_functiondef('koki_private.business'::regproc);
 pairs:=array[
  [$a$to_jsonb((payload->>'stock')::integer-qty)) where public.koki_records.id=r.id;$a$,$b$to_jsonb((payload->>'stock')::integer-qty)) where public.koki_records.id=r.id and payload->>'stock' is not null;$b$],
  [$a$+(line->>'quantity')::integer)) where public.koki_records.id=(line->>'product_id')::uuid;$a$,$b$+(line->>'quantity')::integer)) where public.koki_records.id=(line->>'product_id')::uuid and payload->>'stock' is not null;$b$]];
 for i in 1..array_length(pairs,1) loop n:=(length(d)-length(replace(d,pairs[i][1],'')))/length(pairs[i][1]);if n<>1 then raise exception 'Préflight business % : % occurrence(s)',i,n;end if;d:=replace(d,pairs[i][1],pairs[i][2]);end loop;
 execute d;
 d:=pg_get_functiondef('koki_private.commerce_admin_before_product_review'::regproc);
 pairs:=array[
  [$a$price:=case when input ? 'price' then koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide') else$a$,$b$price:=case when input ? 'price' and input->'price'<>'null'::jsonb then koki_private.commerce_int(input,'price',1000000000,'Prix catalogue invalide') when input ? 'price' then null else$b$],
  [$a$stock:=case when input ? 'stock' then koki_private.commerce_int(input,'stock',1000000,'Stock invalide') else$a$,$b$stock:=case when input ? 'stock' and input->'stock'<>'null'::jsonb then koki_private.commerce_int(input,'stock',1000000,'Stock invalide') when input ? 'stock' then null else$b$],
  [$a$if old_price is not null and old_price<=price then raise$a$,$b$if old_price is not null and (price is null or old_price<=price) then raise$b$]];
 for i in 1..array_length(pairs,1) loop n:=(length(d)-length(replace(d,pairs[i][1],'')))/length(pairs[i][1]);if n<>1 then raise exception 'Préflight révision % : % occurrence(s)',i,n;end if;d:=replace(d,pairs[i][1],pairs[i][2]);end loop;
 execute d;
end $t$;



-- ===== 30/37 : supabase/historique/reference/sources/prod_20261111234728_notifications_ciblees_publications.sql · sha256 7610ae6521a6e2c6
do $p$ begin
 if to_regclass('public.koki_user_interests') is not null or to_regclass('public.koki_content_notified') is not null then raise exception 'Préflight : déjà appliqué'; end if;
end $p$;
create table public.koki_user_interests(user_id uuid primary key references auth.users(id) on delete cascade, types jsonb not null default '{}'::jsonb, categories jsonb not null default '{}'::jsonb, actif boolean not null default true, updated_at timestamptz not null default now());
alter table public.koki_user_interests enable row level security;
revoke all on public.koki_user_interests from anon, authenticated;
grant select on public.koki_user_interests to authenticated;
create policy interests_self_read on public.koki_user_interests for select to authenticated using (user_id=(select auth.uid()));
create function koki_private.interests_clean(o jsonb) returns jsonb language plpgsql immutable set search_path to '' as $f$
declare k text; v jsonb; out jsonb:='{}'::jsonb; c int:=0;
begin
 if o is null or jsonb_typeof(o)<>'object' then return '{}'::jsonb;end if;
 for k,v in select key,value from jsonb_each(o) loop
  if char_length(k) between 1 and 80 and jsonb_typeof(v)='number' and (v#>>'{}')::numeric>0 then out:=out||jsonb_build_object(k,round(least((v#>>'{}')::numeric,50),2));c:=c+1;end if;
  exit when c>=60;
 end loop;
 return out;
end $f$;
create function public.koki_interests_sync(p_types jsonb, p_categories jsonb, p_actif boolean default true) returns void language plpgsql security definer set search_path to '' as $f$
declare actor uuid:=auth.uid();
begin
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Connexion requise' using errcode='42501';end if;
 if octet_length(coalesce(p_types,'{}'::jsonb)::text)+octet_length(coalesce(p_categories,'{}'::jsonb)::text)>16000 then raise exception 'Données trop volumineuses';end if;
 insert into public.koki_user_interests(user_id,types,categories,actif,updated_at)
 values(actor,case when coalesce(p_actif,true) then koki_private.interests_clean(p_types) else '{}'::jsonb end,case when coalesce(p_actif,true) then koki_private.interests_clean(p_categories) else '{}'::jsonb end,coalesce(p_actif,true),now())
 on conflict(user_id) do update set types=excluded.types,categories=excluded.categories,actif=excluded.actif,updated_at=now();
end $f$;
revoke all on function public.koki_interests_sync(jsonb,jsonb,boolean) from public, anon;
grant execute on function public.koki_interests_sync(jsonb,jsonb,boolean) to authenticated;
revoke all on function koki_private.interests_clean(jsonb) from public, anon, authenticated;
alter table public.koki_notifications alter column record_id drop not null;
alter table public.koki_notifications add column content_id uuid references public.koki_contents(id) on delete cascade;
alter table public.koki_notifications add constraint koki_notifications_cible check ((record_id is null) <> (content_id is null));
create unique index koki_notifications_recipient_content on public.koki_notifications(recipient_id,content_id) where content_id is not null;
create table public.koki_content_notified(content_id uuid primary key references public.koki_contents(id) on delete cascade, notified_at timestamptz not null default now(), destinataires integer not null default 0);
alter table public.koki_content_notified enable row level security;
revoke all on public.koki_content_notified from anon, authenticated;
insert into public.koki_content_notified(content_id) select id from public.koki_contents where statut='publié' and publication<=now();
create function koki_private.notify_contents() returns integer language plpgsql security definer set search_path to '' as $f$
declare c record; n integer; total integer:=0;
begin
 perform pg_advisory_xact_lock(hashtextextended('koki_notify_contents',0));
 for c in select id,type,categorie,titre,resume,une from public.koki_contents x where statut='publié' and publication<=now() and publication>now()-interval '2 days' and type<>'Publicités'
  and not exists(select 1 from public.koki_content_notified d where d.content_id=x.id) order by publication limit 20 loop
  insert into public.koki_notifications(recipient_id,content_id,revision,title,body,category)
  select distinct s.user_id,c.id,0,left(c.titre,120),left(coalesce(nullif(c.resume,''),c.type),240),c.type
  from public.koki_push_subscriptions s left join public.koki_user_interests i on i.user_id=s.user_id
  where c.une or (i.actif and (coalesce((i.types->>c.type)::numeric,0)>=2 or coalesce((i.categories->>c.categorie)::numeric,0)>=2))
  on conflict do nothing;
  get diagnostics n=row_count;
  insert into public.koki_content_notified(content_id,destinataires) values(c.id,n) on conflict do nothing;
  total:=total+n;
 end loop;
 return total;
end $f$;
revoke all on function koki_private.notify_contents() from public, anon, authenticated;
do $c$
declare d text; n int;
begin
 d:=pg_get_functiondef('public.koki_notification_claim'::regproc);
 n:=(length(d)-length(replace(d,$a$where n.created_at>now()-interval '1 day' and p.sms and$a$,'')))/length($a$where n.created_at>now()-interval '1 day' and p.sms and$a$);
 if n<>1 then raise exception 'Préflight claim : % occurrence(s)',n;end if;
 execute replace(d,$a$where n.created_at>now()-interval '1 day' and p.sms and$a$,$b$where n.created_at>now()-interval '1 day' and n.content_id is null and p.sms and$b$);
end $c$;
select cron.schedule('koki-notify-contents','*/5 * * * *','select koki_private.notify_contents()');



-- ===== 31/37 : supabase/historique/reference/sources/prod_20261117073437_social_resume_avec_commentaires.sql · sha256 4adcef300701ab0f
do $t$
declare d text; n int;
begin
 d:=pg_get_functiondef('koki_social_private.summaries'::regproc);
 if position('''comments''' in d)>0 then raise exception 'Préflight : déjà appliqué';end if;
 n:=(length(d)-length(replace(d,$a$'liked',exists($a$,'')))/length($a$'liked',exists($a$);
 if n<>1 then raise exception 'Préflight : % occurrence(s)',n;end if;
 execute replace(d,$a$'liked',exists($a$,$b$'comments',(select count(*) from koki_social_private.comments k where k.content_id=c.id and not k.hidden),'liked',exists($b$);
end $t$;



-- ===== 32/37 : supabase/historique/reference/sources/prod_20261117075306_notifications_koki_en_direct.sql · sha256 d1553dbb7cd17f13
do $t$
declare d text; n int;
begin
 d:=pg_get_functiondef('koki_private.notify_contents'::regproc);
 if position('Décès et cérémonies' in d)>0 then raise exception 'Préflight : déjà appliqué';end if;
 n:=(length(d)-length(replace(d,$a$where c.une or (i.actif and$a$,'')))/length($a$where c.une or (i.actif and$a$);
 if n<>1 then raise exception 'Préflight : % occurrence(s)',n;end if;
 execute replace(d,$a$where c.une or (i.actif and$a$,$b$where c.une or (c.type='Annonces' and c.categorie in ('Décès et cérémonies','Coupure eau/électricité','Avis important')) or (c.type='Sports & ASC' and c.categorie='Résultat') or (i.actif and$b$);
end $t$;

-- ===== 33/37 : supabase/historique/reference/sources/rattrapage_01_content_images.sql · sha256 7df8709348344be6
-- Rattrapage : table des photos multiples des publications, créée à la main en production (aucun fichier source).
-- Définition relevée en production le 18/11/2026 (lecture seule).
create table public.koki_content_images(
 id uuid default gen_random_uuid() not null,
 content_id uuid not null,
 storage_path text not null,
 display_order integer default 0 not null,
 created_at timestamp with time zone default now() not null
);
alter table public.koki_content_images add constraint koki_content_images_pkey PRIMARY KEY (id);
alter table public.koki_content_images add constraint koki_content_images_content_id_fkey FOREIGN KEY (content_id) REFERENCES koki_contents(id) ON DELETE CASCADE;
alter table public.koki_content_images add constraint koki_content_images_display_order_check CHECK ((display_order >= 0));
alter table public.koki_content_images add constraint koki_content_images_storage_path_check CHECK ((storage_path ~ '^[a-f0-9-]+/[a-f0-9-]+\\.(jpg|png|webp)$'::text));
CREATE INDEX koki_content_images_content_order ON public.koki_content_images USING btree (content_id, display_order);
alter table public.koki_content_images enable row level security;
create policy koki_content_images_admin_write on public.koki_content_images as permissive for all to authenticated using ((EXISTS ( SELECT 1
   FROM koki_admin_members m
  WHERE ((m.user_id = auth.uid()) AND m.enabled AND (m.role = ANY (ARRAY['superadmin'::text, 'editor'::text])))))) with check ((EXISTS ( SELECT 1
   FROM koki_admin_members m
  WHERE ((m.user_id = auth.uid()) AND m.enabled AND (m.role = ANY (ARRAY['superadmin'::text, 'editor'::text]))))));
create policy koki_content_images_public_read on public.koki_content_images as permissive for select to anon, authenticated using ((EXISTS ( SELECT 1
   FROM koki_contents c
  WHERE ((c.id = koki_content_images.content_id) AND (c.statut = 'publié'::text) AND (c.publication <= now())))));


-- ===== 34/37 : supabase/historique/reference/sources/public_account-deletion.sql · sha256 2741e81139befbc6
-- Suppression du compte par son titulaire (Apple, règle 5.1.1(v)) — à appliquer en production uniquement avec accord.
-- Deux étapes appelées par l'application, avec le même mot de confirmation « SUPPRIMER » :
--   1. 'contenus' : efface les contenus et les données du compte (le compte de connexion reste, pour que
--      l'application puisse ensuite effacer ses photos du stockage, devenues non référencées) ;
--   2. 'compte'   : efface le dossier de photos réservé et le compte de connexion lui-même.
-- Ce qui part avec le compte : fiches professionnelles, boutiques, produits, services, chauffeur et véhicules,
-- commandes et courses passées par le compte ou reçues par ses fiches, commentaires, « J'aime », avis,
-- signalements, blocages, centres d'intérêt, notifications et abonnements aux notifications.
-- Conservé : le journal d'audit de l'administration (identifiant technique seulement, aucune donnée de profil).
-- Un compte d'administration est refusé : ses droits doivent d'abord être retirés dans l'administration.

create or replace function public.koki_account_delete(p_etape text, p_confirmation text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor uuid := auth.uid();
  possede uuid[];
  ordres uuid[];
  dossiers text[];
  n_fiches integer := 0;
  n_ordres integer := 0;
begin
  if actor is null then raise exception 'Connexion requise' using errcode = '42501'; end if;
  if p_confirmation is distinct from 'SUPPRIMER' then raise exception 'Confirmation invalide : saisissez SUPPRIMER'; end if;
  if p_etape not in ('contenus', 'compte') then raise exception 'Étape invalide'; end if;
  if exists (select 1 from public.koki_admin_members m where m.user_id = actor) then
    raise exception 'Compte d’administration : ses droits doivent d’abord être retirés dans l’administration.' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('koki_account_delete:' || actor::text, 0));

  if p_etape = 'contenus' then
    select coalesce(array_agg(id), '{}') into possede from public.koki_records where owner_id = actor;
    select coalesce(array_agg(id), '{}') into ordres from public.koki_records
      where kind in ('commandes', 'demandes_services', 'courses')
        and (client_id = actor or parent_id = any(possede) or provider_id = any(possede) or driver_id = any(possede));
    -- Courses : devis, notes et signalements liés.
    delete from koki_private.ride_quotes where ride_id = any(ordres) or client_id = actor;
    delete from koki_private.ride_ratings where ride_id = any(ordres) or client_id = actor or driver_id = any(possede);
    delete from koki_private.ride_reports where ride_id = any(ordres) or reporter_id = actor;
    -- Commandes : lignes puis commandes, avant les produits et boutiques qu'elles désignent.
    delete from public.koki_order_items where order_id = any(ordres) or product_id = any(possede);
    delete from public.koki_records where id = any(ordres);
    get diagnostics n_ordres = row_count;
    -- Fiches du compte, des plus dépendantes aux plus générales.
    delete from public.koki_records where id = any(possede) and kind in ('produits', 'services', 'vehicules');
    delete from public.koki_records where id = any(possede) and kind = 'boutiques';
    delete from public.koki_records where id = any(possede) and kind in ('professionnels', 'chauffeurs');
    n_fiches := cardinality(possede);
    -- Interactions et préférences.
    delete from koki_social_private.comments where user_id = actor;
    delete from koki_social_private.likes where user_id = actor;
    delete from koki_social_private.reports where reporter_id = actor;
    delete from koki_social_private.blocks where blocker_id = actor or blocked_id = actor;
    delete from koki_social_private.comment_events where user_id = actor;
    delete from public.koki_reviews where author_id = actor;
    delete from public.koki_user_interests where user_id = actor;
    delete from public.koki_notification_preferences where user_id = actor;
    delete from public.koki_push_subscriptions where user_id = actor;
    delete from public.koki_notifications where recipient_id = actor;
    delete from koki_private.nearby_lookups where actor_id = actor;
    delete from koki_private.business_keys where actor_id = actor;
    -- Dossiers de photos à vider par l'application (son propre identifiant et son dossier réservé).
    select array_remove(array[actor::text, (select f.folder::text from koki_private.media_folders f where f.user_id = actor limit 1)], null) into dossiers;
    return jsonb_build_object('etape', 'contenus', 'fiches', n_fiches, 'commandes', n_ordres, 'dossiers', to_jsonb(dossiers));
  end if;

  -- Étape 'compte'
  if exists (select 1 from public.koki_records where owner_id = actor or client_id = actor) then
    raise exception 'Effacez d’abord les contenus du compte.';
  end if;
  delete from koki_private.media_folders where user_id = actor;
  delete from auth.users where id = actor;
  return jsonb_build_object('etape', 'compte', 'supprime', true);
end
$function$;

revoke all on function public.koki_account_delete(text, text) from public, anon;
grant execute on function public.koki_account_delete(text, text) to authenticated;


-- ===== 35/37 : supabase/historique/reference/sources/rattrapage_02_account_delete.sql · sha256 515472ecde0d21e7
-- Rattrapage : version de production de koki_account_delete (relevée le 18/11/2026).
CREATE OR REPLACE FUNCTION public.koki_account_delete(p_etape text, p_confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  possede uuid[];
  ordres uuid[];
  dossiers text[];
  n_fiches integer := 0;
  n_ordres integer := 0;
begin
  if actor is null then raise exception 'Connexion requise' using errcode = '42501'; end if;
  if p_confirmation is distinct from 'SUPPRIMER' then raise exception 'Confirmation invalide : saisissez SUPPRIMER'; end if;
  if p_etape not in ('contenus', 'compte') then raise exception 'Étape invalide'; end if;
  if exists (select 1 from public.koki_admin_members m where m.user_id = actor) then
    raise exception 'Compte d’administration : ses droits doivent d’abord être retirés dans l’administration.' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('koki_account_delete:' || actor::text, 0));

  if p_etape = 'contenus' then
    select coalesce(array_agg(id), '{}') into possede from public.koki_records where owner_id = actor;
    select coalesce(array_agg(id), '{}') into ordres from public.koki_records
      where kind in ('commandes', 'demandes_services', 'courses')
        and (client_id = actor or parent_id = any(possede) or provider_id = any(possede) or driver_id = any(possede));
    delete from koki_private.ride_quotes where ride_id = any(ordres) or client_id = actor;
    delete from koki_private.ride_ratings where ride_id = any(ordres) or client_id = actor or driver_id = any(possede);
    delete from koki_private.ride_reports where ride_id = any(ordres) or reporter_id = actor;
    delete from public.koki_order_items where order_id = any(ordres) or product_id = any(possede);
    delete from public.koki_records where id = any(ordres);
    get diagnostics n_ordres = row_count;
    delete from public.koki_records where id = any(possede) and kind in ('produits', 'services', 'vehicules');
    delete from public.koki_records where id = any(possede) and kind = 'boutiques';
    delete from public.koki_records where id = any(possede) and kind in ('professionnels', 'chauffeurs');
    n_fiches := cardinality(possede);
    delete from koki_social_private.comments where user_id = actor;
    delete from koki_social_private.likes where user_id = actor;
    delete from koki_social_private.reports where reporter_id = actor;
    delete from koki_social_private.blocks where blocker_id = actor or blocked_id = actor;
    delete from koki_social_private.comment_events where user_id = actor;
    delete from public.koki_reviews where author_id = actor;
    delete from public.koki_user_interests where user_id = actor;
    delete from public.koki_notification_preferences where user_id = actor;
    delete from public.koki_push_subscriptions where user_id = actor;
    delete from public.koki_notifications where recipient_id = actor;
    delete from koki_private.nearby_lookups where actor_id = actor;
    delete from koki_private.business_keys where actor_id = actor;
    select array_remove(array[actor::text, (select f.folder::text from koki_private.media_folders f where f.user_id = actor limit 1)], null) into dossiers;
    return jsonb_build_object('etape', 'contenus', 'fiches', n_fiches, 'commandes', n_ordres, 'dossiers', to_jsonb(dossiers));
  end if;

  if exists (select 1 from public.koki_records where owner_id = actor or client_id = actor) then
    raise exception 'Effacez d’abord les contenus du compte.';
  end if;
  delete from koki_private.media_folders where user_id = actor;
  delete from auth.users where id = actor;
  return jsonb_build_object('etape', 'compte', 'supprime', true);
end
$function$
;


-- ===== 36/37 : supabase/historique/reference/sources/public_signalements-fiches.sql · sha256 86f9fb1e25bab632
-- Signaler une fiche (produit, service, boutique, professionnel) — Apple, règle 1.2 (contenus publiés par les utilisateurs).
-- À appliquer en production uniquement avec accord. Ne modifie aucune table ni fonction existante.
--  1. koki_private.record_reports : un signalement par fiche et par compte (un nouveau signalement remplace l'ancien
--     et le repasse « Nouveau »). Effacé avec la fiche ou avec le compte qui l'a envoyé. Aucun accès direct.
--  2. public.koki_record_report : envoi par un compte permanent connecté, sur une fiche publique qui n'est pas la sienne,
--     20 signalements par jour au plus.
--  3. public.koki_record_reports_admin : liste (100 plus récents) et traitement Nouveau / En cours / Traité, réservés
--     au droit Commerce avec double authentification, chaque changement inscrit au journal des opérations.
-- Retour arrière : en fin de fichier.

create table koki_private.record_reports(
  id uuid primary key default gen_random_uuid(),
  record_id uuid not null references public.koki_records(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  motif text not null check (motif in ('Arnaque ou fraude','Contenu choquant','Produit interdit','Fausses informations','Autre')),
  details text check (details is null or char_length(details) between 3 and 500),
  statut text not null default 'Nouveau' check (statut in ('Nouveau','En cours','Traité')),
  note_admin text check (note_admin is null or char_length(note_admin) between 3 and 500),
  traite_le timestamptz,
  traite_par uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (record_id, reporter_id)
);
create index record_reports_recents on koki_private.record_reports(created_at desc);
create index record_reports_auteur on koki_private.record_reports(reporter_id, created_at);
alter table koki_private.record_reports enable row level security;
revoke all on koki_private.record_reports from public, anon, authenticated;

create function public.koki_record_report(p_target uuid, p_motif text, p_details text default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare actor uuid := (select auth.uid()); texte text := nullif(btrim(coalesce(p_details,'')),''); proprio uuid;
begin
  if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
    raise exception 'Connectez-vous avec votre compte pour signaler une fiche.' using errcode='42501'; end if;
  if p_motif is null or p_motif not in ('Arnaque ou fraude','Contenu choquant','Produit interdit','Fausses informations','Autre') then
    raise exception 'Choisissez un motif.'; end if;
  if texte is not null and char_length(texte) not between 3 and 500 then raise exception 'Le détail doit contenir de 3 à 500 caractères.'; end if;
  if p_motif = 'Autre' and texte is null then raise exception 'Précisez le problème.'; end if;
  if p_target is null or not koki_private.is_public_listing(p_target) then raise exception 'Cette fiche n''est plus disponible.'; end if;
  select owner_id into proprio from public.koki_records where id = p_target;
  if proprio = actor then raise exception 'Vous ne pouvez pas signaler votre propre fiche.'; end if;
  if (select count(*) from koki_private.record_reports where reporter_id = actor and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Trop de signalements aujourd''hui. Réessayez demain.'; end if;
  insert into koki_private.record_reports(record_id, reporter_id, motif, details) values (p_target, actor, p_motif, texte)
    on conflict (record_id, reporter_id) do update set motif = excluded.motif, details = excluded.details, statut = 'Nouveau', created_at = now();
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.koki_record_report(uuid, text, text) from public, anon;
grant execute on function public.koki_record_report(uuid, text, text) to authenticated;

create function public.koki_record_reports_admin(p_action text, p_id uuid default null, p_statut text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare actor uuid := (select auth.uid()); x koki_private.record_reports; note text := nullif(btrim(coalesce(p_note,'')),''); avant text;
begin
  if actor is null or not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501'; end if;
  if p_action = 'liste' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'record_id',r.record_id,'motif',r.motif,'details',r.details,'statut',r.statut,
        'note_admin',r.note_admin,'traite_le',r.traite_le,'created_at',r.created_at,'fiche',coalesce(k.payload->>'nom',k.payload->>'titre','Fiche'),
        'kind',k.kind,'fiche_statut',k.statut,'total',(select count(*) from koki_private.record_reports t where t.record_id=r.record_id)) order by r.created_at desc)
      from (select * from koki_private.record_reports order by created_at desc limit 100) r join public.koki_records k on k.id = r.record_id), '[]'::jsonb);
  end if;
  if p_action <> 'statut' then raise exception 'Action inconnue'; end if;
  if p_statut is null or p_statut not in ('Nouveau','En cours','Traité') then raise exception 'Statut de signalement invalide'; end if;
  if note is not null and char_length(note) not between 3 and 500 then raise exception 'Note de 3 à 500 caractères'; end if;
  if p_statut = 'Traité' and note is null then raise exception 'Indiquez ce qui a été fait (note obligatoire pour « Traité »)'; end if;
  select * into x from koki_private.record_reports where id = p_id for update;
  if x.id is null then raise exception 'Signalement introuvable'; end if;
  avant := x.statut;
  update koki_private.record_reports set statut = p_statut, note_admin = coalesce(note, note_admin), traite_le = now(), traite_par = actor
    where id = x.id returning * into x;
  insert into public.koki_audit(actor_id, operation, table_name, record_id, details)
    values (actor, 'SIGNALEMENT', 'record_reports', x.id, jsonb_strip_nulls(jsonb_build_object('avant',avant,'apres',x.statut,'note',note,'fiche',x.record_id)));
  return jsonb_build_object('id',x.id,'statut',x.statut,'note_admin',x.note_admin,'traite_le',x.traite_le);
end $$;
revoke all on function public.koki_record_reports_admin(text, uuid, text, text) from public, anon;
grant execute on function public.koki_record_reports_admin(text, uuid, text, text) to authenticated;

-- Retour arrière :
-- drop function public.koki_record_reports_admin(text, uuid, text, text);
-- drop function public.koki_record_report(uuid, text, text);
-- drop table koki_private.record_reports;


-- ===== 37/37 : supabase/historique/reference/sources/rattrapage_99_droits.sql · sha256 3265906d6771ecaf
-- Droits (ACL) relevés en production le 18/11/2026, lecture seule.
-- Normalise anon/authenticated/service_role/public sur public, koki_private, koki_social_private.
begin;
revoke all on schema koki_private from public, anon, authenticated, service_role;
grant USAGE on schema koki_private to anon;
grant USAGE on schema koki_private to authenticated;
revoke all on schema koki_social_private from public, anon, authenticated, service_role;
grant USAGE on schema koki_social_private to anon;
grant USAGE on schema koki_social_private to authenticated;
revoke all on schema public from public, anon, authenticated, service_role;
grant USAGE on schema public to public;
grant USAGE on schema public to anon;
grant USAGE on schema public to authenticated;
grant USAGE on schema public to service_role;
revoke all on table koki_private.activity_dedup from public, anon, authenticated, service_role;
revoke all on table koki_private.business_keys from public, anon, authenticated, service_role;
revoke all on table koki_private.media_folders from public, anon, authenticated, service_role;
revoke all on table koki_private.migration_archive from public, anon, authenticated, service_role;
revoke all on table koki_private.nearby_lookups from public, anon, authenticated, service_role;
revoke all on sequence koki_private.nearby_lookups_id_seq from public, anon, authenticated, service_role;
revoke all on table koki_private.record_reports from public, anon, authenticated, service_role;
revoke all on table koki_private.ride_codes from public, anon, authenticated, service_role;
revoke all on table koki_private.ride_quotes from public, anon, authenticated, service_role;
revoke all on table koki_private.ride_ratings from public, anon, authenticated, service_role;
revoke all on table koki_private.ride_reports from public, anon, authenticated, service_role;
revoke all on table koki_social_private.blocks from public, anon, authenticated, service_role;
revoke all on table koki_social_private.comment_events from public, anon, authenticated, service_role;
revoke all on sequence koki_social_private.comment_events_id_seq from public, anon, authenticated, service_role;
revoke all on table koki_social_private.comments from public, anon, authenticated, service_role;
revoke all on table koki_social_private.likes from public, anon, authenticated, service_role;
revoke all on table koki_social_private.moderation_log from public, anon, authenticated, service_role;
revoke all on sequence koki_social_private.moderation_log_id_seq from public, anon, authenticated, service_role;
revoke all on table koki_social_private.reports from public, anon, authenticated, service_role;
revoke all on table public.koki_activity from public, anon, authenticated, service_role;
grant REFERENCES on table public.koki_activity to service_role;
grant TRIGGER on table public.koki_activity to service_role;
grant TRUNCATE on table public.koki_activity to service_role;
-- PG17 : grant maintain on table public.koki_activity to service_role;
revoke all on table public.koki_admin_members from public, anon, authenticated, service_role;
grant SELECT on table public.koki_admin_members to authenticated;
grant REFERENCES on table public.koki_admin_members to service_role;
grant TRIGGER on table public.koki_admin_members to service_role;
grant TRUNCATE on table public.koki_admin_members to service_role;
-- PG17 : grant maintain on table public.koki_admin_members to service_role;
revoke all on table public.koki_audit from public, anon, authenticated, service_role;
grant SELECT on table public.koki_audit to authenticated;
grant REFERENCES on table public.koki_audit to service_role;
grant TRIGGER on table public.koki_audit to service_role;
grant TRUNCATE on table public.koki_audit to service_role;
-- PG17 : grant maintain on table public.koki_audit to service_role;
revoke all on sequence public.koki_audit_id_seq from public, anon, authenticated, service_role;
revoke all on table public.koki_content_images from public, anon, authenticated, service_role;
grant REFERENCES on table public.koki_content_images to anon;
grant SELECT on table public.koki_content_images to anon;
grant TRIGGER on table public.koki_content_images to anon;
grant TRUNCATE on table public.koki_content_images to anon;
grant DELETE on table public.koki_content_images to authenticated;
grant INSERT on table public.koki_content_images to authenticated;
grant REFERENCES on table public.koki_content_images to authenticated;
grant SELECT on table public.koki_content_images to authenticated;
grant TRIGGER on table public.koki_content_images to authenticated;
grant TRUNCATE on table public.koki_content_images to authenticated;
grant UPDATE on table public.koki_content_images to authenticated;
grant REFERENCES on table public.koki_content_images to service_role;
grant TRIGGER on table public.koki_content_images to service_role;
grant TRUNCATE on table public.koki_content_images to service_role;
-- PG17 : grant maintain on table public.koki_content_images to anon; grant maintain on table public.koki_content_images to authenticated; grant maintain on table public.koki_content_images to service_role;
revoke all on table public.koki_content_media from public, anon, authenticated, service_role;
grant REFERENCES on table public.koki_content_media to anon;
grant SELECT on table public.koki_content_media to anon;
grant TRIGGER on table public.koki_content_media to anon;
grant TRUNCATE on table public.koki_content_media to anon;
grant DELETE on table public.koki_content_media to authenticated;
grant INSERT on table public.koki_content_media to authenticated;
grant REFERENCES on table public.koki_content_media to authenticated;
grant SELECT on table public.koki_content_media to authenticated;
grant TRIGGER on table public.koki_content_media to authenticated;
grant TRUNCATE on table public.koki_content_media to authenticated;
grant UPDATE on table public.koki_content_media to authenticated;
grant REFERENCES on table public.koki_content_media to service_role;
grant TRIGGER on table public.koki_content_media to service_role;
grant TRUNCATE on table public.koki_content_media to service_role;
-- PG17 : grant maintain on table public.koki_content_media to anon; grant maintain on table public.koki_content_media to authenticated; grant maintain on table public.koki_content_media to service_role;
revoke all on table public.koki_content_notified from public, anon, authenticated, service_role;
grant REFERENCES on table public.koki_content_notified to service_role;
grant TRIGGER on table public.koki_content_notified to service_role;
grant TRUNCATE on table public.koki_content_notified to service_role;
-- PG17 : grant maintain on table public.koki_content_notified to service_role;
revoke all on table public.koki_contents from public, anon, authenticated, service_role;
grant SELECT on table public.koki_contents to anon;
grant DELETE on table public.koki_contents to authenticated;
grant INSERT on table public.koki_contents to authenticated;
grant SELECT on table public.koki_contents to authenticated;
grant UPDATE on table public.koki_contents to authenticated;
grant REFERENCES on table public.koki_contents to service_role;
grant TRIGGER on table public.koki_contents to service_role;
grant TRUNCATE on table public.koki_contents to service_role;
-- PG17 : grant maintain on table public.koki_contents to service_role;
revoke all on table public.koki_localites from public, anon, authenticated, service_role;
grant SELECT on table public.koki_localites to anon;
grant INSERT on table public.koki_localites to authenticated;
grant SELECT on table public.koki_localites to authenticated;
grant UPDATE on table public.koki_localites to authenticated;
grant REFERENCES on table public.koki_localites to service_role;
grant TRIGGER on table public.koki_localites to service_role;
grant TRUNCATE on table public.koki_localites to service_role;
-- PG17 : grant maintain on table public.koki_localites to service_role;
revoke all on table public.koki_notification_deliveries from public, anon, authenticated, service_role;
grant DELETE on table public.koki_notification_deliveries to service_role;
grant INSERT on table public.koki_notification_deliveries to service_role;
grant REFERENCES on table public.koki_notification_deliveries to service_role;
grant SELECT on table public.koki_notification_deliveries to service_role;
grant TRIGGER on table public.koki_notification_deliveries to service_role;
grant TRUNCATE on table public.koki_notification_deliveries to service_role;
grant UPDATE on table public.koki_notification_deliveries to service_role;
-- PG17 : grant maintain on table public.koki_notification_deliveries to service_role;
revoke all on table public.koki_notification_preferences from public, anon, authenticated, service_role;
grant INSERT on table public.koki_notification_preferences to authenticated;
grant SELECT on table public.koki_notification_preferences to authenticated;
grant UPDATE on table public.koki_notification_preferences to authenticated;
grant DELETE on table public.koki_notification_preferences to service_role;
grant INSERT on table public.koki_notification_preferences to service_role;
grant REFERENCES on table public.koki_notification_preferences to service_role;
grant SELECT on table public.koki_notification_preferences to service_role;
grant TRIGGER on table public.koki_notification_preferences to service_role;
grant TRUNCATE on table public.koki_notification_preferences to service_role;
grant UPDATE on table public.koki_notification_preferences to service_role;
-- PG17 : grant maintain on table public.koki_notification_preferences to service_role;
revoke all on table public.koki_notifications from public, anon, authenticated, service_role;
grant SELECT on table public.koki_notifications to authenticated;
grant DELETE on table public.koki_notifications to service_role;
grant INSERT on table public.koki_notifications to service_role;
grant REFERENCES on table public.koki_notifications to service_role;
grant SELECT on table public.koki_notifications to service_role;
grant TRIGGER on table public.koki_notifications to service_role;
grant TRUNCATE on table public.koki_notifications to service_role;
grant UPDATE on table public.koki_notifications to service_role;
-- PG17 : grant maintain on table public.koki_notifications to service_role;
revoke all on table public.koki_order_items from public, anon, authenticated, service_role;
grant SELECT on table public.koki_order_items to authenticated;
grant REFERENCES on table public.koki_order_items to service_role;
grant TRIGGER on table public.koki_order_items to service_role;
grant TRUNCATE on table public.koki_order_items to service_role;
-- PG17 : grant maintain on table public.koki_order_items to service_role;
revoke all on table public.koki_push_subscriptions from public, anon, authenticated, service_role;
grant DELETE on table public.koki_push_subscriptions to authenticated;
grant SELECT on table public.koki_push_subscriptions to authenticated;
grant DELETE on table public.koki_push_subscriptions to service_role;
grant INSERT on table public.koki_push_subscriptions to service_role;
grant REFERENCES on table public.koki_push_subscriptions to service_role;
grant SELECT on table public.koki_push_subscriptions to service_role;
grant TRIGGER on table public.koki_push_subscriptions to service_role;
grant TRUNCATE on table public.koki_push_subscriptions to service_role;
grant UPDATE on table public.koki_push_subscriptions to service_role;
-- PG17 : grant maintain on table public.koki_push_subscriptions to service_role;
revoke all on table public.koki_records from public, anon, authenticated, service_role;
grant SELECT on table public.koki_records to authenticated;
grant REFERENCES on table public.koki_records to service_role;
grant TRIGGER on table public.koki_records to service_role;
grant TRUNCATE on table public.koki_records to service_role;
-- PG17 : grant maintain on table public.koki_records to service_role;
revoke all on table public.koki_reviews from public, anon, authenticated, service_role;
grant SELECT on table public.koki_reviews to authenticated;
grant REFERENCES on table public.koki_reviews to service_role;
grant TRIGGER on table public.koki_reviews to service_role;
grant TRUNCATE on table public.koki_reviews to service_role;
-- PG17 : grant maintain on table public.koki_reviews to service_role;
revoke all on table public.koki_transport_rates from public, anon, authenticated, service_role;
grant SELECT on table public.koki_transport_rates to anon;
grant SELECT on table public.koki_transport_rates to authenticated;
grant REFERENCES on table public.koki_transport_rates to service_role;
grant TRIGGER on table public.koki_transport_rates to service_role;
grant TRUNCATE on table public.koki_transport_rates to service_role;
-- PG17 : grant maintain on table public.koki_transport_rates to service_role;
revoke all on table public.koki_user_interests from public, anon, authenticated, service_role;
grant SELECT on table public.koki_user_interests to authenticated;
grant REFERENCES on table public.koki_user_interests to service_role;
grant TRIGGER on table public.koki_user_interests to service_role;
grant TRUNCATE on table public.koki_user_interests to service_role;
-- PG17 : grant maintain on table public.koki_user_interests to service_role;
revoke all on table public.koki_users from public, anon, authenticated, service_role;
grant SELECT on table public.koki_users to authenticated;
grant REFERENCES on table public.koki_users to service_role;
grant TRIGGER on table public.koki_users to service_role;
grant TRUNCATE on table public.koki_users to service_role;
-- PG17 : grant maintain on table public.koki_users to service_role;
revoke all on function koki_private.allowed(permission text) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.allowed(permission text) to authenticated;
revoke all on function koki_private.audit() from public, anon, authenticated, service_role;
revoke all on function koki_private.business(command text, input jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.business_can_read(r koki_records) from public, anon, authenticated, service_role;
revoke all on function koki_private.business_distance(a jsonb, b jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.business_image_unreferenced(path text) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.business_image_unreferenced(path text) to authenticated;
revoke all on function koki_private.business_item_relation() from public, anon, authenticated, service_role;
revoke all on function koki_private.business_keys_allowed(input jsonb, allowed text[]) from public, anon, authenticated, service_role;
revoke all on function koki_private.business_owned_image(path text) from public, anon, authenticated, service_role;
revoke all on function koki_private.business_participant_image(path text) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.business_participant_image(path text) to authenticated;
revoke all on function koki_private.business_point(point jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.business_public_image(path text) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.business_public_image(path text) to anon;
grant EXECUTE on function koki_private.business_public_image(path text) to authenticated;
revoke all on function koki_private.business_relations() from public, anon, authenticated, service_role;
revoke all on function koki_private.business_text(input jsonb, field text, minimum integer, maximum integer) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_admin(command text, input jsonb) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.commerce_admin(command text, input jsonb) to anon;
grant EXECUTE on function koki_private.commerce_admin(command text, input jsonb) to authenticated;
revoke all on function koki_private.commerce_admin_before_product_review(command text, input jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_admin_view(r koki_records) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_business(command text, input jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_catalog() from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_int(input jsonb, field text, maximum bigint, message text) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_parent_actif(r koki_records) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_phone(input jsonb, field text) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_photos(input jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_publie(r koki_records) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_sensibles(payload jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.commerce_village(input jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.ensure_initial_shop(p koki_records) from public, anon, authenticated, service_role;
revoke all on function koki_private.initial_shop_after_profile() from public, anon, authenticated, service_role;
revoke all on function koki_private.interests_clean(o jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.is_public_listing(p_id uuid) from public, anon, authenticated, service_role;
revoke all on function koki_private.livre_gratuit_publie(path text) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.livre_gratuit_publie(path text) to anon;
grant EXECUTE on function koki_private.livre_gratuit_publie(path text) to authenticated;
revoke all on function koki_private.merchant_business(command text, input jsonb) from public, anon, authenticated, service_role;
revoke all on function koki_private.my_media_folder() from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.my_media_folder() to authenticated;
revoke all on function koki_private.notification_health() from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.notification_health() to authenticated;
revoke all on function koki_private.notify_contents() from public, anon, authenticated, service_role;
revoke all on function koki_private.notify_record() from public, anon, authenticated, service_role;
revoke all on function koki_private.owns_business(record_id uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.owns_business(record_id uuid) to authenticated;
revoke all on function koki_private.product_review_required() from public, anon, authenticated, service_role;
revoke all on function koki_private.refus_motive() from public, anon, authenticated, service_role;
revoke all on function koki_private.register_user() from public, anon, authenticated, service_role;
revoke all on function koki_private.ride_code_create() from public, anon, authenticated, service_role;
revoke all on function koki_private.ride_guard() from public, anon, authenticated, service_role;
revoke all on function koki_private.ride_reports_admin(command text, input jsonb) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.ride_reports_admin(command text, input jsonb) to anon;
grant EXECUTE on function koki_private.ride_reports_admin(command text, input jsonb) to authenticated;
revoke all on function koki_private.stamp() from public, anon, authenticated, service_role;
revoke all on function koki_private.track(p_target uuid, p_kind text) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.track(p_target uuid, p_kind text) to anon;
grant EXECUTE on function koki_private.track(p_target uuid, p_kind text) to authenticated;
revoke all on function koki_private.transport_plus(command text, input jsonb) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_private.transport_plus(command text, input jsonb) to anon;
grant EXECUTE on function koki_private.transport_plus(command text, input jsonb) to authenticated;
revoke all on function koki_social_private.interact(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_social_private.interact(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer) to anon;
grant EXECUTE on function koki_social_private.interact(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer) to authenticated;
revoke all on function koki_social_private.moderate(p_comment uuid, p_hidden boolean, p_reason text, p_offset integer) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_social_private.moderate(p_comment uuid, p_hidden boolean, p_reason text, p_offset integer) to authenticated;
revoke all on function koki_social_private.summaries(p_ids uuid[]) from public, anon, authenticated, service_role;
grant EXECUTE on function koki_social_private.summaries(p_ids uuid[]) to anon;
grant EXECUTE on function koki_social_private.summaries(p_ids uuid[]) to authenticated;
revoke all on function public.koki_account_delete(p_etape text, p_confirmation text) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_account_delete(p_etape text, p_confirmation text) to authenticated;
revoke all on function public.koki_business(command text, input jsonb) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_business(command text, input jsonb) to anon;
grant EXECUTE on function public.koki_business(command text, input jsonb) to authenticated;
revoke all on function public.koki_comment_moderation(p_comment uuid, p_hidden boolean, p_reason text, p_offset integer) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_comment_moderation(p_comment uuid, p_hidden boolean, p_reason text, p_offset integer) to authenticated;
revoke all on function public.koki_content_social(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_content_social(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer) to anon;
grant EXECUTE on function public.koki_content_social(p_content uuid, p_action text, p_text text, p_comment uuid, p_liked boolean, p_offset integer) to authenticated;
revoke all on function public.koki_interests_sync(p_types jsonb, p_categories jsonb, p_actif boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_interests_sync(p_types jsonb, p_categories jsonb, p_actif boolean) to authenticated;
revoke all on function public.koki_notification_claim(p_push boolean, p_sms boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_notification_claim(p_push boolean, p_sms boolean) to service_role;
revoke all on function public.koki_notification_health() from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_notification_health() to authenticated;
revoke all on function public.koki_public_content(p_id uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_public_content(p_id uuid) to anon;
grant EXECUTE on function public.koki_public_content(p_id uuid) to authenticated;
revoke all on function public.koki_public_feed() from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_public_feed() to anon;
grant EXECUTE on function public.koki_public_feed() to authenticated;
revoke all on function public.koki_public_feed(p_offset integer) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_public_feed(p_offset integer) to anon;
grant EXECUTE on function public.koki_public_feed(p_offset integer) to authenticated;
revoke all on function public.koki_push_register(p_endpoint text, p_p256dh text, p_auth text) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_push_register(p_endpoint text, p_p256dh text, p_auth text) to authenticated;
revoke all on function public.koki_record_report(p_target uuid, p_motif text, p_details text) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_record_report(p_target uuid, p_motif text, p_details text) to authenticated;
revoke all on function public.koki_record_reports_admin(p_action text, p_id uuid, p_statut text, p_note text) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_record_reports_admin(p_action text, p_id uuid, p_statut text, p_note text) to authenticated;
revoke all on function public.koki_review_save(p_target uuid, p_rating integer, p_comment text) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_review_save(p_target uuid, p_rating integer, p_comment text) to authenticated;
revoke all on function public.koki_reviews_list(p_target uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_reviews_list(p_target uuid) to anon;
grant EXECUTE on function public.koki_reviews_list(p_target uuid) to authenticated;
revoke all on function public.koki_social_summaries(p_ids uuid[]) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_social_summaries(p_ids uuid[]) to anon;
grant EXECUTE on function public.koki_social_summaries(p_ids uuid[]) to authenticated;
revoke all on function public.koki_statistics() from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_statistics() to authenticated;
revoke all on function public.koki_stats_mine(p_days integer) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_stats_mine(p_days integer) to authenticated;
revoke all on function public.koki_track(p_target uuid, p_kind text) from public, anon, authenticated, service_role;
grant EXECUTE on function public.koki_track(p_target uuid, p_kind text) to anon;
grant EXECUTE on function public.koki_track(p_target uuid, p_kind text) to authenticated;
-- Droits par colonne relevés en production
grant update (read_at) on table public.koki_notifications to authenticated;
grant update (status) on table public.koki_reviews to authenticated;
commit;

