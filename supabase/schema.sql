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
