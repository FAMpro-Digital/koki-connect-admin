-- Module Football — 2/2 : accès (RPC), classement calculé, diffusion en direct (Supabase Realtime).
-- NON APPLIQUÉE EN PRODUCTION. Testée en local (outils/tester-foot.sh).
--
--  * public.koki_foot_public(command, input) : lecture publique (anon) des seules compétitions publiées ;
--  * public.koki_foot_admin(command, input)  : administration. Exige koki_private.allowed('content')
--    (rôle editor ou superadmin ET session aal2) pour écrire, allowed('read') pour lire ;
--  * public.koki_foot_sync(command, input)   : import du fournisseur. Exécutable par service_role
--    SEULEMENT (fonction serveur, clé jamais exposée au navigateur) ;
--  * diffusion : à chaque changement visible d'un match publié, un message Broadcast PUBLIC est envoyé
--    sur le canal « koki-foot » (identifiant, statut, minute, score, révision : aucune donnée personnelle).
--    Les tables restent fermées : le canal ne donne accès à rien d'autre.

begin;

do $$ begin
 if to_regnamespace('koki_foot') is null or to_regclass('koki_foot.matchs') is null then
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
$$ select case when jsonb_typeof(input->k)='string' then btrim(input->>k) when input->k is null or jsonb_typeof(input->k)='null' then null else btrim(input->>k) end $$;
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
create function koki_foot.exiger(permission text) returns uuid language plpgsql stable security definer set search_path='' as $$
begin
 if not koki_private.allowed(permission) then raise exception 'Administration et double authentification requises' using errcode='42501'; end if;
 return auth.uid();
end $$;

-- ───────────── Représentations ─────────────
create function koki_foot.equipe_json(e koki_foot.equipes) returns jsonb language sql stable set search_path='' as
$$ select jsonb_build_object('id',e.id,'nom',e.nom,'nom_court',e.nom_court,'logo_url',e.logo_url,'couleurs',to_jsonb(e.couleurs),'portee',e.portee,'quartier',e.quartier) $$;
create function koki_foot.match_json(m koki_foot.matchs) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',m.id,'revision',m.revision,'competition',jsonb_build_object('id',c.id,'nom',c.nom,'saison',c.saison,'portee',c.portee,'logo_url',c.logo_url),
  'domicile',koki_foot.equipe_json(d),'exterieur',koki_foot.equipe_json(x),'date_match',m.date_match,'lieu',m.lieu,'poule',m.poule,'journee',m.journee,
  'statut',m.statut,'minute',m.minute,'score_domicile',m.score_domicile,'score_exterieur',m.score_exterieur,'tab_domicile',m.tab_domicile,'tab_exterieur',m.tab_exterieur,
  'commentaire',m.commentaire,'source',m.source,'mis_a_jour',m.updated_at)
 from koki_foot.competitions c, koki_foot.equipes d, koki_foot.equipes x where c.id=m.competition_id and d.id=m.domicile_id and x.id=m.exterieur_id
$$;
create function koki_foot.evenement_json(v koki_foot.evenements) returns jsonb language sql stable set search_path='' as
$$ select jsonb_build_object('id',v.id,'type',v.type,'minute',v.minute,'minute_add',v.minute_add,'equipe_id',v.equipe_id,'joueur',v.joueur,'joueur2',v.joueur2) $$;
-- Visible publiquement : match publié d'une compétition publiée et non archivée.
create function koki_foot.visible(m koki_foot.matchs) returns boolean language sql stable set search_path='' as
$$ select m.publie and exists(select 1 from koki_foot.competitions c where c.id=m.competition_id and c.publie and c.statut<>'archivée') $$;

-- ───────────── Classement ─────────────
-- API : lignes importées. Manuel : calculé à partir des matchs terminés et publiés (3/1/0 ;
-- départage : points, différence de buts, buts marqués, nom). Les équipes inscrites sans match apparaissent à 0.
create function koki_foot.classement(p_comp uuid, p_poule text) returns jsonb language plpgsql stable set search_path='' as $$
declare c koki_foot.competitions; begin
 select * into c from koki_foot.competitions where id=p_comp;
 if not found then return '[]'; end if;
 if c.source='api' then
  return coalesce((select jsonb_agg(jsonb_build_object('rang',k.rang,'equipe',koki_foot.equipe_json(e),'poule',k.poule,'joues',k.joues,'gagnes',k.gagnes,'nuls',k.nuls,'perdus',k.perdus,
   'buts_pour',k.buts_pour,'buts_contre',k.buts_contre,'diff',k.buts_pour-k.buts_contre,'points',k.points,'forme',k.forme) order by k.poule,k.rang)
   from koki_foot.classements k join koki_foot.equipes e on e.id=k.equipe_id where k.competition_id=p_comp and (coalesce(p_poule,'')='' or k.poule=p_poule)),'[]');
 end if;
 return coalesce((with
  participants as (
   select ce.equipe_id from koki_foot.competition_equipes ce where ce.competition_id=p_comp and (coalesce(p_poule,'')='' or ce.poule=p_poule)
   union select m.domicile_id from koki_foot.matchs m where m.competition_id=p_comp and m.publie and (coalesce(p_poule,'')='' or m.poule=p_poule)
   union select m.exterieur_id from koki_foot.matchs m where m.competition_id=p_comp and m.publie and (coalesce(p_poule,'')='' or m.poule=p_poule)),
  joues as (
   select m.date_match, m.domicile_id eq, m.score_domicile bp, m.score_exterieur bc from koki_foot.matchs m where m.competition_id=p_comp and m.publie and m.statut='Terminé' and (coalesce(p_poule,'')='' or m.poule=p_poule)
   union all
   select m.date_match, m.exterieur_id, m.score_exterieur, m.score_domicile from koki_foot.matchs m where m.competition_id=p_comp and m.publie and m.statut='Terminé' and (coalesce(p_poule,'')='' or m.poule=p_poule)),
  agg as (
   select p.equipe_id, count(j.eq)::int joues, count(*) filter (where j.bp>j.bc)::int g, count(*) filter (where j.bp=j.bc)::int n, count(*) filter (where j.bp<j.bc)::int pe,
    coalesce(sum(j.bp),0)::int bp, coalesce(sum(j.bc),0)::int bc,
    coalesce(right(string_agg(case when j.bp>j.bc then 'V' when j.bp=j.bc then 'N' else 'D' end,'' order by j.date_match),5),'') forme
   from participants p left join joues j on j.eq=p.equipe_id group by p.equipe_id),
  classe as (
   select a.*, a.g*3+a.n pts, e.nom, e from agg a join koki_foot.equipes e on e.id=a.equipe_id)
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
 if tg_op='UPDATE' and (old.statut,old.minute,old.score_domicile,old.score_exterieur,old.tab_domicile,old.tab_exterieur,old.publie,old.date_match)
    is not distinct from (new.statut,new.minute,new.score_domicile,new.score_exterieur,new.tab_domicile,new.tab_exterieur,new.publie,new.date_match) then
  return null;
 end if;
 if not koki_foot.visible(new) and not (tg_op='UPDATE' and old.publie and not new.publie) then return null; end if;
 perform koki_foot.diffuser('match',jsonb_build_object('id',new.id,'revision',new.revision,'visible',koki_foot.visible(new),'statut',new.statut,'minute',new.minute,
  'score_domicile',new.score_domicile,'score_exterieur',new.score_exterieur,'tab_domicile',new.tab_domicile,'tab_exterieur',new.tab_exterieur,'date_match',new.date_match));
 return null;
end $$;
create trigger matchs_diffusion after insert or update on koki_foot.matchs for each row execute function koki_foot.match_diffuse();
create function koki_foot.evenement_diffuse() returns trigger language plpgsql security definer set search_path='' as $$
declare r koki_foot.evenements:=case when tg_op='DELETE' then old else new end; m koki_foot.matchs;
begin
 select * into m from koki_foot.matchs where id=r.match_id;
 if found and koki_foot.visible(m) then perform koki_foot.diffuser('evenement',jsonb_build_object('match_id',r.match_id)); end if;
 return null;
end $$;
create trigger evenements_diffusion after insert or delete on koki_foot.evenements for each row execute function koki_foot.evenement_diffuse();

-- ───────────── Lecture publique ─────────────
create function public.koki_foot_public(command text, input jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p text; c uuid; m koki_foot.matchs; begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>4096 then perform koki_foot.echec('Requête invalide'); end if;
 if command='accueil' then
  -- En direct, à venir (7 jours) et résultats récents (7 jours), filtrables par portée.
  perform koki_foot.cles(input,'{portee}'); p:=nullif(koki_foot.t(input,'portee'),'');
  if p is not null and p not in ('Koki','Sénégal','International') then perform koki_foot.echec('Portée invalide'); end if;
  return jsonb_build_object(
   'direct',coalesce((select jsonb_agg(koki_foot.match_json(x) order by case c2.portee when 'Koki' then 0 when 'Sénégal' then 1 else 2 end, c2.ordre, x.date_match)
     from koki_foot.matchs x join koki_foot.competitions c2 on c2.id=x.competition_id where koki_foot.visible(x) and x.statut in ('En direct','Mi-temps','Interrompu') and (p is null or c2.portee=p)),'[]'),
   'a_venir',coalesce((select jsonb_agg(koki_foot.match_json(y) order by y.date_match) from (select x.* from koki_foot.matchs x join koki_foot.competitions c2 on c2.id=x.competition_id
     where koki_foot.visible(x) and x.statut in ('À venir','Reporté') and x.date_match>=now()-interval '3 hours' and x.date_match<now()+interval '7 days' and (p is null or c2.portee=p) order by x.date_match limit 40) y),'[]'),
   'resultats',coalesce((select jsonb_agg(koki_foot.match_json(y) order by y.date_match desc) from (select x.* from koki_foot.matchs x join koki_foot.competitions c2 on c2.id=x.competition_id
     where koki_foot.visible(x) and x.statut='Terminé' and x.date_match>now()-interval '7 days' and (p is null or c2.portee=p) order by x.date_match desc limit 40) y),'[]'),
   'maintenant',now());
 elsif command='match' then
  perform koki_foot.cles(input,'{id}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id');
  if not found or not koki_foot.visible(m) then return null; end if;
  return koki_foot.match_json(m)||jsonb_build_object('evenements',coalesce((select jsonb_agg(koki_foot.evenement_json(v) order by v.minute nulls first, v.minute_add nulls first, v.created_at)
   from koki_foot.evenements v where v.match_id=m.id),'[]'));
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

-- Changement de score/statut/minute d'un match existant, commun à « enregistrer_match » et « score ».
-- Match api : le motif est obligatoire et le match est verrouillé (la synchronisation ne touchera plus
-- son score ni son statut). Match manuel déjà terminé : motif obligatoire.
create function koki_foot.appliquer_score(m koki_foot.matchs, a uuid, p_statut text, p_minute integer, sd integer, se integer, td integer, te integer, p_motif text) returns koki_foot.matchs
language plpgsql security definer set search_path='' as $$
declare r koki_foot.matchs; avant jsonb; apres jsonb; begin
 avant:=jsonb_build_object('statut',m.statut,'minute',m.minute,'score_domicile',m.score_domicile,'score_exterieur',m.score_exterieur,'tab_domicile',m.tab_domicile,'tab_exterieur',m.tab_exterieur);
 if p_statut is null or p_statut not in ('À venir','En direct','Mi-temps','Terminé','Reporté','Annulé','Interrompu') then perform koki_foot.echec('Statut invalide'); end if;
 if (sd is null)<>(se is null) or (td is null)<>(te is null) then perform koki_foot.echec('Indiquez le score des deux équipes'); end if;
 if p_statut='Terminé' and sd is null then perform koki_foot.echec('Score requis pour un match terminé'); end if;
 if p_statut in ('En direct','Mi-temps','Interrompu') and sd is null then sd:=0; se:=0; end if;
 if p_statut not in ('En direct','Mi-temps','Interrompu') then p_minute:=null; end if;
 apres:=jsonb_build_object('statut',p_statut,'minute',p_minute,'score_domicile',sd,'score_exterieur',se,'tab_domicile',td,'tab_exterieur',te);
 if avant=apres then return m; end if;
 if (m.source='api' or m.statut='Terminé') and (avant-'minute')<>(apres-'minute') and length(btrim(coalesce(p_motif,'')))<3 then
  perform koki_foot.echec('Motif de la correction requis (3 caractères au moins)');
 end if;
 update koki_foot.matchs set statut=p_statut, minute=p_minute, score_domicile=sd, score_exterieur=se, tab_domicile=td, tab_exterieur=te,
  verrou_manuel=case when source='api' and (avant-'minute')<>(apres-'minute') then true else verrou_manuel end,
  verrouille_par=case when source='api' and (avant-'minute')<>(apres-'minute') then a else verrouille_par end,
  verrouille_le=case when source='api' and (avant-'minute')<>(apres-'minute') then now() else verrouille_le end
 where id=m.id returning * into r;
 if (avant-'minute')<>(apres-'minute') then
  perform koki_foot.corriger(m.id,a,case when (avant->>'statut')<>(apres->>'statut') and (avant-'statut'-'minute')=(apres-'statut'-'minute') then 'statut' else 'score' end,avant,apres,p_motif);
  if m.source='api' and not m.verrou_manuel then perform koki_foot.corriger(m.id,a,'verrou','{}','{"verrou_manuel":true}',p_motif); end if;
 end if;
 return r;
end $$;

create function public.koki_foot_admin(command text, input jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; c koki_foot.competitions; e koki_foot.equipes; m koki_foot.matchs; v koki_foot.evenements; id_ uuid; n integer; s text; delta_d integer:=0; delta_e integer:=0; begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>32768 then perform koki_foot.echec('Requête invalide ou trop volumineuse'); end if;

 -- ── Lecture ──
 if command='etat' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{depuis}');
  return jsonb_build_object(
   'competitions',coalesce((select jsonb_agg(to_jsonb(x) order by x.portee, x.ordre, x.nom) from koki_foot.competitions x),'[]'),
   'equipes',coalesce((select jsonb_agg(to_jsonb(x) order by x.nom) from koki_foot.equipes x where x.source='manuel' or exists(select 1 from koki_foot.competition_equipes ce join koki_foot.competitions c2 on c2.id=ce.competition_id where ce.equipe_id=x.id and c2.publie)),'[]'),
   'inscriptions',coalesce((select jsonb_agg(to_jsonb(x)) from koki_foot.competition_equipes x join koki_foot.competitions c2 on c2.id=x.competition_id where c2.source='manuel'),'[]'),
   'matchs',coalesce((select jsonb_agg(koki_foot.match_json(x)||jsonb_build_object('publie',x.publie,'verrou_manuel',x.verrou_manuel,'synchronise_le',x.synchronise_le) order by x.date_match)
     from koki_foot.matchs x where x.date_match>=coalesce(koki_foot.ts(input,'depuis'),now()-interval '30 days') and x.date_match<now()+interval '60 days'
      and (x.source='manuel' or x.statut in ('En direct','Mi-temps','Interrompu') or exists(select 1 from koki_foot.competitions c2 where c2.id=x.competition_id and c2.publie))),'[]'),
   'synchronisations',coalesce((select jsonb_agg(to_jsonb(y) order by y.created_at desc) from (select * from koki_foot.synchronisations order by created_at desc limit 20) y),'[]'));
 elsif command='evenements' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{match_id}');
  return coalesce((select jsonb_agg(koki_foot.evenement_json(x)||jsonb_build_object('source',x.source) order by x.minute nulls first, x.created_at) from koki_foot.evenements x where x.match_id=koki_foot.u(input,'match_id')),'[]');
 elsif command='corrections' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{match_id}');
  return coalesce((select jsonb_agg(to_jsonb(y) order by y.created_at desc) from (select x.*, (select u.email from auth.users u where u.id=x.acteur) acteur_email from koki_foot.corrections x
   where koki_foot.u(input,'match_id') is null or x.match_id=koki_foot.u(input,'match_id') order by x.created_at desc limit 200) y),'[]');
 elsif command='classement' then
  a:=koki_foot.exiger('read'); perform koki_foot.cles(input,'{competition_id,poule}');
  return koki_foot.classement(koki_foot.u(input,'competition_id'),koki_foot.t(input,'poule'));
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
  perform koki_foot.cles(input,'{id,revision,competition_id,domicile_id,exterieur_id,date_match,lieu,poule,journee,statut,minute,score_domicile,score_exterieur,tab_domicile,tab_exterieur,commentaire,publie,motif}');
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
    where id=m.id returning * into m;
   else
    -- Match importé : seuls l'affichage et le commentaire sont libres ; le reste suit le fournisseur.
    update koki_foot.matchs set commentaire=coalesce(koki_foot.t(input,'commentaire'),commentaire), publie=koki_foot.b(input,'publie',publie) where id=m.id returning * into m;
   end if;
  end if;
  if input ? 'statut' then
   m:=koki_foot.appliquer_score(m,a,koki_foot.t(input,'statut'),koki_foot.i(input,'minute'),koki_foot.i(input,'score_domicile'),koki_foot.i(input,'score_exterieur'),
    koki_foot.i(input,'tab_domicile'),koki_foot.i(input,'tab_exterieur'),koki_foot.t(input,'motif'));
  end if;
  return koki_foot.match_json(m)||jsonb_build_object('publie',m.publie,'verrou_manuel',m.verrou_manuel);

 elsif command='score' then
  -- Saisie rapide depuis le terrain : statut, minute et score en un geste.
  perform koki_foot.cles(input,'{id,revision,statut,minute,score_domicile,score_exterieur,tab_domicile,tab_exterieur,motif}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id') for update; if not found then perform koki_foot.echec('Match introuvable'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  m:=koki_foot.appliquer_score(m,a,coalesce(koki_foot.t(input,'statut'),m.statut),koki_foot.i(input,'minute'),koki_foot.i(input,'score_domicile'),koki_foot.i(input,'score_exterieur'),
   koki_foot.i(input,'tab_domicile'),koki_foot.i(input,'tab_exterieur'),koki_foot.t(input,'motif'));
  return koki_foot.match_json(m)||jsonb_build_object('publie',m.publie,'verrou_manuel',m.verrou_manuel);

 elsif command='ajouter_evenement' then
  -- Un but met aussi le score à jour (but contre son camp : pour l'adversaire), sauf maj_score=false.
  perform koki_foot.cles(input,'{match_id,revision,type,minute,minute_add,equipe_id,joueur,joueur2,maj_score,motif}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'match_id') for update; if not found then perform koki_foot.echec('Match introuvable'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  insert into koki_foot.evenements(match_id,type,minute,minute_add,equipe_id,joueur,joueur2,source,auteur)
   values(m.id,koki_foot.t(input,'type'),koki_foot.i(input,'minute'),koki_foot.i(input,'minute_add'),koki_foot.u(input,'equipe_id'),coalesce(koki_foot.t(input,'joueur'),''),coalesce(koki_foot.t(input,'joueur2'),''),'manuel',a)
   returning * into v;
  perform koki_foot.corriger(m.id,a,'evenement_ajout','{}',koki_foot.evenement_json(v),koki_foot.t(input,'motif'));
  if koki_foot.b(input,'maj_score',true) and v.type in ('but','penalty','but_csc') and v.equipe_id is not null then
   if (v.type='but_csc')=(v.equipe_id=m.domicile_id) then delta_e:=1; else delta_d:=1; end if;
   m:=koki_foot.appliquer_score(m,a,case when m.statut in ('À venir','Reporté') then 'En direct' else m.statut end,m.minute,coalesce(m.score_domicile,0)+delta_d,coalesce(m.score_exterieur,0)+delta_e,
    m.tab_domicile,m.tab_exterieur,koki_foot.t(input,'motif'));
  end if;
  return jsonb_build_object('evenement',koki_foot.evenement_json(v),'match',koki_foot.match_json(m)||jsonb_build_object('verrou_manuel',m.verrou_manuel));

 elsif command='retirer_evenement' then
  perform koki_foot.cles(input,'{id,maj_score,motif}');
  select * into v from koki_foot.evenements where id=koki_foot.u(input,'id'); if not found then perform koki_foot.echec('Événement introuvable'); end if;
  if v.source<>'manuel' then perform koki_foot.echec('Événement du fournisseur : corrigez le score et le match sera verrouillé'); end if;
  if length(btrim(coalesce(koki_foot.t(input,'motif'),'')))<3 then perform koki_foot.echec('Motif requis (3 caractères au moins)'); end if;
  select * into m from koki_foot.matchs where id=v.match_id for update;
  delete from koki_foot.evenements where id=v.id;
  perform koki_foot.corriger(m.id,a,'evenement_retrait',koki_foot.evenement_json(v),'{}',koki_foot.t(input,'motif'));
  if koki_foot.b(input,'maj_score',true) and v.type in ('but','penalty','but_csc') and v.equipe_id is not null and m.score_domicile is not null then
   if (v.type='but_csc')=(v.equipe_id=m.domicile_id) then delta_e:=1; else delta_d:=1; end if;
   m:=koki_foot.appliquer_score(m,a,m.statut,m.minute,greatest(m.score_domicile-delta_d,0),greatest(m.score_exterieur-delta_e,0),m.tab_domicile,m.tab_exterieur,koki_foot.t(input,'motif'));
  end if;
  return koki_foot.match_json(m)||jsonb_build_object('verrou_manuel',m.verrou_manuel);

 elsif command='deverrouiller' then
  -- Rend la main au fournisseur : la prochaine synchronisation pourra réécrire score et statut.
  perform koki_foot.cles(input,'{id,revision,motif}');
  select * into m from koki_foot.matchs where id=koki_foot.u(input,'id') for update; if not found or not m.verrou_manuel then perform koki_foot.echec('Match non verrouillé'); end if;
  perform koki_foot.revision(koki_foot.i(input,'revision'),m.revision);
  if length(btrim(coalesce(koki_foot.t(input,'motif'),'')))<3 then perform koki_foot.echec('Motif requis (3 caractères au moins)'); end if;
  update koki_foot.matchs set verrou_manuel=false, verrouille_par=null, verrouille_le=null where id=m.id returning * into m;
  perform koki_foot.corriger(m.id,a,'deverrou','{"verrou_manuel":true}','{"verrou_manuel":false}',koki_foot.t(input,'motif'));
  return koki_foot.match_json(m)||jsonb_build_object('verrou_manuel',m.verrou_manuel);
 end if;

 perform koki_foot.echec('Commande inconnue');
end $$;

-- ───────────── Synchronisation (service_role seulement) ─────────────
create function public.koki_foot_sync(command text, input jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare f text; op text; x jsonb; lus integer:=0; crees integer:=0; maj integer:=0; verrou integer:=0; rejet integer:=0; erreurs text[]:='{}'; st text;
 cid uuid; d uuid; ex uuid; mid uuid; m koki_foot.matchs; nouveau boolean; k text; rid bigint; comps uuid[]:='{}';
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Réservé à la synchronisation serveur' using errcode='42501'; end if;
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>4194304 then perform koki_foot.echec('Requête invalide ou trop volumineuse'); end if;
 f:=koki_foot.t(input,'fournisseur'); op:=left(coalesce(koki_foot.t(input,'operation'),command),60);
 if f is null or f not in ('api-football','sportmonks') then perform koki_foot.echec('Fournisseur invalide'); end if;

 if command='references' then
  -- Ce que la synchronisation doit suivre : compétitions publiées et matchs en cours ou imminents.
  return jsonb_build_object(
   'competitions',coalesce((select jsonb_agg(jsonb_build_object('ref',c.ref_fournisseur,'saison',c.saison)) from koki_foot.competitions c where c.fournisseur=f and c.publie and c.statut='active'),'[]'),
   'matchs_a_suivre',coalesce((select jsonb_agg(m2.ref_fournisseur) from koki_foot.matchs m2 join koki_foot.competitions c on c.id=m2.competition_id
     where m2.fournisseur=f and c.publie and (m2.statut in ('En direct','Mi-temps','Interrompu') or (m2.statut='À venir' and m2.date_match between now()-interval '3 hours' and now()+interval '15 minutes'))),'[]'));

 elsif command='erreur' then
  perform koki_foot.cles(input,'{fournisseur,operation,message}');
  insert into koki_foot.synchronisations(fournisseur,operation,statut,message) values(f,op,'erreur',left(coalesce(koki_foot.t(input,'message'),'Erreur inconnue'),2000)) returning id into rid;
  return jsonb_build_object('journal',rid);

 elsif command<>'importer' then perform koki_foot.echec('Commande inconnue'); end if;

 perform koki_foot.cles(input,'{fournisseur,operation,competitions,equipes,inscriptions,matchs,evenements,evenements_complets,classements}');

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

 -- Matchs. Verrouillé (correction manuelle) : score, statut et minute ne sont PAS réécrits.
 for x in select * from jsonb_array_elements(coalesce(input->'matchs','[]')) loop
  lus:=lus+1;
  begin
   select id into cid from koki_foot.competitions where fournisseur=f and ref_fournisseur=koki_foot.t(x,'competition_ref');
   select id into d from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'domicile_ref');
   select id into ex from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'exterieur_ref');
   if cid is null or d is null or ex is null then raise exception 'compétition ou équipe inconnue'; end if;
   select * into m from koki_foot.matchs where fournisseur=f and ref_fournisseur=koki_foot.t(x,'ref') for update;
   if not found then
    insert into koki_foot.matchs(competition_id,domicile_id,exterieur_id,date_match,lieu,poule,journee,statut,minute,score_domicile,score_exterieur,tab_domicile,tab_exterieur,source,fournisseur,ref_fournisseur,publie,synchronise_le)
     values(cid,d,ex,koki_foot.ts(x,'date_match'),left(coalesce(koki_foot.t(x,'lieu'),''),120),left(coalesce(koki_foot.t(x,'poule'),''),40),left(coalesce(koki_foot.t(x,'journee'),''),40),
      coalesce(koki_foot.t(x,'statut'),'À venir'),koki_foot.i(x,'minute'),koki_foot.i(x,'score_domicile'),koki_foot.i(x,'score_exterieur'),koki_foot.i(x,'tab_domicile'),koki_foot.i(x,'tab_exterieur'),'api',f,koki_foot.t(x,'ref'),true,now());
    crees:=crees+1;
   else
    if m.verrou_manuel then verrou:=verrou+1; end if;
    update koki_foot.matchs set competition_id=cid, domicile_id=d, exterieur_id=ex, date_match=koki_foot.ts(x,'date_match'), lieu=left(coalesce(koki_foot.t(x,'lieu'),''),120),
     poule=left(coalesce(koki_foot.t(x,'poule'),''),40), journee=left(coalesce(koki_foot.t(x,'journee'),''),40),
     statut=case when m.verrou_manuel then statut else coalesce(koki_foot.t(x,'statut'),'À venir') end,
     minute=case when m.verrou_manuel then minute else koki_foot.i(x,'minute') end,
     score_domicile=case when m.verrou_manuel then score_domicile else koki_foot.i(x,'score_domicile') end,
     score_exterieur=case when m.verrou_manuel then score_exterieur else koki_foot.i(x,'score_exterieur') end,
     tab_domicile=case when m.verrou_manuel then tab_domicile else koki_foot.i(x,'tab_domicile') end,
     tab_exterieur=case when m.verrou_manuel then tab_exterieur else koki_foot.i(x,'tab_exterieur') end,
     synchronise_le=now()
    where id=m.id and ((competition_id,domicile_id,exterieur_id,date_match,lieu,poule,journee) is distinct from (cid,d,ex,koki_foot.ts(x,'date_match'),left(coalesce(koki_foot.t(x,'lieu'),''),120),left(coalesce(koki_foot.t(x,'poule'),''),40),left(coalesce(koki_foot.t(x,'journee'),''),40))
       or (not m.verrou_manuel and (statut,minute,score_domicile,score_exterieur,tab_domicile,tab_exterieur) is distinct from
           (coalesce(koki_foot.t(x,'statut'),'À venir'),koki_foot.i(x,'minute'),koki_foot.i(x,'score_domicile'),koki_foot.i(x,'score_exterieur'),koki_foot.i(x,'tab_domicile'),koki_foot.i(x,'tab_exterieur'))));
    if found then maj:=maj+1; end if;
   end if;
  exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('match '||coalesce(koki_foot.t(x,'ref'),'?')||' : '||sqlerrm); end if; end;
 end loop;

 -- Événements : clé stable => jamais de doublon. Ignorés pour un match verrouillé.
 for x in select * from jsonb_array_elements(coalesce(input->'evenements','[]')) loop
  lus:=lus+1;
  begin
   select * into m from koki_foot.matchs where fournisseur=f and ref_fournisseur=koki_foot.t(x,'match_ref');
   if not found then raise exception 'match inconnu'; end if;
   if m.verrou_manuel then verrou:=verrou+1; continue; end if;
   select id into d from koki_foot.equipes where fournisseur=f and ref_fournisseur=koki_foot.t(x,'equipe_ref');
   insert into koki_foot.evenements(match_id,type,minute,minute_add,equipe_id,joueur,joueur2,source,cle)
    values(m.id,koki_foot.t(x,'type'),koki_foot.i(x,'minute'),koki_foot.i(x,'minute_add'),d,left(coalesce(koki_foot.t(x,'joueur'),''),80),left(coalesce(koki_foot.t(x,'joueur2'),''),80),'api',koki_foot.t(x,'cle'))
   on conflict (match_id,cle) do nothing;
   if found then crees:=crees+1; end if;
  exception when others then rejet:=rejet+1; if cardinality(erreurs)<20 then erreurs:=erreurs||('événement : '||sqlerrm); end if; end;
 end loop;
 -- Liste complète fournie pour un match : les événements api absents (but annulé…) sont retirés.
 for x in select * from jsonb_array_elements(coalesce(input->'evenements_complets','[]')) loop
  select * into m from koki_foot.matchs where fournisseur=f and ref_fournisseur=(x#>>'{}');
  if found and not m.verrou_manuel then
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
 insert into koki_foot.synchronisations(fournisseur,operation,statut,lus,crees,mis_a_jour,ignores_verrou,rejetes,message)
  values(f,op,st,lus,crees,maj,verrou,rejet,left(array_to_string(erreurs,E'\n'),2000)) returning id into rid;
 return jsonb_build_object('statut',st,'lus',lus,'crees',crees,'mis_a_jour',maj,'ignores_verrou',verrou,'rejetes',rejet,'erreurs',to_jsonb(erreurs),'journal',rid);
end $$;

-- ───────────── Droits ─────────────
revoke all on all functions in schema koki_foot from public, anon, authenticated, service_role;
revoke all on function public.koki_foot_public(text,jsonb), public.koki_foot_admin(text,jsonb), public.koki_foot_sync(text,jsonb) from public, anon, authenticated, service_role;
grant execute on function public.koki_foot_public(text,jsonb) to anon, authenticated;
grant execute on function public.koki_foot_admin(text,jsonb) to authenticated;
grant execute on function public.koki_foot_sync(text,jsonb) to service_role;

commit;
