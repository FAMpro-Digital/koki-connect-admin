#!/usr/bin/env bash
# Vérifie le module Football (migrations 20261201000500 et 20261201000600, NON appliquées en production)
# sur une base LOCALE :
#  1. rejoue la référence de production (verifier.sh : empreinte du 20/11/2026, 0 écart attendu) ;
#  2. applique les migrations, puis vérifie que chaque garde bloque une seconde application ;
#  3. exécute supabase/tests/foot.sql (permissions, scores, Realtime, imports, verrous, conflits…) puis
#     les tests de concurrence réelle (tester-foot-concurrence.sh : deux sessions simultanées) ;
#  4. retours arrière : la structure redevient IDENTIQUE à la production actuelle ;
#  5. réapplique les migrations ;
#  6. prouve qu'aucun objet existant n'est modifié (seuls des objets Football sont ajoutés) ;
#  7. simule des échecs partiels : aucune application partielle.
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
M="$H/migrations/20261201000500_foot_schema.sql $H/migrations/20261201000600_foot_acces.sql"
R="$H/retour/20261201000600_foot_acces.sql $H/retour/20261201000500_foot_schema.sql"
B=koki_foot_test

echo "── 1. Référence de production"
bash $H/outils/verifier.sh | tail -1
psql -q -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists $B" -c "create database $B template koki_historique" >/dev/null

echo "── 2. Application et gardes"
for f in $M; do psql -q -d $B -v ON_ERROR_STOP=1 -f "$f" >/dev/null && echo "ok      $f"; done
for f in $M; do
  if psql -q -d $B -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1; then echo "ÉCHEC : la garde n'a pas bloqué une 2e application de $f"; exit 1; fi
  echo "garde   seconde application bloquée"
done

echo "── 3. Tests fonctionnels et de sécurité"
psql -d $B -v ON_ERROR_STOP=1 -f supabase/tests/foot.sql 2>&1 | grep -E "Tests réussis|ÉCHEC|ERROR|ERREUR" || { echo "ÉCHEC des tests"; exit 1; }
bash $H/outils/tester-foot-concurrence.sh $B
psql -d $B -Atc "select 'conseil  '||count(*)||' table(s) koki_foot sans RLS' from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='koki_foot' and c.relkind='r' and not c.relrowsecurity"
psql -d $B -Atc "select 'conseil  '||count(*)||' droit(s) direct(s) anon/authenticated sur koki_foot' from information_schema.role_table_grants where table_schema='koki_foot' and grantee in ('anon','authenticated','PUBLIC')"

echo "── 4. Retour arrière (avec données de test)"
psql -q -d $B -v ON_ERROR_STOP=1 -f $H/retour/20261201000600_foot_acces.sql >/dev/null && echo "ok      $H/retour/20261201000600_foot_acces.sql"
if psql -q -d $B -v ON_ERROR_STOP=1 -f $H/retour/20261201000500_foot_schema.sql >/dev/null 2>&1; then echo "ÉCHEC : le retour n'a pas protégé les données"; exit 1; fi
echo "garde   retour bloqué tant que des données existent"
PGOPTIONS="-c koki.retour_force=oui" psql -q -d $B -v ON_ERROR_STOP=1 -f $H/retour/20261201000500_foot_schema.sql >/dev/null && echo "ok      $H/retour/20261201000500_foot_schema.sql"
psql -q -d $B -c "delete from public.koki_audit where table_name in ('competitions','equipes','matchs'); delete from public.koki_admin_members; delete from auth.users" >/dev/null
psql -Atq -d $B -f $H/outils/empreinte.sql > "${TMPDIR:-/tmp}/empreinte-foot-retour.txt"
echo "état après retour (production du 20/11/2026) :"
python3 $H/outils/comparer.py $H/reference/empreinte-production-2026-11-20.txt "${TMPDIR:-/tmp}/empreinte-foot-retour.txt"

echo "── 5. Réapplication après retour"
for f in $M; do psql -q -d $B -v ON_ERROR_STOP=1 -f "$f" >/dev/null && echo "ok      $f"; done
echo "── 6. Objets existants inchangés (empreinte de production du 20/11/2026 contre état après migrations)"
psql -Atq -d $B -f $H/outils/empreinte.sql > "${TMPDIR:-/tmp}/empreinte-foot-apres.txt"
python3 $H/outils/comparer-ajouts.py $H/reference/empreinte-production-2026-11-20.txt "${TMPDIR:-/tmp}/empreinte-foot-apres.txt"
psql -q -d postgres -c "drop database $B" >/dev/null
echo "── 7. Échec partiel d'une migration : rien n'est appliqué"
bash $H/outils/tester-foot-echec-partiel.sh | tail -1
echo "TERMINÉ : module Football vérifié en local."
