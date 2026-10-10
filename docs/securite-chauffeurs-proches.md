# Recherche de chauffeurs proches — protection de la position (10 octobre 2026)

Problème : `nearby_drivers` répondait sans limite et comparait la distance à la position exacte du chauffeur. En déplaçant le point de départ et en observant l'apparition ou la disparition du chauffeur (frontière des 10 km), on pouvait retrouver sa position au mètre près.

Correction (`supabase/proposals/phase2-transactions.sql`, non appliquée sur Supabase) :
- table privée `koki_private.nearby_lookups` : 10 recherches par minute et 60 par heure par compte, nettoyage après 24 h ;
- distance calculée sur la position arrondie à 0,005° (environ 550 m) : la frontière ne révèle plus que la case de la grille ;
- un chauffeur ne se voit pas dans ses propres résultats.

Vérifications : scénario sur PostgreSQL 16 (schéma + 3 propositions) et test `tests/business-nearby-privacy.test.js` (PGlite, à lancer avec `npm test`). Les deux autres points de la revue (fiche suspendue, comptes supprimés) étaient déjà couverts par `owns_business` et les clés étrangères `on delete restrict`.
