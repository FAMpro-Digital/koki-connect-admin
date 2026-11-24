# Nouvelles migrations

Une migration = `AAAAMMJJHHMMSS_nom.sql` ici + son retour arrière du même nom dans `../retour/`.
Voir `../README.md`, section 3.

## Appliquées en production

- 20/11/2026 — Espace Clubs & Académies : `20261201000000_sport_schema.sql`, `20261201000100_sport_access_rpc.sql`,
  `20261201000200_sport_storage.sql`, `20261201000300_sport_notifications.sql` (+ `reference/sources/rattrapage_100_droits_sport.sql`).
  Référence : `reference/empreinte-production-2026-11-20.txt`. Tests du module : `bash supabase/historique/outils/tester-sport.sh`.
- 20/11/2026 (soir) — `20261201000400_sport_affichage_responsable.sql` : l'affichage public d'un joueur est décidé par le
  responsable de l'académie (mode « responsable », date fixée par le serveur, sans représentant légal obligatoire).

## Préparées, NON appliquées en production

- Module Football (scores en direct, calendriers, compétitions, équipes, classements) :
  `20261201000500_foot_schema.sql`, `20261201000600_foot_acces.sql` (+ retours dans `../retour/`).
  À ajouter à `reference/ordre.txt` seulement APRÈS application en production (accord écrit requis).
  Tests : `bash supabase/historique/outils/tester-foot.sh` (référence de production, gardes, tests, retour arrière, réapplication).
