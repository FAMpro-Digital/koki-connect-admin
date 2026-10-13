-- KOKI CONNECT — ATTRIBUTION D'UN RÔLE D'ADMINISTRATION SUR LE PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay
-- 1. Créer le compte dans Authentication → Users → Add user (adresse e-mail personnelle, mot de passe personnel, « Auto Confirm User »).
-- 2. Copier son identifiant (UID) affiché par le tableau de bord, puis remplacer les TROIS valeurs ci-dessous.
-- 3. Exécuter : le script vérifie que l'identifiant, l'adresse e-mail et la confirmation correspondent au même compte avant toute écriture.
-- Aucun mot de passe ni secret n'est lu ou écrit ici. La double authentification (TOTP) reste exigée à la connexion.
begin;
do $$
declare
 v_user uuid := '00000000-0000-0000-0000-000000000000';   -- UID du compte vérifié dans le tableau de bord
 v_email text := 'adresse-a-remplacer@invalid';            -- adresse e-mail exacte de ce compte
 v_role text := 'superadmin';                              -- superadmin, manager, editor ou analyst
 u record;
begin
 if to_regclass('koki_private.test_environment') is null then raise exception 'GARDE : base non marquée « KOKI TEST » : attribution refusée';end if;
 if not exists(select 1 from koki_private.test_environment where label='KOKI TEST') then raise exception 'GARDE : base non marquée « KOKI TEST » : attribution refusée';end if;
 if v_user='00000000-0000-0000-0000-000000000000' or v_email like '%@invalid' then raise exception 'GARDE : remplacer l''identifiant et l''adresse e-mail du compte vérifié';end if;
 if v_role not in ('superadmin','manager','editor','analyst') then raise exception 'GARDE : rôle inconnu';end if;
 select id,email,email_confirmed_at into u from auth.users where id=v_user;
 if not found then raise exception 'GARDE : aucun compte avec cet identifiant';end if;
 if u.email is null or lower(u.email)<>lower(btrim(v_email)) then raise exception 'GARDE : l''adresse e-mail ne correspond pas à cet identifiant';end if;
 if u.email_confirmed_at is null then raise exception 'GARDE : compte non confirmé';end if;
 if exists(select 1 from public.koki_admin_members where user_id=v_user) then raise exception 'GARDE : ce compte a déjà un rôle (aucune modification)';end if;
 insert into public.koki_admin_members(user_id,role) values(v_user,v_role);
 raise notice 'Rôle % attribué au compte % (%)',v_role,v_user,u.email;
end $$;
commit;
