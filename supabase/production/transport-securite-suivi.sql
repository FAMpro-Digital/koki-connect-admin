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
