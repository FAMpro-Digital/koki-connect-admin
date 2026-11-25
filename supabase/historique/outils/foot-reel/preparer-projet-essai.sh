#!/usr/bin/env bash
# Prépare un projet Supabase HÉBERGÉ d'ESSAI (créé par le propriétaire, distinct de la production) :
# marqueur d'environnement d'essai, structure de production rejouée, migrations Football, comptes aléatoires.
# À lancer seulement après AUTORISATION ÉCRITE, depuis un poste de confiance ou le workflow manuel
# « Football — essais hébergés » (environnement GitHub protégé). Rien n'est écrit dans le dépôt.
#
# Variables (jamais dans Git) :
#   KOKI_ESSAI_URL              https://<ref>.supabase.co du projet d'ESSAI
#   KOKI_ESSAI_DB_URL           chaîne de connexion PostgreSQL du projet d'ESSAI
#   KOKI_ESSAI_PUBLISHABLE_KEY  clé sb_publishable_… du projet d'ESSAI
#   KOKI_ESSAI_SECRET_KEY       clé sb_secret_… du projet d'ESSAI (création des comptes d'essai)
#   KOKI_ESSAI_AUTORISATION     phrase exacte OUI-ESSAI-<ref>
#   KOKI_ESSAI_ENV              fichier de sortie des variables d'essai, HORS du dépôt
set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"; RACINE="$(cd "$ICI/../../../.." && pwd)"; H="$RACINE/supabase/historique"
PROD=qsbmzzbiztfqysstepxm
for v in KOKI_ESSAI_URL KOKI_ESSAI_DB_URL KOKI_ESSAI_PUBLISHABLE_KEY KOKI_ESSAI_SECRET_KEY KOKI_ESSAI_AUTORISATION KOKI_ESSAI_ENV; do
  [ -n "${!v:-}" ] || { echo "REFUS : variable $v absente" >&2; exit 2; }; done
REF=$(printf '%s' "$KOKI_ESSAI_URL" | sed -nE 's#^https://([a-z0-9]{20})\.supabase\.co$#\1#p')
[ -n "$REF" ] || { echo "REFUS : adresse de projet hébergé invalide" >&2; exit 2; }
[ "$REF" != "$PROD" ] || { echo "REFUS : projet de PRODUCTION" >&2; exit 2; }
case "$KOKI_ESSAI_DB_URL$KOKI_ESSAI_PUBLISHABLE_KEY$KOKI_ESSAI_SECRET_KEY" in *"$PROD"*) echo "REFUS : élément de PRODUCTION" >&2; exit 2;; esac
case "$KOKI_ESSAI_DB_URL" in *"$REF"*) ;; *) echo "REFUS : la base ne correspond pas au projet $REF" >&2; exit 2;; esac
[ "$KOKI_ESSAI_AUTORISATION" = "OUI-ESSAI-$REF" ] || { echo "REFUS : phrase d'autorisation attendue : OUI-ESSAI-$REF" >&2; exit 2; }
case "$KOKI_ESSAI_PUBLISHABLE_KEY" in sb_publishable_*) ;; *) echo "REFUS : clé publique sb_publishable_ attendue" >&2; exit 2;; esac
case "$KOKI_ESSAI_ENV" in "$RACINE"/*) echo "REFUS : le fichier des variables doit être hors du dépôt." >&2; exit 2;; esac
q(){ psql "$KOKI_ESSAI_DB_URL" -v ON_ERROR_STOP=1 -X -q "$@"; }

echo "── 1. Identification du projet d'essai $REF"
marqueur=$(q -Atc "select count(*) from pg_namespace where nspname='koki_essai'")
if [ "$marqueur" = 0 ]; then
  occupe=$(q -Atc "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','koki_private') and c.relkind='r'")
  [ "$occupe" = 0 ] || { echo "REFUS : projet non vide et sans marqueur d'essai : ce n'est pas un projet d'essai neuf" >&2; exit 2; }
  q -c "create schema koki_essai; create table koki_essai.environnement(nom text primary key, cree_le timestamptz not null default now());
        insert into koki_essai.environnement(nom) values('KOKI CONNECT — ENVIRONNEMENT D''ESSAI — aucune donnée réelle');
        revoke all on schema koki_essai from public, anon, authenticated;
        comment on schema koki_essai is 'Projet d''ESSAI du module Football. Jamais de données réelles. Jamais la production.'" >/dev/null
  echo "marqueur d'essai posé"
  echo "── 2. Structure de production rejouée (aucune donnée)"
  q -c "create extension if not exists pg_cron; create extension if not exists pg_net with schema extensions" >/dev/null
  while read -r f; do [ -z "$f" ] && continue
    if ! sortie=$(q -f "$RACINE/$f" 2>&1 >/dev/null); then echo "ÉCHEC $f"; echo "$sortie" | grep -E "ERROR|ERREUR" | head -3; exit 1; fi
  done < "$H/reference/ordre.txt"
  # Aucune tâche planifiée active sur le projet d'essai (notifications, envois) :
  q -c "select cron.unschedule(jobname) from cron.job" >/dev/null
  q -Atq -f "$H/outils/empreinte.sql" > "$KOKI_ESSAI_ENV.avant"
  python3 "$H/outils/comparer.py" "$H/reference/empreinte-production-2026-11-20.txt" "$KOKI_ESSAI_ENV.avant" || echo "(écarts listés ci-dessus : projet d'essai contre production)"
  echo "── 3. Migrations Football"
  for f in 20261201000500_foot_schema 20261201000600_foot_acces; do q -f "$H/migrations/$f.sql" >/dev/null && echo "ok      $f"; done
  q -Atq -f "$H/outils/empreinte.sql" > "$KOKI_ESSAI_ENV.apres"
  python3 "$H/outils/comparer-ajouts.py" "$KOKI_ESSAI_ENV.avant" "$KOKI_ESSAI_ENV.apres"
  q -c "notify pgrst, 'reload schema'" >/dev/null
else
  echo "marqueur d'essai présent : structure déjà préparée"
  [ "$(q -Atc "select count(*) from pg_namespace where nspname='koki_foot'")" = 1 ] || { echo "ÉCHEC : koki_foot absent" >&2; exit 1; }
fi
echo "── 4. Comptes et match d'essai (secrets aléatoires, fichier hors dépôt)"
( umask 077; node "$ICI/preparer-comptes.mjs" > "$KOKI_ESSAI_ENV" )
echo "variables d'essai écrites : $(wc -l < "$KOKI_ESSAI_ENV") lignes (droits 600)"
