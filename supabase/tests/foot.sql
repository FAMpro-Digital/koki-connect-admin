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
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'m1','revision',t.rev(:'m1'),'type','but','minute',12,'equipe_id',:'eq1','joueur','Moussa Fall'));
select current_user as role_courant \gset
reset role;
select t.ok((select score_domicile=1 and score_exterieur=0 from koki_foot.matchs where id=:'m1'),'but : score 1–0 mis à jour');
set role :role_courant;
select t.adm('ajouter_evenement',jsonb_build_object('match_id',:'m1','revision',t.rev(:'m1'),'type','but_csc','minute',30,'equipe_id',:'eq1','joueur','Ibra Diop'));
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
select t.ok((select apres->>'score_domicile'='3' and avant->>'score_domicile'='2' and motif='But oublié à la 89e' and acteur=:'editeur' from koki_foot.corrections where match_id=:'m1' order by id desc limit 1),'correction journalisée : avant, après, auteur, motif');
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
\set lot '{"fournisseur":"api-football","operation":"test","competitions":[{"ref":"L1SN","nom":"Ligue 1 Sénégal","saison":"2025","portee":"Sénégal"}],"equipes":[{"ref":"T1","nom":"ASC Jaraaf","logo_url":"https://media.example.com/t1.png"},{"ref":"T2","nom":"Génération Foot"},{"ref":"T3","nom":"Teungueth FC"}],"inscriptions":[{"competition_ref":"L1SN","equipe_ref":"T1"},{"competition_ref":"L1SN","equipe_ref":"T2"}],"matchs":[{"ref":"F100","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T16:00:00Z","statut":"En direct","minute":20,"score_domicile":1,"score_exterieur":0},{"ref":"F101","competition_ref":"L1SN","domicile_ref":"T3","exterieur_ref":"T1","date_match":"2026-11-30T16:00:00Z","statut":"À venir"}],"evenements":[{"match_ref":"F100","cle":"F100|but|12|T1|Diallo","type":"but","minute":12,"equipe_ref":"T1","joueur":"A. Diallo"}],"classements":[{"competition_ref":"L1SN","equipe_ref":"T1","rang":1,"joues":10,"gagnes":7,"nuls":2,"perdus":1,"buts_pour":15,"buts_contre":5,"points":23,"forme":"VVNVD"},{"competition_ref":"L1SN","equipe_ref":"T2","rang":2,"joues":10,"points":20}]}'
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
select t.sync('importer','{"fournisseur":"api-football","operation":"test-verrou","matchs":[{"ref":"F100","competition_ref":"L1SN","domicile_ref":"T1","exterieur_ref":"T2","date_match":"2026-11-24T16:00:00Z","statut":"En direct","minute":30,"score_domicile":1,"score_exterieur":0}],"evenements":[{"match_ref":"F100","cle":"F100|but|28|T2|Sarr","type":"but","minute":28,"equipe_ref":"T2","joueur":"Sarr"}]}') as r4 \gset
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
select t.err(format($$select t.adm('retirer_evenement','{"id":"%s","motif":"erreur"}')$$,t.evt(:'f100')),'fournisseur','événement du fournisseur : retrait refusé');
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
select t.sync('importer','{"fournisseur":"api-football","operation":"test-complet","evenements":[{"match_ref":"F100","cle":"F100|but|28|T2|Sarr","type":"but","minute":28,"equipe_ref":"T2","joueur":"Sarr"}],"evenements_complets":["F100"]}');
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

reset role;
select format('Tests réussis : %s', count(*)) from t.journal \gset
\echo :format
drop schema t cascade; drop schema realtime cascade;
