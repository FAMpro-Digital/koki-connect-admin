-- Retour arrière de 20261201000100_sport_access_rpc.sql
begin;
do $$ begin
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name='koki_notifications' and column_name='sport_ref') then
  raise exception 'RETOUR BLOQUÉ : exécutez d’abord le retour de 20261201000300_sport_notifications.sql';
 end if;
 if exists(select 1 from pg_policies where schemaname='storage' and policyname like 'koki_sport_%') then
  raise exception 'RETOUR BLOQUÉ : exécutez d’abord le retour de 20261201000200_sport_storage.sql';
 end if;
end $$;
drop function if exists public.koki_sport(text,jsonb);
drop function if exists public.koki_sport_public(text,jsonb);
do $$ declare f record; begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='koki_sport' and p.proname not in ('phone_ok','image_ok','text_ok','keep_responsable','consent_revoke') loop
  execute 'drop function '||f.sig;
 end loop;
end $$;
revoke usage on schema koki_sport from anon, authenticated;
commit;
