-- Module Football — 2/2 : accès (RPC), verrous, conflits, classement, fraîcheur, diffusion en direct.
-- NON APPLIQUÉE EN PRODUCTION. Testée en local (outils/tester-foot.sh).
--
--  * public.koki_foot_public(command, input) : lecture publique (anon) des seules compétitions publiées ;
--  * public.koki_foot_admin(command, input)  : administration. Exige koki_private.allowed('content')
--    (rôle editor ou superadmin ET session aal2) pour écrire, allowed('read') pour lire ;
--  * public.koki_foot_sync(command, input)   : import du fournisseur. Exécutable par service_role
--    SEULEMENT (fonction serveur, clé jamais exposée au navigateur). Un seul import à la fois par
--    fournisseur (verrou consultatif) : deux synchronisations simultanées s'exécutent l'une après l'autre ;
--  * verrous : une correction d'un match api pose le verrou global (verrou_manuel, comportement de
--    lancement) ET le verrou du champ touché (score, statut, événements, programmation). La synchronisation
--    respecte chaque verrou ; toute divergence est inscrite dans koki_foot.conflits ;
--  * diffusion : à chaque changement visible d'un match publié, un message Broadcast PUBLIC est envoyé
--    sur le canal « koki-foot » (identifiant, révision, statut, minute, scores : aucune donnée personnelle).
--    La révision permet au client d'ignorer un message plus ancien que l'état qu'il affiche.

begin;

do $$ begin
 if to_regnamespace('koki_foot') is null or to_regclass('koki_foot.conflits') is null or to_regclass('koki_foot.vus_api') is null or to_regclass('koki_foot.changements_horaire') is null then
  raise exception 'GARDE : appliquer d''abord 20261201000500_foot_schema.sql';
 end if;
 if to_regprocedure('public.koki_foot_public(text,jsonb)') is not null or to_regprocedure('public.koki_foot_admin(text,jsonb)') is not null
  or to_regprocedure('public.koki_foot_sync(text,jsonb)') is not null then
  raise exception 'GARDE : fonctions koki_foot déjà présentes';
 end if;
end $$;

-- ───────────── Lecture des paramètres ─────────────
create function koki_foot.echec(msg text) returns void language plpgsql set search_path='' as
$$ begin raise exception '%', msg using errcode='22023'; end $$;
-- Refuse toute clé inattendue (protection contre les champs injectés).
create function koki_foot.cles(input jsonb, permises text[]) returns void language plpgsql set search_path='' as $$
declare k text; begin
 if input is null or jsonb_typeof(input)<>'object' then perform koki_foot.echec('Requête invalide'); end if;
 for k in select jsonb_object_keys(input) loop
  if not k=any(permises) then perform koki_foot.echec('Champ non autorisé : '||k); end if;
 end loop;
end $$;
create function koki_foot.t(input jsonb, k text) returns text language sql immutable set search_path='' as
$$ select case when input->k is null or jsonb_typeof(input->k)='null' then null else btrim(input->>k) end $$;
create function koki_foot.u(input jsonb, k text) returns uuid language plpgsql immutable set search_path='' as $$
declare v text:=koki_foot.t(input,k); begin
 if v is null or v='' then return null; end if;
 if v !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then perform koki_foot.echec('Identifiant invalide : '||k); end if;
 return v::uuid;
end $$;
create function koki_foot.i(input jsonb, k text) returns integer language plpgsql immutable set search_path='' as $$
declare v text:=koki_foot.t(input,k); begin
 if v is null or v='' then return null; end if;
 if v !~ '^-?[0-9]{1,6}$' then perform koki_foot.echec('Nombre invalide : '||k); end if;
 return v::integer;
end $$;
create function koki_foot.b(input jsonb, k text, defaut boolean) returns boolean language sql immutable set search_path='' as
$$ select case when jsonb_typeof(input->k)='boolean' then (input->>k)::boolean else defaut end $$;
create function koki_foot.ts(input jsonb, k text) returns timestamptz language plpgsql stable set search_path='' as $$
declare v text:=koki_foot.t(input,k); begin
 if v is null or v='' then return null; end if;
 begin return v::timestamptz; exception when others then perform koki_foot.echec('Date invalide : '||k); end;
end $$;
create function koki_foot.revision(attendue integer, actuelle integer) returns void language plpgsql set search_path='' as $$
begin
 if attendue is null then perform koki_foot.echec('Révision requise'); end if;
 if attendue<>actuelle then raise exception 'Modifié entre-temps par un autre administrateur : rechargez' using errcode='40001'; end if;
end $$;
create function koki_foot.motif_requis(motif text) returns void language plpgsql set search_path='' as $$
begin if length(btrim(coalesce(motif,'')))<3 then perform koki_foot.echec('Motif de la correction requis (3 caractères au moins)'); end if; end $$;
create function koki_foot.exiger(permission text) returns uuid language plpgsql stable security definer set search_path='' as $$
begin
 if not koki_private.allowed(permission) then raise exception 'Administration et double authentification requises' using errcode='42501'; end if;
 return auth.uid();
end $$;
create function koki_foot.en_jeu(statut text) returns boolean language sql immutable set search_path='' as
$$ select statut in ('En direct','Mi-temps','Prolongations','Tirs au but','Interrompu') $$;

-- ───────────── Représentations ─────────────
create function koki_foot.equipe_json(e koki_foot.equipes) returns jsonb language sql stable set search_path='' as
$$ select jsonb_build_object('id',e.id,'nom',e.nom,'nom_court',e.nom_court,'logo_url',e.logo_url,'couleurs',to_jsonb(e.couleurs),'portee',e.portee,'quartier',e.quartier) $$;
-- État d'une source (fournisseur) : ok ; degrade (dernière tentative en échec, dernière réussite récente) ;
-- en_pause (panne ou quota) ; hors_service (aucune réussite depuis 3 seuils) ; inconnu (jamais appelée).
create function koki_foot.etat_source(f koki_foot.etat_fournisseurs) returns text language sql stable set search_path='' as $$
 select case when f.fournisseur is null or f.derniere_tentative is null then 'inconnu'
  when f.pause_jusqu_a>now() then 'en_pause'
  when f.derniere_reussite is null or f.derniere_reussite<now()-make_interval(secs=>3*f.seuil_ancien_s) then 'hors_service'
  when f.derniere_erreur is not null and f.derniere_erreur>f.derniere_reussite then 'degrade'
  else 'ok' end
$$;
-- Fraîcheur d'un match : manuel ; corrige (résultat corrigé par un administrateur) ; ancien (match api en jeu
-- sans réponse exploitable depuis le seuil du fournisseur, ou qui aurait dû commencer depuis attente_debut_s) ;
-- a_jour. Expose la dernière actualisation (réponse exploitable), la dernière modification et l'état de la source.
create function koki_foot.fraicheur(m koki_foot.matchs) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('source',m.source,'fournisseur',m.fournisseur,'source_resultat',m.resultat_source,
  'derniere_actualisation',v.vu_le,'derniere_modification',v.modifie_le,
  'etat_source',case when m.source='api' then koki_foot.etat_source(f) end,
  'etat',case when m.source='manuel' then 'manuel'
   when m.resultat_source='correction' then 'corrige'
   when koki_foot.en_jeu(m.statut) and coalesce(v.vu_le,'-infinity')<now()-make_interval(secs=>coalesce(f.seuil_ancien_s,300)) then 'ancien'
   when m.statut='À venir' and m.date_match<now()-make_interval(secs=>coalesce(f.attente_debut_s,1800))
        and coalesce(v.vu_le,'-infinity')<now()-make_interval(secs=>coalesce(f.seuil_ancien_s,300)) then 'ancien'
   else 'a_jour' end)
 from (select 1) x
 left join koki_foot.vus_api v on v.match_id=m.id
 left join koki_foot.etat_fournisseurs f on f.fournisseur=m.fournisseur
$$;
create function koki_foot.match_json(m koki_foot.matchs) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',m.id,'revision',m.revision,'competition',jsonb_build_object('id',c.id,'nom',c.nom,'saison',c.saison,'portee',c.portee,'type',c.type,'logo_url',c.logo_url),
  'domicile',koki_foot.equipe_json(d),'exterieur',koki_foot.equipe_json(x),'date_match',m.date_match,'lieu',m.lieu,'poule',m.poule,'journee',m.journee,
  'statut',m.statut,'minute',m.minute,'score_domicile',m.score_domicile,'score_exterieur',m.score_exterieur,'pro_domicile',m.pro_domicile,'pro_exterieur',m.pro_exterieur,
  'tab_domicile',m.tab_domicile,'tab_exterieur',m.tab_exterieur,'forfait_equipe_id',m.forfait_equipe_id,'rejoue_de',m.rejoue_de,
  'programmation_corrigee',m.verrou_programmation,
  'commentaire',m.commentaire,'source',m.source,'fraicheur',koki_foot.fraicheur(m),'mis_a_jour',m.updated_at)
 from koki_foot.competitions c, koki_foot.equipes d, koki_foot.equipes x where c.id=m.competition_id and d.id=m.domicile_id and x.id=m.exterieur_id
$$;
create function koki_foot.evenement_json(v koki_foot.evenements) returns jsonb language sql stable set search_path='' as
$$ select jsonb_build_object('id',v.id,'type',v.type,'periode',v.periode,'minute',v.minute,'minute_add',v.minute_add,'equipe_id',v.equipe_id,'joueur',v.joueur,'joueur2',v.joueur2) $$;
create function koki_foot.rang_periode(p text) returns integer language sql immutable set search_path='' as
$$ select array_position(array['mi_temps_1','mi_temps_2','prolongation_1','prolongation_2','tirs_au_but'],p) $$;
-- Visible publiquement : match publié d'une compétition publiée et non archivée.
create function koki_foot.visible(m koki_foot.matchs) returns boolean language sql stable set search_path='' as
$$ select m.publie and exists(select 1 from koki_foot.competitions c where c.id=m.competition_id and c.publie and c.statut<>'archivée') $$;

-- Cohérence événements ↔ score, PAR PÉRIODE explicite : buts (but, penalty) pour l'équipe, but contre son camp
-- pour l'adversaire ; mi-temps 1-2 => score réglementaire, prolongation 1-2 => pro_*, séance => tab_* (tab_reussi).
-- Les tirs au but ne comptent jamais comme buts du match. etat : aucun_evenement | coherent | incoherent.
create function koki_foot.coherence(m koki_foot.matchs) returns jsonb language sql stable set search_path='' as $$
 with b as (select
   count(*) filter (where v.periode in ('mi_temps_1','mi_temps_2') and ((v.type in ('but','penalty') and v.equipe_id=m.domicile_id) or (v.type='but_csc' and v.equipe_id=m.exterieur_id)))::int rd,
   count(*) filter (where v.periode in ('mi_temps_1','mi_temps_2') and ((v.type in ('but','penalty') and v.equipe_id=m.exterieur_id) or (v.type='but_csc' and v.equipe_id=m.domicile_id)))::int re,
   count(*) filter (where v.periode in ('prolongation_1','prolongation_2') and ((v.type in ('but','penalty') and v.equipe_id=m.domicile_id) or (v.type='but_csc' and v.equipe_id=m.exterieur_id)))::int pd,
   count(*) filter (where v.periode in ('prolongation_1','prolongation_2') and ((v.type in ('but','penalty') and v.equipe_id=m.exterieur_id) or (v.type='but_csc' and v.equipe_id=m.domicile_id)))::int pe,
   count(*) filter (where v.type='tab_reussi' and v.equipe_id=m.domicile_id)::int td,
   count(*) filter (where v.type='tab_reussi' and v.equipe_id=m.exterieur_id)::int te,
   count(*) filter (where v.type in ('but','penalty','but_csc'))::int n,
   count(*) filter (where v.periode='tirs_au_but')::int nt
  from koki_foot.evenements v where v.match_id=m.id)
 select jsonb_build_object('buts_evenements',jsonb_build_object('reglementaire',jsonb_build_array(rd,re),'prolongation',jsonb_build_array(pd,pe),'tirs_au_but',jsonb_build_array(td,te)),
  'etat',case when n=0 and nt=0 then 'aucun_evenement'
   when (rd,re,pd,pe)=(coalesce(m.score_domicile,0),coalesce(m.score_exterieur,0),coalesce(m.pro_domicile,0),coalesce(m.pro_exterieur,0))
    and (nt=0 or (td,te)=(coalesce(m.tab_domicile,0),coalesce(m.tab_exterieur,0))) then 'coherent'
   else 'incoherent' end) from b
$$;
create function koki_foot.verrous_json(m koki_foot.matchs) returns jsonb language sql immutable set search_path='' as
$$ select jsonb_build_object('global',m.verrou_manuel,'score',m.verrou_score,'statut',m.verrou_statut,'evenements',m.verrou_evenements,'programmation',m.verrou_programmation) $$;

-- ───────────── Classement ─────────────
-- API : lignes importées. Manuel : calculé à partir des matchs TERMINÉS et publiés, score RÉGLEMENTAIRE
-- (forfait : résultat officiel saisi ; match annulé puis rejoué : seul le match rejoué compte).
-- 3/1/0 ; départage : points, différence de buts, buts marqués, nom. Équipes inscrites sans match : 0.
create function koki_foot.classement(p_comp uuid, p_poule text) returns jsonb language plpgsql stable set search_path='' as $$
declare c koki_foot.competitions; begin
 select * into c from koki_foot.competitions where id=p_comp;
 if not found then return '[]'; end if;
 if c.source='api' then
  return coalesce((select jsonb_agg(jsonb_build_object('rang',k.rang,'equipe',koki_foot.equipe_json(e),'poule',k.poule,'joues',k.joues,'gagnes',k.gagnes,'nuls',k.nuls,'perdus',k.perdus,
   'buts_pour',k.buts_pour,'buts_contre',k.buts_contre,'diff',k.buts_pour-k.buts_contre,'points',k.points,'forme',k.forme,'synchronise_le',k.synchronise_le) order by k.poule,k.rang)
   from koki_foot.classements k join koki_foot.equipes e on e.id=k.equipe_id where k.competition_id=p_comp and (coalesce(p_poule,'')='' or k.poule=p_poule)),'[]');
 end if;
 return coalesce((with
  retenus as (select * from koki_foot.matchs m where m.competition_id=p_comp and m.publie and (coalesce(p_poule,'')='' or m.poule=p_poule)),
  participants as (
   select ce.equipe_id from koki_foot.competition_equipes ce where ce.competition_id=p_comp and (coalesce(p_poule,'')='' or ce.poule=p_poule)
   union select domicile_id from retenus union select exterieur_id from retenus),
  joues as (
   select date_match, domicile_id eq, score_domicile bp, score_exterieur bc from retenus where statut='Terminé'
   union all
   select date_match, exterieur_id, score_exterieur, score_domicile from retenus where statut='Terminé'),
  agg as (
   select p.equipe_id, count(j.eq)::int joues, count(*) filter (where j.bp>j.bc)::int g, count(*) filter (where j.bp=j.bc)::int n, count(*) filter (where j.bp<j.bc)::int pe,
    coalesce(sum(j.bp),0)::int bp, coalesce(sum(j.bc),0)::int bc,
    coalesce(right(string_agg(case when j.bp>j.bc then 'V' when j.bp=j.bc then 'N' else 'D' end,'' order by j.date_match),5),'') forme
   from participants p left join joues j on j.eq=p.equipe_id group by p.equipe_id),
  classe as (select a.*, a.g*3+a.n pts, e.nom, e from agg a join koki_foot.equipes e on e.id=a.equipe_id)
  select jsonb_agg(jsonb_build_object('rang',r.rang,'equipe',koki_foot.equipe_json(r.e),'poule',coalesce(p_poule,''),'joues',r.joues,'gagnes',r.g,'nuls',r.n,'perdus',r.pe,
   'buts_pour',r.bp,'buts_contre',r.bc,'diff',r.bp-r.bc,'points',r.pts,'forme',r.forme) order by r.rang)
  from (select classe.*, row_number() over (order by pts desc, bp-bc desc, bp desc, nom) rang from classe) r),'[]');
end $$;

-- ───────────── Diffusion en direct (Realtime Broadcast) ─────────────
-- Une erreur de diffusion ne bloque JAMAIS l'enregistrement d'un score.
create function koki_foot.diffuser(p_evenement text, p_charge jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then return; end if;
 begin
  execute 'select realtime.send($1,$2,$3,false)' using p_charge, p_evenement, 'koki-foot';
 exception when others then
  raise warning 'koki_foot : diffusion impossible (%)', sqlerrm;
 end;
end $$;
create function koki_foot.match_diffuse() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and (old.statut,old.minute,old.score_domicile,old.score_exterieur,old.pro_domicile,old.pro_exterieur,old.tab_domicile,old.tab_exterieur,old.publie,old.date_match,old.forfait_equipe_id)
    is not distinct from (new.statut,new.minute,new.score_domicile,new.score_exterieur,new.pro_domicile,new.pro_exterieur,new.tab_domicile,new.tab_exterieur,new.publie,new.date_match,new.forfait_equipe_id) then
  return null;
 end if;
 if not koki_foot.visible(new) and not (tg_op='UPDATE' and old.publie and not new.publie) then return null; end if;
 perform koki_foot.diffuser('match',jsonb_build_object('id',new.id,'revision',new.revision,'visible',koki_foot.visible(new),'statut',new.statut,'minute',new.minute,
  'score_domicile',new.score_domicile,'score_exterieur',new.score_exterieur,'pro_domicile',new.pro_domicile,'pro_exterieur',new.pro_exterieur,
  'tab_domicile',new.tab_domicile,'tab_exterieur',new.tab_exterieur,'date_match',new.date_match));
 return null;
end $$;
create trigger matchs_diffusion after insert or update on koki_foot.matchs for each row execute function koki_foot.match_diffuse();
create function koki_foot.evenement_diffuse() returns trigger language plpgsql security definer set search_path='' as $$
declare r koki_foot.evenements:=case when tg_op='DELETE' then old else new end; m koki_foot.matchs;
begin
 select * into m from koki_foot.matchs where id=r.match_id;
 if found and koki_foot.visible(m) then perform koki_foot.diffuser('evenement',jsonb_build_object('match_id',r.match_id,'revision',m.revision)); end if;
 return null;
end $$;
create trigger evenements_diffusion after insert or delete on koki_foot.evenements for each row execute function koki_foot.evenement_diffuse();

-- ───────────── Changements d'horaire (file pour les notifications futures) ─────────────
-- Match publié dont l'heure change (correction manuelle ou fournisseur) : inscrit une seule fois par
-- couple (ancienne, nouvelle). Les rappels déjà programmés devront être recalculés à partir de cette file.
create function koki_foot.horaire_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.date_match is distinct from old.date_match and koki_foot.visible(new) then
  insert into koki_foot.changements_horaire(match_id,ancienne,nouvelle,origine)
   values(new.id,old.date_match,new.date_match,case when current_setting('koki_foot.origine',true)='api' then 'api' else 'manuel' end)
  on conflict (match_id,ancienne,nouvelle) do nothing;
 end if;
 return null;
end $$;
create trigger matchs_horaire after update of date_match on koki_foot.matchs for each row execute function koki_foot.horaire_change();

-- ───────────── Lecture publique ─────────────
create function public.koki_foot_public(command text, input jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p text; c uuid; m koki_foot.matchs; begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>8192 then perform koki_foot.echec('Requête invalide'); end if;
 if command='accueil' then
  -- En jeu, à venir (7 jours) et résultats récents (7 jours), filtrables par portée.
  perform koki_foot.cles(input,'{portee}'); p:=nullif(koki_foot.t(input,'portee'),'');
  if p is not null and p not in ('Koki','Sénégal','International') then perform koki_foot.echec('Portée invalide'); end if;
  return jsonb_build_object(
   'direct',coalesce((select jsonb_agg(koki_foot.match_json(x) order by case c2.portee when 'Koki' then 0 when 'Sénégal' then 1 else 2 end, c2.ordre, x.date_match)
     from koki_foot.matchs x join koki_foot.competitions c2 on c2.id=x.competition_id where koki_foot.visible(x) and koki_foot.en_jeu(x.statut) and (p is null or c2.portee=p)),'[]'),
   'a_venir',coalesce((select jsonb_agg(koki_foot.match_json(y) order by y.date_match) from (select x.* from koki_foot.matchs x join koki_foot.competitions c2 on c2.id=x.competition_id
     where koki_foot.visible(x) and x.statut in ('À venir','Reporté') and x.date_match>=now()-interval '3 hours' and x.date_match<now()+interval '7 days' and (p is null or c2.portee=p) order by x.date_match limit 40) y),'[]'),
   'resultats',coalesce((select jsonb_agg(koki_foot.match_json(y) order by y.date_match desc) from (select x.* from koki_foot.matchs x join koki_foot.competitions c2 on c2.id=x.competition_id
     where koki_foot.visible(x) and x.statut in ('Terminé','Suspendu') and x.date_match>now()-interval '7 days' and (p is null or c2.portee=p) order by x.date_match desc limit 40) y),'[]'),
   'maintenant',now());
 elsif command='match' then
  perform koki_foot.cles(input,'{id}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id');
  if not found or not koki_foot.visible(m) then return null; end if;
  return koki_foot.match_json(m)||jsonb_build_object('evenements',coalesce((select jsonb_agg(koki_foot.evenement_json(v) order by koki_foot.rang_periode(v.periode), v.minute nulls first, v.minute_add nulls first, v.created_at)
   from koki_foot.evenements v where v.match_id=m.id),'[]'));
 elsif command='etat_matchs' then
  -- Resynchronisation après reconnexion : état actuel des matchs affichés (100 au plus).
  perform koki_foot.cles(input,'{ids}');
  if jsonb_typeof(input->'ids')<>'array' or jsonb_array_length(input->'ids')>100 then perform koki_foot.echec('Liste invalide'); end if;
  return coalesce((select jsonb_agg(koki_foot.match_json(x)) from koki_foot.matchs x
   where x.id in (select koki_foot.u(jsonb_build_object('v',e),'v') from jsonb_array_elements_text(input->'ids') e) and koki_foot.visible(x)),'[]');
 elsif command='sources' then
  -- État public des sources (sans secret) : dernière actualisation réussie et état.
  perform koki_foot.cles(input,'{}');
  return coalesce((select jsonb_agg(jsonb_build_object('fournisseur',x.fournisseur,'derniere_actualisation',x.derniere_reussite,'etat',koki_foot.etat_source(x)) order by x.fournisseur) from koki_foot.etat_fournisseurs x),'[]');
 elsif command='competitions' then
  perform koki_foot.cles(input,'{}');
  return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'nom',x.nom,'saison',x.saison,'portee',x.portee,'type',x.type,'logo_url',x.logo_url,'statut',x.statut,
   'poules',coalesce((select jsonb_agg(distinct ce.poule) from koki_foot.competition_equipes ce where ce.competition_id=x.id and ce.poule<>''),'[]'))
   order by case x.portee when 'Koki' then 0 when 'Sénégal' then 1 else 2 end, x.ordre, x.nom) from koki_foot.competitions x where x.publie and x.statut<>'archivée'),'[]');
 elsif command='matchs' then
  perform koki_foot.cles(input,'{competition_id}'); c:=koki_foot.u(input,'competition_id');
  if not exists(select 1 from koki_foot.competitions x where x.id=c and x.publie and x.statut<>'archivée') then return '[]'; end if;
  return coalesce((select jsonb_agg(koki_foot.match_json(y) order by y.date_match) from (select * from koki_foot.matchs x where x.competition_id=c and x.publie order by x.date_match limit 500) y),'[]');
 elsif command='classement' then
  perform koki_foot.cles(input,'{competition_id,poule}'); c:=koki_foot.u(input,'competition_id');
  if not exists(select 1 from koki_foot.competitions x where x.id=c and x.publie and x.statut<>'archivée') then return '[]'; end if;
  return koki_foot.classement(c,koki_foot.t(input,'poule'));
 end if;
 perform koki_foot.echec('Commande inconnue');
end $$;

-- ───────────── Administration ─────────────
create function koki_foot.corriger(p_match uuid, p_acteur uuid, p_action text, p_avant jsonb, p_apres jsonb, p_motif text) returns void language sql security definer set search_path='' as
$$ insert into koki_foot.corrections(match_id,acteur,action,avant,apres,motif) values(p_match,p_acteur,p_action,p_avant,p_apres,left(coalesce(p_motif,''),300)) $$;

-- Pose les verrous d'un match api après une correction (global + champs touchés).
create function koki_foot.verrouiller(p_match uuid, a uuid, champs text[], p_motif text) returns koki_foot.matchs language plpgsql security definer set search_path='' as $$
declare m koki_foot.matchs; avant jsonb; begin
 select * into m from koki_foot.matchs where id=p_match;
 if m.source<>'api' or cardinality(champs)=0 then return m; end if;
 avant:=koki_foot.verrous_json(m);
 update koki_foot.matchs set verrou_manuel=true,
  verrou_score=verrou_score or 'score'=any(champs), verrou_statut=verrou_statut or 'statut'=any(champs),
  verrou_evenements=verrou_evenements or 'evenements'=any(champs), verrou_programmation=verrou_programmation or 'programmation'=any(champs),
  resultat_source=case when 'score'=any(champs) or 'evenements'=any(champs) then 'correction' else resultat_source end,
  verrouille_par=a, verrouille_le=now()
 where id=p_match returning * into m;
 if avant<>koki_foot.verrous_json(m) then perform koki_foot.corriger(p_match,a,'verrou',avant,koki_foot.verrous_json(m),p_motif); end if;
 return m;
end $$;

-- Changement de statut / minute / scores d'un match. v : {statut, minute, score_*, pro_*, tab_*}.
-- Motif obligatoire pour un match api ou déjà terminé (sauf minute seule). Statut hors « Terminé » : forfait levé.
create function koki_foot.appliquer_score(m koki_foot.matchs, a uuid, v jsonb, p_motif text) returns koki_foot.matchs
language plpgsql security definer set search_path='' as $$
declare r koki_foot.matchs; avant jsonb; apres jsonb; st text; mi integer; sd integer; se integer; pd integer; pe integer; td integer; te integer; champs text[]:='{}';
begin
 st:=coalesce(koki_foot.t(v,'statut'),m.statut);
 if st not in ('À venir','En direct','Mi-temps','Prolongations','Tirs au but','Terminé','Reporté','Annulé','Interrompu','Suspendu') then perform koki_foot.echec('Statut invalide'); end if;
 mi:=case when v ? 'minute' then koki_foot.i(v,'minute') else m.minute end;
 sd:=case when v ? 'score_domicile' then koki_foot.i(v,'score_domicile') else m.score_domicile end; se:=case when v ? 'score_exterieur' then koki_foot.i(v,'score_exterieur') else m.score_exterieur end;
 pd:=case when v ? 'pro_domicile' then koki_foot.i(v,'pro_domicile') else m.pro_domicile end; pe:=case when v ? 'pro_exterieur' then koki_foot.i(v,'pro_exterieur') else m.pro_exterieur end;
 td:=case when v ? 'tab_domicile' then koki_foot.i(v,'tab_domicile') else m.tab_domicile end; te:=case when v ? 'tab_exterieur' then koki_foot.i(v,'tab_exterieur') else m.tab_exterieur end;
 if (sd is null)<>(se is null) or (pd is null)<>(pe is null) or (td is null)<>(te is null) then perform koki_foot.echec('Indiquez le score des deux équipes'); end if;
 if st='Terminé' and sd is null then perform koki_foot.echec('Score requis pour un match terminé'); end if;
 if koki_foot.en_jeu(st) and sd is null then sd:=0; se:=0; end if;
 if st='Prolongations' and pd is null then pd:=0; pe:=0; end if;
 if st='Tirs au but' and td is null then td:=0; te:=0; end if;
 if (pd is not null or td is not null) and exists(select 1 from koki_foot.competitions where id=m.competition_id and type='Championnat') then
  perform koki_foot.echec('Pas de prolongation ni de tirs au but en championnat');
 end if;
 if not koki_foot.en_jeu(st) then mi:=null; end if;
 avant:=jsonb_build_object('statut',m.statut,'score',jsonb_build_array(m.score_domicile,m.score_exterieur,m.pro_domicile,m.pro_exterieur,m.tab_domicile,m.tab_exterieur),'forfait',m.forfait_equipe_id);
 apres:=jsonb_build_object('statut',st,'score',jsonb_build_array(sd,se,pd,pe,td,te),'forfait',case when st='Terminé' then m.forfait_equipe_id end);
 if avant->'score'<>apres->'score' then champs:=champs||'score'::text; end if;
 if avant->'statut'<>apres->'statut' then champs:=champs||'statut'::text; end if;
 if cardinality(champs)=0 and m.minute is not distinct from mi then return m; end if;
 if cardinality(champs)>0 and (m.source='api' or m.statut='Terminé') then perform koki_foot.motif_requis(p_motif); end if;
 update koki_foot.matchs set statut=st, minute=mi, score_domicile=sd, score_exterieur=se, pro_domicile=pd, pro_exterieur=pe, tab_domicile=td, tab_exterieur=te,
  forfait_equipe_id=case when st='Terminé' then forfait_equipe_id end
 where id=m.id returning * into r;
 if cardinality(champs)>0 then
  perform koki_foot.corriger(m.id,a,case when champs=array['statut'] then 'statut' else 'score' end,avant,apres,p_motif);
  r:=koki_foot.verrouiller(m.id,a,champs,p_motif);
 end if;
 return r;
end $$;

-- Score à appliquer pour un événement ajouté (+1) ou retiré (-1), selon sa PÉRIODE : mi-temps => score
-- réglementaire, prolongation => pro_*, séance de tirs au but (tab_reussi) => tab_*. Autres types : aucun effet.
create function koki_foot.effet_but(m koki_foot.matchs, v koki_foot.evenements, sens integer) returns jsonb language plpgsql stable set search_path='' as $$
declare pour_dom boolean; cle text; o jsonb;
begin
 if v.equipe_id is null or v.type not in ('but','penalty','but_csc','tab_reussi') then return null; end if;
 pour_dom:=(v.type='but_csc')<>(v.equipe_id=m.domicile_id);
 o:=jsonb_build_object('score_domicile',coalesce(m.score_domicile,0),'score_exterieur',coalesce(m.score_exterieur,0));
 if v.periode in ('prolongation_1','prolongation_2') or m.pro_domicile is not null then
  o:=o||jsonb_build_object('pro_domicile',coalesce(m.pro_domicile,0),'pro_exterieur',coalesce(m.pro_exterieur,0)); end if;
 if v.periode='tirs_au_but' or m.tab_domicile is not null then
  o:=o||jsonb_build_object('tab_domicile',coalesce(m.tab_domicile,0),'tab_exterieur',coalesce(m.tab_exterieur,0)); end if;
 cle:=case when v.periode in ('mi_temps_1','mi_temps_2') then 'score_' when v.periode='tirs_au_but' then 'tab_' else 'pro_' end
   ||case when pour_dom then 'domicile' else 'exterieur' end;
 return jsonb_set(o,array[cle],to_jsonb(greatest((o->>cle)::int+sens,0)));
end $$;

create function public.koki_foot_admin(command text, input jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; c koki_foot.competitions; e koki_foot.equipes; m koki_foot.matchs; n2 koki_foot.matchs; v koki_foot.evenements; k koki_foot.conflits;
 id_ uuid; eff jsonb; liste text[]; avant jsonb; begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>32768 then perform koki_foot.echec('Requête invalide ou trop volumineuse'); end if;

 -- ── Lecture ──
 if command='etat' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{depuis}');
  return jsonb_build_object(
   'competitions',coalesce((select jsonb_agg(to_jsonb(x) order by x.portee, x.ordre, x.nom) from koki_foot.competitions x),'[]'),
   'equipes',coalesce((select jsonb_agg(to_jsonb(x) order by x.nom) from koki_foot.equipes x where x.source='manuel' or exists(select 1 from koki_foot.competition_equipes ce join koki_foot.competitions c2 on c2.id=ce.competition_id where ce.equipe_id=x.id and c2.publie)),'[]'),
   'inscriptions',coalesce((select jsonb_agg(to_jsonb(x)) from koki_foot.competition_equipes x join koki_foot.competitions c2 on c2.id=x.competition_id where c2.source='manuel'),'[]'),
   'matchs',coalesce((select jsonb_agg(koki_foot.match_json(x)||jsonb_build_object('publie',x.publie,'verrous',koki_foot.verrous_json(x),'coherence',koki_foot.coherence(x),
      'conflits',(select count(*) from koki_foot.conflits k2 where k2.match_id=x.id and not k2.resolu)) order by x.date_match)
     from koki_foot.matchs x where x.date_match>=coalesce(koki_foot.ts(input,'depuis'),now()-interval '30 days') and x.date_match<now()+interval '60 days'
      and (x.source='manuel' or koki_foot.en_jeu(x.statut) or exists(select 1 from koki_foot.competitions c2 where c2.id=x.competition_id and c2.publie))),'[]'),
   'conflits_ouverts',(select count(*) from koki_foot.conflits where not resolu),
   'fournisseurs',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('etat',koki_foot.etat_source(x))) from koki_foot.etat_fournisseurs x),'[]'),
   'changements_horaire_a_traiter',(select count(*) from koki_foot.changements_horaire where traite_le is null),
   'synchronisations',coalesce((select jsonb_agg(to_jsonb(y) order by y.created_at desc) from (select * from koki_foot.synchronisations order by created_at desc limit 20) y),'[]'));
 elsif command='evenements' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{match_id}');
  return coalesce((select jsonb_agg(koki_foot.evenement_json(x)||jsonb_build_object('source',x.source) order by koki_foot.rang_periode(x.periode), x.minute nulls first, x.minute_add nulls first, x.created_at) from koki_foot.evenements x where x.match_id=koki_foot.u(input,'match_id')),'[]');
 elsif command='corrections' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{match_id}');
  return coalesce((select jsonb_agg(to_jsonb(y) order by y.created_at desc) from (select x.*, (select u.email from auth.users u where u.id=x.acteur) acteur_email from koki_foot.corrections x
   where koki_foot.u(input,'match_id') is null or x.match_id=koki_foot.u(input,'match_id') order by x.created_at desc limit 200) y),'[]');
 elsif command='conflits' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{tous}');
  return coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('match',koki_foot.match_json(mm)) order by x.dernier_vu desc) from koki_foot.conflits x join koki_foot.matchs mm on mm.id=x.match_id
   where koki_foot.b(input,'tous',false) or not x.resolu),'[]');
 elsif command='programmation' then
  -- Valeur publiée, dernière valeur du fournisseur et historique des deux.
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{match_id}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'match_id'); if not found then perform koki_foot.echec('Match introuvable'); end if;
  return jsonb_build_object('publiee',jsonb_build_object('date_match',m.date_match,'lieu',m.lieu),'fournisseur',jsonb_build_object('date_match',m.api_date_match,'lieu',m.api_lieu),
   'verrou_programmation',m.verrou_programmation,
   'historique',coalesce((select jsonb_agg(to_jsonb(h) order by h.id) from koki_foot.historique_programmation h where h.match_id=m.id),'[]'),
   'changements_horaire',coalesce((select jsonb_agg(to_jsonb(c2) order by c2.id) from koki_foot.changements_horaire c2 where c2.match_id=m.id),'[]'));
 elsif command='verifier_journal' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{}');
  return jsonb_build_object('premiere_alteration',koki_foot.verifier_journal(),'lignes',(select count(*) from koki_foot.corrections));
 elsif command='classement' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{competition_id,poule}');
  return koki_foot.classement(koki_foot.u(input,'competition_id'),koki_foot.t(input,'poule'));
 end if;

 -- ── Réglages des sources (superadmin seulement) ──
 if command='regler_source' then
  a:=koki_foot.exiger('superadmin'); perform koki_foot.cles(input,'{fournisseur,seuil_ancien_s,attente_debut_s}');
  if koki_foot.t(input,'fournisseur') not in ('api-football','sportmonks') or koki_foot.t(input,'fournisseur') is null then perform koki_foot.echec('Fournisseur invalide'); end if;
  insert into koki_foot.etat_fournisseurs(fournisseur) values(koki_foot.t(input,'fournisseur')) on conflict do nothing;
  update koki_foot.etat_fournisseurs set seuil_ancien_s=coalesce(koki_foot.i(input,'seuil_ancien_s'),seuil_ancien_s), attente_debut_s=coalesce(koki_foot.i(input,'attente_debut_s'),attente_debut_s)
   where fournisseur=koki_foot.t(input,'fournisseur');
  return (select to_jsonb(x) from koki_foot.etat_fournisseurs x where fournisseur=koki_foot.t(input,'fournisseur'));
 end if;

 -- ── Écriture ──
 a:=koki_foot.exiger('content');

 if command='enregistrer_competition' then
  perform koki_foot.cles(input,'{id,revision,nom,saison,portee,type,statut,publie,ordre}');
  id_:=koki_foot.u(input,'id');
  if id_ is null then
   insert into koki_foot.competitions(nom,saison,portee,type,statut,publie,ordre) values(koki_foot.t(input,'nom'),coalesce(koki_foot.t(input,'saison'),''),coalesce(koki_foot.t(input,'portee'),'Koki'),
    coalesce(koki_foot.t(input,'type'),'Championnat'),coalesce(koki_foot.t(input,'statut'),'active'),koki_foot.b(input,'publie',false),coalesce(koki_foot.i(input,'ordre'),100)) returning * into c;
  else
   select * into c from koki_foot.competitions where id=id_ for update; if not found then perform koki_foot.echec('Compétition introuvable'); end if;
   perform koki_foot.revision(koki_foot.i(input,'revision'),c.revision);
   -- Compétition api : nom, saison et type viennent du fournisseur ; seuls l'affichage et la portée se règlent ici.
   update koki_foot.competitions set nom=case when source='manuel' then coalesce(koki_foot.t(input,'nom'),nom) else nom end, saison=case when source='manuel' then coalesce(koki_foot.t(input,'saison'),saison) else saison end,
    type=case when source='manuel' then coalesce(koki_foot.t(input,'type'),type) else type end, portee=coalesce(koki_foot.t(input,'portee'),portee), statut=coalesce(koki_foot.t(input,'statut'),statut),
    publie=koki_foot.b(input,'publie',publie), ordre=coalesce(koki_foot.i(input,'ordre'),ordre) where id=id_ returning * into c;
  end if;
  return to_jsonb(c);

 elsif command='enregistrer_equipe' then
  perform koki_foot.cles(input,'{id,revision,nom,nom_court,portee,quartier,couleurs,statut}');
  id_:=koki_foot.u(input,'id');
  if input ? 'couleurs' and jsonb_typeof(input->'couleurs')<>'array' then perform koki_foot.echec('Couleurs invalides'); end if;
  if id_ is null then
   insert into koki_foot.equipes(nom,nom_court,portee,quartier,couleurs,statut) values(koki_foot.t(input,'nom'),coalesce(koki_foot.t(input,'nom_court'),''),coalesce(koki_foot.t(input,'portee'),'Koki'),
    coalesce(koki_foot.t(input,'quartier'),''),coalesce((select array_agg(lower(x)) from jsonb_array_elements_text(input->'couleurs') x),'{"#087a3d"}'),coalesce(koki_foot.t(input,'statut'),'active')) returning * into e;
  else
   select * into e from koki_foot.equipes where id=id_ for update; if not found then perform koki_foot.echec('Équipe introuvable'); end if;
   perform koki_foot.revision(koki_foot.i(input,'revision'),e.revision);
   update koki_foot.equipes set nom=case when source='manuel' then coalesce(koki_foot.t(input,'nom'),nom) else nom end, nom_court=coalesce(koki_foot.t(input,'nom_court'),nom_court),
    portee=coalesce(koki_foot.t(input,'portee'),portee), quartier=coalesce(koki_foot.t(input,'quartier'),quartier), statut=coalesce(koki_foot.t(input,'statut'),statut),
    couleurs=coalesce((select array_agg(lower(x)) from jsonb_array_elements_text(input->'couleurs') x),couleurs) where id=id_ returning * into e;
  end if;
  return to_jsonb(e);

 elsif command in ('inscrire_equipe','retirer_equipe') then
  perform koki_foot.cles(input,'{competition_id,equipe_id,poule}');
  select * into c from koki_foot.competitions where id=koki_foot.u(input,'competition_id');
  if not found or c.source<>'manuel' then perform koki_foot.echec('Compétition manuelle introuvable'); end if;
  if command='inscrire_equipe' then
   insert into koki_foot.competition_equipes(competition_id,equipe_id,poule) values(c.id,koki_foot.u(input,'equipe_id'),coalesce(koki_foot.t(input,'poule'),''))
    on conflict (competition_id,equipe_id) do update set poule=excluded.poule;
  else
   delete from koki_foot.competition_equipes where competition_id=c.id and equipe_id=koki_foot.u(input,'equipe_id');
  end if;
  return jsonb_build_object('ok',true);

 elsif command='enregistrer_match' then
  perform koki_foot.cles(input,'{id,revision,competition_id,domicile_id,exterieur_id,date_match,lieu,poule,journee,statut,minute,score_domicile,score_exterieur,pro_domicile,pro_exterieur,tab_domicile,tab_exterieur,commentaire,publie,motif}');
  id_:=koki_foot.u(input,'id');
  if id_ is null then
   select * into c from koki_foot.competitions where id=koki_foot.u(input,'competition_id');
   if not found or c.source<>'manuel' then perform koki_foot.echec('Choisissez une compétition locale (les matchs des compétitions importées viennent du fournisseur)'); end if;
   if exists(select 1 from koki_foot.equipes x where x.id in (koki_foot.u(input,'domicile_id'),koki_foot.u(input,'exterieur_id')) and x.statut<>'active') then perform koki_foot.echec('Équipe archivée'); end if;
   if koki_foot.ts(input,'date_match') is null then perform koki_foot.echec('Date du match requise'); end if;
   insert into koki_foot.matchs(competition_id,domicile_id,exterieur_id,date_match,lieu,poule,journee,statut,commentaire,publie)
    values(c.id,koki_foot.u(input,'domicile_id'),koki_foot.u(input,'exterieur_id'),koki_foot.ts(input,'date_match'),coalesce(koki_foot.t(input,'lieu'),''),coalesce(koki_foot.t(input,'poule'),''),
     coalesce(koki_foot.t(input,'journee'),''),'À venir',coalesce(koki_foot.t(input,'commentaire'),''),koki_foot.b(input,'publie',false)) returning * into m;
   perform koki_foot.corriger(m.id,a,'match','{}',jsonb_build_object('creation',true),'');
  else
   select * into m from koki_foot.matchs where id=id_ for update; if not found then perform koki_foot.echec('Match introuvable'); end if;
   perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
   if m.source='manuel' then
    update koki_foot.matchs set domicile_id=coalesce(koki_foot.u(input,'domicile_id'),domicile_id), exterieur_id=coalesce(koki_foot.u(input,'exterieur_id'),exterieur_id),
     date_match=coalesce(koki_foot.ts(input,'date_match'),date_match), lieu=coalesce(koki_foot.t(input,'lieu'),lieu), poule=coalesce(koki_foot.t(input,'poule'),poule),
     journee=coalesce(koki_foot.t(input,'journee'),journee), commentaire=coalesce(koki_foot.t(input,'commentaire'),commentaire), publie=koki_foot.b(input,'publie',publie)
    where id=m.id returning * into n2;
    if (n2.date_match,n2.lieu) is distinct from (m.date_match,m.lieu) then
     insert into koki_foot.historique_programmation(match_id,origine,date_match,lieu,motif,acteur) values(m.id,'manuel',n2.date_match,n2.lieu,left(coalesce(koki_foot.t(input,'motif'),''),300),a);
    end if;
    m:=n2;
   else
    -- Match importé : équipes, compétition, journée et poule suivent le fournisseur. Date et lieu corrigeables
    -- (verrou de programmation + motif) ; commentaire et publication libres.
    if input ? 'domicile_id' or input ? 'exterieur_id' or input ? 'competition_id' or input ? 'journee' or input ? 'poule' then
     perform koki_foot.echec('Match importé : équipes, compétition, journée et poule suivent le fournisseur');
    end if;
    avant:=jsonb_build_object('date_match',m.date_match,'lieu',m.lieu);
    if (input ? 'date_match' and koki_foot.ts(input,'date_match') is distinct from m.date_match) or (input ? 'lieu' and koki_foot.t(input,'lieu') is distinct from m.lieu) then
     perform koki_foot.motif_requis(koki_foot.t(input,'motif'));
     update koki_foot.matchs set date_match=coalesce(koki_foot.ts(input,'date_match'),date_match), lieu=coalesce(koki_foot.t(input,'lieu'),lieu) where id=m.id returning * into m;
     perform koki_foot.corriger(m.id,a,'programmation',avant||jsonb_build_object('api_date_match',m.api_date_match,'api_lieu',m.api_lieu),jsonb_build_object('date_match',m.date_match,'lieu',m.lieu),koki_foot.t(input,'motif'));
     insert into koki_foot.historique_programmation(match_id,origine,date_match,lieu,motif,acteur) values(m.id,'manuel',m.date_match,m.lieu,left(koki_foot.t(input,'motif'),300),a);
     m:=koki_foot.verrouiller(m.id,a,array['programmation'],koki_foot.t(input,'motif'));
    end if;
    update koki_foot.matchs set commentaire=coalesce(koki_foot.t(input,'commentaire'),commentaire), publie=koki_foot.b(input,'publie',publie) where id=m.id returning * into m;
   end if;
  end if;
  if input ? 'statut' then
   m:=koki_foot.appliquer_score(m,a,input-'id'-'revision'-'motif'-'competition_id'-'domicile_id'-'exterieur_id'-'date_match'-'lieu'-'poule'-'journee'-'commentaire'-'publie',koki_foot.t(input,'motif'));
  end if;
  return koki_foot.match_json(m)||jsonb_build_object('publie',m.publie,'verrous',koki_foot.verrous_json(m));

 elsif command='score' then
  -- Saisie rapide depuis le terrain : statut, minute et scores en un geste.
  perform koki_foot.cles(input,'{id,revision,statut,minute,score_domicile,score_exterieur,pro_domicile,pro_exterieur,tab_domicile,tab_exterieur,motif}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id') for update; if not found then perform koki_foot.echec('Match introuvable'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  m:=koki_foot.appliquer_score(m,a,input-'id'-'revision'-'motif',koki_foot.t(input,'motif'));
  return koki_foot.match_json(m)||jsonb_build_object('publie',m.publie,'verrous',koki_foot.verrous_json(m));

 elsif command='forfait' then
  -- Forfait : match terminé, résultat officiel saisi (ex. 3–0), équipe forfait notée.
  perform koki_foot.cles(input,'{id,revision,equipe_id,score_domicile,score_exterieur,motif}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id') for update; if not found then perform koki_foot.echec('Match introuvable'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  perform koki_foot.motif_requis(koki_foot.t(input,'motif'));
  if koki_foot.u(input,'equipe_id') is null or koki_foot.u(input,'equipe_id') not in (m.domicile_id,m.exterieur_id) then perform koki_foot.echec('Équipe forfait : une des deux équipes du match'); end if;
  if koki_foot.i(input,'score_domicile') is null or koki_foot.i(input,'score_exterieur') is null then perform koki_foot.echec('Résultat officiel requis'); end if;
  avant:=jsonb_build_object('statut',m.statut,'score',jsonb_build_array(m.score_domicile,m.score_exterieur),'forfait',m.forfait_equipe_id);
  update koki_foot.matchs set statut='Terminé', minute=null, score_domicile=koki_foot.i(input,'score_domicile'), score_exterieur=koki_foot.i(input,'score_exterieur'),
   pro_domicile=null, pro_exterieur=null, tab_domicile=null, tab_exterieur=null, forfait_equipe_id=koki_foot.u(input,'equipe_id') where id=m.id returning * into m;
  perform koki_foot.corriger(m.id,a,'forfait',avant,jsonb_build_object('statut',m.statut,'score',jsonb_build_array(m.score_domicile,m.score_exterieur),'forfait',m.forfait_equipe_id),koki_foot.t(input,'motif'));
  m:=koki_foot.verrouiller(m.id,a,array['score','statut'],koki_foot.t(input,'motif'));
  return koki_foot.match_json(m)||jsonb_build_object('verrous',koki_foot.verrous_json(m));

 elsif command='rejouer' then
  -- Match manuel à rejouer : l'original passe « Annulé » (hors classement), un nouveau match est programmé.
  perform koki_foot.cles(input,'{id,revision,date_match,lieu,motif}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id') for update; if not found then perform koki_foot.echec('Match introuvable'); end if;
  if m.source<>'manuel' then perform koki_foot.echec('Match importé : le fournisseur publie le match rejoué'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  perform koki_foot.motif_requis(koki_foot.t(input,'motif'));
  if koki_foot.ts(input,'date_match') is null then perform koki_foot.echec('Date du match rejoué requise'); end if;
  if exists(select 1 from koki_foot.matchs where rejoue_de=m.id and statut<>'Annulé') then perform koki_foot.echec('Ce match a déjà été reprogrammé'); end if;
  avant:=jsonb_build_object('statut',m.statut,'score',jsonb_build_array(m.score_domicile,m.score_exterieur));
  update koki_foot.matchs set statut='Annulé', minute=null, forfait_equipe_id=null where id=m.id returning * into m;
  insert into koki_foot.matchs(competition_id,domicile_id,exterieur_id,date_match,lieu,poule,journee,statut,publie,rejoue_de)
   values(m.competition_id,m.domicile_id,m.exterieur_id,koki_foot.ts(input,'date_match'),coalesce(koki_foot.t(input,'lieu'),m.lieu),m.poule,m.journee,'À venir',m.publie,m.id) returning * into n2;
  perform koki_foot.corriger(m.id,a,'rejoue',avant,jsonb_build_object('statut','Annulé','nouveau_match',n2.id,'date_match',n2.date_match),koki_foot.t(input,'motif'));
  return jsonb_build_object('annule',koki_foot.match_json(m),'nouveau',koki_foot.match_json(n2));

 elsif command='ajouter_evenement' then
  -- Un but met aussi le score à jour selon sa PÉRIODE (mi-temps : réglementaire ; prolongation : pro_* ; séance : tab_*),
  -- sauf maj_score=false. Match api : motif obligatoire, verrous « événements » (et « score »).
  perform koki_foot.cles(input,'{match_id,revision,type,periode,minute,minute_add,equipe_id,joueur,joueur2,maj_score,motif}');
  if koki_foot.t(input,'periode') is null then perform koki_foot.echec('Période requise (mi_temps_1, mi_temps_2, prolongation_1, prolongation_2, tirs_au_but)'); end if;
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'match_id') for update; if not found then perform koki_foot.echec('Match introuvable'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  if m.source='api' then perform koki_foot.motif_requis(koki_foot.t(input,'motif')); end if;
  if koki_foot.t(input,'periode')<>all(array['mi_temps_1','mi_temps_2']) and exists(select 1 from koki_foot.competitions where id=m.competition_id and type='Championnat') then
   perform koki_foot.echec('Pas de prolongation ni de tirs au but en championnat');
  end if;
  insert into koki_foot.evenements(match_id,type,periode,minute,minute_add,equipe_id,joueur,joueur2,source,auteur)
   values(m.id,koki_foot.t(input,'type'),koki_foot.t(input,'periode'),koki_foot.i(input,'minute'),koki_foot.i(input,'minute_add'),koki_foot.u(input,'equipe_id'),coalesce(koki_foot.t(input,'joueur'),''),coalesce(koki_foot.t(input,'joueur2'),''),'manuel',a)
   returning * into v;
  perform koki_foot.corriger(m.id,a,'evenement_ajout','{}',koki_foot.evenement_json(v),koki_foot.t(input,'motif'));
  m:=koki_foot.verrouiller(m.id,a,array['evenements'],koki_foot.t(input,'motif'));
  eff:=koki_foot.effet_but(m,v,1);
  if koki_foot.b(input,'maj_score',true) and eff is not null then
   m:=koki_foot.appliquer_score(m,a,eff||jsonb_build_object('statut',case when m.statut in ('À venir','Reporté') then 'En direct' when v.periode='tirs_au_but' and koki_foot.en_jeu(m.statut) then 'Tirs au but' else m.statut end,'minute',m.minute),koki_foot.t(input,'motif'));
  end if;
  return jsonb_build_object('evenement',koki_foot.evenement_json(v),'match',koki_foot.match_json(m)||jsonb_build_object('verrous',koki_foot.verrous_json(m),'coherence',koki_foot.coherence(m)));

 elsif command='retirer_evenement' then
  -- Annulation d'un événement (but refusé, erreur de saisie). Événement api : retiré ET match verrouillé
  -- (« événements ») pour que la synchronisation ne le réintroduise pas.
  perform koki_foot.cles(input,'{id,maj_score,motif}');
  select * into v from koki_foot.evenements where id=koki_foot.u(input,'id'); if not found then perform koki_foot.echec('Événement introuvable'); end if;
  perform koki_foot.motif_requis(koki_foot.t(input,'motif'));
  select * into m from koki_foot.matchs where id=v.match_id for update;
  delete from koki_foot.evenements where id=v.id;
  perform koki_foot.corriger(m.id,a,'evenement_retrait',koki_foot.evenement_json(v)||jsonb_build_object('source',v.source,'cle',v.cle),'{}',koki_foot.t(input,'motif'));
  m:=koki_foot.verrouiller(m.id,a,array['evenements'],koki_foot.t(input,'motif'));
  eff:=koki_foot.effet_but(m,v,-1);
  if koki_foot.b(input,'maj_score',true) and eff is not null and m.score_domicile is not null then
   m:=koki_foot.appliquer_score(m,a,eff||jsonb_build_object('statut',m.statut,'minute',m.minute),koki_foot.t(input,'motif'));
  end if;
  return koki_foot.match_json(m)||jsonb_build_object('verrous',koki_foot.verrous_json(m),'coherence',koki_foot.coherence(m));

 elsif command='deverrouiller' then
  -- Rend la main au fournisseur, pour tous les champs ou ceux indiqués.
  perform koki_foot.cles(input,'{id,revision,motif,verrous}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id') for update;
  if not found or not (m.verrou_manuel or m.verrou_score or m.verrou_statut or m.verrou_evenements or m.verrou_programmation) then perform koki_foot.echec('Match non verrouillé'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  perform koki_foot.motif_requis(koki_foot.t(input,'motif'));
  if input ? 'verrous' and (jsonb_typeof(input->'verrous')<>'array' or jsonb_array_length(input->'verrous')=0) then perform koki_foot.echec('verrous : liste non vide attendue'); end if;
  liste:=coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(input->'verrous','["score","statut","evenements","programmation"]')) x),'{}');
  if not liste<@array['score','statut','evenements','programmation'] then perform koki_foot.echec('Verrou inconnu'); end if;
  avant:=koki_foot.verrous_json(m);
  update koki_foot.matchs set verrou_score=verrou_score and not 'score'=any(liste), verrou_statut=verrou_statut and not 'statut'=any(liste),
   verrou_evenements=verrou_evenements and not 'evenements'=any(liste), verrou_programmation=verrou_programmation and not 'programmation'=any(liste)
  where id=m.id returning * into m;
  -- Le verrou global ne tombe que lorsque plus aucun verrou de champ n'est posé.
  update koki_foot.matchs set verrou_manuel=false, verrouille_par=null, verrouille_le=null,
   resultat_source=case when not verrou_score and not verrou_evenements then 'api' else resultat_source end
  where id=m.id and not (verrou_score or verrou_statut or verrou_evenements or verrou_programmation) returning * into n2;
  if found then m:=n2; end if;
  perform koki_foot.corriger(m.id,a,'deverrou',avant,koki_foot.verrous_json(m),koki_foot.t(input,'motif'));
  return koki_foot.match_json(m)||jsonb_build_object('verrous',koki_foot.verrous_json(m));

 elsif command='resoudre_conflit' then
  -- garder : la valeur corrigée reste, verrou maintenu. accepter_api : le verrou du champ est levé,
  -- la prochaine synchronisation applique la valeur du fournisseur.
  perform koki_foot.cles(input,'{id,decision,motif}');
  select * into k from koki_foot.conflits where id=koki_foot.i(input,'id') and not resolu for update; if not found then perform koki_foot.echec('Conflit introuvable ou déjà résolu'); end if;
  if koki_foot.t(input,'decision') is null or koki_foot.t(input,'decision') not in ('garder','accepter_api') then perform koki_foot.echec('Décision : garder ou accepter_api'); end if;
  perform koki_foot.motif_requis(koki_foot.t(input,'motif'));
  update koki_foot.conflits set resolu=true, resolu_par=a, resolu_le=now(), decision=koki_foot.t(input,'decision') where id=k.id;
  select * into m from koki_foot.matchs where id=k.match_id for update;
  if koki_foot.t(input,'decision')='accepter_api' then
   avant:=koki_foot.verrous_json(m);
   update koki_foot.matchs set verrou_score=verrou_score and k.champ<>'score', verrou_statut=verrou_statut and k.champ<>'statut',
    verrou_evenements=verrou_evenements and k.champ<>'evenements', verrou_programmation=verrou_programmation and k.champ<>'programmation' where id=m.id returning * into m;
   update koki_foot.matchs set verrou_manuel=false, verrouille_par=null, verrouille_le=null where id=m.id and not (verrou_score or verrou_statut or verrou_evenements or verrou_programmation) returning * into n2;
   if found then m:=n2; end if;
   perform koki_foot.corriger(m.id,a,'conflit_api',jsonb_build_object('champ',k.champ,'verrous',avant,'valeur_locale',k.valeur_locale),jsonb_build_object('valeur_api',k.valeur_api,'verrous',koki_foot.verrous_json(m)),koki_foot.t(input,'motif'));
  else
   perform koki_foot.corriger(m.id,a,'conflit_garde',jsonb_build_object('champ',k.champ,'valeur_api',k.valeur_api),jsonb_build_object('valeur_locale',k.valeur_locale),koki_foot.t(input,'motif'));
  end if;
  return koki_foot.match_json(m)||jsonb_build_object('verrous',koki_foot.verrous_json(m));
 end if;

 perform koki_foot.echec('Commande inconnue');
end $$;

-- ───────────── Synchronisation (service_role seulement) ─────────────
-- Divergence sur une valeur verrouillée : conflit ouvert (ou mis à jour), jamais d'écrasement silencieux.
create function koki_foot.signaler_conflit(p_match uuid, p_champ text, p_locale jsonb, p_api jsonb) returns void language sql security definer set search_path='' as $$
 insert into koki_foot.conflits(match_id,champ,valeur_locale,valeur_api) values(p_match,p_champ,p_locale,p_api)
 on conflict (match_id,champ) where not resolu do update set valeur_locale=excluded.valeur_locale, valeur_api=excluded.valeur_api, dernier_vu=now(), occurrences=koki_foot.conflits.occurrences+1
$$;

create function public.koki_foot_sync(command text, input jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare f text; op text; x jsonb; lus integer:=0; crees integer:=0; maj integer:=0; verrou integer:=0; rejet integer:=0; erreurs text[]:='{}'; st text;
 cid uuid; d uuid; ex uuid; m koki_foot.matchs; nouveau boolean; rid bigint; comps uuid[]:='{}'; code_ text; pause timestamptz; ef koki_foot.etat_fournisseurs;
 l_sc boolean; l_st boolean; l_ev boolean; l_pr boolean; api_score jsonb; api_statut text; api_prog jsonb; nb integer;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Réservé à la synchronisation serveur' using errcode='42501'; end if;
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>4194304 then perform koki_foot.echec('Requête invalide ou trop volumineuse'); end if;
 f:=koki_foot.t(input,'fournisseur'); op:=left(coalesce(koki_foot.t(input,'operation'),command),60);
 if f is null or f not in ('api-football','sportmonks') then perform koki_foot.echec('Fournisseur invalide'); end if;
 -- Une seule synchronisation à la fois par fournisseur : la seconde attend la fin de la première.
 perform pg_advisory_xact_lock(hashtext('koki_foot_sync:'||f));
 insert into koki_foot.etat_fournisseurs(fournisseur) values(f) on conflict do nothing;
 -- Origine des changements d'horaire inscrits par le déclencheur (transaction courante seulement).
 perform set_config('koki_foot.origine','api',true);

 if command='references' then
  -- Ce que la synchronisation doit suivre, et si elle doit attendre (panne, quota).
  select * into ef from koki_foot.etat_fournisseurs where fournisseur=f;
  return jsonb_build_object('pause_jusqu_a',case when ef.pause_jusqu_a>now() then ef.pause_jusqu_a end,'erreurs_consecutives',ef.erreurs_consecutives,'quota_restant',ef.quota_restant,
   'competitions',coalesce((select jsonb_agg(jsonb_build_object('ref',c.ref_fournisseur,'saison',c.saison)) from koki_foot.competitions c where c.fournisseur=f and c.publie and c.statut='active'),'[]'),
   'matchs_a_suivre',coalesce((select jsonb_agg(m2.ref_fournisseur) from koki_foot.matchs m2 join koki_foot.competitions c on c.id=m2.competition_id
     where m2.fournisseur=f and c.publie and (koki_foot.en_jeu(m2.statut) or (m2.statut='À venir' and m2.date_match between now()-interval '3 hours' and now()+interval '15 minutes'))),'[]'));

 elsif command='erreur' then
  -- API indisponible, quota dépassé… : journal + pause progressive (1, 2, 4… 60 min) ou date fournie.
  perform koki_foot.cles(input,'{fournisseur,operation,code,message,reessayer_apres}');
  code_:=coalesce(koki_foot.t(input,'code'),'autre');
  if code_ not in ('indisponible','quota','authentification','donnees','delai','autre') then perform koki_foot.echec('Code d''erreur invalide'); end if;
  update koki_foot.etat_fournisseurs set erreurs_consecutives=erreurs_consecutives+1, derniere_erreur=now(), derniere_erreur_code=code_, derniere_tentative=now() where fournisseur=f returning * into ef;
  pause:=coalesce(koki_foot.ts(input,'reessayer_apres'),case code_
   when 'quota' then (date_trunc('day',now() at time zone 'UTC')+interval '1 day') at time zone 'UTC'
   when 'authentification' then now()+interval '24 hours'
   else now()+make_interval(mins=>least(60,(2^least(ef.erreurs_consecutives-1,6))::int)) end);
  update koki_foot.etat_fournisseurs set pause_jusqu_a=pause where fournisseur=f;
  insert into koki_foot.synchronisations(fournisseur,operation,statut,code,message) values(f,op,'erreur',code_,left(coalesce(koki_foot.t(input,'message'),'Erreur inconnue'),2000)) returning id into rid;
  return jsonb_build_object('journal',rid,'pause_jusqu_a',pause,'erreurs_consecutives',ef.erreurs_consecutives);

 elsif command<>'importer' then perform koki_foot.echec('Commande inconnue'); end if;

 perform koki_foot.cles(input,'{fournisseur,operation,quota_restant,competitions,equipes,inscriptions,matchs,evenements,evenements_complets,classements}');

 -- Compétitions (créées non publiées : l'administrateur choisit ce qui s'affiche).
 for x in select * from jsonb_array_elements(coalesce(input->'competitions','[]')) loop
  lus:=lus+1;
  begin
   insert into koki_foot.competitions(nom,saison,portee,type,source,fournisseur,ref_fournisseur,logo_url,publie)
    values(koki_foot.t(x,'nom'),coalesce(koki_foot.t(x,'saison'),''),coalesce(koki_foot.t(x,'portee'),'International'),coalesce(koki_foot.t(x,'type'),'Championnat'),'api',f,koki_foot.t(x,'ref'),koki_foot.t(x,'logo_url'),false)
   on conflict (fournisseur,ref_fournisseur) do update set nom=excluded.nom, saison=excluded.saison, type=excluded.type, logo_url=excluded.logo_url
    where (koki_foot.competitions.nom,koki_foot.competitions.saison,koki_foot.competitions.type,koki_foot.competitions.logo_url) is distinct from (excluded.nom,excluded.saison,excluded.type,excluded.logo_url)
   returning (xmax=0) into nouveau;
   if found then if nouveau then crees:=crees+1; else maj:=maj+1; end if; end if;
  exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('compétition '||coalesce(koki_foot.t(x,'ref'),'?')||' : '||sqlerrm); end if; end;
 end loop;

 -- Équipes.
 for x in select * from jsonb_array_elements(coalesce(input->'equipes','[]')) loop
  lus:=lus+1;
  begin
   insert into koki_foot.equipes(nom,nom_court,portee,source,fournisseur,ref_fournisseur,logo_url)
    values(koki_foot.t(x,'nom'),left(coalesce(koki_foot.t(x,'nom_court'),''),20),coalesce(koki_foot.t(x,'portee'),'International'),'api',f,koki_foot.t(x,'ref'),koki_foot.t(x,'logo_url'))
   on conflict (fournisseur,ref_fournisseur) do update set nom=excluded.nom, logo_url=excluded.logo_url
    where (koki_foot.equipes.nom,koki_foot.equipes.logo_url) is distinct from (excluded.nom,excluded.logo_url)
   returning (xmax=0) into nouveau;
   if found then if nouveau then crees:=crees+1; else maj:=maj+1; end if; end if;
  exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('équipe '||coalesce(koki_foot.t(x,'ref'),'?')||' : '||sqlerrm); end if; end;
 end loop;

 -- Inscriptions équipe ↔ compétition.
 for x in select * from jsonb_array_elements(coalesce(input->'inscriptions','[]')) loop
  begin
   select id into cid from koki_foot.competitions where fournisseur=f and ref_fournisseur=koki_foot.t(x,'competition_ref');
   select id into d from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'equipe_ref');
   if cid is null or d is null then raise exception 'référence inconnue'; end if;
   insert into koki_foot.competition_equipes(competition_id,equipe_id,poule) values(cid,d,coalesce(koki_foot.t(x,'poule'),''))
    on conflict (competition_id,equipe_id) do update set poule=excluded.poule where koki_foot.competition_equipes.poule<>excluded.poule;
  exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('inscription : '||sqlerrm); end if; end;
 end loop;

 -- Matchs. Chaque verrou (global ou de champ) protège sa partie ; une divergence ouvre un conflit.
 for x in select * from jsonb_array_elements(coalesce(input->'matchs','[]')) loop
  lus:=lus+1;
  begin
   select id into cid from koki_foot.competitions where fournisseur=f and ref_fournisseur=koki_foot.t(x,'competition_ref');
   select id into d from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'domicile_ref');
   select id into ex from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'exterieur_ref');
   if cid is null or d is null or ex is null then raise exception 'compétition ou équipe inconnue'; end if;
   api_statut:=coalesce(koki_foot.t(x,'statut'),'À venir');
   api_score:=jsonb_build_array(koki_foot.i(x,'score_domicile'),koki_foot.i(x,'score_exterieur'),koki_foot.i(x,'pro_domicile'),koki_foot.i(x,'pro_exterieur'),koki_foot.i(x,'tab_domicile'),koki_foot.i(x,'tab_exterieur'));
   api_prog:=jsonb_build_object('date_match',koki_foot.ts(x,'date_match'),'lieu',left(coalesce(koki_foot.t(x,'lieu'),''),120));
   select * into m from koki_foot.matchs where fournisseur=f and ref_fournisseur=koki_foot.t(x,'ref') for update;
   if not found then
    insert into koki_foot.matchs(competition_id,domicile_id,exterieur_id,date_match,lieu,poule,journee,statut,minute,score_domicile,score_exterieur,pro_domicile,pro_exterieur,tab_domicile,tab_exterieur,
      source,fournisseur,ref_fournisseur,resultat_source,publie,synchronise_le,api_date_match,api_lieu)
     values(cid,d,ex,koki_foot.ts(x,'date_match'),api_prog->>'lieu',left(coalesce(koki_foot.t(x,'poule'),''),40),left(coalesce(koki_foot.t(x,'journee'),''),40),
      api_statut,koki_foot.i(x,'minute'),koki_foot.i(x,'score_domicile'),koki_foot.i(x,'score_exterieur'),koki_foot.i(x,'pro_domicile'),koki_foot.i(x,'pro_exterieur'),koki_foot.i(x,'tab_domicile'),koki_foot.i(x,'tab_exterieur'),
      'api',f,koki_foot.t(x,'ref'),'api',true,now(),(api_prog->>'date_match')::timestamptz,api_prog->>'lieu') returning * into m;
    insert into koki_foot.historique_programmation(match_id,origine,date_match,lieu) values(m.id,'api',m.api_date_match,m.api_lieu);
    crees:=crees+1; nouveau:=true;
   else
    l_sc:=m.verrou_manuel or m.verrou_score; l_st:=m.verrou_manuel or m.verrou_statut; l_pr:=m.verrou_manuel or m.verrou_programmation;
    nb:=0;
    if l_sc and jsonb_build_array(m.score_domicile,m.score_exterieur,m.pro_domicile,m.pro_exterieur,m.tab_domicile,m.tab_exterieur)<>api_score then
     perform koki_foot.signaler_conflit(m.id,'score',jsonb_build_array(m.score_domicile,m.score_exterieur,m.pro_domicile,m.pro_exterieur,m.tab_domicile,m.tab_exterieur),api_score); nb:=nb+1;
    end if;
    if l_st and m.statut<>api_statut then perform koki_foot.signaler_conflit(m.id,'statut',to_jsonb(m.statut),to_jsonb(api_statut)); nb:=nb+1; end if;
    if l_pr and jsonb_build_object('date_match',m.date_match,'lieu',m.lieu)<>api_prog then
     perform koki_foot.signaler_conflit(m.id,'programmation',jsonb_build_object('date_match',m.date_match,'lieu',m.lieu),api_prog); nb:=nb+1;
    end if;
    if nb>0 then verrou:=verrou+1; end if;
    -- Programmation reçue du fournisseur : toujours conservée (même verrouillée), historisée si elle change.
    if jsonb_build_object('date_match',m.api_date_match,'lieu',m.api_lieu)<>api_prog then
     insert into koki_foot.historique_programmation(match_id,origine,date_match,lieu) values(m.id,'api',(api_prog->>'date_match')::timestamptz,api_prog->>'lieu');
    end if;
    update koki_foot.matchs set api_date_match=(api_prog->>'date_match')::timestamptz, api_lieu=api_prog->>'lieu', competition_id=cid, domicile_id=d, exterieur_id=ex, poule=left(coalesce(koki_foot.t(x,'poule'),''),40), journee=left(coalesce(koki_foot.t(x,'journee'),''),40),
     date_match=case when l_pr then date_match else (api_prog->>'date_match')::timestamptz end, lieu=case when l_pr then lieu else api_prog->>'lieu' end,
     statut=case when l_st then statut else api_statut end,
     minute=case when l_st then minute else koki_foot.i(x,'minute') end,
     score_domicile=case when l_sc then score_domicile else koki_foot.i(x,'score_domicile') end,
     score_exterieur=case when l_sc then score_exterieur else koki_foot.i(x,'score_exterieur') end,
     pro_domicile=case when l_sc then pro_domicile else koki_foot.i(x,'pro_domicile') end,
     pro_exterieur=case when l_sc then pro_exterieur else koki_foot.i(x,'pro_exterieur') end,
     tab_domicile=case when l_sc then tab_domicile else koki_foot.i(x,'tab_domicile') end,
     tab_exterieur=case when l_sc then tab_exterieur else koki_foot.i(x,'tab_exterieur') end,
     resultat_source=case when l_sc or m.verrou_evenements then resultat_source else 'api' end,
     synchronise_le=now()
    where id=m.id and (
     (competition_id,domicile_id,exterieur_id,poule,journee) is distinct from (cid,d,ex,left(coalesce(koki_foot.t(x,'poule'),''),40),left(coalesce(koki_foot.t(x,'journee'),''),40))
     or (not l_pr and jsonb_build_object('date_match',date_match,'lieu',lieu)<>api_prog)
     or (not l_st and (statut,minute) is distinct from (api_statut,koki_foot.i(x,'minute')))
     or (not l_sc and jsonb_build_array(score_domicile,score_exterieur,pro_domicile,pro_exterieur,tab_domicile,tab_exterieur)<>api_score)
     or (not l_sc and not m.verrou_evenements and resultat_source<>'api')
     or jsonb_build_object('date_match',api_date_match,'lieu',api_lieu)<>api_prog);
    nouveau:=found; if found then maj:=maj+1; end if;
   end if;
   -- Réponse exploitable pour ce match (ligne valide et traitée) : actualisation ; changement effectif : modification.
   insert into koki_foot.vus_api(match_id,vu_le,modifie_le) values(m.id,now(),case when nouveau then now() end)
    on conflict (match_id) do update set vu_le=excluded.vu_le, modifie_le=coalesce(excluded.modifie_le,koki_foot.vus_api.modifie_le);
  exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('match '||coalesce(koki_foot.t(x,'ref'),'?')||' : '||sqlerrm); end if; end;
 end loop;

 -- Événements : clé stable => jamais de doublon. Match verrouillé (global ou événements) : un événement
 -- nouveau n'est pas ajouté mais signalé en conflit (sauf s'il a été retiré volontairement par un administrateur).
 for x in select * from jsonb_array_elements(coalesce(input->'evenements','[]')) loop
  lus:=lus+1;
  begin
   select * into m from koki_foot.matchs where fournisseur=f and ref_fournisseur=koki_foot.t(x,'match_ref');
   if not found then raise exception 'match inconnu'; end if;
   l_ev:=m.verrou_manuel or m.verrou_evenements;
   if l_ev then
    if not exists(select 1 from koki_foot.evenements where match_id=m.id and cle=koki_foot.t(x,'cle'))
       and not exists(select 1 from koki_foot.corrections where match_id=m.id and action='evenement_retrait' and avant->>'cle'=koki_foot.t(x,'cle')) then
     perform koki_foot.signaler_conflit(m.id,'evenements',to_jsonb('événement absent localement'::text),x); verrou:=verrou+1;
    end if;
    continue;
   end if;
   select id into d from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'equipe_ref');
   insert into koki_foot.evenements(match_id,type,periode,minute,minute_add,equipe_id,joueur,joueur2,source,cle)
    values(m.id,koki_foot.t(x,'type'),koki_foot.t(x,'periode'),koki_foot.i(x,'minute'),koki_foot.i(x,'minute_add'),d,left(coalesce(koki_foot.t(x,'joueur'),''),80),left(coalesce(koki_foot.t(x,'joueur2'),''),80),'api',koki_foot.t(x,'cle'))
   on conflict (match_id,cle) do nothing;
   if found then crees:=crees+1; update koki_foot.vus_api set modifie_le=now() where match_id=m.id; end if;
  exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('événement : '||sqlerrm); end if; end;
 end loop;
 -- Liste complète fournie pour un match : les événements api absents (but annulé…) sont retirés,
 -- sauf match verrouillé.
 for x in select * from jsonb_array_elements(coalesce(input->'evenements_complets','[]')) loop
  select * into m from koki_foot.matchs where fournisseur=f and ref_fournisseur=(x#>>'{}');
  if found and not (m.verrou_manuel or m.verrou_evenements) then
   delete from koki_foot.evenements v where v.match_id=m.id and v.source='api'
    and not exists(select 1 from jsonb_array_elements(coalesce(input->'evenements','[]')) y where koki_foot.t(y,'match_ref')=m.ref_fournisseur and koki_foot.t(y,'cle')=v.cle);
  end if;
 end loop;

 -- Classements : remplacés en bloc par compétition (données du fournisseur uniquement).
 select coalesce(array_agg(distinct c.id),'{}') into comps from jsonb_array_elements(coalesce(input->'classements','[]')) y join koki_foot.competitions c on c.fournisseur=f and c.ref_fournisseur=koki_foot.t(y,'competition_ref');
 begin
  delete from koki_foot.classements where competition_id=any(comps);
  for x in select * from jsonb_array_elements(coalesce(input->'classements','[]')) loop
   lus:=lus+1;
   select id into cid from koki_foot.competitions where fournisseur=f and ref_fournisseur=koki_foot.t(x,'competition_ref');
   select id into d from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'equipe_ref');
   if cid is null or d is null then rejet:=rejet+1; continue; end if;
   insert into koki_foot.classements(competition_id,poule,equipe_id,rang,joues,gagnes,nuls,perdus,buts_pour,buts_contre,points,forme)
    values(cid,left(coalesce(koki_foot.t(x,'poule'),''),40),d,koki_foot.i(x,'rang'),coalesce(koki_foot.i(x,'joues'),0),coalesce(koki_foot.i(x,'gagnes'),0),coalesce(koki_foot.i(x,'nuls'),0),
     coalesce(koki_foot.i(x,'perdus'),0),coalesce(koki_foot.i(x,'buts_pour'),0),coalesce(koki_foot.i(x,'buts_contre'),0),coalesce(koki_foot.i(x,'points'),0),
     coalesce(regexp_replace(upper(right(coalesce(koki_foot.t(x,'forme'),''),5)),'[^VND]','','g'),''))
    on conflict (competition_id,poule,equipe_id) do nothing;
  end loop;
 exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('classement : '||sqlerrm); end if; end;

 st:=case when rejet=0 then 'ok' when rejet<lus then 'partiel' else 'erreur' end;
 update koki_foot.etat_fournisseurs set derniere_tentative=now(), derniere_reussite=case when st<>'erreur' then now() else derniere_reussite end,
  derniere_modification=case when crees+maj>0 then now() else derniere_modification end,
  derniere_erreur=case when st='erreur' then now() else derniere_erreur end, derniere_erreur_code=case when st='erreur' then 'donnees' else derniere_erreur_code end,
  erreurs_consecutives=case when st<>'erreur' then 0 else erreurs_consecutives+1 end, pause_jusqu_a=case when st<>'erreur' then null else pause_jusqu_a end,
  quota_restant=coalesce(koki_foot.i(input,'quota_restant'),quota_restant) where fournisseur=f;
 insert into koki_foot.synchronisations(fournisseur,operation,statut,code,lus,crees,mis_a_jour,ignores_verrou,rejetes,message)
  values(f,op,st,case when rejet>0 then 'donnees' end,lus,crees,maj,verrou,rejet,left(array_to_string(erreurs,E'\n'),2000)) returning id into rid;
 return jsonb_build_object('statut',st,'lus',lus,'crees',crees,'mis_a_jour',maj,'ignores_verrou',verrou,'rejetes',rejet,'erreurs',to_jsonb(erreurs),'journal',rid);
end $$;

-- ───────────── Droits ─────────────
revoke all on all functions in schema koki_foot from public, anon, authenticated, service_role;
revoke all on function public.koki_foot_public(text,jsonb), public.koki_foot_admin(text,jsonb), public.koki_foot_sync(text,jsonb) from public, anon, authenticated, service_role;
grant execute on function public.koki_foot_public(text,jsonb) to anon, authenticated;
grant execute on function public.koki_foot_admin(text,jsonb) to authenticated;
grant execute on function public.koki_foot_sync(text,jsonb) to service_role;

commit;
