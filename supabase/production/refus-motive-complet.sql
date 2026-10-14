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
-- 2. koki_private.merchant_business (copie exacte de la version de production, md5 525819041eed1710d0dbc44e62721c4d, avec 3 ajouts) :
--    - ancienne décision review_merchant : clé « note » acceptée, motif obligatoire pour « reject », décision enregistrée
--      dans payload.moderation (le professionnel voit le motif, comme avec « moderate ») ;
--    - nouvelle décision admin_review « reject » pour une inscription chauffeur « À valider » : motif obligatoire,
--      droit Transport + double authentification, statut « Suspendu » (aucune modification de la contrainte de statuts),
--      motif enregistré dans payload.moderation ; l'administration peut toujours la valider ensuite (« approve »).
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
   -- Refus motivé d'une inscription chauffeur (motif obligatoire, visible par le chauffeur).
   if r.kind='chauffeurs' and input->>'decision'='reject' then command:='reject_driver';end if;
 end if;
 if command not in ('submit_merchant','review_merchant','reject_driver') then return koki_private.business(command,input);end if;
 if actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501';end if;
 if command='review_merchant' and not koki_private.allowed('commerce') then raise exception 'Administration Commerce et MFA requises' using errcode='42501';end if;
 if command='reject_driver' and not koki_private.allowed('transport') then raise exception 'Administration Transport et MFA requises' using errcode='42501';end if;
 perform koki_private.business_keys_allowed(input,case when command='submit_merchant' then array['request_id','id','revision','name','profile','category','phone','address','location','hours','description','photos'] when command='reject_driver' then array['request_id','id','decision','note'] else array['request_id','id','revision','decision','note'] end);
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
   select * into r from public.koki_records where id=(input->>'id')::uuid for update;
   if r.kind is distinct from 'chauffeurs' then raise exception 'Fiche chauffeur requise';end if;
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
