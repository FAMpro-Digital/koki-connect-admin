-- KOKI CONNECT TEST — VALIDATION TECHNIQUE APRÈS RECONSTRUCTION.
-- Lecture seule : chaque contrôle renvoie « OK » ou « ÉCHEC ». Les essais de droits sont
-- faits dans une transaction annulée (rollback) : rien n'est conservé.
select controle, case when ok then 'OK' else 'ÉCHEC' end resultat from (
 select 'marqueur KOKI TEST présent' controle, to_regclass('koki_private.test_environment') is not null ok
 union all select 'aucune tâche planifiée ne contacte un service extérieur',
  not exists(select 1 from pg_extension where extname='pg_cron') or not exists(select 1 from cron.job where jobname='koki-notifications-dispatch' or command ~* 'http|net\.')
 union all select 'aucun secret dans le coffre',
  not exists(select 1 from pg_extension where extname='supabase_vault') or not exists(select 1 from vault.secrets)
 union all select 'aucun webhook de base (supabase_functions / pg_net)',
  not exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('supabase_functions','net'))
 union all select 'Realtime : aucune table diffusée',
  not exists(select 1 from pg_publication_tables where pubname='supabase_realtime')
 union all select 'RLS active sur toutes les tables Koki',
  not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and (n.nspname like 'koki%' or (n.nspname='public' and c.relname like 'koki%')) and not c.relrowsecurity)
 union all select '3 buckets privés (koki-media, koki-livres, koki-videos)',
  (select count(*) from storage.buckets where id in ('koki-media','koki-livres','koki-videos') and not public)=3
 union all select 'fonctions métier présentes',
  to_regprocedure('public.koki_business(text,jsonb)') is not null and to_regprocedure('public.koki_public_feed(integer)') is not null and to_regprocedure('public.koki_account_delete(text,text)') is not null
 union all select 'administration : 2FA exigée (aal2) dans koki_private.allowed',
  pg_get_functiondef('koki_private.allowed(text)'::regprocedure) like '%aal2%'
 union all select 'anon ne peut pas lire les tables privées',
  not has_table_privilege('anon','koki_private.ride_codes','select') and not has_table_privilege('anon','public.koki_users','select')
 union all select 'statistiques refusées aux visiteurs',
  not has_function_privilege('anon','public.koki_statistics()','execute')
) t;

-- Essai de lecture publique comme visiteur anonyme (annulé).
begin;
set local role anon;
select 'flux public lisible par un visiteur' controle, (select count(*) from public.koki_public_feed(0)) >= 0 as ok;
rollback;
