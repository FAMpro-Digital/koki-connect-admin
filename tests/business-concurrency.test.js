import test from 'node:test';import assert from 'node:assert/strict';import EmbeddedPostgres from 'embedded-postgres';import {mkdtemp,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {createServer} from 'node:net';import {randomUUID as key} from 'node:crypto';import {setupBusinessDB,fixtureBusiness,actor,rpc,testActors,point,destination} from './helpers/business-db.js';
async function freePort(){const s=createServer();await new Promise(resolve=>s.listen(0,'127.0.0.1',resolve));const port=s.address().port;await new Promise(resolve=>s.close(resolve));return port;}
test('PostgreSQL natif : concurrence réelle entre connexions isolées', {timeout:120000},async t=>{
 const dir=await mkdtemp(join(tmpdir(),'koki-business-test-'));const port=await freePort();
 const postgres=new EmbeddedPostgres({databaseDir:join(dir,'db'),user:'koki_test',password:key(),port,persistent:false,postgresFlags:['-h','127.0.0.1','-k',dir,'-c','shared_buffers=16MB','-c','max_wal_size=64MB','-c','min_wal_size=32MB'],onLog:()=>{},onError:()=>{}});let index=0;
 try{await postgres.initialise();await postgres.start();
 async function scenario(fn){const name='business_'+index++;await postgres.createDatabase(name);const connections=[];const connect=async()=>{const c=postgres.getPgClient(name,'127.0.0.1');await c.connect();await c.query("set statement_timeout='10s';set lock_timeout='8s'");connections.push(c);return c;};
  try{const root=await connect();await setupBusinessDB(root);const f=await fixtureBusiness(root);await root.query('reset role');const a=await connect(),b=await connect();await actor(a,testActors.client);await actor(b,testActors.other);await fn({root,a,b,f,connect});}finally{await Promise.all(connections.map(c=>c.end()));await postgres.dropDatabase(name);}}
 const order=(f,quantity,request_id=key())=>({request_id,shop_id:f.shop.id,items:[{product_id:f.product.id,quantity}],mode:'retrait'});
 await t.test('deux commandes de deux unités : une seule acceptée, stock jamais négatif',()=>scenario(async({root,a,b,f})=>{
  const results=await Promise.allSettled([rpc(a,'create_order',order(f,2)),rpc(b,'create_order',order(f,2))]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.filter(r=>r.status==='rejected').length,1);
  assert.equal((await root.query('select payload from koki_records where id=$1',[f.product.id])).rows[0].payload.stock,0);assert.equal((await root.query("select count(*)::int n from koki_records where kind='commandes'")).rows[0].n,1);
 }));
 await t.test('deux commandes distinctes d’une unité : deux commandes et décompte exact',()=>scenario(async({root,a,b,f})=>{
  const results=await Promise.all([rpc(a,'create_order',order(f,1)),rpc(b,'create_order',order(f,1))]);assert.notEqual(results[0].id,results[1].id);assert.equal(results[0].payload.total+results[1].payload.total,1000);assert.equal((await root.query('select payload from koki_records where id=$1',[f.product.id])).rows[0].payload.stock,0);
 }));
 await t.test('renvoi simultané de la même clé : une commande, un seul décompte',()=>scenario(async({root,a,b,f})=>{
  await actor(b,testActors.client);const input=order(f,1);const results=await Promise.all([rpc(a,'create_order',input),rpc(b,'create_order',input)]);assert.equal(results[0].id,results[1].id);assert.equal((await root.query('select payload from koki_records where id=$1',[f.product.id])).rows[0].payload.stock,1);
 }));
 await t.test('deux passagers réservent le même chauffeur : une seule course active',()=>scenario(async({root,a,b,f})=>{
  const [qa,qb]=await Promise.all([rpc(a,'quote',{category:'Taxi',start:point,end:destination}),rpc(b,'quote',{category:'Taxi',start:point,end:destination})]);
  const results=await Promise.allSettled([rpc(a,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:qa.quote_id}),rpc(b,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:qb.quote_id})]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.filter(r=>r.status==='rejected').length,1);assert.equal((await root.query("select count(*)::int n from koki_records where kind='courses'")).rows[0].n,1);
 }));
 await t.test('un passager réserve deux chauffeurs différents : une seule course active',()=>scenario(async({root,a,b,f})=>{
  await actor(b,testActors.other);const second=await rpc(b,'register_driver',{request_id:key(),name:'TEST second chauffeur',phone:'+999000000004'});const vehicle=await rpc(b,'save_vehicle',{request_id:key(),parent_id:second.id,name:'TEST seconde voiture',category:'Taxi',registration:'TEST-002'});
  await actor(root,testActors.admin,'aal2');for(const item of [second,vehicle])await rpc(root,'admin_review',{request_id:key(),id:item.id,decision:'approve'});await actor(b,testActors.other);await rpc(b,'driver_position',{request_id:key(),position:point,available:true});await actor(b,testActors.client);
  const [qa,qb]=await Promise.all([rpc(a,'quote',{category:'Taxi',start:point,end:destination}),rpc(b,'quote',{category:'Taxi',start:point,end:destination})]);const results=await Promise.allSettled([rpc(a,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:qa.quote_id}),rpc(b,'reserve_ride',{request_id:key(),vehicle_id:vehicle.id,quote_id:qb.quote_id})]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.filter(r=>r.status==='rejected').length,1);
 }));
 await t.test('clé identique pour deux comptes : les demandes restent distinctes',()=>scenario(async({a,b,f})=>{
  const request_id=key();const results=await Promise.all([rpc(a,'create_order',order(f,1,request_id)),rpc(b,'create_order',order(f,1,request_id))]);assert.notEqual(results[0].id,results[1].id);assert.notEqual(results[0].client_id,results[1].client_id);
 }));
 await t.test('acceptation contre annulation : une transition et une révision unique',()=>scenario(async({a,b,f})=>{
  const quote=await rpc(a,'quote',{category:'Taxi',start:point,end:destination});const ride=await rpc(a,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:quote.quote_id});await actor(b,testActors.driver);
  const results=await Promise.allSettled([rpc(a,'transition',{request_id:key(),id:ride.id,next:'Annulée',revision:ride.revision}),rpc(b,'transition',{request_id:key(),id:ride.id,next:'Acceptée',revision:ride.revision})]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.filter(r=>r.status==='rejected').length,1);const stored=await rpc(a,'get',{id:ride.id});assert.equal(stored.revision,ride.revision+1);
 }));
 await t.test('annulation simultanée répétée : restitution de stock une seule fois',()=>scenario(async({root,a,b,f})=>{
  const created=await rpc(a,'create_order',order(f,2));await actor(b,testActors.client);const input={request_id:key(),id:created.id,next:'Annulée',revision:created.revision};await Promise.all([rpc(a,'transition',input),rpc(b,'transition',input)]);assert.equal((await root.query('select payload from koki_records where id=$1',[f.product.id])).rows[0].payload.stock,2);
 }));
 await t.test('édition catalogue concurrente à une commande : pas de blocage croisé',()=>scenario(async({a,b,f})=>{
  await actor(b,testActors.merchant);await Promise.all([rpc(a,'create_order',order(f,1)),rpc(b,'save_shop',{request_id:key(),id:f.shop.id,revision:f.shop.revision,parent_id:f.merchant.id,name:'TEST shop modifiée',address:'TEST Koki'})]);
 }));
 }finally{await postgres.stop();await rm(dir,{recursive:true,force:true});}
});
