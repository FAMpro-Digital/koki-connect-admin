import test from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {randomUUID as key} from 'node:crypto';import {setupBusinessDB,actor,rpc,fixtureBusiness,testActors,point,destination} from './helpers/business-db.js';
test('phase 2 : refus de privilèges, médias privés, expiration et conservation des prix',async t=>{
 const pg=new PGlite();const db={query:(sql,values)=>values?pg.query(sql,values):pg.exec(sql).then(results=>results.at(-1))};
 try{await setupBusinessDB(db);const f=await fixtureBusiness(db);
 await t.test('rôle prétendu, DML direct et appels privés refusés',async()=>{
  await actor(db,testActors.client);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({aal:'aal2',user_metadata:{role:'superadmin'},role:'superadmin'})]);
  await assert.rejects(rpc(db,'set_rate',{request_id:key(),category:'Taxi',base_fcfa:0,per_km_fcfa:0,active:true}),/MFA/);
  await assert.rejects(db.query("update koki_admin_members set role='superadmin' where user_id=$1",[testActors.client]),/permission denied/);
  await assert.rejects(db.query('select * from koki_private.business_keys'),/permission denied/);
  await assert.rejects(db.query("select koki_private.business_text('{}','name',1,10)"),/permission denied/);
  await assert.rejects(rpc(db,'register_driver',{request_id:key(),name:'TEST',phone:'+999000000004',statut:'Disponible'}),/Champs inconnus/);
  await actor(db,testActors.editor,'aal2');await assert.rejects(rpc(db,'get',{id:f.driver.id}),/Accès refusé/);assert.equal((await db.query('select * from koki_records')).rows.length,0);const stats=(await db.query('select koki_statistics() as stats')).rows[0].stats;assert.equal(stats['Chauffeurs'],null);assert.equal(stats['Commandes'],null);
  await actor(db,null,'aal1','anon');await assert.rejects(rpc(db,'register_driver',{request_id:key(),name:'TEST',phone:'+999000000004'}),/connecté/);
 });
 await t.test('propriétaire, profil professionnel et champs catalogue contrôlés',async()=>{
  await actor(db,testActors.client);await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:f.shop.id,name:'TEST',price:1,stock:3}),/Propriétaire/);
  await actor(db,testActors.provider);await assert.rejects(rpc(db,'save_shop',{request_id:key(),parent_id:f.provider.id,name:'TEST'}),/incompatible/);
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'save_service',{request_id:key(),parent_id:f.merchant.id,name:'TEST'}),/incompatible/);
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:f.shop.id,name:'TEST',price:1,stock:1.5}),/Stock invalide/);
  await assert.rejects(rpc(db,'save_product',{request_id:key(),parent_id:f.shop.id,name:'TEST',price:-1,stock:1}),/Prix catalogue/);
 });
 await t.test('photo de devis privée, partage participant et suppression protégée',async()=>{
  const path=testActors.client+'/'+key()+'.jpg';await actor(db,testActors.client);await db.query("insert into storage.objects(bucket_id,name) values('koki-media',$1)",[path]);
  const request=await rpc(db,'request_service',{request_id:key(),service_id:f.service.id,need:'TEST besoin de plomberie',address:'TEST adresse privée',date:'2099-10-08',image_path:path});
  assert.equal(request.payload.image_path,path);assert.equal((await db.query('delete from storage.objects where name=$1 returning name',[path])).rows.length,0);
  await actor(db,testActors.other);assert.equal((await db.query('select * from storage.objects')).rows.length,0);await assert.rejects(rpc(db,'request_service',{request_id:key(),service_id:f.service.id,need:'TEST besoin de plomberie',address:'TEST lieu',date:'2099-10-08',image_path:path}),/Média propriétaire/);
  await actor(db,testActors.provider);assert.equal((await db.query('select * from storage.objects')).rows.length,1);
  await actor(db,testActors.editor,'aal2');assert.equal((await db.query('select * from storage.objects')).rows.length,0);
  await actor(db,null,'aal1','anon');assert.equal((await db.query('select * from storage.objects')).rows.length,0);
 });
 await t.test('devis expiré refusé, tarif figé et absence de GPS public',async()=>{
  await actor(db,testActors.client);const near=await rpc(db,'nearby_drivers',{category:'Taxi',start:point});assert.equal(near.length,1);assert.ok(!JSON.stringify(near).includes('latitude'));await assert.rejects(rpc(db,'get',{id:f.driver.id}),/Accès refusé/);
  const expired=await rpc(db,'quote',{category:'Taxi',start:point,end:destination});await db.query('reset role');await db.query("update koki_private.ride_quotes set expires_at=now()-interval '1 second' where id=$1",[expired.quote_id]);await actor(db,testActors.client);
  await assert.rejects(rpc(db,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:expired.quote_id}),/Devis expiré/);
  const quote=await rpc(db,'quote',{category:'Taxi',start:point,end:destination});await actor(db,testActors.admin,'aal2');await rpc(db,'set_rate',{request_id:key(),category:'Taxi',base_fcfa:9000,per_km_fcfa:900,active:true});await actor(db,testActors.client);
  const ride=await rpc(db,'reserve_ride',{request_id:key(),vehicle_id:f.vehicle.id,quote_id:quote.quote_id});assert.equal(ride.payload.tarif,quote.fare_fcfa);await assert.rejects(rpc(db,'ride_contacts',{id:ride.id}),/acceptée active/);
  await actor(db,testActors.driver);const accepted=await rpc(db,'transition',{request_id:key(),id:ride.id,next:'Acceptée',revision:ride.revision});await actor(db,testActors.client);assert.equal((await rpc(db,'ride_contacts',{id:accepted.id})).phone,'+999000000001');
 });
 await t.test('prix figé, reprise de clé différente et stock périmé refusés',async()=>{
  await actor(db,testActors.client);const input={request_id:key(),shop_id:f.shop.id,items:[{product_id:f.product.id,quantity:1}],mode:'retrait'};const order=await rpc(db,'create_order',input);
  await assert.rejects(rpc(db,'create_order',{...input,items:[{product_id:f.product.id,quantity:2}]}),/Clé déjà utilisée/);
  await actor(db,testActors.merchant);await assert.rejects(rpc(db,'save_product',{request_id:key(),id:f.product.id,revision:f.product.revision,parent_id:f.shop.id,name:'TEST',price:9999,stock:2}),/Révision périmée/);
  const current=await rpc(db,'get',{id:f.product.id});await rpc(db,'save_product',{request_id:key(),id:current.id,revision:current.revision,parent_id:f.shop.id,name:'TEST nouveau prix',price:9999,stock:1});await actor(db,testActors.client);const saved=await rpc(db,'get',{id:order.id});assert.equal(saved.payload.total,500);assert.equal(saved.items[0].unit_price,500);
 });
 }finally{await pg.close();}
});
