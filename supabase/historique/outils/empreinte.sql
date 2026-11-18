with
scope as (select oid, nspname from pg_namespace where nspname in ('public','koki_private','koki_social_private')),
rels as (select c.oid, c.relname, c.relkind, n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in (select nspname from scope) and c.relkind in ('r','v','m','S','p','f')),
lignes as (
 select 'schema' categorie, s.nspname objet, md5(coalesce((select string_agg(case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type,',' order by case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type) from aclexplode(n.nspacl) g where g.grantee=0 or pg_get_userbyid(g.grantee) in ('anon','authenticated','service_role')),'')) empreinte from scope s join pg_namespace n on n.oid=s.oid
 union all
 select 'relation', r.nspname||'.'||r.relname, md5(r.relkind::text||':'||c.relrowsecurity||c.relforcerowsecurity) from rels r join pg_class c on c.oid=r.oid
 union all
 select 'droits', r.nspname||'.'||r.relname, md5(coalesce((select string_agg(case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type,',' order by case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type) from aclexplode(c.relacl) g where g.privilege_type<>'MAINTAIN' and (g.grantee=0 or pg_get_userbyid(g.grantee) in ('anon','authenticated','service_role'))),'')) from rels r join pg_class c on c.oid=r.oid
 union all
 select 'colonnes', r.nspname||'.'||r.relname, md5(string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),'')||':'||coalesce((select string_agg(case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type,',' order by case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type) from aclexplode(a.attacl) g where g.grantee=0 or pg_get_userbyid(g.grantee) in ('anon','authenticated','service_role')),''),',' order by a.attnum))
  from rels r join pg_attribute a on a.attrelid=r.oid and a.attnum>0 and not a.attisdropped left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where r.relkind<>'S' group by 1,2
 union all
 select 'contrainte', r.nspname||'.'||r.relname||'.'||co.conname, md5(pg_get_constraintdef(co.oid)) from pg_constraint co join rels r on r.oid=co.conrelid where co.contype<>'n'
 union all
 select 'index', r.nspname||'.'||i.relname, md5(pg_get_indexdef(i.oid)) from pg_index x join pg_class i on i.oid=x.indexrelid join rels r on r.oid=x.indrelid
 union all
 select 'politique', schemaname||'.'||tablename||'.'||policyname, md5(permissive||':'||roles::text||':'||cmd||':'||coalesce(qual,'')||':'||coalesce(with_check,'')) from pg_policies where schemaname in (select nspname from scope) or (schemaname='storage' and tablename in ('objects','buckets'))
 union all
 select 'declencheur', cn.nspname||'.'||c.relname||'.'||t.tgname, md5(pg_get_triggerdef(t.oid)||':'||t.tgenabled::text) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace cn on cn.oid=c.relnamespace where not t.tgisinternal and (cn.nspname in (select nspname from scope) or (cn.nspname='auth' and c.relname='users'))
 union all
 select 'fonction', n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in (select nspname from scope) and p.prokind in ('f','p')
 union all
 select 'droits_fonction', n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', md5(coalesce((select string_agg(case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type,',' order by case when g.grantee=0 then 'public' else pg_get_userbyid(g.grantee) end||'='||g.privilege_type) from aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) g where g.grantee=0 or pg_get_userbyid(g.grantee) in ('anon','authenticated','service_role')),'')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in (select nspname from scope) and p.prokind in ('f','p')
 union all
 select 'bucket', id, md5(public::text||':'||coalesce(file_size_limit::text,'')||':'||coalesce(allowed_mime_types::text,'')) from storage.buckets
 union all
 select 'cron', jobname, md5(schedule||':'||regexp_replace(command,'\s+',' ','g')) from cron.job
)
select categorie||'|'||objet||'|'||left(empreinte,12) from lignes order by 1;
