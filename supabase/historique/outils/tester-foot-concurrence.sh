#!/usr/bin/env bash
# Tests de concurrence RÉELLE du module Football (deux sessions PostgreSQL simultanées), base LOCALE.
# Usage : tester-foot-concurrence.sh <base>   (appelé par tester-foot.sh, migrations déjà appliquées)
set -euo pipefail
B="$1"; T="${TMPDIR:-/tmp}/koki-foot-conc"; mkdir -p "$T"
case "${PGHOST:-/var/run/postgresql}" in /*|localhost|127.0.0.1|::1) ;; *) echo "REFUS : hôte non local" >&2; exit 2;; esac
ADM='d0000000-0000-4000-8000-0000000000aa'
CLAIMS="{\"sub\":\"$ADM\",\"aal\":\"aal2\",\"role\":\"authenticated\"}"
ok(){ echo "ok      $1"; }
ko(){ echo "ÉCHEC : $1"; exit 1; }

# Données : un éditeur, une compétition, deux équipes, un match.
psql -q -d "$B" -v ON_ERROR_STOP=1 >/dev/null <<SQL
insert into auth.users(id,email) values('$ADM','conc@test.local') on conflict do nothing;
insert into public.koki_admin_members(user_id,role) values('$ADM','editor') on conflict do nothing;
insert into koki_foot.competitions(id,nom,publie) values('c0c0c0c0-0000-4000-8000-000000000001','Concurrence',true);
insert into koki_foot.equipes(id,nom) values('e0e0e0e0-0000-4000-8000-000000000001','Conc A'),('e0e0e0e0-0000-4000-8000-000000000002','Conc B');
insert into koki_foot.matchs(id,competition_id,domicile_id,exterieur_id,date_match,publie)
 values('a0a0a0a0-0000-4000-8000-000000000001','c0c0c0c0-0000-4000-8000-000000000001','e0e0e0e0-0000-4000-8000-000000000001','e0e0e0e0-0000-4000-8000-000000000002',now(),true);
SQL
REV=$(psql -Atq -d "$B" -c "select revision from koki_foot.matchs where id='a0a0a0a0-0000-4000-8000-000000000001'")

# 1. Deux administrateurs modifient le même score en même temps, avec la même révision.
score(){ psql -Atq -d "$B" 2>&1 <<SQL
begin;
set role authenticated; select set_config('request.jwt.claims','$CLAIMS',true);
select public.koki_foot_admin('score','{"id":"a0a0a0a0-0000-4000-8000-000000000001","revision":$REV,"statut":"En direct","minute":10,"score_domicile":$1,"score_exterieur":$2}')->>'revision';
select pg_sleep($3);
commit;
SQL
}
score 1 0 2 > "$T/a.txt" & PA=$!
sleep 0.5
score 0 1 0 > "$T/b.txt" & PB=$!
wait $PA; wait $PB || true
FINAL=$(psql -Atq -d "$B" -c "select score_domicile||'-'||score_exterieur from koki_foot.matchs where id='a0a0a0a0-0000-4000-8000-000000000001'")
grep -q "Modifié entre-temps" "$T/b.txt" || ko "modification simultanée : le second appareil aurait dû être refusé ($(cat "$T/b.txt"))"
[ "$FINAL" = "1-0" ] || ko "modification simultanée : score final $FINAL au lieu de 1-0"
ok "modifications simultanées : le 2e appareil attend puis est refusé (révision périmée), score 1–0 conservé"

# 2. Deux synchronisations simultanées du même lot (nouveaux matchs) : aucun doublon, aucune erreur.
# Compétition et équipes déjà connues : les deux sessions se disputent la création du même match.
psql -Atq -d "$B" >/dev/null <<SQL
set role service_role; select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.koki_foot_sync('importer','{"fournisseur":"sportmonks","operation":"conc-prep","competitions":[{"ref":"SC1","nom":"Conc League"}],"equipes":[{"ref":"S1","nom":"S1"},{"ref":"S2","nom":"S2"}]}');
SQL
LOT='{"fournisseur":"sportmonks","operation":"conc","matchs":[{"ref":"SM1","competition_ref":"SC1","domicile_ref":"S1","exterieur_ref":"S2","date_match":"2026-12-05T16:00:00Z"}],"evenements":[{"match_ref":"SM1","cle":"SM1|k","type":"carton_jaune","periode":"mi_temps_1","minute":5}]}'
sync(){ psql -Atq -d "$B" 2>&1 <<SQL
begin;
set role service_role; select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.koki_foot_sync('importer','$LOT');
select pg_sleep($1);
commit;
SQL
}
sync 2 > "$T/s1.txt" & P1=$!
sleep 0.5
sync 0 > "$T/s2.txt" & P2=$!
wait $P1; wait $P2
grep -q '"statut": "ok"' "$T/s1.txt" && grep -q '"statut": "ok"' "$T/s2.txt" || ko "synchronisations simultanées : statuts $(cat "$T/s1.txt" "$T/s2.txt")"
grep -q '"crees": 0' "$T/s2.txt" || ko "synchronisations simultanées : la seconde aurait dû ne rien créer"
N=$(psql -Atq -d "$B" -c "select count(*) from koki_foot.matchs where fournisseur='sportmonks' and ref_fournisseur='SM1'")
[ "$N" = "1" ] || ko "synchronisations simultanées : $N matchs SM1"
ok "synchronisations simultanées : exécutées l'une après l'autre, 1 seul match, aucune erreur"
