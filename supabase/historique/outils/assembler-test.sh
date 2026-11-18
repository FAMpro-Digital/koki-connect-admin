#!/usr/bin/env bash
# Assemble les 37 fichiers de la référence en un seul fichier à exécuter sur la base TEST
# (supabase/historique/test/03-reference.sql). N'exécute rien.
set -euo pipefail
cd "$(dirname "$0")/../../.."
H=supabase/historique; out=$H/test/03-reference.sql
{
 echo "-- KOKI CONNECT TEST — RÉFÉRENCE DU 18/11/2026 (37 fichiers). GÉNÉRÉ par outils/assembler-test.sh, ne pas modifier."
 echo "-- NÉCESSITE UNE AUTORISATION EXPLICITE. Base TEST nettoyée uniquement (01-nettoyage.sql), jamais la production."
 echo "do \$\$ begin if exists(select 1 from auth.users limit 1) then raise exception 'GARDE : base non vide, référence refusée'; end if; end \$\$;"
 n=0
 while read -r f; do [ -z "$f" ] && continue; n=$((n+1))
  echo; echo "-- ===== $n/37 : $f · sha256 $(sha256sum "$f" | cut -c1-16)"; cat "$f"; echo
 done < $H/reference/ordre.txt
} > "$out"
echo "$out : $(wc -c < "$out") octets, $(grep -c '^-- ===== ' "$out") fichiers"
