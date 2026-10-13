-- KOKI CONNECT — RETRAIT DU CROCHET « Before User Created » DU PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay
-- Jamais sur qsbmzzbiztfqysstepxm ni paegdthtusbwxuarhacb.
-- D'ABORD désactiver le crochet dans Authentication → Hooks : sinon toute création de compte échoue (fonction introuvable).
-- Ne touche ni aux comptes existants, ni au crochet SMS (koki_test), ni à la poursuite.
begin;
do $$ begin
 if to_regclass('koki_private.test_environment') is null then raise exception 'GARDE : base non marquée « KOKI TEST » : retrait refusé';end if;
 if to_regnamespace('koki_test_signup') is null then raise exception 'GARDE : crochet d''inscription absent, rien à retirer';end if;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='koki_test_signup' and c.relname<>'allowed_emails' and c.relkind in ('r','v','m','p','f'))
  or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_test_signup' and p.proname<>'before_user_created')
 then raise exception 'GARDE : objets inattendus dans koki_test_signup : retrait refusé';end if;
end $$;
drop function koki_test_signup.before_user_created(jsonb);
drop table koki_test_signup.allowed_emails;
drop schema koki_test_signup;
commit;
