# Commerces & Services — phase 1 (serveur et contrat)

Branche `dev/commerces-services`. Proposition SQL **locale uniquement** : `supabase/proposals/commerce-modernisation.sql`, à appliquer après `merchant-profiles.sql`. Elle est rejouée par le Supabase local (`supabase/migrations/20261011000450_commerce_modernisation.sql`, générée) et incluse au paquet d'installation TEST. Aucune migration distante n'a été exécutée.

## Règles

- **Validation** : les professionnels (deux parcours conservés : `register_professional` → « À valider », `submit_merchant` → « En attente ») et leurs **boutiques** (« À valider » à la création) sont approuvés par l'administration. Produits et services sont publiés directement, seulement si toute la chaîne parente est approuvée et active.
- **Aucun identifiant à saisir** : la boutique et le service sont rattachés automatiquement à la fiche du compte ; le produit à l'unique boutique du compte (sinon, choix dans la liste).
- **Décisions de l'administration** (`moderate`, droit Commerce + double authentification, révision exacte) : approuver, refuser, suspendre, archiver, avec motif facultatif. Table des transitions identique dans `src/commerce-contract.js` (vérifiée par test).
- **Professionnel** : `save_profile_details` (WhatsApp, village, zone, horaires, GPS facultatif), `set_availability`, `archive`. Changer le WhatsApp d'une fiche approuvée la renvoie en validation ; une offre suspendue par l'administration ne peut pas être remise en ligne par son propriétaire.
- **Nouveaux champs** : ancien prix (> prix), jusqu'à 5 photos par élément, tarif fixe ou sur devis, zone d'intervention, village choisi dans `koki_localites` (10 villages OpenStreetMap, type « À préciser », liste modifiable par l'administration, jamais supprimée).
- **Doublons** : un même nom (sans tenir compte des majuscules et des espaces) est refusé sous un même parent, hors éléments archivés.
- **Catalogue public** (`catalog`) : mêmes clés qu'avant + nouveaux champs ; produits épuisés visibles ; aucun identifiant de propriétaire ni donnée d'administration.

## Ajouts de la phase 2 (espace professionnel public)

- `save_profile` : fiche unifiée (commerçant, prestataire ou les deux) créée « En attente », **GPS facultatif**, village obligatoire choisi dans la liste, téléphone et WhatsApp au format international. Sur une fiche approuvée, changer le nom, l'activité, un numéro ou les photos la renvoie en validation ; horaires, village, adresse, description et GPS restent modifiables sans interruption. Une fiche refusée corrigée repart en validation. Retirer une activité qui a encore des boutiques ou des services est refusé. `register_professional` et `submit_merchant` restent disponibles.
- `media_folder` : chaque compte reçoit un **dossier photo anonyme** (table privée `koki_private.media_folders`). Les nouvelles photos y sont déposées ; leurs chemins publiés ne contiennent plus l'identifiant du compte. Politiques Storage ajoutées (dépôt, lecture, suppression dans son seul dossier) ; les anciens chemins restent valides.

## Ajouts de la phase 3 (revalidation sans interruption)

- Sur une fiche **en ligne**, un changement de nom, d'activité, de numéro ou de photos n'est plus appliqué tout de suite : il est rangé dans `payload.modification` et la fiche reste « Actif » avec la **dernière version approuvée**. Le catalogue public ne lit jamais `modification` ; les photos en attente ne sont lisibles que par le propriétaire et l'administration, et protégées contre la suppression.
- `review_changes` (droit Commerce + double authentification, révision exacte) : `approve` publie les nouvelles valeurs, `reject` les écarte avec un motif ; le statut ne change pas. Revenir soi-même aux valeurs approuvées annule la demande.
- Les autres champs (horaires, village, adresse, description, catégorie, GPS) restent appliqués immédiatement.

## Ajouts de la phase 4 (administration)

Routeur `koki_private.commerce_admin` placé devant les précédents (`public.koki_business`) :

- **Garde-fous** : aucun administrateur ne peut valider ni corriger ses propres fiches (toutes commandes de décision, anciennes comprises) ; une boutique, un produit ou un service ne peut être approuvé que si sa fiche parente (et sa boutique) est approuvée.
- **Historique** : chaque décision (`moderate`, `review_changes`, `admin_review`, `review_merchant`) et chaque correction est inscrite dans le journal existant `koki_audit` (décision, motif, statut avant et après, administrateur).
- `admin_stats` (lecture + double authentification) : comptages réels — professionnels inscrits, inscriptions, boutiques et modifications en attente, boutiques actives, produits publiés, services disponibles, fiches suspendues et archivées.
- `admin_queue` (droit Commerce) : file de validation, la plus ancienne demande d'abord, sans identifiant de compte.
- `admin_records` (droit Commerce) : rubrique, recherche, filtres statut, village, fiche parente choisie dans une liste, 50 par page, historique des décisions.
- `admin_update` (droit Commerce) : correction des champs (nom, catégorie, village, adresse, horaires, zone, téléphone, WhatsApp, prix, ancien prix, stock, tarif, description, retrait ou ordre des photos existantes). Le rattachement à la boutique ou à la fiche reste immuable (règle existante).
- **Ancien formulaire commerçant** (`submit_merchant`) : sur une fiche en ligne, même revalidation sans retrait du catalogue.

Écrans : `src/commerce-admin.js` (tableau de bord commercial, « Validations commerciales » avec comparaison publiée / proposée, gestion des quatre rubriques). Photos historiques : voir `docs/migration-photos-historiques.md` (stratégie seulement, rien n'est migré).

## Compatibilité avec les données existantes

Préflight : la migration s'arrête **sans rien modifier** si des boutiques, produits ou services n'ont pas de parent, ou si des doublons de nom existent. Les statuts sont un sur-ensemble des statuts actuels : aucune ligne existante n'est réécrite (vérifié par test, instantané avant/après identique). Les anciennes commandes (`admin_review`, `review_merchant`, `save_*` avec `parent_id`, commandes et transport) restent disponibles.

Changement de comportement assumé : une nouvelle boutique est créée « À valider » (auparavant « Actif »).

## Tests

`tests/commerce-modernisation.test.js` (compatibilité, préflight doublons, parcours complet, permissions, cohérence contrat/serveur), `tests/commerce-contract.test.js` (numéros sénégalais, liens WhatsApp, message de commande, prix, statuts ; empreinte identique au dépôt public).
