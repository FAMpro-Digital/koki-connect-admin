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
