#!/usr/bin/env bash
# Échec partiel d'une migration Football (base LOCALE uniquement) : une instruction cassée est injectée à
# plusieurs endroits d'une COPIE de chaque migration ; on vérifie que rien n'est appliqué (transaction unique
# begin … commit) : la structure reste IDENTIQUE à l'état de départ, puis la migration intacte s'applique.
set -euo pipefail
cd "$(dirname "$0")/../../.."
: "${PGPORT:=5432}" "${PGUSER:=postgres}"
if [ -z "${PGHOST:-}" ]; then if [ -S /var/run/postgresql/.s.PGSQL.$PGPORT ]; then PGHOST=/var/run/postgresql; else PGHOST=/tmp; fi; fi
export PGHOST PGPORT PGUSER
case "$PGHOST" in /*|localhost|127.0.0.1|::1) ;; *) echo "REFUS : hôte « $PGHOST » non local." >&2; exit 2 ;; esac
H=supabase/historique;B=koki_foot_echec;T="${TMPDIR:-/tmp}/koki-foot-echec";mkdir -p "$T"
empreinte(){ psql -Atq -d $B -f $H/outils/empreinte.sql > "$1"; }
psql -q -d postgres -c "drop database if exists $B" -c "create database $B template koki_historique" >/dev/null
total=0
for mig in 20261201000500_foot_schema 20261201000600_foot_acces; do
  src=$H/migrations/$mig.sql
  empreinte "$T/avant-$mig.txt"
  n=$(wc -l < "$src")
  # Points d'injection : après le begin, vers 1/4, 1/2 et 3/4, juste avant le commit (fin d'instruction hors corps $$ … $$).
  debut=$(grep -n '^begin;' "$src" | head -1 | cut -d: -f1); fin=$(grep -n '^commit;' "$src" | tail -1 | cut -d: -f1)
  points="$debut"
  for k in 1 2 3; do cible=$(( n*k/4 )); l=$(awk -v c=$cible '{n=gsub(/\$\$/,"&"); dedans=(dedans+n)%2} NR>=c && !dedans && /;[[:space:]]*$/ && !/^[[:space:]]*--/ {print NR; exit}' "$src"); points="$points $l"; done
  points="$(echo $points $((fin-1)) | tr " " "\n" | sort -nu | tr "\n" " ")"
  for p in $points; do
    awk -v p=$p '{print} NR==p {print "select koki_injection_volontaire_d_echec();"}' "$src" > "$T/casse.sql"
    if psql -q -d $B -v ON_ERROR_STOP=1 -f "$T/casse.sql" >/dev/null 2>"$T/err.txt"; then echo "ÉCHEC : la copie cassée ($mig, ligne $p) s'est appliquée"; exit 1; fi
    grep -q 'koki_injection_volontaire_d_echec' "$T/err.txt" || { echo "ÉCHEC : erreur inattendue ($mig, ligne $p) :"; head -3 "$T/err.txt"; exit 1; }
    empreinte "$T/apres.txt"
    if ! diff -q "$T/avant-$mig.txt" "$T/apres.txt" >/dev/null; then echo "ÉCHEC : application partielle ($mig, ligne $p)"; diff "$T/avant-$mig.txt" "$T/apres.txt" | head; exit 1; fi
    psql -Atq -d $B -c "select count(*) from pg_namespace where nspname='koki_foot'" | grep -qx "$([ $mig = 20261201000500_foot_schema ] && echo 0 || echo 1)" || { echo "ÉCHEC : schéma koki_foot dans un état inattendu"; exit 1; }
    echo "ok      $mig : échec injecté ligne $p/$n → rien appliqué, structure identique"
    total=$((total+1))
  done
  psql -q -d $B -v ON_ERROR_STOP=1 -f "$src" >/dev/null && echo "ok      $mig intacte appliquée ensuite"
done
psql -q -d postgres -c "drop database $B" >/dev/null
echo "TERMINÉ : $total échecs partiels simulés, aucune application partielle."
