import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
import {setupBusinessDB} from './helpers/business-db.js';
// Audit permanent : toute nouvelle exposition d'une fonction, table sans RLS ou fonction privilégiée mal isolée fait échouer les tests.
test('audit : fonctions exposées, isolation des fonctions privilégiées, RLS partout',async()=>{
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};
 try{await setupBusinessDB(db);const rows=async q=>(await db.query(q)).rows;
  const exposed=(await rows(`select n.nspname||'.'||p.proname||':'||(case when has_function_privilege('anon',p.oid,'execute') then 'anon' else 'auth' end) f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','koki_private') and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute')) order by 1`)).map(r=>r.f);
  assert.deepEqual(exposed,['koki_private.allowed:auth','koki_private.business_image_unreferenced:auth','koki_private.business_participant_image:auth','koki_private.business_public_image:anon','koki_private.commerce_admin:anon','koki_private.my_media_folder:auth','koki_private.owns_business:auth','koki_private.transport_plus:anon','public.koki_business:anon','public.koki_public_feed:anon','public.koki_statistics:auth']);
  assert.deepEqual(await rows(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prosecdef and n.nspname in ('public','koki_private') and not coalesce(p.proconfig::text,'') like '%search_path=%'`),[]);
  assert.deepEqual(await rows(`select schemaname||'.'||tablename t from pg_tables where schemaname in ('public','koki_private') and not rowsecurity`),[]);
  // Aucun droit d'écriture directe des clients sur les fiches métier.
  for(const priv of ['INSERT','UPDATE','DELETE'])for(const role of ['anon','authenticated'])assert.equal((await rows(`select has_table_privilege('${role}','public.koki_records','${priv}') ok`))[0].ok,false,role+' '+priv);
 }finally{await pg.close();}
});
test('audit : aucun secret ni compte réel dans les fichiers locaux',async()=>{
 for(const p of ['supabase/seed.sql','supabase/config.toml','supabase/proposals/commerce-modernisation.sql','.env.supabase-local.example','src/commerce-admin.js']){const t=await readFile(new URL('../'+p,import.meta.url),'utf8');assert.doesNotMatch(t,/sb_secret_[A-Za-z0-9]|service_role_key|eyJhbGciOi|BEGIN (RSA|PRIVATE)|ghp_[A-Za-z0-9]/,p);}
 const seed=await readFile(new URL('../supabase/seed.sql',import.meta.url),'utf8');assert.doesNotMatch(seed,/encrypted_password\)? *values[^;]*'\$2[aby]\$/,'aucun mot de passe');for(const m of seed.matchAll(/'(\+?\d{9,15})'/g))assert.match(m[1],/^\+?999|^17$|^18$|^1515$/,'numéros fictifs uniquement : '+m[1]);
});
