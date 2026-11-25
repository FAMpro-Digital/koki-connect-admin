-- Données de démonstration du banc d'essai navigateur (base LOCALE uniquement). Noms fictifs.
insert into auth.users(id,email) values
 ('b0000000-0000-4000-8000-0000000000e1','editeur@banc.local'),('b0000000-0000-4000-8000-0000000000a1','super@banc.local'),('b0000000-0000-4000-8000-0000000000c1','habitant@banc.local');
insert into public.koki_admin_members(user_id,role) values('b0000000-0000-4000-8000-0000000000e1','editor'),('b0000000-0000-4000-8000-0000000000a1','superadmin');
select set_config('request.jwt.claims','{"sub":"b0000000-0000-4000-8000-0000000000e1","aal":"aal2","role":"authenticated"}',false);
create temp table ids(k text primary key, v uuid);
create function pg_temp.adm(c text, i jsonb) returns jsonb language sql as $$ select public.koki_foot_admin(c,i) $$;
create function pg_temp.rev(m text) returns int language sql as $$ select revision from koki_foot.matchs where id=(select v from ids where k=m) $$;
create function pg_temp.id(cle text) returns text language sql as $$ select v::text from ids where k=cle $$;

insert into ids select 'nav',(pg_temp.adm('enregistrer_competition','{"nom":"Navétanes Koki 2026","saison":"2026","type":"Championnat","portee":"Koki","publie":true,"ordre":1}')->>'id')::uuid;
insert into ids select 'coupe',(pg_temp.adm('enregistrer_competition','{"nom":"Coupe de Koki","saison":"2026","type":"Coupe","portee":"Koki","publie":true,"ordre":2}')->>'id')::uuid;
insert into ids select 'ndiaye',(pg_temp.adm('enregistrer_equipe','{"nom":"ASC Koki Ndiaye","quartier":"Koki Ndiaye","couleurs":["#087a3d","#ffffff"]}')->>'id')::uuid;
insert into ids select 'darou',(pg_temp.adm('enregistrer_equipe','{"nom":"ASC Darou","quartier":"Darou","couleurs":["#c0392b","#f1c40f"]}')->>'id')::uuid;
insert into ids select 'gouye',(pg_temp.adm('enregistrer_equipe','{"nom":"ASC Gouye","couleurs":["#1f4e9c"]}')->>'id')::uuid;
insert into ids select 'santhiou',(pg_temp.adm('enregistrer_equipe','{"nom":"ASC Santhiou","couleurs":["#6c3483","#ffffff"]}')->>'id')::uuid;
select pg_temp.adm('inscrire_equipe',jsonb_build_object('competition_id',pg_temp.id('nav'),'equipe_id',pg_temp.id(x),'poule','A')) from unnest(array['ndiaye','darou','gouye','santhiou']) x;

-- Match en direct (Navétanes) avec événements.
insert into ids select 'direct',(pg_temp.adm('enregistrer_match',jsonb_build_object('competition_id',pg_temp.id('nav'),'domicile_id',pg_temp.id('ndiaye'),'exterieur_id',pg_temp.id('darou'),'date_match',(now()-interval '70 minutes')::text,'lieu','Stade de Koki','journee','3e journée','poule','A','publie',true))->>'id')::uuid;
select pg_temp.adm('score',jsonb_build_object('id',pg_temp.id('direct'),'revision',pg_temp.rev('direct'),'statut','En direct','minute',1));
select pg_temp.adm('ajouter_evenement',jsonb_build_object('match_id',pg_temp.id('direct'),'revision',pg_temp.rev('direct'),'type','but','periode','mi_temps_1','minute',23,'equipe_id',pg_temp.id('ndiaye'),'joueur','Moussa Fall'));
select pg_temp.adm('ajouter_evenement',jsonb_build_object('match_id',pg_temp.id('direct'),'revision',pg_temp.rev('direct'),'type','carton_jaune','periode','mi_temps_1','minute',45,'minute_add',2,'equipe_id',pg_temp.id('darou'),'joueur','Ibra Diop'));
select pg_temp.adm('score',jsonb_build_object('id',pg_temp.id('direct'),'revision',pg_temp.rev('direct'),'statut','En direct','minute',67));
-- Match à venir ce soir et résultat d'hier.
insert into ids select 'soir',(pg_temp.adm('enregistrer_match',jsonb_build_object('competition_id',pg_temp.id('nav'),'domicile_id',pg_temp.id('gouye'),'exterieur_id',pg_temp.id('santhiou'),'date_match',(date_trunc('day',now())+interval '22 hours')::text,'lieu','Terrain de Gouye','journee','3e journée','poule','A','publie',true))->>'id')::uuid;
insert into ids select 'hier',(pg_temp.adm('enregistrer_match',jsonb_build_object('competition_id',pg_temp.id('nav'),'domicile_id',pg_temp.id('darou'),'exterieur_id',pg_temp.id('gouye'),'date_match',(now()-interval '1 day')::text,'lieu','Stade de Koki','journee','2e journée','poule','A','publie',true))->>'id')::uuid;
select pg_temp.adm('score',jsonb_build_object('id',pg_temp.id('hier'),'revision',pg_temp.rev('hier'),'statut','Terminé','score_domicile',2,'score_exterieur',1));
-- Coupe : prolongation et tirs au but.
insert into ids select 'tab',(pg_temp.adm('enregistrer_match',jsonb_build_object('competition_id',pg_temp.id('coupe'),'domicile_id',pg_temp.id('santhiou'),'exterieur_id',pg_temp.id('ndiaye'),'date_match',(now()-interval '2 days')::text,'lieu','Stade de Koki','journee','Demi-finale','publie',true))->>'id')::uuid;
select pg_temp.adm('score',jsonb_build_object('id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'statut','En direct','minute',1));
select pg_temp.adm('ajouter_evenement',jsonb_build_object('match_id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'type','but','periode','mi_temps_2','minute',88,'equipe_id',pg_temp.id('santhiou'),'joueur','Ablaye Sow'));
select pg_temp.adm('ajouter_evenement',jsonb_build_object('match_id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'type','penalty','periode','mi_temps_2','minute',90,'minute_add',4,'equipe_id',pg_temp.id('ndiaye'),'joueur','Moussa Fall'));
select pg_temp.adm('score',jsonb_build_object('id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'statut','Prolongations','minute',91));
select pg_temp.adm('ajouter_evenement',jsonb_build_object('match_id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'type','but','periode','prolongation_2','minute',112,'equipe_id',pg_temp.id('ndiaye'),'joueur','Cheikh Ba'));
select pg_temp.adm('ajouter_evenement',jsonb_build_object('match_id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'type','but','periode','prolongation_2','minute',118,'equipe_id',pg_temp.id('santhiou'),'joueur','Ablaye Sow'));
select pg_temp.adm('score',jsonb_build_object('id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'statut','Tirs au but','minute',120));
select pg_temp.adm('ajouter_evenement',jsonb_build_object('match_id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'type',t,'periode','tirs_au_but','equipe_id',pg_temp.id(e),'joueur',j))
 from (values ('tab_reussi','santhiou','Sow'),('tab_reussi','ndiaye','Fall'),('tab_manque','santhiou','Ndao'),('tab_reussi','ndiaye','Ba')) v(t,e,j);
select pg_temp.adm('score',jsonb_build_object('id',pg_temp.id('tab'),'revision',pg_temp.rev('tab'),'statut','Terminé','motif','Fin de la séance de tirs au but'));

-- Fournisseur : Ligue 1 Sénégal (match en direct) et CAF (international, à venir).
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.koki_foot_sync('importer',jsonb_build_object('fournisseur','api-football','operation','demo',
 'competitions',jsonb_build_array(jsonb_build_object('ref','L1SN','nom','Ligue 1 Sénégal','saison','2025','portee','Sénégal'),jsonb_build_object('ref','CAFCL','nom','Ligue des champions CAF','saison','2025','type','Coupe','portee','International')),
 'equipes','[{"ref":"T1","nom":"ASC Jaraaf"},{"ref":"T2","nom":"Génération Foot"},{"ref":"T3","nom":"Teungueth FC"},{"ref":"T4","nom":"Al Ahly"}]'::jsonb,
 'matchs',jsonb_build_array(
  jsonb_build_object('ref','F1','competition_ref','L1SN','domicile_ref','T1','exterieur_ref','T2','date_match',(now()-interval '50 minutes')::text,'lieu','Stade Iba Mar Diop','statut','En direct','minute',48,'score_domicile',0,'score_exterieur',1),
  jsonb_build_object('ref','F2','competition_ref','L1SN','domicile_ref','T3','exterieur_ref','T1','date_match',(now()-interval '3 days')::text,'statut','Terminé','score_domicile',1,'score_exterieur',1),
  jsonb_build_object('ref','F3','competition_ref','CAFCL','domicile_ref','T3','exterieur_ref','T4','date_match',(date_trunc('day',now())+interval '2 days 19 hours')::text,'statut','À venir')),
 'evenements','[{"match_ref":"F1","cle":"F1|b|33","type":"but","periode":"mi_temps_1","minute":33,"equipe_ref":"T2","joueur":"P. Sarr"}]'::jsonb,
 'classements','[{"competition_ref":"L1SN","equipe_ref":"T1","rang":1,"joues":10,"gagnes":7,"nuls":2,"perdus":1,"buts_pour":15,"buts_contre":5,"points":23,"forme":"VVNVD"},{"competition_ref":"L1SN","equipe_ref":"T2","rang":2,"joues":10,"gagnes":6,"nuls":2,"perdus":2,"buts_pour":14,"buts_contre":9,"points":20,"forme":"VNVVV"},{"competition_ref":"L1SN","equipe_ref":"T3","rang":3,"joues":10,"gagnes":5,"nuls":3,"perdus":2,"buts_pour":11,"buts_contre":8,"points":18,"forme":"NVNDV"}]'::jsonb));
-- Compétitions importées publiées par l'administrateur (comportement réel : non publiées par défaut).
update koki_foot.competitions set publie=true where ref_fournisseur in ('L1SN','CAFCL');
-- Un match importé corrigé localement puis contredit par le fournisseur : conflit ouvert.
select set_config('request.jwt.claims','{"sub":"b0000000-0000-4000-8000-0000000000e1","aal":"aal2","role":"authenticated"}',false);
select public.koki_foot_admin('score',jsonb_build_object('id',(select id from koki_foot.matchs where ref_fournisseur='F2'),'revision',(select revision from koki_foot.matchs where ref_fournisseur='F2'),'statut','Terminé','score_domicile',2,'score_exterieur',1,'motif','Feuille de match officielle reçue'));
select set_config('request.jwt.claims','{"role":"service_role"}',false);
select public.koki_foot_sync('importer',jsonb_build_object('fournisseur','api-football','operation','demo-conflit','matchs',jsonb_build_array(
 jsonb_build_object('ref','F2','competition_ref','L1SN','domicile_ref','T3','exterieur_ref','T1','date_match',(select api_date_match from koki_foot.matchs where ref_fournisseur='F2')::text,'statut','Terminé','score_domicile',1,'score_exterieur',1))));
