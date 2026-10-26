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
