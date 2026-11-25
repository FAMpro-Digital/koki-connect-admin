#!/usr/bin/env bash
# Produit des réponses RÉELLES de public.koki_foot_public (base LOCALE) pour les tests d'intégration du site public.
# Usage : fixtures-foot.sh <dossier-de-sortie>   (ex. ../koki-connect/tests/fixtures/foot)
set -euo pipefail
cd "$(dirname "$0")/../../.."
OUT="$1"; mkdir -p "$OUT"; B=koki_foot_fixtures; H=supabase/historique
case "${PGHOST:-/var/run/postgresql}" in /*|localhost|127.0.0.1|::1) ;; *) echo "REFUS : hôte non local" >&2; exit 2;; esac
psql -q -d postgres -c "drop database if exists $B" -c "create database $B template koki_historique" >/dev/null
for f in $H/migrations/20261201000500_foot_schema.sql $H/migrations/20261201000600_foot_acces.sql; do psql -q -d $B -v ON_ERROR_STOP=1 -f $f >/dev/null; done
psql -q -d $B -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
insert into auth.users(id,email) values('f0000000-0000-4000-8000-000000000001','fixtures@test.local');
insert into public.koki_admin_members(user_id,role) values('f0000000-0000-4000-8000-000000000001','editor');
select set_config('request.jwt.claims','{"sub":"f0000000-0000-4000-8000-000000000001","aal":"aal2","role":"authenticated"}',false);
create temp table ids(k text primary key, v text);
insert into ids select 'comp',public.koki_foot_admin('enregistrer_competition','{"nom":"Navétanes Koki 2026","type":"Championnat","portee":"Koki","publie":true}')->>'id';
insert into ids select 'coupe',public.koki_foot_admin('enregistrer_competition','{"nom":"Coupe de Koki","type":"Coupe","portee":"Koki","publie":true}')->>'id';
insert into ids select 'a',public.koki_foot_admin('enregistrer_equipe','{"nom":"ASC Koki Ndiaye","couleurs":["#087a3d","#ffffff"]}')->>'id';
insert into ids select 'b',public.koki_foot_admin('enregistrer_equipe','{"nom":"ASC Darou"}')->>'id';
insert into ids select 'c',public.koki_foot_admin('enregistrer_equipe','{"nom":"ASC Gouye"}')->>'id';
-- Match en direct (championnat), avec but à 90+3.
insert into ids select 'direct',public.koki_foot_admin('enregistrer_match',jsonb_build_object('competition_id',(select v from ids where k='comp'),'domicile_id',(select v from ids where k='a'),'exterieur_id',(select v from ids where k='b'),'date_match',(now()-interval '95 minutes')::text,'lieu','Stade de Koki','publie',true))->>'id';
select public.koki_foot_admin('ajouter_evenement',jsonb_build_object('match_id',(select v from ids where k='direct'),'revision',1,'type','but','periode','mi_temps_1','minute',12,'equipe_id',(select v from ids where k='a'),'joueur','Moussa Fall'));
select public.koki_foot_admin('ajouter_evenement',jsonb_build_object('match_id',(select v from ids where k='direct'),'revision',(select revision from koki_foot.matchs where id=(select v::uuid from ids where k='direct')),'type','carton_jaune','periode','mi_temps_2','minute',90,'minute_add',3,'equipe_id',(select v from ids where k='b'),'joueur','Ibra Diop'));
select public.koki_foot_admin('score',jsonb_build_object('id',(select v from ids where k='direct'),'revision',(select revision from koki_foot.matchs where id=(select v::uuid from ids where k='direct')),'statut','En direct','minute',90));
-- Coupe terminée après prolongation et tirs au but.
insert into ids select 'tab',public.koki_foot_admin('enregistrer_match',jsonb_build_object('competition_id',(select v from ids where k='coupe'),'domicile_id',(select v from ids where k='b'),'exterieur_id',(select v from ids where k='c'),'date_match',(now()-interval '1 day')::text,'publie',true))->>'id';
select public.koki_foot_admin('score',jsonb_build_object('id',(select v from ids where k='tab'),'revision',1,'statut','Terminé','score_domicile',1,'score_exterieur',1,'pro_domicile',1,'pro_exterieur',1,'tab_domicile',4,'tab_exterieur',3));
-- Forfait.
insert into ids select 'forfait',public.koki_foot_admin('enregistrer_match',jsonb_build_object('competition_id',(select v from ids where k='comp'),'domicile_id',(select v from ids where k='c'),'exterieur_id',(select v from ids where k='a'),'date_match',(now()-interval '2 days')::text,'publie',true))->>'id';
select public.koki_foot_admin('forfait',jsonb_build_object('id',(select v from ids where k='forfait'),'revision',1,'equipe_id',(select v from ids where k='c'),'score_domicile',0,'score_exterieur',3,'motif','Équipe absente'));
-- Match à venir (demain 18 h à Koki).
select public.koki_foot_admin('enregistrer_match',jsonb_build_object('competition_id',(select v from ids where k='comp'),'domicile_id',(select v from ids where k='b'),'exterieur_id',(select v from ids where k='c'),'date_match',(date_trunc('day',now())+interval '1 day 18 hours')::text,'publie',true));
-- Match du fournisseur en direct (Sénégal), source dégradée.
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.koki_foot_sync('importer','{"fournisseur":"api-football","operation":"fixtures","competitions":[{"ref":"L1SN","nom":"Ligue 1 Sénégal","portee":"Sénégal"}],"equipes":[{"ref":"T1","nom":"ASC Jaraaf"},{"ref":"T2","nom":"Génération Foot"}],"matchs":[{"ref":"F1","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T16:00:00Z","statut":"En direct","minute":55,"score_domicile":0,"score_exterieur":1}],"evenements":[{"match_ref":"F1","cle":"F1|b|40","type":"but","periode":"mi_temps_1","minute":40,"equipe_ref":"T2","joueur":"Sarr"}]}');
update koki_foot.competitions set publie=true where ref_fournisseur='L1SN';
update koki_foot.matchs set date_match=now()-interval '60 minutes' where ref_fournisseur='F1';
update koki_foot.vus_api set vu_le=now()-interval '12 minutes';
select public.koki_foot_sync('erreur','{"fournisseur":"api-football","code":"indisponible","message":"HTTP 503"}');
create table public.fixtures_ids as select * from ids;
SQL
q(){ psql -Atq -d $B -c "$1"; }
q "select public.koki_foot_public('accueil','{}')" > "$OUT/accueil.json"
q "select public.koki_foot_public('match',jsonb_build_object('id',(select v from public.fixtures_ids where k='direct')))" > "$OUT/match-direct.json"
q "select public.koki_foot_public('match',jsonb_build_object('id',(select v from public.fixtures_ids where k='tab')))" > "$OUT/match-tab.json"
q "select public.koki_foot_public('match',jsonb_build_object('id',(select v from public.fixtures_ids where k='forfait')))" > "$OUT/match-forfait.json"
q "select public.koki_foot_public('match',jsonb_build_object('id',(select id::text from koki_foot.matchs where ref_fournisseur='F1')))" > "$OUT/match-api.json"
q "select public.koki_foot_public('classement',jsonb_build_object('competition_id',(select v from public.fixtures_ids where k='comp')))" > "$OUT/classement.json"
q "select public.koki_foot_public('sources','{}')" > "$OUT/sources.json"
q "select jsonb_build_object('genere_le',now(),'source','supabase/historique/outils/fixtures-foot.sh (koki-connect-admin), base locale')" > "$OUT/_origine.json"
psql -q -d postgres -c "drop database $B" >/dev/null
ls "$OUT"
