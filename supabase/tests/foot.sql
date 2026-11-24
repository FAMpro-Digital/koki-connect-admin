-- Tests du module Football (koki_foot) sur une base LOCALE rejouant la référence de production.
-- Lancement : bash supabase/historique/outils/tester-foot.sh
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = warning;

-- ───── Outils de test (schéma t) ─────
create schema t;
grant usage on schema t to anon, authenticated, service_role;
create table t.journal(n serial, ok text);
grant insert, select on t.journal to anon, authenticated, service_role; grant usage on sequence t.journal_n_seq to anon, authenticated, service_role;
create function t.as_user(uid text, aal text default 'aal1') returns void language sql as $$
 select set_config('request.jwt.claim.sub',coalesce(uid,''),false), set_config('request.jwt.claims',json_build_object('sub',uid,'aal',aal,'role','authenticated')::text,false), null::void $$;
create function t.as_anon() returns void language sql as $$
 select set_config('request.jwt.claim.sub','',false), set_config('request.jwt.claims','{"role":"anon"}',false), null::void $$;
create function t.as_service() returns void language sql as $$
 select set_config('request.jwt.claim.sub','',false), set_config('request.jwt.claims','{"role":"service_role"}',false), null::void $$;
create function t.ok(cond boolean, msg text) returns void language plpgsql as $$
begin if cond is not true then raise exception 'ÉCHEC : %', msg; end if; insert into t.journal(ok) values(msg); end $$;
create function t.err(q text, pattern text, msg text) returns void language plpgsql as $$
declare e text;
begin
 begin execute q; exception when others then e:=sqlerrm; end;
 if e is null then raise exception 'ÉCHEC (aucune erreur) : %', msg; end if;
 if e !~* pattern then raise exception 'ÉCHEC (% ≠ %) : %', e, pattern, msg; end if;
 insert into t.journal(ok) values(msg);
end $$;
create function t.adm(cmd text, input jsonb default '{}') returns jsonb language sql as $$ select public.koki_foot_admin(cmd,input) $$;
create function t.pub(cmd text, input jsonb default '{}') returns jsonb language sql as $$ select public.koki_foot_public(cmd,input) $$;
create function t.sync(cmd text, input jsonb default '{}') returns jsonb language sql as $$ select public.koki_foot_sync(cmd,input) $$;
create function t.rev(m uuid) returns integer language sql security definer as $$ select revision from koki_foot.matchs where id=m $$;
create function t.rev_l1() returns integer language sql security definer as $$ select revision from koki_foot.competitions where ref_fournisseur='L1SN' $$;
create function t.id_l1() returns uuid language sql security definer as $$ select id from koki_foot.competitions where ref_fournisseur='L1SN' $$;
create function t.evt(m uuid) returns uuid language sql security definer as $$ select id from koki_foot.evenements where match_id=m limit 1 $$;
grant execute on all functions in schema t to anon, authenticated, service_role;

-- Realtime simulé : realtime.send enregistre les messages diffusés (en production : Supabase Realtime).
create schema realtime;
create table t.diffusions(n serial, evenement text, topic text, prive boolean, charge jsonb);
create function realtime.send(payload jsonb, event text, topic text, private boolean default true) returns void language sql as
$$ insert into t.diffusions(evenement,topic,prive,charge) values(event,topic,private,payload) $$;

-- Acteurs fictifs
insert into auth.users(id,email) values
 ('d0000000-0000-4000-8000-000000000001','super@test.local'),('d0000000-0000-4000-8000-000000000002','editeur@test.local'),
 ('d0000000-0000-4000-8000-000000000003','analyste@test.local'),('c0000000-0000-4000-8000-000000000001','habitant@test.local');
insert into public.koki_admin_members(user_id,role) values('d0000000-0000-4000-8000-000000000001','superadmin'),
 ('d0000000-0000-4000-8000-000000000002','editor'),('d0000000-0000-4000-8000-000000000003','analyst');
\set super 'd0000000-0000-4000-8000-000000000001'
\set editeur 'd0000000-0000-4000-8000-000000000002'
\set analyste 'd0000000-0000-4000-8000-000000000003'
\set habitant 'c0000000-0000-4000-8000-000000000001'

-- ═════ 1. Permissions (RLS et droits) ═════
set role anon; select t.as_anon();
select t.err($$select * from koki_foot.matchs$$,'permission denied','anon : aucun accès direct aux tables');
select t.err($$select public.koki_foot_admin('etat','{}')$$,'permission denied','anon : administration interdite');
select t.err($$select public.koki_foot_sync('references','{"fournisseur":"api-football"}')$$,'permission denied','anon : synchronisation interdite');
select t.ok(jsonb_array_length(t.pub('competitions'))=0,'anon : lecture publique autorisée (vide)');
set role authenticated; select t.as_user(:'habitant','aal2');
select t.err($$select * from koki_foot.equipes$$,'permission denied','utilisateur : aucun accès direct aux tables');
select t.err($$update koki_foot.matchs set score_domicile=9$$,'permission denied','utilisateur : modification directe d''un score impossible');
select t.err($$select t.adm('etat')$$,'double authentification requises','utilisateur ordinaire : administration refusée');
select t.err($$select t.adm('enregistrer_equipe','{"nom":"Pirate"}')$$,'double authentification requises','utilisateur ordinaire : ne peut pas créer d''équipe');
select t.err($$select t.sync('references','{"fournisseur":"api-football"}')$$,'permission denied','utilisateur : synchronisation interdite');
select t.as_user(:'editeur','aal1');
select t.err($$select t.adm('etat')$$,'double authentification','éditeur sans 2FA (aal1) : refusé');
select t.as_user(:'analyste','aal2');
select t.ok(t.adm('etat') ? 'matchs','analyste : lecture autorisée');
select t.err($$select t.adm('enregistrer_equipe','{"nom":"Analyste FC"}')$$,'double authentification requises','analyste : écriture refusée');

-- ═════ 2. Création des équipes, de la compétition et programmation d'un match ═════
select t.as_user(:'editeur','aal2');
select t.adm('enregistrer_equipe','{"nom":"ASC Koki Ndiaye","quartier":"Koki Ndiaye","couleurs":["#087A3D","#ffffff"]}')->>'id' as eq1 \gset
select t.adm('enregistrer_equipe','{"nom":"ASC Darou","couleurs":["#c0392b"]}')->>'id' as eq2 \gset
select t.adm('enregistrer_equipe','{"nom":"ASC Gouye"}')->>'id' as eq3 \gset
select t.err($$select t.adm('enregistrer_equipe','{"nom":"asc koki ndiaye "}')$$,'equipes_nom_manuel','doublon de nom d''équipe locale refusé');
select t.err($$select t.adm('enregistrer_equipe','{"nom":"X","couleurs":["rouge"]}')$$,'check','couleur invalide refusée');
select t.err($$select t.adm('enregistrer_equipe','{"nom":"X","pirate":1}')$$,'Champ non autorisé','champ inattendu refusé');
select t.adm('enregistrer_competition','{"nom":"Navétanes Koki 2026","saison":"2026","portee":"Koki","type":"Championnat"}')->>'id' as comp \gset
select t.adm('inscrire_equipe',jsonb_build_object('competition_id',:'comp','equipe_id',:'eq1','poule','A'));
select t.adm('inscrire_equipe',jsonb_build_object('competition_id',:'comp','equipe_id',:'eq2','poule','A'));
select t.adm('inscrire_equipe',jsonb_build_object('competition_id',:'comp','equipe_id',:'eq3','poule','A'));
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'comp','domicile_id',:'eq1','exterieur_id',:'eq2','date_match',(now()+interval '2 hours')::text,'lieu','Stade de Koki','journee','1re journée','poule','A','publie',true)) as m1j \gset
select (:'m1j'::jsonb)->>'id' as m1 \gset
select t.ok((:'m1j'::jsonb)->>'statut'='À venir','match programmé : statut À venir');
select t.err(format($$select t.adm('enregistrer_match','{"competition_id":"%s","domicile_id":"%s","exterieur_id":"%s","date_match":"2026-12-01T16:00:00Z"}')$$,:'comp',:'eq1',:'eq1'),'check','une équipe ne joue pas contre elle-même');
select t.err(format($$select t.adm('enregistrer_match','{"competition_id":"%s","domicile_id":"%s","exterieur_id":"%s"}')$$,:'comp',:'eq1',:'eq2'),'Date du match requise','date obligatoire');
-- Compétition non publiée : invisible du public.
set role anon; select t.as_anon();
select t.ok(jsonb_array_length(t.pub('accueil')->'a_venir')=0,'compétition non publiée : match invisible');
set role authenticated; select t.as_user(:'editeur','aal2');
select t.adm('enregistrer_competition',jsonb_build_object('id',:'comp','revision',1,'publie',true));
set role anon; select t.as_anon();
select t.ok(jsonb_array_length(t.pub('accueil')->'a_venir')=1,'compétition publiée : match visible à l''accueil');
select t.ok(t.pub('accueil','{"portee":"Sénégal"}')->'a_venir'='[]'::jsonb,'filtre de portée Sénégal : vide');
select t.ok((t.pub('accueil','{"portee":"Koki"}')->'a_venir'->0->'domicile'->>'nom')='ASC Koki Ndiaye','filtre de portée Koki');
select t.err($$select t.pub('accueil','{"portee":"Mars"}')$$,'Portée invalide','portée inconnue refusée');

-- ═════ 3. Modification du score, en direct, corrections ═════
set role authenticated; select t.as_user(:'editeur','aal2');
select current_user as role_courant \gset
reset role;
truncate t.diffusions;
set role :role_courant;
select t.adm('score',jsonb_build_object('id',:'m1','revision',t.rev(:'m1'),'statut','En direct','minute',1));
select current_user as role_courant \gset
reset role;
select t.ok((select score_domicile=0 and score_exterieur=0 and statut='En direct' from koki_foot.matchs where id=:'m1'),'coup d''envoi : 0–0 En direct');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from t.diffusions where topic='koki-foot' and evenement='match' and not prive)=1,'Realtime : coup d''envoi diffusé sur le canal public koki-foot');
set role :role_courant;
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'m1','revision',t.rev(:'m1'),'type','but','periode','mi_temps_1','minute',12,'equipe_id',:'eq1','joueur','Moussa Fall'));
select current_user as role_courant \gset
reset role;
select t.ok((select score_domicile=1 and score_exterieur=0 from koki_foot.matchs where id=:'m1'),'but : score 1–0 mis à jour');
set role :role_courant;
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'m1','revision',t.rev(:'m1'),'type','but_csc','periode','mi_temps_1','minute',30,'equipe_id',:'eq1','joueur','Ibra Diop'));
select current_user as role_courant \gset
reset role;
select t.ok((select score_domicile=1 and score_exterieur=1 from koki_foot.matchs where id=:'m1'),'but contre son camp : compté pour l''adversaire (1–1)');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from t.diffusions where evenement='evenement' and charge->>'match_id'=:'m1')=2,'Realtime : événements diffusés');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from t.diffusions where evenement='match' and (charge->>'score_domicile')::int=1 and (charge->>'score_exterieur')::int=1)=1,'Realtime : nouveau score diffusé');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select charge ?& array['id','statut','minute','score_domicile','score_exterieur','revision'] and not charge ? 'commentaire' from t.diffusions where evenement='match' order by n desc limit 1),'Realtime : charge minimale (aucune donnée privée)');
set role :role_courant;
-- Conflit d'édition entre deux appareils administrateurs.
select t.err(format($$select t.adm('score','{"id":"%s","revision":1,"score_domicile":5,"score_exterieur":0,"statut":"En direct"}')$$,:'m1'),'Modifié entre-temps','révision périmée : deuxième appareil refusé');
-- Minute seule : diffusée, sans correction journalisée.
select current_user as role_courant \gset
reset role;
select count(*) as corr_avant from koki_foot.corrections where match_id=:'m1' \gset
set role :role_courant;
select t.adm('score',jsonb_build_object('id',:'m1','revision',t.rev(:'m1'),'statut','En direct','minute',35,'score_domicile',1,'score_exterieur',1));
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from koki_foot.corrections where match_id=:'m1')=:corr_avant,'minute seule : pas de correction journalisée');
set role :role_courant;
select t.adm('score',jsonb_build_object('id',:'m1','revision',t.rev(:'m1'),'statut','Terminé','score_domicile',2,'score_exterieur',1));
select current_user as role_courant \gset
reset role;
select t.ok((select statut='Terminé' and minute is null from koki_foot.matchs where id=:'m1'),'fin du match');
set role :role_courant;
select t.err(format($$select t.adm('score','{"id":"%s","revision":%s,"statut":"Terminé","score_domicile":3,"score_exterieur":1}')$$,:'m1',t.rev(:'m1')),'Motif','match terminé : correction sans motif refusée');
select t.adm('score',jsonb_build_object('id',:'m1','revision',t.rev(:'m1'),'statut','Terminé','score_domicile',3,'score_exterieur',1,'motif','But oublié à la 89e'));
select current_user as role_courant \gset
reset role;
select t.ok((select apres->'score'->>0='3' and avant->'score'->>0='2' and motif='But oublié à la 89e' and acteur=:'editeur' from koki_foot.corrections where match_id=:'m1' order by id desc limit 1),'correction journalisée : avant, après, auteur, motif');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select count(*)>0 from public.koki_audit where table_name='matchs' and record_id=:'m1'::uuid),'journal koki_audit alimenté');
set role :role_courant;
reset role;
select t.err(format($$update koki_foot.corrections set motif='effacé' where match_id='%s'$$,:'m1'),'ajout seul','journal des corrections : modification impossible (même propriétaire)');
select t.err(format($$delete from koki_foot.corrections where match_id='%s'$$,:'m1'),'ajout seul','journal des corrections : suppression impossible');

-- ═════ 4. Affichage public : match, événements, classement ═════
set role anon; select t.as_anon();
select t.ok(jsonb_array_length(t.pub('match',jsonb_build_object('id',:'m1'))->'evenements')=2,'détail du match : événements affichés');
select t.ok((t.pub('match',jsonb_build_object('id',:'m1'))->'evenements'->0->>'joueur')='Moussa Fall','événements dans l''ordre des minutes');
select t.ok((t.pub('accueil')->'resultats'->0->>'score_domicile')='3','résultat corrigé visible');
select t.ok((t.pub('classement',jsonb_build_object('competition_id',:'comp'))->0->'equipe'->>'nom')='ASC Koki Ndiaye','classement calculé : vainqueur 1er');
select t.ok((t.pub('classement',jsonb_build_object('competition_id',:'comp'))->0->>'points')='3','classement : victoire = 3 points');
select t.ok(jsonb_array_length(t.pub('classement',jsonb_build_object('competition_id',:'comp')))=3,'classement : équipe inscrite sans match présente (0 point)');
select t.ok((t.pub('classement',jsonb_build_object('competition_id',:'comp'))->1->>'forme')='D' or (t.pub('classement',jsonb_build_object('competition_id',:'comp'))->2->>'forme')='D','classement : forme V/N/D');
-- Match dépublié : retiré de la vue publique, retrait diffusé.
set role authenticated; select t.as_user(:'editeur','aal2');
select current_user as role_courant \gset
reset role;
truncate t.diffusions;
set role :role_courant;
select t.adm('enregistrer_match',jsonb_build_object('id',:'m1','revision',t.rev(:'m1'),'publie',false));
select current_user as role_courant \gset
reset role;
select t.ok((select (charge->>'visible')::boolean=false from t.diffusions where evenement='match'),'Realtime : dépublication diffusée (retrait des écrans)');
set role :role_courant;
set role anon; select t.as_anon();
select t.ok(t.pub('match',jsonb_build_object('id',:'m1')) is null,'match dépublié : invisible');
set role authenticated; select t.as_user(:'editeur','aal2');
select current_user as role_courant \gset
reset role;
truncate t.diffusions;
set role :role_courant;
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'comp','domicile_id',:'eq2','exterieur_id',:'eq3','date_match',(now()+interval '1 day')::text)) ->>'id' as m2 \gset
select t.adm('score',jsonb_build_object('id',:'m2','revision',t.rev(:'m2'),'statut','En direct','minute',5));
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from t.diffusions)=0,'Realtime : match non publié jamais diffusé');
set role :role_courant;
reset role;
-- La diffusion ne bloque jamais l'enregistrement d'un score.
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true) returns void language plpgsql as $$ begin raise exception 'Realtime indisponible'; end $$;
set role authenticated; select t.as_user(:'editeur','aal2');
select t.adm('enregistrer_match',jsonb_build_object('id',:'m2','revision',t.rev(:'m2'),'publie',true));
select t.adm('score',jsonb_build_object('id',:'m2','revision',t.rev(:'m2'),'statut','En direct','minute',6,'score_domicile',1,'score_exterieur',0));
select current_user as role_courant \gset
reset role;
select t.ok((select score_domicile=1 from koki_foot.matchs where id=:'m2'),'panne Realtime : le score est quand même enregistré');
set role :role_courant;
reset role;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true) returns void language sql as
$$ insert into t.diffusions(evenement,topic,prive,charge) values(event,topic,private,payload) $$;

-- ═════ 5. Import automatique sans doublons ═════
set role service_role; select t.as_service();
\set lot '{"fournisseur":"api-football","operation":"test","competitions":[{"ref":"L1SN","nom":"Ligue 1 Sénégal","saison":"2025","portee":"Sénégal"}],"equipes":[{"ref":"T1","nom":"ASC Jaraaf","logo_url":"https://media.example.com/t1.png"},{"ref":"T2","nom":"Génération Foot"},{"ref":"T3","nom":"Teungueth FC"}],"inscriptions":[{"competition_ref":"L1SN","equipe_ref":"T1"},{"competition_ref":"L1SN","equipe_ref":"T2"}],"matchs":[{"ref":"F100","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T16:00:00Z","statut":"En direct","minute":20,"score_domicile":1,"score_exterieur":0},{"ref":"F101","competition_ref":"L1SN","domicile_ref":"T3","exterieur_ref":"T1","date_match":"2026-11-30T16:00:00Z","statut":"À venir"}],"evenements":[{"match_ref":"F100","cle":"F100|but|12|T1|Diallo","type":"but","periode":"mi_temps_1","minute":12,"equipe_ref":"T1","joueur":"A. Diallo"}],"classements":[{"competition_ref":"L1SN","equipe_ref":"T1","rang":1,"joues":10,"gagnes":7,"nuls":2,"perdus":1,"buts_pour":15,"buts_contre":5,"points":23,"forme":"VVNVD"},{"competition_ref":"L1SN","equipe_ref":"T2","rang":2,"joues":10,"points":20}]}'
select t.sync('importer',:'lot') as r1 \gset
select t.ok((:'r1'::jsonb->>'statut')='ok' and (:'r1'::jsonb->>'crees')::int=7,'premier import : 1 compétition, 3 équipes, 2 matchs, 1 événement');
select t.sync('importer',:'lot') as r2 \gset
select t.ok((:'r2'::jsonb->>'crees')::int=0 and (:'r2'::jsonb->>'mis_a_jour')::int=0,'second import identique : aucune création ni mise à jour');
reset role;
select t.ok((select count(*) from koki_foot.matchs where source='api')=2 and (select count(*) from koki_foot.evenements where source='api')=1
 and (select count(*) from koki_foot.equipes where source='api')=3 and (select count(*) from koki_foot.classements)=2,'aucun doublon en base');
select current_user as role_courant \gset
reset role;
select t.ok((select not publie from koki_foot.competitions where ref_fournisseur='L1SN'),'compétition importée non publiée par défaut');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from koki_foot.synchronisations where statut='ok')=2,'imports journalisés');
set role :role_courant;

-- ═════ 6. Erreurs du fournisseur ═════
set role service_role; select t.as_service();
select t.sync('erreur','{"fournisseur":"api-football","operation":"fixtures","message":"HTTP 429 : quota dépassé"}');
select t.sync('importer','{"fournisseur":"api-football","operation":"test-partiel","matchs":[{"ref":"F200","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T9","date_match":"2026-12-01T16:00:00Z"},{"ref":"F201","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T3","date_match":"2026-12-01T18:00:00Z","statut":"Terminé"},{"ref":"F202","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T3","date_match":"2026-12-02T18:00:00Z"}]}') as r3 \gset
select t.ok((:'r3'::jsonb->>'statut')='partiel' and (:'r3'::jsonb->>'rejetes')::int=2 and (:'r3'::jsonb->>'crees')::int=1,'données invalides du fournisseur rejetées, le reste importé');
select t.err($$select t.sync('importer','{"fournisseur":"pirate"}')$$,'Fournisseur invalide','fournisseur inconnu refusé');
select t.err($$select t.sync('importer','{"fournisseur":"api-football","sql":"drop"}')$$,'Champ non autorisé','champ inattendu refusé à l''import');
reset role;
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from koki_foot.synchronisations where statut='erreur')=1 and (select count(*) from koki_foot.synchronisations where statut='partiel')=1,'erreurs du fournisseur journalisées');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select message ~ 'T9|inconnue' from koki_foot.synchronisations where statut='partiel'),'motif du rejet conservé');
set role :role_courant;
-- Un utilisateur authentifié ne peut pas se faire passer pour la synchronisation.
set role authenticated; select set_config('request.jwt.claims','{"role":"service_role"}',false);
select t.err($$select public.koki_foot_sync('references','{"fournisseur":"api-football"}')$$,'permission denied','rôle authenticated + faux jeton service_role : refusé');

-- ═════ 7. Protection des corrections manuelles ═════
select t.as_user(:'editeur','aal2');
select current_user as role_courant \gset
reset role;
select id as f100 from koki_foot.matchs where ref_fournisseur='F100' \gset
set role :role_courant;
select current_user as role_courant \gset
reset role;
reset role; select revision as rev100 from koki_foot.matchs where id=:'f100' \gset
set role :role_courant;
set role authenticated; select t.as_user(:'editeur','aal2');
select t.err(format($$select t.adm('score','{"id":"%s","revision":%s,"statut":"En direct","minute":25,"score_domicile":2,"score_exterieur":0}')$$,:'f100',:rev100),'Motif','match importé : correction sans motif refusée');
select t.adm('score',jsonb_build_object('id',:'f100','revision',:rev100,'statut','En direct','minute',25,'score_domicile',2,'score_exterieur',0,'motif','Le fournisseur n''a pas vu le 2e but'));
reset role;
select current_user as role_courant \gset
reset role;
select t.ok((select verrou_manuel and verrouille_par=:'editeur' from koki_foot.matchs where id=:'f100'),'correction d''un match importé : match verrouillé');
set role :role_courant;
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from koki_foot.corrections where match_id=:'f100' and action='verrou')=1,'verrouillage journalisé');
set role :role_courant;
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"test-verrou","matchs":[{"ref":"F100","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T16:00:00Z","statut":"En direct","minute":30,"score_domicile":1,"score_exterieur":0}],"evenements":[{"match_ref":"F100","cle":"F100|but|28|T2|Sarr","type":"but","periode":"mi_temps_1","minute":28,"equipe_ref":"T2","joueur":"Sarr"}]}') as r4 \gset
reset role;
select current_user as role_courant \gset
reset role;
select t.ok((select score_domicile=2 and score_exterieur=0 from koki_foot.matchs where id=:'f100'),'synchronisation : score corrigé conservé (2–0, pas 1–0)');
set role :role_courant;
select t.ok((:'r4'::jsonb->>'ignores_verrou')::int=2,'synchronisation : match et événement ignorés comptés');
select current_user as role_courant \gset
reset role;
select t.ok((select count(*) from koki_foot.evenements where match_id=:'f100')=1,'événement du fournisseur ignoré sur match verrouillé');
set role :role_courant;
-- Événement api non supprimable par l'admin (il reviendrait à l'import).
set role authenticated; select t.as_user(:'editeur','aal2');
select t.err(format($$select t.adm('deverrouiller','{"id":"%s","revision":%s}')$$,:'f100',t.rev(:'f100')),'Motif','déverrouillage sans motif refusé');
select t.adm('deverrouiller',jsonb_build_object('id',:'f100','revision',t.rev(:'f100'),'motif','Fournisseur à jour'));
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"test-deverrou","matchs":[{"ref":"F100","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T16:00:00Z","statut":"Terminé","score_domicile":2,"score_exterieur":1}]}');
reset role;
select current_user as role_courant \gset
reset role;
select t.ok((select statut='Terminé' and score_exterieur=1 and not verrou_manuel from koki_foot.matchs where id=:'f100'),'après déverrouillage : le fournisseur reprend la main');
set role :role_courant;
-- Liste complète d'événements : but annulé (VAR) retiré, sans doublon.
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"test-complet","evenements":[{"match_ref":"F100","cle":"F100|but|28|T2|Sarr","type":"but","periode":"mi_temps_1","minute":28,"equipe_ref":"T2","joueur":"Sarr"}],"evenements_complets":["F100"]}');
reset role;
select current_user as role_courant \gset
reset role;
select t.ok((select array_agg(joueur order by joueur) from koki_foot.evenements where match_id=:'f100')=array['Sarr'],'liste complète : but annulé retiré, nouveau but ajouté une seule fois');
set role :role_courant;
-- Compétition manuelle intouchable par la synchronisation ; match manuel jamais créé dans une compétition importée.
select current_user as role_courant \gset
reset role;
select t.ok((select score_domicile=3 from koki_foot.matchs where id=:'m1'),'match manuel inchangé après les imports');
set role :role_courant;
set role authenticated; select t.as_user(:'editeur','aal2');
select t.err(format($$select t.adm('enregistrer_match','{"competition_id":"%s","domicile_id":"%s","exterieur_id":"%s","date_match":"2026-12-01T16:00:00Z"}')$$,t.id_l1(),:'eq1',:'eq2'),'compétition locale','match manuel refusé dans une compétition importée');
select t.adm('enregistrer_competition',jsonb_build_object('id',t.id_l1(),'revision',t.rev_l1(),'nom','Nom pirate','publie',true));
select current_user as role_courant \gset
reset role;
select t.ok((select nom='Ligue 1 Sénégal' and publie from koki_foot.competitions where ref_fournisseur='L1SN'),'compétition importée : publication réglable, nom protégé');
set role :role_courant;
set role anon; select t.as_anon();
select t.ok((t.pub('classement',jsonb_build_object('competition_id',t.id_l1()))->0->>'points')='23','classement importé affiché');
select t.ok((select count(*) from jsonb_array_elements(t.pub('accueil','{"portee":"Sénégal"}')->'resultats'))=1,'accueil : filtre Sénégal');
set role service_role; select t.as_service();
select t.ok((t.sync('references','{"fournisseur":"api-football"}')->'competitions'->0->>'ref')='L1SN','références : compétitions publiées à suivre');

-- ════════════════ TESTS COMPLÉMENTAIRES (revue technique) ════════════════
reset role;
\set E 'set role authenticated; select t.as_user(\'d0000000-0000-4000-8000-000000000002\',\'aal2\');'

-- ═════ 8. Prolongations et tirs au but (champs distincts) ═════
:E
select t.adm('enregistrer_competition','{"nom":"Coupe de Koki 2026","type":"Coupe","portee":"Koki","publie":true}')->>'id' as coupe \gset
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'coupe','domicile_id',:'eq1','exterieur_id',:'eq3','date_match',(now()-interval '2 hours')::text,'publie',true))->>'id' as cm \gset
select t.adm('score',jsonb_build_object('id',:'cm','revision',t.rev(:'cm'),'statut','En direct','minute',1));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'cm','revision',t.rev(:'cm'),'type','but','periode','mi_temps_1','minute',40,'equipe_id',:'eq1','joueur','Fall'));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'cm','revision',t.rev(:'cm'),'type','penalty','periode','mi_temps_2','minute',88,'equipe_id',:'eq3','joueur','Ndiaye'));
select t.adm('score',jsonb_build_object('id',:'cm','revision',t.rev(:'cm'),'statut','Prolongations','minute',91));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'cm','revision',t.rev(:'cm'),'type','but','periode','prolongation_1','minute',105,'equipe_id',:'eq3','joueur','Sow'));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'cm','revision',t.rev(:'cm'),'type','but_csc','periode','prolongation_2','minute',118,'equipe_id',:'eq3','joueur','Ba'));
reset role;
select t.ok((select (score_domicile,score_exterieur,pro_domicile,pro_exterieur)=(1,1,1,1) from koki_foot.matchs where id=:'cm'),'prolongation : réglementaire 1–1 et prolongation 1–1 dans des champs distincts');
select t.ok(((select koki_foot.coherence(m) from koki_foot.matchs m where id=:'cm')->>'etat')='coherent','cohérence buts ↔ score (penalty, csc, prolongation)');
:E
select t.adm('score',jsonb_build_object('id',:'cm','revision',t.rev(:'cm'),'statut','Tirs au but','minute',120));
select t.adm('score',jsonb_build_object('id',:'cm','revision',t.rev(:'cm'),'statut','Terminé','tab_domicile',4,'tab_exterieur',3));
reset role;
select t.ok((select statut='Terminé' and (tab_domicile,tab_exterieur)=(4,3) and (score_domicile,score_exterieur)=(1,1) and minute is null from koki_foot.matchs where id=:'cm'),'tirs au but 4–3 séparés du score réglementaire');
select t.ok((select (charge->>'tab_domicile')::int=4 from t.diffusions where evenement='match' and charge->>'id'=:'cm' order by n desc limit 1),'Realtime : tirs au but diffusés');
:E
select t.err(format($$select t.adm('score','{"id":"%s","revision":%s,"statut":"En direct","pro_domicile":1,"pro_exterieur":0}')$$,:'m2',t.rev(:'m2')),'championnat','championnat : prolongation refusée');
select t.err(format($$select t.adm('score','{"id":"%s","revision":%s,"statut":"En direct","pro_domicile":1,"pro_exterieur":null}')$$,:'cm',t.rev(:'cm')),'deux équipes','score incomplet refusé');

-- ═════ 9. Matchs interrompus, suspendus et reportés ═════
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'comp','domicile_id',:'eq3','exterieur_id',:'eq1','date_match',(now()-interval '1 hour')::text,'publie',true))->>'id' as ms \gset
select t.adm('score',jsonb_build_object('id',:'ms','revision',t.rev(:'ms'),'statut','En direct','minute',60,'score_domicile',1,'score_exterieur',0));
select t.adm('score',jsonb_build_object('id',:'ms','revision',t.rev(:'ms'),'statut','Interrompu'));
reset role;
select t.ok((select statut='Interrompu' and minute=60 and score_domicile=1 from koki_foot.matchs where id=:'ms'),'interrompu : score et minute conservés');
select t.ok(exists(select 1 from jsonb_array_elements(public.koki_foot_public('accueil')->'direct') x where x->>'id'=:'ms'),'interrompu : reste affiché en direct');
:E
select t.adm('score',jsonb_build_object('id',:'ms','revision',t.rev(:'ms'),'statut','Suspendu'));
reset role;
select t.ok((select statut='Suspendu' and minute is null and score_domicile=1 from koki_foot.matchs where id=:'ms'),'suspendu : score conservé, minute effacée');
select t.ok(exists(select 1 from jsonb_array_elements(public.koki_foot_public('accueil')->'resultats') x where x->>'id'=:'ms' and x->>'statut'='Suspendu'),'suspendu : affiché avec son statut');
select t.ok((select (r->>'joues')::int from jsonb_array_elements(koki_foot.classement(:'comp','')) r where r->'equipe'->>'id'=:'eq3')=0,'suspendu : hors classement');
:E
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'comp','domicile_id',:'eq2','exterieur_id',:'eq1','date_match',(now()+interval '1 hour')::text,'publie',true))->>'id' as mr \gset
select t.adm('score',jsonb_build_object('id',:'mr','revision',t.rev(:'mr'),'statut','Reporté'));
select t.adm('enregistrer_match',jsonb_build_object('id',:'mr','revision',t.rev(:'mr'),'date_match',(now()+interval '3 days')::text));
reset role;
select t.ok((select statut='Reporté' and date_match>now()+interval '2 days' from koki_foot.matchs where id=:'mr'),'reporté : nouvelle date enregistrée');
select t.ok(exists(select 1 from jsonb_array_elements(public.koki_foot_public('accueil')->'a_venir') x where x->>'id'=:'mr' and x->>'statut'='Reporté'),'reporté : listé à venir');

-- ═════ 10. Forfaits et matchs rejoués ═════
:E
select t.err(format($$select t.adm('forfait','{"id":"%s","revision":%s,"equipe_id":"%s","score_domicile":3,"score_exterieur":0,"motif":"Absence"}')$$,:'ms',t.rev(:'ms'),:'eq2'),'une des deux équipes','forfait : équipe étrangère refusée');
select t.err(format($$select t.adm('forfait','{"id":"%s","revision":%s,"equipe_id":"%s","score_domicile":3,"score_exterieur":0}')$$,:'ms',t.rev(:'ms'),:'eq1'),'Motif','forfait sans motif refusé');
reset role; select koki_foot.classement(:'comp','') as cl_avant \gset
:E
select t.adm('forfait',jsonb_build_object('id',:'ms','revision',t.rev(:'ms'),'equipe_id',:'eq1','score_domicile',3,'score_exterieur',0,'motif','Équipe absente à l''heure'));
reset role;
select t.ok((select statut='Terminé' and forfait_equipe_id=:'eq1' and (score_domicile,score_exterieur)=(3,0) from koki_foot.matchs where id=:'ms'),'forfait : terminé 3–0, équipe forfait notée');
select t.ok((select (r->>'points')::int from jsonb_array_elements(koki_foot.classement(:'comp','')) r where r->'equipe'->>'id'=:'eq3')=3,'classement après forfait : 3 points au vainqueur');
select t.ok((select action='forfait' from koki_foot.corrections where match_id=:'ms' order by id desc limit 1),'forfait journalisé');
:E
select t.adm('score',jsonb_build_object('id',:'ms','revision',t.rev(:'ms'),'statut','Suspendu','motif','Forfait annulé par la commission'));
reset role;
select t.ok((select forfait_equipe_id is null from koki_foot.matchs where id=:'ms'),'forfait levé quand le match quitte « Terminé »');
:E
select t.adm('rejouer',jsonb_build_object('id',:'ms','revision',t.rev(:'ms'),'date_match',(now()+interval '5 days')::text,'motif','Décision de la commission : match à rejouer'))->'nouveau'->>'id' as mrj \gset
reset role;
select t.ok((select statut='Annulé' from koki_foot.matchs where id=:'ms') and (select rejoue_de=:'ms' and statut='À venir' from koki_foot.matchs where id=:'mrj'),'match rejoué : original annulé, nouveau lié');
select t.ok((select (r->>'joues')::int from jsonb_array_elements(koki_foot.classement(:'comp','')) r where r->'equipe'->>'id'=:'eq3')=0,'classement : match annulé exclu');
:E
select t.err(format($$select t.adm('rejouer','{"id":"%s","revision":%s,"date_match":"2026-12-20T16:00:00Z","motif":"encore"}')$$,:'ms',t.rev(:'ms')),'déjà été reprogrammé','match déjà reprogrammé : refus');

-- ═════ 11. Correction d'un but et cohérence du classement ═════
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'comp','domicile_id',:'eq2','exterieur_id',:'eq3','date_match',(now()-interval '3 hours')::text,'publie',true))->>'id' as mc \gset
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'mc','revision',t.rev(:'mc'),'type','but','periode','mi_temps_1','minute',10,'equipe_id',:'eq2','joueur','A'))->'evenement'->>'id' as but1 \gset
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'mc','revision',t.rev(:'mc'),'type','but','periode','mi_temps_1','minute',20,'equipe_id',:'eq2','joueur','B'));
select t.adm('score',jsonb_build_object('id',:'mc','revision',t.rev(:'mc'),'statut','Terminé'));
reset role;
select (r->>'points')::int as pts_eq2_avant from jsonb_array_elements(koki_foot.classement(:'comp','')) r where r->'equipe'->>'id'=:'eq2' \gset
:E
select t.err(format($$select t.adm('retirer_evenement','{"id":"%s"}')$$,:'but1'),'Motif','retrait d''un but sans motif refusé');
select t.adm('retirer_evenement',jsonb_build_object('id',:'but1','motif','Hors-jeu signalé par l''arbitre'));
reset role;
select t.ok((select (score_domicile,score_exterieur)=(1,0) from koki_foot.matchs where id=:'mc'),'correction d''un but : score 2–0 → 1–0');
select t.ok(((select koki_foot.coherence(m) from koki_foot.matchs m where id=:'mc')->>'etat')='coherent','cohérence conservée après correction');
select t.ok((select count(*) from koki_foot.corrections where match_id=:'mc' and action='evenement_retrait' and motif ~ 'Hors-jeu')=1,'annulation journalisée avec motif');
:E
select t.adm('score',jsonb_build_object('id',:'mc','revision',t.rev(:'mc'),'statut','Terminé','score_domicile',1,'score_exterieur',2,'motif','Feuille de match officielle'));
reset role;
select t.ok((select (r->>'points')::int from jsonb_array_elements(koki_foot.classement(:'comp','')) r where r->'equipe'->>'id'=:'eq2')=:pts_eq2_avant-3,'classement recalculé après correction (victoire → défaite)');
select t.ok(((select koki_foot.coherence(m) from koki_foot.matchs m where id=:'mc')->>'etat')='incoherent','score corrigé sans événements : incohérence signalée');

-- ═════ 12. Verrous indépendants, conflits visibles, annulation d'un événement api ═════
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"v12","matchs":[{"ref":"F300","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T3","date_match":"2026-11-24T18:00:00Z","statut":"En direct","minute":30,"score_domicile":1,"score_exterieur":0}],"evenements":[{"match_ref":"F300","cle":"F300|but|25|T1|Diouf","type":"but","periode":"mi_temps_1","minute":25,"equipe_ref":"T1","joueur":"Diouf"}]}');
reset role;
select id as f300 from koki_foot.matchs where ref_fournisseur='F300' \gset
:E
select t.adm('retirer_evenement',jsonb_build_object('id',t.evt(:'f300'),'motif','But refusé par la VAR, fournisseur en retard'));
reset role;
select t.ok((select verrou_evenements and verrou_score and verrou_manuel and not verrou_statut and resultat_source='correction' and score_domicile=0 from koki_foot.matchs where id=:'f300'),'annulation d''un but api : verrous événements + score, score 0–0');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"v12b","matchs":[{"ref":"F300","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T3","date_match":"2026-11-24T18:00:00Z","statut":"En direct","minute":35,"score_domicile":1,"score_exterieur":0}],"evenements":[{"match_ref":"F300","cle":"F300|but|25|T1|Diouf","type":"but","periode":"mi_temps_1","minute":25,"equipe_ref":"T1","joueur":"Diouf"}]}') as r12 \gset
reset role;
select t.ok((select count(*) from koki_foot.evenements where match_id=:'f300')=0,'but annulé : non réintroduit par la synchronisation');
select t.ok((select score_domicile=0 from koki_foot.matchs where id=:'f300'),'score corrigé conservé');
select t.ok((select count(*) from koki_foot.conflits where match_id=:'f300' and champ='score' and not resolu and valeur_api->>0='1')=1,'divergence de score inscrite en conflit (jamais silencieuse)');
select t.ok((select count(*) from koki_foot.conflits where match_id=:'f300' and champ='evenements')=0,'événement retiré volontairement : pas de faux conflit');
select t.ok((:'r12'::jsonb->>'ignores_verrou')::int=1,'synchronisation : divergence comptée');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"v12c","matchs":[{"ref":"F300","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T3","date_match":"2026-11-24T18:00:00Z","statut":"Mi-temps","score_domicile":1,"score_exterieur":0}]}');
reset role;
select t.ok((select count(*)=1 and max(occurrences)=2 from koki_foot.conflits where match_id=:'f300' and champ='score'),'conflit répété : une seule ligne, occurrences comptées');
-- Global encore posé : le statut ne bouge pas tant que verrou_manuel est actif.
select t.ok((select statut='En direct' from koki_foot.matchs where id=:'f300'),'verrou global (lancement) : statut protégé aussi');
:E
select t.err(format($$select t.adm('deverrouiller','{"id":"%s","revision":%s,"verrous":"evenements","motif":"test"}')$$,:'f300',t.rev(:'f300')),'liste non vide','déverrouillage : format invalide refusé (pas de levée totale silencieuse)');
select t.adm('deverrouiller',jsonb_build_object('id',:'f300','revision',t.rev(:'f300'),'verrous','["evenements"]'::jsonb,'motif','Fournisseur à jour pour les événements'));
reset role;
select t.ok((select verrou_manuel and verrou_score and not verrou_evenements from koki_foot.matchs where id=:'f300'),'déverrouillage partiel : global maintenu tant qu''un verrou de champ reste');
select id as conflit_score from koki_foot.conflits where match_id=:'f300' and champ='score' and not resolu \gset
:E
select t.err(format($$select t.adm('resoudre_conflit','{"id":%s,"decision":"accepter_api"}')$$,:'conflit_score'),'Motif','résolution de conflit sans motif refusée');
select t.adm('resoudre_conflit',jsonb_build_object('id',:'conflit_score','decision','accepter_api','motif','Le fournisseur a raison finalement'));
reset role;
select t.ok((select not verrou_manuel and not verrou_score from koki_foot.matchs where id=:'f300'),'conflit accepté : verrous levés');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"v12d","matchs":[{"ref":"F300","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T3","date_match":"2026-11-24T18:00:00Z","statut":"Mi-temps","score_domicile":1,"score_exterieur":0}]}');
reset role;
select t.ok((select statut='Mi-temps' and score_domicile=1 from koki_foot.matchs where id=:'f300'),'après résolution : valeurs du fournisseur appliquées');
select t.ok((select count(*) from koki_foot.corrections where match_id=:'f300' and action='conflit_api')=1,'décision de conflit journalisée');
-- Verrou de programmation : date corrigée par l'administrateur, conservée face à l'API.
:E
select t.err(format($$select t.adm('enregistrer_match','{"id":"%s","revision":%s,"date_match":"2026-11-24T19:00:00Z"}')$$,:'f300',t.rev(:'f300')),'Motif','programmation api : motif requis');
select t.err(format($$select t.adm('enregistrer_match','{"id":"%s","revision":%s,"domicile_id":"%s"}')$$,:'f300',t.rev(:'f300'),:'eq1'),'suivent le fournisseur','match api : équipes non modifiables');
select t.adm('enregistrer_match',jsonb_build_object('id',:'f300','revision',t.rev(:'f300'),'date_match','2026-11-24T19:00:00Z','lieu','Stade Alassane Djigo','motif','Horaire confirmé par la ligue'));
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"v12e","matchs":[{"ref":"F300","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T3","date_match":"2026-11-24T18:00:00Z","statut":"Terminé","score_domicile":2,"score_exterieur":0}]}');
reset role;
select t.ok((select date_match='2026-11-24T19:00:00Z'::timestamptz and lieu='Stade Alassane Djigo' and verrou_programmation and not verrou_score from koki_foot.matchs where id=:'f300'),'verrou de programmation : date et lieu corrigés conservés');
select t.ok((select count(*) from koki_foot.conflits where match_id=:'f300' and champ='programmation' and not resolu)=1,'divergence de programmation signalée');

-- ═════ 13. API indisponible et quota dépassé ═════
set role service_role; select t.as_service();
select t.sync('erreur','{"fournisseur":"sportmonks","operation":"fixtures","code":"indisponible","message":"HTTP 503"}') as e1 \gset
select t.sync('erreur','{"fournisseur":"sportmonks","operation":"fixtures","code":"indisponible","message":"HTTP 503"}') as e2 \gset
select t.ok((:'e1'::jsonb->>'pause_jusqu_a')::timestamptz between now()+interval '55 seconds' and now()+interval '65 seconds','panne 1 : pause d''une minute');
select t.ok((:'e2'::jsonb->>'pause_jusqu_a')::timestamptz between now()+interval '115 seconds' and now()+interval '125 seconds' and (:'e2'::jsonb->>'erreurs_consecutives')::int=2,'panne 2 : pause doublée (2 min)');
select t.ok((t.sync('references','{"fournisseur":"sportmonks"}')->>'pause_jusqu_a') is not null,'références : la synchronisation sait qu''elle doit attendre');
select t.sync('erreur','{"fournisseur":"sportmonks","operation":"fixtures","code":"quota","message":"Limite quotidienne atteinte"}') as e3 \gset
select t.ok((:'e3'::jsonb->>'pause_jusqu_a')::timestamptz=(date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC','quota dépassé : pause jusqu''à minuit UTC');
select t.sync('erreur','{"fournisseur":"sportmonks","operation":"fixtures","code":"quota","reessayer_apres":"2026-12-31T00:00:00Z"}') as e4 \gset
select t.ok((:'e4'::jsonb->>'pause_jusqu_a')::timestamptz='2026-12-31T00:00:00Z','délai indiqué par le fournisseur respecté (Retry-After)');
select t.err($$select t.sync('erreur','{"fournisseur":"sportmonks","code":"pirate"}')$$,'Code','code d''erreur inconnu refusé');
select t.sync('importer','{"fournisseur":"sportmonks","operation":"reprise","quota_restant":2950}');
reset role;
select t.ok((select erreurs_consecutives=0 and pause_jusqu_a is null and quota_restant=2950 and derniere_reussite is not null and derniere_erreur_code='quota' from koki_foot.etat_fournisseurs where fournisseur='sportmonks'),'reprise : compteur remis à zéro, quota restant noté, dernière erreur conservée');
select t.ok((select count(*) from koki_foot.synchronisations where fournisseur='sportmonks' and statut='erreur' and code in ('indisponible','quota'))=4,'journal des erreurs API (codes)');

-- ═════ 14. Fraîcheur des données ═════
select t.ok((select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where id=:'mc')='manuel','fraîcheur : match manuel');
select t.ok((select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where id=:'f300')='a_jour','fraîcheur : match api synchronisé');
update koki_foot.matchs set statut='En direct', minute=50, score_domicile=0, score_exterieur=0, synchronise_le=now()-interval '10 minutes' where ref_fournisseur='F202';
update koki_foot.vus_api set vu_le=now()-interval '10 minutes' where match_id=(select id from koki_foot.matchs where ref_fournisseur='F202');
select revision as rev202 from koki_foot.matchs where ref_fournisseur='F202' \gset
select t.ok((select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where ref_fournisseur='F202')='ancien','fraîcheur : match en jeu sans nouvelles depuis 10 min = ancien');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"frais","matchs":[{"ref":"F202","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T3","date_match":"2026-12-02T18:00:00Z","statut":"En direct","minute":50,"score_domicile":0,"score_exterieur":0}]}');
reset role;
select t.ok((select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where ref_fournisseur='F202')='a_jour','fraîcheur : passage de la synchronisation sans changement = à jour');
select t.ok((select revision from koki_foot.matchs where ref_fournisseur='F202')=:rev202,'passage sans changement : aucune nouvelle révision ni ligne d''audit');
select t.ok((select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where id=:'f100')='corrige' or (select resultat_source from koki_foot.matchs where id=:'f100')='api','fraîcheur : source du résultat exposée');

-- ═════ 15. SECURITY DEFINER et privilèges ═════
select t.ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='koki_foot' or p.proname like 'koki_foot%') and p.prosecdef
 and not coalesce(p.proconfig,'{}')@>array['search_path=""']),'SECURITY DEFINER : search_path vide partout');
select t.ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_foot'
 and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('service_role',p.oid,'execute'))),'fonctions internes koki_foot : aucune exécutable par anon, authenticated ou service_role');
select t.ok(has_function_privilege('anon','public.koki_foot_public(text,jsonb)','execute') and not has_function_privilege('anon','public.koki_foot_admin(text,jsonb)','execute')
 and not has_function_privilege('anon','public.koki_foot_sync(text,jsonb)','execute') and not has_function_privilege('authenticated','public.koki_foot_sync(text,jsonb)','execute')
 and not has_function_privilege('service_role','public.koki_foot_admin(text,jsonb)','execute') and has_function_privilege('service_role','public.koki_foot_sync(text,jsonb)','execute'),'points d''entrée : droits exacts par rôle');
select t.ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='koki_foot' and c.relkind='r'
 and (has_table_privilege('service_role',c.oid,'select,insert,update,delete,truncate') or has_table_privilege('anon',c.oid,'select') or has_table_privilege('authenticated',c.oid,'select'))),'tables koki_foot : aucun privilège direct, même service_role');
select t.ok(not has_schema_privilege('service_role','koki_foot','usage') and not has_schema_privilege('anon','koki_foot','usage'),'schéma koki_foot : aucun usage hors propriétaire');
set role service_role; select t.as_service();
select t.err($$insert into koki_foot.matchs(competition_id) values(gen_random_uuid())$$,'permission denied','service_role : écriture directe refusée');
select t.err($$select public.koki_foot_admin('etat','{}')$$,'permission denied','service_role : administration refusée');
set role authenticated; select t.as_user(:'super','aal2');
select t.err($$select public.koki_foot_sync('importer','{"fournisseur":"api-football"}')$$,'permission denied','superadmin : ne peut pas se faire passer pour la synchronisation');
reset role;
-- Journal des corrections : résistance.
select t.err($$truncate koki_foot.corrections$$,'vidage interdit','journal : TRUNCATE refusé (même propriétaire)');
select t.err($$update koki_foot.corrections set acteur=null$$,'ajout seul','journal : effacement de l''auteur refusé');
select t.ok((select count(*) from koki_foot.corrections)>20,'journal intact');

-- ═════ 16. Realtime : révisions croissantes, charge sans donnée personnelle ═════
select t.ok(not exists(select 1 from (select charge->>'id' id, (charge->>'revision')::int r, lag((charge->>'revision')::int) over (partition by charge->>'id' order by n) p from t.diffusions where evenement='match') z where p is not null and r<=p),'Realtime : révisions strictement croissantes par match');
select t.ok(not exists(select 1 from t.diffusions where charge::text ~* 'joueur|email|auteur|acteur|motif|commentaire'),'Realtime : aucune donnée personnelle ni motif diffusés');
select t.ok(not exists(select 1 from t.diffusions where prive or topic<>'koki-foot'),'Realtime : canal public unique koki-foot');
select t.ok((select count(*) from t.diffusions where evenement='evenement' and charge ? 'revision')=(select count(*) from t.diffusions where evenement='evenement'),'Realtime : événements porteurs de la révision du match');

-- ════════════════ TESTS v3 (revue phase 2) ════════════════
reset role;
-- ═════ 17. Périodes explicites ═════
:E
select t.adm('enregistrer_competition','{"nom":"Coupe des quartiers","type":"Coupe","portee":"Koki","publie":true}')->>'id' as cq \gset
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'cq','domicile_id',:'eq1','exterieur_id',:'eq2','date_match',(now()-interval '150 minutes')::text,'publie',true))->>'id' as pm \gset
select t.adm('score',jsonb_build_object('id',:'pm','revision',t.rev(:'pm'),'statut','En direct','minute',1));
select t.err(format($$select t.adm('ajouter_evenement','{"match_id":"%s","revision":%s,"type":"but","minute":10,"equipe_id":"%s"}')$$,:'pm',t.rev(:'pm'),:'eq1'),'Période requise','événement sans période refusé');
-- 90+5 en 2e mi-temps saisi « 95 » : réglementaire (l'ancienne règle minute>90 l'aurait compté en prolongation).
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'pm','revision',t.rev(:'pm'),'type','but','periode','mi_temps_2','minute',95,'equipe_id',:'eq1','joueur','Diop'));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'pm','revision',t.rev(:'pm'),'type','but','periode','mi_temps_2','minute',90,'minute_add',4,'equipe_id',:'eq2','joueur','Kane'));
reset role;
select t.ok((select (score_domicile,score_exterieur)=(1,1) and pro_domicile is null from koki_foot.matchs where id=:'pm'),'période explicite : but à « 95 » en 2e mi-temps = score réglementaire');
select t.ok((select minute=90 and minute_add=4 from koki_foot.evenements where match_id=:'pm' and joueur='Kane'),'minute affichée et temps additionnel conservés séparément');
:E
select t.adm('score',jsonb_build_object('id',:'pm','revision',t.rev(:'pm'),'statut','Prolongations','minute',91));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'pm','revision',t.rev(:'pm'),'type','but','periode','prolongation_1','minute',91,'equipe_id',:'eq2','joueur','Gueye'));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'pm','revision',t.rev(:'pm'),'type','penalty','periode','prolongation_2','minute',120,'minute_add',2,'equipe_id',:'eq1','joueur','Diop'));
reset role;
select t.ok((select (score_domicile,score_exterieur,pro_domicile,pro_exterieur)=(1,1,1,1) from koki_foot.matchs where id=:'pm'),'prolongations 1 et 2 : buts dans pro_*');
-- Tirs au but : séance distincte, jamais comptée dans le score du match.
:E
select t.err(format($$select t.adm('ajouter_evenement','{"match_id":"%s","revision":%s,"type":"but","periode":"tirs_au_but","equipe_id":"%s"}')$$,:'pm',t.rev(:'pm'),:'eq1'),'check','un « but » pendant la séance de tirs au but est refusé');
select t.err(format($$select t.adm('ajouter_evenement','{"match_id":"%s","revision":%s,"type":"tab_reussi","periode":"prolongation_2","equipe_id":"%s"}')$$,:'pm',t.rev(:'pm'),:'eq1'),'check','tir au but hors séance refusé');
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'pm','revision',t.rev(:'pm'),'type','tab_reussi','periode','tirs_au_but','equipe_id',:'eq1','joueur','Diop'));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'pm','revision',t.rev(:'pm'),'type','tab_manque','periode','tirs_au_but','equipe_id',:'eq2','joueur','Kane'));
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'pm','revision',t.rev(:'pm'),'type','tab_reussi','periode','tirs_au_but','equipe_id',:'eq1','joueur','Fall'));
reset role;
select t.ok((select statut='Tirs au but' and (tab_domicile,tab_exterieur)=(2,0) and (score_domicile,score_exterieur,pro_domicile,pro_exterieur)=(1,1,1,1) from koki_foot.matchs where id=:'pm'),'tirs au but : 2–0 en séance, score du match inchangé (1–1, a.p. 1–1)');
select t.ok(((select koki_foot.coherence(m) from koki_foot.matchs m where id=:'pm')->>'etat')='coherent','cohérence par période (réglementaire, prolongation, séance)');
select t.ok(((select koki_foot.coherence(m) from koki_foot.matchs m where id=:'pm')->'buts_evenements'->'tirs_au_but')='[2,0]'::jsonb,'cohérence : tirs au but comptés à part');
select t.ok((select array_agg(e->>'periode') from jsonb_array_elements(public.koki_foot_public('match',jsonb_build_object('id',:'pm'))->'evenements') e)
 =array['mi_temps_2','mi_temps_2','prolongation_1','prolongation_2','tirs_au_but','tirs_au_but','tirs_au_but'],'événements ordonnés par période puis minute');
select id as tab_fall from koki_foot.evenements where match_id=:'pm' and joueur='Fall' and periode='tirs_au_but' \gset
:E
select t.adm('retirer_evenement',jsonb_build_object('id',:'tab_fall','motif','Tir à retirer : gardien avancé, à retirer'));
reset role;
select t.ok((select (tab_domicile,tab_exterieur)=(1,0) from koki_foot.matchs where id=:'pm'),'annulation d''un tir au but : séance 1–0, score du match intact');
:E
select t.err(format($$select t.adm('ajouter_evenement','{"match_id":"%s","revision":%s,"type":"but","periode":"prolongation_1","minute":95,"equipe_id":"%s"}')$$,:'m2',t.rev(:'m2'),:'eq2'),'championnat','championnat : événement de prolongation refusé');
reset role;

-- ═════ 18. VAR et tirs au but venant du fournisseur ═════
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"var","competitions":[{"ref":"CUPSN","nom":"Coupe du Sénégal","type":"Coupe","portee":"Sénégal"}],"matchs":[{"ref":"F400","competition_ref":"CUPSN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T15:00:00Z","statut":"En direct","minute":30,"score_domicile":1,"score_exterieur":0}],"evenements":[{"match_ref":"F400","cle":"F400|but|28","type":"but","periode":"mi_temps_1","minute":28,"equipe_ref":"T1","joueur":"Diallo"}]}');
-- VAR : le fournisseur retire le but et corrige le score.
select t.sync('importer','{"fournisseur":"api-football","operation":"var2","matchs":[{"ref":"F400","competition_ref":"CUPSN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T15:00:00Z","statut":"En direct","minute":33,"score_domicile":0,"score_exterieur":0}],"evenements":[],"evenements_complets":["F400"]}');
reset role;
select t.ok((select score_domicile=0 from koki_foot.matchs where ref_fournisseur='F400') and (select count(*) from koki_foot.evenements e join koki_foot.matchs m on m.id=e.match_id where m.ref_fournisseur='F400')=0,'VAR fournisseur : but retiré et score corrigé');
select t.ok(((select koki_foot.coherence(m) from koki_foot.matchs m where ref_fournisseur='F400')->>'etat')='aucun_evenement','VAR : plus d''événement de but');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"tab","matchs":[{"ref":"F400","competition_ref":"CUPSN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T15:00:00Z","statut":"Terminé","score_domicile":0,"score_exterieur":0,"pro_domicile":0,"pro_exterieur":0,"tab_domicile":4,"tab_exterieur":2}],"evenements":[{"match_ref":"F400","cle":"F400|tab|1","type":"tab_reussi","periode":"tirs_au_but","equipe_ref":"T1"},{"match_ref":"F400","cle":"F400|tab|2","type":"tab_manque","periode":"tirs_au_but","equipe_ref":"T2"},{"match_ref":"F400","cle":"F400|tab|x","type":"but","periode":"tirs_au_but","equipe_ref":"T2"},{"match_ref":"F400","cle":"F400|sansperiode","type":"but","minute":5,"equipe_ref":"T2"}]}') as rt \gset
reset role;
select t.ok((select (tab_domicile,tab_exterieur,score_domicile)=(4,2,0) from koki_foot.matchs where ref_fournisseur='F400'),'tirs au but du fournisseur : séance 4–2, score du match 0–0');
select t.ok((:'rt'::jsonb->>'rejetes')::int=2,'événements du fournisseur incohérents (but en séance, sans période) rejetés');

-- ═════ 19. Conflits multiples, deux verrous simultanés, résolution sélective ═════
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"multi","matchs":[{"ref":"F500","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T1","date_match":"2026-12-10T16:00:00Z","lieu":"Stade A","statut":"En direct","minute":10,"score_domicile":0,"score_exterieur":0}]}');
reset role; select id as f500 from koki_foot.matchs where ref_fournisseur='F500' \gset
:E
select t.adm('score',jsonb_build_object('id',:'f500','revision',t.rev(:'f500'),'statut','En direct','minute',12,'score_domicile',1,'score_exterieur',0,'motif','But vu au stade'));
select t.adm('enregistrer_match',jsonb_build_object('id',:'f500','revision',t.rev(:'f500'),'date_match','2026-12-10T17:00:00Z','motif','Coup d''envoi décalé par la ligue'));
reset role;
select t.ok((select verrou_score and verrou_programmation and not verrou_statut and not verrou_evenements and verrou_manuel from koki_foot.matchs where id=:'f500'),'deux verrous actifs simultanément (score + programmation)');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"multi2","matchs":[{"ref":"F500","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T1","date_match":"2026-12-10T16:30:00Z","lieu":"Stade B","statut":"Mi-temps","score_domicile":0,"score_exterieur":0}]}');
reset role;
select t.ok((select count(*) from koki_foot.conflits where match_id=:'f500' and not resolu)=3,'conflits multiples : score, statut (verrou global) et programmation');
select t.ok((select score_domicile=1 and date_match='2026-12-10T17:00:00Z' and lieu='Stade A' and statut='En direct' from koki_foot.matchs where id=:'f500'),'valeurs locales conservées');
select t.ok((select api_date_match='2026-12-10T16:30:00Z' and api_lieu='Stade B' from koki_foot.matchs where id=:'f500'),'valeur du fournisseur conservée à part (api_date_match, api_lieu)');
select id as k_score from koki_foot.conflits where match_id=:'f500' and champ='score' and not resolu \gset
select id as k_prog from koki_foot.conflits where match_id=:'f500' and champ='programmation' and not resolu \gset
:E
select t.adm('resoudre_conflit',jsonb_build_object('id',:k_score,'decision','accepter_api','motif','Le fournisseur a raison'));
reset role;
select t.ok((select not verrou_score and verrou_programmation and verrou_manuel from koki_foot.matchs where id=:'f500'),'résoudre un conflit ne retire pas les autres verrous');
select t.ok((select not resolu from koki_foot.conflits where id=:k_prog),'les autres conflits restent ouverts');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"multi3","matchs":[{"ref":"F500","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T1","date_match":"2026-12-10T16:30:00Z","lieu":"Stade B","statut":"Mi-temps","score_domicile":0,"score_exterieur":0}]}');
reset role;
select t.ok((select score_domicile=1 and date_match='2026-12-10T17:00:00Z' from koki_foot.matchs where id=:'f500'),'verrou global encore actif : le score reste protégé tant qu''un autre verrou existe');
:E
select t.adm('resoudre_conflit',jsonb_build_object('id',:k_prog,'decision','garder','motif','Horaire officiel de la ligue'));
select t.adm('deverrouiller',jsonb_build_object('id',:'f500','revision',t.rev(:'f500'),'verrous','["statut"]'::jsonb,'motif','Statut au fournisseur'));
reset role;
select t.ok((select verrou_manuel and verrou_programmation and not verrou_statut from koki_foot.matchs where id=:'f500'),'« garder » : verrou de programmation maintenu');
:E
select t.adm('deverrouiller',jsonb_build_object('id',:'f500','revision',t.rev(:'f500'),'verrous','["score"]'::jsonb,'motif','Rien à garder sur le score'));
reset role;
select t.ok((select verrou_manuel and verrou_programmation from koki_foot.matchs where id=:'f500'),'verrou global maintenu tant que la programmation est verrouillée');

-- ═════ 20. Programmation : historique et changements d'horaire ═════
select t.ok((select array_agg(origine order by id) from koki_foot.historique_programmation where match_id=:'f500')=array['api','manuel','api'],'historique : valeur fournisseur, correction manuelle, nouvelle valeur fournisseur');
select t.ok((select motif ~ 'décalé' and acteur=:'editeur' from koki_foot.historique_programmation where match_id=:'f500' and origine='manuel'),'historique : motif et auteur de la correction');
select t.ok((select count(*)=1 and min(origine)='manuel' and min(nouvelle)='2026-12-10T17:00:00Z' from koki_foot.changements_horaire where match_id=:'f500'),'changement d''horaire manuel inscrit une fois (fournisseur ignoré : verrouillé)');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"horaire","matchs":[{"ref":"F202","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T3","date_match":"2026-12-02T19:00:00Z","statut":"À venir"}]}');
select t.sync('importer','{"fournisseur":"api-football","operation":"horaire-bis","matchs":[{"ref":"F202","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T3","date_match":"2026-12-02T19:00:00Z","statut":"À venir"}]}');
reset role;
select t.ok((select count(*)=1 and min(origine)='api' from koki_foot.changements_horaire c join koki_foot.matchs m on m.id=c.match_id where m.ref_fournisseur='F202' and c.nouvelle='2026-12-02T19:00:00Z'),'changement d''horaire du fournisseur inscrit une seule fois (import répété)');
:E
select t.adm('enregistrer_match',jsonb_build_object('id',:'m2','revision',t.rev(:'m2'),'publie',false));
select t.adm('enregistrer_match',jsonb_build_object('id',:'m2','revision',t.rev(:'m2'),'date_match',(now()+interval '9 days')::text));
reset role;
select t.ok(not exists(select 1 from koki_foot.changements_horaire where match_id=:'m2'),'match non publié : pas de changement d''horaire à notifier');
:E
select t.ok((t.adm('programmation',jsonb_build_object('match_id',:'f500'))->'fournisseur'->>'lieu')='Stade B','administration : valeur publiée et valeur du fournisseur consultables');
reset role;

-- ═════ 21. Fraîcheur configurable et état des sources ═════
:E
select t.err($$select t.adm('regler_source','{"fournisseur":"api-football","seuil_ancien_s":600}')$$,'double authentification','éditeur : réglage des seuils refusé');
set role authenticated; select t.as_user(:'super','aal2');
select t.err($$select t.adm('regler_source','{"fournisseur":"api-football","seuil_ancien_s":30}')$$,'check','seuil hors bornes refusé');
reset role;
update koki_foot.vus_api set vu_le=now()-interval '8 minutes' where match_id=(select id from koki_foot.matchs where ref_fournisseur='F202');
update koki_foot.matchs set statut='En direct', minute=60, score_domicile=0, score_exterieur=0 where ref_fournisseur='F202';
select t.ok((select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where ref_fournisseur='F202')='ancien','seuil 5 min : vu il y a 8 min = ancien');
set role authenticated; select t.as_user(:'super','aal2');
select t.adm('regler_source','{"fournisseur":"api-football","seuil_ancien_s":600}');
reset role;
select t.ok((select koki_foot.fraicheur(m)->>'etat' from koki_foot.matchs m where ref_fournisseur='F202')='a_jour','seuil réglé à 10 min : vu il y a 8 min = à jour');
select t.ok((select koki_foot.fraicheur(m) ?& array['derniere_actualisation','derniere_modification','etat_source','source'] from koki_foot.matchs m where ref_fournisseur='F202'),'fraîcheur : dernière actualisation, dernière modification, état de la source');
-- Ligne rejetée : pas d'actualisation.
select vu_le as vu_avant from koki_foot.vus_api where match_id=(select id from koki_foot.matchs where ref_fournisseur='F202') \gset
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"rejet","matchs":[{"ref":"F202","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T3","date_match":"2026-12-02T19:00:00Z","statut":"Terminé"}]}') as rj \gset
reset role;
select t.ok((:'rj'::jsonb->>'statut')='erreur','réponse inexploitable : synchronisation en erreur');
select t.ok((select vu_le=:'vu_avant'::timestamptz from koki_foot.vus_api where match_id=(select id from koki_foot.matchs where ref_fournisseur='F202')),'ligne rejetée : vus_api non actualisé');
select t.ok((select derniere_tentative>derniere_reussite and derniere_erreur_code='donnees' from koki_foot.etat_fournisseurs where fournisseur='api-football'),'tentative notée, réussite non');
select t.ok((select koki_foot.etat_source(f) from koki_foot.etat_fournisseurs f where fournisseur='api-football')='degrade','état de la source : dégradé');
-- Réponse exploitable sans changement : actualisation oui, modification non.
select modifie_le as mod_avant from koki_foot.vus_api where match_id=(select id from koki_foot.matchs where ref_fournisseur='F202') \gset
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"stable","matchs":[{"ref":"F202","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T3","date_match":"2026-12-02T19:00:00Z","statut":"En direct","minute":60,"score_domicile":0,"score_exterieur":0}]}');
reset role;
select t.ok((select vu_le>:'vu_avant'::timestamptz and modifie_le is not distinct from :'mod_avant'::timestamptz from koki_foot.vus_api where match_id=(select id from koki_foot.matchs where ref_fournisseur='F202')),'réponse sans changement : actualisée, non modifiée');
select t.ok((select koki_foot.etat_source(f) from koki_foot.etat_fournisseurs f where fournisseur='api-football')='ok','état de la source : ok après réussite');
update koki_foot.etat_fournisseurs set derniere_reussite=now()-interval '2 hours', derniere_tentative=now()-interval '1 minute' where fournisseur='api-football';
select t.ok((select koki_foot.etat_source(f) from koki_foot.etat_fournisseurs f where fournisseur='api-football')='hors_service','état de la source : hors service (aucune réussite depuis 3 seuils)');
select t.ok(coalesce((select bool_and(e ?& array['fournisseur','derniere_actualisation','etat'] and (select count(*) from jsonb_object_keys(e))=3) from jsonb_array_elements(public.koki_foot_public('sources')) e),false),'sources publiques : 3 champs, aucun secret ni compteur interne');

-- ═════ 22. Fuseaux horaires ═════
:E
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'comp','domicile_id',:'eq1','exterieur_id',:'eq3','date_match','2026-12-05T18:00:00+01:00','publie',true))->>'id' as tz \gset
reset role;
select t.ok((select date_match='2026-12-05T17:00:00Z' from koki_foot.matchs where id=:'tz'),'heure saisie avec décalage (+01:00) convertie en UTC');
select t.ok((select to_char(date_match at time zone 'Africa/Dakar','HH24:MI') from koki_foot.matchs where id=:'tz')='17:00','heure de Koki (Africa/Dakar = UTC) : 17:00');
select t.ok((public.koki_foot_public('matchs',jsonb_build_object('competition_id',:'comp'))->-1->>'date_match') ~ '\+00:00$|Z$','dates publiques en ISO 8601 avec fuseau');
:E
select t.err(format($$select t.adm('enregistrer_match','{"competition_id":"%s","domicile_id":"%s","exterieur_id":"%s","date_match":"demain 18h"}')$$,:'comp',:'eq1',:'eq3'),'Date invalide','date ambiguë refusée');
reset role;
set timezone='America/New_York';
select t.ok((select date_match='2026-12-05T17:00:00Z' from koki_foot.matchs where id=:'tz') and (public.koki_foot_public('matchs',jsonb_build_object('competition_id',:'comp'))::text like '%2026-12-05T17:00:00+00:00%' or (public.koki_foot_public('matchs',jsonb_build_object('competition_id',:'comp'))::text like '%2026-12-05T12:00:00-05:00%')),'fuseau de session différent : même instant');
reset timezone;

-- ═════ 23. Classements : départage et filtres ═════
:E
select t.adm('enregistrer_competition','{"nom":"Tournoi départage","type":"Championnat","publie":true}')->>'id' as cd \gset
select t.adm('enregistrer_equipe','{"nom":"Alpha"}')->>'id' as ea \gset
select t.adm('enregistrer_equipe','{"nom":"Beta"}')->>'id' as eb \gset
select t.adm('enregistrer_equipe','{"nom":"Gamma"}')->>'id' as ec \gset
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'cd','domicile_id',:'ea','exterieur_id',:'ec','date_match',(now()-interval '3 days')::text,'publie',true))->>'id' as d1 \gset
select t.adm('score',jsonb_build_object('id',:'d1','revision',t.rev(:'d1'),'statut','Terminé','score_domicile',1,'score_exterieur',0));
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'cd','domicile_id',:'eb','exterieur_id',:'ec','date_match',(now()-interval '2 days')::text,'publie',true))->>'id' as d2 \gset
select t.adm('score',jsonb_build_object('id',:'d2','revision',t.rev(:'d2'),'statut','Terminé','score_domicile',3,'score_exterieur',2));
select t.adm('enregistrer_match',jsonb_build_object('competition_id',:'cd','domicile_id',:'ea','exterieur_id',:'eb','date_match',(now()-interval '1 days')::text,'publie',false))->>'id' as d3 \gset
select t.adm('score',jsonb_build_object('id',:'d3','revision',t.rev(:'d3'),'statut','Terminé','score_domicile',5,'score_exterieur',0));
reset role;
select t.ok((select array_agg(r->'equipe'->>'nom' order by (r->>'rang')::int) from jsonb_array_elements(koki_foot.classement(:'cd','')) r)=array['Beta','Alpha','Gamma'],'départage : points égaux, différence égale, buts marqués (Beta 3 > Alpha 1)');
select t.ok((select (r->>'joues')::int from jsonb_array_elements(koki_foot.classement(:'cd','')) r where r->'equipe'->>'nom'='Alpha')=1,'match non publié exclu du classement');

-- ═════ 24. Sécurité : recontrôle ═════
select t.ok(not exists(select 1 from pg_policies where schemaname='koki_foot') and not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='koki_foot' and c.relkind='r' and not c.relrowsecurity),'RLS active partout, aucune politique (refus par défaut)');
select t.ok((select bool_and(p.prosecdef) from pg_proc p where p.oid in ('public.koki_foot_public(text,jsonb)'::regprocedure,'public.koki_foot_admin(text,jsonb)'::regprocedure,'public.koki_foot_sync(text,jsonb)'::regprocedure)),'points d''entrée en SECURITY DEFINER');
select t.ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_foot' and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('service_role',p.oid,'execute'))),'nouvelles fonctions internes (périodes, sources, horaires, journal) non exécutables hors propriétaire');
select t.ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_foot' and p.prosecdef and not coalesce(p.proconfig,'{}')@>array['search_path=""']),'toutes les fonctions SECURITY DEFINER : search_path vide');
select t.ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'koki_foot%' and p.proname not in ('koki_foot_public','koki_foot_admin','koki_foot_sync')),'aucun autre point d''entrée public');

-- ═════ 25. Journal chaîné : intégrité et limites ═════
select t.ok(koki_foot.verifier_journal() is null,'journal intact : chaîne d''empreintes valide');
select t.ok((select count(*)=count(empreinte) from koki_foot.corrections),'chaque correction porte son empreinte');
select min(id) as cible from koki_foot.corrections where motif<>'' \gset
-- Simulation d'un propriétaire malveillant : déclencheurs désactivés, ligne modifiée.
alter table koki_foot.corrections disable trigger corrections_ajout_seul;
update koki_foot.corrections set motif='réécrit' where id=:cible;
alter table koki_foot.corrections enable trigger corrections_ajout_seul;
select t.ok(koki_foot.verifier_journal()=:cible,'altération par le propriétaire (déclencheurs contournés) détectée');
alter table koki_foot.corrections disable trigger corrections_ajout_seul;
delete from koki_foot.corrections where id=:cible+1;
alter table koki_foot.corrections enable trigger corrections_ajout_seul;
select t.ok(koki_foot.verifier_journal() is not null,'suppression d''une ligne détectée');
:E
select t.ok((t.adm('verifier_journal')->>'premiere_alteration')::bigint=:cible,'administration : vérification du journal disponible');
reset role;

-- ════════════════ PHASE 4 ════════════════
reset role;
-- ═════ 26. Verrous indépendants (mode préparé, désactivé par défaut) ═════
select t.ok(koki_foot.mode_verrous()='global','mode par défaut : global (lancement)');
:E
select t.err($$select t.adm('regler_verrous','{"mode":"independant"}')$$,'double authentification','éditeur : changement de mode refusé');
set role authenticated; select t.as_user(:'super','aal2');
select t.err($$select t.adm('regler_verrous','{"mode":"tout"}')$$,'global ou independant','mode inconnu refusé');
select t.adm('regler_verrous','{"mode":"independant"}');
reset role;
select t.ok(koki_foot.mode_verrous()='independant' and (select modifie_par=:'super' from koki_foot.reglages),'mode indépendant activé par le superadmin, tracé');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"ind","matchs":[{"ref":"F600","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-12-12T16:00:00Z","lieu":"Stade A","statut":"En direct","minute":10,"score_domicile":0,"score_exterieur":0}]}');
reset role; select id as f600 from koki_foot.matchs where ref_fournisseur='F600' \gset
:E
select t.adm('score',jsonb_build_object('id',:'f600','revision',t.rev(:'f600'),'statut','En direct','minute',12,'score_domicile',1,'score_exterieur',0,'motif','But vu au stade'));
reset role;
select t.ok((select verrou_score and not verrou_manuel and not verrou_statut and not verrou_programmation and not verrou_evenements from koki_foot.matchs where id=:'f600'),'mode indépendant : seul le verrou du score est posé');
-- Synchronisation croisée : statut, minute, programmation et événements changent ; le score diverge.
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"ind2","matchs":[{"ref":"F600","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-12-12T16:15:00Z","lieu":"Stade B","statut":"Mi-temps","score_domicile":0,"score_exterieur":0}],"evenements":[{"match_ref":"F600","cle":"F600|cj|20","type":"carton_jaune","periode":"mi_temps_1","minute":20,"equipe_ref":"T2","joueur":"Ba"}]}');
reset role;
select t.ok((select score_domicile=1 and statut='Mi-temps' and date_match='2026-12-12T16:15:00Z' and lieu='Stade B' from koki_foot.matchs where id=:'f600'),'synchronisation croisée : score protégé, statut et programmation suivent le fournisseur');
select t.ok((select count(*) from koki_foot.evenements where match_id=:'f600')=1,'événements non verrouillés : importés');
select t.ok((select array_agg(champ order by champ) from koki_foot.conflits where match_id=:'f600' and not resolu)=array['score'],'un seul conflit (score), aucun faux conflit');
:E
select t.adm('enregistrer_match',jsonb_build_object('id',:'f600','revision',t.rev(:'f600'),'lieu','Stade Municipal','motif','Lieu confirmé par la ligue'));
reset role;
select domicile_id as f600_dom from koki_foot.matchs where id=:'f600' \gset
:E
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'f600','revision',t.rev(:'f600'),'type','carton_rouge','periode','mi_temps_1','minute',40,'equipe_id',:'f600_dom','joueur','X','motif','Expulsion non remontée'));
reset role;
select t.ok((select verrou_score and verrou_programmation and verrou_evenements and not verrou_statut and not verrou_manuel from koki_foot.matchs where id=:'f600'),'trois verrous indépendants, statut libre, pas de verrou global');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"ind3","matchs":[{"ref":"F600","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-12-12T16:15:00Z","lieu":"Stade B","statut":"En direct","minute":50,"score_domicile":0,"score_exterieur":0}],"evenements":[{"match_ref":"F600","cle":"F600|but|48","type":"but","periode":"mi_temps_2","minute":48,"equipe_ref":"T2","joueur":"Sarr"}]}');
reset role;
select t.ok((select statut='En direct' and minute=50 and lieu='Stade Municipal' and score_domicile=1 from koki_foot.matchs where id=:'f600'),'statut suit le fournisseur ; lieu et score corrigés conservés');
select t.ok((select array_agg(champ order by champ) from koki_foot.conflits where match_id=:'f600' and not resolu)=array['evenements','programmation','score'],'conflits ouverts : événements, programmation, score (pas de statut)');
select id as k600 from koki_foot.conflits where match_id=:'f600' and champ='programmation' and not resolu \gset
:E
select t.adm('resoudre_conflit',jsonb_build_object('id',:k600,'decision','accepter_api','motif','Le stade B est confirmé'));
reset role;
select t.ok((select not verrou_programmation and verrou_score and verrou_evenements from koki_foot.matchs where id=:'f600'),'mode indépendant : résoudre la programmation ne touche pas aux autres verrous');
-- Compatibilité : un verrou global déjà posé reste respecté en mode indépendant.
select t.ok((select verrou_manuel from koki_foot.matchs where ref_fournisseur='F500'),'compatibilité : verrou_manuel d''avant conservé');
set role service_role; select t.as_service();
select t.sync('importer','{"fournisseur":"api-football","operation":"compat","matchs":[{"ref":"F500","competition_ref":"L1SN","domicile_ref":"T2","exterieur_ref":"T1","date_match":"2026-12-10T16:30:00Z","lieu":"Stade B","statut":"Terminé","score_domicile":3,"score_exterieur":3}]}');
reset role;
select t.ok((select statut<>'Terminé' from koki_foot.matchs where ref_fournisseur='F500'),'compatibilité : verrou_manuel existant toujours respecté en mode indépendant');
set role authenticated; select t.as_user(:'super','aal2');
select t.adm('regler_verrous','{"mode":"global"}');
reset role;
select t.ok(koki_foot.mode_verrous()='global','retour au mode global (lancement)');

-- ═════ 27. Priorité des notifications de changement d'horaire ═════
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-20T16:03Z','À venir','2026-12-19T10:00Z')='aucune','écart < 5 min : aucune');
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-20T16:10Z','À venir','2026-12-19T10:00Z')='facultative','5 à 14 min : facultative');
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-20T16:15Z','À venir','2026-12-19T10:00Z')='normale','15 min : normale');
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-20T15:40Z','À venir','2026-12-19T10:00Z')='normale','avancé de 20 min : normale');
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-21T16:00Z','À venir','2026-12-19T10:00Z')='prioritaire','changement de jour : prioritaire');
select t.ok(koki_foot.priorite_horaire('2026-12-20T23:50Z','2026-12-21T00:05Z','À venir','2026-12-19T10:00Z')='prioritaire','passage de minuit à Koki : prioritaire');
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-20T16:02Z','Reporté','2026-12-19T10:00Z')='prioritaire','report : prioritaire');
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-20T16:03Z','À venir','2026-12-20T15:20Z')='normale','match dans moins de 60 min : notifié même pour 3 min');
select t.ok(koki_foot.priorite_horaire('2026-12-20T16:00Z','2026-12-20T16:03Z','À venir','2026-12-20T17:30Z')='aucune','match déjà passé : pas de règle des 60 min');
select t.ok((select count(*)=count(priorite) from koki_foot.changements_horaire),'chaque changement inscrit porte une priorité');
select t.ok((select priorite from koki_foot.changements_horaire c join koki_foot.matchs m on m.id=c.match_id where m.ref_fournisseur='F600' and c.nouvelle='2026-12-12T16:15:00Z')='normale','synchronisation : décalage de 15 min = normale');

-- ═════ 28. Ancrage externe : lecture de la dernière empreinte ═════
set role service_role; select t.as_service();
select t.sync('empreinte_journal','{"fournisseur":"api-football"}') as ancre \gset
reset role;
select t.ok((:'ancre'::jsonb->>'empreinte')=(select empreinte from koki_foot.corrections order by id desc limit 1) and (:'ancre'::jsonb->>'dernier_id')::bigint=(select max(id) from koki_foot.corrections),'empreinte du journal : dernière ligne');
set role authenticated; select t.as_user(:'super','aal2');
select t.err($$select public.koki_foot_sync('empreinte_journal','{"fournisseur":"api-football"}')$$,'permission denied','empreinte : réservée à la clé serveur');
reset role;

reset role;
select format('Tests réussis : %s', count(*)) from t.journal \gset
\echo :format
drop schema t cascade; drop schema realtime cascade;
