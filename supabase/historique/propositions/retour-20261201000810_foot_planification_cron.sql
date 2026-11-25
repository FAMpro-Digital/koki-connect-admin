-- Retour de 20261201000810 : arrête le déclenchement automatique (données et secret Vault conservés).
begin;
select cron.unschedule('koki-foot-sync') where exists(select 1 from cron.job where jobname='koki-foot-sync');
commit;
