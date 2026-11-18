#!/usr/bin/env bash
# Rejoue l'historique de référence dans une base PostgreSQL LOCALE et compare
# sa structure à l'empreinte relevée en production (lecture seule).
#
# Ne se connecte JAMAIS à Supabase : refuse tout hôte qui n'est pas local.
#
# Variables : PGHOST (défaut /tmp ou /var/run/postgresql), PGPORT (5432),
#             PGUSER (postgres), BASE (koki_historique).
set -euo pipefail
cd "$(dirname "$0")/../../.."

: "${PGPORT:=5432}" "${PGUSER:=postgres}" "${BASE:=koki_historique}"
if [ -z "${PGHOST:-}" ]; then
  if [ -S /var/run/postgresql/.s.PGSQL.$PGPORT ]; then PGHOST=/var/run/postgresql; else PGHOST=/tmp; fi
fi
export PGHOST PGPORT PGUSER

case "$PGHOST" in
  /*|localhost|127.0.0.1|::1) ;;
  *) echo "REFUS : hôte « $PGHOST » non local. Cet outil ne s'utilise que sur une base locale." >&2; exit 2 ;;
esac

H=supabase/historique
psql -q -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists $BASE" -c "create database $BASE" >/dev/null
psql -q -d "$BASE" -v ON_ERROR_STOP=1 -f $H/outils/simulation-supabase.sql >/dev/null

version=$(psql -Atq -d "$BASE" -c "show server_version_num")
echait=0
while read -r f; do
  [ -z "$f" ] && continue
  fichier="$f"
  # Le paquet des phases 2 à 6 exige PostgreSQL 17 (version de Supabase) ;
  # en local sous PostgreSQL 16, seule cette garde est assouplie, dans une copie.
  if [ "$version" -lt 170000 ] && grep -q "<170000 then raise exception 'GARDE : PostgreSQL 17 requis'" "$f"; then
    fichier=$(mktemp); sed "s/<170000 then raise exception 'GARDE : PostgreSQL 17 requis'/<160000 then raise exception 'GARDE : PostgreSQL 17 requis'/" "$f" > "$fichier"
  fi
  if ! sortie=$(psql -q -d "$BASE" -v ON_ERROR_STOP=1 -f "$fichier" 2>&1 >/dev/null); then
    echo "ÉCHEC $f"; echo "$sortie" | grep -E "ERROR|ERREUR" | head -3; echait=1
  else
    echo "ok    $f"
  fi
done < $H/reference/ordre.txt
[ "$echait" = 0 ] || exit 1

psql -Atq -d "$BASE" -f $H/outils/empreinte.sql > "${TMPDIR:-/tmp}/empreinte-locale.txt"
python3 $H/outils/comparer.py $H/reference/empreinte-production-2026-11-18.txt "${TMPDIR:-/tmp}/empreinte-locale.txt"
