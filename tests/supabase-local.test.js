import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
import {setupSupabaseStub} from './helpers/business-db.js';import {localMigrations,migrationSources} from '../scripts/build-local-migrations.mjs';import {checkBackendTarget,LOCAL_MODE} from '../src/backend-guard.js';
const file=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
// Interfaces Auth réelles utilisées par seed.sql (colonnes de GoTrue, identités, rôle du service Auth).
async function supabaseLike(db){
 await setupSupabaseStub(db);
 await db.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='supabase_auth_admin') then create role supabase_auth_admin;end if;end $$;
 alter table auth.users add column instance_id uuid,add column aud varchar(255),add column role varchar(255),add column email varchar(255),add column encrypted_password varchar(255),add column email_confirmed_at timestamptz,add column phone text unique,add column phone_confirmed_at timestamptz,add column raw_app_meta_data jsonb,add column raw_user_meta_data jsonb,add column updated_at timestamptz,add column confirmation_token varchar(255),add column recovery_token varchar(255),add column email_change_token_new varchar(255),add column email_change varchar(255);
 create table auth.identities(id uuid primary key default gen_random_uuid(),provider_id text not null,user_id uuid not null references auth.users(id),identity_data jsonb not null,provider text not null,last_sign_in_at timestamptz,created_at timestamptz,updated_at timestamptz,unique(provider_id,provider));`);
}
async function install(db){for(const m of await localMigrations())await db.query(m.sql);}
const as=async(db,sql)=>(await db.query(sql)).rows;
test('migrations locales : générées depuis les sources, dans l’ordre validé, à jour',async()=>{
 const generated=await localMigrations();
 assert.deepEqual(generated.map(m=>m.name),[...generated.map(m=>m.name)].sort());
 assert.deepEqual(migrationSources.filter(m=>m.file).map(m=>m.file),['supabase/preproduction/fresh-project-check.sql','supabase/schema.sql','supabase/proposals/commerce-transport-foundation.sql','supabase/proposals/phase2-transactions.sql','supabase/proposals/merchant-profiles.sql','supabase/proposals/commerce-modernisation.sql']);
 for(const m of generated){assert.equal(await file('supabase/migrations/'+m.name),m.sql,m.name+' doit être régénéré (node scripts/build-local-migrations.mjs)');assert.doesNotMatch(m.sql,/^\s*(begin|commit);\s*$/m);}
});
test('Supabase local : migrations + données fictives, flux public et commandes métier',async()=>{
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};
 try{
  await supabaseLike(db);await install(db);await db.query(await file('supabase/seed.sql'));
  assert.deepEqual((await as(db,'select label from koki_private.test_environment')).map(r=>r.label),['KOKI TEST']);
  assert.equal((await as(db,'select count(*)::int n from auth.users'))[0].n,6);
  assert.ok((await as(db,"select phone from auth.users where phone is not null")).every(r=>r.phone.startsWith('999')));
  assert.equal((await as(db,'select count(*)::int n from auth.users where encrypted_password is not null'))[0].n,0);
  assert.deepEqual(await as(db,'select role from public.koki_admin_members'),[{role:'superadmin'}]);
  const records=await as(db,"select kind,statut,payload->>'nom' nom,owner_id::text owner from public.koki_records order by kind,payload->>'nom'");
  assert.ok(records.length>=7);assert.ok(records.every(r=>r.nom.startsWith('TEST')));
  assert.deepEqual(records.filter(r=>r.kind==='chauffeurs').map(r=>r.statut),['Disponible']);
  assert.deepEqual(records.filter(r=>r.kind==='professionnels').map(r=>r.statut).sort(),['Actif','Actif','En attente']);
  assert.equal(records.filter(r=>r.kind==='produits').length,3);assert.deepEqual(records.filter(r=>r.kind==='boutiques').map(r=>r.statut).sort(),['Actif','À valider']);
  assert.deepEqual((await as(db,'select category,base_fcfa,per_km_fcfa from public.koki_transport_rates where active order by base_fcfa')).map(r=>[r.category,r.base_fcfa,r.per_km_fcfa]),[['Moto',200,100],['Taxi',500,250],['Voiture',700,300],['Minicar',1000,400]]);
  // Le flux public (anonyme) ne contient que des contenus publiés : jamais le brouillon.
  await db.query('set role anon');const feed=(await as(db,'select public.koki_public_feed() f'))[0].f;await db.query('reset role');
  assert.equal(feed.version,1);const titres=feed.contenus.map(c=>c.titre);
  assert.ok(!titres.includes('TEST — Brouillon non visible'));
  for(const t of ['Actualités','Annonces','Événements','Sports & ASC','Opportunités','Publicités','Informations utiles'])assert.ok(feed.contenus.some(c=>c.type===t),t);
  await import('../src/numeros-contract.js');const numeros=feed.contenus.map(c=>globalThis.KokiNumeroContract.decode(c)).filter(Boolean);
  assert.deepEqual(numeros.map(n=>n.telephone).sort(),['+999 00 000 00 06','1515','17','18','800 00 20 20']);
  // Un client fictif peut demander un devis de course via la commande sécurisée (claims comme Supabase Auth).
  await db.query("select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false),set_config('request.jwt.claims','{\"sub\":\"22222222-2222-4222-8222-222222222222\",\"aal\":\"aal1\"}',false)");
  await db.query('set role authenticated');
  const nearby=(await as(db,`select public.koki_business('nearby_drivers','{"start":{"latitude":15.561,"longitude":-16.211},"category":"Taxi"}'::jsonb) r`))[0].r;
  assert.equal(nearby.length,1);assert.equal(nearby[0].name,'TEST Chauffeur');assert.ok(!JSON.stringify(nearby).includes('15.56'));
  await db.query('reset role');
  // Catalogue Commerces & Services fictif : boutique validée et ses offres ; éléments en attente invisibles.
  await db.query('set role anon');const catalog=(await as(db,"select public.koki_business('catalog','{}'::jsonb) c"))[0].c;await db.query('reset role');
  const names=catalog.map(x=>x.nom);for(const n of ['TEST Boutique Koki','TEST Riz 1 kg','TEST Sucre 1 kg','TEST Plomberie','TEST Pose de robinet'])assert.ok(names.includes(n),n);
  for(const n of ['TEST Annexe Ouarak','TEST Quincaillerie en attente'])assert.ok(!names.includes(n),n);
  assert.equal(catalog.find(x=>x.nom==='TEST Boutique Koki').village,'Coki');assert.equal(catalog.find(x=>x.nom==='TEST Sucre 1 kg').statut,'Épuisé');assert.equal(catalog.find(x=>x.nom==='TEST Riz 1 kg').ancien_prix,600);
  // Crochet SMS local : enregistre le code, n'envoie rien.
  await db.query('set role supabase_auth_admin');await db.query(`select koki_local.send_sms('{"user":{"phone":"221770000000"},"sms":{"otp":"654321"}}')`);await db.query('reset role');
  assert.deepEqual(await as(db,'select phone,code from koki_local.sms_codes'),[{phone:'221770000000',code:'654321'}]);
  await db.query('set role anon');await assert.rejects(db.query('select * from koki_local.sms_codes'));await db.query('reset role');
  // Garde « projet vide » : une base déjà installée (comme la production) refuse les migrations.
  await assert.rejects(db.query((await localMigrations())[0].sql),/non vide/);
 }finally{await pg.close();}
});
test('données fictives refusées sur une base non marquée TEST',async()=>{
 const pg=new PGlite(),db={query:(q,v)=>v?pg.query(q,v):pg.exec(q).then(x=>x.at(-1))};
 try{await supabaseLike(db);const m=await localMigrations();for(const x of m.slice(0,-1))await db.query(x.sql);
  await assert.rejects(db.query(await file('supabase/seed.sql')),/non marquée/);
  assert.equal((await as(db,'select count(*)::int n from auth.users'))[0].n,0);
 }finally{await pg.close();}
});
test('config.toml : local seulement, SMS en mode test sans fournisseur, MFA TOTP',async()=>{
 const c=await file('supabase/config.toml');
 assert.match(c,/^project_id = "koki-connect-local"$/m);assert.doesNotMatch(c,/supabase\.co(?!m)|qsbmzzbiztfqysstepxm|paegdthtusbwxuarhacb/);
 assert.doesNotMatch(c,/\[auth\.sms\.(twilio|twilio_verify|messagebird|textlocal|vonage)\]/);
 assert.doesNotMatch(c,/(auth_token|api_key|access_key|secret)\s*=/i);
 const otp=c.split('[auth.sms.test_otp]')[1].split('\n[')[0].match(/^\d+(?= =)/gm);assert.ok(otp.length>=4&&otp.every(n=>n.startsWith('999')));
 assert.match(c,/uri = "pg-functions:\/\/postgres\/koki_local\/send_sms"/);
 assert.match(c,/\[auth\.mfa\.totp\]\nenroll_enabled = true\nverify_enabled = true/);
 assert.match(c,/enable_anonymous_sign_ins = false/);assert.match(c,/major_version = 17/);
});
test('aucun secret dans les fichiers locaux, .env.supabase-local ignoré par Git',async()=>{
 for(const p of ['supabase/config.toml','supabase/seed.sql','.env.supabase-local.example']){const t=await file(p);assert.doesNotMatch(t,/sb_secret_|service_role|eyJhbGci|BEGIN (RSA|PRIVATE)/,p);}
 const ignore=await file('.gitignore');assert.match(ignore,/^\.env\.\*$/m);assert.match(ignore,/^!\.env\.supabase-local\.example$/m);
 const env=await file('.env.supabase-local.example');assert.match(env,/^VITE_SUPABASE_URL=http:\/\/127\.0\.0\.1:54321$/m);
});
test('garde-fou de cible : local uniquement en développement, jamais en version publiée',()=>{
 const key='sb_publishable_TEST';
 assert.deepEqual(checkBackendTarget({url:'http://127.0.0.1:54321',key,mode:LOCAL_MODE,dev:true}),{configured:true,local:true});
 assert.throws(()=>checkBackendTarget({url:'http://127.0.0.1:54321',key,mode:LOCAL_MODE,dev:false}),/réservé/);
 assert.throws(()=>checkBackendTarget({url:'https://qsbmzzbiztfqysstepxm.supabase.co',key,mode:LOCAL_MODE,dev:true}),/Aucune base distante/);
 assert.throws(()=>checkBackendTarget({url:'http://192.168.1.5:54321',key,mode:LOCAL_MODE,dev:true}),/Aucune base distante/);
 assert.throws(()=>checkBackendTarget({url:'http://127.0.0.1:54321',key,mode:'production',dev:false}),/https/);
 assert.throws(()=>checkBackendTarget({url:'http://127.0.0.1:54321',key,mode:'development',dev:true}),/https/);
 assert.throws(()=>checkBackendTarget({url:'http://127.0.0.1:54321',key:'sb_secret_x',mode:LOCAL_MODE,dev:true}),/publishable/);
 assert.throws(()=>checkBackendTarget({mode:LOCAL_MODE,dev:true}),/requis/);
 assert.deepEqual(checkBackendTarget({mode:'production',dev:false}),{configured:false,local:false});
 assert.equal(checkBackendTarget({url:'https://qsbmzzbiztfqysstepxm.supabase.co',key,mode:'production',dev:false}).production,true);
});
