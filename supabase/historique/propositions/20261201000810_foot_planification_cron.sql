-- PROPOSITION (NON appliquée) — déclenchement de la synchronisation API-Football chaque minute,
-- sur le modèle de la tâche existante « koki-notifications-dispatch » (pg_cron → pg_net → fonction Vercel).
-- Chaque appel ne coûte une requête API-Football QUE si le planificateur le décide (quota, matchs suivis) :
-- sans compétition publiée ni match à suivre, aucune requête n'est envoyée au fournisseur.
-- Préalables (à faire par le propriétaire, hors dépôt) :
--  1. secret aléatoire (≥ 32 caractères) enregistré dans Vault :
--       select vault.create_secret('<secret>','koki_foot_sync_secret','Appel de /api/foot-sync');
--     et la même valeur dans Vercel (projet koki-connect-admin, Production) : FOOT_SYNC_SECRET ;
--  2. 20261201000800 appliquée ; FOOT_SYNC_ENABLED=true et API_FOOTBALL_KEY dans Vercel.
-- Retour : retour-20261201000810_foot_planification_cron.sql (ou FOOT_SYNC_ENABLED=false : arrêt immédiat).
begin;
do $$ begin
 if to_regprocedure('public.koki_foot_sync_planning(text)') is null then raise exception 'GARDE : 20261201000800 absente'; end if;
 if not exists(select 1 from vault.decrypted_secrets where name='koki_foot_sync_secret' and length(decrypted_secret)>=32) then raise exception 'GARDE : secret Vault koki_foot_sync_secret absent ou trop court'; end if;
 if exists(select 1 from cron.job where jobname='koki-foot-sync') then raise exception 'GARDE : tâche koki-foot-sync déjà planifiée'; end if;
end $$;
select cron.schedule('koki-foot-sync','* * * * *',$cmd$
 select net.http_post(
  url:='https://koki-connect-admin.vercel.app/api/foot-sync',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='koki_foot_sync_secret')),
  body:='{"mode":"passage"}'::jsonb,
  timeout_milliseconds:=25000)
$cmd$);
commit;
