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
