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
