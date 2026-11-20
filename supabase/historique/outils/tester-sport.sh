#!/usr/bin/env bash
# Vérifie le module Clubs & Académies (migrations EN ATTENTE 20261201*) sur une base LOCALE :
#  1. rejoue la référence de production (verifier.sh : 549 éléments, 0 écart) ;
#  2. applique les migrations du module, vérifie que chaque garde bloque une seconde application ;
#  3. exécute supabase/tests/sport-clubs.sql (rôles, isolation, accès directs, mineurs, stockage…) ;
#  4. exécute les retours arrière et vérifie que la structure redevient IDENTIQUE à la production ;
#  5. réapplique les migrations (cycle complet).
# Ne se connecte JAMAIS à Supabase : refuse tout hôte non local.
set -euo pipefail
cd "$(dirname "$0")/../../.."
: "${PGPORT:=5432}" "${PGUSER:=postgres}"
if [ -z "${PGHOST:-}" ]; then
  if [ -S /var/run/postgresql/.s.PGSQL.$PGPORT ]; then PGHOST=/var/run/postgresql; else PGHOST=/tmp; fi
fi
export PGHOST PGPORT PGUSER
case "$PGHOST" in
  /*|localhost|127.0.0.1|::1) ;;
  *) echo "REFUS : hôte « $PGHOST » non local." >&2; exit 2 ;;
esac
H=supabase/historique
M="$H/migrations/20261201000000_sport_schema.sql $H/migrations/20261201000100_sport_access_rpc.sql $H/migrations/20261201000200_sport_storage.sql"
R="$H/retour/20261201000200_sport_storage.sql $H/retour/20261201000100_sport_access_rpc.sql $H/retour/20261201000000_sport_schema.sql"
BASE_SPORT=koki_sport_test

echo "── 1. Référence de production"
bash $H/outils/verifier.sh | tail -1
psql -q -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists $BASE_SPORT" -c "create database $BASE_SPORT template koki_historique" >/dev/null

echo "── 2. Migrations et gardes"
for f in $M; do
  psql -q -d $BASE_SPORT -v ON_ERROR_STOP=1 -f "$f" >/dev/null && echo "ok      $f"
  if psql -q -d $BASE_SPORT -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1; then echo "ÉCHEC : la garde n'a pas bloqué une 2e application de $f"; exit 1; fi
  echo "garde   seconde application bloquée"
done

echo "── 3. Tests fonctionnels et de sécurité"
psql -d $BASE_SPORT -v ON_ERROR_STOP=1 -f supabase/tests/sport-clubs.sql 2>&1 | grep -E "Tests réussis|ÉCHEC|ERROR|ERREUR" || { echo "ÉCHEC des tests"; exit 1; }

echo "── 4. Retour arrière (avec données de test : export préalable simulé)"
for f in $R; do
  if [ "$f" = "$H/retour/20261201000200_sport_storage.sql" ]; then
    psql -q -d $BASE_SPORT -c "delete from storage.objects where bucket_id='koki-sport'" >/dev/null
  fi
  if [ "$f" = "$H/retour/20261201000000_sport_schema.sql" ]; then
    if psql -q -d $BASE_SPORT -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1; then echo "ÉCHEC : le retour n'a pas protégé les données"; exit 1; fi
    echo "garde   retour bloqué tant que des académies existent"
    PGOPTIONS="-c koki.retour_force=oui" psql -q -d $BASE_SPORT -v ON_ERROR_STOP=1 -f "$f" >/dev/null
  else
    psql -q -d $BASE_SPORT -v ON_ERROR_STOP=1 -f "$f" >/dev/null
  fi
  echo "ok      $f"
done
psql -Atq -d $BASE_SPORT -f $H/outils/empreinte.sql > "${TMPDIR:-/tmp}/empreinte-sport-retour.txt"
python3 $H/outils/comparer.py $H/reference/empreinte-production-2026-11-18.txt "${TMPDIR:-/tmp}/empreinte-sport-retour.txt"

echo "── 5. Réapplication après retour"
for f in $M; do psql -q -d $BASE_SPORT -v ON_ERROR_STOP=1 -f "$f" >/dev/null && echo "ok      $f"; done
psql -q -d postgres -c "drop database $BASE_SPORT" >/dev/null
echo "TERMINÉ : module Clubs & Académies vérifié en local."
