# Nouvelles migrations

Une migration = `AAAAMMJJHHMMSS_nom.sql` ici + son retour arrière du même nom dans `../retour/`.
Voir `../README.md`, section 3.

## En attente (non appliquées, hors `reference/ordre.txt`)

- `20261201000000_sport_schema.sql`, `20261201000100_sport_access_rpc.sql`, `20261201000200_sport_storage.sql` —
  Espace Clubs & Académies. Vérification locale : `bash supabase/historique/outils/tester-sport.sh`.
  Voir `docs/clubs-academies.md`.
