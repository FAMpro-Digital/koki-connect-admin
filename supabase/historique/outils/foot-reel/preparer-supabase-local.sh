#!/usr/bin/env bash
# Environnement d'essai INDÉPENDANT et ÉPHÉMÈRE pour les essais réels du module Football :
# Supabase local (Docker, PostgreSQL 17, Auth avec MFA TOTP, Realtime, PostgREST), sans aucun projet distant.
#  1. démarre Supabase local avec la configuration ./supabase/config.toml ;
#  2. rejoue la structure de production (supabase/historique/reference/ordre.txt) et la compare à
#     l'empreinte de production du 20/11/2026 ;
#  3. applique les migrations Football 0500 puis 0600 et vérifie que les objets existants sont inchangés ;
#  4. crée les comptes d'essai (mots de passe et secrets TOTP aléatoires, jamais écrits dans Git)
#     et un match d'essai, puis écrit les variables dans le fichier indiqué par $KOKI_ESSAI_ENV.
# Garde-fou : uniquement 127.0.0.1 ; refuse toute exécution si un lien vers un projet distant existe.
set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"; RACINE="$(cd "$ICI/../../../.." && pwd)"; H="$RACINE/supabase/historique"
SORTIE="${KOKI_ESSAI_ENV:?Indiquer KOKI_ESSAI_ENV (fichier des variables d'essai, hors du dépôt)}"
case "$SORTIE" in "$RACINE"/*) echo "REFUS : le fichier des variables doit être hors du dépôt." >&2; exit 2;; esac
[ -e "$ICI/supabase/.temp/project-ref" ] && { echo "REFUS : ce dossier est lié à un projet distant." >&2; exit 2; }
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
ADMIN_DB="postgresql://supabase_admin:postgres@127.0.0.1:54322/postgres"
q(){ psql "$DB" -v ON_ERROR_STOP=1 -X -q "$@"; }

echo "── 1. Démarrage de Supabase local (éphémère)"
supabase start --workdir "$ICI" >/dev/null
supabase status --workdir "$ICI" -o env > "$SORTIE.supabase"
chmod 600 "$SORTIE.supabase"
# shellcheck disable=SC1090
set -a; . "$SORTIE.supabase"; set +a
[ "${API_URL:-}" = "http://127.0.0.1:54321" ] || { echo "REFUS : adresse inattendue ${API_URL:-?}" >&2; exit 2; }
q -Atc "select 'PostgreSQL '||current_setting('server_version')"

echo "── 2. Structure de production rejouée"
psql "$ADMIN_DB" -v ON_ERROR_STOP=1 -X -q -c "create extension if not exists pg_cron; create extension if not exists pg_net with schema extensions; grant usage on schema cron to postgres; grant all on all tables in schema cron to postgres" >/dev/null
while read -r f; do [ -z "$f" ] && continue
  if ! sortie=$(psql "$ADMIN_DB" -v ON_ERROR_STOP=1 -X -q -f "$RACINE/$f" 2>&1 >/dev/null); then echo "ÉCHEC $f"; echo "$sortie" | grep -E "ERROR|ERREUR" | head -3; exit 1; fi
done < "$H/reference/ordre.txt"
psql "$ADMIN_DB" -Atq -X -f "$H/outils/empreinte.sql" > "$SORTIE.avant"
python3 "$H/outils/comparer.py" "$H/reference/empreinte-production-2026-11-20.txt" "$SORTIE.avant" | tail -15 || echo "(écarts listés ci-dessus : plateforme Supabase locale contre production)"

echo "── 3. Migrations Football"
for f in 20261201000500_foot_schema 20261201000600_foot_acces; do psql "$ADMIN_DB" -v ON_ERROR_STOP=1 -X -q -f "$H/migrations/$f.sql" >/dev/null && echo "ok      $f"; done
psql "$ADMIN_DB" -Atq -X -f "$H/outils/empreinte.sql" > "$SORTIE.apres"
python3 "$H/outils/comparer-ajouts.py" "$SORTIE.avant" "$SORTIE.apres"
psql "$ADMIN_DB" -X -q -c "notify pgrst, 'reload schema'" >/dev/null

echo "── 4. Comptes et match d'essai"
KOKI_ESSAI_URL="$API_URL" node "$ICI/preparer-comptes.mjs" > "$SORTIE"
chmod 600 "$SORTIE"
echo "variables d'essai écrites (fichier hors dépôt, droits 600)"
