-- Tests du module Clubs & Académies (koki_sport) sur une base LOCALE rejouant la référence de production.
-- Lancement : bash supabase/historique/outils/tester-sport.sh
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = warning;

-- ───── Outils de test (schéma t, supprimé à la fin) ─────
create schema t;
grant usage on schema t to anon, authenticated;
create table t.journal(n serial, ok text);
grant insert, select on t.journal to anon, authenticated; grant usage on sequence t.journal_n_seq to anon, authenticated;
create function t.as_user(uid text, aal text default 'aal1') returns void language sql as $$
 select set_config('request.jwt.claim.sub',coalesce(uid,''),false), set_config('request.jwt.claims',json_build_object('sub',uid,'aal',aal,'role','authenticated')::text,false), null::void $$;
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
create function t.call(cmd text, input jsonb default '{}') returns jsonb language sql as $$ select public.koki_sport(cmd,input) $$;
grant execute on all functions in schema t to anon, authenticated;

-- Acteurs fictifs
insert into auth.users(id) values
 ('a0000000-0000-4000-8000-000000000001'),('a0000000-0000-4000-8000-000000000002'),('a0000000-0000-4000-8000-000000000003'),
 ('b0000000-0000-4000-8000-000000000001'),('b0000000-0000-4000-8000-000000000002'),
 ('c0000000-0000-4000-8000-000000000001'),('c0000000-0000-4000-8000-000000000002'),
 ('d0000000-0000-4000-8000-000000000001'),('d0000000-0000-4000-8000-000000000002');
insert into public.koki_admin_members(user_id,role) values('d0000000-0000-4000-8000-000000000001','superadmin'),('d0000000-0000-4000-8000-000000000002','editor');
\set respA 'a0000000-0000-4000-8000-000000000001'
\set coachA 'a0000000-0000-4000-8000-000000000002'
\set commA 'a0000000-0000-4000-8000-000000000003'
\set respB 'b0000000-0000-4000-8000-000000000001'
\set coachB 'b0000000-0000-4000-8000-000000000002'
\set fan 'c0000000-0000-4000-8000-000000000001'
\set intrus 'c0000000-0000-4000-8000-000000000002'
\set admin 'd0000000-0000-4000-8000-000000000001'
\set editor 'd0000000-0000-4000-8000-000000000002'

-- ═════ 1. Création des académies ═════
set role authenticated;
select t.as_user(:'respA');
select (t.call('create_club','{"nom":"Koki Académie Foot","request_id":"11111111-0000-4000-8000-000000000001"}'))->>'id' as club_a \gset
select t.ok((t.call('create_club','{"nom":"Koki Académie Foot","request_id":"11111111-0000-4000-8000-000000000001"}'))->>'id'=:'club_a','idempotence : même request_id → même académie');
select t.ok((t.call('my_clubs')->0->>'statut')='À valider','nouvelle académie À valider');
select t.ok((t.call('my_clubs')->0->>'slug')='koki-academie-foot','slug sans accents');
select t.as_user(:'respB');
select (t.call('create_club','{"nom":"Académie Rivale"}'))->>'id' as club_b \gset
select t.err($$select t.call('create_club','{"nom":"X","statut":"Actif"}')$$,'Champs inconnus','champ non autorisé refusé (pas d’auto-validation)');

-- Pas de publication tant que l'académie n'est pas validée
select t.as_user(:'respA');
select (t.call('post_save',jsonb_build_object('club_id',:'club_a','titre','Brouillon')))->>'id' as post0 \gset
select t.err(format($$select t.call('post_publish','{"id":"%s","revision":1}')$$,:'post0'),'refusé','publication impossible avant validation');

-- ═════ 2. Validation FAMpro (MFA obligatoire) ═════
select t.as_user(:'admin','aal1');
select t.err(format($$select t.call('admin_review','{"id":"%s","revision":1,"decision":"approve"}')$$,:'club_a'),'refusé','admin sans MFA refusé');
select t.as_user(:'editor','aal2');
select t.err(format($$select t.call('admin_review','{"id":"%s","revision":1,"decision":"approve"}')$$,:'club_a'),'refusé','editor ne valide pas les académies');
select t.as_user(:'respA');
select t.err(format($$select t.call('admin_review','{"id":"%s","revision":1,"decision":"approve"}')$$,:'club_a'),'refusé','un responsable ne se valide pas lui-même');
select t.as_user(:'admin','aal2');
select t.err(format($$select t.call('admin_review','{"id":"%s","revision":1,"decision":"refuse","motif":"x"}')$$,:'club_b'),'check','refus sans motif refusé');
select t.ok((t.call('admin_review',jsonb_build_object('id',:'club_a','revision',1,'decision','approve')))->>'statut'='Actif','académie A validée');
select t.ok((t.call('admin_review',jsonb_build_object('id',:'club_b','revision',1,'decision','approve')))->>'statut'='Actif','académie B validée');

-- ═════ 3. Catégories, encadrement, invitations ═════
select t.as_user(:'respA');
select (t.call('category_save',jsonb_build_object('club_id',:'club_a','nom','U11','annee_min',2015,'annee_max',2016)))->>'id' as u11 \gset
select (t.call('category_save',jsonb_build_object('club_id',:'club_a','nom','U13','ordre',2)))->>'id' as u13 \gset
select t.err(format($$select t.call('category_save','{"club_id":"%s","nom":"u11"}')$$,:'club_a'),'categories_nom|duplicate','catégorie en double refusée');
select (t.call('staff_save',jsonb_build_object('club_id',:'club_a','prenom','Moussa','nom','Coach','fonction','Entraîneur U11','public',true,'categories',jsonb_build_array(:'u11'))))->>'id' as staff_a \gset
select (t.call('invite',jsonb_build_object('club_id',:'club_a','role','entraineur','staff_id',:'staff_a')))->>'code' as code_coach \gset
select x->>'code' as code_comm, x->>'id' as inv_comm from (select t.call('invite',jsonb_build_object('club_id',:'club_a','role','communication')) x) z \gset
select t.ok(not exists(select 1 from t.journal where ok like '%' || :'code_coach' || '%'),'code non journalisé');
select t.as_user(:'coachA');
select t.ok((t.call('accept_invitation',jsonb_build_object('code',lower(:'code_coach'))))->>'role'='entraineur','entraîneur rejoint A (code insensible à la casse)');
select t.ok((t.call('accept_invitation',jsonb_build_object('code',:'code_coach')))->>'ok'='false','code à usage unique');
select t.as_user(:'commA');
select t.ok((t.call('accept_invitation',jsonb_build_object('code',:'code_comm')))->>'role'='communication','chargé de communication rejoint A');

-- ═════ 4. Joueurs (privés) et rôles ═════
select t.as_user(:'respA');
select (t.call('player_save',jsonb_build_object('club_id',:'club_a','categorie_id',:'u11','prenom','Awa','nom','Diop','annee_naissance',2015,'numero',7)))->>'id' as p1 \gset
select (t.call('player_save',jsonb_build_object('club_id',:'club_a','categorie_id',:'u13','prenom','Ibou','nom','Fall','annee_naissance',2013)))->>'id' as p2 \gset
select t.err(format($$select t.call('player_save','{"club_id":"%s","categorie_id":"%s","prenom":"X","nom":"Y","date_naissance":"2015-01-01"}')$$,:'club_a',:'u11'),'Champs inconnus','date de naissance complète refusée (minimisation)');

select t.as_user(:'coachA');
select t.ok(jsonb_array_length(t.call('players_list',jsonb_build_object('club_id',:'club_a')))=1,'entraîneur U11 ne voit que ses joueurs');
select t.ok((t.call('player_get',jsonb_build_object('id',:'p1')))->>'prenom'='Awa','entraîneur lit un joueur de sa catégorie');
select t.err(format($$select t.call('player_get','{"id":"%s"}')$$,:'p2'),'refusé','entraîneur ne lit pas un joueur U13');
select t.err(format($$select t.call('player_save','{"club_id":"%s","categorie_id":"%s","prenom":"X","nom":"Y"}')$$,:'club_a',:'u13'),'refusé','entraîneur ne crée pas en U13');
select t.err(format($$select t.call('player_save','{"id":"%s","revision":1,"categorie_id":"%s","prenom":"Awa"}')$$,:'p1',:'u13'),'refusé','entraîneur ne déplace pas vers U13');
select t.ok((t.call('session_save',jsonb_build_object('club_id',:'club_a','categorie_id',:'u11','debut','2026-12-05T09:00:00Z','fin','2026-12-05T10:30:00Z','lieu','Stade de Koki','theme','Passes')))->>'statut'='planifiée','entraîneur programme une séance U11');
select t.err(format($$select t.call('session_save','{"club_id":"%s","categorie_id":"%s","debut":"2026-12-05T09:00:00Z","fin":"2026-12-05T10:00:00Z"}')$$,:'club_a',:'u13'),'refusé','entraîneur ne programme pas en U13');
select t.err(format($$select t.call('consent_save','{"player_id":"%s","revision":1,"nom_public":"complet","recueilli_le":"2026-11-20","mode":"papier"}')$$,:'p1'),'refusé','entraîneur ne saisit pas les consentements');
select t.err(format($$select t.call('invite','{"club_id":"%s","role":"responsable"}')$$,:'club_a'),'refusé','entraîneur n’invite pas');

select t.as_user(:'commA');
select t.err(format($$select t.call('players_list','{"club_id":"%s"}')$$,:'club_a'),'refusé','communication ne voit pas les fiches joueurs');
select t.ok(jsonb_array_length(t.call('tagging_list',jsonb_build_object('club_id',:'club_a')))=2,'communication voit la liste de désignation (prénom + initiale)');
select t.ok(not (t.call('tagging_list',jsonb_build_object('club_id',:'club_a'))::text ~ '(Diop|2015|annee)'),'liste de désignation sans nom complet ni âge');
select (t.call('post_save',jsonb_build_object('club_id',:'club_a','titre','Victoire des U11','texte','Belle victoire ce week-end.')))->>'id' as post1 \gset
select t.ok((t.call('post_publish',jsonb_build_object('id',:'post1','revision',1)))->>'statut'='publié','communication publie une actualité');
select t.err(format($$select t.call('session_save','{"club_id":"%s","categorie_id":"%s","debut":"2026-12-05T09:00:00Z","fin":"2026-12-05T10:00:00Z"}')$$,:'club_a',:'u11'),'refusé','communication ne gère pas les séances');

-- ═════ 5. Isolation entre académies ═════
select t.as_user(:'respB');
select (t.call('category_save',jsonb_build_object('club_id',:'club_b','nom','U11')))->>'id' as u11b \gset
select (t.call('player_save',jsonb_build_object('club_id',:'club_b','categorie_id',:'u11b','prenom','Modou','nom','Sarr')))->>'id' as pb \gset
select t.err(format($$select t.call('player_get','{"id":"%s"}')$$,:'p1'),'refusé','B ne lit pas un joueur de A');
select t.err(format($$select t.call('players_list','{"club_id":"%s"}')$$,:'club_a'),'refusé','B ne liste pas les joueurs de A');
select t.err(format($$select t.call('club_get','{"club_id":"%s"}')$$,:'club_a'),'refusé','B ne lit pas l’espace privé de A');
select t.err(format($$select t.call('player_save','{"club_id":"%s","categorie_id":"%s","prenom":"X","nom":"Y"}')$$,:'club_a',:'u11'),'refusé','B ne crée pas de joueur chez A');
select t.err(format($$select t.call('player_save','{"id":"%s","revision":1,"categorie_id":"%s","prenom":"Pirate"}')$$,:'p1',:'u11b'),'refusé','B ne modifie pas un joueur de A');
select t.err(format($$select t.call('player_save','{"club_id":"%s","categorie_id":"%s","prenom":"X","nom":"Y"}')$$,:'club_b',:'u11'),'Catégorie invalide','B ne range pas un joueur dans une catégorie de A');
select t.err(format($$select t.call('category_save','{"id":"%s","revision":1,"nom":"Pirate"}')$$,:'u11'),'refusé','B ne renomme pas une catégorie de A');
select t.err(format($$select t.call('session_save','{"club_id":"%s","categorie_id":"%s","debut":"2026-12-05T09:00:00Z","fin":"2026-12-05T10:00:00Z"}')$$,:'club_b',:'u11'),'foreign key|violates','FK composite : séance de B sur catégorie de A impossible');
select t.err(format($$select t.call('staff_save','{"club_id":"%s","prenom":"X","nom":"Y","categories":["%s"]}')$$,:'club_b',:'u11'),'foreign key|violates','FK composite : encadrant de B sur catégorie de A impossible');
select (t.call('session_save',jsonb_build_object('club_id',:'club_b','categorie_id',:'u11b','debut','2026-12-06T09:00:00Z','fin','2026-12-06T10:00:00Z')))->>'id' as sess_b \gset
select t.err(format($$select t.call('attendance_save','{"session_id":"%s","presences":[{"player_id":"%s","present":true}]}')$$,:'sess_b',:'p1'),'foreign key|violates','FK composite : présence d’un joueur de A dans une séance de B impossible');
select (t.call('match_save',jsonb_build_object('club_id',:'club_b','categorie_id',:'u11b','adversaire','ASC Test','a_domicile',true,'date_match','2026-12-07T15:00:00Z')))->>'id' as match_b \gset
select t.err(format($$select t.call('match_event_add','{"match_id":"%s","player_id":"%s","type":"but"}')$$,:'match_b',:'p1'),'foreign key|violates','FK composite : but d’un joueur de A dans un match de B impossible');
select t.err(format($$select t.call('media_add','{"club_id":"%s","type":"photo","storage_path":"%s/00000000-0000-4000-8000-000000000001.webp","contient_mineurs":false}')$$,:'club_b',:'club_a'),'check|violates','média de B rangé dans le dossier de A impossible');
select t.err(format($$select t.call('media_add','{"club_id":"%s","type":"youtube","youtube_id":"dQw4w9WgXcQ","contient_mineurs":true,"joueurs":["%s"]}')$$,:'club_b',:'p1'),'foreign key|violates','B ne désigne pas un joueur de A sur un média');
select t.err(format($$select t.call('post_publish','{"id":"%s","revision":2}')$$,:'post1'),'refusé','B ne dépublie pas une actualité de A');
select t.err(format($$select t.call('invitation_cancel','{"id":"%s"}')$$,:'inv_comm'),'refusé|permission','B n’annule pas une invitation de A');

-- ═════ 6. Accès direct aux tables refusé ═════
select t.err('select * from koki_sport.players','permission denied','authenticated : lecture directe des joueurs refusée');
select t.err('select * from koki_sport.player_guardians','permission denied','authenticated : lecture directe des représentants refusée');
select t.err($$insert into koki_sport.clubs(nom,slug,statut) values('X','x','Actif')$$,'permission denied','authenticated : insertion directe refusée');
select t.err($$update koki_sport.clubs set statut='Actif'$$,'permission denied','authenticated : auto-validation directe refusée');
select t.err('select koki_sport.can(null,''read'')','permission denied','fonctions internes non exécutables');
reset role; set role anon; select t.as_user(null);
select t.err('select * from koki_sport.clubs','permission denied','anon : lecture directe refusée');
select t.err($$select public.koki_sport('my_clubs','{}')$$,'permission denied','anon : RPC privée refusée');
select t.ok(jsonb_array_length(public.koki_sport_public('clubs','{}'))=2,'anon : liste publique des académies actives');

-- ═════ 7. Protection des mineurs ═════
select t.ok(jsonb_array_length(public.koki_sport_public('club',jsonb_build_object('slug','koki-academie-foot'))->'joueurs')=0,'sans consentement : aucun joueur public');
select t.ok(not (public.koki_sport_public('club',jsonb_build_object('slug','koki-academie-foot'))::text ~ '(Awa|Diop|Ibou|Fall|2015|2013|annee_naissance)'),'page publique sans nom, prénom ni année de naissance');
reset role; set role authenticated; select t.as_user(:'respA');
-- Migration 400 : l'affichage est décidé par le responsable (sans représentant légal obligatoire ; date et mode fixés par le serveur).
select (t.call('consent_save',jsonb_build_object('player_id',:'p1','revision',1,'nom_public','prenom_initiale','photo',true,'stats',true,'recueilli_le','2001-01-01','mode','papier'))) as cs1 \gset
select t.ok((:'cs1'::jsonb->>'mode')='responsable' and (:'cs1'::jsonb->>'recueilli_le')::date=current_date,'affichage décidé par le responsable : sans représentant, date et mode fixés par le serveur');
select t.ok(not (:'cs1'::jsonb ? 'recueilli_par'),'auteur de la décision non exposé');
select t.call('guardian_save',jsonb_build_object('player_id',:'p1','nom','Fatou Diop','lien','Mère','telephone','+221 77 000 00 00'));
reset role; set role anon; select t.as_user(null);
select t.ok((public.koki_sport_public('club',jsonb_build_object('slug','koki-academie-foot'))->'joueurs'->0->>'nom')='Awa D.','consentement « prénom + initiale » respecté');
select t.ok(not (public.koki_sport_public('club',jsonb_build_object('slug','koki-academie-foot'))::text ~ '(Diop|Fatou|77 000|Ibou)'),'ni nom complet, ni représentant, ni téléphone, ni joueur non autorisé');
reset role; set role authenticated; select t.as_user(:'commA');
select t.err(format($$select t.call('media_add','{"club_id":"%s","type":"photo","storage_path":"%s/00000000-0000-4000-8000-0000000000a1.webp"}')$$,:'club_a',:'club_a'),'reconnaissables','déclaration « mineurs reconnaissables » obligatoire');
select t.err(format($$select t.call('media_add','{"club_id":"%s","type":"photo","storage_path":"%s/00000000-0000-4000-8000-0000000000a1.webp","contient_mineurs":true}')$$,:'club_a',:'club_a'),'Désignez','mineurs non désignés refusés');
select (t.call('media_add',jsonb_build_object('club_id',:'club_a','post_id',:'post1','type','photo','storage_path',:'club_a'||'/00000000-0000-4000-8000-0000000000a1.webp','contient_mineurs',true,'joueurs',jsonb_build_array(:'p1')))) as m1 \gset
select t.ok((:'m1'::jsonb->>'public')::boolean,'photo avec joueur autorisé : publique');
select (t.call('media_add',jsonb_build_object('club_id',:'club_a','post_id',:'post1','type','photo','storage_path',:'club_a'||'/00000000-0000-4000-8000-0000000000a2.webp','contient_mineurs',true,'joueurs',jsonb_build_array(:'p1',:'p2')))) as m2 \gset
select t.ok(not (:'m2'::jsonb->>'public')::boolean,'photo avec un joueur non autorisé : privée');
select (t.call('media_add',jsonb_build_object('club_id',:'club_a','type','youtube','youtube_id','dQw4w9WgXcQ','contient_mineurs',true,'joueurs',jsonb_build_array(:'p1')))) as m3 \gset
select t.ok(not (:'m3'::jsonb->>'public')::boolean,'vidéo : autorisation photo insuffisante, vidéo exigée');

-- Stockage
insert into storage.objects(bucket_id,name) values('koki-sport',:'club_a'||'/00000000-0000-4000-8000-0000000000a1.webp');
select t.ok(exists(select 1 from storage.objects where bucket_id='koki-sport' and name like '%a1.webp'),'communication dépose une image dans le dossier de A');
insert into storage.objects(bucket_id,name) values('koki-sport',:'club_a'||'/00000000-0000-4000-8000-0000000000a2.webp');
delete from storage.objects where bucket_id='koki-sport' and name like '%a1.webp';
select t.ok(exists(select 1 from storage.objects where bucket_id='koki-sport' and name like '%a1.webp'),'image référencée : suppression bloquée');
select t.as_user(:'respB');
select t.err(format($$insert into storage.objects(bucket_id,name) values('koki-sport','%s/00000000-0000-4000-8000-0000000000ff.webp')$$,:'club_a'),'row-level security','B ne dépose rien dans le dossier de A');
select t.err($$insert into storage.objects(bucket_id,name) values('koki-sport','pas-un-dossier/photo.webp')$$,'row-level security','chemin hors convention refusé');
select t.ok((select count(*) from storage.objects where bucket_id='koki-sport' and name like :'club_a'||'%a2.webp')=0,'B ne voit pas l’image privée a2 de A');
reset role; set role anon; select t.as_user(null);
select t.ok((select count(*) from storage.objects where bucket_id='koki-sport' and name like '%a1.webp')=1,'anon voit l’image autorisée a1');
select t.ok((select count(*) from storage.objects where bucket_id='koki-sport' and name like '%a2.webp')=0,'anon ne voit pas l’image a2 (joueur non autorisé)');
select t.ok(jsonb_array_length(public.koki_sport_public('club',jsonb_build_object('slug','koki-academie-foot'))->'publications'->0->'medias')=1,'actualité publique : seul le média autorisé est listé');
-- Retrait du consentement : effet immédiat
reset role; set role authenticated; select t.as_user(:'respA');
select t.call('consent_revoke',jsonb_build_object('player_id',:'p1','revision',2));
reset role; set role anon; select t.as_user(null);
select t.ok(jsonb_array_length(public.koki_sport_public('club',jsonb_build_object('slug','koki-academie-foot'))->'joueurs')=0,'retrait : joueur retiré de la page publique');
select t.ok((select count(*) from storage.objects where bucket_id='koki-sport' and name like '%a1.webp')=0,'retrait : image a1 immédiatement privée');
select t.ok(jsonb_array_length(public.koki_sport_public('club',jsonb_build_object('slug','koki-academie-foot'))->'publications'->0->'medias')=0,'retrait : média retiré de l’actualité');

-- ═════ 8. Matchs, compétitions, classement ═════
reset role; set role authenticated; select t.as_user(:'respA');
select (t.call('competition_save',jsonb_build_object('club_id',:'club_a','nom','Tournoi de Koki','saison','2026-2027','type','Tournoi','categorie_id',:'u13'))) as co \gset
select :'co'::jsonb->>'id' as co_id \gset
select (t.call('team_add',jsonb_build_object('competition_id',:'co_id','nom','ASC Ndiambour')))->>'id' as t2 \gset
select (t.call('team_add',jsonb_build_object('competition_id',:'co_id','nom','ASC Louga')))->>'id' as t3 \gset
reset role; select id as t1 from koki_sport.competition_teams where competition_id=:'co_id' and is_self \gset
set role authenticated; select t.as_user(:'respA');
select t.call('match_save',jsonb_build_object('club_id',:'club_a','categorie_id',:'u13','competition_id',:'co_id','home_team_id',:'t1','away_team_id',:'t2','date_match','2026-11-15T15:00:00Z','statut','Terminé','score_domicile',3,'score_exterieur',1));
select t.call('match_save',jsonb_build_object('club_id',:'club_a','categorie_id',:'u13','competition_id',:'co_id','home_team_id',:'t3','away_team_id',:'t1','date_match','2026-11-16T15:00:00Z','statut','Terminé','score_domicile',2,'score_exterieur',2));
select t.err(format($$select t.call('match_save','{"club_id":"%s","categorie_id":"%s","competition_id":"%s","home_team_id":"%s","away_team_id":"%s","date_match":"2026-11-20T15:00:00Z","statut":"Terminé"}')$$,:'club_a',:'u13',:'co_id',:'t1',:'t2'),'check|violates','match terminé sans score refusé');
select t.ok((t.call('standings',jsonb_build_object('competition_id',:'co_id'))->0->>'equipe')='Koki Académie Foot','classement : A en tête');
select t.ok((t.call('standings',jsonb_build_object('competition_id',:'co_id'))->0->>'points')='4','classement : 4 points (V + N)');
select t.as_user(:'respB');
select (t.call('competition_save',jsonb_build_object('club_id',:'club_b','nom','Coupe B')))->>'id' as co_b \gset
select t.err(format($$select t.call('match_save','{"club_id":"%s","categorie_id":"%s","competition_id":"%s","home_team_id":"%s","away_team_id":"%s","date_match":"2026-11-20T15:00:00Z"}')$$,:'club_b',:'u11b',:'co_b',:'t1',:'t2'),'foreign key|violates','FK composite : match de B avec équipes d’une compétition de A impossible');
select t.err(format($$select t.call('standings','{"competition_id":"%s"}')$$,:'co_id'),'refusé','B ne lit pas le classement privé de A (public seulement via la page publique)');

-- ═════ 9. Suspension et responsable unique ═════
reset role; select revision as rev_a from koki_sport.clubs where id=:'club_a' \gset
set role authenticated; select t.as_user(:'admin','aal2');
select t.ok((t.call('admin_review',jsonb_build_object('id',:'club_a','revision',:'rev_a'::int,'decision','suspend','motif','Signalement en cours d’examen')))->>'statut'='Suspendu','suspension motivée');
select t.as_user(:'respA');
select t.ok((t.call('club_get',jsonb_build_object('club_id',:'club_a')))->>'statut'='Suspendu','suspendue : lecture conservée');
select t.err(format($$select t.call('player_save','{"club_id":"%s","categorie_id":"%s","prenom":"X","nom":"Y"}')$$,:'club_a',:'u11'),'refusé','suspendue : aucune écriture');
reset role; set role anon; select t.as_user(null);
select t.err($$select public.koki_sport_public('club','{"slug":"koki-academie-foot"}')$$,'introuvable','suspendue : page publique retirée');
reset role; set role authenticated; select t.as_user(:'admin','aal2');
select t.call('admin_review',jsonb_build_object('id',:'club_a','revision',:'rev_a'::int+1,'decision','reactivate'));
reset role; select id as m_resp, revision as m_rev from koki_sport.club_members where club_id=:'club_a' and role='responsable' \gset
set role authenticated; select t.as_user(:'respA');
select t.err(format($$select t.call('member_update','{"id":"%s","revision":%s,"statut":"retiré"}')$$,:'m_resp',:'m_rev'),'au moins un responsable','le dernier responsable ne peut pas partir');

-- ═════ 10. Modération FAMpro et signalements ═════
select t.as_user(:'fan');
select t.call('follow',jsonb_build_object('club_id',:'club_a'));
select t.ok((t.call('report',jsonb_build_object('cible_type','post','cible_id',:'post1','motif','Mineur exposé')))->>'id' is not null,'un abonné signale une actualité');
select t.as_user(:'admin','aal1');
select t.err(format($$select t.call('admin_hide','{"cible_type":"post","id":"%s","motif":"Photo à vérifier"}')$$,:'post1'),'refusé','modération sans MFA refusée');
select t.as_user(:'editor','aal2');
select t.ok((t.call('admin_hide',jsonb_build_object('cible_type','post','id',:'post1','motif','Photo à vérifier')))->>'statut'='masqué','editor masque une actualité');
select t.as_user(:'commA');
select t.err(format($$select t.call('post_publish','{"id":"%s","revision":3}')$$,:'post1'),'masquée par la modération','l’académie ne republie pas un contenu masqué');
select t.as_user(:'editor','aal2');
select t.ok(jsonb_array_length(t.call('admin_posts','{"relais":"demandé"}'))=0 and jsonb_array_length(t.call('admin_posts','{}'))>=1,'admin_posts : liste des publications (hors brouillons)');
select t.as_user(:'respA');
select t.err($$select t.call('admin_posts','{}')$$,'refusé','admin_posts réservé aux administrateurs');

-- ═════ 11. Suppression de compte (non-régression public.koki_account_delete) ═════
select t.as_user(:'fan');
select public.koki_account_delete('contenus','SUPPRIMER');
select public.koki_account_delete('compte','SUPPRIMER');
reset role;
select t.ok(not exists(select 1 from koki_sport.follows where user_id=:'fan'),'compte abonné supprimé : abonnements effacés');
select t.ok(exists(select 1 from koki_sport.reports where reporter_id is null),'signalement conservé, auteur anonymisé');
set role authenticated; select t.as_user(:'coachA');
select public.koki_account_delete('contenus','SUPPRIMER'); select public.koki_account_delete('compte','SUPPRIMER');
reset role;
select t.ok((select user_id is null from koki_sport.staff where id=:'staff_a'),'compte entraîneur supprimé : fiche encadrant détachée');
set role authenticated; select t.as_user(:'respB');
select public.koki_account_delete('contenus','SUPPRIMER'); select public.koki_account_delete('compte','SUPPRIMER');
reset role;
select t.ok(not exists(select 1 from auth.users where id=:'respB'),'le dernier responsable peut supprimer son compte (non bloquant)');

-- ═════ 12. Divers ═════
set role authenticated; select t.as_user(:'intrus');
select t.ok((t.call('accept_invitation','{"code":"AAAAA-AAAAA"}'))->>'ok'='false','code faux 1 refusé (essai enregistré)');
select t.ok((t.call('accept_invitation','{"code":"AAAAA-AAAAB"}'))->>'ok'='false','code faux 2 refusé (essai enregistré)');
select t.ok((t.call('accept_invitation','{"code":"AAAAA-AAAAC"}'))->>'ok'='false','code faux 3 refusé (essai enregistré)');
select t.ok((t.call('accept_invitation','{"code":"AAAAA-AAAAD"}'))->>'ok'='false','code faux 4 refusé (essai enregistré)');
select t.ok((t.call('accept_invitation','{"code":"AAAAA-AAAAE"}'))->>'ok'='false','code faux 5 refusé (essai enregistré)');
select t.err($$select t.call('accept_invitation','{"code":"AAAAA-AAAAF"}')$$,'Trop d’essais','essais limités (anti force brute)');
select t.err($$select t.call('nimporte','{}')$$,'Commande inconnue','commande inconnue refusée');
select t.err($$select t.call('my_clubs','{"x":1}')$$,'Champs inconnus','champs inconnus refusés');
reset role;
select t.ok(exists(select 1 from public.koki_audit where table_name='players') and not exists(select 1 from public.koki_audit where details::text ~ '(Awa|Diop)'),'journal : écritures tracées sans contenu personnel');
select t.ok((select count(*) from public.koki_audit where table_name='player_consents')>=3,'journal : consentements tracés');

-- Non-régression : le module Commerce fonctionne toujours
set role authenticated; select t.as_user(:'intrus');
select t.ok((public.koki_business('register_professional',jsonb_build_object('request_id','22222222-0000-4000-8000-000000000001','name','TEST Boutique','phone','+221770000001','profile','Commerçant')))->>'kind'='professionnels','non-régression : inscription professionnelle Commerce');
reset role;

select count(*) as reussis from t.journal \gset
\echo 'Tests réussis :' :reussis
drop schema t cascade;
