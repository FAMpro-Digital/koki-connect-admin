-- KOKI CONNECT — RETOUR ARRIÈRE DE LA POURSUITE PHASE 6, PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay
-- GÉNÉRÉ par scripts/prepare-test-continuation.mjs — NE PAS MODIFIER À LA MAIN. Jamais sur qsbmzzbiztfqysstepxm ni paegdthtusbwxuarhacb.
-- Ramène la base à l'état vérifié le 11/10/2026 (schema.sql + fondation) : même empreinte (supabase/preproduction/empreinte.sql).
-- Aucune donnée n'est supprimée : le script REFUSE de s'exécuter si une table ajoutée contient des données créées après l'installation,
-- ou si une fiche existante n'est plus compatible avec les règles d'origine. Comptes, contenus, tarifs, journal et photos sont conservés.
-- Une seule transaction : en cas d'erreur, rien n'est modifié.
begin;
do $$ declare n bigint; begin
 if to_regclass('koki_private.test_environment') is null then raise exception 'GARDE : base non marquée « KOKI TEST » (production ou poursuite non appliquée) : retour arrière refusé';end if;
 if not exists(select 1 from koki_private.test_environment where label='KOKI TEST') then raise exception 'GARDE : base non marquée « KOKI TEST » (production ou poursuite non appliquée) : retour arrière refusé';end if;
 if to_regprocedure('public.koki_business(text,jsonb)') is null then raise exception 'GARDE : routeur métier absent, état inattendu';end if;
 select count(*) into n from koki_private.business_keys;if n>0 then raise exception 'GARDE : % clé(s) d''opération créées après installation : exporter et décider avant retour arrière',n;end if;
 select count(*) into n from koki_private.ride_quotes;if n>0 then raise exception 'GARDE : % devis de course créés après installation',n;end if;
 select count(*) into n from koki_private.nearby_lookups;if n>0 then raise exception 'GARDE : % recherche(s) de proximité enregistrées après installation',n;end if;
 select count(*) into n from koki_private.media_folders;if n>0 then raise exception 'GARDE : % dossier(s) photo anonymes attribués après installation',n;end if;
 if (select count(*) from public.koki_localites)<>10
  or exists(select 1 from public.koki_localites l where not l.actif or l.type<>'À préciser'
   or not exists(select 1 from (values ('Bellel Ouolof',1,'OpenStreetMap'),('Coki',2,'OpenStreetMap'),('Kanène Khar',3,'OpenStreetMap'),('Keur Ngoura',4,'OpenStreetMap'),('Loumène',5,'OpenStreetMap'),('Ndare Wakhy',6,'OpenStreetMap'),('Ndiobene Belal',7,'OpenStreetMap'),('Ouarak',8,'OpenStreetMap'),('Pallene',9,'OpenStreetMap'),('Thiourour',10,'OpenStreetMap')) v(nom,ordre,source) where v.nom=l.nom and v.ordre=l.ordre and v.source=l.source))
  then raise exception 'GARDE : la liste des villages a été modifiée après installation';end if;
 if exists(select 1 from public.koki_records where not (

(kind='professionnels' and statut in ('À valider','Actif','Suspendu')) or
(kind='boutiques' and statut in ('À valider','Actif','Fermé')) or
(kind='produits' and statut in ('Disponible','Épuisé','Masqué')) or
(kind='services' and statut in ('Disponible','Indisponible','Masqué')) or
(kind='chauffeurs' and statut in ('À valider','Disponible','Indisponible','Suspendu')) or
(kind='vehicules' and statut in ('Actif','Indisponible')) or
(kind='commandes' and statut in ('Commande reçue','Confirmée','Préparation','En livraison','Livrée','Annulée')) or
(kind='demandes_services' and statut in ('Demande envoyée','Acceptée','Prestataire en route','Service en cours','Terminé','Annulée')) or
(kind='courses' and statut in ('En attente','Acceptée','Chauffeur en route','Course en cours','Terminée','Annulée'))
 )) then raise exception 'GARDE : des fiches utilisent des statuts introduits par la poursuite : retour arrière refusé sans perte';end if;
end $$;
-- 1. Politiques ajoutées (Storage et tables)
drop policy business_media_alias_delete on storage.objects;
drop policy business_media_alias_insert on storage.objects;
drop policy business_media_alias_read on storage.objects;
drop policy business_media_insert on storage.objects;
drop policy business_media_owner_delete on storage.objects;
drop policy business_media_owner_read on storage.objects;
drop policy business_media_participant_read on storage.objects;
drop policy business_media_public_read on storage.objects;
drop policy editorial_admin_media_read on storage.objects;
drop policy media_reference_guard on storage.objects;
drop policy localites_admin_insert on public.koki_localites;
drop policy localites_admin_update on public.koki_localites;
drop policy localites_public_read on public.koki_localites;
drop policy records_admin_business_read on public.koki_records;
drop policy users_self_read on public.koki_users;
-- 2. Déclencheurs, contraintes et index ajoutés
drop trigger business_relations on public.koki_records;
drop trigger business_item_relation on public.koki_order_items;
alter table public.koki_records drop constraint koki_business_owner, drop constraint business_required_links, drop constraint business_source_reserved;
drop index public.koki_commerce_unique_name, public.koki_client_one_active_ride, public.koki_driver_one_active_ride, public.koki_driver_account, public.koki_professional_account;
-- 3. Fonctions ajoutées (routeur public en premier)
drop function public.koki_business(text,jsonb);
drop function koki_private.commerce_admin(text,jsonb);
drop function koki_private.commerce_admin_view(public.koki_records);
drop function koki_private.commerce_publie(public.koki_records);
drop function koki_private.commerce_parent_actif(public.koki_records);
drop function koki_private.commerce_business(text,jsonb);
drop function koki_private.commerce_sensibles(jsonb);
drop function koki_private.my_media_folder();
drop function koki_private.commerce_catalog();
drop function koki_private.commerce_int(jsonb,text,bigint,text);
drop function koki_private.commerce_village(jsonb);
drop function koki_private.commerce_phone(jsonb,text);
drop function koki_private.commerce_photos(jsonb);
drop function koki_private.merchant_business(text,jsonb);
drop function koki_private.business_image_unreferenced(text);
drop function koki_private.business_participant_image(text);
drop function koki_private.business_public_image(text);
drop function koki_private.business(text,jsonb);
drop function koki_private.business_owned_image(text);
drop function koki_private.business_can_read(public.koki_records);
drop function koki_private.business_distance(jsonb,jsonb);
drop function koki_private.business_point(jsonb);
drop function koki_private.business_text(jsonb,text,integer,integer);
drop function koki_private.business_keys_allowed(jsonb,text[]);
drop function koki_private.business_item_relation();
drop function koki_private.business_relations();
-- 4. Tables ajoutées (vérifiées vides ou identiques à l'installation ci-dessus)
drop table koki_private.business_keys;
drop table koki_private.ride_quotes;
drop table koki_private.nearby_lookups;
drop table koki_private.media_folders;
drop table koki_private.test_environment;
drop table public.koki_localites;
-- 5. Définitions d'origine (extraites de supabase/schema.sql)
alter table public.koki_records drop constraint koki_record_status;
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
create policy records_read on public.koki_records for select to authenticated using((select koki_private.allowed('read')));
create policy koki_media_read on storage.objects for select to authenticated using(bucket_id='koki-media' and koki_private.allowed('read'));
create or replace function public.koki_statistics() returns jsonb language plpgsql security invoker set search_path='' as $$ begin
if not koki_private.allowed('read') then raise exception 'Administration et MFA requises' using errcode='42501';end if;
return jsonb_build_object('Utilisateurs inscrits',(select count(*) from public.koki_users),'Utilisateurs actifs',null,'Actualités publiées',(select count(*) from public.koki_contents where type='Actualités' and statut='publié' and publication<=now()),'Annonces publiées',(select count(*) from public.koki_contents where type='Annonces' and statut='publié' and publication<=now()),'Publicités actives',(select count(*) from public.koki_contents where type='Publicités' and statut='publié' and actif and publication<=now() and (fin is null or fin>now())),'Commerces et prestataires',(select count(*) from public.koki_records where kind='professionnels'),'Chauffeurs',(select count(*) from public.koki_records where kind='chauffeurs'),'Courses',(select count(*) from public.koki_records where kind='courses'),'Commandes',(select count(*) from public.koki_records where kind='commandes'),'Demandes de services',(select count(*) from public.koki_records where kind='demandes_services'),'Revenus FCFA',null,'Impressions publicitaires',null,'Clics publicitaires',null,'mesure_le',now());end $$;
-- 6. Droits d'origine, y compris le droit par défaut Supabase constaté sur TEST avant poursuite
grant insert,update,delete on public.koki_records to authenticated;
grant insert,update,delete on public.koki_transport_rates to authenticated;
revoke usage on schema koki_private from anon;
grant execute on function public.koki_statistics() to anon;
notify pgrst, 'reload schema';
commit;
