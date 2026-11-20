-- Espace Clubs & Académies — 1/3 : schéma, tables, contraintes, déclencheurs.
-- EN ATTENTE : non appliquée en production. Ne pas ajouter à reference/ordre.txt
-- avant application autorisée par le propriétaire (voir supabase/historique/README.md).
--
-- Principes :
--  * schéma privé koki_sport : aucun droit direct pour anon/authenticated, RLS activée
--    sans politique (refus par défaut). Accès uniquement par les RPC de la migration 2/3 ;
--  * chaque table porte club_id ; les références internes sont des clés étrangères
--    COMPOSITES (club_id, id) : une ligne ne peut jamais viser l'objet d'une autre académie ;
--  * aucune table existante n'est modifiée. Réutilisation de koki_private.stamp() et
--    koki_private.audit() (journal public.koki_audit : révision et statut, jamais le contenu) ;
--  * suppression de compte (public.koki_account_delete) : les références à auth.users sont
--    en CASCADE ou SET NULL pour ne jamais bloquer l'effacement d'un compte.

begin;

-- GARDE : état attendu, sinon arrêt (jamais deux fois, jamais sur une base inattendue).
do $$ begin
 if exists(select 1 from pg_namespace where nspname='koki_sport') then
  raise exception 'GARDE : le schéma koki_sport existe déjà';
 end if;
 if (select md5(pg_get_functiondef('koki_private.stamp()'::regprocedure)))<>'4306e3bf8d135b88cd2d90a94dc3f522'
  or (select md5(pg_get_functiondef('koki_private.audit()'::regprocedure)))<>'0c591f2c151f9d9752aa243e1fdedf5a'
  or (select md5(pg_get_functiondef('koki_private.allowed(text)'::regprocedure)))<>'65eb21efbcf33f88f9e1767ec92170fc'
  or (select md5(pg_get_functiondef('koki_private.business_keys_allowed(jsonb,text[])'::regprocedure)))<>'7ee1f283dfed6af80c491cef170d6e4f' then
  raise exception 'GARDE : fonctions de référence modifiées (stamp/audit/allowed/business_keys_allowed)';
 end if;
 if to_regclass('public.koki_localites') is null or to_regclass('public.koki_audit') is null then
  raise exception 'GARDE : tables de référence absentes';
 end if;
end $$;

create schema koki_sport;
revoke all on schema koki_sport from public, anon, authenticated;

-- Listes contrôlées partagées avec assets/sport/clubs-contract.js
create function koki_sport.phone_ok(v text) returns boolean language sql immutable set search_path='' as
$$ select v is null or v ~ '^\+?[0-9 ()-]{6,24}$' $$;
create function koki_sport.image_ok(v text) returns boolean language sql immutable set search_path='' as
$$ select v is null or v ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$' $$;
create function koki_sport.text_ok(v text, mini integer, maxi integer) returns boolean language sql immutable set search_path='' as
$$ select v is not null and length(btrim(v)) between mini and maxi $$;

-- ───────────── Académies ─────────────
create table koki_sport.clubs(
 id uuid primary key default gen_random_uuid(),
 type text not null default 'Académie' check (type in ('Académie','Club')),
 nom text not null check (koki_sport.text_ok(nom,2,120)),
 slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug)<=80),
 statut text not null default 'À valider' check (statut in ('À valider','Actif','Suspendu','Refusé','Archivé')),
 motif text check (motif is null or length(motif)<=500),
 discipline text not null default 'Football' check (discipline in ('Football','Basket-ball','Lutte','Handball','Volley-ball','Athlétisme','Autre')),
 presentation text not null default '' check (length(presentation)<=3000),
 historique text not null default '' check (length(historique)<=5000),
 activites text not null default '' check (length(activites)<=2000),
 localite_id uuid references public.koki_localites(id) on delete set null,
 adresse text not null default '' check (length(adresse)<=200),
 latitude numeric check (latitude is null or latitude between -90 and 90),
 longitude numeric check (longitude is null or longitude between -180 and 180),
 telephone text check (koki_sport.phone_ok(telephone)),
 whatsapp text check (koki_sport.phone_ok(whatsapp)),
 logo_path text check (koki_sport.image_ok(logo_path)),
 couleurs text[] not null default array['#087a3d'] check (cardinality(couleurs) between 1 and 2 and array_to_string(couleurs,',') ~ '^#[0-9a-f]{6}(,#[0-9a-f]{6})?$'),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 check ((latitude is null)=(longitude is null)),
 check (statut not in ('Refusé','Suspendu') or length(btrim(coalesce(motif,'')))>=5)
);

create table koki_sport.club_members(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('responsable','entraineur','communication')),
 statut text not null default 'actif' check (statut in ('actif','retiré')),
 invited_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,user_id), unique (club_id,id)
);
create index club_members_user on koki_sport.club_members(user_id) where statut='actif';

create table koki_sport.categories(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 nom text not null check (koki_sport.text_ok(nom,1,40)),
 annee_min integer check (annee_min is null or annee_min between 1950 and 2100),
 annee_max integer check (annee_max is null or annee_max between 1950 and 2100),
 ordre integer not null default 0 check (ordre between 0 and 1000),
 statut text not null default 'active' check (statut in ('active','archivée')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id),
 check (annee_min is null or annee_max is null or annee_min<=annee_max)
);
create unique index categories_nom on koki_sport.categories(club_id, lower(btrim(nom))) where statut='active';

create table koki_sport.staff(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 user_id uuid references auth.users(id) on delete set null,
 prenom text not null check (koki_sport.text_ok(prenom,1,60)),
 nom text not null check (koki_sport.text_ok(nom,1,60)),
 fonction text not null default '' check (length(fonction)<=60),
 telephone text check (koki_sport.phone_ok(telephone)),
 photo_path text check (koki_sport.image_ok(photo_path)),
 public boolean not null default false,
 statut text not null default 'actif' check (statut in ('actif','archivé')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id)
);
create unique index staff_user on koki_sport.staff(club_id,user_id) where user_id is not null and statut='actif';

create table koki_sport.staff_categories(
 club_id uuid not null,
 staff_id uuid not null,
 categorie_id uuid not null,
 primary key (staff_id,categorie_id),
 foreign key (club_id,staff_id) references koki_sport.staff(club_id,id) on delete cascade,
 foreign key (club_id,categorie_id) references koki_sport.categories(club_id,id) on delete cascade
);

-- ───────────── Joueurs (données de mineurs : privées par défaut) ─────────────
create table koki_sport.players(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 categorie_id uuid not null,
 prenom text not null check (koki_sport.text_ok(prenom,1,60)),
 nom text not null check (koki_sport.text_ok(nom,1,60)),
 annee_naissance integer check (annee_naissance is null or annee_naissance between 1950 and 2100),
 poste text not null default '' check (length(poste)<=40),
 numero integer check (numero is null or numero between 0 and 99),
 photo_path text check (koki_sport.image_ok(photo_path)),
 statut text not null default 'actif' check (statut in ('actif','archivé')),
 sorti_le date,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id),
 foreign key (club_id,categorie_id) references koki_sport.categories(club_id,id) on delete restrict,
 check ((statut='archivé')=(sorti_le is not null))
);
create index players_categorie on koki_sport.players(club_id,categorie_id) where statut='actif';

create table koki_sport.player_guardians(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 player_id uuid not null,
 nom text not null check (koki_sport.text_ok(nom,2,120)),
 lien text not null default '' check (length(lien)<=40),
 telephone text check (koki_sport.phone_ok(telephone)),
 statut text not null default 'actif' check (statut in ('actif','retiré')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 foreign key (club_id,player_id) references koki_sport.players(club_id,id) on delete cascade
);
create index guardians_player on koki_sport.player_guardians(player_id);

create table koki_sport.player_consents(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 player_id uuid not null unique,
 nom_public text not null default 'aucun' check (nom_public in ('aucun','prenom_initiale','complet')),
 photo boolean not null default false,
 video boolean not null default false,
 stats boolean not null default false,
 recueilli_le date,
 mode text check (mode is null or mode in ('papier','oral','whatsapp','autre')),
 recueilli_par uuid references auth.users(id) on delete set null,
 retire_le timestamptz,
 statut text not null default 'actif' check (statut in ('actif','retiré')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 foreign key (club_id,player_id) references koki_sport.players(club_id,id) on delete cascade,
 -- Toute autorisation exige la date et le mode de recueil.
 check ((nom_public='aucun' and not photo and not video and not stats) or (recueilli_le is not null and mode is not null)),
 check ((statut='retiré')=(retire_le is not null)),
 check (statut='actif' or (nom_public='aucun' and not photo and not video and not stats))
);

-- ───────────── Activités sportives ─────────────
create table koki_sport.sessions(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 categorie_id uuid not null,
 debut timestamptz not null,
 fin timestamptz not null,
 lieu text not null default '' check (length(lieu)<=120),
 theme text not null default '' check (length(theme)<=200),
 statut text not null default 'planifiée' check (statut in ('planifiée','réalisée','annulée')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id),
 foreign key (club_id,categorie_id) references koki_sport.categories(club_id,id) on delete restrict,
 check (fin>debut and fin-debut<=interval '12 hours')
);
create index sessions_club on koki_sport.sessions(club_id,debut);

create table koki_sport.attendance(
 club_id uuid not null,
 session_id uuid not null,
 player_id uuid not null,
 present boolean not null,
 updated_at timestamptz not null default now(),
 primary key (session_id,player_id),
 foreign key (club_id,session_id) references koki_sport.sessions(club_id,id) on delete cascade,
 foreign key (club_id,player_id) references koki_sport.players(club_id,id) on delete cascade
);

create table koki_sport.competitions(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 nom text not null check (koki_sport.text_ok(nom,2,120)),
 saison text not null default '' check (length(saison)<=20),
 type text not null default 'Championnat' check (type in ('Championnat','Coupe','Tournoi','Amical')),
 categorie_id uuid,
 organisateur text not null default '' check (length(organisateur)<=120),
 statut text not null default 'active' check (statut in ('active','terminée','archivée')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id),
 foreign key (club_id,categorie_id) references koki_sport.categories(club_id,id) on delete restrict
);

create table koki_sport.competition_teams(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 competition_id uuid not null,
 nom text not null check (koki_sport.text_ok(nom,1,80)),
 is_self boolean not null default false,
 unique (club_id,competition_id,id),
 foreign key (club_id,competition_id) references koki_sport.competitions(club_id,id) on delete cascade
);
create unique index competition_teams_nom on koki_sport.competition_teams(competition_id, lower(btrim(nom)));
create unique index competition_teams_self on koki_sport.competition_teams(competition_id) where is_self;

create table koki_sport.matches(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 categorie_id uuid not null,
 competition_id uuid,
 home_team_id uuid,
 away_team_id uuid,
 adversaire text check (adversaire is null or koki_sport.text_ok(adversaire,1,80)),
 a_domicile boolean,
 date_match timestamptz not null,
 lieu text not null default '' check (length(lieu)<=120),
 statut text not null default 'À venir' check (statut in ('À venir','En direct','Terminé','Reporté','Annulé')),
 score_home integer check (score_home is null or score_home between 0 and 999),
 score_away integer check (score_away is null or score_away between 0 and 999),
 journee text not null default '' check (length(journee)<=40),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id),
 foreign key (club_id,categorie_id) references koki_sport.categories(club_id,id) on delete restrict,
 foreign key (club_id,competition_id) references koki_sport.competitions(club_id,id) on delete restrict,
 foreign key (club_id,competition_id,home_team_id) references koki_sport.competition_teams(club_id,competition_id,id) on delete restrict,
 foreign key (club_id,competition_id,away_team_id) references koki_sport.competition_teams(club_id,competition_id,id) on delete restrict,
 -- Match de compétition : deux équipes engagées distinctes. Match hors compétition : adversaire + domicile/extérieur.
 check ((competition_id is not null and home_team_id is not null and away_team_id is not null and home_team_id<>away_team_id and adversaire is null and a_domicile is null)
     or (competition_id is null and home_team_id is null and away_team_id is null and adversaire is not null and a_domicile is not null)),
 check ((score_home is null)=(score_away is null)),
 check (statut not in ('Terminé','En direct') or score_home is not null)
);
create index matches_club on koki_sport.matches(club_id,date_match);
create index matches_competition on koki_sport.matches(competition_id) where competition_id is not null;

create table koki_sport.match_events(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null,
 match_id uuid not null,
 player_id uuid not null,
 type text not null check (type in ('but','passe','carton_jaune','carton_rouge')),
 minute integer check (minute is null or minute between 0 and 130),
 created_at timestamptz not null default now(),
 foreign key (club_id,match_id) references koki_sport.matches(club_id,id) on delete cascade,
 foreign key (club_id,player_id) references koki_sport.players(club_id,id) on delete cascade
);
create index match_events_match on koki_sport.match_events(match_id);

-- ───────────── Communication ─────────────
create table koki_sport.posts(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 type text not null default 'Actualité' check (type in ('Actualité','Annonce','Événement','Performance')),
 titre text not null check (koki_sport.text_ok(titre,1,180)),
 texte text not null default '' check (length(texte)<=10000),
 statut text not null default 'brouillon' check (statut in ('brouillon','publié','masqué')),
 publication timestamptz,
 evenement timestamptz,
 lieu text not null default '' check (length(lieu)<=120),
 motif text check (motif is null or length(motif)<=500),
 masque_par uuid references auth.users(id) on delete set null,
 relais text not null default 'aucun' check (relais in ('aucun','demandé','accepté','refusé')),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id),
 check (statut<>'publié' or publication is not null),
 check (statut<>'masqué' or length(btrim(coalesce(motif,'')))>=5),
 check (type<>'Événement' or evenement is not null)
);
create index posts_club on koki_sport.posts(club_id,statut,publication desc);

create table koki_sport.media(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 post_id uuid,
 type text not null check (type in ('photo','youtube')),
 storage_path text check (koki_sport.image_ok(storage_path)),
 youtube_id text check (youtube_id is null or youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
 legende text not null default '' check (length(legende)<=300),
 contient_mineurs boolean not null,
 statut text not null default 'actif' check (statut in ('actif','masqué')),
 motif text check (motif is null or length(motif)<=500),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 unique (club_id,id),
 foreign key (club_id,post_id) references koki_sport.posts(club_id,id) on delete cascade,
 check ((type='photo' and storage_path is not null and youtube_id is null) or (type='youtube' and youtube_id is not null and storage_path is null)),
 -- Le fichier doit être rangé dans le dossier de SON académie.
 check (storage_path is null or split_part(storage_path,'/',1)=club_id::text)
);
create unique index media_path on koki_sport.media(storage_path) where storage_path is not null;

create table koki_sport.media_players(
 club_id uuid not null,
 media_id uuid not null,
 player_id uuid not null,
 primary key (media_id,player_id),
 foreign key (club_id,media_id) references koki_sport.media(club_id,id) on delete cascade,
 foreign key (club_id,player_id) references koki_sport.players(club_id,id) on delete cascade
);

-- ───────────── Communauté et administration ─────────────
create table koki_sport.club_invitations(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 role text not null check (role in ('responsable','entraineur','communication')),
 staff_id uuid,
 code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
 expires_at timestamptz not null,
 statut text not null default 'active' check (statut in ('active','utilisée','annulée')),
 used_by uuid references auth.users(id) on delete set null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 foreign key (club_id,staff_id) references koki_sport.staff(club_id,id) on delete cascade
);

create table koki_sport.invitation_attempts(
 actor_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create index invitation_attempts_actor on koki_sport.invitation_attempts(actor_id,created_at);

create table koki_sport.follows(
 user_id uuid not null references auth.users(id) on delete cascade,
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 notifications boolean not null default true,
 created_at timestamptz not null default now(),
 primary key (user_id,club_id)
);
create index follows_club on koki_sport.follows(club_id);

create table koki_sport.reports(
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null references koki_sport.clubs(id) on delete cascade,
 cible_type text not null check (cible_type in ('club','post','media')),
 cible_id uuid not null,
 reporter_id uuid references auth.users(id) on delete set null,
 motif text not null check (motif in ('Mineur exposé','Contenu inapproprié','Fausse information','Autre')),
 details text not null default '' check (length(details)<=1000),
 statut text not null default 'Nouveau' check (statut in ('Nouveau','En cours','Traité')),
 note_admin text check (note_admin is null or length(note_admin)<=1000),
 traite_le timestamptz,
 traite_par uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1
);

create table koki_sport.request_keys(
 actor_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null,
 command text not null,
 output jsonb not null,
 created_at timestamptz not null default now(),
 primary key (actor_id,request_id)
);

-- ───────────── Déclencheurs ─────────────
do $$ declare t text; begin
 foreach t in array array['clubs','club_members','categories','staff','players','player_guardians','player_consents','sessions','competitions','matches','posts','media','club_invitations','reports'] loop
  execute format('create trigger %I before insert or update on koki_sport.%I for each row execute function koki_private.stamp()', t||'_stamp', t);
  execute format('create trigger %I after insert or update or delete on koki_sport.%I for each row execute function koki_private.audit()', t||'_audit', t);
 end loop;
end $$;

-- Au moins un responsable actif par académie. Ne bloque jamais l'effacement d'un compte
-- (cascade depuis auth.users : le compte n'existe déjà plus) ni la suppression de l'académie.
create function koki_sport.keep_responsable() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.role='responsable' and old.statut='actif'
  and (tg_op='DELETE' or new.role<>'responsable' or new.statut<>'actif')
  and exists(select 1 from auth.users u where u.id=old.user_id)
  and exists(select 1 from koki_sport.clubs c where c.id=old.club_id)
  and not exists(select 1 from koki_sport.club_members m where m.club_id=old.club_id and m.id<>old.id and m.role='responsable' and m.statut='actif') then
  raise exception 'L’académie doit garder au moins un responsable actif';
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
create trigger club_members_keep_responsable before update or delete on koki_sport.club_members
 for each row execute function koki_sport.keep_responsable();

-- Retrait d'un consentement : toutes les autorisations retombent.
create function koki_sport.consent_revoke() returns trigger language plpgsql set search_path='' as $$
begin
 if new.statut='retiré' then new.nom_public:='aucun';new.photo:=false;new.video:=false;new.stats:=false;new.retire_le:=coalesce(new.retire_le,now());end if;
 return new;
end $$;
create trigger player_consents_revoke before insert or update on koki_sport.player_consents
 for each row execute function koki_sport.consent_revoke();

-- ───────────── Verrouillage ─────────────
do $$ declare t text; begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='koki_sport' and c.relkind='r' loop
  execute format('alter table koki_sport.%I enable row level security', t);
 end loop;
end $$;
revoke all on all tables in schema koki_sport from public, anon, authenticated;
revoke all on all functions in schema koki_sport from public, anon, authenticated;

commit;
