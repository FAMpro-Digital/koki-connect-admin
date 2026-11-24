#!/usr/bin/env bash
# Prépare la base du banc d'essai navigateur : copie de la référence de production + migrations Football + données de démonstration.
set -euo pipefail
cd "$(dirname "$0")/../../../.."
B="${BANC_BASE:-koki_foot_banc}"; H=supabase/historique
psql -q -d postgres -c "drop database if exists $B" -c "create database $B template koki_historique" >/dev/null
for f in $H/migrations/20261201000500_foot_schema.sql $H/migrations/20261201000600_foot_acces.sql; do psql -q -d $B -v ON_ERROR_STOP=1 -f $f >/dev/null; done
psql -q -d $B -v ON_ERROR_STOP=1 -f $H/outils/banc-foot/donnees.sql >/dev/null
echo "base $B prête"
