-- Espace Clubs & Académies — 2/3 : contrôle d'accès, commandes, lecture publique.
-- APPLIQUÉE EN PRODUCTION le 20/11/2026 (accord écrit de Mourtada Fam). Voir supabase/production/README.md.
--
--  public.koki_sport(command, input)        : comptes connectés (membres d'académie, abonnés, administrateurs aal2)
--  public.koki_sport_public(command, input) : visiteurs (anon) — champs en liste blanche, filtre de consentement
--
-- Toute commande déduit l'académie DEPUIS LA BASE (jamais depuis la requête) puis appelle koki_sport.can().

begin;

do $$ begin
 if to_regclass('koki_sport.clubs') is null then raise exception 'GARDE : migration 20261201000000_sport_schema absente';end if;
 if to_regprocedure('koki_sport.can(uuid,text,uuid)') is not null then raise exception 'GARDE : déjà appliquée';end if;
end $$;

-- ───────────── Utilitaires ─────────────
create function koki_sport.fail(msg text) returns void language plpgsql set search_path='' as
$$ begin raise exception '%', msg; end $$;
create function koki_sport.deny() returns void language plpgsql set search_path='' as
$$ begin raise exception 'Accès refusé' using errcode='42501'; end $$;

create function koki_sport.u(input jsonb, k text, required boolean default true) returns uuid language plpgsql immutable set search_path='' as $$
begin
 if input->>k is null or input->>k='' then
  if required then raise exception 'Champ manquant : %', k; end if; return null; end if;
 return (input->>k)::uuid;
exception when invalid_text_representation then raise exception 'Identifiant invalide : %', k;
end $$;
create function koki_sport.t(input jsonb, k text, dflt text default '') returns text language sql immutable set search_path='' as
$$ select coalesce(btrim(input->>k), dflt) $$;
create function koki_sport.i(input jsonb, k text) returns integer language plpgsql immutable set search_path='' as $$
begin
 if input->k is null or input->k='null'::jsonb or input->>k='' then return null; end if;
 if jsonb_typeof(input->k)='number' and (input->>k)::numeric=trunc((input->>k)::numeric) then return (input->>k)::integer; end if;
 if jsonb_typeof(input->k)='string' and input->>k ~ '^-?[0-9]{1,9}$' then return (input->>k)::integer; end if;
 raise exception 'Nombre entier attendu : %', k;
end $$;
create function koki_sport.b(input jsonb, k text, dflt boolean default false) returns boolean language plpgsql immutable set search_path='' as $$
begin
 if input->k is null or input->k='null'::jsonb then return dflt; end if;
 if jsonb_typeof(input->k)<>'boolean' then raise exception 'Oui/non attendu : %', k; end if;
 return (input->>k)::boolean;
end $$;
create function koki_sport.ts(input jsonb, k text, required boolean default true) returns timestamptz language plpgsql stable set search_path='' as $$
begin
 if input->>k is null or input->>k='' then if required then raise exception 'Date manquante : %', k; end if; return null; end if;
 return (input->>k)::timestamptz;
exception when others then raise exception 'Date invalide : %', k;
end $$;
create function koki_sport.keys(input jsonb, allowed text[]) returns void language plpgsql immutable set search_path='' as $$
begin
 if exists(select 1 from jsonb_object_keys(input) k where not k=any(allowed)) then raise exception 'Champs inconnus ou requête invalide'; end if;
end $$;
create function koki_sport.check_revision(current_rev integer, input jsonb) returns void language plpgsql immutable set search_path='' as $$
begin
 if koki_sport.i(input,'revision') is distinct from current_rev then raise exception 'Modifié entre-temps : rechargez avant d’enregistrer'; end if;
end $$;
create function koki_sport.slugify(v text) returns text language sql immutable set search_path='' as $$
 select left(btrim(regexp_replace(lower(translate(v,'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ','aaaaaaceeeeiiiinooooouuuuyyaaaaaaceeeeiiiinooooouuuuy')),'[^a-z0-9]+','-','g'),'-'),70)
$$;

-- ───────────── Décision d'accès (unique) ─────────────
create function koki_sport.actor() returns uuid language plpgsql stable set search_path='' as $$
declare a uuid:=auth.uid();
begin
 if a is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Compte permanent connecté requis' using errcode='42501'; end if;
 return a;
end $$;

create function koki_sport.role_in(p_club uuid) returns text language sql stable security definer set search_path='' as $$
 select m.role from koki_sport.club_members m where m.club_id=p_club and m.user_id=auth.uid() and m.statut='actif'
$$;

create function koki_sport.coach_cats(p_club uuid) returns uuid[] language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(sc.categorie_id),'{}') from koki_sport.staff s join koki_sport.staff_categories sc on sc.staff_id=s.id and sc.club_id=s.club_id
 where s.club_id=p_club and s.user_id=auth.uid() and s.statut='actif'
$$;

-- Permissions : read · profile · manage · players · sport · media · publish
create function koki_sport.can(p_club uuid, p_perm text, p_cat uuid default null) returns boolean language plpgsql stable security definer set search_path='' as $$
declare r text; st text;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then return false; end if;
 select c.statut into st from koki_sport.clubs c where c.id=p_club;
 if st is null or st='Archivé' then return false; end if;
 r:=koki_sport.role_in(p_club);
 if r is null then return false; end if;
 if p_perm='read' then return true; end if;
 if st not in ('À valider','Actif') then return false; end if;
 return case p_perm
  when 'profile' then r in ('responsable','communication')
  when 'manage'  then r='responsable'
  when 'media'   then r in ('responsable','communication')
  when 'publish' then st='Actif' and r in ('responsable','communication')
  when 'players' then r='responsable' or (r='entraineur' and p_cat is not null and p_cat=any(koki_sport.coach_cats(p_club)))
  when 'sport'   then r='responsable' or (r='entraineur' and p_cat is not null and p_cat=any(koki_sport.coach_cats(p_club)))
  else false end;
end $$;

create function koki_sport.require(p_club uuid, p_perm text, p_cat uuid default null) returns void language plpgsql stable set search_path='' as $$
begin if not coalesce(koki_sport.can(p_club,p_perm,p_cat),false) then perform koki_sport.deny(); end if; end $$;

-- ───────────── Filtres publics (consentements) ─────────────
create function koki_sport.public_name(p_player uuid) returns text language sql stable security definer set search_path='' as $$
 select case pc.nom_public when 'complet' then p.prenom||' '||p.nom when 'prenom_initiale' then p.prenom||' '||left(p.nom,1)||'.' end
 from koki_sport.players p join koki_sport.player_consents pc on pc.player_id=p.id and pc.club_id=p.club_id
 join koki_sport.clubs c on c.id=p.club_id
 where p.id=p_player and p.statut='actif' and pc.statut='actif' and c.statut='Actif'
$$;

create function koki_sport.media_public(p_media uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((
  select m.statut='actif' and c.statut='Actif'
   and (m.post_id is null or exists(select 1 from koki_sport.posts po where po.id=m.post_id and po.club_id=m.club_id and po.statut='publié' and po.publication<=now()))
   and case
    when not exists(select 1 from koki_sport.media_players mp where mp.media_id=m.id) then not m.contient_mineurs
    else not exists(select 1 from koki_sport.media_players mp
      left join koki_sport.player_consents pc on pc.player_id=mp.player_id and pc.statut='actif'
      left join koki_sport.players p on p.id=mp.player_id
      where mp.media_id=m.id and (pc.player_id is null or p.statut<>'actif'
        or (m.type='photo' and not pc.photo) or (m.type='youtube' and not pc.video)))
   end
  from koki_sport.media m join koki_sport.clubs c on c.id=m.club_id where m.id=p_media),false)
$$;

create function koki_sport.public_object(name text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from koki_sport.media m where m.storage_path=name and koki_sport.media_public(m.id))
  or exists(select 1 from koki_sport.clubs c where c.logo_path=name and c.statut='Actif')
  or exists(select 1 from koki_sport.staff s join koki_sport.clubs c on c.id=s.club_id where s.photo_path=name and s.public and s.statut='actif' and c.statut='Actif')
  or exists(select 1 from koki_sport.players p join koki_sport.player_consents pc on pc.player_id=p.id and pc.statut='actif'
            join koki_sport.clubs c on c.id=p.club_id
            where p.photo_path=name and p.statut='actif' and pc.photo and pc.nom_public<>'aucun' and c.statut='Actif')
$$;

-- Dossier de stockage = identifiant de l'académie.
create function koki_sport.folder_club(name text) returns uuid language plpgsql immutable set search_path='' as $$
begin
 if name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$' then return null; end if;
 return split_part(name,'/',1)::uuid;
exception when others then return null;
end $$;
create function koki_sport.club_writable(p_club uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from koki_sport.clubs c where c.id=p_club and c.statut in ('À valider','Actif'))
$$;
create function koki_sport.can_write_object(name text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(koki_sport.can(koki_sport.folder_club(name),'media') or koki_sport.can(koki_sport.folder_club(name),'manage')
  or (koki_sport.can(koki_sport.folder_club(name),'read') and koki_sport.role_in(koki_sport.folder_club(name))='entraineur'
      and koki_sport.club_writable(koki_sport.folder_club(name))),false)
$$;
create function koki_sport.can_read_object(name text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(koki_sport.can(koki_sport.folder_club(name),'read'),false)
$$;
create function koki_sport.object_unreferenced(name text) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from koki_sport.media where storage_path=name)
  and not exists(select 1 from koki_sport.clubs where logo_path=name)
  and not exists(select 1 from koki_sport.staff where photo_path=name)
  and not exists(select 1 from koki_sport.players where photo_path=name)
$$;

-- ───────────── Vues de lecture (privées) ─────────────
create function koki_sport.club_json(c koki_sport.clubs) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'slug',c.slug,'type',c.type,'nom',c.nom,'statut',c.statut,'motif',c.motif,'discipline',c.discipline,
  'presentation',c.presentation,'historique',c.historique,'activites',c.activites,'localite_id',c.localite_id,
  'localite',(select l.nom from public.koki_localites l where l.id=c.localite_id),'adresse',c.adresse,'latitude',c.latitude,'longitude',c.longitude,
  'telephone',c.telephone,'whatsapp',c.whatsapp,'logo_path',c.logo_path,'couleurs',to_jsonb(c.couleurs),'revision',c.revision,'updated_at',c.updated_at)
$$;

create function koki_sport.match_json(m koki_sport.matches) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',m.id,'categorie_id',m.categorie_id,'categorie',(select k.nom from koki_sport.categories k where k.id=m.categorie_id),
  'competition_id',m.competition_id,'competition',(select co.nom from koki_sport.competitions co where co.id=m.competition_id),
  'domicile',case when m.competition_id is not null then (select t.nom from koki_sport.competition_teams t where t.id=m.home_team_id)
                  when m.a_domicile then (select c.nom from koki_sport.clubs c where c.id=m.club_id) else m.adversaire end,
  'exterieur',case when m.competition_id is not null then (select t.nom from koki_sport.competition_teams t where t.id=m.away_team_id)
                  when m.a_domicile then m.adversaire else (select c.nom from koki_sport.clubs c where c.id=m.club_id) end,
  'home_team_id',m.home_team_id,'away_team_id',m.away_team_id,'adversaire',m.adversaire,'a_domicile',m.a_domicile,
  'date_match',m.date_match,'lieu',m.lieu,'statut',m.statut,'score_domicile',m.score_home,'score_exterieur',m.score_away,'journee',m.journee,'revision',m.revision)
$$;

-- Classement calculé (3 points victoire, 1 nul, 0 défaite), comme le module Sports & ASC.
create function koki_sport.standings(p_competition uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with r as (
  select m.home_team_id team, m.score_home gf, m.score_away ga from koki_sport.matches m where m.competition_id=p_competition and m.statut='Terminé'
  union all
  select m.away_team_id, m.score_away, m.score_home from koki_sport.matches m where m.competition_id=p_competition and m.statut='Terminé')
 select coalesce(jsonb_agg(x order by x.points desc, x.diff desc, x.bp desc, x.equipe),'[]'::jsonb) from (
  select t.nom equipe, t.is_self moi, count(r.team)::int joues,
   count(*) filter (where r.gf>r.ga)::int gagnes, count(*) filter (where r.gf=r.ga)::int nuls, count(*) filter (where r.gf<r.ga)::int perdus,
   coalesce(sum(r.gf),0)::int bp, coalesce(sum(r.ga),0)::int bc, coalesce(sum(r.gf)-sum(r.ga),0)::int diff,
   (3*count(*) filter (where r.gf>r.ga)+count(*) filter (where r.gf=r.ga))::int points
  from koki_sport.competition_teams t left join r on r.team=t.id where t.competition_id=p_competition group by t.id,t.nom,t.is_self) x
$$;

-- ───────────── Commandes ─────────────
create function koki_sport.handle(command text, input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 a uuid; club uuid; cat uuid; oldcat uuid; rid uuid; n integer; code text; h text; out jsonb; r text;
 c koki_sport.clubs; p koki_sport.players; s koki_sport.sessions; m koki_sport.matches; po koki_sport.posts; me koki_sport.media;
 co koki_sport.competitions; st koki_sport.staff; inv koki_sport.club_invitations; mb koki_sport.club_members; pc koki_sport.player_consents;
 g koki_sport.player_guardians; ca koki_sport.categories; x jsonb;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>65536 then raise exception 'Requête invalide ou trop volumineuse'; end if;
 a:=koki_sport.actor();

 if command='my_clubs' then
  perform koki_sport.keys(input,'{}');
  return coalesce((select jsonb_agg(koki_sport.club_json(c2)||jsonb_build_object('role',m2.role) order by c2.nom)
   from koki_sport.club_members m2 join koki_sport.clubs c2 on c2.id=m2.club_id where m2.user_id=a and m2.statut='actif' and c2.statut<>'Archivé'),'[]');

 elsif command='create_club' then
  perform koki_sport.keys(input,'{nom,type,discipline,localite_id,telephone,whatsapp,presentation}');
  if (select count(*) from koki_sport.club_members m2 join koki_sport.clubs c2 on c2.id=m2.club_id
      where m2.user_id=a and m2.role='responsable' and m2.statut='actif' and c2.statut<>'Archivé')>=3 then
   raise exception 'Trois académies au maximum par compte'; end if;
  h:=koki_sport.slugify(koki_sport.t(input,'nom'));
  if h='' then raise exception 'Nom invalide'; end if;
  n:=1; code:=h;
  while exists(select 1 from koki_sport.clubs where slug=code) loop n:=n+1; code:=left(h,66)||'-'||n; end loop;
  insert into koki_sport.clubs(nom,slug,type,discipline,localite_id,telephone,whatsapp,presentation,created_by)
  values(koki_sport.t(input,'nom'),code,koki_sport.t(input,'type','Académie'),koki_sport.t(input,'discipline','Football'),koki_sport.u(input,'localite_id',false),
   nullif(koki_sport.t(input,'telephone'),''),nullif(koki_sport.t(input,'whatsapp'),''),koki_sport.t(input,'presentation'),a) returning * into c;
  insert into koki_sport.club_members(club_id,user_id,role,invited_by) values(c.id,a,'responsable',a);
  return koki_sport.club_json(c)||jsonb_build_object('role','responsable');

 elsif command='accept_invitation' then
  perform koki_sport.keys(input,'{code}');
  perform pg_advisory_xact_lock(hashtextextended('sport-invite:'||a::text,0));
  if (select count(*) from koki_sport.invitation_attempts t where t.actor_id=a and t.created_at>now()-interval '15 minutes')>=5
   or (select count(*) from koki_sport.invitation_attempts t where t.actor_id=a and t.created_at>now()-interval '1 day')>=20 then
   raise exception 'Trop d’essais. Réessayez plus tard.'; end if;
  delete from koki_sport.invitation_attempts t where t.actor_id=a and t.created_at<now()-interval '2 days';
  insert into koki_sport.invitation_attempts(actor_id) values(a);
  h:=encode(extensions.digest(upper(regexp_replace(koki_sport.t(input,'code'),'[^A-Za-z0-9]','','g')),'sha256'),'hex');
  select * into inv from koki_sport.club_invitations i where i.code_hash=h for update;
  if inv.id is null or inv.statut<>'active' or inv.expires_at<now() then return jsonb_build_object('ok',false,'erreur','Code d’invitation invalide ou expiré'); end if;
  if not koki_sport.club_writable(inv.club_id) then raise exception 'Cette académie n’accepte pas de nouveaux membres pour le moment'; end if;
  select * into mb from koki_sport.club_members where club_id=inv.club_id and user_id=a;
  if mb.id is null then insert into koki_sport.club_members(club_id,user_id,role,invited_by) values(inv.club_id,a,inv.role,inv.created_by);
  else update koki_sport.club_members set role=case when mb.role='responsable' and mb.statut='actif' then 'responsable' else inv.role end, statut='actif' where id=mb.id; end if;
  if inv.staff_id is not null then
   update koki_sport.staff set user_id=null where club_id=inv.club_id and user_id=a and id<>inv.staff_id;
   update koki_sport.staff set user_id=a where id=inv.staff_id and club_id=inv.club_id;
  end if;
  update koki_sport.club_invitations set statut='utilisée', used_by=a where id=inv.id;
  select * into c from koki_sport.clubs where id=inv.club_id;
  return koki_sport.club_json(c)||jsonb_build_object('ok',true,'role',koki_sport.role_in(c.id));

 elsif command in ('follow','unfollow') then
  perform koki_sport.keys(input,'{club_id,notifications}');
  club:=koki_sport.u(input,'club_id');
  if command='unfollow' then delete from koki_sport.follows where user_id=a and club_id=club; return jsonb_build_object('suivi',false); end if;
  if not exists(select 1 from koki_sport.clubs where id=club and statut='Actif') then raise exception 'Académie introuvable'; end if;
  insert into koki_sport.follows(user_id,club_id,notifications) values(a,club,koki_sport.b(input,'notifications',true))
   on conflict(user_id,club_id) do update set notifications=excluded.notifications;
  return jsonb_build_object('suivi',true);

 elsif command='report' then
  perform koki_sport.keys(input,'{cible_type,cible_id,motif,details}');
  rid:=koki_sport.u(input,'cible_id');
  club:=case koki_sport.t(input,'cible_type')
   when 'club' then (select id from koki_sport.clubs where id=rid and statut='Actif')
   when 'post' then (select club_id from koki_sport.posts where id=rid and statut='publié')
   when 'media' then (select club_id from koki_sport.media where id=rid and koki_sport.media_public(id)) end;
  if club is null then raise exception 'Contenu introuvable'; end if;
  if (select count(*) from koki_sport.reports where reporter_id=a and created_at>now()-interval '1 hour')>=10 then raise exception 'Trop de signalements. Réessayez plus tard.'; end if;
  insert into koki_sport.reports(club_id,cible_type,cible_id,reporter_id,motif,details)
  values(club,koki_sport.t(input,'cible_type'),rid,a,koki_sport.t(input,'motif'),koki_sport.t(input,'details')) returning id into rid;
  return jsonb_build_object('id',rid);
 end if;

 if command like 'admin\_%' then
  return koki_sport.admin(command,input);
 end if;

 if command='club_get' then
  perform koki_sport.keys(input,'{club_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'read');
  select * into c from koki_sport.clubs where id=club; r:=koki_sport.role_in(club);
  return koki_sport.club_json(c)||jsonb_build_object('role',r,
   'categories_entraineur',to_jsonb(koki_sport.coach_cats(club)),
   'categories',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'nom',k.nom,'annee_min',k.annee_min,'annee_max',k.annee_max,'ordre',k.ordre,'statut',k.statut,'revision',k.revision,
      'joueurs',(select count(*) from koki_sport.players p2 where p2.categorie_id=k.id and p2.statut='actif')) order by k.ordre,k.nom) from koki_sport.categories k where k.club_id=club),'[]'),
   'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s2.id,'prenom',s2.prenom,'nom',s2.nom,'fonction',s2.fonction,'photo_path',s2.photo_path,'public',s2.public,'statut',s2.statut,'revision',s2.revision,
      'lie_a_un_compte',s2.user_id is not null,'telephone',case when r='responsable' then s2.telephone end,
      'categories',(select coalesce(jsonb_agg(sc.categorie_id),'[]') from koki_sport.staff_categories sc where sc.staff_id=s2.id)) order by s2.nom) from koki_sport.staff s2 where s2.club_id=club),'[]'),
   'membres',case when r='responsable' then coalesce((select jsonb_agg(jsonb_build_object('id',m2.id,'role',m2.role,'statut',m2.statut,'moi',m2.user_id=a,'revision',m2.revision,'depuis',m2.created_at)) from koki_sport.club_members m2 where m2.club_id=club),'[]') end,
   'invitations',case when r='responsable' then coalesce((select jsonb_agg(jsonb_build_object('id',i2.id,'role',i2.role,'expire',i2.expires_at,'statut',i2.statut)) from koki_sport.club_invitations i2 where i2.club_id=club and i2.statut='active' and i2.expires_at>now()),'[]') end,
   'compteurs',jsonb_build_object('joueurs',(select count(*) from koki_sport.players p2 where p2.club_id=club and p2.statut='actif'),
      'abonnes',(select count(*) from koki_sport.follows f where f.club_id=club),
      'publications',(select count(*) from koki_sport.posts p3 where p3.club_id=club and p3.statut='publié')),
   'prochaines_seances',coalesce((select jsonb_agg(to_jsonb(s3) order by s3.debut) from (select * from koki_sport.sessions s4 where s4.club_id=club and s4.debut>=now()-interval '3 hours' and s4.statut<>'annulée' order by s4.debut limit 10) s3),'[]'),
   'matchs',coalesce((select jsonb_agg(koki_sport.match_json(m3) order by m3.date_match desc) from (select * from koki_sport.matches m4 where m4.club_id=club order by m4.date_match desc limit 30) m3),'[]'),
   'competitions',coalesce((select jsonb_agg(to_jsonb(c3)||jsonb_build_object('equipes',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'nom',t.nom,'is_self',t.is_self) order by t.nom),'[]') from koki_sport.competition_teams t where t.competition_id=c3.id)) order by c3.created_at desc) from koki_sport.competitions c3 where c3.club_id=club),'[]'),
   'publications',coalesce((select jsonb_agg(to_jsonb(p5)-'masque_par'-'created_by' order by p5.created_at desc) from (select * from koki_sport.posts p6 where p6.club_id=club order by p6.created_at desc limit 30) p5),'[]'));

 elsif command='club_update' then
  perform koki_sport.keys(input,'{club_id,revision,nom,type,discipline,presentation,historique,activites,localite_id,adresse,latitude,longitude,telephone,whatsapp,logo_path,couleurs}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'profile');
  select * into c from koki_sport.clubs where id=club for update; perform koki_sport.check_revision(c.revision,input);
  if input ? 'logo_path' and nullif(koki_sport.t(input,'logo_path'),'') is not null and koki_sport.folder_club(koki_sport.t(input,'logo_path')) is distinct from club then raise exception 'Image hors du dossier de l’académie'; end if;
  update koki_sport.clubs set
   nom=case when input ? 'nom' then koki_sport.t(input,'nom') else nom end,
   type=case when input ? 'type' then koki_sport.t(input,'type') else type end,
   discipline=case when input ? 'discipline' then koki_sport.t(input,'discipline') else discipline end,
   presentation=case when input ? 'presentation' then koki_sport.t(input,'presentation') else presentation end,
   historique=case when input ? 'historique' then koki_sport.t(input,'historique') else historique end,
   activites=case when input ? 'activites' then koki_sport.t(input,'activites') else activites end,
   localite_id=case when input ? 'localite_id' then koki_sport.u(input,'localite_id',false) else localite_id end,
   adresse=case when input ? 'adresse' then koki_sport.t(input,'adresse') else adresse end,
   latitude=case when input ? 'latitude' then (input->>'latitude')::numeric else latitude end,
   longitude=case when input ? 'longitude' then (input->>'longitude')::numeric else longitude end,
   telephone=case when input ? 'telephone' then nullif(koki_sport.t(input,'telephone'),'') else telephone end,
   whatsapp=case when input ? 'whatsapp' then nullif(koki_sport.t(input,'whatsapp'),'') else whatsapp end,
   logo_path=case when input ? 'logo_path' then nullif(koki_sport.t(input,'logo_path'),'') else logo_path end,
   couleurs=case when input ? 'couleurs' then array(select lower(jsonb_array_elements_text(input->'couleurs'))) else couleurs end
  where id=club returning * into c;
  return koki_sport.club_json(c);

 elsif command='invite' then
  perform koki_sport.keys(input,'{club_id,role,staff_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'manage');
  return koki_sport.new_invitation(club,koki_sport.t(input,'role'),koki_sport.u(input,'staff_id',false),a);

 elsif command='invitation_cancel' then
  perform koki_sport.keys(input,'{id}');
  select * into inv from koki_sport.club_invitations where id=koki_sport.u(input,'id') for update;
  if inv.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(inv.club_id,'manage');
  update koki_sport.club_invitations set statut='annulée' where id=inv.id and statut='active';
  return jsonb_build_object('id',inv.id,'statut','annulée');

 elsif command='member_update' then
  perform koki_sport.keys(input,'{id,revision,role,statut}');
  select * into mb from koki_sport.club_members where id=koki_sport.u(input,'id') for update;
  if mb.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(mb.club_id,'manage'); perform koki_sport.check_revision(mb.revision,input);
  update koki_sport.club_members set role=coalesce(nullif(koki_sport.t(input,'role'),''),role), statut=coalesce(nullif(koki_sport.t(input,'statut'),''),statut) where id=mb.id returning * into mb;
  if mb.statut='retiré' then update koki_sport.staff set user_id=null where club_id=mb.club_id and user_id=mb.user_id; end if;
  return jsonb_build_object('id',mb.id,'role',mb.role,'statut',mb.statut,'revision',mb.revision);

 elsif command='category_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,nom,annee_min,annee_max,ordre,statut}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then
   club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'manage');
   if (select count(*) from koki_sport.categories where club_id=club)>=40 then raise exception '40 catégories au maximum'; end if;
   insert into koki_sport.categories(club_id,nom,annee_min,annee_max,ordre) values(club,koki_sport.t(input,'nom'),koki_sport.i(input,'annee_min'),koki_sport.i(input,'annee_max'),coalesce(koki_sport.i(input,'ordre'),0)) returning * into ca;
  else
   select * into ca from koki_sport.categories where id=rid for update;
   if ca.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(ca.club_id,'manage'); perform koki_sport.check_revision(ca.revision,input);
   if koki_sport.t(input,'statut',ca.statut)='archivée' and exists(select 1 from koki_sport.players where categorie_id=ca.id and statut='actif') then raise exception 'Déplacez d’abord les joueurs actifs de cette catégorie'; end if;
   update koki_sport.categories set nom=koki_sport.t(input,'nom',nom), annee_min=koki_sport.i(input,'annee_min'), annee_max=koki_sport.i(input,'annee_max'),
    ordre=coalesce(koki_sport.i(input,'ordre'),ordre), statut=koki_sport.t(input,'statut',statut) where id=rid returning * into ca;
  end if;
  return to_jsonb(ca);

 elsif command='staff_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,prenom,nom,fonction,telephone,photo_path,public,statut,categories}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then club:=koki_sport.u(input,'club_id'); else select club_id into club from koki_sport.staff where id=rid; end if;
  if club is null then perform koki_sport.deny(); end if; perform koki_sport.require(club,'manage');
  if nullif(koki_sport.t(input,'photo_path'),'') is not null and koki_sport.folder_club(koki_sport.t(input,'photo_path')) is distinct from club then raise exception 'Image hors du dossier de l’académie'; end if;
  if rid is null then
   insert into koki_sport.staff(club_id,prenom,nom,fonction,telephone,photo_path,public) values(club,koki_sport.t(input,'prenom'),koki_sport.t(input,'nom'),koki_sport.t(input,'fonction'),
    nullif(koki_sport.t(input,'telephone'),''),nullif(koki_sport.t(input,'photo_path'),''),koki_sport.b(input,'public')) returning * into st;
  else
   select * into st from koki_sport.staff where id=rid for update; perform koki_sport.check_revision(st.revision,input);
   update koki_sport.staff set prenom=koki_sport.t(input,'prenom',prenom), nom=koki_sport.t(input,'nom',nom), fonction=koki_sport.t(input,'fonction',fonction),
    telephone=case when input ? 'telephone' then nullif(koki_sport.t(input,'telephone'),'') else telephone end,
    photo_path=case when input ? 'photo_path' then nullif(koki_sport.t(input,'photo_path'),'') else photo_path end,
    public=koki_sport.b(input,'public',public), statut=koki_sport.t(input,'statut',statut),
    user_id=case when koki_sport.t(input,'statut',statut)='archivé' then null else user_id end where id=rid returning * into st;
  end if;
  if input ? 'categories' then
   delete from koki_sport.staff_categories where staff_id=st.id;
   insert into koki_sport.staff_categories(club_id,staff_id,categorie_id) select club,st.id,x2::uuid from jsonb_array_elements_text(input->'categories') x2;
  end if;
  return to_jsonb(st)-'user_id'||jsonb_build_object('categories',(select coalesce(jsonb_agg(categorie_id),'[]') from koki_sport.staff_categories where staff_id=st.id));

 elsif command='players_list' then
  perform koki_sport.keys(input,'{club_id,categorie_id,archives}');
  club:=koki_sport.u(input,'club_id'); cat:=koki_sport.u(input,'categorie_id',false); perform koki_sport.require(club,'read');
  r:=koki_sport.role_in(club);
  if r not in ('responsable','entraineur') then perform koki_sport.deny(); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p2.id,'categorie_id',p2.categorie_id,'prenom',p2.prenom,'nom',p2.nom,'annee_naissance',p2.annee_naissance,'poste',p2.poste,'numero',p2.numero,
     'photo_path',p2.photo_path,'statut',p2.statut,'revision',p2.revision,
     'consentement',(select jsonb_build_object('nom_public',pc2.nom_public,'photo',pc2.photo,'video',pc2.video,'stats',pc2.stats,'statut',pc2.statut) from koki_sport.player_consents pc2 where pc2.player_id=p2.id))
    order by p2.nom,p2.prenom)
   from koki_sport.players p2 where p2.club_id=club and (cat is null or p2.categorie_id=cat) and (p2.statut='actif' or koki_sport.b(input,'archives'))
    and (r='responsable' or p2.categorie_id=any(koki_sport.coach_cats(club)))),'[]');

 elsif command='player_get' then
  perform koki_sport.keys(input,'{id}');
  select * into p from koki_sport.players where id=koki_sport.u(input,'id');
  if p.id is null or not koki_sport.can(p.club_id,'players',p.categorie_id) then perform koki_sport.deny(); end if;
  return to_jsonb(p)||jsonb_build_object(
   'representants',(select coalesce(jsonb_agg(to_jsonb(g2) order by g2.created_at),'[]') from koki_sport.player_guardians g2 where g2.player_id=p.id and g2.statut='actif'),
   'consentement',(select to_jsonb(pc2)-'recueilli_par' from koki_sport.player_consents pc2 where pc2.player_id=p.id),
   'presences',(select jsonb_build_object('seances',count(*),'presents',count(*) filter (where present)) from koki_sport.attendance at2 where at2.player_id=p.id),
   'statistiques',(select jsonb_object_agg(type,n2) from (select type,count(*) n2 from koki_sport.match_events e where e.player_id=p.id group by type) z));

 elsif command='player_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,categorie_id,prenom,nom,annee_naissance,poste,numero,photo_path}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id');
  if rid is null then
   club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'players',cat);
   if (select count(*) from koki_sport.players where club_id=club and statut='actif')>=500 then raise exception '500 joueurs actifs au maximum'; end if;
  else
   select * into p from koki_sport.players where id=rid for update;
   if p.id is null then perform koki_sport.deny(); end if; club:=p.club_id;
   perform koki_sport.require(club,'players',p.categorie_id); perform koki_sport.require(club,'players',cat); perform koki_sport.check_revision(p.revision,input);
  end if;
  if not exists(select 1 from koki_sport.categories where id=cat and club_id=club and statut='active') then raise exception 'Catégorie invalide'; end if;
  if nullif(koki_sport.t(input,'photo_path'),'') is not null and koki_sport.folder_club(koki_sport.t(input,'photo_path')) is distinct from club then raise exception 'Image hors du dossier de l’académie'; end if;
  if rid is null then
   insert into koki_sport.players(club_id,categorie_id,prenom,nom,annee_naissance,poste,numero,photo_path) values(club,cat,koki_sport.t(input,'prenom'),koki_sport.t(input,'nom'),
    koki_sport.i(input,'annee_naissance'),koki_sport.t(input,'poste'),koki_sport.i(input,'numero'),nullif(koki_sport.t(input,'photo_path'),'')) returning * into p;
   insert into koki_sport.player_consents(club_id,player_id) values(club,p.id);
  else
   update koki_sport.players set categorie_id=cat, prenom=koki_sport.t(input,'prenom',prenom), nom=koki_sport.t(input,'nom',nom),
    annee_naissance=case when input ? 'annee_naissance' then koki_sport.i(input,'annee_naissance') else annee_naissance end,
    poste=koki_sport.t(input,'poste',poste), numero=case when input ? 'numero' then koki_sport.i(input,'numero') else numero end,
    photo_path=case when input ? 'photo_path' then nullif(koki_sport.t(input,'photo_path'),'') else photo_path end where id=rid returning * into p;
  end if;
  return to_jsonb(p);

 elsif command='player_archive' then
  perform koki_sport.keys(input,'{id,revision,restaurer}');
  select * into p from koki_sport.players where id=koki_sport.u(input,'id') for update;
  if p.id is null then perform koki_sport.deny(); end if;
  perform koki_sport.require(p.club_id,'players',p.categorie_id); perform koki_sport.check_revision(p.revision,input);
  if koki_sport.b(input,'restaurer') then update koki_sport.players set statut='actif', sorti_le=null where id=p.id returning * into p;
  else update koki_sport.players set statut='archivé', sorti_le=current_date where id=p.id returning * into p; end if;
  return to_jsonb(p);

 elsif command='guardian_save' then
  perform koki_sport.keys(input,'{player_id,id,revision,nom,lien,telephone,statut}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then select * into p from koki_sport.players where id=koki_sport.u(input,'player_id');
  else select * into g from koki_sport.player_guardians where id=rid for update; select * into p from koki_sport.players where id=g.player_id; end if;
  if p.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(p.club_id,'manage');
  if rid is null then
   if (select count(*) from koki_sport.player_guardians where player_id=p.id and statut='actif')>=3 then raise exception 'Trois représentants au maximum'; end if;
   insert into koki_sport.player_guardians(club_id,player_id,nom,lien,telephone) values(p.club_id,p.id,koki_sport.t(input,'nom'),koki_sport.t(input,'lien'),nullif(koki_sport.t(input,'telephone'),'')) returning * into g;
  else
   perform koki_sport.check_revision(g.revision,input);
   update koki_sport.player_guardians set nom=koki_sport.t(input,'nom',nom), lien=koki_sport.t(input,'lien',lien),
    telephone=case when input ? 'telephone' then nullif(koki_sport.t(input,'telephone'),'') else telephone end, statut=koki_sport.t(input,'statut',statut) where id=rid returning * into g;
  end if;
  return to_jsonb(g);

 elsif command in ('consent_save','consent_revoke') then
  perform koki_sport.keys(input,'{player_id,revision,nom_public,photo,video,stats,recueilli_le,mode}');
  select * into pc from koki_sport.player_consents where player_id=koki_sport.u(input,'player_id') for update;
  if pc.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(pc.club_id,'manage'); perform koki_sport.check_revision(pc.revision,input);
  if command='consent_revoke' then
   update koki_sport.player_consents set statut='retiré' where id=pc.id returning * into pc;
  else
   if (koki_sport.t(input,'nom_public','aucun')<>'aucun' or koki_sport.b(input,'photo') or koki_sport.b(input,'video') or koki_sport.b(input,'stats'))
    and not exists(select 1 from koki_sport.player_guardians where player_id=pc.player_id and statut='actif') then
    raise exception 'Enregistrez d’abord le représentant légal qui donne l’autorisation'; end if;
   if (koki_sport.b(input,'photo') or koki_sport.b(input,'video') or koki_sport.b(input,'stats')) and koki_sport.t(input,'nom_public','aucun')='aucun' and koki_sport.b(input,'stats') then
    raise exception 'Les statistiques publiques exigent un nom public'; end if;
   update koki_sport.player_consents set statut='actif', retire_le=null, nom_public=koki_sport.t(input,'nom_public','aucun'),
    photo=koki_sport.b(input,'photo'), video=koki_sport.b(input,'video'), stats=koki_sport.b(input,'stats'),
    recueilli_le=(nullif(input->>'recueilli_le',''))::date, mode=nullif(koki_sport.t(input,'mode'),''), recueilli_par=a where id=pc.id returning * into pc;
  end if;
  return to_jsonb(pc)-'recueilli_par';

 elsif command='session_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,categorie_id,debut,fin,lieu,theme,statut}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id');
  if rid is null then club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'sport',cat);
  else select * into s from koki_sport.sessions where id=rid for update; if s.id is null then perform koki_sport.deny(); end if;
   club:=s.club_id; perform koki_sport.require(club,'sport',s.categorie_id); perform koki_sport.require(club,'sport',cat); perform koki_sport.check_revision(s.revision,input); end if;
  if rid is null then
   insert into koki_sport.sessions(club_id,categorie_id,debut,fin,lieu,theme) values(club,cat,koki_sport.ts(input,'debut'),koki_sport.ts(input,'fin'),koki_sport.t(input,'lieu'),koki_sport.t(input,'theme')) returning * into s;
  else
   update koki_sport.sessions set categorie_id=cat, debut=koki_sport.ts(input,'debut'), fin=koki_sport.ts(input,'fin'), lieu=koki_sport.t(input,'lieu',lieu), theme=koki_sport.t(input,'theme',theme),
    statut=koki_sport.t(input,'statut',statut) where id=rid returning * into s;
  end if;
  return to_jsonb(s);

 elsif command='sessions_list' then
  perform koki_sport.keys(input,'{club_id,du,au}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'read');
  return coalesce((select jsonb_agg(to_jsonb(s2)||jsonb_build_object('categorie',(select nom from koki_sport.categories where id=s2.categorie_id)) order by s2.debut)
   from koki_sport.sessions s2 where s2.club_id=club and s2.debut>=coalesce(koki_sport.ts(input,'du',false),now()-interval '30 days') and s2.debut<=coalesce(koki_sport.ts(input,'au',false),now()+interval '60 days')),'[]');

 elsif command='attendance_save' then
  perform koki_sport.keys(input,'{session_id,presences}');
  select * into s from koki_sport.sessions where id=koki_sport.u(input,'session_id');
  if s.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(s.club_id,'sport',s.categorie_id);
  if jsonb_typeof(input->'presences')<>'array' or jsonb_array_length(input->'presences')>200 then raise exception 'Liste de présences invalide'; end if;
  insert into koki_sport.attendance(club_id,session_id,player_id,present)
   select s.club_id,s.id,(e->>'player_id')::uuid,(e->>'present')::boolean from jsonb_array_elements(input->'presences') e
   on conflict(session_id,player_id) do update set present=excluded.present, updated_at=now();
  return jsonb_build_object('session_id',s.id,'enregistrees',jsonb_array_length(input->'presences'));

 elsif command='attendance_get' then
  perform koki_sport.keys(input,'{session_id}');
  select * into s from koki_sport.sessions where id=koki_sport.u(input,'session_id');
  if s.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(s.club_id,'sport',s.categorie_id);
  return coalesce((select jsonb_agg(jsonb_build_object('player_id',at2.player_id,'present',at2.present)) from koki_sport.attendance at2 where at2.session_id=s.id),'[]');

 elsif command='competition_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,nom,saison,type,categorie_id,organisateur,statut}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id',false);
  if rid is null then club:=koki_sport.u(input,'club_id');
  else select * into co from koki_sport.competitions where id=rid for update; if co.id is null then perform koki_sport.deny(); end if; club:=co.club_id;
   if co.categorie_id is null then perform koki_sport.require(club,'manage'); else perform koki_sport.require(club,'sport',co.categorie_id); end if;
   perform koki_sport.check_revision(co.revision,input); end if;
  if cat is null then perform koki_sport.require(club,'manage'); else perform koki_sport.require(club,'sport',cat); end if;
  if rid is null then
   insert into koki_sport.competitions(club_id,nom,saison,type,categorie_id,organisateur) values(club,koki_sport.t(input,'nom'),koki_sport.t(input,'saison'),koki_sport.t(input,'type','Championnat'),cat,koki_sport.t(input,'organisateur')) returning * into co;
   insert into koki_sport.competition_teams(club_id,competition_id,nom,is_self) select club,co.id,c2.nom,true from koki_sport.clubs c2 where c2.id=club;
  else
   update koki_sport.competitions set nom=koki_sport.t(input,'nom',nom), saison=koki_sport.t(input,'saison',saison), type=koki_sport.t(input,'type',type), categorie_id=cat,
    organisateur=koki_sport.t(input,'organisateur',organisateur), statut=koki_sport.t(input,'statut',statut) where id=rid returning * into co;
  end if;
  return to_jsonb(co);

 elsif command in ('team_add','team_delete') then
  perform koki_sport.keys(input,'{competition_id,id,nom}');
  if command='team_add' then select * into co from koki_sport.competitions where id=koki_sport.u(input,'competition_id');
  else select co2.* into co from koki_sport.competitions co2 join koki_sport.competition_teams t on t.competition_id=co2.id where t.id=koki_sport.u(input,'id'); end if;
  if co.id is null then perform koki_sport.deny(); end if;
  if co.categorie_id is null then perform koki_sport.require(co.club_id,'manage'); else perform koki_sport.require(co.club_id,'sport',co.categorie_id); end if;
  if command='team_add' then
   if (select count(*) from koki_sport.competition_teams where competition_id=co.id)>=40 then raise exception '40 équipes au maximum'; end if;
   insert into koki_sport.competition_teams(club_id,competition_id,nom) values(co.club_id,co.id,koki_sport.t(input,'nom')) returning id into rid;
   return jsonb_build_object('id',rid,'nom',koki_sport.t(input,'nom'));
  end if;
  if exists(select 1 from koki_sport.competition_teams where id=koki_sport.u(input,'id') and is_self) then raise exception 'L’équipe de l’académie ne peut pas être retirée'; end if;
  delete from koki_sport.competition_teams where id=koki_sport.u(input,'id') and competition_id=co.id;
  return jsonb_build_object('id',koki_sport.u(input,'id'),'supprime',true);

 elsif command='match_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,categorie_id,competition_id,home_team_id,away_team_id,adversaire,a_domicile,date_match,lieu,statut,score_domicile,score_exterieur,journee}');
  rid:=koki_sport.u(input,'id',false); cat:=koki_sport.u(input,'categorie_id');
  if rid is null then club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'sport',cat);
  else select * into m from koki_sport.matches where id=rid for update; if m.id is null then perform koki_sport.deny(); end if;
   club:=m.club_id; perform koki_sport.require(club,'sport',m.categorie_id); perform koki_sport.require(club,'sport',cat); perform koki_sport.check_revision(m.revision,input); end if;
  if rid is null then
   insert into koki_sport.matches(club_id,categorie_id,competition_id,home_team_id,away_team_id,adversaire,a_domicile,date_match,lieu,statut,score_home,score_away,journee)
   values(club,cat,koki_sport.u(input,'competition_id',false),koki_sport.u(input,'home_team_id',false),koki_sport.u(input,'away_team_id',false),
    nullif(koki_sport.t(input,'adversaire'),''),case when input ? 'a_domicile' and input->'a_domicile'<>'null'::jsonb then koki_sport.b(input,'a_domicile') end,
    koki_sport.ts(input,'date_match'),koki_sport.t(input,'lieu'),koki_sport.t(input,'statut','À venir'),koki_sport.i(input,'score_domicile'),koki_sport.i(input,'score_exterieur'),koki_sport.t(input,'journee')) returning * into m;
  else
   update koki_sport.matches set categorie_id=cat, competition_id=koki_sport.u(input,'competition_id',false), home_team_id=koki_sport.u(input,'home_team_id',false), away_team_id=koki_sport.u(input,'away_team_id',false),
    adversaire=nullif(koki_sport.t(input,'adversaire'),''), a_domicile=case when input ? 'a_domicile' and input->'a_domicile'<>'null'::jsonb then koki_sport.b(input,'a_domicile') end,
    date_match=koki_sport.ts(input,'date_match'), lieu=koki_sport.t(input,'lieu',lieu), statut=koki_sport.t(input,'statut',statut),
    score_home=koki_sport.i(input,'score_domicile'), score_away=koki_sport.i(input,'score_exterieur'), journee=koki_sport.t(input,'journee',journee) where id=rid returning * into m;
  end if;
  return koki_sport.match_json(m);

 elsif command in ('match_event_add','match_event_delete') then
  perform koki_sport.keys(input,'{match_id,id,player_id,type,minute}');
  if command='match_event_add' then select * into m from koki_sport.matches where id=koki_sport.u(input,'match_id');
  else select m2.* into m from koki_sport.matches m2 join koki_sport.match_events e on e.match_id=m2.id where e.id=koki_sport.u(input,'id'); end if;
  if m.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(m.club_id,'sport',m.categorie_id);
  if command='match_event_delete' then delete from koki_sport.match_events where id=koki_sport.u(input,'id'); return jsonb_build_object('supprime',true); end if;
  insert into koki_sport.match_events(club_id,match_id,player_id,type,minute) values(m.club_id,m.id,koki_sport.u(input,'player_id'),koki_sport.t(input,'type'),koki_sport.i(input,'minute')) returning id into rid;
  return jsonb_build_object('id',rid);

 elsif command='standings' then
  perform koki_sport.keys(input,'{competition_id}');
  select * into co from koki_sport.competitions where id=koki_sport.u(input,'competition_id');
  if co.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(co.club_id,'read');
  return koki_sport.standings(co.id);

 elsif command='post_save' then
  perform koki_sport.keys(input,'{club_id,id,revision,type,titre,texte,evenement,lieu}');
  rid:=koki_sport.u(input,'id',false);
  if rid is null then club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'media');
   insert into koki_sport.posts(club_id,type,titre,texte,evenement,lieu,created_by) values(club,koki_sport.t(input,'type','Actualité'),koki_sport.t(input,'titre'),koki_sport.t(input,'texte'),
    koki_sport.ts(input,'evenement',false),koki_sport.t(input,'lieu'),a) returning * into po;
  else select * into po from koki_sport.posts where id=rid for update; if po.id is null then perform koki_sport.deny(); end if;
   perform koki_sport.require(po.club_id,'media'); perform koki_sport.check_revision(po.revision,input);
   if po.statut='masqué' then raise exception 'Publication masquée par la modération : contactez FAMpro Digital'; end if;
   update koki_sport.posts set type=koki_sport.t(input,'type',type), titre=koki_sport.t(input,'titre',titre), texte=koki_sport.t(input,'texte',texte),
    evenement=case when input ? 'evenement' then koki_sport.ts(input,'evenement',false) else evenement end, lieu=koki_sport.t(input,'lieu',lieu) where id=rid returning * into po;
  end if;
  return to_jsonb(po)-'masque_par'-'created_by';

 elsif command in ('post_publish','post_relay') then
  perform koki_sport.keys(input,'{id,revision,publier,publication}');
  select * into po from koki_sport.posts where id=koki_sport.u(input,'id') for update;
  if po.id is null then perform koki_sport.deny(); end if; perform koki_sport.check_revision(po.revision,input);
  if po.statut='masqué' then raise exception 'Publication masquée par la modération : contactez FAMpro Digital'; end if;
  if command='post_relay' then
   perform koki_sport.require(po.club_id,'publish');
   if po.statut<>'publié' then raise exception 'Publiez d’abord cette actualité'; end if;
   update koki_sport.posts set relais='demandé' where id=po.id and relais in ('aucun','refusé') returning * into po;
  elsif koki_sport.b(input,'publier',true) then
   perform koki_sport.require(po.club_id,'publish');
   update koki_sport.posts set statut='publié', publication=coalesce(koki_sport.ts(input,'publication',false),now()) where id=po.id returning * into po;
  else
   perform koki_sport.require(po.club_id,'media');
   update koki_sport.posts set statut='brouillon', publication=null where id=po.id returning * into po;
  end if;
  return to_jsonb(po)-'masque_par'-'created_by';

 elsif command='tagging_list' then
  perform koki_sport.keys(input,'{club_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'media');
  return coalesce((select jsonb_agg(jsonb_build_object('id',p2.id,'nom',p2.prenom||' '||left(p2.nom,1)||'.','categorie',k.nom,
     'photo',coalesce(pc2.statut='actif' and pc2.photo,false),'video',coalesce(pc2.statut='actif' and pc2.video,false)) order by k.ordre,p2.prenom)
   from koki_sport.players p2 join koki_sport.categories k on k.id=p2.categorie_id left join koki_sport.player_consents pc2 on pc2.player_id=p2.id
   where p2.club_id=club and p2.statut='actif'),'[]');

 elsif command='media_add' then
  perform koki_sport.keys(input,'{club_id,post_id,type,storage_path,youtube_id,legende,contient_mineurs,joueurs}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'media');
  if input->'contient_mineurs' is null or jsonb_typeof(input->'contient_mineurs')<>'boolean' then raise exception 'Indiquez si des mineurs sont reconnaissables sur ce média'; end if;
  if koki_sport.b(input,'contient_mineurs') and coalesce(jsonb_array_length(input->'joueurs'),0)=0 then raise exception 'Désignez les joueurs reconnaissables : sans eux, le média restera privé'; end if;
  if (select count(*) from koki_sport.media where club_id=club)>=2000 then raise exception 'Limite de médias atteinte'; end if;
  insert into koki_sport.media(club_id,post_id,type,storage_path,youtube_id,legende,contient_mineurs,created_by)
  values(club,koki_sport.u(input,'post_id',false),koki_sport.t(input,'type'),nullif(koki_sport.t(input,'storage_path'),''),nullif(koki_sport.t(input,'youtube_id'),''),koki_sport.t(input,'legende'),
   koki_sport.b(input,'contient_mineurs'),a) returning * into me;
  if jsonb_typeof(input->'joueurs')='array' then
   insert into koki_sport.media_players(club_id,media_id,player_id) select club,me.id,x2::uuid from jsonb_array_elements_text(input->'joueurs') x2 on conflict do nothing;
  end if;
  return to_jsonb(me)-'created_by'||jsonb_build_object('public',koki_sport.media_public(me.id));

 elsif command in ('media_hide','media_delete') then
  perform koki_sport.keys(input,'{id,motif}');
  select * into me from koki_sport.media where id=koki_sport.u(input,'id') for update;
  if me.id is null then perform koki_sport.deny(); end if; perform koki_sport.require(me.club_id,'media');
  if command='media_delete' then delete from koki_sport.media where id=me.id; return jsonb_build_object('id',me.id,'supprime',true,'storage_path',me.storage_path); end if;
  update koki_sport.media set statut='masqué', motif=nullif(koki_sport.t(input,'motif'),'') where id=me.id returning * into me;
  return to_jsonb(me)-'created_by';

 elsif command='media_list' then
  perform koki_sport.keys(input,'{club_id,post_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'read');
  return coalesce((select jsonb_agg(to_jsonb(m2)-'created_by'||jsonb_build_object('public',koki_sport.media_public(m2.id),
     'joueurs',(select coalesce(jsonb_agg(mp.player_id),'[]') from koki_sport.media_players mp where mp.media_id=m2.id)) order by m2.created_at desc)
   from koki_sport.media m2 where m2.club_id=club and (koki_sport.u(input,'post_id',false) is null or m2.post_id=koki_sport.u(input,'post_id',false))),'[]');

 elsif command='audit_list' then
  perform koki_sport.keys(input,'{club_id}');
  club:=koki_sport.u(input,'club_id'); perform koki_sport.require(club,'manage');
  return coalesce((select jsonb_agg(jsonb_build_object('operation',au.operation,'objet',au.table_name,'statut',au.details->>'statut','revision',au.details->'revision','date',au.created_at,
     'par_moi',au.actor_id=a) order by au.id desc) from (select * from public.koki_audit au2 where au2.record_id in (
     select id from koki_sport.clubs where id=club union all select id from koki_sport.club_members where club_id=club union all select id from koki_sport.categories where club_id=club
     union all select id from koki_sport.staff where club_id=club union all select id from koki_sport.players where club_id=club union all select id from koki_sport.player_consents where club_id=club
     union all select id from koki_sport.sessions where club_id=club union all select id from koki_sport.matches where club_id=club union all select id from koki_sport.posts where club_id=club
     union all select id from koki_sport.media where club_id=club) order by au2.id desc limit 100) au),'[]');
 end if;

 raise exception 'Commande inconnue';
end $$;

create function koki_sport.new_invitation(p_club uuid, p_role text, p_staff uuid, p_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare code text; i koki_sport.club_invitations; alphabet constant text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea;
begin
 if p_role not in ('responsable','entraineur','communication') then raise exception 'Rôle invalide'; end if;
 if p_staff is not null and not exists(select 1 from koki_sport.staff where id=p_staff and club_id=p_club and statut='actif') then raise exception 'Encadrant invalide'; end if;
 if (select count(*) from koki_sport.club_invitations where club_id=p_club and statut='active' and expires_at>now())>=20 then raise exception 'Trop d’invitations en cours'; end if;
 b:=extensions.gen_random_bytes(10); code:='';
 for k in 0..9 loop code:=code||substr(alphabet,(get_byte(b,k)%32)+1,1); end loop;
 insert into koki_sport.club_invitations(club_id,role,staff_id,code_hash,expires_at,created_by)
 values(p_club,p_role,p_staff,encode(extensions.digest(code,'sha256'),'hex'),now()+interval '72 hours',p_actor) returning * into i;
 return jsonb_build_object('id',i.id,'code',substr(code,1,5)||'-'||substr(code,6,5),'role',i.role,'expire',i.expires_at);
end $$;

-- ───────────── Administration FAMpro ─────────────
create function koki_sport.admin(command text, input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c koki_sport.clubs; rid uuid; n integer; h text; d text; out jsonb; rep koki_sport.reports;
begin
 if command in ('admin_clubs','admin_reports') then
  if not koki_private.allowed('read') then perform koki_sport.deny(); end if;
  if command='admin_clubs' then
   perform koki_sport.keys(input,'{statut}');
   return coalesce((select jsonb_agg(koki_sport.club_json(c2)||jsonb_build_object('created_at',c2.created_at,
      'responsables',(select count(*) from koki_sport.club_members m where m.club_id=c2.id and m.role='responsable' and m.statut='actif'),
      'joueurs',(select count(*) from koki_sport.players p where p.club_id=c2.id and p.statut='actif'),
      'signalements',(select count(*) from koki_sport.reports r where r.club_id=c2.id and r.statut<>'Traité')) order by c2.updated_at desc)
    from koki_sport.clubs c2 where nullif(koki_sport.t(input,'statut'),'') is null or c2.statut=koki_sport.t(input,'statut')),'[]');
  end if;
  perform koki_sport.keys(input,'{statut}');
  return coalesce((select jsonb_agg(to_jsonb(r2)-'reporter_id'||jsonb_build_object('academie',(select nom from koki_sport.clubs where id=r2.club_id)) order by r2.created_at desc)
   from koki_sport.reports r2 where nullif(koki_sport.t(input,'statut'),'') is null or r2.statut=koki_sport.t(input,'statut')),'[]');

 elsif command='admin_posts' then
  if not koki_private.allowed('read') then perform koki_sport.deny(); end if;
  perform koki_sport.keys(input,'{relais,club_id}');
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'club_id',p.club_id,'academie',c2.nom,'type',p.type,'titre',p.titre,'texte',p.texte,'statut',p.statut,
     'publication',p.publication,'relais',p.relais,'motif',p.motif,'revision',p.revision) order by p.updated_at desc)
   from (select * from koki_sport.posts p2 where (nullif(koki_sport.t(input,'relais'),'') is null or p2.relais=koki_sport.t(input,'relais'))
     and (koki_sport.u(input,'club_id',false) is null or p2.club_id=koki_sport.u(input,'club_id',false)) and p2.statut<>'brouillon' order by p2.updated_at desc limit 100) p
   join koki_sport.clubs c2 on c2.id=p.club_id),'[]');

 elsif command='admin_review' then
  if not koki_private.allowed('commerce') then perform koki_sport.deny(); end if;
  perform koki_sport.keys(input,'{id,revision,decision,motif}');
  select * into c from koki_sport.clubs where id=koki_sport.u(input,'id') for update;
  if c.id is null then raise exception 'Académie introuvable'; end if; perform koki_sport.check_revision(c.revision,input);
  d:=koki_sport.t(input,'decision');
  update koki_sport.clubs set statut=case d when 'approve' then 'Actif' when 'refuse' then 'Refusé' when 'suspend' then 'Suspendu' when 'reactivate' then 'Actif' when 'archive' then 'Archivé' end,
   motif=case when d in ('refuse','suspend','archive') then nullif(koki_sport.t(input,'motif'),'') else null end
  where id=c.id and ((d='approve' and c.statut in ('À valider','Refusé')) or (d='refuse' and c.statut='À valider') or (d='suspend' and c.statut='Actif')
   or (d='reactivate' and c.statut='Suspendu') or (d='archive' and c.statut<>'Archivé')) returning * into c;
  if not found then raise exception 'Décision impossible dans l’état actuel'; end if;
  return koki_sport.club_json(c);

 elsif command='admin_create_club' then
  if not koki_private.allowed('commerce') then perform koki_sport.deny(); end if;
  perform koki_sport.keys(input,'{nom,type,discipline,localite_id,telephone,whatsapp,presentation}');
  h:=koki_sport.slugify(koki_sport.t(input,'nom')); if h='' then raise exception 'Nom invalide'; end if;
  n:=1; d:=h; while exists(select 1 from koki_sport.clubs where slug=d) loop n:=n+1; d:=left(h,66)||'-'||n; end loop;
  insert into koki_sport.clubs(nom,slug,type,discipline,localite_id,telephone,whatsapp,presentation,statut,created_by)
  values(koki_sport.t(input,'nom'),d,koki_sport.t(input,'type','Académie'),koki_sport.t(input,'discipline','Football'),koki_sport.u(input,'localite_id',false),
   nullif(koki_sport.t(input,'telephone'),''),nullif(koki_sport.t(input,'whatsapp'),''),koki_sport.t(input,'presentation'),'Actif',auth.uid()) returning * into c;
  return koki_sport.club_json(c)||jsonb_build_object('invitation_responsable',koki_sport.new_invitation(c.id,'responsable',null,auth.uid()));

 elsif command='admin_invite' then
  if not koki_private.allowed('commerce') then perform koki_sport.deny(); end if;
  perform koki_sport.keys(input,'{club_id,role}');
  if not exists(select 1 from koki_sport.clubs where id=koki_sport.u(input,'club_id') and statut in ('À valider','Actif')) then raise exception 'Académie introuvable ou inactive'; end if;
  return koki_sport.new_invitation(koki_sport.u(input,'club_id'),koki_sport.t(input,'role','responsable'),null,auth.uid());

 elsif command='admin_hide' then
  if not koki_private.allowed('content') then perform koki_sport.deny(); end if;
  perform koki_sport.keys(input,'{cible_type,id,motif,masquer}');
  if length(koki_sport.t(input,'motif'))<5 and koki_sport.b(input,'masquer',true) then raise exception 'Motif obligatoire (5 caractères minimum)'; end if;
  if koki_sport.t(input,'cible_type')='post' then
   update koki_sport.posts set statut=case when koki_sport.b(input,'masquer',true) then 'masqué' else 'brouillon' end,
    publication=case when koki_sport.b(input,'masquer',true) then publication else null end,
    motif=case when koki_sport.b(input,'masquer',true) then koki_sport.t(input,'motif') end, masque_par=auth.uid() where id=koki_sport.u(input,'id') returning to_jsonb(posts.*) into out;
  elsif koki_sport.t(input,'cible_type')='media' then
   update koki_sport.media set statut=case when koki_sport.b(input,'masquer',true) then 'masqué' else 'actif' end,
    motif=case when koki_sport.b(input,'masquer',true) then koki_sport.t(input,'motif') end where id=koki_sport.u(input,'id') returning to_jsonb(media.*) into out;
  else raise exception 'Cible invalide'; end if;
  if out is null then raise exception 'Contenu introuvable'; end if;
  return out-'created_by'-'masque_par';

 elsif command='admin_relay' then
  if not koki_private.allowed('content') then perform koki_sport.deny(); end if;
  perform koki_sport.keys(input,'{id,decision}');
  update koki_sport.posts set relais=case when koki_sport.t(input,'decision')='accepte' then 'accepté' else 'refusé' end
  where id=koki_sport.u(input,'id') and relais='demandé' and statut='publié' returning to_jsonb(posts.*) into out;
  if out is null then raise exception 'Aucune demande de relais en attente pour cette publication'; end if;
  return out-'created_by'-'masque_par';

 elsif command='admin_report_status' then
  if not koki_private.allowed('content') then perform koki_sport.deny(); end if;
  perform koki_sport.keys(input,'{id,revision,statut,note}');
  select * into rep from koki_sport.reports where id=koki_sport.u(input,'id') for update;
  if rep.id is null then raise exception 'Signalement introuvable'; end if; perform koki_sport.check_revision(rep.revision,input);
  update koki_sport.reports set statut=koki_sport.t(input,'statut'), note_admin=nullif(koki_sport.t(input,'note'),''),
   traite_le=case when koki_sport.t(input,'statut')='Traité' then now() end, traite_par=auth.uid() where id=rep.id returning * into rep;
  return to_jsonb(rep)-'reporter_id';
 end if;
 raise exception 'Commande inconnue';
end $$;

-- ───────────── Lecture publique (visiteurs) ─────────────
create function koki_sport.public_api(command text, input jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c koki_sport.clubs; po koki_sport.posts; co koki_sport.competitions;
begin
 if input is null or jsonb_typeof(input)<>'object' or octet_length(input::text)>4096 then raise exception 'Requête invalide'; end if;
 if command='clubs' then
  perform koki_sport.keys(input,'{}');
  return coalesce((select jsonb_agg(jsonb_build_object('id',c2.id,'slug',c2.slug,'type',c2.type,'nom',c2.nom,'discipline',c2.discipline,
     'localite',(select l.nom from public.koki_localites l where l.id=c2.localite_id),'logo_path',c2.logo_path,'couleurs',to_jsonb(c2.couleurs),
     'resume',left(c2.presentation,200),'abonnes',(select count(*) from koki_sport.follows f where f.club_id=c2.id)) order by c2.nom)
   from koki_sport.clubs c2 where c2.statut='Actif'),'[]');

 elsif command='club' then
  perform koki_sport.keys(input,'{slug,id}');
  select * into c from koki_sport.clubs c2 where c2.statut='Actif' and (c2.slug=koki_sport.t(input,'slug') or c2.id::text=koki_sport.t(input,'id'));
  if c.id is null then raise exception 'Académie introuvable'; end if;
  return jsonb_build_object('id',c.id,'slug',c.slug,'type',c.type,'nom',c.nom,'discipline',c.discipline,'presentation',c.presentation,'historique',c.historique,'activites',c.activites,
   'localite',(select l.nom from public.koki_localites l where l.id=c.localite_id),'adresse',c.adresse,'latitude',c.latitude,'longitude',c.longitude,
   'telephone',c.telephone,'whatsapp',c.whatsapp,'logo_path',c.logo_path,'couleurs',to_jsonb(c.couleurs),
   'abonnes',(select count(*) from koki_sport.follows f where f.club_id=c.id),
   'je_suis',case when auth.uid() is not null then exists(select 1 from koki_sport.follows f where f.club_id=c.id and f.user_id=auth.uid()) else false end,
   'categories',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'nom',k.nom,'effectif',(select count(*) from koki_sport.players p where p.categorie_id=k.id and p.statut='actif')) order by k.ordre,k.nom)
      from koki_sport.categories k where k.club_id=c.id and k.statut='active'),'[]'),
   'encadrement',coalesce((select jsonb_agg(jsonb_build_object('prenom',s.prenom,'nom',s.nom,'fonction',s.fonction,'photo_path',s.photo_path) order by s.nom)
      from koki_sport.staff s where s.club_id=c.id and s.public and s.statut='actif'),'[]'),
   'joueurs',coalesce((select jsonb_agg(jsonb_build_object('nom',koki_sport.public_name(p.id),'categorie',k.nom,'poste',p.poste,'numero',p.numero,
       'photo_path',case when pc.photo then p.photo_path end) order by k.ordre,p.numero nulls last)
      from koki_sport.players p join koki_sport.player_consents pc on pc.player_id=p.id and pc.statut='actif' and pc.nom_public<>'aucun'
      join koki_sport.categories k on k.id=p.categorie_id where p.club_id=c.id and p.statut='actif'),'[]'),
   'seances',coalesce((select jsonb_agg(jsonb_build_object('categorie',k.nom,'debut',s.debut,'fin',s.fin,'lieu',s.lieu,'theme',s.theme,'statut',s.statut) order by s.debut)
      from koki_sport.sessions s join koki_sport.categories k on k.id=s.categorie_id where s.club_id=c.id and s.debut between now()-interval '3 hours' and now()+interval '14 days'),'[]'),
   'matchs',coalesce((select jsonb_agg(koki_sport.match_json(m)-'revision'-'home_team_id'-'away_team_id' order by m.date_match desc)
      from (select * from koki_sport.matches m2 where m2.club_id=c.id and m2.statut<>'Annulé' order by m2.date_match desc limit 30) m),'[]'),
   'competitions',coalesce((select jsonb_agg(jsonb_build_object('id',co2.id,'nom',co2.nom,'saison',co2.saison,'type',co2.type,'statut',co2.statut,
       'categorie',(select k.nom from koki_sport.categories k where k.id=co2.categorie_id),'classement',koki_sport.standings(co2.id)) order by co2.created_at desc)
      from koki_sport.competitions co2 where co2.club_id=c.id and co2.statut<>'archivée'),'[]'),
   'buteurs',coalesce((select jsonb_agg(jsonb_build_object('nom',z.nom,'buts',z.buts) order by z.buts desc) from (
      select koki_sport.public_name(e.player_id) nom, count(*)::int buts from koki_sport.match_events e
      join koki_sport.player_consents pc on pc.player_id=e.player_id and pc.statut='actif' and pc.stats and pc.nom_public<>'aucun'
      where e.club_id=c.id and e.type='but' group by e.player_id order by count(*) desc limit 10) z where z.nom is not null),'[]'),
   'publications',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'type',p.type,'titre',p.titre,'texte',p.texte,'publication',p.publication,'evenement',p.evenement,'lieu',p.lieu,
       'medias',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'type',m.type,'storage_path',m.storage_path,'youtube_id',m.youtube_id,'legende',m.legende) order by m.created_at),'[]')
                 from koki_sport.media m where m.post_id=p.id and koki_sport.media_public(m.id))) order by p.publication desc)
      from (select * from koki_sport.posts p2 where p2.club_id=c.id and p2.statut='publié' and p2.publication<=now() order by p2.publication desc limit 20) p),'[]'),
   'galerie',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'type',m.type,'storage_path',m.storage_path,'youtube_id',m.youtube_id,'legende',m.legende) order by m.created_at desc)
      from (select * from koki_sport.media m2 where m2.club_id=c.id and m2.post_id is null order by m2.created_at desc limit 60) m where koki_sport.media_public(m.id)),'[]'));

 elsif command='standings' then
  perform koki_sport.keys(input,'{competition_id}');
  select co2.* into co from koki_sport.competitions co2 join koki_sport.clubs c2 on c2.id=co2.club_id
  where co2.id=koki_sport.u(input,'competition_id') and c2.statut='Actif' and co2.statut<>'archivée';
  if co.id is null then raise exception 'Compétition introuvable'; end if;
  return koki_sport.standings(co.id);
 end if;
 raise exception 'Commande inconnue';
end $$;

-- ───────────── Points d'entrée exposés ─────────────
create function public.koki_sport(command text, input jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a uuid; k uuid; cached koki_sport.request_keys; out jsonb;
begin
 if input ? 'request_id' then
  a:=koki_sport.actor();
  begin k:=(input->>'request_id')::uuid; exception when others then raise exception 'request_id invalide'; end;
  select * into cached from koki_sport.request_keys r where r.actor_id=a and r.request_id=k;
  if cached.actor_id is not null then
   if cached.command<>command then raise exception 'request_id déjà utilisé pour une autre commande'; end if;
   return cached.output;
  end if;
  out:=koki_sport.handle(command,input-'request_id');
  insert into koki_sport.request_keys(actor_id,request_id,command,output) values(a,k,command,out);
  delete from koki_sport.request_keys r where r.actor_id=a and r.created_at<now()-interval '2 days';
  return out;
 end if;
 return koki_sport.handle(command,input);
end $$;

create function public.koki_sport_public(command text, input jsonb default '{}'::jsonb) returns jsonb language sql stable security definer set search_path='' as $$
 select koki_sport.public_api(command,input)
$$;

revoke all on all functions in schema koki_sport from public, anon, authenticated;
revoke all on function public.koki_sport(text,jsonb), public.koki_sport_public(text,jsonb) from public, anon, authenticated;
grant execute on function public.koki_sport(text,jsonb) to authenticated;
grant execute on function public.koki_sport_public(text,jsonb) to anon, authenticated;
-- Fonctions appelées par les politiques de stockage (migration 3/3) : exécutables, sans données renvoyées.
grant usage on schema koki_sport to anon, authenticated;
grant execute on function koki_sport.public_object(text) to anon, authenticated;
grant execute on function koki_sport.can_write_object(text), koki_sport.can_read_object(text), koki_sport.object_unreferenced(text) to authenticated;

commit;
