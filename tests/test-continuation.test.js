// Poursuite d'installation du projet Supabase TEST et son retour arrière : répétés UNIQUEMENT sur une copie locale jetable
// reproduisant l'état vérifié de TEST (schema.sql + fondation, privilèges par défaut de Supabase, base vide).
import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
import {setupSupabaseStub} from './helpers/business-db.js';
import {continuationBundle,rollbackScript,TEST_PROJECT_REF,BLOCKED_PROJECT_REFS,BUNDLE_PATH,MANIFEST_PATH,ROLLBACK_PATH} from '../scripts/prepare-test-continuation.mjs';
const file=p=>readFile(new URL('../'+p,import.meta.url),'utf8');

async function testProjectCopy(){
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1)),close:()=>pg.close()};
 await setupSupabaseStub(db);
 await db.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role;end if;end $$;
 alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
 alter default privileges in schema public grant all on functions to anon,authenticated,service_role;
 alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;`);
 await db.query(await file('supabase/schema.sql'));await db.query(await file('supabase/proposals/commerce-transport-foundation.sql'));
 return db;
}
const fingerprintSQL=await file('supabase/preproduction/empreinte.sql');
async function fingerprint(db){const rows=(await db.query(fingerprintSQL)).rows;return new Map(rows.map(r=>[r.categorie+' '+r.objet,r.empreinte]));}
const structure=f=>new Map([...f].filter(([k])=>!k.startsWith('donnees ')));
const data=f=>new Map([...f].filter(([k])=>k.startsWith('donnees ')));
async function run(db,sql){try{await db.query(sql);return 'ok';}catch(e){await db.query('rollback').catch(()=>{});return e.message;}}

test('paquet, manifeste et retour arrière versionnés : identiques au générateur, cible TEST unique',async()=>{
 const {sql,manifest}=await continuationBundle();
 assert.equal(await file(BUNDLE_PATH),sql,'régénérer : node scripts/prepare-test-continuation.mjs');
 assert.equal(await file(MANIFEST_PATH),manifest);assert.equal(await file(ROLLBACK_PATH),await rollbackScript());
 const m=JSON.parse(manifest);assert.equal(m.target,'euvxtwmyoihnutifshay');assert.equal(m.remoteApplied,false);
 assert.deepEqual(m.blocked,['qsbmzzbiztfqysstepxm','paegdthtusbwxuarhacb']);assert.equal(TEST_PROJECT_REF,'euvxtwmyoihnutifshay');
 for(const f of m.files)assert.equal((await import('node:crypto')).createHash('sha256').update(await file(f.file)).digest('hex'),f.sha256,f.file);
 const plan=JSON.parse(await file('supabase/preproduction/project-plan.json'));
 assert.equal(plan.testProjectRef,TEST_PROJECT_REF);assert.equal(plan.organizationId,'ybsokeuyduvfoulizcay');assert.deepEqual(plan.blockedProjectRefs,BLOCKED_PROJECT_REFS);
 assert.ok(!BLOCKED_PROJECT_REFS.includes(plan.testProjectRef));assert.equal(plan.productionChanges,false);assert.equal(plan.continuation.remoteApplied,false);
 for(const text of [sql,await rollbackScript()]){
  // Les références interdites n'apparaissent que dans l'avertissement d'en-tête, jamais dans une instruction.
  const body=text.split('\n').filter(l=>!l.startsWith('--')).join('\n');for(const ref of BLOCKED_PROJECT_REFS)assert.ok(!body.includes(ref));
  assert.match(text,/^-- KOKI CONNECT — .*PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay/);
  assert.equal((text.match(/^begin;$/gm)||[]).length,1);assert.equal((text.match(/^commit;$/gm)||[]).length,1);
  assert.doesNotMatch(text,/service_role_key|sb_secret_|eyJhbGciOi|password\s*=|BEGIN (RSA|PRIVATE)/i);
 }
});

test('poursuite : appliquée sur l’état TEST, refusée sur une base non vide ou déjà installée, sans rien modifier',async()=>{
 const db=await testProjectCopy();
 try{
  const bundle=await file(BUNDLE_PATH),f0=await fingerprint(db);
  assert.equal((await db.query("select has_function_privilege('anon','public.koki_statistics()','EXECUTE') v")).rows[0].v,true,'écart constaté sur TEST reproduit');
  assert.equal(await run(db,bundle),'ok');
  const f1=await fingerprint(db);assert.notDeepEqual(structure(f1),structure(f0));
  assert.equal((await db.query('select label from koki_private.test_environment')).rows[0].label,'KOKI TEST');
  assert.equal((await db.query("select has_function_privilege('anon','public.koki_statistics()','EXECUTE') v")).rows[0].v,false);
  assert.equal((await db.query('select count(*)::int n from public.koki_localites')).rows[0].n,10);
  assert.match(await run(db,bundle),/GARDE : poursuite déjà appliquée/);assert.deepEqual(await fingerprint(db),f1);
 }finally{await db.close();}
 const prod=await testProjectCopy();
 try{
  await prod.query("insert into auth.users(id) values('99999999-9999-4999-8999-999999999999')");const before=await fingerprint(prod);
  assert.match(await run(prod,await file(BUNDLE_PATH)),/GARDE : base non vide, installation refusée/);assert.deepEqual(await fingerprint(prod),before);
 }finally{await prod.close();}
});

test('retour arrière : empreinte d’origine restaurée, données conservées, cycle rejouable',async()=>{
 const db=await testProjectCopy();
 try{
  const bundle=await file(BUNDLE_PATH),rollback=await file(ROLLBACK_PATH);
  assert.match(await run(db,rollback),/GARDE : base non marquée « KOKI TEST »/,'refusé avant installation (ou sur la production)');
  const f0=await fingerprint(db);
  assert.equal(await run(db,bundle),'ok');const f1=await fingerprint(db);
  assert.equal(await run(db,rollback),'ok');const f2=await fingerprint(db);
  assert.deepEqual(f2,f0,'structure, droits et données identiques à l’état TEST vérifié');
  assert.equal(await run(db,rollback),'GARDE : base non marquée « KOKI TEST » (production ou poursuite non appliquée) : retour arrière refusé');
  assert.equal(await run(db,bundle),'ok');assert.deepEqual(structure(await fingerprint(db)),structure(f1),'réinstallation identique (identifiants et dates des villages régénérés)');
  // Données d'usage compatibles avec l'état d'origine, créées après installation : conservées à l'identique.
  await db.query(`insert into auth.users(id) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
   insert into public.koki_admin_members(user_id,role) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','superadmin');
   insert into public.koki_contents(type,titre,resume,texte,statut,publication) values('Actualités','TEST Actualité','TEST résumé','TEST texte','publié',now());
   insert into public.koki_transport_rates(category,base_fcfa,per_km_fcfa,active) values('Taxi',500,250,true);
   insert into storage.objects(bucket_id,name) values('koki-media','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/photo-test.jpg');
   insert into public.koki_records(kind,statut,owner_id,payload) values('professionnels','Actif','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','{"nom":"TEST Commerce","telephone":"+999000000003"}');`);
  const withData=await fingerprint(db);
  assert.equal(await run(db,rollback),'ok');const f3=await fingerprint(db);
  assert.deepEqual(structure(f3),structure(f0));
  for(const [k,v] of data(withData))if(f3.has(k))assert.equal(f3.get(k),v,k+' conservé');
  for(const t of ['auth.users','storage.objects','public.koki_records','public.koki_contents','public.koki_users','public.koki_admin_members','public.koki_transport_rates','public.koki_audit'])
   assert.ok(f3.get('donnees '+t)===withData.get('donnees '+t)&&!/^0:/.test(f3.get('donnees '+t)),t);
 }finally{await db.close();}
});

test('retour arrière : refusé sans rien modifier si des données créées après installation seraient perdues',async()=>{
 const db=await testProjectCopy();
 try{
  await db.query(await file(BUNDLE_PATH));const rollback=await file(ROLLBACK_PATH);
  const cases=[
   [`insert into auth.users(id) values('cccccccc-cccc-4ccc-8ccc-cccccccccccc');insert into koki_private.media_folders(user_id) values('cccccccc-cccc-4ccc-8ccc-cccccccccccc')`,/dossier\(s\) photo anonymes/],
   [`insert into auth.users(id) values('dddddddd-dddd-4ddd-8ddd-dddddddddddd');insert into public.koki_records(kind,statut,owner_id,payload) values('professionnels','Archivé','dddddddd-dddd-4ddd-8ddd-dddddddddddd','{"nom":"TEST Fiche archivée"}')`,/statuts introduits par la poursuite/],
   [`update public.koki_localites set nom='TEST Village modifié' where ordre=1`,/liste des villages a été modifiée/],
   [`insert into public.koki_localites(nom,ordre,source) values('TEST Nouveau quartier',11,'Administration')`,/liste des villages a été modifiée/],
  ];
  for(const [setup,expected] of cases){
   await db.query('begin');await db.query(setup);const before=await fingerprint(db);
   await db.query('savepoint essai');
   let message='ok';try{await db.query(rollback.replace(/^begin;$/m,'').replace(/^commit;$/m,''));}catch(e){message=e.message;await db.query('rollback to savepoint essai');}
   assert.match(message,expected);assert.deepEqual(await fingerprint(db),before,'aucune modification');await db.query('rollback');
  }
 }finally{await db.close();}
});

async function installedCopy(){
 const db=await testProjectCopy();
 await db.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='supabase_auth_admin') then create role supabase_auth_admin;end if;end $$;
  alter table auth.users add column if not exists email text, add column if not exists email_confirmed_at timestamptz, add column if not exists phone text;`);
 await db.query(await file(BUNDLE_PATH));return db;
}

test('crochet SMS TEST : format d’appel de Supabase Auth, numéros de test seuls, aucun accès public, retrait propre',async()=>{
 const raw=await testProjectCopy();
 try{await raw.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='supabase_auth_admin') then create role supabase_auth_admin;end if;end $$;`);
  assert.match(await run(raw,await file('supabase/preproduction/crochet-sms-test.sql')),/base non marquée « KOKI TEST »/,'refusé hors TEST');}finally{await raw.close();}
 const db=await installedCopy();
 try{
  const before=await fingerprint(db);
  assert.equal(await run(db,await file('supabase/preproduction/crochet-sms-test.sql')),'ok');
  assert.match(await run(db,await file('supabase/preproduction/crochet-sms-test.sql')),/déjà installé/);
  const call=async phone=>{await db.query('set role supabase_auth_admin');try{return (await db.query('select koki_test.send_sms($1::jsonb) r',[JSON.stringify({user:{id:'x',phone},sms:{otp:'123456'}})])).rows[0].r;}finally{await db.query('reset role');}};
  assert.deepEqual(await call('999000000001'),{});assert.deepEqual(await call('+999000000005'),{});
  for(const phone of ['221770000000','33612345678','999000000010','9990000000011',''])assert.equal((await call(phone)).error.http_code,400,phone);
  assert.deepEqual((await db.query('select phone,code from koki_test.sms_codes order by id')).rows,[{phone:'999000000001',code:'123456'},{phone:'999000000005',code:'123456'}]);
  for(const role of ['anon','authenticated']){
   await db.query('set role '+role);await assert.rejects(db.query('select * from koki_test.sms_codes'));await assert.rejects(db.query(`select koki_test.send_sms('{}'::jsonb)`));await db.query('reset role');
  }
  await db.query('set role supabase_auth_admin');await assert.rejects(db.query('select * from koki_test.sms_codes'),'le service Auth écrit sans relire les codes');await db.query('reset role');
  assert.equal(await run(db,await file('supabase/preproduction/crochet-sms-test-retrait.sql')),'ok');
  assert.deepEqual(await fingerprint(db),before,'retrait : empreinte d’avant crochet');
 }finally{await db.close();}
});

test('rôle administrateur TEST : attribué seulement à un compte vérifié (identifiant + e-mail confirmé)',async()=>{
 const tpl=await file('supabase/preproduction/attribuer-role-admin.sql');
 const fill=(id,email,role='superadmin')=>tpl.replace("'00000000-0000-0000-0000-000000000000';","'"+id+"';").replace("'adresse-a-remplacer@invalid';","'"+email+"';").replace("v_role text := 'superadmin';","v_role text := '"+role+"';");
 const raw=await testProjectCopy();
 try{assert.match(await run(raw,fill('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a@exemple.test')),/base non marquée « KOKI TEST »/);}finally{await raw.close();}
 const db=await installedCopy();
 try{
  await db.query(`insert into auth.users(id,email,email_confirmed_at) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Admin.Test@exemple.test',now()),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','attente@exemple.test',null);
   insert into auth.users(id,phone) values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','999000000001');`);
  const members=async()=>(await db.query('select user_id,role from public.koki_admin_members order by user_id')).rows;
  assert.match(await run(db,tpl),/remplacer l'identifiant/);
  assert.match(await run(db,fill('dddddddd-dddd-4ddd-8ddd-dddddddddddd','x@exemple.test')),/aucun compte avec cet identifiant/);
  assert.match(await run(db,fill('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','autre@exemple.test')),/ne correspond pas/);
  assert.match(await run(db,fill('cccccccc-cccc-4ccc-8ccc-cccccccccccc','999000000001')),/ne correspond pas/);
  assert.match(await run(db,fill('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','attente@exemple.test')),/non confirmé/);
  assert.match(await run(db,fill('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','admin.test@exemple.test','root')),/rôle inconnu/);
  assert.deepEqual(await members(),[]);
  assert.equal(await run(db,fill('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',' admin.test@exemple.test ')),'ok');
  assert.deepEqual(await members(),[{user_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',role:'superadmin'}]);
  assert.match(await run(db,fill('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','admin.test@exemple.test','analyst')),/déjà un rôle/);
  assert.deepEqual(await members(),[{user_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',role:'superadmin'}]);
 }finally{await db.close();}
});
