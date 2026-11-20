# Nouvelles migrations

Une migration = `AAAAMMJJHHMMSS_nom.sql` ici + son retour arrière du même nom dans `../retour/`.
Voir `../README.md`, section 3.

## Appliquées en production

- 20/11/2026 — Espace Clubs & Académies : `20261201000000_sport_schema.sql`, `20261201000100_sport_access_rpc.sql`,
  `20261201000200_sport_storage.sql`, `20261201000300_sport_notifications.sql` (+ `reference/sources/rattrapage_100_droits_sport.sql`).
  Référence : `reference/empreinte-production-2026-11-20.txt`. Tests du module : `bash supabase/historique/outils/tester-sport.sh`.
