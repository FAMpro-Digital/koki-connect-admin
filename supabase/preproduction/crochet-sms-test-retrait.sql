-- KOKI CONNECT — RETRAIT DU CROCHET « Send SMS » DU PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay
-- D'abord désactiver le crochet dans Authentication → Hooks, puis exécuter ce script.
-- Les codes de test enregistrés sont éphémères et fictifs (numéros +999) ; le script refuse s'il trouve autre chose.
begin;
do $$ begin
 if to_regnamespace('koki_test') is null then raise exception 'GARDE : crochet absent, rien à retirer';end if;
 if exists(select 1 from koki_test.sms_codes where phone !~ '^99900000000[1-9]$') then raise exception 'GARDE : données inattendues dans koki_test.sms_codes';end if;
end $$;
drop function koki_test.send_sms(jsonb);
drop table koki_test.sms_codes;
drop schema koki_test;
commit;
