// Crochet « Before User Created » du projet Supabase TEST : répété UNIQUEMENT sur une copie locale jetable
// de l'état TEST après la poursuite (schema.sql + fondation + paquet phase 6, privilèges par défaut de Supabase).
import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
import {setupSupabaseStub} from './helpers/business-db.js';
import {BUNDLE_PATH} from '../scripts/prepare-test-continuation.mjs';
const file=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const INSTALL='supabase/preproduction/crochet-inscriptions-test.sql',REMOVE='supabase/preproduction/crochet-inscriptions-test-retrait.sql',SMS='supabase/preproduction/crochet-sms-test.sql',SMS_REMOVE='supabase/preproduction/crochet-sms-test-retrait.sql';
const ADMIN='admin.test@exemple.test';

async function testProjectCopy({installed=true}={}){
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1)),close:()=>pg.close()};
 await setupSupabaseStub(db);
 await db.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role;end if;
  if not exists(select 1 from pg_roles where rolname='supabase_auth_admin') then create role supabase_auth_admin;end if;end $$;
 alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
 alter default privileges in schema public grant all on functions to anon,authenticated,service_role;
 alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;`);
 await db.query(await file('supabase/schema.sql'));await db.query(await file('supabase/proposals/commerce-transport-foundation.sql'));
 if(installed){await db.query(await file(BUNDLE_PATH));await db.query('alter table auth.users add column if not exists email text, add column if not exists phone text');}
 return db;
}
const fingerprintSQL=await file('supabase/preproduction/empreinte.sql'),signupSQL=await file('supabase/preproduction/empreinte-inscriptions.sql');
const rows=async(db,sql)=>new Map((await db.query(sql)).rows.map(r=>[r.categorie+' '+r.objet,r.empreinte]));
const fingerprint=db=>rows(db,fingerprintSQL),signupFingerprint=db=>rows(db,signupSQL);
async function run(db,sql){try{await db.query(sql);return 'ok';}catch(e){await db.query('rollback').catch(()=>{});return e.message;}}
const withEmail=(sql,email)=>sql.replace("'adresse-a-remplacer@invalid';","'"+email+"';");
// Charge utile au format documenté par Supabase (user = forme de auth.users, avant insertion).
const event=(user)=>({metadata:{uuid:'8b34dcdd-9df1-4c10-850a-b3277c653040',time:'2026-10-11T18:00:00Z',name:'before-user-created',ip_address:'127.0.0.1'},
 user:{id:'ff7fc9ae-3b1b-4642-9241-64adb9848a03',aud:'authenticated',role:'',email:'',phone:'',app_metadata:{provider:'email',providers:['email']},user_metadata:{},identities:[],created_at:'0001-01-01T00:00:00Z',updated_at:'0001-01-01T00:00:00Z',is_anonymous:false,...user}});
const phoneUser=phone=>({phone,app_metadata:{provider:'phone',providers:['phone']}});
async function call(db,payload){await db.query('set role supabase_auth_admin');try{return (await db.query('select koki_test_signup.before_user_created($1::jsonb) r',[JSON.stringify(payload)])).rows[0].r;}finally{await db.query('reset role');}}

test('installation : refusée hors TEST, sans adresse administrateur valide, ou en double, sans rien modifier',async()=>{
 const raw=await testProjectCopy({installed:false});
 try{const before=await fingerprint(raw);assert.match(await run(raw,withEmail(await file(INSTALL),ADMIN)),/base non marquée « KOKI TEST »/);assert.deepEqual(await fingerprint(raw),before);}finally{await raw.close();}
 const db=await testProjectCopy();
 try{
  const tpl=await file(INSTALL),before=await signupFingerprint(db);
  assert.deepEqual([...before],[['etat koki_test_signup','absent']]);
  for(const email of [null,'pas-une-adresse','a@b','x@invalid'])assert.match(await run(db,email===null?tpl:withEmail(tpl,email)),/remplacer l'adresse e-mail/,String(email));
  assert.deepEqual(await signupFingerprint(db),before,'aucune modification');
  const f0=await fingerprint(db);
  assert.equal(await run(db,withEmail(tpl,' Admin.Test@Exemple.test ')),'ok');
  assert.deepEqual(await fingerprint(db),f0,'empreinte.sql inchangée : rien hors de koki_test_signup');
  const f1=await signupFingerprint(db);assert.equal(f1.get('etat koki_test_signup'),'present');
  assert.deepEqual((await db.query('select email from koki_test_signup.allowed_emails')).rows,[{email:ADMIN}],'adresse normalisée');
  assert.match(await run(db,withEmail(tpl,'autre@exemple.test')),/déjà installé/);assert.deepEqual(await signupFingerprint(db),f1);
 }finally{await db.close();}
});

test('décisions : numéros +999000000001 à 009 et adresse administrateur seuls, tout le reste refusé (403)',async()=>{
 const db=await testProjectCopy();
 try{
  await db.query(withEmail(await file(INSTALL),ADMIN));
  const allowed=[
   ['téléphone 001 sans +',phoneUser('999000000001')],['téléphone 009 avec +',phoneUser('+999000000009')],['téléphone 005',phoneUser('999000000005')],
   ['administrateur',{email:ADMIN}],['administrateur, casse et espaces',{email:'  ADMIN.Test@exemple.TEST '}],
   ['administrateur créé par le tableau de bord (téléphone vide)',{email:ADMIN,phone:'',app_metadata:{provider:'email',providers:['email']}}],
  ];
  for(const [label,user] of allowed)assert.deepEqual(await call(db,event(user)),{},label);
  const refused=[
   ['autre numéro sénégalais',phoneUser('221770000000')],['numéro français',phoneUser('+33612345678')],['999000000000',phoneUser('999000000000')],
   ['999000000010',phoneUser('999000000010')],['préfixe +999 hors plage',phoneUser('+999100000000')],['chiffre en trop',phoneUser('9990000000011')],
   ['caractères parasites',phoneUser('999000000001;')],['autre adresse',{email:'inconnu@exemple.test'}],['adresse proche',{email:'admin.test@exemple.test.evil'}],
   ['sous-adresse',{email:'admin.test+x@exemple.test'}],['téléphone et adresse ensemble',{email:ADMIN,phone:'999000000001'}],
   ['connexion anonyme',{is_anonymous:true,app_metadata:{provider:'anonymous',providers:['anonymous']}}],
   ['OAuth avec adresse autorisée',{email:ADMIN,app_metadata:{provider:'google',providers:['google']}}],['SSO',{email:ADMIN,app_metadata:{provider:'sso:abc',providers:['sso:abc']}}],
   ['fournisseur absent',{email:ADMIN,app_metadata:{}}],['ni adresse ni téléphone',{}],
  ];
  for(const [label,user] of refused){const r=await call(db,event(user));assert.equal(r.error?.http_code,403,label);assert.match(r.error.message,/réservée aux comptes de test/);}
  for(const payload of [{},{user:null},{user:'x'},{metadata:{}},{user:{is_anonymous:'oui',email:ADMIN,app_metadata:{provider:'email'}}}])assert.equal((await call(db,payload)).error?.http_code,403,JSON.stringify(payload));
 }finally{await db.close();}
});

test('droits : seul le service Auth appelle la fonction et lit la liste, sans pouvoir l’écrire ; aucun accès public',async()=>{
 const db=await testProjectCopy();
 try{
  await db.query(withEmail(await file(INSTALL),ADMIN));
  for(const role of ['anon','authenticated','service_role']){
   await db.query('set role '+role);
   await assert.rejects(db.query('select * from koki_test_signup.allowed_emails'),role);
   await assert.rejects(db.query(`select koki_test_signup.before_user_created('{}'::jsonb)`),role);
   await assert.rejects(db.query(`insert into koki_test_signup.allowed_emails(email,note) values('pirate@exemple.test','x')`),role);
   await db.query('reset role');
  }
  await db.query('set role supabase_auth_admin');
  try{
   assert.equal((await db.query('select count(*)::int n from koki_test_signup.allowed_emails')).rows[0].n,1);
   for(const sql of [`insert into koki_test_signup.allowed_emails(email,note) values('pirate@exemple.test','x')`,`update koki_test_signup.allowed_emails set email='pirate@exemple.test'`,`delete from koki_test_signup.allowed_emails`])
    await assert.rejects(db.query(sql),sql);
  }finally{await db.query('reset role');}
  const fn=(await db.query(`select p.prosecdef,p.proconfig from pg_proc p where p.oid='koki_test_signup.before_user_created(jsonb)'::regprocedure`)).rows[0];
  assert.equal(fn.prosecdef,false,'pas de security definer');assert.deepEqual(fn.proconfig,['search_path=""']);
 }finally{await db.close();}
});

test('comptes existants : non concernés (aucun déclencheur ni lecture de auth.users), connexions inchangées',async()=>{
 const db=await testProjectCopy();
 try{
  await db.query(`insert into auth.users(id,phone) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','221770000000');insert into auth.users(id,email) values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','ancien@exemple.test')`);
  const triggers=async()=>(await db.query(`select count(*)::int n from pg_trigger where tgrelid='auth.users'::regclass`)).rows[0].n,before=await triggers();
  const users=async()=>(await db.query('select id,email,phone from auth.users order by id')).rows,u0=await users();
  await db.query(withEmail(await file(INSTALL),ADMIN));
  assert.equal(await triggers(),before,'aucun déclencheur sur auth.users');assert.deepEqual(await users(),u0,'comptes existants intacts');
  const src=(await db.query(`select pg_get_functiondef('koki_test_signup.before_user_created(jsonb)'::regprocedure) d`)).rows[0].d;
  assert.doesNotMatch(src,/auth\.|koki_records|koki_users/,'la fonction ne lit que sa liste');
  // Supabase n'appelle ce crochet qu'avant une CRÉATION : une connexion (mot de passe, OTP d'un compte existant) ne l'appelle pas.
  await db.query(`update auth.users set email='ancien@exemple.test' where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'`);assert.deepEqual(await users(),u0);
 }finally{await db.close();}
});

test('cohabitation avec le crochet SMS : installation et retrait indépendants, dans les deux ordres',async()=>{
 for(const order of [['signup','sms'],['sms','signup']]){
  const db=await testProjectCopy();
  try{
   const f0=await fingerprint(db),s0=await signupFingerprint(db);
   for(const step of order)assert.equal(await run(db,step==='sms'?await file(SMS):withEmail(await file(INSTALL),ADMIN)),'ok',order+' '+step);
   assert.deepEqual(await call(db,event(phoneUser('999000000003'))),{});
   assert.equal(await run(db,await file(SMS_REMOVE)),'ok');assert.equal((await signupFingerprint(db)).get('etat koki_test_signup'),'present','retrait SMS sans effet sur les inscriptions');
   assert.equal(await run(db,await file(REMOVE)),'ok');
   assert.deepEqual(await fingerprint(db),f0);assert.deepEqual(await signupFingerprint(db),s0);
  }finally{await db.close();}
 }
});

test('retrait : refusé hors TEST, si absent ou si le schéma contient des objets inattendus ; sinon empreinte d’avant restaurée',async()=>{
 const raw=await testProjectCopy({installed:false});
 try{assert.match(await run(raw,await file(REMOVE)),/base non marquée « KOKI TEST »/);}finally{await raw.close();}
 const db=await testProjectCopy();
 try{
  const remove=await file(REMOVE);
  assert.match(await run(db,remove),/absent, rien à retirer/);
  const f0=await fingerprint(db),s0=await signupFingerprint(db);
  await db.query(withEmail(await file(INSTALL),ADMIN));
  await db.query('create table koki_test_signup.imprevu(id int)');const s1=await signupFingerprint(db);
  assert.match(await run(db,remove),/objets inattendus/);assert.deepEqual(await signupFingerprint(db),s1,'aucune modification');
  await db.query('drop table koki_test_signup.imprevu');
  assert.equal(await run(db,remove),'ok');
  assert.deepEqual(await fingerprint(db),f0);assert.deepEqual(await signupFingerprint(db),s0);
  assert.equal(await run(db,withEmail(await file(INSTALL),ADMIN)),'ok','réinstallable');
 }finally{await db.close();}
});

test('scripts : cible TEST unique, une transaction, aucun secret ni référence interdite dans les instructions',async()=>{
 for(const p of [INSTALL,REMOVE]){
  const text=await file(p);
  assert.match(text,/^-- KOKI CONNECT — .*PROJET SUPABASE TEST UNIQUEMENT : euvxtwmyoihnutifshay/);
  assert.equal((text.match(/^begin;$/gm)||[]).length,1);assert.equal((text.match(/^commit;$/gm)||[]).length,1);
  const body=text.split('\n').filter(l=>!l.startsWith('--')).join('\n');for(const ref of ['qsbmzzbiztfqysstepxm','paegdthtusbwxuarhacb'])assert.ok(!body.includes(ref));
  assert.doesNotMatch(text,/service_role_key|sb_secret_|eyJhbGciOi|password\s*=|BEGIN (RSA|PRIVATE)/i);
 }
 assert.doesNotMatch(await file('supabase/preproduction/empreinte-inscriptions.sql'),/\b(insert|update|delete|create|drop|alter|grant|revoke)\b/i,'empreinte en lecture seule');
});
