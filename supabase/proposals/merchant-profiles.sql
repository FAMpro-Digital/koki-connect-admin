-- PROPOSITION LOCALE UNIQUEMENT. Après phase2-transactions.sql ; aucune application distante automatique.
begin;
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
commit;
