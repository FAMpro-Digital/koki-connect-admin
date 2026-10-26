-- PROPOSITION — Commerces & Services : le commerçant peut DÉSARCHIVER ses boutiques, produits et services.
-- NON APPLIQUÉE : à n'installer qu'après accord explicite.
--
-- Aujourd'hui seul l'administration peut rétablir un élément archivé (décision « Approuver »). La commande 'unarchive' est ajoutée
-- à koki_private.commerce_business (même chaîne que 'archive' : koki_business > commerce_admin > commerce_business).
-- Règles :
--  * propriétaire uniquement, révision à jour, l'élément doit être « Archivé » ;
--  * un élément archivé par l'administration (moderation.decision = 'archive') ne peut pas être rétabli par son propriétaire ;
--  * la boutique ou la fiche parente ne doit pas être archivée, suspendue ou refusée ;
--  * retour de l'élément : boutique → « À valider » (nouvelle validation) ; produit / service → « Masqué » avec son verrou de
--    validation inchangé (le commerçant le rend disponible ensuite, sauf s'il attend la validation de l'administration) ;
--  * deux éléments actifs ne peuvent pas porter le même nom : message « renommez-le avant de le rétablir ».
-- Méthode : le texte exact de la fonction en production est relu puis modifié en trois endroits (une occurrence exigée chacun).
-- Essai à blanc (transaction annulée) réalisé le 2026-10-26 sur Koki : 7 cas validés, aucune trace laissée.
begin;

do $$
declare
 src text; t text;
 a1 text:='''set_availability'',''archive'',''moderate'') then';
 b1 text:='''set_availability'',''archive'',''unarchive'',''moderate'') then';
 a2 text:='  when ''archive'' then array[''request_id'',''id'',''revision'']';
 b2 text:=E'  when ''archive'' then array[''request_id'',''id'',''revision'']\n  when ''unarchive'' then array[''request_id'',''id'',''revision'']';
 a3 text:=E'\n elsif command=''review_changes'' then';
 b3 text:=E'\n elsif command=''unarchive'' then
  perform pg_advisory_xact_lock(hashtextextended(''trade-owner:''||actor::text,0));
  select * into r from public.koki_records where id=(input->>''id'')::uuid for update;
  if r.id is null or r.owner_id is distinct from actor or r.kind not in (''boutiques'',''produits'',''services'') then raise exception ''Élément inaccessible'' using errcode=''42501'';end if;
  if (input->>''revision'')::integer is distinct from r.revision then raise exception ''Révision périmée : actualisez'';end if;
  if r.statut<>''Archivé'' then raise exception ''Cet élément n’est pas archivé'';end if;
  if r.payload->''moderation''->>''decision''=''archive'' then raise exception ''Archivé par l’administration : contactez-la pour le rétablir'' using errcode=''42501'';end if;
  if r.parent_id is not null then
   select * into p from public.koki_records where id=r.parent_id for update;
   if p.id is null or p.statut in (''Archivé'',''Suspendu'',''Refusé'') then raise exception ''Désarchivez d’abord la boutique ou la fiche parente'';end if;
  end if;
  begin
   update public.koki_records set statut=case r.kind when ''boutiques'' then ''À valider'' else ''Masqué'' end where id=r.id returning * into r;
  exception when unique_violation then raise exception ''Un élément actif porte déjà ce nom : renommez-le avant de le rétablir'';end;'||E'\n elsif command=''review_changes'' then';
begin
 select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='koki_private' and p.proname='commerce_business' and pg_get_function_identity_arguments(p.oid)='command text, input jsonb';
 if src is null then raise exception 'Préflight : koki_private.commerce_business introuvable';end if;
 if position('''unarchive''' in src)>0 then raise exception 'Préflight : commande unarchive déjà installée — rien n''est changé';end if;
 foreach t in array array[a1,a2,a3] loop
  if position(t in src)=0 then raise exception 'Préflight : texte attendu absent (%) — rien n''est changé',left(t,40);end if;
  if position(t in substr(src,position(t in src)+length(t)))>0 then raise exception 'Préflight : texte présent plusieurs fois (%) — rien n''est changé',left(t,40);end if;
 end loop;
 execute replace(replace(replace(src,a1,b1),a2,b2),a3,b3);
end $$;

commit;

-- RETOUR ARRIÈRE : réexécuter la fonction d'origine (copie enregistrée avant installation) ou inverser les trois remplacements.
-- Les éléments déjà désarchivés restent valides : aucun statut nouveau n'est introduit.
