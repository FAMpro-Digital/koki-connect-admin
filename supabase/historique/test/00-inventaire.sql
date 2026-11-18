-- KOKI CONNECT TEST (euvxtwmyoihnutifshay) — INVENTAIRE AVANT RECONSTRUCTION.
-- LECTURE SEULE : aucune écriture. À exécuter juste après la restauration,
-- dans l'éditeur SQL du projet TEST, et à conserver (copie du résultat).
select 'projet' rubrique, 'version PostgreSQL' element, current_setting('server_version') valeur
union all select 'projet','base',current_database()
union all select 'schemas', nspname, (select count(*)::text from pg_class c where c.relnamespace=n.oid and c.relkind in ('r','p','v','m','S'))||' relations'
  from pg_namespace n where nspname not like 'pg_%' and nspname<>'information_schema'
union all select 'tables koki', n.nspname||'.'||c.relname, greatest(c.reltuples,0)::bigint::text||' lignes (estimation)'
  from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and (n.nspname like 'koki%' or (n.nspname='public' and c.relname like 'koki%'))
union all select 'migrations', version, name from supabase_migrations.schema_migrations
union all select 'auth', 'comptes', count(*)::text from auth.users
union all select 'auth', 'facteurs 2FA', count(*)::text from auth.mfa_factors
union all select 'storage', 'bucket '||id, 'public='||public||' limite='||coalesce(file_size_limit::text,'-')||' fichiers='||(select count(*) from storage.objects o where o.bucket_id=b.id) from storage.buckets b
union all select 'fonctions', n.nspname, count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname like 'koki%' or (n.nspname='public' and p.proname like 'koki%') group by n.nspname
union all select 'rls', schemaname||'.'||tablename, count(*)::text||' règles' from pg_policies where schemaname in ('public','storage') or schemaname like 'koki%' group by 1,2
union all select 'extensions', extname, extversion from pg_extension
union all select 'realtime', pubname, coalesce((select string_agg(schemaname||'.'||tablename,',') from pg_publication_tables t where t.pubname=p.pubname),'(aucune table)') from pg_publication p
union all select 'declencheurs auth', tgname, tgrelid::regclass::text from pg_trigger where tgrelid='auth.users'::regclass and not tgisinternal
union all select 'webhooks', tgrelid::regclass::text||'.'||tgname, p.proname from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('supabase_functions','net')
union all select 'cron', 'pg_cron installé', (exists(select 1 from pg_extension where extname='pg_cron'))::text
union all select 'vault', 'pg_net installé', (exists(select 1 from pg_extension where extname='pg_net'))::text
order by 1,2;
-- Si pg_cron est installé, exécuter aussi :  select jobname, schedule, command, active from cron.job;
-- Si supabase_vault est installé :          select name from vault.secrets;   (noms uniquement)
