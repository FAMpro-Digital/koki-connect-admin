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
