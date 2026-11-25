-- Module Football (scores en direct, calendriers, compétitions, équipes, classements) — 1/2 : schéma.
-- NON APPLIQUÉE EN PRODUCTION. Testée en local (outils/tester-foot.sh). Application en production
-- seulement après accord écrit de Mourtada Fam.
--
-- Principes :
--  * schéma privé koki_foot : aucun droit direct pour anon/authenticated, RLS activée sans
--    politique (refus par défaut). Accès uniquement par les RPC de la migration 2/2 ;
--  * aucune table existante n'est modifiée ; aucune donnée existante n'est touchée.
--    Les modules « Sports & ASC » (koki_contents) et Clubs & Académies (koki_sport) restent intacts ;
--  * deux sources : « manuel » (saisie des administrateurs) et « api » (fournisseur externe).
--    Une ligne api est identifiée par (fournisseur, ref_fournisseur) : un import ne crée jamais de doublon ;
--  * protection des corrections : la synchronisation ne modifie jamais une ligne manuelle. Sur un match api,
--    une correction pose un verrou : verrou_manuel (global, comportement actuel) et, en préparation de
--    l'évolution, des verrous indépendants verrou_score / verrou_statut / verrou_evenements / verrou_programmation.
--    Une divergence entre l'API et une valeur verrouillée n'est jamais ignorée en silence : elle est inscrite
--    dans koki_foot.conflits jusqu'à décision d'un administrateur ;
--  * scores distincts : réglementaire (score_*), buts de prolongation (pro_*), tirs au but (tab_*) ;
--    chaque événement porte sa PÉRIODE explicite (mi_temps_1/2, prolongation_1/2, tirs_au_but), la minute
--    affichée et le temps additionnel séparément : aucune période n'est déduite de la minute ;
--  * programmation : la dernière valeur reçue du fournisseur (api_date_match, api_lieu) est conservée à côté
--    de la valeur publiée ; historique des deux dans historique_programmation ; tout changement d'horaire d'un
--    match publié est inscrit dans changements_horaire (file pour le futur module de notifications) ;
--  * journal des corrections chaîné (empreinte SHA-256 de la ligne précédente) : une altération faite en
--    contournant les déclencheurs (propriétaire, superutilisateur) devient détectable (verifier_journal) ;
--  * fraîcheur : source du résultat, date de dernière synchronisation par match, état de chaque fournisseur ;
--  * journal : koki_private.audit() (révision et statut) + koki_foot.corrections (avant/après, auteur,
--    motif), en ajout seul : aucune correction ne peut être modifiée ni effacée.

begin;

-- GARDE : état attendu, sinon arrêt (jamais deux fois, jamais sur une base inattendue).
do $$ begin
 if exists(select 1 from pg_namespace where nspname='koki_foot') then
  raise exception 'GARDE : le schéma koki_foot existe déjà';
 end if;
 if (select md5(pg_get_functiondef('koki_private.stamp()'::regprocedure)))<>'4306e3bf8d135b88cd2d90a94dc3f522'
  or (select md5(pg_get_functiondef('koki_private.audit()'::regprocedure)))<>'0c591f2c151f9d9752aa243e1fdedf5a'
  or (select md5(pg_get_functiondef('koki_private.allowed(text)'::regprocedure)))<>'65eb21efbcf33f88f9e1767ec92170fc' then
  raise exception 'GARDE : fonctions de référence modifiées (stamp/audit/allowed)';
 end if;
 if to_regclass('public.koki_audit') is null then
  raise exception 'GARDE : table public.koki_audit absente';
 end if;
end $$;

create schema koki_foot;
revoke all on schema koki_foot from public, anon, authenticated;

create function koki_foot.texte_ok(v text, mini integer, maxi integer) returns boolean language sql immutable set search_path='' as
$$ select v is not null and length(btrim(v)) between mini and maxi $$;
-- Logos fournis par l'API : adresse https uniquement (affichée telle quelle, jamais exécutée).
create function koki_foot.url_ok(v text) returns boolean language sql immutable set search_path='' as
$$ select v is null or (v ~ '^https://[A-Za-z0-9.-]+/[^\s<>"'']*$' and length(v)<=500) $$;

-- ───────────── Compétitions ─────────────
create table koki_foot.competitions(
 id uuid primary key default gen_random_uuid(),
 nom text not null check (koki_foot.texte_ok(nom,2,120)),
 saison text not null default '' check (length(saison)<=20),
 portee text not null default 'Koki' check (portee in ('Koki','Sénégal','International')),
 type text not null default 'Championnat' check (type in ('Championnat','Coupe','Tournoi','Amical')),
 source text not null default 'manuel' check (source in ('manuel','api')),
 fournisseur text check (fournisseur in ('api-football','sportmonks')),
 ref_fournisseur text check (ref_fournisseur is null or length(ref_fournisseur) between 1 and 64),
 logo_url text check (koki_foot.url_ok(logo_url)),
 statut text not null default 'active' check (statut in ('active','terminée','archivée')),
 publie boolean not null default false,
 ordre integer not null default 100 check (ordre between 0 and 1000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 check ((source='manuel' and fournisseur is null and ref_fournisseur is null) or (source='api' and fournisseur is not null and ref_fournisseur is not null)),
 unique (fournisseur, ref_fournisseur)
);

-- ───────────── Équipes ─────────────
create table koki_foot.equipes(
 id uuid primary key default gen_random_uuid(),
 nom text not null check (koki_foot.texte_ok(nom,1,80)),
 nom_court text not null default '' check (length(nom_court)<=20),
 portee text not null default 'Koki' check (portee in ('Koki','Sénégal','International')),
 quartier text not null default '' check (length(quartier)<=80),
 couleurs text[] not null default '{"#087a3d"}' check (cardinality(couleurs) between 1 and 2 and array_to_string(couleurs,',') ~ '^#[0-9a-f]{6}(,#[0-9a-f]{6})?$'),
 source text not null default 'manuel' check (source in ('manuel','api')),
 fournisseur text check (fournisseur in ('api-football','sportmonks')),
 ref_fournisseur text check (ref_fournisseur is null or length(ref_fournisseur) between 1 and 64),
 logo_url text check (koki_foot.url_ok(logo_url)),
 statut text not null default 'active' check (statut in ('active','archivée')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 check ((source='manuel' and fournisseur is null and ref_fournisseur is null) or (source='api' and fournisseur is not null and ref_fournisseur is not null)),
 unique (fournisseur, ref_fournisseur)
);
create unique index equipes_nom_manuel on koki_foot.equipes(lower(btrim(nom))) where source='manuel';

create table koki_foot.competition_equipes(
 competition_id uuid not null references koki_foot.competitions(id) on delete cascade,
 equipe_id uuid not null references koki_foot.equipes(id) on delete cascade,
 poule text not null default '' check (length(poule)<=40),
 primary key (competition_id, equipe_id)
);
create index competition_equipes_equipe on koki_foot.competition_equipes(equipe_id);

-- ───────────── Matchs ─────────────
create table koki_foot.matchs(
 id uuid primary key default gen_random_uuid(),
 competition_id uuid not null references koki_foot.competitions(id) on delete restrict,
 domicile_id uuid not null references koki_foot.equipes(id) on delete restrict,
 exterieur_id uuid not null references koki_foot.equipes(id) on delete restrict,
 date_match timestamptz not null,
 lieu text not null default '' check (length(lieu)<=120),
 poule text not null default '' check (length(poule)<=40),
 journee text not null default '' check (length(journee)<=40),
 statut text not null default 'À venir' check (statut in ('À venir','En direct','Mi-temps','Prolongations','Tirs au but','Terminé','Reporté','Annulé','Interrompu','Suspendu')),
 minute integer check (minute is null or minute between 0 and 150),
 -- Score réglementaire (temps réglementaire seulement).
 score_domicile integer check (score_domicile is null or score_domicile between 0 and 99),
 score_exterieur integer check (score_exterieur is null or score_exterieur between 0 and 99),
 -- Buts marqués pendant la prolongation (en plus du score réglementaire).
 pro_domicile integer check (pro_domicile is null or pro_domicile between 0 and 99),
 pro_exterieur integer check (pro_exterieur is null or pro_exterieur between 0 and 99),
 -- Séance de tirs au but.
 tab_domicile integer check (tab_domicile is null or tab_domicile between 0 and 99),
 tab_exterieur integer check (tab_exterieur is null or tab_exterieur between 0 and 99),
 -- Dernière programmation reçue du fournisseur (conservée même si la valeur publiée est corrigée).
 api_date_match timestamptz,
 api_lieu text check (api_lieu is null or length(api_lieu)<=120),
 -- Forfait : équipe forfait (résultat officiel saisi dans le score) ; match rejoué : lien vers le match d'origine.
 forfait_equipe_id uuid references koki_foot.equipes(id) on delete restrict,
 rejoue_de uuid references koki_foot.matchs(id) on delete set null,
 commentaire text not null default '' check (length(commentaire)<=500),
 source text not null default 'manuel' check (source in ('manuel','api')),
 fournisseur text check (fournisseur in ('api-football','sportmonks')),
 ref_fournisseur text check (ref_fournisseur is null or length(ref_fournisseur) between 1 and 64),
 verrou_manuel boolean not null default false,
 verrou_score boolean not null default false,
 verrou_statut boolean not null default false,
 verrou_evenements boolean not null default false,
 verrou_programmation boolean not null default false,
 resultat_source text not null default 'manuel' check (resultat_source in ('manuel','api','correction')),
 verrouille_par uuid references auth.users(id) on delete set null,
 verrouille_le timestamptz,
 synchronise_le timestamptz,
 publie boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 revision integer not null default 1,
 check (domicile_id<>exterieur_id),
 check ((score_domicile is null)=(score_exterieur is null)),
 check ((tab_domicile is null)=(tab_exterieur is null)),
 check ((pro_domicile is null)=(pro_exterieur is null)),
 check (pro_domicile is null or score_domicile is not null),
 check (tab_domicile is null or score_domicile is not null),
 check (statut not in ('Terminé','En direct','Mi-temps','Prolongations','Tirs au but','Interrompu') or score_domicile is not null),
 check (statut in ('En direct','Mi-temps','Prolongations','Tirs au but','Interrompu') or minute is null),
 check (forfait_equipe_id is null or (forfait_equipe_id in (domicile_id,exterieur_id) and statut='Terminé')),
 check (rejoue_de is null or rejoue_de<>id),
 check ((source='manuel' and fournisseur is null and ref_fournisseur is null) or (source='api' and fournisseur is not null and ref_fournisseur is not null)),
 check (source='api' or not (verrou_manuel or verrou_score or verrou_statut or verrou_evenements or verrou_programmation)),
 check (source='api' or resultat_source='manuel'),
 unique (fournisseur, ref_fournisseur)
);
create index matchs_date on koki_foot.matchs(date_match);
create index matchs_competition on koki_foot.matchs(competition_id, date_match);
create index matchs_direct on koki_foot.matchs(statut) where statut in ('En direct','Mi-temps','Prolongations','Tirs au but','Interrompu');
create index matchs_rejoue on koki_foot.matchs(rejoue_de) where rejoue_de is not null;
create index matchs_domicile on koki_foot.matchs(domicile_id);
create index matchs_exterieur on koki_foot.matchs(exterieur_id);

-- ───────────── Événements de match ─────────────
-- cle : identifiant stable d'un événement. API : calculée par la synchronisation (l'API ne fournit pas
-- toujours d'identifiant) ; manuel : aléatoire. Unicité (match_id, cle) => aucun doublon à l'import.
create table koki_foot.evenements(
 id uuid primary key default gen_random_uuid(),
 match_id uuid not null references koki_foot.matchs(id) on delete cascade,
 type text not null check (type in ('but','but_csc','penalty','penalty_manque','carton_jaune','carton_rouge','remplacement','tab_reussi','tab_manque')),
 -- Période explicite ; minute affichée (ex. 90) et temps additionnel (ex. +3) séparés.
 periode text not null check (periode in ('mi_temps_1','mi_temps_2','prolongation_1','prolongation_2','tirs_au_but')),
 minute integer check (minute is null or minute between 0 and 150),
 minute_add integer check (minute_add is null or minute_add between 0 and 30),
 -- Tirs au but : seulement dans la séance, jamais comptés comme buts du match.
 check ((type in ('tab_reussi','tab_manque'))=(periode='tirs_au_but')),
 equipe_id uuid references koki_foot.equipes(id) on delete set null,
 joueur text not null default '' check (length(joueur)<=80),
 joueur2 text not null default '' check (length(joueur2)<=80),
 source text not null default 'manuel' check (source in ('manuel','api')),
 cle text not null default gen_random_uuid()::text check (length(cle) between 1 and 200),
 auteur uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique (match_id, cle)
);
create index evenements_match on koki_foot.evenements(match_id, periode, minute);

-- L'équipe d'un événement doit être l'une des deux équipes du match.
create function koki_foot.evenement_equipe() returns trigger language plpgsql set search_path='' as $$
begin
 if new.equipe_id is not null and not exists(select 1 from koki_foot.matchs m where m.id=new.match_id and new.equipe_id in (m.domicile_id,m.exterieur_id)) then
  raise exception 'Équipe étrangère au match' using errcode='23514';
 end if;
 return new;
end $$;
create trigger evenements_equipe before insert or update on koki_foot.evenements for each row execute function koki_foot.evenement_equipe();

-- ───────────── Classements fournis par l'API ─────────────
-- Les compétitions manuelles n'ont pas de lignes ici : leur classement est calculé (migration 2/2).
create table koki_foot.classements(
 competition_id uuid not null references koki_foot.competitions(id) on delete cascade,
 poule text not null default '' check (length(poule)<=40),
 equipe_id uuid not null references koki_foot.equipes(id) on delete cascade,
 rang integer not null check (rang between 1 and 200),
 joues integer not null default 0 check (joues>=0), gagnes integer not null default 0 check (gagnes>=0),
 nuls integer not null default 0 check (nuls>=0), perdus integer not null default 0 check (perdus>=0),
 buts_pour integer not null default 0 check (buts_pour>=0), buts_contre integer not null default 0 check (buts_contre>=0),
 points integer not null default 0 check (points between -50 and 500),
 forme text not null default '' check (forme ~ '^[VND]{0,5}$'),
 synchronise_le timestamptz not null default now(),
 primary key (competition_id, poule, equipe_id)
);

-- ───────────── Journal des corrections (ajout seul) ─────────────
create table koki_foot.corrections(
 id bigint generated always as identity primary key,
 match_id uuid references koki_foot.matchs(id) on delete set null,
 acteur uuid references auth.users(id) on delete set null,
 action text not null check (action in ('score','statut','match','programmation','forfait','rejoue','evenement_ajout','evenement_retrait','verrou','deverrou','conflit_garde','conflit_api')),
 avant jsonb not null default '{}'::jsonb check (jsonb_typeof(avant)='object'),
 apres jsonb not null default '{}'::jsonb check (jsonb_typeof(apres)='object'),
 motif text not null default '' check (length(motif)<=300),
 created_at timestamptz not null default now(),
 -- Chaînage : empreinte = SHA-256(empreinte précédente | contenu de la ligne).
 precedente text,
 empreinte text
);
create index corrections_match on koki_foot.corrections(match_id, created_at desc);
create function koki_foot.corrections_ajout_seul() returns trigger language plpgsql set search_path='' as $$
begin
 -- Seule la mise à NULL de match_id (effacement d'un match par cascade) est tolérée.
 if tg_op='UPDATE' and new.id=old.id and new.acteur is not distinct from old.acteur and new.action=old.action and new.avant=old.avant
    and new.apres=old.apres and new.motif=old.motif and new.created_at=old.created_at and new.match_id is null then return new; end if;
 raise exception 'Journal des corrections : ajout seul' using errcode='42501';
end $$;
create function koki_foot.corrections_contenu(c koki_foot.corrections) returns text language sql immutable set search_path='' as
$$ select concat_ws('|',c.id,c.match_id,c.acteur,c.action,c.avant::text,c.apres::text,c.motif,to_char(c.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US')) $$;
create function koki_foot.corrections_chainer() returns trigger language plpgsql set search_path='' as $$
begin
 -- Une écriture à la fois dans le journal : la chaîne reste linéaire.
 perform pg_advisory_xact_lock(hashtext('koki_foot.corrections'));
 new.precedente:=(select c.empreinte from koki_foot.corrections c order by c.id desc limit 1);
 new.empreinte:=encode(sha256(convert_to(coalesce(new.precedente,'')||'|'||koki_foot.corrections_contenu(new),'UTF8')),'hex');
 return new;
end $$;
create trigger corrections_chainer before insert on koki_foot.corrections for each row execute function koki_foot.corrections_chainer();
-- Vérification : renvoie l'identifiant de la première ligne altérée, supprimée ou réordonnée (null si intact).
create function koki_foot.verifier_journal() returns bigint language plpgsql stable set search_path='' as $$
declare c koki_foot.corrections; prec text:=null; begin
 for c in select * from koki_foot.corrections order by id loop
  if c.precedente is distinct from prec or c.empreinte is distinct from encode(sha256(convert_to(coalesce(prec,'')||'|'||koki_foot.corrections_contenu(c),'UTF8')),'hex') then return c.id; end if;
  prec:=c.empreinte;
 end loop;
 return null;
end $$;
create trigger corrections_ajout_seul before update or delete on koki_foot.corrections for each row execute function koki_foot.corrections_ajout_seul();
-- TRUNCATE contourne les déclencheurs de ligne : interdit aussi.
create function koki_foot.corrections_sans_vidage() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Journal des corrections : vidage interdit' using errcode='42501'; end $$;
create trigger corrections_sans_vidage before truncate on koki_foot.corrections for each statement execute function koki_foot.corrections_sans_vidage();

-- ───────────── Conflits API ↔ correction manuelle ─────────────
-- Une valeur verrouillée que l'API voudrait changer : jamais écrasée, jamais ignorée en silence.
create table koki_foot.conflits(
 id bigint generated always as identity primary key,
 match_id uuid not null references koki_foot.matchs(id) on delete cascade,
 champ text not null check (champ in ('score','statut','evenements','programmation')),
 valeur_locale jsonb not null,
 valeur_api jsonb not null,
 premier_vu timestamptz not null default now(),
 dernier_vu timestamptz not null default now(),
 occurrences integer not null default 1 check (occurrences>=1),
 resolu boolean not null default false,
 resolu_par uuid references auth.users(id) on delete set null,
 resolu_le timestamptz,
 decision text check (decision in ('garder','accepter_api'))
);
create unique index conflits_ouverts on koki_foot.conflits(match_id, champ) where not resolu;

-- ───────────── État des fournisseurs (fraîcheur, pannes, quota) ─────────────
create table koki_foot.etat_fournisseurs(
 fournisseur text primary key check (fournisseur in ('api-football','sportmonks')),
 derniere_reussite timestamptz,
 derniere_erreur timestamptz,
 derniere_erreur_code text check (derniere_erreur_code in ('indisponible','quota','authentification','donnees','delai','autre')),
 erreurs_consecutives integer not null default 0 check (erreurs_consecutives>=0),
 quota_restant integer check (quota_restant is null or quota_restant>=0),
 pause_jusqu_a timestamptz,
 -- Distinction : tentative (appel fait), réussite (réponse exploitable), modification (donnée changée).
 derniere_tentative timestamptz,
 derniere_modification timestamptz,
 -- Seuils réglables selon la fréquence réelle de synchronisation (forfait choisi).
 seuil_ancien_s integer not null default 300 check (seuil_ancien_s between 60 and 86400),
 attente_debut_s integer not null default 1800 check (attente_debut_s between 300 and 86400)
);

-- ───────────── Réglages du module (une seule ligne) ─────────────
-- mode_verrous : « global » (lancement : une correction pose aussi verrou_manuel, qui protège tout le match)
-- ou « independant » (chaque verrou ne protège que son champ ; verrou_manuel n'est plus posé, mais un
-- verrou_manuel déjà posé reste respecté pour compatibilité). Passage réservé au superadmin.
create table koki_foot.reglages(
 id boolean primary key default true check (id),
 mode_verrous text not null default 'global' check (mode_verrous in ('global','independant')),
 modifie_le timestamptz not null default now(),
 modifie_par uuid references auth.users(id) on delete set null
);
insert into koki_foot.reglages default values;

-- ───────────── Programmation : historique et changements d'horaire ─────────────
create table koki_foot.historique_programmation(
 id bigint generated always as identity primary key,
 match_id uuid not null references koki_foot.matchs(id) on delete cascade,
 origine text not null check (origine in ('api','manuel')),
 date_match timestamptz,
 lieu text check (lieu is null or length(lieu)<=120),
 motif text not null default '' check (length(motif)<=300),
 acteur uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create index historique_programmation_match on koki_foot.historique_programmation(match_id, id);
-- File pour le futur module de notifications : un changement d'horaire d'un match publié, une seule fois.
create table koki_foot.changements_horaire(
 id bigint generated always as identity primary key,
 match_id uuid not null references koki_foot.matchs(id) on delete cascade,
 ancienne timestamptz not null,
 nouvelle timestamptz not null,
 origine text not null check (origine in ('api','manuel')),
 -- Priorité de notification (règles : docs/football-notifications.md) : aucune | facultative | normale | prioritaire.
 priorite text not null default 'normale' check (priorite in ('aucune','facultative','normale','prioritaire')),
 created_at timestamptz not null default now(),
 traite_le timestamptz,
 unique (match_id, ancienne, nouvelle)
);
create index changements_horaire_a_traiter on koki_foot.changements_horaire(created_at) where traite_le is null;

-- ───────────── Journal des synchronisations ─────────────
create table koki_foot.synchronisations(
 id bigint generated always as identity primary key,
 fournisseur text not null check (fournisseur in ('api-football','sportmonks')),
 operation text not null check (length(operation) between 1 and 60),
 statut text not null check (statut in ('ok','partiel','erreur')),
 code text check (code in ('indisponible','quota','authentification','donnees','delai','autre')),
 lus integer not null default 0, crees integer not null default 0, mis_a_jour integer not null default 0,
 ignores_verrou integer not null default 0, rejetes integer not null default 0,
 message text not null default '' check (length(message)<=2000),
 created_at timestamptz not null default now()
);
create index synchronisations_date on koki_foot.synchronisations(created_at desc);

-- Dernier passage de la synchronisation sur un match, même sans changement (fraîcheur), séparé de la table
-- matchs pour ne pas créer une révision et une ligne d'audit à chaque passage.
create table koki_foot.vus_api(
 match_id uuid primary key references koki_foot.matchs(id) on delete cascade,
 -- Dernière réponse EXPLOITABLE du fournisseur contenant ce match (ligne valide et traitée).
 vu_le timestamptz not null default now(),
 -- Dernière fois que le fournisseur a effectivement changé une donnée de ce match.
 modifie_le timestamptz
);

-- ───────────── Horodatage et journal (fonctions existantes) ─────────────
create trigger competitions_stamp before insert or update on koki_foot.competitions for each row execute function koki_private.stamp();
create trigger equipes_stamp before insert or update on koki_foot.equipes for each row execute function koki_private.stamp();
create trigger matchs_stamp before insert or update on koki_foot.matchs for each row execute function koki_private.stamp();
create trigger competitions_audit after insert or update or delete on koki_foot.competitions for each row execute function koki_private.audit();
create trigger equipes_audit after insert or update or delete on koki_foot.equipes for each row execute function koki_private.audit();
create trigger matchs_audit after insert or update or delete on koki_foot.matchs for each row execute function koki_private.audit();

-- ───────────── Verrouillage ─────────────
do $$ declare t text; begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='koki_foot' and c.relkind='r' loop
  execute format('alter table koki_foot.%I enable row level security', t);
 end loop;
end $$;
revoke all on all tables in schema koki_foot from public, anon, authenticated, service_role;
revoke all on all sequences in schema koki_foot from public, anon, authenticated, service_role;
revoke all on all functions in schema koki_foot from public, anon, authenticated, service_role;

commit;
