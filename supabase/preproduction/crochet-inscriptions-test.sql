-- KOKI CONNECT — CROCHET « Before User Created » DU PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay
-- Jamais sur qsbmzzbiztfqysstepxm ni paegdthtusbwxuarhacb.
-- À exécuter APRÈS la poursuite (marqueur « KOKI TEST » requis), puis à choisir dans
-- Authentication → Hooks → Before User Created → Postgres → schéma koki_test_signup, fonction before_user_created.
-- Effet : seules ces créations de compte sont acceptées, par n'importe quel parcours (inscription, OTP, tableau de bord, API d'administration) :
--  * téléphone +999000000001 à +999000000009 (sans adresse e-mail) ;
--  * adresse e-mail inscrite dans koki_test_signup.allowed_emails (le compte administrateur de test, indiqué ci-dessous).
-- Tout le reste est refusé (403) : autre numéro, autre adresse, connexion anonyme, OAuth, SSO, requête mal formée.
-- Les connexions aux comptes existants ne passent pas par ce crochet : elles restent possibles.
-- Schéma distinct de koki_test (crochet SMS) : les deux crochets s'installent et se retirent indépendamment.
-- Retrait : désactiver le crochet dans le tableau de bord, PUIS supabase/preproduction/crochet-inscriptions-test-retrait.sql.
-- 1. Remplacer l'adresse ci-dessous par l'adresse e-mail exacte du futur compte administrateur de test.
-- 2. Exécuter une seule fois : une seconde exécution est refusée sans modification.
begin;
do $$
declare v_admin_email text := 'adresse-a-remplacer@invalid';   -- adresse e-mail du compte administrateur de test
begin
 if to_regclass('koki_private.test_environment') is null then raise exception 'GARDE : base non marquée « KOKI TEST » : crochet refusé';end if;
 if not exists(select 1 from koki_private.test_environment where label='KOKI TEST') then raise exception 'GARDE : base non marquée « KOKI TEST » : crochet refusé';end if;
 if to_regnamespace('koki_test_signup') is not null then raise exception 'GARDE : crochet d''inscription déjà installé';end if;
 v_admin_email:=lower(btrim(v_admin_email));
 if v_admin_email like '%@invalid' or v_admin_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'GARDE : remplacer l''adresse e-mail du compte administrateur de test';end if;
 create schema koki_test_signup;
 revoke all on schema koki_test_signup from public, anon, authenticated;
 create table koki_test_signup.allowed_emails(
  email text primary key check(email=lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  note text not null,
  created_at timestamptz not null default now()
 );
 alter table koki_test_signup.allowed_emails enable row level security;
 revoke all on koki_test_signup.allowed_emails from public, anon, authenticated;
 insert into koki_test_signup.allowed_emails(email,note) values(v_admin_email,'Compte administrateur de test');
end $$;
create function koki_test_signup.before_user_created(event jsonb) returns jsonb language plpgsql stable set search_path='' as $$
-- Toute charge utile inattendue est refusée ; une erreur interne ferait aussi échouer la création (Supabase refuse si le crochet échoue).
declare
 u jsonb:=event->'user';
 v_email text;v_phone text;v_provider text;
 refus jsonb:=jsonb_build_object('error',jsonb_build_object('http_code',403,'message','Préproduction Koki Connect : création de compte réservée aux comptes de test autorisés'));
begin
 if jsonb_typeof(u) is distinct from 'object' then return refus;end if;
 if jsonb_typeof(u->'email') not in ('string','null') or jsonb_typeof(u->'phone') not in ('string','null') then return refus;end if;
 v_email:=lower(btrim(coalesce(u->>'email','')));
 v_phone:=regexp_replace(btrim(coalesce(u->>'phone','')),'^\+','');
 v_provider:=coalesce(u->'app_metadata'->>'provider','');
 if coalesce(u->>'is_anonymous','false')<>'false' then return refus;end if;
 if v_provider not in ('email','phone') then return refus;end if;
 if v_email='' and v_phone='' then return refus;end if;
 if v_phone<>'' and v_email<>'' then return refus;end if;
 if v_phone<>'' and v_phone !~ '^99900000000[1-9]$' then return refus;end if;
 if v_email<>'' and not exists(select 1 from koki_test_signup.allowed_emails a where a.email=v_email) then return refus;end if;
 return '{}'::jsonb;
end $$;
revoke all on function koki_test_signup.before_user_created(jsonb) from public, anon, authenticated;
-- Droits minimaux du service Auth (rôle supabase_auth_admin) : lire la liste, appeler la fonction ; aucune écriture.
grant usage on schema koki_test_signup to supabase_auth_admin;
grant select on koki_test_signup.allowed_emails to supabase_auth_admin;
create policy allowed_emails_auth_read on koki_test_signup.allowed_emails for select to supabase_auth_admin using (true);
grant execute on function koki_test_signup.before_user_created(jsonb) to supabase_auth_admin;
commit;
