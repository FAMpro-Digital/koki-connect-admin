-- APPLIQUÉ en production le 2026-10-27 (migration commerce_catalogue_sans_coordonnees_professionnelles), après accord de la direction.
-- Catalogue public (visiteurs et autres professionnels) : les produits publiés restent visibles ; la boutique ne montre que
-- nom, description, catégorie, village, photos et WhatsApp (pour commander) ; la fiche du professionnel ne montre plus
-- téléphone, WhatsApp, adresse, position GPS, zone ni horaires lorsqu'il a une boutique active. Un professionnel sans
-- boutique (ex. prestataire) garde son contact visible pour recevoir des demandes de devis.
-- Retour arrière : recréer koki_private.commerce_catalog() avec l'ancienne définition (adresse/localisation/horaires/zone
-- exposés pour 'professionnels' et 'boutiques').
create or replace function koki_private.commerce_catalog() returns jsonb language sql stable security definer set search_path to '' as $b$
 select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
  'id',x.id,'kind',x.kind,'parent_id',x.parent_id,'provider_id',x.provider_id,'statut',x.statut,
  'nom',x.payload->>'nom','description',x.payload->>'description','categorie',x.payload->>'categorie',
  'prix',x.payload->'prix','ancien_prix',x.payload->'ancien_prix','stock',x.payload->'stock','tarif',x.payload->>'tarif',
  'telephone',case when x.kind='professionnels' and not x.avec_boutique then x.payload->>'telephone' end,
  'whatsapp',case when x.kind='boutiques' or (x.kind='professionnels' and not x.avec_boutique) then x.payload->>'whatsapp' end,
  'type',case when x.kind='professionnels' then x.payload->>'type' end,
  'adresse',case when x.kind='professionnels' and not x.avec_boutique then x.payload->>'adresse' end,
  'village',x.payload->>'village',
  'zone',case when x.kind='services' or (x.kind='professionnels' and not x.avec_boutique) then x.payload->>'zone' end,
  'horaires',case when x.kind='professionnels' and not x.avec_boutique then x.payload->>'horaires' end,
  'localisation',case when x.kind='professionnels' and not x.avec_boutique then x.payload->'localisation' end,
  'photos',coalesce(x.payload->'photos',case when x.payload->>'image_path' is not null then jsonb_build_array(x.payload->>'image_path') end),
  'image_path',x.payload->>'image_path')) order by x.updated_at desc),'[]'::jsonb)
 from (select listing.*, exists(select 1 from public.koki_records s where s.parent_id=listing.id and s.kind='boutiques' and s.statut='Actif') as avec_boutique from public.koki_records listing where (listing.kind='professionnels' and listing.statut='Actif')
  or (listing.kind='boutiques' and listing.statut='Actif' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.kind='professionnels' and prof.statut='Actif'))
  or (listing.kind='services' and listing.statut='Disponible' and exists(select 1 from public.koki_records prof where prof.id=listing.parent_id and prof.statut='Actif'))
  or (listing.kind='produits' and listing.statut in ('Disponible','Épuisé') and exists(select 1 from public.koki_records b join public.koki_records prof on prof.id=b.parent_id where b.id=listing.parent_id and b.statut='Actif' and prof.statut='Actif'))
  order by listing.updated_at desc limit 500) x
$b$;
