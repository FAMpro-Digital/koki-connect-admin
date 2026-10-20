#!/usr/bin/env bash
# Lance les paliers 10 → 50 → 100 → 250 → 500 utilisateurs virtuels, et S'ARRÊTE au premier palier qui sature.
# ENVIRONNEMENT ISOLÉ UNIQUEMENT (Supabase local : `supabase start`). La garde de garde.js refuse la production.
#   BASE_URL=http://127.0.0.1:54321 ANON_KEY=sb_publishable_... ./loadtests/run-paliers.sh
set -uo pipefail
cd "$(dirname "$0")"
: "${BASE_URL:?BASE_URL requis (ex. http://127.0.0.1:54321)}"
: "${ANON_KEY:?ANON_KEY requis (clé publishable locale)}"
command -v k6 >/dev/null || { echo "k6 n'est pas installé (https://grafana.com/docs/k6/latest/set-up/install-k6/)"; exit 2; }
mkdir -p resultats
for palier in 10 50 100 250 500; do
  echo "== Palier ${palier} utilisateurs virtuels"
  k6 run -e BASE_URL="$BASE_URL" -e ANON_KEY="$ANON_KEY" -e PALIER="$palier" --summary-export "resultats/palier-${palier}.json" flux-public.js
  code=$?
  if [ "$code" -ne 0 ]; then
    echo "Arrêt : le palier ${palier} a dépassé un seuil (code ${code}). Les paliers suivants ne sont pas lancés."
    exit "$code"
  fi
done
echo "Tous les paliers sont passés."
