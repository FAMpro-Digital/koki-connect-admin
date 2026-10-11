-- EMPREINTE EN LECTURE SEULE de la structure et des données Koki (aucune écriture, aucun secret lu).
-- Usage : exécuter avant puis après une opération sur le projet TEST et comparer les lignes (categorie, objet, empreinte).
-- Les droits sont triés (l'ordre d'attribution n'a pas d'effet) ; les données sont résumées par un condensé md5 par table ; aucune ligne n'est affichée.
with
scope as (select oid, nspname from pg_namespace where nspname in ('public','koki_private','koki_test')),
rels as (select c.oid, c.relname, c.relkind, n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where (n.nspname in (select nspname from scope) and c.relkind in ('r','v','m','S','p','f'))
     or (n.nspname='storage' and c.relname in ('objects','buckets')) or (n.nspname='auth' and c.relname='users')),
lignes as (
 select 'schema' categorie, s.nspname objet, md5(coalesce((select string_agg(x::text,',' order by x::text) from unnest(n.nspacl) x),'')) empreinte from scope s join pg_namespace n on n.oid=s.oid
 union all
 select 'relation', r.nspname||'.'||r.relname, md5(r.relkind::text||':'||c.relrowsecurity||c.relforcerowsecurity||':'||coalesce((select string_agg(x::text,',' order by x::text) from unnest(c.relacl) x),''))
  from rels r join pg_class c on c.oid=r.oid where r.nspname in (select nspname from scope)
 union all
 select 'colonnes', r.nspname||'.'||r.relname, md5(string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull||':'||coalesce(pg_get_expr(d.adbin,d.adrelid),'')||':'||coalesce((select string_agg(x::text,',' order by x::text) from unnest(a.attacl) x),''),',' order by a.attnum))
  from rels r join pg_attribute a on a.attrelid=r.oid and a.attnum>0 and not a.attisdropped left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
  where r.nspname in (select nspname from scope) group by 1,2
 union all
 select 'contrainte', r.nspname||'.'||r.relname||'.'||co.conname, md5(pg_get_constraintdef(co.oid))
  from pg_constraint co join rels r on r.oid=co.conrelid where r.nspname in (select nspname from scope)
 union all
 select 'index', r.nspname||'.'||i.relname, md5(pg_get_indexdef(i.oid))
  from pg_index x join pg_class i on i.oid=x.indexrelid join rels r on r.oid=x.indrelid where r.nspname in (select nspname from scope)
 union all
 select 'politique', schemaname||'.'||tablename||'.'||policyname, md5(permissive||':'||roles::text||':'||cmd||':'||coalesce(qual,'')||':'||coalesce(with_check,''))
  from pg_policies where schemaname in (select nspname from scope) or (schemaname='storage' and tablename in ('objects','buckets'))
 union all
 select 'declencheur', r.nspname||'.'||r.relname||'.'||t.tgname, md5(pg_get_triggerdef(t.oid)||':'||t.tgenabled::text)
  from pg_trigger t join rels r on r.oid=t.tgrelid where not t.tgisinternal
 union all
 select 'fonction', n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', md5(pg_get_functiondef(p.oid)||':'||coalesce((select string_agg(x::text,',' order by x::text) from unnest(p.proacl) x),''))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in (select nspname from scope) and p.prokind in ('f','p')
 union all
 select 'type', n.nspname||'.'||t.typname, md5(t.typtype::text||coalesce((select string_agg(enumlabel,',' order by enumsortorder) from pg_enum e where e.enumtypid=t.oid),''))
  from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname in (select nspname from scope) and t.typtype in ('e','d')
 union all
 select 'bucket', id, md5(public::text||':'||coalesce(file_size_limit::text,'')||':'||coalesce(allowed_mime_types::text,'')) from storage.buckets
 union all
 select 'donnees', r.nspname||'.'||r.relname,
  substring(query_to_xml(format('select count(*)||'':''||md5(coalesce(string_agg(t::text, ''|'' order by t::text),'''')) h from %I.%I t', r.nspname, r.relname), false, true, '')::text from '<h>([0-9]+:[0-9a-f]{32})</h>')
  from rels r where r.relkind in ('r','p') and r.nspname in (select nspname from scope)
 union all
 select 'donnees', 'auth.users', count(*)::text||':'||md5(coalesce(string_agg(id::text,',' order by id),'')) from auth.users
 union all
 select 'donnees', 'storage.objects', count(*)::text||':'||md5(coalesce(string_agg(bucket_id||'/'||name,',' order by bucket_id,name),'')) from storage.objects
)
select categorie, objet, empreinte from lignes order by 1,2,3;
