-- Lecture seule, projet TEST exclusivement ; aucun secret MFA lu.
select current_setting('server_version') as postgres_version;
select schemaname,tablename,rowsecurity from pg_tables where schemaname='public' and tablename like 'koki_%';
select id,public,file_size_limit,allowed_mime_types from storage.buckets where id='koki-media';
select has_table_privilege('authenticated','public.koki_records','INSERT') as direct_insert_should_be_false,
 has_table_privilege('authenticated','public.koki_records','UPDATE') as direct_update_should_be_false,
 has_table_privilege('authenticated','public.koki_records','DELETE') as direct_delete_should_be_false,
 has_table_privilege('anon','koki_private.business_keys','SELECT') as private_keys_should_be_false,
 has_function_privilege('authenticated','koki_private.business_text(jsonb,text,integer,integer)','EXECUTE') as private_helper_should_be_false;
select schemaname,tablename,policyname,roles,cmd from pg_policies where schemaname in ('public','storage') and (tablename like 'koki_%' or tablename='objects');
select n.nspname,p.proname,p.prosecdef,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_private';
