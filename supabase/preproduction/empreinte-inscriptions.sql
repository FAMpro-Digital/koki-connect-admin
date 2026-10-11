-- EMPREINTE EN LECTURE SEULE du crochet d'inscription TEST (complément de empreinte.sql, qui ne couvre pas koki_test_signup).
-- Aucune écriture, aucune adresse e-mail affichée : la liste autorisée est résumée par un condensé.
-- Avant installation : une seule ligne « etat | koki_test_signup | absent ». Après : schéma, table, politique, fonction et condensé de la liste.
select 'etat' categorie, 'koki_test_signup' objet, case when to_regnamespace('koki_test_signup') is null then 'absent' else 'present' end empreinte
union all
select 'schema', n.nspname, md5(coalesce((select string_agg(x::text,',' order by x::text) from unnest(n.nspacl) x),'')) from pg_namespace n where n.nspname='koki_test_signup'
union all
select 'relation', n.nspname||'.'||c.relname, md5(c.relkind::text||':'||c.relrowsecurity||':'||coalesce((select string_agg(x::text,',' order by x::text) from unnest(c.relacl) x),''))
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='koki_test_signup' and c.relkind in ('r','v','m','p','f')
union all
select 'politique', schemaname||'.'||tablename||'.'||policyname, md5(permissive||':'||roles::text||':'||cmd||':'||coalesce(qual,'')||':'||coalesce(with_check,'')) from pg_policies where schemaname='koki_test_signup'
union all
select 'fonction', n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', md5(pg_get_functiondef(p.oid)||':'||coalesce((select string_agg(x::text,',' order by x::text) from unnest(p.proacl) x),''))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='koki_test_signup'
union all
select 'donnees', 'koki_test_signup.allowed_emails', substring(query_to_xml('select count(*)||'':''||md5(coalesce(string_agg(email,'','' order by email),'''')) h from koki_test_signup.allowed_emails', false, true, '')::text from '<h>([0-9]+:[0-9a-f]{32})</h>')
 where to_regclass('koki_test_signup.allowed_emails') is not null
order by 1,2;
