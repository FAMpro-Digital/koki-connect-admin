#!/usr/bin/env bash
# Connecteur API-Football sur base LOCALE (après verifier.sh, qui crée koki_historique) :
#  1. intégration du connecteur avec la vraie fonction koki_foot_sync (fournisseur simulé) ;
#  2. propositions 0800 (planification) et 0810 (tâche pg_cron) : gardes, application, retours.
# Ne se connecte JAMAIS à Supabase ni à API-Football : refuse tout hôte non local.
set -euo pipefail
cd "$(dirname "$0")/../../.."
: "${PGPORT:=5432}"
if [ -z "${PGHOST:-}" ]; then
  if [ -S /var/run/postgresql/.s.PGSQL.$PGPORT ]; then PGHOST=/var/run/postgresql; else PGHOST=/tmp; fi
fi
export PGHOST PGPORT
case "$PGHOST" in /*|localhost|127.0.0.1|::1) ;; *) echo "REFUS : hôte « $PGHOST » non local." >&2; exit 2 ;; esac
P=supabase/historique/propositions

echo "── 1. Connecteur API-Football ↔ koki_foot_sync (fournisseur simulé)"
node supabase/historique/outils/tester-foot-api.mjs 2>&1 | grep -E '^(ok|TERMINÉ)'

echo "── 2. Propositions 0800 / 0810 : gardes, application, retours"
D=koki_foot_cron
psql -Xq -d postgres -c "drop database if exists $D" -c "create database $D template koki_historique" >/dev/null 2>&1
for f in supabase/historique/migrations/20261201000500_foot_schema.sql supabase/historique/migrations/20261201000600_foot_acces.sql $P/20261201000800_foot_planification_api.sql; do
  psql -Xq -v ON_ERROR_STOP=1 -d $D -f "$f" >/dev/null
done
if psql -Xq -v ON_ERROR_STOP=1 -d $D -f $P/20261201000810_foot_planification_cron.sql >/dev/null 2>&1; then echo "ÉCHEC : 0810 appliquée sans secret Vault"; exit 1; fi
echo "ok      0810 : refusée sans secret Vault"
psql -Xq -d $D -c "insert into vault.secrets(name,secret) values('koki_foot_sync_secret',repeat('k',40))" >/dev/null
psql -Xq -v ON_ERROR_STOP=1 -d $D -f $P/20261201000810_foot_planification_cron.sql >/dev/null
r=$(psql -XAt -d $D -c "select schedule||'|'||(command like '%kkkkkkkk%')||'|'||(command like '%/api/foot-sync%') from cron.job where jobname='koki-foot-sync'")
[ "$r" = "* * * * *|false|true" ] || { echo "ÉCHEC : tâche inattendue ($r)"; exit 1; }
echo "ok      0810 : tâche chaque minute, secret lu dans Vault (jamais en clair dans la commande)"
if psql -Xq -v ON_ERROR_STOP=1 -d $D -f $P/20261201000810_foot_planification_cron.sql >/dev/null 2>&1; then echo "ÉCHEC : seconde application de 0810"; exit 1; fi
echo "ok      0810 : seconde application bloquée"
avant=$(psql -XAt -d $D -c "select count(*) from cron.job where jobname<>'koki-foot-sync'")
psql -Xq -v ON_ERROR_STOP=1 -d $D -f $P/retour-20261201000810_foot_planification_cron.sql >/dev/null
[ "$(psql -XAt -d $D -c "select count(*) from cron.job where jobname='koki-foot-sync'")/$(psql -XAt -d $D -c "select count(*) from cron.job")" = "0/$avant" ] || { echo "ÉCHEC : retour 0810"; exit 1; }
echo "ok      retour 0810 : seule la tâche Football est retirée"
psql -Xq -v ON_ERROR_STOP=1 -d $D -f $P/retour-20261201000800_foot_planification_api.sql >/dev/null
[ "$(psql -XAt -d $D -c "select to_regprocedure('public.koki_foot_sync_planning(text)') is null")" = "t" ] || { echo "ÉCHEC : retour 0800"; exit 1; }
echo "ok      retour 0800 : fonction de planification retirée"
psql -Xq -d postgres -c "drop database $D" >/dev/null
echo "TERMINÉ : connecteur et propositions vérifiés en local."
